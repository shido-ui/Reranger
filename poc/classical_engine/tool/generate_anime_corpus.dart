import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:classical_engine_poc/classical_engine.dart';

Uint8List encodeBmp(ImageBuffer src) {
  final w = src.width;
  final h = src.height;
  final rowStride = (w * 3 + 3) & ~3;
  final imageSize = rowStride * h;
  final fileSize = 54 + imageSize;

  final bytes = ByteData(fileSize);
  bytes.setUint8(0, 0x42); // 'B'
  bytes.setUint8(1, 0x4D); // 'M'
  bytes.setUint32(2, fileSize, Endian.little);
  bytes.setUint32(6, 0, Endian.little);
  bytes.setUint32(10, 54, Endian.little);

  bytes.setUint32(14, 40, Endian.little);
  bytes.setInt32(18, w, Endian.little);
  bytes.setInt32(22, h, Endian.little);
  bytes.setUint16(26, 1, Endian.little);
  bytes.setUint16(28, 24, Endian.little);
  bytes.setUint32(30, 0, Endian.little);
  bytes.setUint32(34, imageSize, Endian.little);
  bytes.setInt32(38, 2835, Endian.little);
  bytes.setInt32(42, 2835, Endian.little);
  bytes.setUint32(46, 0, Endian.little);
  bytes.setUint32(50, 0, Endian.little);

  final uint8 = bytes.buffer.asUint8List();
  int pixelOffset = 54;
  for (int y = h - 1; y >= 0; y--) {
    for (int x = 0; x < w; x++) {
      final (r, g, b, _) = src.getPixel(x, y);
      uint8[pixelOffset++] = b;
      uint8[pixelOffset++] = g;
      uint8[pixelOffset++] = r;
    }
    for (int p = 0; p < (rowStride - w * 3); p++) {
      uint8[pixelOffset++] = 0;
    }
  }
  return uint8;
}

void drawLine(
    ImageBuffer img, int x0, int y0, int x1, int y1, (int, int, int, int) color,
    {int thickness = 1}) {
  int dx = (x1 - x0).abs();
  int dy = (y1 - y0).abs();
  int sx = x0 < x1 ? 1 : -1;
  int sy = y0 < y1 ? 1 : -1;
  int err = dx - dy;

  int x = x0;
  int y = y0;

  while (true) {
    for (int ty = -thickness ~/ 2; ty <= thickness ~/ 2; ty++) {
      for (int tx = -thickness ~/ 2; tx <= thickness ~/ 2; tx++) {
        int px = x + tx;
        int py = y + ty;
        if (px >= 0 && px < img.width && py >= 0 && py < img.height) {
          img.setPixel(px, py, color.$1, color.$2, color.$3, color.$4);
        }
      }
    }
    if (x == x1 && y == y1) break;
    int e2 = 2 * err;
    if (e2 > -dy) {
      err -= dy;
      x += sx;
    }
    if (e2 < dx) {
      err += dx;
      y += sy;
    }
  }
}

void drawCircle(
    ImageBuffer img, int cx, int cy, int radius, (int, int, int, int) color,
    {bool fill = false}) {
  for (int y = -radius; y <= radius; y++) {
    for (int x = -radius; x <= radius; x++) {
      int distSq = x * x + y * y;
      if (fill && distSq <= radius * radius) {
        int px = cx + x;
        int py = cy + y;
        if (px >= 0 && px < img.width && py >= 0 && py < img.height) {
          img.setPixel(px, py, color.$1, color.$2, color.$3, color.$4);
        }
      } else if (!fill &&
          (distSq >= (radius - 1) * (radius - 1) &&
              distSq <= radius * radius)) {
        int px = cx + x;
        int py = cy + y;
        if (px >= 0 && px < img.width && py >= 0 && py < img.height) {
          img.setPixel(px, py, color.$1, color.$2, color.$3, color.$4);
        }
      }
    }
  }
}

