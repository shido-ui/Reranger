import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../../data/local/local_project_repository.dart';
import '../../../data/local/project_file_storage.dart';
import '../../../data/render/render_job_controller.dart';
import '../../../domain/layers/editor_layer.dart';
import '../../../domain/presets/preset_definition.dart';
import '../../../domain/project/project_entity.dart';
import '../../../domain/recipes/adversarial_stealth_node.dart';
import '../../../domain/recipes/render_graph.dart';
import '../../../domain/recipes/render_graph_node.dart';
import '../../presets/data/preset_catalog.dart';
import 'layer_history_controller.dart';

/// Presentation state for SCR-04 Editor Viewport.
class EditorController extends ChangeNotifier {
  final LocalProjectRepository projectRepository;
  final ProjectFileStorage fileStorage;
  final RenderJobController renderJobController;

  String? projectId;
  ProjectEntity? project;
  Uint8List? sourceImageBytes;
  Uint8List? previewPngBytes;
  PresetDefinition? activePreset;
  Map<String, double> parameterValues = {};
  LayerHistoryController? layerHistoryController;

  String? selectedCategory;
  double effectStrength = 1.0;
  bool isSplitComparisonActive = false;
  double splitPosition = 0.5;
  double renderScale = 1.0;
  String exportFormat = 'PNG';

  // Adversarial Stealth Studio state (Post-Prompt 23 PO Addendum)
  bool isStealthEnabled = false;
  double stealthStrength = 0.5;
  bool stealthApplyFrequency = true;
  bool isPreviewingStealth = false;

  bool isComparing = false;
  bool isLoading = true;
  bool isSaving = false;
  bool isSaved = false;
  String? errorMessage;
  RenderJobState renderState = const RenderJobIdle();

  StreamSubscription<RenderJobState>? _jobSubscription;
  int _renderRequestCount = 0;

  EditorController({
    required this.projectRepository,
    required this.fileStorage,
    RenderJobController? jobController,
  }) : renderJobController = jobController ?? RenderJobController() {
    _jobSubscription = renderJobController.stateStream.listen((state) {
      renderState = state;
      notifyListeners();
    });
  }

