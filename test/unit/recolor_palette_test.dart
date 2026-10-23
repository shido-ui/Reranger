import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/domain/color/color_palette.dart';

void main() {
  group('ColorRgb & ColorHsl Conversions', () {
    test('BT.601 integer luminance computes standard weighted sum', () {
      // Formula: (299*R + 587*G + 114*B) / 1000
      expect(const ColorRgb(255, 255, 255).luminance, equals(255));
      expect(const ColorRgb(0, 0, 0).luminance, equals(0));
      expect(
        const ColorRgb(255, 0, 0).luminance,
        equals(76),
      ); // 255 * 0.299 = 76.245
      expect(
        const ColorRgb(0, 255, 0).luminance,
        equals(149),
      ); // 255 * 0.587 = 149.685
      expect(
        const ColorRgb(0, 0, 255).luminance,
        equals(29),
      ); // 255 * 0.114 = 29.07
    });

    test('Hex string parsing and generation round-trip correctly', () {
      const red = ColorRgb(255, 0, 0);
      expect(red.toHex(), equals('#FF0000'));
      expect(ColorRgb.fromHex('#FF0000'), equals(red));
      expect(ColorRgb.fromHex('FF0000'), equals(red));
      expect(ColorRgb.fromHex('#F00'), equals(red));

      const semiBlue = ColorRgb(0, 0, 255, 128);
      expect(semiBlue.toHex(includeAlpha: true), equals('#800000FF'));
      expect(ColorRgb.fromHex('#800000FF'), equals(semiBlue));
    });

    test('RGB to HSL and back preserves color coordinates', () {
      final testColors = [
        const ColorRgb(255, 0, 0), // Pure Red
        const ColorRgb(0, 255, 0), // Pure Green
        const ColorRgb(0, 0, 255), // Pure Blue
        const ColorRgb(255, 255, 0), // Pure Yellow
        const ColorRgb(0, 255, 255), // Cyan
        const ColorRgb(255, 0, 255), // Magenta
        const ColorRgb(128, 128, 128), // Neutral Gray
        const ColorRgb(200, 100, 50), // Arbitrary Orange
      ];

      for (final rgb in testColors) {
        final hsl = rgb.toHsl();
        final reconstructed = hsl.toRgb();
        expect(
          (reconstructed.r - rgb.r).abs(),
          lessThanOrEqualTo(1),
          reason: 'R drifted for $rgb',
        );
        expect(
          (reconstructed.g - rgb.g).abs(),
          lessThanOrEqualTo(1),
          reason: 'G drifted for $rgb',
        );
        expect(
          (reconstructed.b - rgb.b).abs(),
          lessThanOrEqualTo(1),
          reason: 'B drifted for $rgb',
        );
      }
    });

    test('Normalized color distance reflects Euclidean proximity', () {
      const c1 = ColorRgb(255, 0, 0);
      const c2 = ColorRgb(255, 0, 0);
      const c3 = ColorRgb(0, 0, 0);
      const c4 = ColorRgb(255, 255, 255);

      expect(c1.normalizedDistanceTo(c2), equals(0.0));
      expect(c3.normalizedDistanceTo(c4), closeTo(1.0, 1e-4));
      expect(c1.normalizedDistanceTo(c3), closeTo(1.0 / math.sqrt(3.0), 1e-4));
    });
  });

  group('ColorHarmonies Mathematical Accuracy', () {
    test('Complementary harmony calculates 180° opposite hue', () {
      const base = ColorRgb(255, 0, 0); // Hue = 0°
      final comp = ColorHarmonies.complementary(base);
      expect(comp.length, equals(2));
      expect(comp[0], equals(base));

      final compHsl = comp[1].toHsl();
      expect(compHsl.h, closeTo(180.0, 1.0)); // Cyan
    });

    test('Analogous harmony calculates ±30° neighboring hues', () {
      const base = ColorRgb(0, 255, 0); // Hue = 120°
      final analogous = ColorHarmonies.analogous(base, angle: 30.0);
      expect(analogous.length, equals(3));
      expect(analogous[1], equals(base));

      final leftHsl = analogous[0].toHsl();
      final rightHsl = analogous[2].toHsl();
      expect(leftHsl.h, closeTo(90.0, 1.0));
      expect(rightHsl.h, closeTo(150.0, 1.0));
    });

    test('Split-Complementary calculates 150° and 210° offsets', () {
      const base = ColorRgb(0, 0, 255); // Hue = 240°
      final split = ColorHarmonies.splitComplementary(base);
      expect(split.length, equals(3));

      final h1 = split[1].toHsl().h;
      final h2 = split[2].toHsl().h;
      // (240 + 150) % 360 = 30°
      // (240 + 210) % 360 = 90°
      expect(h1, closeTo(30.0, 1.0));
      expect(h2, closeTo(90.0, 1.0));
    });

    test('Triadic harmony generates equilateral 120° / 240° triangle', () {
      const base = ColorRgb(255, 0, 0); // Hue = 0°
      final tri = ColorHarmonies.triadic(base);
      expect(tri.length, equals(3));
      expect(tri[0], equals(base));

      expect(tri[1].toHsl().h, closeTo(120.0, 1.0)); // Green
      expect(tri[2].toHsl().h, closeTo(240.0, 1.0)); // Blue
    });

    test('Monochromatic harmony varies lightness while fixing hue', () {
      const base = ColorRgb(200, 100, 50);
      final mono = ColorHarmonies.monochromatic(base);
      expect(mono.length, equals(4));

      final baseHue = base.toHsl().h;
      for (final shade in mono) {
        expect(shade.toHsl().h, closeTo(baseHue, 1.5));
      }
      // Lightness should be ordered from dark to light
      expect(mono[0].toHsl().l, lessThan(mono[1].toHsl().l));
      expect(mono[1].toHsl().l, lessThanOrEqualTo(mono[2].toHsl().l));
    });
  });

  group('ColorPalette Persistence & Deterministic Extraction', () {
    test('JSON serialization round-trip succeeds losslessly', () {
      final palette = ColorPalette(
        id: 'pal_01',
        name: 'Cyber Neon',
        colors: const [
          ColorRgb(255, 0, 128),
          ColorRgb(0, 255, 200),
          ColorRgb(30, 20, 60),
        ],
      );

      final json = palette.toJson();
      final restored = ColorPalette.fromJson(json);
      expect(restored, equals(palette));
    });

    test('Hex list import and export round-trip', () {
      final hexList = ['#FF0080', '#00FFC8', '#1E143C'];
      final palette = ColorPalette.fromHexList(
        id: 'hex_pal',
        name: 'Hex Import',
        hexList: hexList,
      );

      expect(palette.toHexList(), equals(hexList));
    });

    test('Median cut extraction extracts K dominant colors deterministically ordered by luminance', () {
      // 10x10 synthetic buffer: top half pure blue (L=29), bottom half pure yellow (L=225)
      final rgba = Uint8List(10 * 10 * 4);
      for (int y = 0; y < 10; y++) {
        for (int x = 0; x < 10; x++) {
          final off = (y * 10 + x) * 4;
          if (y < 5) {
            rgba[off] = 0;
            rgba[off + 1] = 0;
            rgba[off + 2] = 255;
            rgba[off + 3] = 255;
          } else {
            rgba[off] = 255;
            rgba[off + 1] = 255;
            rgba[off + 2] = 0;
            rgba[off + 3] = 255;
          }
        }
      }

      final palette = ColorPalette.extractDominant(
        id: 'test_median_cut',
        name: 'Blue Yellow Test',
        rgbaBytes: rgba,
        width: 10,
        height: 10,
        k: 2,
      );

      expect(palette.colors.length, equals(2));
      // Ascending luminance ordering: Blue (lower lum) must come before Yellow (higher lum)
      expect(
        palette.colors[0].luminance,
        lessThan(palette.colors[1].luminance),
      );
      expect(palette.colors[0].b, greaterThan(150));
      expect(palette.colors[1].r, greaterThan(150));
    });
  });

  group('ColorReplacement Specification Validation', () {
    test('Validates parameters and round-trips via JSON', () {
      const rep = ColorReplacement(
        sourceColor: ColorRgb(255, 0, 0),
        targetColor: ColorRgb(0, 255, 0),
        tolerance: 0.25,
        feather: 0.15,
        preserveLuminance: true,
        strength: 0.85,
      );

      final json = rep.toJson();
      final restored = ColorReplacement.fromJson(json);
      expect(restored, equals(rep));
    });
  });
}
