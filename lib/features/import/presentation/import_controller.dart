import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../data/local/project_file_storage.dart';
import '../../../domain/import/image_file_validator.dart';
import '../../../domain/import/image_picker_service.dart';
import '../../../domain/import/image_staging_service.dart';
import '../../../domain/project/project_entity.dart';
import '../../../domain/project/project_repository.dart';
import '../../presets/data/preset_catalog.dart';
import '../data/isolate_image_decoder.dart';

/// Concrete, honest processing stages for image analysis.
/// No fabricated continuous percentages (Invariant 7).
enum ImportStage {
  validatingFormat(
    'Validating Media Format',
    'Inspecting binary header and checking format compatibility.',
  ),
  stagingSandboxCopy(
    'Staging Working Copy',
    'Creating a non-destructive sandbox copy. Original media is untouched.',
  ),
  decodingAndOrientation(
    'Correcting EXIF Orientation',
    'Baking orientation transform and verifying color alpha channels.',
  ),
  extractingPalette(
    'Extracting Dominant Palette',
    'Analyzing 5-point harmonic color palette for Recolor Studio.',
  ),
  savingProject(
    'Finalizing Project',
    'Creating persistent local project record.',
  );

  final String title;
  final String description;
  const ImportStage(this.title, this.description);
}

/// State of the image intake & analysis workflow.
sealed class ImportState {
  const ImportState();
}

class ImportInitial extends ImportState {
  const ImportInitial();
}

class ImportPicking extends ImportState {
  const ImportPicking();
}

class ImportInProgress extends ImportState {
  final ImportStage stage;
  final String? activeProjectId;

  const ImportInProgress({required this.stage, this.activeProjectId});

  @override
  String toString() => 'ImportInProgress(stage: ${stage.title})';
}

class ImportSuccess extends ImportState {
  final ProjectEntity project;
  final DecodedImageSummary imageSummary;

  const ImportSuccess({required this.project, required this.imageSummary});

  @override
  String toString() => 'ImportSuccess(projectId: ${project.id})';
}

class ImportCancelled extends ImportState {
  const ImportCancelled();
}

class ImportFailureState extends ImportState {
  final String errorMessage;
  final bool canRetry;
  final String? sourcePath;

  const ImportFailureState({
    required this.errorMessage,
    this.canRetry = true,
    this.sourcePath,
  });

  @override
  String toString() => 'ImportFailureState(error: $errorMessage)';
}

/// Controller coordinating real photo import, validation, staging, decoding, and project creation.
/// Strictly enforces:
/// - Single-flight concurrency: rapid double taps create $\le 1$ active intake job.
/// - Invariant 4: Source image media is never modified.
/// - Invariant 5: 100% offline-first execution.
/// - Invariant 7: Honest indeterminate stages without fake progress numbers.
class ImportController extends ChangeNotifier {
  final ImageFileValidator validator;
  final ImageStagingService stagingService;
  final IsolateImageDecoder decoder;
  final ProjectRepository projectRepository;
  final ProjectFileStorage fileStorage;
  final ImagePickerService? pickerService;

  ImportState _state = const ImportInitial();
  ImportState get state => _state;

  bool _isCancelled = false;
  bool _isExecuting = false;
  bool _isDisposed = false;
  int _activeJobToken = 0;

  /// Guard to prevent concurrent executions / double taps
  bool get isExecuting => _isExecuting;

  String? _lastSourcePath;

  ImportController({
    required this.projectRepository,
    required this.fileStorage,
    this.validator = const ImageFileValidator(),
    this.stagingService = const ImageStagingService(),
    this.decoder = const IsolateImageDecoder(),
    this.pickerService,
    ImportState initialState = const ImportInitial(),
  }) : _state = initialState;

  void _setState(ImportState newState) {
    if (_isDisposed) return;
    _state = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _activeJobToken++;
    super.dispose();
  }

