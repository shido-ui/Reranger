import 'dart:math' as math;
import 'dart:typed_data';

/// Immutable 32-bit RGBA color representation with color-science utilities.
class ColorRgb {
  final int r;
  final int g;
  final int b;
  final int a;

  const ColorRgb(this.r, this.g, this.b, [this.a = 255])
    : assert(r >= 0 && r <= 255, 'R out of [0, 255]'),
      assert(g >= 0 && g <= 255, 'G out of [0, 255]'),
      assert(b >= 0 && b <= 255, 'B out of [0, 255]'),
      assert(a >= 0 && a <= 255, 'A out of [0, 255]');

  static const ColorRgb black = ColorRgb(0, 0, 0);
  static const ColorRgb white = ColorRgb(255, 255, 255);
  static const ColorRgb transparent = ColorRgb(0, 0, 0, 0);

  /// BT.601 integer luminance: (299*R + 587*G + 114*B) / 1000 in [0, 255].
  int get luminance => (299 * r + 587 * g + 114 * b) ~/ 1000;

  /// Normalized luminance in [0.0, 1.0].
  double get normalizedLuminance => luminance / 255.0;

  /// Hex string representation, e.g. '#FF5733' (or '#AARRGGBB' if alpha < 255).
  String toHex({bool includeAlpha = false}) {
    final rHex = r.toRadixString(16).padLeft(2, '0').toUpperCase();
    final gHex = g.toRadixString(16).padLeft(2, '0').toUpperCase();
    final bHex = b.toRadixString(16).padLeft(2, '0').toUpperCase();
    if (includeAlpha || a < 255) {
      final aHex = a.toRadixString(16).padLeft(2, '0').toUpperCase();
      return '#$aHex$rHex$gHex$bHex';
    }
    return '#$rHex$gHex$bHex';
  }

  /// Parses hex color strings like '#RGB', '#RRGGBB', or '#AARRGGBB'.
  factory ColorRgb.fromHex(String hex) {
    String cleanHex = hex.trim().replaceAll('#', '');
    if (cleanHex.length == 3) {
      final rStr = cleanHex[0] * 2;
      final gStr = cleanHex[1] * 2;
      final bStr = cleanHex[2] * 2;
      return ColorRgb(
        int.parse(rStr, radix: 16),
        int.parse(gStr, radix: 16),
        int.parse(bStr, radix: 16),
      );
    } else if (cleanHex.length == 6) {
      return ColorRgb(
        int.parse(cleanHex.substring(0, 2), radix: 16),
        int.parse(cleanHex.substring(2, 4), radix: 16),
        int.parse(cleanHex.substring(4, 6), radix: 16),
      );
    } else if (cleanHex.length == 8) {
      final a = int.parse(cleanHex.substring(0, 2), radix: 16);
      final r = int.parse(cleanHex.substring(2, 4), radix: 16);
      final g = int.parse(cleanHex.substring(4, 6), radix: 16);
      final b = int.parse(cleanHex.substring(6, 8), radix: 16);
      return ColorRgb(r, g, b, a);
    }
    throw FormatException('Invalid hex color format: "$hex"');
  }

  /// Normalized Euclidean color distance in [0.0, 1.0].
  double normalizedDistanceTo(ColorRgb other) {
    final dr = (r - other.r) / 255.0;
    final dg = (g - other.g) / 255.0;
    final db = (b - other.b) / 255.0;
    return math.sqrt((dr * dr + dg * dg + db * db) / 3.0);
  }

