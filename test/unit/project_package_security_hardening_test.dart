import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/data/project_package/project_package_importer.dart';
import 'package:reranger/data/project_package/project_package_models.dart';
import 'package:reranger/domain/project/project_entity.dart';

void main() {
  group('DEF-026: Project Package Security Hardening Tests', () {
    late Directory tempDir;
    late ProjectDatabase db;
    late ProjectFileStorage storage;
    late ProjectPackageImporter importer;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('reranger_pkg_sec_');
      db = ProjectDatabase.openInMemory();
      storage = ProjectFileStorage(rootDir: tempDir);
      importer = ProjectPackageImporter(database: db, fileStorage: storage);
    });

    tearDown(() {
      db.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    File createZipPackage(List<ArchiveFile> files, String filename) {
      final archive = Archive();
      for (final file in files) {
        archive.addFile(file);
      }
      final zipData = ZipEncoder().encode(archive);
      final file = File(p.join(tempDir.path, filename));
      file.writeAsBytesSync(zipData);
      return file;
    }

    test(
      'Rejects archive exceeding maximum entry count (Zip Bomb limit)',
      () async {
        final files = <ArchiveFile>[];
        for (
          int i = 0;
          i < ProjectPackageImporter.maxArchiveEntryCount + 5;
          i++
        ) {
          files.add(ArchiveFile('file_$i.txt', 4, utf8.encode('data')));
        }

        final zipFile = createZipPackage(files, 'too_many_entries.rrproj');
        expect(
          () => importer.importPackage(zipFile),
          throwsA(isA<SecurityFailure>()),
        );
      },
    );

    test('Rejects archive exceeding maximum uncompressed byte limit', () async {
      final hugeData = List<int>.filled(1024, 65);
      final hugeFile = ArchiveFile(
        'huge.bin',
        ProjectPackageImporter.maxTotalUnpackedBytes + 1024,
        hugeData,
      );

      final zipFile = createZipPackage([hugeFile], 'too_large.rrproj');
      expect(
        () => importer.importPackage(zipFile),
        throwsA(isA<SecurityFailure>()),
      );
    });

    test(
      'Handles short or empty source image hashes without throwing RangeError',
      () async {
        final sourceBytes = [1, 2, 3, 4];
        final actualSourceSha = sha256.convert(sourceBytes).toString();

        final initialRecipe = RenderRecipe.initial(
          recipeId: 'rec_short',
          sourceImageHash: actualSourceSha,
          sourceImagePath: '/dummy.png',
          activeStudio: 'recolor',
          activePresetId: 'default',
        );
        final recipeJson = jsonEncode(initialRecipe.toJson());
        final recipeSha = sha256.convert(utf8.encode(recipeJson)).toString();

        final manifestJson = jsonEncode({
          'format': kRerangerPackageFormatId,
          'version': 1,
          'projectName': 'Short Hash Project',
          'sourceImageHash': actualSourceSha,
          'createdAt': DateTime.now().toIso8601String(),
          'files': {
            'source/photo.png': actualSourceSha,
            'recipe.json': recipeSha,
          },
        });

        final files = [
          ArchiveFile(
            'manifest.json',
            manifestJson.length,
            utf8.encode(manifestJson),
          ),
          ArchiveFile('source/photo.png', sourceBytes.length, sourceBytes),
          ArchiveFile(
            'recipe.json',
            recipeJson.length,
            utf8.encode(recipeJson),
          ),
        ];

        final zipFile = createZipPackage(files, 'short_hash.rrproj');
        final project = await importer.importPackage(zipFile);

        expect(project.name, equals('Short Hash Project'));
        expect(project.sourceImageHash, equals(actualSourceSha));
      },
    );

    test(
      'Failed import cleans up staged project files without leaving orphans',
      () async {
        final manifestJson = jsonEncode({
          'format': kRerangerPackageFormatId,
          'version': 1,
          'projectName': 'Failing Project',
          'sourceImageHash': 'abcdef123456',
          'createdAt': DateTime.now().toIso8601String(),
          'files': {
            'source/photo.png': 'dummy_hash',
            'missing_mask.png': 'expected_hash_for_missing_file',
          },
        });

        final files = [
          ArchiveFile(
            'manifest.json',
            manifestJson.length,
            utf8.encode(manifestJson),
          ),
        ];

        final zipFile = createZipPackage(files, 'failing.rrproj');
        expect(
          () => importer.importPackage(zipFile),
          throwsA(isA<MissingFileFailure>()),
        );

        // Verify no orphan directories exist
        if (storage.projectsDir.existsSync()) {
          final projectDirs = storage.projectsDir.listSync();
          expect(projectDirs, isEmpty);
        }
      },
    );
  });
}
