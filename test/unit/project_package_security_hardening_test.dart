import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/local/atomic_file_writer.dart';
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/data/project_package/project_package_importer.dart';
import 'package:reranger/data/project_package/project_package_models.dart';
import 'package:reranger/domain/project/project_entity.dart';

class _MockLowCapacityChecker implements StorageCapacityChecker {
  final int available;
  const _MockLowCapacityChecker(this.available);

  @override
  Future<int?> getAvailableDiskBytes(String directoryPath) async => available;
}

class _MockUnknownCapacityChecker implements StorageCapacityChecker {
  const _MockUnknownCapacityChecker();

  @override
  Future<int?> getAvailableDiskBytes(String directoryPath) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ProjectDatabase db;
  late ProjectFileStorage fileStorage;

  Uint8List createDummyPng(int w, int h) {
    final image = img.Image(width: w, height: h, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(50, 100, 150, 255));
    return Uint8List.fromList(img.encodePng(image));
  }

  Uint8List buildZipArchive(List<ArchiveFile> files) {
    final archive = Archive();
    for (final f in files) {
      archive.addFile(f);
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pkg_sec_test_');
    db = ProjectDatabase.openInMemory();
    fileStorage = ProjectFileStorage(rootDir: tempDir);
  });

  tearDown(() {
    db.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group(
    'PROMPT 6: Section A - Project Package Security & Preflight Hardening',
    () {
      test(
        'Rejects zip archive with excessive entries (> 256) in preflight',
        () async {
          final entries = <ArchiveFile>[];
          for (int i = 0; i < 260; i++) {
            final content = utf8.encode('test content $i');
            entries.add(
              ArchiveFile('source/file_$i.png', content.length, content),
            );
          }
          final zipBytes = buildZipArchive(entries);
          final zipFile = File('${tempDir.path}/excessive_entries.rrproj');
          zipFile.writeAsBytesSync(zipBytes);

          final importer = ProjectPackageImporter(
            database: db,
            fileStorage: fileStorage,
          );

          expect(
            () => importer.importPackage(zipFile),
            throwsA(
              isA<SecurityFailure>().having(
                (e) => e.message,
                'message',
                contains('exceeds maximum entry count'),
              ),
            ),
          );
        },
      );

      test(
        'Rejects Zip-Slip directory traversal attempts before extraction',
        () async {
          final dummySource = createDummyPng(16, 16);
          final entries = [
            ArchiveFile('../../etc/passwd', 12, utf8.encode('root:x:0:0::')),
            ArchiveFile('manifest.json', 10, utf8.encode('{}')),
            ArchiveFile('recipe.json', 10, utf8.encode('{}')),
            ArchiveFile('source/photo.png', dummySource.length, dummySource),
          ];
          final zipBytes = buildZipArchive(entries);
          final zipFile = File('${tempDir.path}/zip_slip.rrproj');
          zipFile.writeAsBytesSync(zipBytes);

          final importer = ProjectPackageImporter(
            database: db,
            fileStorage: fileStorage,
          );

          expect(
            () => importer.importPackage(zipFile),
            throwsA(
              isA<SecurityFailure>().having(
                (e) => e.message,
                'message',
                contains('Zip-Slip / path traversal'),
              ),
            ),
          );
        },
      );

      test('Rejects null bytes in entry filename', () async {
        final dummySource = createDummyPng(16, 16);
        final entries = [
          ArchiveFile(
            'source/malicious\x00.png',
            dummySource.length,
            dummySource,
          ),
          ArchiveFile('manifest.json', 10, utf8.encode('{}')),
          ArchiveFile('recipe.json', 10, utf8.encode('{}')),
        ];
        final zipBytes = buildZipArchive(entries);
        final zipFile = File('${tempDir.path}/null_byte.rrproj');
        zipFile.writeAsBytesSync(zipBytes);

        final importer = ProjectPackageImporter(
          database: db,
          fileStorage: fileStorage,
        );

        expect(
          () => importer.importPackage(zipFile),
          throwsA(isA<SecurityFailure>()),
        );
      });

      test(
        'Rejects disallowed nested subdirectories under source/ or masks/',
        () async {
          final dummySource = createDummyPng(16, 16);
          final entries = [
            ArchiveFile(
              'source/nested/sub/image.png',
              dummySource.length,
              dummySource,
            ),
            ArchiveFile('manifest.json', 10, utf8.encode('{}')),
            ArchiveFile('recipe.json', 10, utf8.encode('{}')),
          ];
          final zipBytes = buildZipArchive(entries);
          final zipFile = File('${tempDir.path}/nested_sub.rrproj');
          zipFile.writeAsBytesSync(zipBytes);

          final importer = ProjectPackageImporter(
            database: db,
            fileStorage: fileStorage,
          );

          expect(
            () => importer.importPackage(zipFile),
            throwsA(
              isA<SecurityFailure>().having(
                (e) => e.message,
                'message',
                contains('Nested subdirectories in source/ not permitted'),
              ),
            ),
          );
        },
      );

      test(
        'Rejects missing manifest.json before decompressing files',
        () async {
          final dummySource = createDummyPng(16, 16);
          final entries = [
            ArchiveFile('source/photo.png', dummySource.length, dummySource),
            ArchiveFile('recipe.json', 10, utf8.encode('{}')),
          ];
          final zipBytes = buildZipArchive(entries);
          final zipFile = File('${tempDir.path}/missing_manifest.rrproj');
          zipFile.writeAsBytesSync(zipBytes);

          final importer = ProjectPackageImporter(
            database: db,
            fileStorage: fileStorage,
          );

          expect(
            () => importer.importPackage(zipFile),
            throwsA(
              isA<FormatFailure>().having(
                (e) => e.message,
                'message',
                contains('manifest.json'),
              ),
            ),
          );
        },
      );

      test('Rejects checksum mismatch on declared manifest files', () async {
        final dummySource = createDummyPng(16, 16);
        final sourceHash = sha256.convert(dummySource).toString();

        final manifestMap = {
          'format': kRerangerPackageFormatId,
          'sourceImageHash': sourceHash,
          'projectName': 'Tampered Project',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'files': {
            'source/photo.png': '0000000000000000000000000000000000000000000000000000000000000000', // forged hash
          },
        };
        final manifestJson = jsonEncode(manifestMap);

        final recipeJson = jsonEncode(
          RenderRecipe.initial(
            recipeId: 'rec_test',
            sourceImageHash: sourceHash,
            sourceImagePath: 'source/photo.png',
            activePresetId: 'default_natural',
          ).toJson(),
        );

        final entries = [
          ArchiveFile(
            'manifest.json',
            manifestJson.length,
            utf8.encode(manifestJson),
          ),
          ArchiveFile(
            'recipe.json',
            recipeJson.length,
            utf8.encode(recipeJson),
          ),
          ArchiveFile('source/photo.png', dummySource.length, dummySource),
        ];
        final zipBytes = buildZipArchive(entries);
        final zipFile = File('${tempDir.path}/tampered_hash.rrproj');
        zipFile.writeAsBytesSync(zipBytes);

        final importer = ProjectPackageImporter(
          database: db,
          fileStorage: fileStorage,
        );

        expect(
          () => importer.importPackage(zipFile),
          throwsA(isA<ChecksumMismatchFailure>()),
        );
      });

      test('Rejects undeclared foreign file in package archive', () async {
        final dummySource = createDummyPng(16, 16);
        final sourceHash = sha256.convert(dummySource).toString();

        final manifestMap = {
          'format': kRerangerPackageFormatId,
          'sourceImageHash': sourceHash,
          'projectName': 'Undeclared Test',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'files': {'source/photo.png': sourceHash},
        };
        final manifestJson = jsonEncode(manifestMap);

        final recipeJson = jsonEncode(
          RenderRecipe.initial(
            recipeId: 'rec_test',
            sourceImageHash: sourceHash,
            sourceImagePath: 'source/photo.png',
            activePresetId: 'default_natural',
          ).toJson(),
        );

        final entries = [
          ArchiveFile(
            'manifest.json',
            manifestJson.length,
            utf8.encode(manifestJson),
          ),
          ArchiveFile(
            'recipe.json',
            recipeJson.length,
            utf8.encode(recipeJson),
          ),
          ArchiveFile('source/photo.png', dummySource.length, dummySource),
          ArchiveFile('masks/injected_secret.png', 8, utf8.encode('secret!!')),
        ];
        final zipBytes = buildZipArchive(entries);
        final zipFile = File('${tempDir.path}/undeclared_file.rrproj');
        zipFile.writeAsBytesSync(zipBytes);

        final importer = ProjectPackageImporter(
          database: db,
          fileStorage: fileStorage,
        );

        expect(
          () => importer.importPackage(zipFile),
          throwsA(
            isA<SecurityFailure>().having(
              (e) => e.message,
              'message',
              contains('undeclared file'),
            ),
          ),
        );
      });

      test(
        'Rejects import when storage capacity is known and insufficient',
        () async {
          final dummySource = createDummyPng(16, 16);
          final sourceHash = sha256.convert(dummySource).toString();

          final manifestMap = {
            'format': kRerangerPackageFormatId,
            'sourceImageHash': sourceHash,
            'projectName': 'Low Disk Test',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'files': {'source/photo.png': sourceHash},
          };
          final manifestJson = jsonEncode(manifestMap);
          final recipeJson = jsonEncode(
            RenderRecipe.initial(
              recipeId: 'rec_test',
              sourceImageHash: sourceHash,
              sourceImagePath: 'source/photo.png',
              activePresetId: 'default_natural',
            ).toJson(),
          );

          final entries = [
            ArchiveFile(
              'manifest.json',
              manifestJson.length,
              utf8.encode(manifestJson),
            ),
            ArchiveFile(
              'recipe.json',
              recipeJson.length,
              utf8.encode(recipeJson),
            ),
            ArchiveFile('source/photo.png', dummySource.length, dummySource),
          ];
          final zipBytes = buildZipArchive(entries);
          final zipFile = File('${tempDir.path}/low_disk.rrproj');
          zipFile.writeAsBytesSync(zipBytes);

          // Capacity checker reports only 512 bytes available (insufficient for 10MB safety margin)
          final importer = ProjectPackageImporter(
            database: db,
            fileStorage: fileStorage,
            capacityChecker: const _MockLowCapacityChecker(512),
          );

          expect(
            () => importer.importPackage(zipFile),
            throwsA(isA<LowStorageFailure>()),
          );
        },
      );

      test(
        'Permits import when storage capacity is unknown (null fallback)',
        () async {
          final dummySource = createDummyPng(16, 16);
          final sourceHash = sha256.convert(dummySource).toString();

          final manifestMap = {
            'format': kRerangerPackageFormatId,
            'sourceImageHash': sourceHash,
            'projectName': 'Unknown Disk Test',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'files': {'source/photo.png': sourceHash},
          };
          final manifestJson = jsonEncode(manifestMap);
          final recipeJson = jsonEncode(
            RenderRecipe.initial(
              recipeId: 'rec_test',
              sourceImageHash: sourceHash,
              sourceImagePath: 'source/photo.png',
              activePresetId: 'default_natural',
            ).toJson(),
          );

          final entries = [
            ArchiveFile(
              'manifest.json',
              manifestJson.length,
              utf8.encode(manifestJson),
            ),
            ArchiveFile(
              'recipe.json',
              recipeJson.length,
              utf8.encode(recipeJson),
            ),
            ArchiveFile('source/photo.png', dummySource.length, dummySource),
          ];
          final zipBytes = buildZipArchive(entries);
          final zipFile = File('${tempDir.path}/unknown_disk.rrproj');
          zipFile.writeAsBytesSync(zipBytes);

          // Unknown capacity checker returns null (Prompt 6.A.3)
          final importer = ProjectPackageImporter(
            database: db,
            fileStorage: fileStorage,
            capacityChecker: const _MockUnknownCapacityChecker(),
          );

          final imported = await importer.importPackage(zipFile);
          expect(imported.id, isNotEmpty);
          expect(imported.name, equals('Unknown Disk Test'));
          expect(imported.sourceImageHash, equals(sourceHash));
          expect(File(imported.sourceImagePath).existsSync(), isTrue);
        },
      );
    },
  );

  group('PROMPT 6: Section A.4 - AtomicFileWriter Rollback & Replacement Durability', () {
    test('Strictly forbids overwriting immutable source image media', () async {
      const writer = AtomicFileWriter();
      final sourceFile = File('${tempDir.path}/immutable_source.png');
      sourceFile.writeAsBytesSync([1, 2, 3, 4]);

      expect(
        () => writer.writeBytes(
          destinationPath: sourceFile.path,
          bytes: [5, 6, 7, 8],
          sourceImagePath: sourceFile.path,
        ),
        throwsA(isA<StorageFailure>()),
      );

      // File was not modified
      expect(sourceFile.readAsBytesSync(), equals([1, 2, 3, 4]));
    });

    test('Atomic write creates target file with correct checksum and cleans temp files', () async {
      const writer = AtomicFileWriter();
      final destPath = '${tempDir.path}/atomic_output.png';
      final payload = [10, 20, 30, 40, 50];

      final result = await writer.writeBytes(
        destinationPath: destPath,
        bytes: payload,
      );

      expect(result.path, equals(destPath));
      expect(result.byteLength, equals(5));
      expect(File(destPath).existsSync(), isTrue);
      expect(File(destPath).readAsBytesSync(), equals(payload));

      // Temporary files cleaned up
      final siblingFiles = tempDir.listSync().map((e) => e.path).toList();
      expect(siblingFiles.any((p) => p.contains('.tmp.')), isFalse);
      expect(siblingFiles.any((p) => p.contains('.bak.')), isFalse);
    });
  });
}