  /// Converts this RGB color to HSL representation.
  ColorHsl toHsl() {
    final rf = r / 255.0;
    final gf = g / 255.0;
    final bf = b / 255.0;

    final maxVal = math.max(rf, math.max(gf, bf));
    final minVal = math.min(rf, math.min(gf, bf));
    final delta = maxVal - minVal;

    double h = 0.0;
    double s = 0.0;
    final l = (maxVal + minVal) / 2.0;

    if (delta > 1e-6) {
      s = (l > 0.5)
          ? (delta / (2.0 - maxVal - minVal))
          : (delta / (maxVal + minVal));

      if (maxVal == rf) {
        h = ((gf - bf) / delta) + (gf < bf ? 6.0 : 0.0);
      } else if (maxVal == gf) {
        h = ((bf - rf) / delta) + 2.0;
      } else {
        h = ((rf - gf) / delta) + 4.0;
      }
      h *= 60.0;
    }

    return ColorHsl(h, s.clamp(0.0, 1.0), l.clamp(0.0, 1.0), a);
  }

  Map<String, dynamic> toJson() => {
    'r': r,
    'g': g,
    'b': b,
    'a': a,
    'hex': toHex(),
  };

  factory ColorRgb.fromJson(Map<String, dynamic> json) => ColorRgb(
    json['r'] as int,
    json['g'] as int,
    json['b'] as int,
    (json['a'] as int?) ?? 255,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorRgb &&
          runtimeType == other.runtimeType &&
          r == other.r &&
          g == other.g &&
          b == other.b &&
          a == other.a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'ColorRgb($r, $g, $b, $a | ${toHex()})';
}

/// Cylindrical HSL color representation.
class ColorHsl {
  final double h; // Hue in [0.0, 360.0)
  final double s; // Saturation in [0.0, 1.0]
  final double l; // Lightness in [0.0, 1.0]
  final int a; // Alpha in [0, 255]

  const ColorHsl(double h, this.s, this.l, [this.a = 255])
    : h = (h % 360.0 + 360.0) % 360.0,
      assert(s >= 0.0 && s <= 1.0001, 'S out of [0.0, 1.0]'),
      assert(l >= 0.0 && l <= 1.0001, 'L out of [0.0, 1.0]'),
      assert(a >= 0 && a <= 255, 'A out of [0, 255]');

  /// Converts this HSL color to RGB.
  ColorRgb toRgb() {
    if (s <= 1e-6) {
      final gray = (l * 255.0).round().clamp(0, 255);
      return ColorRgb(gray, gray, gray, a);
    }

    final q = l < 0.5 ? l * (1.0 + s) : l + s - (l * s);
    final p = 2.0 * l - q;
    final hk = h / 360.0;

    double hueToRgb(double t) {
      double tc = t;
      if (tc < 0.0) tc += 1.0;
      if (tc > 1.0) tc -= 1.0;
      if (tc < 1.0 / 6.0) return p + (q - p) * 6.0 * tc;
      if (tc < 1.0 / 2.0) return q;
      if (tc < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - tc) * 6.0;
      return p;
    }

    final rf = (hueToRgb(hk + 1.0 / 3.0) * 255.0).round().clamp(0, 255);
    final gf = (hueToRgb(hk) * 255.0).round().clamp(0, 255);
    final bf = (hueToRgb(hk - 1.0 / 3.0) * 255.0).round().clamp(0, 255);

    return ColorRgb(rf, gf, bf, a);
  }

  ColorHsl withHue(double newHue) => ColorHsl(newHue, s, l, a);
  ColorHsl withSaturation(double newSat) =>
      ColorHsl(h, newSat.clamp(0.0, 1.0), l, a);
  ColorHsl withLightness(double newLight) =>
      ColorHsl(h, s, newLight.clamp(0.0, 1.0), a);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorHsl &&
          runtimeType == other.runtimeType &&
          (h - other.h).abs() < 1e-4 &&
          (s - other.s).abs() < 1e-4 &&
          (l - other.l).abs() < 1e-4 &&
          a == other.a;

  @override
  int get hashCode =>
      Object.hash((h * 10).round(), (s * 100).round(), (l * 100).round(), a);

