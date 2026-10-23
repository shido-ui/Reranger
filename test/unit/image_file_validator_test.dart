import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/data/local/atomic_file_writer.dart';
import 'package:reranger/domain/import/image_file_validator.dart';
import 'package:reranger/domain/import/image_staging_service.dart';
import 'package:reranger/domain/project/project_entity.dart';

class MockLowStorageCapacityChecker implements StorageCapacityChecker {
  final int availableBytes;
  MockLowStorageCapacityChecker(this.availableBytes);

  @override
  Future<int> getAvailableDiskBytes(String directoryPath) async =>
      availableBytes;
}

void main() {
  group('ImageFileValidator Tests (Batch A)', () {
    const validator = ImageFileValidator();
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('image_validator_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('validates valid JPEG magic bytes', () async {
      final jpegBytes = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x10,
        0x4A,
        0x46,
        0x49,
        0x46,
        0x00,
        0x01,
      ]);
      final file = File('${tempDir.path}/test.jpg')
        ..writeAsBytesSync(jpegBytes);

      final format = await validator.validateFile(file);
      expect(format, equals(SupportedImageFormat.jpeg));
    });

    test('validates valid PNG magic bytes', () async {
      final pngBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
      ]);
      final file = File('${tempDir.path}/test.png')..writeAsBytesSync(pngBytes);

      final format = await validator.validateFile(file);
      expect(format, equals(SupportedImageFormat.png));
    });

    test('validates valid WebP magic bytes (RIFF....WEBP)', () async {
      final webpBytes = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x20, 0x00, 0x00, 0x00, // Size
        0x57, 0x45, 0x42, 0x50, // WEBP
      ]);
      final file = File('${tempDir.path}/test.webp')
        ..writeAsBytesSync(webpBytes);

      final format = await validator.validateFile(file);
      expect(format, equals(SupportedImageFormat.webp));
    });

    test('rejects unsupported GIF format with explicit failure', () async {
      final gifBytes = Uint8List.fromList([
        0x47,
        0x49,
        0x46,
        0x38,
        0x39,
        0x61,
        0x01,
        0x00,
        0x01,
        0x00,
        0x80,
        0x00,
      ]);
      final file = File('${tempDir.path}/test.gif')..writeAsBytesSync(gifBytes);

      expect(
        () => validator.validateFile(file),
        throwsA(
          isA<UnsupportedFormatValidationFailure>().having(
            (e) => e.detectedFormat,
            'detectedFormat',
            'GIF',
          ),
        ),
      );
    });

    test('rejects unsupported BMP format with explicit failure', () async {
      final bmpBytes = Uint8List.fromList([
        0x42,
        0x4D,
        0x36,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x36,
        0x00,
      ]);
      final file = File('${tempDir.path}/test.bmp')..writeAsBytesSync(bmpBytes);

      expect(
        () => validator.validateFile(file),
        throwsA(
          isA<UnsupportedFormatValidationFailure>().having(
            (e) => e.detectedFormat,
            'detectedFormat',
            'BMP',
          ),
        ),
      );
    });

    test('rejects empty file (0 bytes)', () async {
      final file = File('${tempDir.path}/empty.jpg')..writeAsBytesSync([]);

      expect(
        () => validator.validateFile(file),
        throwsA(isA<EmptyFileValidationFailure>()),
      );
    });

    test('rejects corrupt/truncated file (< 12 bytes)', () async {
      final file = File('${tempDir.path}/truncated.jpg')
        ..writeAsBytesSync([0xFF, 0xD8]);

      expect(
        () => validator.validateFile(file),
        throwsA(isA<CorruptHeaderValidationFailure>()),
      );
    });

    test('rejects non-existent file', () async {
      final file = File('${tempDir.path}/does_not_exist.jpg');

      expect(
        () => validator.validateFile(file),
        throwsA(isA<FileNotFoundValidationFailure>()),
      );
    });
  });

  group('ImageStagingService Tests (Batch A)', () {
    late Directory tempDir;
    late Directory stagingDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('staging_test_');
      stagingDir = Directory('${tempDir.path}/sandbox/projects/proj-101/source')
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'stages valid JPEG and verifies Invariant 4 source immutability',
      () async {
        final sourceBytes = Uint8List.fromList([
          0xFF,
          0xD8,
          0xFF,
          0xE0,
          0x00,
          0x10,
          0x4A,
          0x46,
          0x49,
          0x46,
          0x00,
          0x01,
          0xAA,
          0xBB,
          0xCC,
          0xDD,
        ]);
        final sourceFile = File('${tempDir.path}/user_original.jpg')
          ..writeAsBytesSync(sourceBytes);

        const stagingService = ImageStagingService();
        final result = await stagingService.stageSourceImage(
          sourcePath: sourceFile.path,
          destinationDir: stagingDir.path,
          projectId: 'proj-101',
        );

        // Verify staged file
        expect(result.format, equals(SupportedImageFormat.jpeg));
        expect(result.byteLength, equals(sourceBytes.length));
        expect(File(result.stagedPath).existsSync(), isTrue);
        expect(File(result.stagedPath).readAsBytesSync(), equals(sourceBytes));

        // Invariant 4 check: verify original source file is untouched
        expect(sourceFile.existsSync(), isTrue);
        expect(sourceFile.readAsBytesSync(), equals(sourceBytes));
      },
    );

    test('fails staging when disk storage headroom is exhausted', () async {
      final sourceBytes = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x10,
        0x4A,
        0x46,
        0x49,
        0x46,
        0x00,
        0x01,
      ]);
      final sourceFile = File('${tempDir.path}/user_photo.jpg')
        ..writeAsBytesSync(sourceBytes);

      // Capacity checker reporting only 1 KB available (< 10 MB margin)
      final lowStorageService = ImageStagingService(
        atomicWriter: AtomicFileWriter(
          capacityChecker: MockLowStorageCapacityChecker(1024),
        ),
      );

      expect(
        () => lowStorageService.stageSourceImage(
          sourcePath: sourceFile.path,
          destinationDir: stagingDir.path,
          projectId: 'proj-101',
        ),
        throwsA(isA<LowStorageFailure>()),
      );

      // Original source file is untouched
      expect(sourceFile.existsSync(), isTrue);
      expect(sourceFile.readAsBytesSync(), equals(sourceBytes));
    });

    test(
      'fails staging corrupt/unsupported file without touching sandbox',
      () async {
        final corruptBytes = Uint8List.fromList([
          0x00,
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
          0x08,
          0x09,
          0x0A,
          0x0B,
        ]);
        final corruptFile = File('${tempDir.path}/corrupt.bin')
          ..writeAsBytesSync(corruptBytes);

        const stagingService = ImageStagingService();
        expect(
          () => stagingService.stageSourceImage(
            sourcePath: corruptFile.path,
            destinationDir: stagingDir.path,
            projectId: 'proj-101',
          ),
          throwsA(isA<UnsupportedFormatValidationFailure>()),
        );

        // No staged source created
        expect(stagingDir.listSync().isEmpty, isTrue);
      },
    );
  });
}