  /// Cancels any active import and cleans up transient sandbox files (DEF-023).
  void cancel() {
    _activeJobToken++;
    _isCancelled = true;
    _isExecuting = false;
    _setState(const ImportCancelled());
  }

  /// Resets the controller back to initial state for a fresh intake session.
  void reset() {
    _activeJobToken++;
    _isCancelled = false;
    _isExecuting = false;
    _lastSourcePath = null;
    _setState(const ImportInitial());
  }

  /// Retries the last failed import job.
  Future<void> retry() async {
    if (_lastSourcePath != null) {
      await importFromPath(_lastSourcePath!);
    } else if (pickerService != null) {
      await pickAndImport();
    }
  }

  /// Launches the platform photo picker and imports the selected image.
  Future<void> pickAndImport() async {
    if (_isExecuting) return; // Prevent double tap
    if (pickerService == null) {
      _setState(
        const ImportFailureState(
          errorMessage: 'Platform photo picker service not available.',
          canRetry: false,
        ),
      );
      return;
    }

    final token = ++_activeJobToken;
    _isExecuting = true;
    _isCancelled = false;
    _setState(const ImportPicking());

    try {
      final pickResult = await pickerService!.pickImage();
      if (token != _activeJobToken || _isDisposed) return;

      switch (pickResult) {
        case ImagePickSuccess(:final path):
          _isExecuting = false; // reset before calling importFromPath
          await importFromPath(path);
          return;
        case ImagePickCancelled():
          _isExecuting = false;
          _setState(const ImportCancelled());
          return;
        case ImagePickPermissionDenied(:final message):
          _isExecuting = false;
          _setState(
            ImportFailureState(
              errorMessage: message ?? 'Photo library access was not granted.',
              canRetry: true,
            ),
          );
          return;
        case ImagePickFailure(:final error):
          _isExecuting = false;
          _setState(ImportFailureState(errorMessage: error, canRetry: true));
          return;
      }
    } catch (e) {
      if (token != _activeJobToken || _isDisposed) return;
      _isExecuting = false;
      _setState(
        ImportFailureState(
          errorMessage: 'Unexpected error opening photo picker: $e',
          canRetry: true,
        ),
      );
    }
  }