  @override
  String toString() =>
      'ColorHsl(H: ${h.toStringAsFixed(1)}°, S: ${(s * 100).toStringAsFixed(1)}%, L: ${(l * 100).toStringAsFixed(1)}%)';
}

/// Color harmony relationships generating artistic palettes from an anchor color.
class ColorHarmonies {
  const ColorHarmonies._();

  /// Complementary harmony: opposite color (180°).
  static List<ColorRgb> complementary(ColorRgb base) {
    final hsl = base.toHsl();
    final comp = hsl.withHue(hsl.h + 180.0).toRgb();
    return [base, comp];
  }

  /// Analogous harmony: neighboring colors (±30°).
  static List<ColorRgb> analogous(ColorRgb base, {double angle = 30.0}) {
    final hsl = base.toHsl();
    final left = hsl.withHue(hsl.h - angle).toRgb();
    final right = hsl.withHue(hsl.h + angle).toRgb();
    return [left, base, right];
  }

  /// Split-Complementary harmony: base and two colors adjacent to its complement (150° and 210°).
  static List<ColorRgb> splitComplementary(ColorRgb base) {
    final hsl = base.toHsl();
    final split1 = hsl.withHue(hsl.h + 150.0).toRgb();
    final split2 = hsl.withHue(hsl.h + 210.0).toRgb();
    return [base, split1, split2];
  }

  /// Triadic harmony: three evenly spaced colors (120° and 240°).
  static List<ColorRgb> triadic(ColorRgb base) {
    final hsl = base.toHsl();
    final t1 = hsl.withHue(hsl.h + 120.0).toRgb();
    final t2 = hsl.withHue(hsl.h + 240.0).toRgb();
    return [base, t1, t2];
  }

  /// Tetradic (Square / Rectangle) harmony: four evenly spaced colors (90°, 180°, 270°).
  static List<ColorRgb> tetradic(ColorRgb base) {
    final hsl = base.toHsl();
    final c1 = hsl.withHue(hsl.h + 90.0).toRgb();
    final c2 = hsl.withHue(hsl.h + 180.0).toRgb();
    final c3 = hsl.withHue(hsl.h + 270.0).toRgb();
    return [base, c1, c2, c3];
  }

  /// Monochromatic harmony: variations in lightness and saturation at identical hue.
  static List<ColorRgb> monochromatic(ColorRgb base) {
    final hsl = base.toHsl();
    final dark = hsl.withLightness(hsl.l * 0.40).toRgb();
    final midDark = hsl.withLightness(hsl.l * 0.70).toRgb();
    final light = hsl
        .withLightness(math.min(1.0, hsl.l * 1.30))
        .withSaturation(hsl.s * 0.85)
        .toRgb();
    return [dark, midDark, base, light];
  }
}

/// Named color palette containing an ordered sequence of colors with import/export capabilities.
class ColorPalette {
  final String id;
  final String name;
  final List<ColorRgb> colors;

  const ColorPalette({
    required this.id,
    required this.name,
    required this.colors,
  }) : assert(colors.length > 0, 'Palette must contain at least one color');

  List<String> toHexList() => colors.map((c) => c.toHex()).toList();

  static ColorPalette fromHexList({
    required String id,
    required String name,
    required List<String> hexList,
  }) {
    if (hexList.isEmpty) {
      throw const FormatException('Hex list cannot be empty');
    }
    final colors = hexList.map((h) => ColorRgb.fromHex(h)).toList();
    return ColorPalette(id: id, name: name, colors: colors);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'colors': colors.map((c) => c.toJson()).toList(),
  };

  factory ColorPalette.fromJson(Map<String, dynamic> json) {
    final rawColors = (json['colors'] as List)
        .map((e) => ColorRgb.fromJson(e as Map<String, dynamic>))
        .toList();
    return ColorPalette(
      id: json['id'] as String,
      name: json['name'] as String,
      colors: rawColors,
    );
  }

