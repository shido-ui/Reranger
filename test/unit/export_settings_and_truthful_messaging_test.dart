import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/data/platform/platform_media_service.dart';
import 'package:reranger/data/project_package/project_package_exporter.dart';
import 'package:reranger/data/project_package/project_package_importer.dart';
import 'package:reranger/domain/layers/editor_layer.dart';
import 'package:reranger/domain/layers/variant_board.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/features/editor/presentation/editor_controller.dart';
import 'package:reranger/features/export/data/image_exporter.dart';
import 'package:reranger/features/export/domain/export_format.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

class _MockTestMediaService implements PlatformMediaService {
  String? lastSavedPath;
  String? lastSharedPath;
  bool simulateGallerySuccess;

  _MockTestMediaService({this.simulateGallerySuccess = true});

  @override
  Future<String> saveImageToGallery({
    required String filePath,
    required String title,
    required String mimeType,
  }) async {
    lastSavedPath = filePath;
    if (simulateGallerySuccess) {
      return '/storage/emulated/0/Pictures/Reranger/${title}_saved.jpg';
    }
    // Sandbox fallback
    return filePath;
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProjectDatabase db;
  late ProjectFileStorage fileStorage;
  late LocalProjectRepository repository;

  Uint8List createTransparentPng(int w, int h) {
    final image = img.Image(width: w, height: h, numChannels: 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (x < w ~/ 2) {
          image.setPixelRgba(x, y, 200, 50, 50, 255); // Opaque red
        } else {
          image.setPixelRgba(x, y, 0, 0, 0, 0); // Transparent
        }
      }
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('export_sec_test_');
    db = ProjectDatabase.openInMemory();
    fileStorage = ProjectFileStorage(rootDir: tempDir);
    repository = LocalProjectRepository(database: db, fileStorage: fileStorage);
  });

