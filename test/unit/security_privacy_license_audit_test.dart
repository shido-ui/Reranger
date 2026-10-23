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
  group('Prompt 26: Offline, Privacy, Security & Licensing Audit Tests', () {
    test('1. AndroidManifest.xml enforces Zero Network Permissions', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);

      final content = manifestFile.readAsStringSync();

      // Ensure no INTERNET or network permissions
      expect(
        content.contains('android.permission.INTERNET'),
        isFalse,
        reason: 'Production manifest must not declare INTERNET permission',
      );
      expect(
        content.contains('android.permission.ACCESS_NETWORK_STATE'),
        isFalse,
      );
      expect(content.contains('android.permission.ACCESS_WIFI_STATE'), isFalse);
      expect(
        content.contains('android.permission.ACCESS_FINE_LOCATION'),
        isFalse,
      );
      expect(
        content.contains('android.permission.ACCESS_COARSE_LOCATION'),
        isFalse,
      );
    });

    test('2. Runtime code in lib/ contains Zero Network APIs or Telemetry Calls', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final networkPatterns = [
        'HttpClient',
        'WebSocket',
        'RawSocket',
        'SecureSocket',
        'DatagramSocket',
        'package:http',
        'package:dio',
        'package:firebase',
        'package:sentry',
      ];

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          for (final pattern in networkPatterns) {
            expect(
              line.contains(pattern),
              isFalse,
              reason:
                  'Forbidden network pattern "$pattern" in ${file.path}:${i + 1}',
            );
          }
        }
      }
    });

    test(
      '3. Default Export Configuration Enforces GPS Stripping for Privacy',
      () {
        final image = img.Image(width: 16, height: 16);
        image.exif.imageIfd.orientation = 1;
        image.exif['gps'][0x0001] = img.IfdValueAscii('N');
        image.exif['gps'][0x0002] = img.IfdValueAscii('37/1,46/1,29/1');

        expect(ExifMetadataPolicy.hasGpsData(image), isTrue);

        // Apply default privacy stripping
        ExifMetadataPolicy.apply(
          image: image,
          stripGps: true,
          software: 'Reranger Studio',
        );

        expect(
          ExifMetadataPolicy.hasGpsData(image),
          isFalse,
          reason: 'GPS coordinates must be stripped from exported images',
        );
        expect(image.exif.imageIfd.software, equals('Reranger Studio'));
      },
    );

    test('4. ProjectPackageImporter Rejects Path Traversal (Zip-Slip) Attacks', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'security_audit_test_',
      );
      final db = ProjectDatabase.openInMemory();
      final storage = ProjectFileStorage(rootDir: tempDir);
      final importer = ProjectPackageImporter(
        database: db,
        fileStorage: storage,
      );

      final maliciousNames = [
        '../../evil.sh',
        '../etc/passwd',
        '/root/secret.txt',
        'C:\\Windows\\system32.cmd',
        'assets/../../../hacked',
      ];

      for (final badName in maliciousNames) {
        final archive = Archive();
        archive.addFile(ArchiveFile(badName, 4, [1, 2, 3, 4]));
        final zipData = ZipEncoder().encode(archive);
        final badFile = File('${tempDir.path}/bad_${badName.hashCode}.rrproj')
          ..writeAsBytesSync(zipData);

        expect(
          () => importer.importPackage(badFile),
          throwsA(isA<SecurityFailure>()),
          reason:
              'Archive entry "$badName" must trigger SecurityFailure on import',
        );
      }

      db.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test(
      '5. Dependency and Model Notices are Fully Documented with Zero UNKNOWNs',
      () {
        final noticesFile = File('THIRD_PARTY_NOTICES.md');
        expect(noticesFile.existsSync(), isTrue);

        final content = noticesFile.readAsStringSync();
        expect(
          content.contains('UNKNOWN'),
          isFalse,
          reason: 'No third party notices should contain UNKNOWN licenses',
        );
        expect(content.contains('MOD-SD15-Q4'), isTrue);
        expect(content.contains('MOD-LCM-LORA'), isTrue);
        expect(content.contains('CreativeML OpenRAIL-M'), isTrue);
        expect(content.contains('Apache-2.0'), isTrue);
        expect(content.contains('The MIT License'), isTrue);
        expect(content.contains('The 3-Clause BSD License'), isTrue);
      },
    );
  });
}