  /// Imports an image directly from [sourcePath].
  Future<void> importFromPath(String sourcePath) async {
    // 1. Concurrency Guard: Drop duplicate taps immediately
    if (_isExecuting) return;
    final token = ++_activeJobToken;
    _isExecuting = true;
    _isCancelled = false;
    _lastSourcePath = sourcePath;

    final projectId = 'proj_${DateTime.now().millisecondsSinceEpoch}';
    String? stagedFilePath;

    try {
      // Stage 1: Validation
      _setState(
        ImportInProgress(
          stage: ImportStage.validatingFormat,
          activeProjectId: projectId,
        ),
      );

      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        throw FileNotFoundValidationFailure(sourcePath);
      }
      await validator.validateFile(sourceFile);

      if (token != _activeJobToken || _isCancelled) {
        _cleanupStagedFiles(projectId);
        if (!_isDisposed && token == _activeJobToken) {
          _setState(const ImportCancelled());
        }
        return;
      }

      // Stage 2: Sandbox Staging
      _setState(
        ImportInProgress(
          stage: ImportStage.stagingSandboxCopy,
          activeProjectId: projectId,
        ),
      );

      fileStorage.ensureProjectDirectories(projectId);
      final sourceDir = fileStorage.getSourceDirectory(projectId);

      final stagedInfo = await stagingService.stageSourceImage(
        sourcePath: sourcePath,
        destinationDir: sourceDir.path,
        projectId: projectId,
      );
      stagedFilePath = stagedInfo.stagedPath;

      if (token != _activeJobToken || _isCancelled) {
        _cleanupStagedFiles(projectId);
        if (!_isDisposed && token == _activeJobToken) {
          _setState(const ImportCancelled());
        }
        return;
      }

      // Stage 3: Decoding, EXIF Baking & Alpha Verification
      _setState(
        ImportInProgress(
          stage: ImportStage.decodingAndOrientation,
          activeProjectId: projectId,
        ),
      );

      final stagedBytes = await File(stagedFilePath).readAsBytes();
      final summary = await decoder.decodeAndAnalyze(stagedBytes);

      if (token != _activeJobToken || _isCancelled) {
        _cleanupStagedFiles(projectId);
        if (!_isDisposed && token == _activeJobToken) {
          _setState(const ImportCancelled());
        }
        return;
      }

      // Stage 4: Palette & Scene Map
      _setState(
        ImportInProgress(
          stage: ImportStage.extractingPalette,
          activeProjectId: projectId,
        ),
      );

      // Save downscaled preview thumbnail into project sandbox
      final thumbFile = File(
        p.join(
          fileStorage.getProjectDirectory(projectId).path,
          'thumbnail.png',
        ),
      );
      await thumbFile.writeAsBytes(summary.thumbnailBytes, flush: true);

      if (token != _activeJobToken || _isCancelled) {
        _cleanupStagedFiles(projectId);
        if (!_isDisposed && token == _activeJobToken) {
          _setState(const ImportCancelled());
        }
        return;
      }

      // Stage 5: Project Creation & Persistence
      _setState(
        ImportInProgress(
          stage: ImportStage.savingProject,
          activeProjectId: projectId,
        ),
      );

      final recipe = RenderRecipe.initial(
        recipeId: 'rec_$projectId',
        sourceImageHash: stagedInfo.sha256Checksum,
        sourceImagePath: stagedFilePath,
        activeStudio: 'style',
        activePresetId: PresetCatalog.defaultPresetId,
      );

      final rawName = p.basenameWithoutExtension(sourcePath);
      final uniqueName = projectRepository.resolveUniqueProjectName(rawName);

      final project = ProjectEntity(
        id: projectId,
        name: uniqueName,
        sourceImagePath: stagedFilePath,
        sourceImageHash: stagedInfo.sha256Checksum,
        sourceWidth: summary.width,
        sourceHeight: summary.height,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        recipe: recipe,
      );

      if (token != _activeJobToken || _isCancelled) {
        _cleanupStagedFiles(projectId);
        return;
      }

      await projectRepository.saveProject(project);

      if (token != _activeJobToken || _isDisposed) {
        return;
      }

      _setState(ImportSuccess(project: project, imageSummary: summary));
    } on ImageValidationFailure catch (e) {
      if (token != _activeJobToken || _isDisposed) return;
      _cleanupStagedFiles(projectId);
      _setState(
        ImportFailureState(
          errorMessage: e.message,
          canRetry: true,
          sourcePath: sourcePath,
        ),
      );
    } on ImageDecodingFailure catch (e) {
      if (token != _activeJobToken || _isDisposed) return;
      _cleanupStagedFiles(projectId);
      _setState(
        ImportFailureState(
          errorMessage: e.message,
          canRetry: true,
          sourcePath: sourcePath,
        ),
      );
    } on ProjectFailure catch (e) {
      if (token != _activeJobToken || _isDisposed) return;
      _cleanupStagedFiles(projectId);
      _setState(
        ImportFailureState(
          errorMessage: e.message,
          canRetry: true,
          sourcePath: sourcePath,
        ),
      );
    } catch (e) {
      if (token != _activeJobToken || _isDisposed) return;
      _cleanupStagedFiles(projectId);
      _setState(
        ImportFailureState(
          errorMessage: 'An unexpected error occurred during import: $e',
          canRetry: true,
          sourcePath: sourcePath,
        ),
      );
    } finally {
      if (token == _activeJobToken) {
        _isExecuting = false;
      }
    }
  }

  void _cleanupStagedFiles(String projectId) {
    try {
      final projectDir = fileStorage.getProjectDirectory(projectId);
      if (projectDir.existsSync()) {
        projectDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }
}