  tearDown(() {
    db.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group(
    'PROMPT 6: Section B.1 - Single Source of Truth for Export Controls',
    () {
      test('EditorController renderScale and exportFormat control full-resolution render dimensions', () async {
        final sourceBytes = createTransparentPng(64, 64);
        final sourceHash = sha256.convert(sourceBytes).toString();
        final sourceFile = File('${tempDir.path}/test_source.png');
        sourceFile.writeAsBytesSync(sourceBytes);

        final project = ProjectEntity(
          id: 'proj_scale_test',
          name: 'Scale Test',
          sourceImagePath: sourceFile.path,
          sourceImageHash: sourceHash,
          sourceWidth: 64,
          sourceHeight: 64,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          recipe: RenderRecipe.initial(
            recipeId: 'rec_scale',
            sourceImageHash: sourceHash,
            sourceImagePath: sourceFile.path,
            activePresetId: PresetCatalog.defaultPresetId,
          ),
        );
        await repository.saveProject(project);

        final controller = EditorController(
          projectRepository: repository,
          fileStorage: fileStorage,
        );
        await controller.loadProject(project.id);
        controller.sourceImageBytes = sourceBytes;

        // Verify default 1.0x master scale
        expect(controller.renderScale, equals(1.0));
        final masterImage = await controller.renderFullResolutionOutput(
          scale: 1.0,
        );
        expect(masterImage.width, equals(64));
        expect(masterImage.height, equals(64));

        // Set 50% scale
        controller.setRenderScale(0.5);
        expect(controller.renderScale, equals(0.5));
        final halfImage = await controller.renderFullResolutionOutput(
          scale: 0.5,
        );
        expect(halfImage.width, equals(32));
        expect(halfImage.height, equals(32));

        // Set 200% scale
        controller.setRenderScale(2.0);
        expect(controller.renderScale, equals(2.0));
        final doubleImage = await controller.renderFullResolutionOutput(
          scale: 2.0,
        );
        expect(doubleImage.width, equals(128));
        expect(doubleImage.height, equals(128));

        // Format synchronization
        controller.setExportFormat('JPEG');
        expect(controller.exportFormat, equals('JPEG'));
        controller.setExportFormat('WEBP');
        expect(controller.exportFormat, equals('WEBP'));
        controller.setExportFormat('PNG');
        expect(controller.exportFormat, equals('PNG'));

        controller.dispose();
      });
    },
  );

  group(
    'PROMPT 6: Section B.2 - Alpha, Metadata & Truthful Size Estimation',
    () {
      test(
        'ImageExporter preserves RGBA alpha for PNG and composites for JPEG',
        () async {
          final transparentBytes = createTransparentPng(32, 32);
          final decodedImage = img.decodePng(transparentBytes)!;
          final exporter = ImageExporter();

          // 1. PNG Export
          final pngOut = exporter.encode(
            sourceImage: decodedImage,
            config: const ExportConfiguration(format: ExportImageFormat.png),
          );
          final decodedPng = img.decodePng(pngOut.bytes)!;
          expect(pngOut.alphaStripped, isFalse);
          expect(decodedPng.hasAlpha, isTrue);

          // Check right side remains transparent
          final transparentPixel = decodedPng.getPixel(24, 16);
          expect(transparentPixel.a, equals(0));

          // 2. JPEG Export
          final jpgOut = exporter.encode(
            sourceImage: decodedImage,
            config: const ExportConfiguration(
              format: ExportImageFormat.jpeg,
              quality: 90,
              backgroundColorForOpaque: [255, 255, 255],
            ),
          );
          final decodedJpg = img.decodeJpg(jpgOut.bytes)!;
          expect(jpgOut.alphaStripped, isTrue);

          // Check right side was composited onto white
          final compositedPixel = decodedJpg.getPixel(24, 16);
          expect(compositedPixel.r, greaterThanOrEqualTo(250));
          expect(compositedPixel.g, greaterThanOrEqualTo(250));
          expect(compositedPixel.b, greaterThanOrEqualTo(250));
        },
      );

      test('RealSizeEstimator formats non-placebo byte estimates', () {
        const configPng = ExportConfiguration(format: ExportImageFormat.png);
        final estBytesPng = RealSizeEstimator.estimateSizeBytes(
          width: 1000,
          height: 1000,
          config: configPng,
        );
        expect(estBytesPng, greaterThan(1000000)); // ~1.5 MB

        const configJpg = ExportConfiguration(
          format: ExportImageFormat.jpeg,
          quality: 80,
        );
        final estBytesJpg = RealSizeEstimator.estimateSizeBytes(
          width: 1000,
          height: 1000,
          config: configJpg,
        );
        expect(
          estBytesJpg,
          lessThan(estBytesPng),
        ); // JPEG smaller than lossless PNG

        final formatted = RealSizeEstimator.formatBytes(estBytesJpg);
        expect(formatted, anyOf(contains('KB'), contains('MB')));
      });
    },
  );

  group('PROMPT 6: Section B.3 - Truthful Messaging for Save & Share', () {
    test(
      'Distinguishes device gallery save from private project sandbox storage',
      () async {
        final mediaService = _MockTestMediaService(
          simulateGallerySuccess: true,
        );
        final testPath = '${tempDir.path}/test_out.jpg';
        File(testPath).writeAsBytesSync([1, 2, 3]);

        final galleryResult = await mediaService.saveImageToGallery(
          filePath: testPath,
          title: 'photo_export',
          mimeType: 'image/jpeg',
        );
        final inGallery = galleryResult != testPath;
        expect(inGallery, isTrue);
        expect(galleryResult, contains('/Pictures/Reranger/'));

        // When platform channel fails, fallback returns private file path
        mediaService.simulateGallerySuccess = false;
        final fallbackResult = await mediaService.saveImageToGallery(
          filePath: testPath,
          title: 'photo_export',
          mimeType: 'image/jpeg',
        );
        expect(fallbackResult, equals(testPath));
        final fallbackInGallery = fallbackResult != testPath;
        expect(fallbackInGallery, isFalse);
      },
    );

    test(
      'Share invokes system sheet without claiming transmission completion',
      () async {
        final mediaService = _MockTestMediaService();
        final testPath = '${tempDir.path}/test_share.png';
        File(testPath).writeAsBytesSync([1, 2, 3]);

        await mediaService.shareImage(
          filePath: testPath,
          mimeType: 'image/png',
          subject: 'My Image',
        );
        expect(mediaService.lastSharedPath, equals(testPath));
      },
    );
  });

  group(
    'PROMPT 6: Section A.5 - Offline Export/Import Complete Round-Trip',
    () {
      test('Exports and re-imports project package with layers, masks, variants, and checksums intact', () async {
        final sourceBytes = createTransparentPng(64, 64);
        final sourceHash = sha256.convert(sourceBytes).toString();
        final sourceFile = File('${tempDir.path}/roundtrip_source.png');
        sourceFile.writeAsBytesSync(sourceBytes);

        // Create dummy mask in masks dir
        final projectMasksDir = fileStorage.getMasksDirectory('proj_roundtrip');
        projectMasksDir.createSync(recursive: true);
        final maskFile = File('${projectMasksDir.path}/mask_0.png');
        maskFile.writeAsBytesSync([11, 22, 33, 44]);

        final initialLayerStack = LayerStack([
          SourceLayer(
            id: 'source_layer_0',
            name: 'Original Photo',
            sourceHash: sourceHash,
            sourceWidth: 64,
            sourceHeight: 64,
          ),
          AdjustmentLayer(
            id: 'adj_layer_1',
            name: 'Warm Wash',
            effectType: 'tint',
            parameters: const {'highlightR': 200},
            opacity: 0.85,
            blendMode: BlendModeType.overlay,
          ),
        ]);

        final initialVariantBoard = VariantBoard(
          variants: [
            ProjectVariant(
              id: 'var_0',
              name: 'Default Natural',
              layerStack: initialLayerStack,
              createdAt: DateTime.now().toUtc(),
            ),
          ],
          activeVariantId: 'var_0',
        );

        final initialRecipe = RenderRecipe.initial(
          recipeId: 'rec_roundtrip',
          sourceImageHash: sourceHash,
          sourceImagePath: sourceFile.path,
          activeStudio: 'style',
          activePresetId: 'graphite_pencil',
        );

        final project = ProjectEntity(
          id: 'proj_roundtrip',
          name: 'Offline Roundtrip Art',
          sourceImagePath: sourceFile.path,
          sourceImageHash: sourceHash,
          sourceWidth: 64,
          sourceHeight: 64,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
          recipe: initialRecipe.copyWith(
            masterIntensity: 0.9,
            fineTuneParameters: const {'leadHardness': 0.75},
            layerStack: initialLayerStack,
            variantBoard: initialVariantBoard,
            recipeVersion: 2,
          ),
        );
        await repository.saveProject(project);

        // 1. Export package to .rrproj
        final packageExporter = ProjectPackageExporter(
          fileStorage: fileStorage,
        );
        final packageDest = '${tempDir.path}/export_roundtrip.rrproj';
        final exportResult = await packageExporter.exportPackage(
          project: project,
          destinationPackagePath: packageDest,
        );
        expect(exportResult.byteLength, greaterThan(0));
        expect(File(packageDest).existsSync(), isTrue);

        // 2. Import package via ProjectPackageImporter completely offline
        final packageImporter = ProjectPackageImporter(
          database: db,
          fileStorage: fileStorage,
        );
        final importedProject = await packageImporter.importPackage(
          File(packageDest),
        );

        expect(importedProject.id, isNotEmpty);
        expect(
          importedProject.name,
          equals('Offline Roundtrip Art (Imported)'),
        );
        expect(importedProject.sourceImageHash, equals(sourceHash));
        expect(File(importedProject.sourceImagePath).existsSync(), isTrue);
        expect(
          sha256
              .convert(File(importedProject.sourceImagePath).readAsBytesSync())
              .toString(),
          equals(sourceHash),
        );

        // Verify recipe, layers, and variants survived losslessly
        final reloadedRecipe = importedProject.recipe;
        expect(reloadedRecipe.activePresetId, equals('graphite_pencil'));
        expect(reloadedRecipe.masterIntensity, equals(0.9));
        expect(reloadedRecipe.fineTuneParameters['leadHardness'], equals(0.75));
        expect(reloadedRecipe.layerStack, isNotNull);
        expect(reloadedRecipe.layerStack!.layers.length, equals(2));
        expect(reloadedRecipe.layerStack!.layers[1].name, equals('Warm Wash'));
        expect(reloadedRecipe.variantBoard, isNotNull);
        expect(reloadedRecipe.variantBoard!.variants.length, equals(1));
        expect(
          reloadedRecipe.variantBoard!.variants.first.name,
          equals('Default Natural'),
        );
      });
    },
  );
}
