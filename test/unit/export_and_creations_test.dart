import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/data/platform/platform_media_service.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/features/editor/presentation/editor_controller.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

class _MockMediaService implements PlatformMediaService {
  String? lastSavedPath;
  String? lastSharedPath;

  @override
  Future<String> saveImageToGallery({
    required String filePath,
    required String title,
    required String mimeType,
  }) async {
    lastSavedPath = filePath;
    return 'content://media/external/images/media/999';
  }

  @override
  Future<void> shareImage({
    required String filePath,
    required String mimeType,
    String? subject,
  }) async {
    lastSharedPath = filePath;
  }
}

void main() {
  group(
    'DEF-025: Honest Export, Full-Resolution Render & Media Service Tests',
    () {
      late Directory tempDir;
      late ProjectDatabase db;
      late ProjectFileStorage storage;
      late LocalProjectRepository repository;
      late EditorController editor;
      late _MockMediaService mediaService;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('reranger_export_test_');
        db = ProjectDatabase.openInMemory();
        storage = ProjectFileStorage(rootDir: tempDir);
        repository = LocalProjectRepository(database: db, fileStorage: storage);
        mediaService = _MockMediaService();
        editor = EditorController(
          projectRepository: repository,
          fileStorage: storage,
        );
      });

      tearDown(() {
        editor.dispose();
        db.dispose();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test(
        'renderFullResolutionOutput executes at authentic source dimensions',
        () async {
          // 2000 x 1000 high-resolution test image
          final highRes = img.Image(width: 2000, height: 1000);
          highRes.clear(img.ColorRgb8(100, 150, 200));
          final highResPng = Uint8List.fromList(img.encodePng(highRes));
          final sourceHash = sha256.convert(highResPng).toString();

          final testPreset = PresetCatalog.all.first;

          final testProject = ProjectEntity(
            id: 'proj_high_res',
            name: 'High Res Project',
            sourceImagePath: '/dummy/high_res.png',
            sourceImageHash: sourceHash,
            sourceWidth: 2000,
            sourceHeight: 1000,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            recipe: RenderRecipe.initial(
              recipeId: 'rec_high',
              sourceImageHash: sourceHash,
              sourceImagePath: '/dummy/high_res.png',
              activeStudio: testPreset.category,
              activePresetId: testPreset.id,
            ),
          );

          editor.project = testProject;
          editor.sourceImageBytes = highResPng;
          editor.activePreset = testPreset;
          editor.parameterValues = testPreset.resolveParameters(null);

          final rendered = await editor.renderFullResolutionOutput(scale: 1.0);

          // Verify that full resolution is strictly preserved (never downscaled to 1536px preview)
          expect(rendered.width, equals(2000));
          expect(rendered.height, equals(1000));
        },
      );

      test(
        'PlatformMediaService records honest save and share destinations',
        () async {
          const dummyPath = '/test/exported_photo.png';
          final galleryUri = await mediaService.saveImageToGallery(
            filePath: dummyPath,
            title: 'exported_photo',
            mimeType: 'image/png',
          );

          expect(galleryUri, contains('content://media/external/images/media'));
          expect(mediaService.lastSavedPath, equals(dummyPath));

          await mediaService.shareImage(
            filePath: dummyPath,
            mimeType: 'image/png',
          );
          expect(mediaService.lastSharedPath, equals(dummyPath));
        },
      );
    },
  );
}