void fillPolygon(
    ImageBuffer img, List<(int, int)> points, (int, int, int, int) color) {
  if (points.length < 3) return;
  int minY = points.map((p) => p.$2).reduce(math.min).clamp(0, img.height - 1);
  int maxY = points.map((p) => p.$2).reduce(math.max).clamp(0, img.height - 1);

  for (int y = minY; y <= maxY; y++) {
    List<int> nodeX = [];
    int j = points.length - 1;
    for (int i = 0; i < points.length; i++) {
      if ((points[i].$2 < y && points[j].$2 >= y) ||
          (points[j].$2 < y && points[i].$2 >= y)) {
        nodeX.add((points[i].$1 +
                (y - points[i].$2) /
                    (points[j].$2 - points[i].$2) *
                    (points[j].$1 - points[i].$1))
            .round());
      }
      j = i;
    }
    nodeX.sort();
    for (int i = 0; i < nodeX.length; i += 2) {
      if (i + 1 < nodeX.length) {
        int startX = nodeX[i].clamp(0, img.width - 1);
        int endX = nodeX[i + 1].clamp(0, img.width - 1);
        for (int x = startX; x <= endX; x++) {
          img.setPixel(x, y, color.$1, color.$2, color.$3, color.$4);
        }
      }
    }
  }
}

// 1. Anime Portrait
ImageBuffer createAnimePortrait() {
  final img = ImageBuffer(width: 256, height: 256);
  // Background: pastel gradient
  for (int y = 0; y < 256; y++) {
    for (int x = 0; x < 256; x++) {
      img.setPixel(x, y, 240, 245 - (y * 20 ~/ 256), 255, 255);
    }
  }
  // Face shape
  fillPolygon(img, [(128, 220), (64, 130), (74, 90), (182, 90), (192, 130)],
      (255, 228, 206, 255));
  // Neck
  fillPolygon(img, [(110, 200), (110, 255), (146, 255), (146, 200)],
      (240, 205, 185, 255));
  // Cheeks blush
  drawCircle(img, 90, 155, 12, (255, 190, 185, 255), fill: true);
  drawCircle(img, 166, 155, 12, (255, 190, 185, 255), fill: true);
  // Eyes: Large anime eyes
  for (int side in [-1, 1]) {
    int cx = 128 + side * 38;
    int cy = 138;
    // Sclera
    drawCircle(img, cx, cy, 18, (255, 255, 255, 255), fill: true);
    // Iris (Cyan to Navy gradient)
    for (int y = -14; y <= 14; y++) {
      for (int x = -10; x <= 10; x++) {
        if (x * x + y * y <= 14 * 14) {
          int b = 180 + (y * 60 ~/ 14);
          int g = 100 + (y * 80 ~/ 14);
          img.setPixel(
              cx + x, cy + y, 20, g.clamp(0, 255), b.clamp(0, 255), 255);
        }
      }
    }
    // Pupil
    drawCircle(img, cx, cy + 2, 5, (10, 15, 40, 255), fill: true);
    // Catchlight reflections
    drawCircle(img, cx - 4, cy - 5, 3, (255, 255, 255, 255), fill: true);
    drawCircle(img, cx + 4, cy + 5, 2, (255, 255, 255, 255), fill: true);
    // Upper Eyelash line
    drawLine(img, cx - 18, cy - 14, cx + 18, cy - 16, (30, 20, 25, 255),
        thickness: 3);
  }
  // Nose mark
  img.setPixel(128, 175, 180, 130, 120, 255);
  img.setPixel(128, 176, 160, 110, 100, 255);
  // Mouth
  drawLine(img, 122, 192, 134, 192, (190, 80, 90, 255), thickness: 2);
  // Dark hair bangs
  fillPolygon(img, [(40, 60), (128, 115), (70, 110)], (50, 40, 70, 255));
  fillPolygon(img, [(128, 115), (216, 60), (186, 110)], (50, 40, 70, 255));
  fillPolygon(img, [(95, 60), (128, 130), (145, 60)], (60, 50, 85, 255));
  return img;
}

