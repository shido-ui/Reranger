import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/local/project_database.dart';
import 'package:reranger/data/local/project_file_storage.dart';
import 'package:reranger/data/project_package/project_package_importer.dart';
import 'package:reranger/domain/project/project_entity.dart';
import 'package:reranger/features/export/domain/exif_metadata_policy.dart';

void main() {
  group('Batch D (Offline, Privacy & Licensing) Red-Team Audit Tests', () {
    late Directory tempDir;
    late ProjectDatabase db;
    late ProjectFileStorage storage;
    late ProjectPackageImporter importer;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('batch_d_sec_');
      db = ProjectDatabase.openInMemory();
      storage = ProjectFileStorage(rootDir: tempDir);
      importer = ProjectPackageImporter(database: db, fileStorage: storage);
    });

    tearDown(() {
      db.dispose();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('DEF-019 Regression: Zip-Slip null-byte injection is detected and rejected with SecurityFailure', () async {
      final archive = Archive();
      archive.addFile(
        ArchiveFile('manifest.json\x00.evil', 10, utf8.encode('malicious')),
      );

      final encoder = ZipEncoder();
      final zipBytes = encoder.encode(archive);

      final badPkg = File('${tempDir.path}/null_byte.rrproj')
        ..writeAsBytesSync(zipBytes);

      expect(
        () => importer.importPackage(badPkg),
        throwsA(
          isA<SecurityFailure>().having(
            (e) => e.message,
            'message',
            contains('Zip-Slip'),
          ),
        ),
      );
    });

    test(
      'ExifMetadataPolicy: Strips all GPS metadata tags comprehensively',
      () {
        final image = img.Image(width: 32, height: 32);
        image.exif.imageIfd.orientation = 1;
        image.exif['gps'][0x0001] = img.IfdValueAscii('N');
        image.exif['gps'][0x0002] = img.IfdValueAscii('37/1,46/1,29/1');
        image.exif['gps'][0x0003] = img.IfdValueAscii('W');
        image.exif['gps'][0x0004] = img.IfdValueAscii('122/1,25/1,9/1');

        expect(ExifMetadataPolicy.hasGpsData(image), isTrue);

        ExifMetadataPolicy.apply(image: image, stripGps: true);

        expect(ExifMetadataPolicy.hasGpsData(image), isFalse);
      },
    );

    test(
      'Zero Network Configuration: Manifest declares 0 network permissions',
      () {
        final manifest = File('android/app/src/main/AndroidManifest.xml');
        expect(manifest.existsSync(), isTrue);
        final xml = manifest.readAsStringSync();
        expect(xml.contains('android.permission.INTERNET'), isFalse);
        expect(
          xml.contains('android.permission.ACCESS_NETWORK_STATE'),
          isFalse,
        );
        expect(
          xml.contains('android.permission.CHANGE_NETWORK_STATE'),
          isFalse,
        );
      },
    );
  });
}
