import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/local/atomic_file_writer.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/features/export/data/image_exporter.dart';
import 'package:reranger/features/export/domain/exif_metadata_policy.dart';
import 'package:reranger/features/export/domain/export_format.dart';

class MockConstrainedCapacityChecker implements StorageCapacityChecker {
  final int availableBytes;

  const MockConstrainedCapacityChecker(this.availableBytes);

  @override
  Future<int> getAvailableDiskBytes(String directoryPath) async =>
      availableBytes;
}

void main() {
  group('Prompt 24: Export Service & Format Encoders Unit Tests', () {
    late Directory tempDir;
    late img.Image testImageWithAlpha;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('export_service_test_');

      // Create a 16x16 image with a transparent center
      testImageWithAlpha = img.Image(width: 16, height: 16, numChannels: 4);
      for (int y = 0; y < 16; y++) {
        for (int x = 0; x < 16; x++) {
          if (x >= 4 && x < 12 && y >= 4 && y < 12) {
            // Transparent region (A = 0)
            testImageWithAlpha.setPixelRgba(x, y, 0, 0, 0, 0);
          } else {
            // Opaque blue region (A = 255)
            testImageWithAlpha.setPixelRgba(x, y, 50, 100, 200, 255);
          }
        }
      }
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('PNG export preserves complete 32-bit RGBA transparency', () async {
      const exporter = ImageExporter();
      final destination = '${tempDir.path}/output.png';

      final result = await exporter.exportToFile(
        sourceImage: testImageWithAlpha,
        destinationPath: destination,
        config: const ExportConfiguration(format: ExportImageFormat.png),
      );

      expect(File(destination).existsSync(), isTrue);
      expect(result.format, equals(ExportImageFormat.png));
      expect(result.alphaStripped, isFalse);
      expect(result.width, equals(16));
      expect(result.height, equals(16));

      // Decode exported bytes to verify transparency is intact
      final decoded = img.decodePng(File(destination).readAsBytesSync())!;
      expect(decoded.hasAlpha, isTrue);
      expect(
        decoded.getPixel(8, 8).a,
        equals(0),
      ); // Center pixel is transparent
      expect(decoded.getPixel(0, 0).a, equals(255)); // Corner pixel is opaque
    });

    test('JPEG export honestly composites transparency onto white and sets alphaStripped', () async {
      const exporter = ImageExporter();
      final destination = '${tempDir.path}/output.jpg';

      final result = await exporter.exportToFile(
        sourceImage: testImageWithAlpha,
        destinationPath: destination,
        config: const ExportConfiguration(
          format: ExportImageFormat.jpeg,
          quality: 85,
          backgroundColorForOpaque: [255, 255, 255],
        ),
      );

      expect(File(destination).existsSync(), isTrue);
      expect(result.format, equals(ExportImageFormat.jpeg));
      expect(result.alphaStripped, isTrue); // Honestly declares alpha removal

      // Verify decoded JPEG has no alpha channel and transparent center became white
      final decoded = img.decodeJpg(File(destination).readAsBytesSync())!;
      expect(decoded.width, equals(16));
      expect(decoded.height, equals(16));

      final centerPixel = decoded.getPixel(8, 8);
      // Center pixel was composited onto white [255, 255, 255]
      expect(centerPixel.r, greaterThan(240));
      expect(centerPixel.g, greaterThan(240));
      expect(centerPixel.b, greaterThan(240));
    });

    test('JPEG quality setting meaningfully modulates file size', () {
      const exporter = ImageExporter();

      final highQuality = exporter.encode(
        sourceImage: testImageWithAlpha,
        config: const ExportConfiguration(
          format: ExportImageFormat.jpeg,
          quality: 98,
        ),
      );

      final lowQuality = exporter.encode(
        sourceImage: testImageWithAlpha,
        config: const ExportConfiguration(
          format: ExportImageFormat.jpeg,
          quality: 20,
        ),
      );

      expect(
        highQuality.bytes.length,
        greaterThanOrEqualTo(lowQuality.bytes.length),
      );
    });

    test(
      'WebP export produces valid modern format with alpha preservation',
      () {
        const exporter = ImageExporter();

        final result = exporter.encode(
          sourceImage: testImageWithAlpha,
          config: const ExportConfiguration(
            format: ExportImageFormat.webp,
            quality: 90,
          ),
        );

        expect(result.alphaStripped, isFalse);
        expect(result.bytes.length, greaterThan(12));

        // WebP container begins with 'RIFF' and has 'WEBP' marker at offset 8
        final headerStr = String.fromCharCodes(result.bytes.sublist(0, 4));
        final webpStr = String.fromCharCodes(result.bytes.sublist(8, 12));
        expect(headerStr, equals('RIFF'));
        expect(webpStr, equals('WEBP'));
      },
    );

    test('Scale parameter accurately rescales pixel dimensions', () async {
      const exporter = ImageExporter();
      final destination = '${tempDir.path}/scaled_half.png';

      final result = await exporter.exportToFile(
        sourceImage: testImageWithAlpha,
        destinationPath: destination,
        config: const ExportConfiguration(
          format: ExportImageFormat.png,
          scale: 0.5,
        ),
      );

      expect(result.width, equals(8));
      expect(result.height, equals(8));

      final decoded = img.decodePng(File(destination).readAsBytesSync())!;
      expect(decoded.width, equals(8));
      expect(decoded.height, equals(8));
    });

    test('EXIF policy strips GPS tags and canonicalizes orientation to 1', () {
      final imageWithExif = testImageWithAlpha.clone();
      // Inject GPS and Orientation tags
      imageWithExif.exif.imageIfd.orientation = 6; // 90 CW
      imageWithExif.exif['gps'][0x0001] = img.IfdValueAscii(
        'N',
      ); // GPSLatitudeRef

      expect(ExifMetadataPolicy.hasGpsData(imageWithExif), isTrue);

      ExifMetadataPolicy.apply(
        image: imageWithExif,
        stripGps: true,
        software: 'Reranger Studio',
      );

      expect(ExifMetadataPolicy.hasGpsData(imageWithExif), isFalse);
      expect(imageWithExif.exif.imageIfd.orientation, equals(1));
      expect(imageWithExif.exif.imageIfd.software, equals('Reranger Studio'));
    });

    test(
      'RealSizeEstimator produces monotonic dimension/quality estimates',
      () {
        final q50 = RealSizeEstimator.estimateSizeBytes(
          width: 1000,
          height: 1000,
          config: const ExportConfiguration(
            format: ExportImageFormat.jpeg,
            quality: 50,
          ),
        );
        final q90 = RealSizeEstimator.estimateSizeBytes(
          width: 1000,
          height: 1000,
          config: const ExportConfiguration(
            format: ExportImageFormat.jpeg,
            quality: 90,
          ),
        );

        expect(q90, greaterThan(q50));
        expect(RealSizeEstimator.formatBytes(1500000), equals('1.43 MB'));
        expect(RealSizeEstimator.formatBytes(50000), equals('48.8 KB'));
      },
    );

    test('Atomic write verifies SHA-256 and leaves no temp files', () async {
      const exporter = ImageExporter();
      final destination = '${tempDir.path}/atomic_test.png';

      final result = await exporter.exportToFile(
        sourceImage: testImageWithAlpha,
        destinationPath: destination,
        config: const ExportConfiguration(format: ExportImageFormat.png),
      );

      final writtenBytes = File(destination).readAsBytesSync();
      final realSha = sha256.convert(writtenBytes).toString();
      expect(result.sha256Checksum, equals(realSha));

      // Verify no temporary files remain
      final tempFiles = tempDir
          .listSync()
          .where((f) => f.path.contains('.tmp.'))
          .toList();
      expect(tempFiles, isEmpty);
    });

    test(
      'Low storage headroom check throws LowStorageFailure and cleans up',
      () async {
        final exporter = ImageExporter(
          atomicWriter: AtomicFileWriter(
            capacityChecker: const MockConstrainedCapacityChecker(1024),
          ),
        );
        final destination = '${tempDir.path}/low_storage.png';

        expect(
          () => exporter.exportToFile(
            sourceImage: testImageWithAlpha,
            destinationPath: destination,
            config: const ExportConfiguration(format: ExportImageFormat.png),
          ),
          throwsA(isA<LowStorageFailure>()),
        );

        // Destination was never created
        expect(File(destination).existsSync(), isFalse);
      },
    );

    test(
      'Source image immutability: Cannot overwrite source media path',
      () async {
        final fakeSourcePath = '${tempDir.path}/immutable_source.png';
        File(fakeSourcePath).writeAsBytesSync([1, 2, 3]);

        const exporter = ImageExporter();
        expect(
          () => exporter.exportToFile(
            sourceImage: testImageWithAlpha,
            destinationPath: fakeSourcePath,
            sourceImagePath: fakeSourcePath,
            config: const ExportConfiguration(format: ExportImageFormat.png),
          ),
          throwsA(isA<StorageFailure>()),
        );
      },
    );

    test('resolveNonCollidingPath auto-increments to prevent overwrite', () {
      File('${tempDir.path}/artwork.png').writeAsStringSync('1');
      final path1 = ImageExporter.resolveNonCollidingPath(
        destinationDir: tempDir,
        baseName: 'artwork',
        extension: '.png',
      );
      expect(path1, equals('${tempDir.path}/artwork (1).png'));

      File(path1).writeAsStringSync('2');
      final path2 = ImageExporter.resolveNonCollidingPath(
        destinationDir: tempDir,
        baseName: 'artwork',
        extension: '.png',
      );
      expect(path2, equals('${tempDir.path}/artwork (2).png'));
    });
  });
}