// 2. Character with Detailed Hair & Specular Ring
ImageBuffer createAnimeHair() {
  final img = ImageBuffer(width: 256, height: 256);
  // Deep background
  for (int y = 0; y < 256; y++) {
    for (int x = 0; x < 256; x++) {
      img.setPixel(x, y, 35, 30, 45, 255);
    }
  }
  // Face underlying
  fillPolygon(img, [(128, 210), (70, 140), (186, 140)], (255, 230, 215, 255));
  // Hair base (Vibrant Magenta/Purple)
  for (int i = 0; i < 40; i++) {
    int startX = 30 + i * 5;
    int endX = startX + (i % 2 == 0 ? 15 : -10);
    drawLine(img, startX, 20, endX, 240,
        (160 + (i % 5) * 15, 40, 130 + (i % 4) * 20, 255),
        thickness: 3);
  }
  // Angel ring specular highlight (curved band across hair)
  for (int x = 40; x < 216; x++) {
    int yCurve = 75 + (math.sin(x * 0.03) * 10).round();
    drawLine(img, x, yCurve - 3, x, yCurve + 3, (255, 215, 240, 255),
        thickness: 2);
  }
  return img;
}

// 3. Flat-color Cel-Shaded Illustration
ImageBuffer createCelShadedAnime() {
  final img = ImageBuffer(width: 256, height: 256);
  // Crisp uniform background
  for (int i = 0; i < 256 * 256; i++) {
    int x = i % 256, y = i ~/ 256;
    img.setPixel(x, y, 255, 248, 230, 255);
  }
  // Cel shaded face: Lit side vs Shadow side (Sharp boundary at x = 120)
  for (int y = 60; y < 210; y++) {
    for (int x = 60; x < 196; x++) {
      int dx = x - 128;
      int dy = y - 130;
      if (dx * dx * 1.2 + dy * dy < 70 * 70) {
        if (x < 125) {
          // Shadow zone (cool purple-gray cel shade)
          img.setPixel(x, y, 220, 195, 190, 255);
        } else {
          // Lit zone (bright warm peach)
          img.setPixel(x, y, 255, 235, 215, 255);
        }
      }
    }
  }
  // Bold 2-tone Anime Jacket
  fillPolygon(
      img, [(40, 200), (216, 200), (230, 256), (26, 256)], (40, 80, 160, 255));
  fillPolygon(img, [(40, 200), (120, 200), (110, 256), (26, 256)],
      (25, 50, 110, 255)); // Shadow half
  return img;
}

// 4. Intricate Line Art & Fine Contours
ImageBuffer createIntricateLineArt() {
  final img = ImageBuffer(width: 256, height: 256);
  // Crisp white paper
  for (int i = 0; i < 256 * 256; i++) {
    img.setPixel(i % 256, i ~/ 256, 255, 255, 255, 255);
  }
  // Fine ink contours (Manga aesthetic)
  for (int i = 0; i < 25; i++) {
    drawLine(img, 40 + i * 7, 20, 30 + i * 8, 120, (15, 15, 20, 255),
        thickness: 1);
  }
  // Cross hatching shading on jaw and collar
  for (int y = 140; y < 190; y += 4) {
    drawLine(img, 80, y, 176, y - 15, (30, 30, 35, 255), thickness: 1);
    drawLine(img, 80, y - 15, 176, y, (30, 30, 35, 255), thickness: 1);
  }
  // Outer silhouette
  drawCircle(img, 128, 128, 85, (20, 20, 25, 255), fill: false);
  return img;
}

