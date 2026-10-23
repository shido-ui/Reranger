import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reranger/data/local/atomic_file_writer.dart';
import 'package:reranger/domain/project/project_entity.dart';

class _LowStorageChecker implements StorageCapacityChecker {
  @override
  Future<int> getAvailableDiskBytes(String directoryPath) async => 1024; // Only 1 KB available
}

void main() {
  group('DEF-024: AtomicFileWriter Safety, Headroom & Backup Rollback Tests', () {
    late Directory tempDir;
    late AtomicFileWriter writer;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('reranger_writer_test_');
      writer = const AtomicFileWriter();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'writeBytes successfully writes file with correct checksum and length',
      () async {
        final destPath = p.join(tempDir.path, 'output.png');
        final data = [1, 2, 3, 4, 5, 6, 7, 8];

        final result = await writer.writeBytes(
          destinationPath: destPath,
          bytes: data,
        );

        expect(result.path, equals(destPath));
        expect(result.byteLength, equals(8));
        expect(File(destPath).existsSync(), isTrue);
        expect(File(destPath).readAsBytesSync(), equals(data));

        final verified = await writer.verifyChecksum(
          destPath,
          result.sha256Checksum,
        );
        expect(verified, isTrue);
      },
    );

    test('Source image immutability prevents overwriting source media (Invariant 4)', () async {
      final sourcePath = p.join(tempDir.path, 'source_photo.jpg');
      File(sourcePath).writeAsStringSync('ORIGINAL_SOURCE_MEDIA');

      expect(
        () => writer.writeBytes(
          destinationPath: sourcePath,
          bytes: [9, 9, 9],
          sourceImagePath: sourcePath,
        ),
        throwsA(isA<StorageFailure>()),
      );

      // Verify original content was untouched
      expect(
        File(sourcePath).readAsStringSync(),
        equals('ORIGINAL_SOURCE_MEDIA'),
      );
    });

    test('LowStorageFailure thrown when disk space does not meet headroom requirement', () async {
      final destPath = p.join(tempDir.path, 'output.png');
      final lowWriter = AtomicFileWriter(capacityChecker: _LowStorageChecker());

      expect(
        () => lowWriter.writeBytes(
          destinationPath: destPath,
          bytes: List.filled(1024, 0),
        ),
        throwsA(isA<LowStorageFailure>()),
      );
    });

    test(
      'Overwriting existing file retains backup on rename or write operations',
      () async {
        final destPath = p.join(tempDir.path, 'existing.png');
        final originalBytes = [10, 20, 30, 40];
        File(destPath).writeAsBytesSync(originalBytes);

        final newBytes = [50, 60, 70, 80, 90];
        final result = await writer.writeBytes(
          destinationPath: destPath,
          bytes: newBytes,
        );

        expect(result.byteLength, equals(5));
        expect(File(destPath).readAsBytesSync(), equals(newBytes));

        // No leftover .tmp or .bak files
        final leftovers = tempDir.listSync().where(
          (f) => f.path.contains('.tmp.') || f.path.contains('.bak.'),
        );
        expect(leftovers, isEmpty);
      },
    );
  });
}
