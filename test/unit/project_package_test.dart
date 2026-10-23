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
import 'package:reranger/data/project_package/project_package_exporter.dart';
import 'package:reranger/data/project_package/project_package_importer.dart';
import 'package:reranger/data/project_package/project_package_models.dart';
import 'package:reranger/domain/project/project_entity.dart';

class MockConstrainedCapacityChecker implements StorageCapacityChecker {
  final int availableBytes;

  const MockConstrainedCapacityChecker(this.availableBytes);

  @override
  Future<int> getAvailableDiskBytes(String directoryPath) async =>
      availableBytes;
}

void main() {
  group('Prompt 24: Portable Project Package Format (.rrproj) Tests', () {
    late Directory tempDir;
    late Directory exportDir;
    late Directory importDir;

    late ProjectDatabase sourceDb;
    late ProjectFileStorage sourceStorage;
    late ProjectDatabase targetDb;
    late ProjectFileStorage targetStorage;

    late File sampleSourceImage;
    late ProjectEntity sampleProject;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('project_package_test_');
      exportDir = Directory('${tempDir.path}/export_sandbox')..createSync();
      importDir = Directory('${tempDir.path}/import_sandbox')..createSync();

      sourceDb = ProjectDatabase.openInMemory();
      sourceStorage = ProjectFileStorage(rootDir: exportDir);

      targetDb = ProjectDatabase.openInMemory();
      targetStorage = ProjectFileStorage(rootDir: importDir);

      // Create a test 32x32 image
      final image = img.Image(width: 32, height: 32, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(120, 160, 200, 255));
      final imageBytes = img.encodePng(image);
      final sourceSha = sha256.convert(imageBytes).toString();

      sourceStorage.ensureProjectDirectories('proj_pkg_001');
      sampleSourceImage = File(
        '${sourceStorage.getSourceDirectory('proj_pkg_001').path}/input.png',
      )..writeAsBytesSync(imageBytes);

      sampleProject = ProjectEntity(
        id: 'proj_pkg_001',
        name: 'Vibrant Sunset',
        sourceImagePath: sampleSourceImage.path,
        sourceImageHash: sourceSha,
        sourceWidth: 32,
        sourceHeight: 32,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        recipe:
            RenderRecipe.initial(
              recipeId: 'rec_pkg_001',
              sourceImageHash: sourceSha,
              sourceImagePath: sampleSourceImage.path,
              activeStudio: 'style',
              activePresetId: 'warm_glow',
            ).copyWith(
              fineTuneParameters: const {
                'temperature': 0.40,
                'tint': -0.15,
                'vibrance': 0.65,
              },
            ),
      );

      sourceDb.upsertProject(sampleProject);
    });

    tearDown(() {
      sourceDb.dispose();
      targetDb.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Export and import round-trip: all metadata, recipes, and assets preserved', () async {
      final exporter = ProjectPackageExporter(fileStorage: sourceStorage);
      final packagePath = '${tempDir.path}/vibrant_sunset.rrproj';

      final exportResult = await exporter.exportPackage(
        project: sampleProject,
        destinationPackagePath: packagePath,
      );

      expect(File(packagePath).existsSync(), isTrue);
      expect(exportResult.byteLength, greaterThan(0));

      // Import into clean target environment
      final importer = ProjectPackageImporter(
        database: targetDb,
        fileStorage: targetStorage,
      );
      final importedProject = await importer.importPackage(File(packagePath));

      expect(importedProject.name, equals('Vibrant Sunset'));
      expect(
        importedProject.sourceImageHash,
        equals(sampleProject.sourceImageHash),
      );
      expect(importedProject.sourceWidth, equals(32));
      expect(importedProject.sourceHeight, equals(32));
      expect(
        importedProject.recipe.activePresetId,
        equals(sampleProject.recipe.activePresetId),
      );
      expect(
        importedProject.recipe.fineTuneParameters['temperature'],
        equals(0.40),
      );
      expect(
        importedProject.recipe.fineTuneParameters['vibrance'],
        equals(0.65),
      );
      expect(File(importedProject.sourceImagePath).existsSync(), isTrue);
      expect(importedProject.isCorrupted, isFalse);

      // Verify registered in target SQLite database
      final queried = targetDb.getProjectById(importedProject.id);
      expect(queried, isNotNull);
      expect(queried!.name, equals('Vibrant Sunset'));
    });

    test('Zip-Slip security protection: Strictly rejects archive containing path traversal', () async {
      // Construct a malicious zip archive with "../../evil.txt" entry
      final archive = Archive();
      final maliciousEntry = ArchiveFile(
        '../../evil.txt',
        11,
        utf8.encode('malicious..'),
      );
      archive.addFile(maliciousEntry);

      // Add a fake manifest so manifest check isn't the first failure
      final manifest = ProjectPackageManifest(
        createdAt: DateTime.now().toUtc(),
        originalProjectId: 'proj_evil',
        projectName: 'Malicious Project',
        sourceImageHash: 'fake_hash',
        files: const {'../../evil.txt': 'fake_digest'},
      );
      final manifestBytes = utf8.encode(manifest.toJsonString());
      archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );

      final zipData = ZipEncoder().encode(archive);
      final attackPackage = File('${tempDir.path}/attack.rrproj')
        ..writeAsBytesSync(zipData);

      final importer = ProjectPackageImporter(
        database: targetDb,
        fileStorage: targetStorage,
      );

      expect(
        () => importer.importPackage(attackPackage),
        throwsA(
          isA<SecurityFailure>().having(
            (e) => e.message,
            'message',
            contains('Zip-Slip'),
          ),
        ),
      );

      // Verify the malicious file was NEVER written to the host filesystem
      expect(File('${tempDir.path}/evil.txt').existsSync(), isFalse);
    });

    test('Checksum verification: Detects and rejects tampered files', () async {
      // Export a clean package first
      final exporter = ProjectPackageExporter(fileStorage: sourceStorage);
      final packagePath = '${tempDir.path}/tampered.rrproj';
      await exporter.exportPackage(
        project: sampleProject,
        destinationPackagePath: packagePath,
      );

      // Unpack, tamper with the source image, and repack
      final zipBytes = File(packagePath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final sourceFile = archive.findFile('source/input.png')!;

      // Alter content bytes
      final tamperedContent = Uint8List.fromList(
        List<int>.from(sourceFile.content as List<int>)..first = 0xAA,
      );
      final tamperedArchive = Archive();
      for (final f in archive.files) {
        if (f.name == 'source/input.png') {
          tamperedArchive.addFile(
            ArchiveFile(f.name, tamperedContent.length, tamperedContent),
          );
        } else {
          tamperedArchive.addFile(f);
        }
      }

      final tamperedZip = ZipEncoder().encode(tamperedArchive);
      File(packagePath).writeAsBytesSync(tamperedZip);

      final importer = ProjectPackageImporter(
        database: targetDb,
        fileStorage: targetStorage,
      );

      expect(
        () => importer.importPackage(File(packagePath)),
        throwsA(isA<ChecksumMismatchFailure>()),
      );
    });

    test(
      'Missing asset detection: Rejects package missing declared file',
      () async {
        // Create an archive where manifest declares a file that is not in the archive
        final archive = Archive();
        final manifest = ProjectPackageManifest(
          createdAt: DateTime.now().toUtc(),
          originalProjectId: 'proj_missing',
          projectName: 'Missing Asset Project',
          sourceImageHash: 'fake_hash',
          files: const {'source/missing.png': 'fake_sha'},
        );
        final manifestBytes = utf8.encode(manifest.toJsonString());
        archive.addFile(
          ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
        );

        final zipData = ZipEncoder().encode(archive);
        final packageFile = File('${tempDir.path}/missing_asset.rrproj')
          ..writeAsBytesSync(zipData);

        final importer = ProjectPackageImporter(
          database: targetDb,
          fileStorage: targetStorage,
        );

        expect(
          () => importer.importPackage(packageFile),
          throwsA(isA<MissingFileFailure>()),
        );
      },
    );

    test('Corrupted archive format: Rejects invalid or truncated files', () {
      final invalidFile = File('${tempDir.path}/not_a_zip.rrproj')
        ..writeAsStringSync('THIS IS NOT A ZIP ARCHIVE');

      final importer = ProjectPackageImporter(
        database: targetDb,
        fileStorage: targetStorage,
      );

      expect(
        () => importer.importPackage(invalidFile),
        throwsA(isA<FormatFailure>()),
      );
    });

    test(
      'Name collision resolution: Auto-resolves duplicate name gracefully',
      () async {
        // Insert a project with the same name into the target database
        targetDb.upsertProject(sampleProject);

        final exporter = ProjectPackageExporter(fileStorage: sourceStorage);
        final packagePath = '${tempDir.path}/collision_test.rrproj';
        await exporter.exportPackage(
          project: sampleProject,
          destinationPackagePath: packagePath,
        );

        final importer = ProjectPackageImporter(
          database: targetDb,
          fileStorage: targetStorage,
        );
        final imported = await importer.importPackage(File(packagePath));

        // Name was auto-resolved to prevent unique constraint failure
        expect(imported.name, equals('Vibrant Sunset (Imported)'));

        // Import again: should become 'Vibrant Sunset (Imported 1)'
        final importedAgain = await importer.importPackage(File(packagePath));
        expect(importedAgain.name, equals('Vibrant Sunset (Imported 1)'));
      },
    );

    test(
      'Low storage headroom check: Throws LowStorageFailure on full disk',
      () async {
        final exporter = ProjectPackageExporter(fileStorage: sourceStorage);
        final packagePath = '${tempDir.path}/storage_test.rrproj';
        await exporter.exportPackage(
          project: sampleProject,
          destinationPackagePath: packagePath,
        );

        final constrainedImporter = ProjectPackageImporter(
          database: targetDb,
          fileStorage: targetStorage,
          capacityChecker: const MockConstrainedCapacityChecker(1024),
        );

        expect(
          () => constrainedImporter.importPackage(File(packagePath)),
          throwsA(isA<LowStorageFailure>()),
        );
      },
    );
  });
}