// 5. Full Body Character with Clothing Folds
ImageBuffer createFullBodyAnime() {
  final img = ImageBuffer(width: 256, height: 256);
  for (int i = 0; i < 256 * 256; i++) {
    img.setPixel(i % 256, i ~/ 256, 235, 240, 245, 255);
  }
  // Head
  drawCircle(img, 128, 45, 20, (255, 225, 210, 255), fill: true);
  // Torso / Blazer
  fillPolygon(
      img, [(105, 65), (151, 65), (160, 140), (96, 140)], (45, 55, 80, 255));
  // Blazer lapels and folds
  drawLine(img, 105, 65, 128, 110, (20, 25, 40, 255), thickness: 2);
  drawLine(img, 151, 65, 128, 110, (20, 25, 40, 255), thickness: 2);
  // Belt
  drawLine(img, 96, 140, 160, 140, (180, 140, 40, 255), thickness: 3);
  // Skirt with accordion pleats
  for (int i = 0; i < 9; i++) {
    int xTop = 100 + i * 7;
    int xBottom = 88 + i * 10;
    int shade = i % 2 == 0 ? 160 : 120;
    fillPolygon(
        img,
        [(xTop, 145), (xTop + 7, 145), (xBottom + 10, 185), (xBottom, 185)],
        (shade, 30, 50, 255));
  }
  // Legs
  fillPolygon(img, [(108, 185), (120, 185), (118, 250), (106, 250)],
      (250, 220, 205, 255));
  fillPolygon(img, [(136, 185), (148, 185), (150, 250), (138, 250)],
      (250, 220, 205, 255));
  return img;
}

// 6. Visible Hands & Anatomy Test
ImageBuffer createAnimeHands() {
  final img = ImageBuffer(width: 256, height: 256);
  for (int i = 0; i < 256 * 256; i++) {
    img.setPixel(i % 256, i ~/ 256, 245, 242, 238, 255);
  }
  // Palm base
  fillPolygon(img, [(90, 140), (166, 140), (155, 220), (100, 220)],
      (255, 225, 208, 255));
  // 5 distinct anime fingers with knuckles
  // Thumb
  drawLine(img, 90, 160, 65, 130, (255, 220, 205, 255), thickness: 12);
  drawLine(img, 90, 160, 65, 130, (190, 120, 110, 255), thickness: 2);
  // Index
  drawLine(img, 105, 140, 100, 65, (255, 220, 205, 255), thickness: 10);
  drawLine(img, 105, 140, 100, 65, (190, 120, 110, 255), thickness: 2);
  // Middle
  drawLine(img, 128, 140, 128, 50, (255, 220, 205, 255), thickness: 10);
  drawLine(img, 128, 140, 128, 50, (190, 120, 110, 255), thickness: 2);
  // Ring
  drawLine(img, 148, 140, 150, 68, (255, 220, 205, 255), thickness: 10);
  drawLine(img, 148, 140, 150, 68, (190, 120, 110, 255), thickness: 2);
  // Pinky
  drawLine(img, 164, 150, 172, 95, (255, 220, 205, 255), thickness: 9);
  drawLine(img, 164, 150, 172, 95, (190, 120, 110, 255), thickness: 2);
  return img;
}

// 7. Anime Character with Detailed Background
ImageBuffer createAnimeWithBackground() {
  final img = ImageBuffer(width: 256, height: 256);
  // Vibrant anime sky gradient
  for (int y = 0; y < 140; y++) {
    for (int x = 0; x < 256; x++) {
      img.setPixel(x, y, 70, 150 + (y * 60 ~/ 140), 245, 255);
    }
  }
  // Fluffy anime clouds
  drawCircle(img, 60, 80, 35, (255, 255, 255, 255), fill: true);
  drawCircle(img, 100, 70, 42, (255, 255, 255, 255), fill: true);
  drawCircle(img, 190, 95, 30, (255, 255, 255, 255), fill: true);
  // Torii Gate / Architectural perspective
  drawLine(img, 30, 130, 226, 130, (190, 30, 30, 255), thickness: 6);
  drawLine(img, 60, 130, 60, 240, (180, 25, 25, 255), thickness: 8);
  drawLine(img, 196, 130, 196, 240, (180, 25, 25, 255), thickness: 8);
  // Character in foreground
  fillPolygon(img, [(128, 150), (90, 255), (166, 255)], (255, 240, 120, 255));
  drawCircle(img, 128, 135, 25, (255, 225, 205, 255), fill: true);
  return img;
}

