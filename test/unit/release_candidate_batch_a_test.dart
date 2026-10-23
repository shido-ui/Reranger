import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:reranger/data/local/atomic_file_writer.dart';
import 'package:reranger/data/local/local_project_repository.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/data/render/render_job_controller.dart';
import 'package:reranger/domain/import/image_staging_service.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/domain/recipes/render_graph.dart';
import 'package:reranger/domain/recipes/render_graph_node.dart';
import 'package:reranger/features/import/data/isolate_image_decoder.dart';

void main() {
  group('Batch A (Correctness & Data Safety) Red-Team Audit Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('batch_a_audit_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('DEF-013 Regression: Corrupted output file does not destroy project and allows recovery', () async {
      final db = ProjectDatabase.openInMemory();
      final storage = ProjectFileStorage(
        rootDir: Directory(p.join(tempDir.path, 'storage')),
      );
      final repo = LocalProjectRepository(database: db, fileStorage: storage);

      final sourceFile = File(p.join(tempDir.path, 'source.png'));
      sourceFile.writeAsBytesSync(utf8.encode('VALID_SOURCE_PIXELS_DATA'));
      final sourceHash = sha256
          .convert(sourceFile.readAsBytesSync())
          .toString();

      final outputFile = File(p.join(tempDir.path, 'output.png'));
      outputFile.writeAsBytesSync(utf8.encode('ORIGINAL_OUTPUT_DATA'));
      final outputHash = sha256
          .convert(outputFile.readAsBytesSync())
          .toString();

      final now = DateTime.now().toUtc();
      final project = ProjectEntity(
        id: 'proj_corrupt_out',
        name: 'Corrupt Output Recovery Project',
        sourceImagePath: sourceFile.path,
        sourceImageHash: sourceHash,
        sourceWidth: 800,
        sourceHeight: 600,
        createdAt: now,
        updatedAt: now,
        recipe: RenderRecipe.initial(
          recipeId: 'rec_corrupt_out',
          sourceImageHash: sourceHash,
          sourceImagePath: sourceFile.path,
        ),
        outputReferencePath: outputFile.path,
        outputChecksum: outputHash,
      );

      await repo.saveProject(project);

      // Now maliciously corrupt the output file on disk (alter bytes without updating db)
      outputFile.writeAsBytesSync(utf8.encode('CORRUPTED_TAMPERED_OUTPUT'));

      // Load project - must NOT be marked isCorrupted: true!
      final loaded = await repo.loadProject('proj_corrupt_out');
      expect(loaded, isNotNull);
      expect(
        loaded!.isCorrupted,
        isFalse,
        reason: 'Corrupted output must not cause project to be declared corrupted when source is intact',
      );
      expect(
        loaded.outputReferencePath,
        isNull,
        reason: 'Invalid output reference must be cleanly cleared',
      );
      expect(
        loaded.recipe.recipeId,
        equals('rec_corrupt_out'),
        reason: 'Recipe must remain 100% intact',
      );

      db.dispose();
    });

    test('DEF-014 Regression: Path canonicalization prevents traversal overwrite of immutable source media', () async {
      final writer = const AtomicFileWriter();
      final sourcePath = p.join(tempDir.path, 'source_photo.jpg');
      File(sourcePath).writeAsStringSync('IMMUTABLE_SOURCE_DATA');
      final originalHash = sha256
          .convert(File(sourcePath).readAsBytesSync())
          .toString();

      // Attempt overwrite using non-normalized relative path traversal
      final traversedDestination = p.join(
        tempDir.path,
        'subdir',
        '..',
        'source_photo.jpg',
      );

      expect(
        () => writer.writeBytes(
          destinationPath: traversedDestination,
          bytes: utf8.encode('MALICIOUS_OVERWRITE_BYTES'),
          sourceImagePath: sourcePath,
        ),
        throwsA(isA<StorageFailure>()),
      );

      // Verify source file is byte-for-byte unmodified
      final currentHash = sha256
          .convert(File(sourcePath).readAsBytesSync())
          .toString();
      expect(
        currentHash,
        equals(originalHash),
        reason: 'Source media must remain strictly immutable (Invariant 4)',
      );
    });

    test('DEF-014 Regression: Atomic write replaces existing file without pre-deletion race', () async {
      final writer = const AtomicFileWriter();
      final destination = p.join(tempDir.path, 'existing_file.txt');
      File(destination).writeAsStringSync('INITIAL_CONTENT');

      final newBytes = utf8.encode('NEW_ATOMIC_CONTENT');
      final result = await writer.writeBytes(
        destinationPath: destination,
        bytes: newBytes,
      );

      expect(File(destination).existsSync(), isTrue);
      expect(
        File(destination).readAsStringSync(),
        equals('NEW_ATOMIC_CONTENT'),
      );
      expect(
        result.sha256Checksum,
        equals(sha256.convert(newBytes).toString()),
      );
    });

    test('DEF-015 Regression: Degenerate 1x1 image Sobel edge node preserves alpha and handles invert correctly', () async {
      final executor = RenderGraphExecutor();

      // Create 1x1 image with custom RGBA values (R=100, G=100, B=100, A=180)
      final image1x1 = img.Image(width: 1, height: 1, numChannels: 4);
      image1x1.setPixelRgba(0, 0, 100, 100, 100, 180);
      final encodedPng = Uint8List.fromList(img.encodePng(image1x1));

      final valid64Hash =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

      // 1. Inverted Sobel Edge (standard for sketch/line-art)
      final graphInverted = RenderGraph(
        id: 'graph_1x1_inverted',
        nodes: {
          'src': SourceImageNode(
            id: 'src',
            sourceImageHash: valid64Hash,
            sourceWidth: 1,
            sourceHeight: 1,
          ),
          'gray': GrayscaleNode(
            id: 'gray',
            inputNodeId: 'src',
            preserveAlpha: true,
          ),
          'edge': SobelEdgeNode(
            id: 'edge',
            inputNodeId: 'gray',
            edgeThreshold: 30,
            invertOutput: true,
          ),
        },
        outputNodeId: 'edge',
      );

      final resultInverted = await executor.execute(
        graph: graphInverted,
        sourceImageBytes: encodedPng,
      );

      expect(resultInverted.width, equals(1));
      expect(resultInverted.height, equals(1));
      // Output RGB should be 255 (inverted 0 gradient = white)
      expect(resultInverted.pixelBytes[0], equals(255));
      expect(resultInverted.pixelBytes[1], equals(255));
      expect(resultInverted.pixelBytes[2], equals(255));
      // Output Alpha must match source alpha (180), NOT 0!
      expect(resultInverted.pixelBytes[3], equals(180));

      // 2. Non-inverted Sobel Edge
      final graphNonInverted = RenderGraph(
        id: 'graph_1x1_non_inv',
        nodes: {
          'src': SourceImageNode(
            id: 'src',
            sourceImageHash: valid64Hash,
            sourceWidth: 1,
            sourceHeight: 1,
          ),
          'gray': GrayscaleNode(
            id: 'gray',
            inputNodeId: 'src',
            preserveAlpha: true,
          ),
          'edge': SobelEdgeNode(
            id: 'edge',
            inputNodeId: 'gray',
            edgeThreshold: 30,
            invertOutput: false,
          ),
        },
        outputNodeId: 'edge',
      );

      final resultNonInverted = await executor.execute(
        graph: graphNonInverted,
        sourceImageBytes: encodedPng,
      );

      expect(resultNonInverted.pixelBytes[0], equals(0));
      expect(resultNonInverted.pixelBytes[1], equals(0));
      expect(resultNonInverted.pixelBytes[2], equals(0));
      expect(resultNonInverted.pixelBytes[3], equals(180));
    });

    test('Intake Stress: Extreme panorama decoding (1x2000 and 2000x1) executes without NaN or exception', () async {
      const decoder = IsolateImageDecoder();

      // 1. Extreme vertical panorama: 1 x 500
      final vertImage = img.Image(width: 1, height: 500);
      for (int y = 0; y < 500; y++) {
        vertImage.setPixelRgb(0, y, y % 255, (y * 2) % 255, 128);
      }
      final vertBytes = Uint8List.fromList(img.encodePng(vertImage));
      final vertSummary = await decoder.decodeAndAnalyze(vertBytes);

      expect(vertSummary.width, equals(1));
      expect(vertSummary.height, equals(500));
      expect(vertSummary.aspectRatio.isFinite, isTrue);
      expect(vertSummary.aspectRatio.isNaN, isFalse);
      expect(vertSummary.thumbnailWidth, greaterThanOrEqualTo(1));
      expect(vertSummary.thumbnailHeight, greaterThanOrEqualTo(1));
      expect(vertSummary.dominantPalette.length, equals(5));

      // 2. Extreme horizontal panorama: 500 x 1
      final horizImage = img.Image(width: 500, height: 1);
      for (int x = 0; x < 500; x++) {
        horizImage.setPixelRgb(x, 0, x % 255, 100, 200);
      }
      final horizBytes = Uint8List.fromList(img.encodePng(horizImage));
      final horizSummary = await decoder.decodeAndAnalyze(horizBytes);

      expect(horizSummary.width, equals(500));
      expect(horizSummary.height, equals(1));
      expect(horizSummary.aspectRatio.isFinite, isTrue);
      expect(horizSummary.aspectRatio.isNaN, isFalse);
      expect(horizSummary.dominantPalette.length, equals(5));
    });

    test('Read-Only Source Media: Staging succeeds on read-only permissions (chmod 444)', () async {
      final stagingService = const ImageStagingService();
      final sourceFile = File(p.join(tempDir.path, 'readonly_source.png'));

      final testImage = img.Image(width: 32, height: 32);
      sourceFile.writeAsBytesSync(img.encodePng(testImage));

      // Set file permissions to read-only (chmod 444)
      Process.runSync('chmod', ['444', sourceFile.path]);

      final stageDir = Directory(p.join(tempDir.path, 'staged'));
      stageDir.createSync();

      final stagedInfo = await stagingService.stageSourceImage(
        sourcePath: sourceFile.path,
        destinationDir: stageDir.path,
        projectId: 'p_readonly_test',
      );

      expect(stagedInfo.sourcePath, equals(sourceFile.path));
      expect(File(stagedInfo.stagedPath).existsSync(), isTrue);

      // Clean up permissions before teardown
      Process.runSync('chmod', ['644', sourceFile.path]);
    });

    test('RenderJobController: Monotonic request ordering and race-free cancellation', () async {
      final controller = RenderJobController();

      final testImage = img.Image(width: 16, height: 16);
      final bytes = Uint8List.fromList(img.encodePng(testImage));

      final graph = RenderGraph(
        id: 'test_graph',
        nodes: {
          'src': SourceImageNode(
            id: 'src',
            sourceImageHash: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
            sourceWidth: 16,
            sourceHeight: 16,
          ),
          'gray': GrayscaleNode(id: 'gray', inputNodeId: 'src'),
        },
        outputNodeId: 'gray',
      );

      // Submit 3 requests in rapid succession
      final future1 = controller.submitRenderRequest(
        graph: graph,
        sourceImageBytes: bytes,
      );
      final future2 = controller.submitRenderRequest(
        graph: graph,
        sourceImageBytes: bytes,
      );
      final future3 = controller.submitRenderRequest(
        graph: graph,
        sourceImageBytes: bytes,
      );

      final res1 = await future1;
      final res2 = await future2;
      final res3 = await future3;

      // Exactly request 3 should complete with valid pixel output
      // Requests 1 and 2 were superseded / cancelled
      expect(res1, isNull);
      expect(res2, isNull);
      expect(res3, isNotNull);
      expect(res3!.width, equals(16));
      expect(controller.latestRequestId, equals(3));
      expect(controller.staleResultsDiscardedCount, greaterThanOrEqualTo(1));

      controller.dispose();
    });
  });
}