  /// Initial load of the project, checking crash recovery journals and staging initial render.
  Future<void> loadProject(String id) async {
    projectId = id;
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      var loaded = await projectRepository.loadProject(id);
      if (loaded == null) {
        errorMessage = 'Project not found: $id';
        isLoading = false;
        notifyListeners();
        return;
      }

      if (loaded.isCorrupted) {
        errorMessage = 'Project source file is corrupted or missing';
        isLoading = false;
        notifyListeners();
        return;
      }

      // Check crash dirty journal for unsaved recovery
      final dirtyRecipe = await projectRepository.checkDirtyJournal();
      if (dirtyRecipe != null &&
          dirtyRecipe.recipeId == loaded.recipe.recipeId) {
        loaded = loaded.copyWith(recipe: dirtyRecipe, isDirty: true);
      }

      project = loaded;
      layerHistoryController = LayerHistoryController(
        sourceLayer: SourceLayer(
          id: 'source_layer_0',
          name: 'Original Photo',
          sourceHash: loaded.sourceImageHash,
          sourceWidth: loaded.sourceWidth,
          sourceHeight: loaded.sourceHeight,
        ),
      );

      // Load source image bytes
      final sourceFile = File(loaded.sourceImagePath);
      if (!sourceFile.existsSync()) {
        errorMessage = 'Source image not found: ${loaded.sourceImagePath}';
        isLoading = false;
        notifyListeners();
        return;
      }
      sourceImageBytes = await sourceFile.readAsBytes();

      // Resolve active preset
      final presetId = loaded.recipe.activePresetId;
      activePreset = PresetCatalog.getById(presetId) ?? PresetCatalog.all.first;

      // Restore parameters
      if (loaded.recipe.fineTuneParameters.isNotEmpty) {
        parameterValues = Map<String, double>.from(
          loaded.recipe.fineTuneParameters,
        );
      } else {
        parameterValues = activePreset!.resolveParameters(null);
      }

      // If output reference already exists and file is intact, load it directly
      if (loaded.outputReferencePath != null) {
        final outFile = File(loaded.outputReferencePath!);
        if (outFile.existsSync()) {
          previewPngBytes = await outFile.readAsBytes();
          isSaved = true;
        }
      }

      isLoading = false;
      notifyListeners();

      // If no preview loaded, render initial preset
      if (previewPngBytes == null) {
        await _dispatchRender();
      }
    } catch (e) {
      errorMessage = 'Error loading project: $e';
      isLoading = false;
      notifyListeners();
    }
  }

  /// Selects a new style preset from the catalog and dispatches rendering.
  Future<void> selectPreset(PresetDefinition preset) async {
    if (activePreset?.id == preset.id && previewPngBytes != null) return;

    activePreset = preset;
    parameterValues = preset.resolveParameters(null);
    isSaved = false;
    notifyListeners();

    _recordDirtyJournal();
    await _dispatchRender();
  }

  /// Adjusts a slider parameter and dispatches a render with latest-request-wins semantics.
  Future<void> updateParameter(String paramId, double value) async {
    final param = activePreset?.parameters.firstWhere(
      (p) => p.id == paramId,
      orElse: () => activePreset!.parameters.first,
    );
    final clamped = param != null ? param.clamp(value) : value;

    parameterValues[paramId] = clamped;
    isSaved = false;
    notifyListeners();

    _recordDirtyJournal();
    await _dispatchRender();
  }

  /// Toggles before/after comparison mode.
  void setComparing(bool comparing) {
    if (isComparing == comparing) return;
    isComparing = comparing;
    notifyListeners();
  }

  /// Cancels any currently executing render job.
  void cancelRender() {
    renderJobController.cancelCurrentJob();
  }

  /// Sets category filter for the preset carousel.
  void setSelectedCategory(String? category) {
    if (selectedCategory == category) return;
    selectedCategory = category;
    notifyListeners();
  }

  /// Returns presets filtered by the active category or all 48 if unselected.
  List<PresetDefinition> get visiblePresets {
    if (selectedCategory == null) {
      return PresetCatalog.all;
    }
    return PresetCatalog.getByCategory(selectedCategory!);
  }

  /// Resets a specific parameter to its default value.
  Future<void> resetParameter(String paramId) async {
    final param = activePreset?.parameters.firstWhere(
      (p) => p.id == paramId,
      orElse: () => activePreset!.parameters.first,
    );
    if (param == null) return;
    await updateParameter(paramId, param.defaultValue);
  }

  /// Resets all recipe parameters of active preset to defaults.
  Future<void> resetAllParameters() async {
    if (activePreset == null) return;
    parameterValues = activePreset!.resolveParameters(null);
    effectStrength = 1.0;
    isSaved = false;
    notifyListeners();
    _recordDirtyJournal();
    await _dispatchRender();
  }

  /// Updates overall effect strength (0.0 to 1.0) modulating the primary parameter.
  Future<void> setEffectStrength(double strength) async {
    effectStrength = strength.clamp(0.0, 1.0);
    final primaryParam = activePreset?.parameters.isNotEmpty == true
        ? activePreset!.parameters.first
        : null;
    if (primaryParam != null) {
      final value =
          primaryParam.min +
          effectStrength * (primaryParam.max - primaryParam.min);
      await updateParameter(primaryParam.id, value);
    } else {
      notifyListeners();
    }
  }

  /// Configures split-screen before/after comparison curtain.
  void setSplitComparison({bool? active, double? position}) {
    if (active != null) isSplitComparisonActive = active;
    if (position != null) splitPosition = position.clamp(0.0, 1.0);
    layerHistoryController?.setSplitComparison(
      isSplitComparisonActive,
      position: splitPosition,
    );
    notifyListeners();
  }

  /// Sets output render scale.
  void setRenderScale(double scale) {
    if ((renderScale - scale).abs() < 1e-4) return;
    renderScale = scale;
    notifyListeners();
  }

  /// Sets export file format.
  void setExportFormat(String format) {
    if (exportFormat == format) return;
    exportFormat = format;
    notifyListeners();
  }

  /// Toggles whether adversarial stealth perturbations are enabled.
  Future<void> setStealthEnabled(bool enabled) async {
    if (isStealthEnabled == enabled) return;
    isStealthEnabled = enabled;
    notifyListeners();
    await _dispatchRender();
  }

  /// Sets adversarial stealth perturbation magnitude (epsilon).
  Future<void> setStealthStrength(double val) async {
    stealthStrength = val.clamp(0.0, 1.0);
    notifyListeners();
    if (isStealthEnabled || isPreviewingStealth) {
      await _dispatchRender();
    }
  }

  /// Toggles frequency domain perturbation mode.
  Future<void> setStealthApplyFrequency(bool val) async {
    stealthApplyFrequency = val;
    notifyListeners();
    if (isStealthEnabled || isPreviewingStealth) {
      await _dispatchRender();
    }
  }

  /// Toggles preview of adversarial stealth effect in viewport.
  Future<void> toggleStealthPreview() async {
    isPreviewingStealth = !isPreviewingStealth;
    notifyListeners();
    await _dispatchRender();
  }

  /// Builds the active [RenderGraph], only injecting [AdversarialStealthNode] if explicitly toggled in Stealth Studio.
  RenderGraph buildActiveGraph() {
    var graph = activePreset!.buildGraph(
      project!.sourceImageHash,
      project!.sourceWidth,
      project!.sourceHeight,
      parameterValues,
    );

    // Strict Isolation: AdversarialStealthNode cannot be injected unless explicitly toggled
    if (isStealthEnabled || isPreviewingStealth) {
      final stealthNode = AdversarialStealthNode(
        id: 'stealth_output_node',
        inputNodeId: graph.outputNodeId,
        strength: stealthStrength,
        applyFrequencyPerturbation: stealthApplyFrequency,
      );
      final updatedNodes = Map<String, RenderGraphNode>.from(graph.nodes);
      updatedNodes[stealthNode.id] = stealthNode;
      graph = RenderGraph(
        id: '${graph.id}_stealth',
        nodes: updatedNodes,
        outputNodeId: stealthNode.id,
      );
    }
    return graph;
  }

  /// Submits render job to the deterministic render pipeline.
  Future<void> _dispatchRender() async {
    if (activePreset == null || sourceImageBytes == null || project == null) {
      return;
    }

    final currentRequestId = ++_renderRequestCount;
    final graph = buildActiveGraph();

    // Viewport resolution optimization (1536px cap for responsive frame pacing)
    const maxPreviewDim = 1536.0;
    final maxSourceDim = math
        .max(project!.sourceWidth, project!.sourceHeight)
        .toDouble();
    final previewScale = maxSourceDim > maxPreviewDim
        ? (maxPreviewDim / maxSourceDim)
        : 1.0;

    final result = await renderJobController.submitRenderRequest(
      graph: graph,
      sourceImageBytes: sourceImageBytes!,
      renderScale: previewScale,
    );

    // Only update preview if this was the latest request and not cancelled
    if (result != null && currentRequestId == _renderRequestCount) {
      final imgBuffer = img.Image.fromBytes(
        width: result.width,
        height: result.height,
        bytes: result.pixelBytes.buffer,
        numChannels: 4,
      );
      // Fast uncompressed PNG (level 0) for instant preview serialization (eliminates CPU compression lag)
      previewPngBytes = Uint8List.fromList(img.encodePng(imgBuffer, level: 0));
      notifyListeners();
    }
  }

  /// Records active recipe into SQLite crash journal for force-stop recovery.
  void _recordDirtyJournal() {
    if (project == null || activePreset == null) return;
    final recipe = project!.recipe.copyWith(
      activeStudio: 'style',
      activePresetId: activePreset!.id,
      fineTuneParameters: parameterValues,
      updatedAt: DateTime.now().toUtc(),
    );
    projectRepository.writeDirtyJournal(project!.id, recipe);
  }

  /// Atomically saves the rendered output to local storage and updates project metadata.
  Future<bool> saveProject() async {
    if (previewPngBytes == null || project == null || activePreset == null) {
      return false;
    }

    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      Uint8List exportBytes = previewPngBytes!;
      // If preview was rendered at downscaled resolution, perform full 1.0 scale render for lossless archival
      if (project!.sourceWidth > 1536 || project!.sourceHeight > 1536) {
        final fullGraph = buildActiveGraph();
        final fullResult = await renderJobController.executor.execute(
          graph: fullGraph,
          sourceImageBytes: sourceImageBytes!,
          renderScale: 1.0,
        );
        final fullImg = img.Image.fromBytes(
          width: fullResult.width,
          height: fullResult.height,
          bytes: fullResult.pixelBytes.buffer,
          numChannels: 4,
        );
        exportBytes = Uint8List.fromList(img.encodePng(fullImg));
      }

      final fileName = 'export_${DateTime.now().millisecondsSinceEpoch}.png';
      final writeResult = await fileStorage.saveOutput(
        projectId: project!.id,
        fileName: fileName,
        bytes: exportBytes,
        sourceImagePath: project!.sourceImagePath,
      );

      final updatedRecipe = project!.recipe.copyWith(
        activeStudio: 'style',
        activePresetId: activePreset!.id,
        fineTuneParameters: parameterValues,
        updatedAt: DateTime.now().toUtc(),
      );

      final updatedProject = project!.copyWith(
        outputReferencePath: writeResult.path,
        outputChecksum: writeResult.sha256Checksum,
        recipe: updatedRecipe,
        isDirty: false,
        updatedAt: DateTime.now().toUtc(),
      );

      await projectRepository.saveProject(updatedProject);
      project = updatedProject;
      isSaved = true;
      isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Failed to save project: $e';
      isSaving = false;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _jobSubscription?.cancel();
    renderJobController.dispose();
    super.dispose();
  }
}