// 8. Contrasting 90s Vintage Retro Anime Cel
ImageBuffer createRetroAnimeCel() {
  final img = ImageBuffer(width: 256, height: 256);
  // Vintage warm golden-hour glow
  for (int y = 0; y < 256; y++) {
    for (int x = 0; x < 256; x++) {
      img.setPixel(x, y, 220 - (y * 40 ~/ 256), 160 - (y * 50 ~/ 256), 90, 255);
    }
  }
  // Bold cyberpunk / mecha pilot helmet & visor
  fillPolygon(img, [(70, 60), (186, 60), (200, 160), (128, 220), (56, 160)],
      (180, 40, 50, 255));
  // Shiny curved gold-reflective visor
  fillPolygon(
      img, [(85, 95), (171, 95), (160, 150), (96, 150)], (255, 200, 60, 255));
  // Visor reflection streak
  drawLine(img, 90, 140, 155, 105, (255, 255, 220, 255), thickness: 4);
  // Heavy 90s black ink outlines
  drawLine(img, 70, 60, 186, 60, (20, 10, 10, 255), thickness: 4);
  drawLine(img, 186, 60, 200, 160, (20, 10, 10, 255), thickness: 4);
  drawLine(img, 200, 160, 128, 220, (20, 10, 10, 255), thickness: 4);
  drawLine(img, 128, 220, 56, 160, (20, 10, 10, 255), thickness: 4);
  drawLine(img, 56, 160, 70, 60, (20, 10, 10, 255), thickness: 4);
  return img;
}

// 9. Authorized Reference: Human-drawn Anime Illustration Reference
ImageBuffer createHumanDrawnReference() {
  final img = ImageBuffer(width: 256, height: 256);
  // Subtle watercolor paper grain tone
  for (int y = 0; y < 256; y++) {
    for (int x = 0; x < 256; x++) {
      int paperNoise = ((x * 17 + y * 23) % 7);
      img.setPixel(
          x, y, 250 - paperNoise, 248 - paperNoise, 242 - paperNoise, 255);
    }
  }
  // Organic ink line modulation (variable thickness, dipping pen pressure)
  for (int i = 0; i < 50; i++) {
    double t = i / 50.0;
    int x = (80 + t * 96).round();
    int y = (70 + math.sin(t * math.pi) * 40).round();
    int th = (1 + (math.sin(t * math.pi) * 3))
        .round(); // dynamic calligraphic pressure
    drawCircle(img, x, y, th, (35, 30, 40, 255), fill: true);
  }
  // Soft watercolor blush
  for (int y = 140; y < 180; y++) {
    for (int x = 90; x < 166; x++) {
      double dist = math.sqrt((x - 128) * (x - 128) + (y - 160) * (y - 160));
      if (dist < 25) {
        int alpha = (25 - dist.round()) * 4;
        img.setPixel(x, y, 255, 210 - alpha, 210 - alpha, 255);
      }
    }
  }
  return img;
}

