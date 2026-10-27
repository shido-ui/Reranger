import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../../data/local/local_project_repository.dart';
import '../../../data/local/project_file_storage.dart';
import '../../../data/render/render_job_controller.dart';
import '../../../domain/layers/editor_layer.dart';
import '../../../domain/layers/history_command.dart';
import '../../../domain/presets/preset_definition.dart';
import '../../../domain/project/project_entity.dart';
import '../../../domain/recipes/render_graph.dart';
import '../../../domain/recipes/render_graph_node.dart';
import '../../../domain/recipes/adversarial_stealth_node.dart';
import '../../export/data/image_exporter.dart';
import '../../export/domain/export_format.dart';
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
  String activeStudio = 'style';

  bool get canUndo => layerHistoryController?.state.canUndo ?? false;
  bool get canRedo => layerHistoryController?.state.canRedo ?? false;
  void undo() => layerHistoryController?.undo();
  void redo() => layerHistoryController?.redo();

  void setActiveStudio(String studio) {
    if (activeStudio == studio) return;
    activeStudio = studio;
    isSaved = false;
    notifyListeners();
    _recordDirtyJournal();
  }

  String? selectedCategory;
  double effectStrength = 1.0;
  bool isSplitComparisonActive = false;
  double splitPosition = 0.5;
  double renderScale = 1.0;
  String exportFormat = 'PNG';
  double realism = 0.0;

  bool isComparing = false;
  bool isLoading = true;
  bool isSaving = false;
  bool isSaved = false;
  String? errorMessage;
  String? presetMigrationNotice;
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

      // Check crash dirty journal for project-scoped unsaved recovery (Prompt 1.C.2)
      final dirtyRecipe = await projectRepository.checkDirtyJournal(loaded.id);
      if (dirtyRecipe != null &&
          dirtyRecipe.recipeId == loaded.recipe.recipeId &&
          dirtyRecipe.sourceImageHash == loaded.sourceImageHash) {
        loaded = loaded.copyWith(recipe: dirtyRecipe, isDirty: true);
      }

      project = loaded;
      activeStudio = loaded.recipe.activeStudio;
      final initialLayers = loaded.recipe.layerStack?.layers.skip(1).toList();
      final initialVariantBoard = loaded.recipe.variantBoard;

      layerHistoryController?.removeListener(_onLayerStackChanged);
      layerHistoryController = LayerHistoryController(
        sourceLayer: SourceLayer(
          id: 'source_layer_0',
          name: 'Original Photo',
          sourceHash: loaded.sourceImageHash,
          sourceWidth: loaded.sourceWidth,
          sourceHeight: loaded.sourceHeight,
        ),
        initialLayers: initialLayers,
        initialVariantBoard: initialVariantBoard,
      );
      layerHistoryController!.addListener(_onLayerStackChanged);

      // Load source image bytes
      final sourceFile = File(loaded.sourceImagePath);
      if (!sourceFile.existsSync()) {
        errorMessage = 'Source image not found: ${loaded.sourceImagePath}';
        isLoading = false;
        notifyListeners();
        return;
      }
      sourceImageBytes = await sourceFile.readAsBytes();

      // Resolve active preset with honest, recoverable fallback (Prompt 1.A.2 & 1.A.3)
      final presetId = loaded.recipe.activePresetId;
      final resolvedPreset = PresetCatalog.getById(presetId);
      if (resolvedPreset != null) {
        activePreset = resolvedPreset;
      } else {
        // Recoverable, user-visible migration path for unrecognized preset IDs
        activePreset = PresetCatalog.defaultPreset;
        presetMigrationNotice =
            'The style preset "$presetId" is no longer available and was migrated to "${activePreset!.displayName}".';
        loaded = loaded.copyWith(
          recipe: loaded.recipe.copyWith(
            activePresetId: activePreset!.id,
            updatedAt: DateTime.now().toUtc(),
          ),
          isDirty: true,
        );
        project = loaded;
      }

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
  Future<void> updateParameter(
    String paramId,
    double value, {
    bool recordHistory = true,
  }) async {
    final param = activePreset?.parameters.firstWhere(
      (p) => p.id == paramId,
      orElse: () => activePreset!.parameters.first,
    );
    final clamped = param != null ? param.clamp(value) : value;
    final oldValue = parameterValues[paramId] ?? (param?.defaultValue ?? 0.0);

    if ((oldValue - clamped).abs() < 1e-5) return;

    parameterValues[paramId] = clamped;
    isSaved = false;
    notifyListeners();

    if (recordHistory && layerHistoryController != null) {
      final cmd = SetParameterCommand(
        parameterId: paramId,
        oldValue: oldValue,
        newValue: clamped,
        onApply: (id, val) {
          parameterValues[id] = val;
          isSaved = false;
          notifyListeners();
          _recordDirtyJournal();
          _dispatchRender();
        },
      );
      layerHistoryController!.executeCommand(cmd);
    }

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

  /// Returns presets filtered by the active category or all presets if unselected,
  /// always featuring the Original pass-through preset at the forefront.
  List<PresetDefinition> get visiblePresets {
    if (selectedCategory == null) {
      return [PresetCatalog.original, ...PresetCatalog.all];
    }
    if (selectedCategory == 'Studio') {
      return [PresetCatalog.original, ...PresetCatalog.studioPresets];
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
    renderScale = scale.clamp(0.1, 4.0);
    notifyListeners();
    _dispatchRender();
  }

  /// Sets export file format.
  void setExportFormat(String format) {
    if (exportFormat == format) return;
    exportFormat = format;
    notifyListeners();
  }

  /// Sets Realism level (0.0 to 1.0) controlling Stealth Engine V2 in Export pipeline.
  void setRealism(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (realism == clamped) return;
    realism = clamped;
    notifyListeners();
    _recordDirtyJournal();
    _dispatchRender();
  }

  void _onLayerStackChanged() {
    _recordDirtyJournal();
    _dispatchRender();
  }

  /// Builds the active [RenderGraph], composing non-destructive layers on top of base presets (Prompt B).
  /// Wires Robust Stealth Engine V2 (ARMOR UAP DCT perturbation & sensor noise) when realism > 0.0.
  RenderGraph buildActiveGraph() {
    var graph = activePreset!.buildGraph(
      project!.sourceImageHash,
      project!.sourceWidth,
      project!.sourceHeight,
      parameterValues,
    );

    // Composite non-destructive layer stack if configured (Prompt B)
    if (layerHistoryController != null &&
        layerHistoryController!.state.layerStack.layers.length > 1) {
      graph = layerHistoryController!.state.layerStack.toRenderGraph(
        baseGraph: graph,
      );
    }

    // Include Stealth Engine nodes in the active graph when realism > 0.0
    if (realism > 0.0) {
      final outNodeId = graph.outputNodeId;
      final armorNode = ARMORAttackNode(
        id: 'armor_live_${graph.id}',
        inputNodeId: outNodeId,
        strength: realism,
        maxLInf: 16.0,
        useEot: true,
        bilateralSanitization: true,
      );
      final sensorNode = SensorNoiseNode(
        id: 'sensor_live_${graph.id}',
        inputNodeId: armorNode.id,
        noiseIntensity: (realism * 0.4).clamp(0.0, 1.0),
        chromaticAberration: (realism * 0.3).clamp(0.0, 1.0),
      );
      final updatedNodes = Map<String, RenderGraphNode>.from(graph.nodes);
      updatedNodes[armorNode.id] = armorNode;
      updatedNodes[sensorNode.id] = sensorNode;
      graph = RenderGraph(
        id: graph.id,
        version: graph.version,
        nodes: updatedNodes,
        outputNodeId: sensorNode.id,
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

  /// Constructs the canonical [RenderRecipe] describing the exact current edit state (Prompt 1.B.2).
  RenderRecipe buildCurrentRecipe() {
    return project!.recipe.copyWith(
      activeStudio: activeStudio,
      activePresetId: activePreset!.id,
      fineTuneParameters: Map<String, double>.from(parameterValues),
      layerStack: layerHistoryController?.state.layerStack,
      variantBoard: layerHistoryController?.state.variantBoard,
      recipeVersion: 2,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Records active recipe into SQLite crash journal for force-stop recovery.
  void _recordDirtyJournal() {
    if (project == null || activePreset == null) return;
    final recipe = buildCurrentRecipe();
    projectRepository.writeDirtyJournal(project!.id, recipe);
  }

  /// Renders the active graph at full source resolution (multiplied by [scale]).
  /// Guaranteed not to use downscaled preview viewport buffers (DEF-025).
  /// When [realism] > 0.0, wires Robust Stealth Engine V2 (ARMOR UAP, Sensor Noise, and Metadata Annihilation).
  Future<img.Image> renderFullResolutionOutput({double scale = 1.0}) async {
    if (sourceImageBytes == null || project == null || activePreset == null) {
      throw StateError(
        'Cannot render output: Project or preset is not initialized.',
      );
    }

    var fullGraph = buildActiveGraph();

    // Ensure Stealth Engine nodes are wired if Realism > 0.0
    final hasStealth = fullGraph.nodes.values.any(
      (n) => n is ARMORAttackNode || n is SensorNoiseNode,
    );
    if (realism > 0.0 && !hasStealth) {
      final outNodeId = fullGraph.outputNodeId;
      final armorNode = ARMORAttackNode(
        id: 'armor_export_${DateTime.now().microsecondsSinceEpoch}',
        inputNodeId: outNodeId,
        strength: realism,
        maxLInf: 16.0,
        useEot: true,
        bilateralSanitization: true,
      );
      final sensorNode = SensorNoiseNode(
        id: 'sensor_export_${DateTime.now().microsecondsSinceEpoch}',
        inputNodeId: armorNode.id,
        noiseIntensity: (realism * 0.4).clamp(0.0, 1.0),
        chromaticAberration: (realism * 0.3).clamp(0.0, 1.0),
      );
      final updatedNodes = Map<String, RenderGraphNode>.from(fullGraph.nodes);
      updatedNodes[armorNode.id] = armorNode;
      updatedNodes[sensorNode.id] = sensorNode;
      fullGraph = RenderGraph(
        id: fullGraph.id,
        version: fullGraph.version,
        nodes: updatedNodes,
        outputNodeId: sensorNode.id,
      );
    }

    // Apply metadata annihilation before rendering
    final workingSourceBytes = realism > 0.0
        ? MetadataAnnihilator.stripMetadata(sourceImageBytes!)
        : sourceImageBytes!;

    final fullResult = await renderJobController.executor.execute(
      graph: fullGraph,
      sourceImageBytes: workingSourceBytes,
      renderScale: scale.clamp(0.1, 4.0),
    );

    return img.Image.fromBytes(
      width: fullResult.width,
      height: fullResult.height,
      bytes: fullResult.pixelBytes.buffer,
      numChannels: 4,
    );
  }

  /// Atomically saves the rendered output to local storage and updates project metadata.
  Future<bool> saveProject() async {
    if (previewPngBytes == null || project == null || activePreset == null) {
      return false;
    }
    if (isSaving) return false; // Prevent concurrent duplicate saves / spam

    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      // 1. Run entire graph (including Stealth nodes) at final export resolution (scale: 1.0)
      final fullImg = await renderFullResolutionOutput(scale: 1.0);

      // 2. Encode through ImageExporter with ExportConfiguration containing realism
      final exporter = ImageExporter();
      final config = ExportConfiguration(
        format: ExportImageFormat.png,
        quality: 100,
        scale: 1.0,
        stripGpsMetadata: true,
        realism: realism,
      );

      final encoded = exporter.encode(sourceImage: fullImg, config: config);

      // Verify stripMetadata is executed on final exported bytes
      final exportBytes = MetadataAnnihilator.stripMetadata(encoded.bytes);

      final fileName = 'export_${DateTime.now().millisecondsSinceEpoch}.png';
      final writeResult = await fileStorage.saveOutput(
        projectId: project!.id,
        fileName: fileName,
        bytes: exportBytes,
        sourceImagePath: project!.sourceImagePath,
      );

      final updatedRecipe = buildCurrentRecipe();

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
    layerHistoryController?.removeListener(_onLayerStackChanged);
    _jobSubscription?.cancel();
    renderJobController.dispose();
    super.dispose();
  }
}
