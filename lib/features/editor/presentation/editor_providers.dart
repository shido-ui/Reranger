import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../import/presentation/import_providers.dart';
import 'editor_controller.dart';

/// Riverpod family provider supplying an [EditorController] instance per project ID.
final editorControllerProvider = Provider.autoDispose
    .family<EditorController, String>((ref, projectId) {
      final repository = ref.watch(projectRepositoryProvider);
      final fileStorage = ref.watch(projectFileStorageProvider);

      final controller = EditorController(
        projectRepository: repository,
        fileStorage: fileStorage,
      );

      ref.onDispose(() => controller.dispose());
      controller.loadProject(projectId);
      return controller;
    });