  /// Deterministic Median Cut palette extraction from raw RGBA byte buffer.
  /// Sorts by ascending luminance with RGB tie-breaking.
  static ColorPalette extractDominant({
    required String id,
    required String name,
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    int k = 5,
  }) {
    final totalPixels = width * height;
    if (totalPixels <= 0 || rgbaBytes.length < totalPixels * 4) {
      return ColorPalette(
        id: id,
        name: name,
        colors: const [ColorRgb(128, 128, 128)],
      );
    }

    final samples = <(int, int, int)>[];
    final step = (totalPixels > 25000) ? (totalPixels ~/ 25000) : 1;

    for (int i = 0; i < totalPixels; i += step) {
      final offset = i * 4;
      final a = rgbaBytes[offset + 3];
      // Exclude fully transparent pixels from dominant palette extraction
      if (a < 32) continue;
      samples.add((
        rgbaBytes[offset],
        rgbaBytes[offset + 1],
        rgbaBytes[offset + 2],
      ));
    }

    if (samples.isEmpty) {
      return ColorPalette(
        id: id,
        name: name,
        colors: const [ColorRgb(128, 128, 128)],
      );
    }

    final rawBoxes = _medianCut(samples, math.max(1, k));

    // Sort by ascending luminance with RGB tie-breaking
    rawBoxes.sort((a, b) {
      final lumA = 299 * a.$1 + 587 * a.$2 + 114 * a.$3;
      final lumB = 299 * b.$1 + 587 * b.$2 + 114 * b.$3;
      if (lumA != lumB) return lumA.compareTo(lumB);
      if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
      if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
      return a.$3.compareTo(b.$3);
    });

    final extracted = rawBoxes.map((c) => ColorRgb(c.$1, c.$2, c.$3)).toList();

    return ColorPalette(id: id, name: name, colors: extracted);
  }

