import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/features/detector_lab/detector_lab_models.dart';

void main() {
  group(
    'Prompt B Batch 5: Truthful C2PA Provenance & Signal Inspection Tests',
    () {
      test(
        'Empty and truncated inputs (< 8 bytes) evaluate truthfully as missing',
        () {
          final emptyResult = C2paParser.parseBytes(Uint8List(0));
          expect(emptyResult.status, equals(C2paStatus.missing));
          expect(emptyResult.isMissing, isTrue);
          expect(emptyResult.isValid, isFalse);
          expect(emptyResult.manifestIssuer, isNull);

          final shortResult = C2paParser.parseBytes(
            Uint8List.fromList([0x6a, 0x75, 0x6d]),
          );
          expect(shortResult.status, equals(C2paStatus.missing));
        },
      );

      test('C2PA magic and JUMBF magic detect manifest containers without simulating fake PKI signatures', () {
        // 1. C2PA magic tag
        final c2paBytes = Uint8List.fromList([
          0xFF,
          0xD8,
          0xFF,
          0xE1,
          ...C2paParser.c2paMagic,
          0x01,
          0x02,
          0x03,
          0x04,
        ]);
        final c2paResult = C2paParser.parseBytes(c2paBytes);
        expect(
          c2paResult.status,
          equals(C2paStatus.manifestContainerDetectedUnverified),
        );
        expect(c2paResult.isContainerDetected, isTrue);
        expect(
          c2paResult.isValid,
          isFalse,
        ); // Invariant 7: unverified marker is not valid
        expect(
          c2paResult.manifestIssuer,
          isNull,
        ); // Invariant 7: never fabricate issuer
        expect(c2paResult.message, contains('not verified'));

        // 2. JUMBF magic tag with full header segment
        final jumbBytes = Uint8List.fromList([
          0x00,
          0x00,
          0x00,
          0x18,
          ...C2paParser.jumbMagic,
          0x63,
          0x32,
          0x70,
          0x61,
          0x01,
          0x02,
          0x03,
          0x04,
          0x05,
          0x06,
          0x07,
          0x08,
        ]);
        final jumbResult = C2paParser.parseBytes(jumbBytes);
        expect(
          jumbResult.status,
          equals(C2paStatus.manifestContainerDetectedUnverified),
        );
        expect(jumbResult.manifestIssuer, isNull);
      });

      test(
        'Corrupt marker or truncated segment reports malformed invalid status',
        () {
          // Truncated segment (magic at end of buffer without 8-byte header window)
          final truncatedBytes = Uint8List.fromList([
            0xFF,
            0xD8,
            ...C2paParser.c2paMagic,
            0x01,
            0x02,
          ]);
          final truncatedResult = C2paParser.parseBytes(truncatedBytes);
          expect(truncatedResult.status, equals(C2paStatus.invalid));
          expect(truncatedResult.message, contains('Truncated'));

          // Corrupt magic marker
          final corruptBytes = Uint8List.fromList([
            0xFF,
            0xD8,
            0xFF,
            0xE1,
            ...C2paParser.corruptMagic,
            0x00,
            0x00,
            0x00,
            0x00,
          ]);
          final corruptResult = C2paParser.parseBytes(corruptBytes);
          expect(corruptResult.status, equals(C2paStatus.invalid));
          expect(corruptResult.message, contains('Corrupt or unreadable'));
        },
      );

      test('C2paStatus label and messages conform to Invariant 7 non-illusory reporting', () {
        expect(
          C2paStatus.manifestContainerDetectedUnverified.label,
          equals(
            'Metadata marker present; cryptographic signature not verified',
          ),
        );
        expect(
          C2paStatus.invalid.label,
          equals('Corrupt or Malformed C2PA Box'),
        );
        expect(
          C2paStatus.missing.label,
          equals('No supported provenance signal found.'),
        );
      });
    },
  );
}