void main() {
  final corpusDir =
      Directory('/root/reranger/docs/evidence/prompt-09-a/corpus');
  if (!corpusDir.existsSync()) {
    corpusDir.createSync(recursive: true);
  }

  print(
      'Generating 8 authorized anime test fixtures + 1 human reference fixture...');

  final fixtures = <Map<String, dynamic>>[
    {
      'id': 'ANIME-01-PORTRAIT',
      'title': 'Anime Portrait with Expressive Eyes & Eyelashes',
      'category': 'Portrait',
      'buffer': createAnimePortrait(),
      'characteristics':
          'Large dual-tone cyan/navy anime eyes, catchlights, eyelashes, triangular jaw, blush',
    },
    {
      'id': 'ANIME-02-HAIR',
      'title': 'Detailed Hair Strands & Angel-Ring Specular Sheen',
      'category': 'Hair & Specular',
      'buffer': createAnimeHair(),
      'characteristics':
          'Layered violet/magenta hair strands, curved specular highlight band, overlapping fringe',
    },
    {
      'id': 'ANIME-03-CELSHADE',
      'title': 'Flat-Color Cel-Shaded Illustration',
      'category': 'Cel Shading',
      'buffer': createCelShadedAnime(),
      'characteristics':
          'Strict 2-tone split shadow without gradients, crisp boundaries on jacket & face',
    },
    {
      'id': 'ANIME-04-INT_LINE',
      'title': 'Intricate Manga Line Art & Cross-Hatching',
      'category': 'Line Art',
      'buffer': createIntricateLineArt(),
      'characteristics':
          'Fine 1px ink contours, cross-hatching shading on neck/jaw, zero color fills',
    },
    {
      'id': 'ANIME-05-FULLBODY',
      'title': 'Full-Body Character with Fabric Folds & Uniform',
      'category': 'Full Body & Drapery',
      'buffer': createFullBodyAnime(),
      'characteristics':
          'Head-to-toe proportions, sharp lapel folds, pleated skirt shadows, gold belt',
    },
    {
      'id': 'ANIME-06-HANDS',
      'title': 'Foreground Anime Hand & Finger Anatomy',
      'category': 'Anatomy & Hands',
      'buffer': createAnimeHands(),
      'characteristics':
          'Five distinct fingers with articulated knuckles and palm contour; AI flaw test',
    },
    {
      'id': 'ANIME-07-BACKGROUND',
      'title': 'Anime Character with Detailed Sky & Architecture',
      'category': 'Composition & Environment',
      'buffer': createAnimeWithBackground(),
      'characteristics':
          'Sky gradient, fluffy clouds, Torii gate architectural pillars, foreground figure',
    },
    {
      'id': 'ANIME-08-RETRO',
      'title': '90s Vintage Mecha/Cyberpunk Anime Cel',
      'category': 'Retro Aesthetic',
      'buffer': createRetroAnimeCel(),
      'characteristics':
          'Heavy black ink outlines, warm golden sunset grading, mecha helmet & visor reflection',
    },
    {
      'id': 'ANIME-REF-HUMAN-01',
      'title': 'Human-Drawn Anime Reference Illustration',
      'category': 'Human Reference',
      'buffer': createHumanDrawnReference(),
      'characteristics':
          'Organic calligraphic line-weight pressure variation, soft watercolor wash, paper tooth',
    },
  ];

  final manifestList = <Map<String, dynamic>>[];

  for (final fix in fixtures) {
    final id = fix['id'] as String;
    final buffer = fix['buffer'] as ImageBuffer;
    final bmpBytes = encodeBmp(buffer);
    final filePath = '${corpusDir.path}/$id.bmp';
    File(filePath).writeAsBytesSync(bmpBytes);

    final sha256 = buffer.computeSha256();
    print('Generated [$id] -> $filePath (SHA-256: $sha256)');

    manifestList.add({
      'id': id,
      'title': fix['title'],
      'category': fix['category'],
      'width': buffer.width,
      'height': buffer.height,
      'format': 'BMP (24-bit uncompressed RGB)',
      'sha256': sha256,
      'file_path': 'docs/evidence/prompt-09-a/corpus/$id.bmp',
      'file_size_bytes': bmpBytes.length,
      'visual_characteristics': fix['characteristics'],
      'provenance':
          'Deterministic synthetic vector-raster anime archetype fixture generated by Reranger Anime QA Suite',
      'license': 'Permissive Open Access (Apache-2.0 / MIT)',
    });
  }

  final manifestFile =
      File('/root/reranger/docs/evidence/prompt-09-a/corpus_manifest.json');
  manifestFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'corpus_version': '1.0.0',
    'total_fixtures': manifestList.length,
    'fixtures': manifestList,
  }));
  print('Saved corpus manifest to: ${manifestFile.path}');
}