  static List<(int, int, int)> _medianCut(List<(int, int, int)> colors, int k) {
    if (colors.isEmpty) return const [(128, 128, 128)];
    final boxes = <_ColorBox>[_ColorBox(colors)];

    while (boxes.length < k) {
      int bestIdx = -1;
      int maxRange = -1;
      for (int i = 0; i < boxes.length; i++) {
        if (boxes[i].colors.length > 1) {
          boxes[i].computeRange();
          if (boxes[i].range > maxRange) {
            maxRange = boxes[i].range;
            bestIdx = i;
          }
        }
      }
      if (bestIdx == -1 || maxRange <= 0) break;

      final target = boxes.removeAt(bestIdx);
      final (b1, b2) = target.split();
      boxes.add(b1);
      boxes.add(b2);
    }

    return boxes.map((b) => b.averageColor()).toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorPalette &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          _colorsEqual(colors, other.colors);

  @override
  int get hashCode => Object.hash(id, name, colors.length);

  static bool _colorsEqual(List<ColorRgb> a, List<ColorRgb> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _ColorBox {
  final List<(int, int, int)> colors;
  int range = 0;
  int channel = 0; // 0=R, 1=G, 2=B

  _ColorBox(this.colors);

  void computeRange() {
    int minR = 255, maxR = 0;
    int minG = 255, maxG = 0;
    int minB = 255, maxB = 0;

    for (final c in colors) {
      if (c.$1 < minR) minR = c.$1;
      if (c.$1 > maxR) maxR = c.$1;
      if (c.$2 < minG) minG = c.$2;
      if (c.$2 > maxG) maxG = c.$2;
      if (c.$3 < minB) minB = c.$3;
      if (c.$3 > maxB) maxB = c.$3;
    }

    final diffR = maxR - minR;
    final diffG = maxG - minG;
    final diffB = maxB - minB;

    if (diffR >= diffG && diffR >= diffB) {
      channel = 0;
      range = diffR;
    } else if (diffG >= diffR && diffG >= diffB) {
      channel = 1;
      range = diffG;
    } else {
      channel = 2;
      range = diffB;
    }
  }

  (_ColorBox, _ColorBox) split() {
    if (channel == 0) {
      colors.sort((a, b) => a.$1.compareTo(b.$1));
    } else if (channel == 1) {
      colors.sort((a, b) => a.$2.compareTo(b.$2));
    } else {
      colors.sort((a, b) => a.$3.compareTo(b.$3));
    }

    final mid = colors.length ~/ 2;
    return (_ColorBox(colors.sublist(0, mid)), _ColorBox(colors.sublist(mid)));
  }

  (int, int, int) averageColor() {
    if (colors.isEmpty) return (128, 128, 128);
    int sumR = 0, sumG = 0, sumB = 0;
    for (final c in colors) {
      sumR += c.$1;
      sumG += c.$2;
      sumB += c.$3;
    }
    final count = colors.length;
    return (
      (sumR / count).round().clamp(0, 255),
      (sumG / count).round().clamp(0, 255),
      (sumB / count).round().clamp(0, 255),
    );
  }
}

/// Declarative specification for a single color remapping operation.
class ColorReplacement {
  final ColorRgb sourceColor;
  final ColorRgb targetColor;
  final double tolerance; // Distance threshold in [0.0, 1.0]
  final double feather; // Soft edge feathering in [0.0, 1.0]
  final bool
  preserveLuminance; // Whether to isolate chrominance and preserve luma
  final double strength; // Effect intensity in [0.0, 1.0]

  const ColorReplacement({
    required this.sourceColor,
    required this.targetColor,
    this.tolerance = 0.20,
    this.feather = 0.10,
    this.preserveLuminance = true,
    this.strength = 1.0,
  }) : assert(
         tolerance >= 0.0 && tolerance <= 1.0,
         'Tolerance out of [0.0, 1.0]',
       ),
       assert(feather >= 0.0 && feather <= 1.0, 'Feather out of [0.0, 1.0]'),
       assert(strength >= 0.0 && strength <= 1.0, 'Strength out of [0.0, 1.0]');

  ColorReplacement copyWith({
    ColorRgb? sourceColor,
    ColorRgb? targetColor,
    double? tolerance,
    double? feather,
    bool? preserveLuminance,
    double? strength,
  }) {
    return ColorReplacement(
      sourceColor: sourceColor ?? this.sourceColor,
      targetColor: targetColor ?? this.targetColor,
      tolerance: tolerance ?? this.tolerance,
      feather: feather ?? this.feather,
      preserveLuminance: preserveLuminance ?? this.preserveLuminance,
      strength: strength ?? this.strength,
    );
  }

  Map<String, dynamic> toJson() => {
    'sourceColor': sourceColor.toJson(),
    'targetColor': targetColor.toJson(),
    'tolerance': tolerance,
    'feather': feather,
    'preserveLuminance': preserveLuminance,
    'strength': strength,
  };

  factory ColorReplacement.fromJson(Map<String, dynamic> json) {
    return ColorReplacement(
      sourceColor: ColorRgb.fromJson(
        json['sourceColor'] as Map<String, dynamic>,
      ),
      targetColor: ColorRgb.fromJson(
        json['targetColor'] as Map<String, dynamic>,
      ),
      tolerance: (json['tolerance'] as num?)?.toDouble() ?? 0.20,
      feather: (json['feather'] as num?)?.toDouble() ?? 0.10,
      preserveLuminance: json['preserveLuminance'] as bool? ?? true,
      strength: (json['strength'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorReplacement &&
          runtimeType == other.runtimeType &&
          sourceColor == other.sourceColor &&
          targetColor == other.targetColor &&
          (tolerance - other.tolerance).abs() < 1e-4 &&
          (feather - other.feather).abs() < 1e-4 &&
          preserveLuminance == other.preserveLuminance &&
          (strength - other.strength).abs() < 1e-4;

  @override
  int get hashCode => Object.hash(
    sourceColor,
    targetColor,
    (tolerance * 100).round(),
    preserveLuminance,
    (strength * 100).round(),
  );
}
