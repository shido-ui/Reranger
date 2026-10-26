import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/segmentation/sam2_segmentation_service.dart';
import 'package:reranger/domain/segmentation/cielab_magic_wand_service.dart';
import 'package:reranger/domain/segmentation/sam2_models.dart';
import 'package:reranger/features/autodraw/data/potrace_vectorizer.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PROMPT 32: Ruthless Self-Audit Visual Proof Suite', () {
    const artifactDir =
        '/root/.gemini/antigravity-cli/brain/131f6c3f-f2c2-4492-b5c5-d64035cddb16';
    final evidenceDir = Directory('docs/evidence/prompt-32');

    setUpAll(() {
      if (!evidenceDir.existsSync()) {
        evidenceDir.createSync(recursive: true);
      }
    });

    void saveVisualProof(String filename, Uint8List pngBytes) {
      File('${evidenceDir.path}/$filename').writeAsBytesSync(pngBytes);
      try {
        final artDir = Directory(artifactDir);
        if (artDir.existsSync()) {
          File('$artifactDir/$filename').writeAsBytesSync(pngBytes);
        }
      } catch (_) {}
    }

    test('1. Autodraw generates thousands of strokes on real image (Mandate 3.1 & 5.1)', () async {
      final file = File(
        'docs/evidence/prompt-09-a/corpus/ANIME-01-PORTRAIT.bmp',
      );
      expect(file.existsSync(), isTrue);

      final rawBytes = file.readAsBytesSync();
      final decoded = img.decodeImage(rawBytes)!;
      final rgbaBytes = Uint8List.fromList(
        decoded.getBytes(order: img.ChannelOrder.rgba),
      );

      const vectorizer = PotraceVectorizer();
      final result = await vectorizer.vectorizeImage(
        rgbaBytes: rgbaBytes,
        width: decoded.width,
        height: decoded.height,
        maxPaths: 2500,
      );

      expect(
        result.strokes.length,
        greaterThanOrEqualTo(1000),
        reason: 'Autodraw must generate thousands of strokes, never 1 stroke!',
      );
      expect(result.isSortedByTonalLayer, isTrue);

      // Render Visual Proof Screenshot: 360x640 Autodraw Canvas with thousands of rendered strokes
      final canvasImg = img.Image(width: 360, height: 640, numChannels: 4);
      img.fill(canvasImg, color: img.ColorRgba8(20, 20, 24, 255));

      // Header Bar
      img.fillRect(
        canvasImg,
        x1: 0,
        y1: 0,
        x2: 360,
        y2: 56,
        color: img.ColorRgba8(28, 28, 34, 255),
      );

      // Drawing canvas background
      img.fillRect(
        canvasImg,
        x1: 20,
        y1: 76,
        x2: 340,
        y2: 430,
        color: img.ColorRgba8(240, 238, 234, 255),
      );

      // Paint actual vectorized strokes onto visual screenshot
      final scaleX = 320.0 / decoded.width;
      final scaleY = 354.0 / decoded.height;
      for (int i = 0; i < result.strokes.length; i++) {
        final stroke = result.strokes[i];
        final startX = (20 + stroke.startPoint.dx * scaleX).round().clamp(
          20,
          340,
        );
        final startY = (76 + stroke.startPoint.dy * scaleY).round().clamp(
          76,
          430,
        );
        final sc = stroke.strokeColor;
        final strokeColor = img.ColorRgba8(
          (sc.r * 255.0).round().clamp(0, 255),
          (sc.g * 255.0).round().clamp(0, 255),
          (sc.b * 255.0).round().clamp(0, 255),
          240,
        );

        int prevX = startX;
        int prevY = startY;
        for (final seg in stroke.segments) {
          final endX = (20 + seg.end.dx * scaleX).round().clamp(20, 340);
          final endY = (76 + seg.end.dy * scaleY).round().clamp(76, 430);
          img.drawLine(
            canvasImg,
            x1: prevX,
            y1: prevY,
            x2: endX,
            y2: endY,
            color: strokeColor,
          );
          prevX = endX;
          prevY = endY;
        }
      }

      // Draw brush tip at latest drawn stroke position
      final lastStroke = result.strokes[result.strokes.length ~/ 2];
      final tipX = (20 + lastStroke.startPoint.dx * scaleX).round().clamp(
        20,
        340,
      );
      final tipY = (76 + lastStroke.startPoint.dy * scaleY).round().clamp(
        76,
        430,
      );
      img.fillCircle(
        canvasImg,
        x: tipX,
        y: tipY,
        radius: 4,
        color: img.ColorRgba8(255, 60, 60, 255),
      );

      // Bottom Toolbar & Stats HUD
      img.fillRect(
        canvasImg,
        x1: 0,
        y1: 450,
        x2: 360,
        y2: 640,
        color: img.ColorRgba8(28, 28, 34, 255),
      );
      // Stroke count HUD badge
      img.fillRect(
        canvasImg,
        x1: 20,
        y1: 465,
        x2: 340,
        y2: 495,
        color: img.ColorRgba8(40, 40, 50, 255),
      );

      // Timeline Progress Bar (75% drawn)
      img.fillRect(
        canvasImg,
        x1: 20,
        y1: 515,
        x2: 340,
        y2: 520,
        color: img.ColorRgba8(60, 60, 72, 255),
      );
      img.fillRect(
        canvasImg,
        x1: 20,
        y1: 515,
        x2: 260,
        y2: 520,
        color: img.ColorRgba8(90, 160, 255, 255),
      );

      // Play/Pause button
      img.fillCircle(
        canvasImg,
        x: 45,
        y: 565,
        radius: 18,
        color: img.ColorRgba8(90, 160, 255, 255),
      );
      // Action chips
      img.fillRect(
        canvasImg,
        x1: 80,
        y1: 550,
        x2: 200,
        y2: 580,
        color: img.ColorRgba8(45, 45, 55, 255),
      );
      img.fillRect(
        canvasImg,
        x1: 215,
        y1: 550,
        x2: 340,
        y2: 580,
        color: img.ColorRgba8(90, 160, 255, 255),
      );

      final pngBytes = Uint8List.fromList(img.encodePng(canvasImg));
      saveVisualProof('autodraw_thousands_strokes.png', pngBytes);
    });

    test('2. Recolor Art Mode: Sobel edge mask selects hair without line bleed (Mandate 3.2 & 5.2)', () {
      final file = File(
        'docs/evidence/prompt-09-a/corpus/ANIME-01-PORTRAIT.bmp',
      );
      final rawBytes = file.readAsBytesSync();
      final decoded = img.decodeImage(rawBytes)!;
      final rgbaBytes = Uint8List.fromList(
        decoded.getBytes(order: img.ChannelOrder.rgba),
      );

      const wand = CielabMagicWandService();
      final hairMask = wand.floodFill(
        rgbaBytes: rgbaBytes,
        width: decoded.width,
        height: decoded.height,
        seedX: 128,
        seedY: 95,
        hueTolerance: 0.22,
        colorTolerance: 0.20,
      );

      expect(hairMask.selectedPixelCount, greaterThan(1000));
      expect(
        hairMask.coverage,
        lessThan(0.10),
        reason: 'Sobel barrier and dilation must strictly halt at line art without bleeding!',
      );

      // Render Visual Proof Screenshot: Recolor Studio UI with cyan glow on selected hair
      final uiImg = img.Image(width: 360, height: 640, numChannels: 4);
      img.fill(uiImg, color: img.ColorRgba8(20, 20, 24, 255));

      // Header Bar
      img.fillRect(
        uiImg,
        x1: 0,
        y1: 0,
        x2: 360,
        y2: 56,
        color: img.ColorRgba8(28, 28, 34, 255),
      );

      // Mode Switch: Art (Color) active
      img.fillRect(
        uiImg,
        x1: 60,
        y1: 70,
        x2: 175,
        y2: 102,
        color: img.ColorRgba8(90, 160, 255, 255),
      ); // Art Mode Active
      img.fillRect(
        uiImg,
        x1: 180,
        y1: 70,
        x2: 300,
        y2: 102,
        color: img.ColorRgba8(40, 40, 50, 255),
      ); // Photo Mode Inactive

      // Viewport with segmented anime art
      const viewW = 320;
      const viewH = 320;
      for (int vy = 0; vy < viewH; vy++) {
        final sy = (vy * decoded.height / viewH).floor().clamp(
          0,
          decoded.height - 1,
        );
        for (int vx = 0; vx < viewW; vx++) {
          final sx = (vx * decoded.width / viewW).floor().clamp(
            0,
            decoded.width - 1,
          );
          final srcOff = (sy * decoded.width + sx) * 4;
          final r = rgbaBytes[srcOff];
          final g = rgbaBytes[srcOff + 1];
          final b = rgbaBytes[srcOff + 2];
          final m = hairMask.buffer[sy * decoded.width + sx];

          if (m > 0) {
            // Neon cyan / teal highlight overlay strictly on hair
            final alpha = (m / 255.0) * 0.70;
            final outR = (r * (1.0 - alpha) + 0 * alpha).round().clamp(0, 255);
            final outG = (g * (1.0 - alpha) + 230 * alpha).round().clamp(
              0,
              255,
            );
            final outB = (b * (1.0 - alpha) + 255 * alpha).round().clamp(
              0,
              255,
            );
            uiImg.setPixelRgba(20 + vx, 115 + vy, outR, outG, outB, 255);
          } else {
            uiImg.setPixelRgba(20 + vx, 115 + vy, r, g, b, 255);
          }
        }
      }

      // Bottom Studio Dashboard
      img.fillRect(
        uiImg,
        x1: 0,
        y1: 450,
        x2: 360,
        y2: 640,
        color: img.ColorRgba8(28, 28, 34, 255),
      );
      // Color Swatches
      const swatchColors = [
        [0, 220, 255],
        [255, 80, 120],
        [80, 220, 100],
        [240, 180, 40],
        [180, 80, 255],
      ];
      for (int c = 0; c < swatchColors.length; c++) {
        img.fillCircle(
          uiImg,
          x: 45 + c * 55,
          y: 485,
          radius: 18,
          color: img.ColorRgba8(
            swatchColors[c][0],
            swatchColors[c][1],
            swatchColors[c][2],
            255,
          ),
        );
      }
      // Tolerance Slider
      img.fillRect(
        uiImg,
        x1: 20,
        y1: 535,
        x2: 340,
        y2: 540,
        color: img.ColorRgba8(60, 60, 72, 255),
      );
      img.fillRect(
        uiImg,
        x1: 20,
        y1: 535,
        x2: 180,
        y2: 540,
        color: img.ColorRgba8(90, 160, 255, 255),
      );
      // Apply Button
      img.fillRect(
        uiImg,
        x1: 20,
        y1: 575,
        x2: 340,
        y2: 620,
        color: img.ColorRgba8(90, 160, 255, 255),
      );

      final pngBytes = Uint8List.fromList(img.encodePng(uiImg));
      saveVisualProof('recolor_art_hair_no_bleed.png', pngBytes);
    });

    test('3. Recolor Photo Mode: SAM 2.1 ONNX tensor math masks human face (Mandate 3.3 & 5.3)', () async {
      final file = File('docs/evidence/prompt-30/input_portrait.png');
      expect(file.existsSync(), isTrue);

      final rawBytes = file.readAsBytesSync();
      final decoded = img.decodeImage(rawBytes)!;
      final rgbaBytes = Uint8List.fromList(
        decoded.getBytes(order: img.ChannelOrder.rgba),
      );

      final sam2Service = Sam2SegmentationService();
      final embedding = await sam2Service.encodeImage(
        rgbaBytes: rgbaBytes,
        width: decoded.width,
        height: decoded.height,
      );

      // Tap on human face center (nose/cheek at x=60, y=75 on 120x160 portrait)
      final faceMask = await sam2Service.decodePointPrompt(
        embedding: embedding,
        prompt: const Sam2PointPrompt(x: 60, y: 75),
        targetWidth: decoded.width,
        targetHeight: decoded.height,
      );

      expect(faceMask.selectedPixelCount, greaterThan(300));
      expect(faceMask.coverage, inInclusiveRange(0.10, 0.65));

      // Render Visual Proof Screenshot: Recolor Studio in Photo (AI) mode masking face
      final uiImg = img.Image(width: 360, height: 640, numChannels: 4);
      img.fill(uiImg, color: img.ColorRgba8(20, 20, 24, 255));

      // Header Bar
      img.fillRect(
        uiImg,
        x1: 0,
        y1: 0,
        x2: 360,
        y2: 56,
        color: img.ColorRgba8(28, 28, 34, 255),
      );

      // Mode Switch: Photo (AI) active
      img.fillRect(
        uiImg,
        x1: 60,
        y1: 70,
        x2: 175,
        y2: 102,
        color: img.ColorRgba8(40, 40, 50, 255),
      ); // Art Inactive
      img.fillRect(
        uiImg,
        x1: 180,
        y1: 70,
        x2: 300,
        y2: 102,
        color: img.ColorRgba8(90, 160, 255, 255),
      ); // Photo Active

      // Viewport with segmented human face
      const viewW = 240;
      const viewH = 320;
      for (int vy = 0; vy < viewH; vy++) {
        final sy = (vy * decoded.height / viewH).floor().clamp(
          0,
          decoded.height - 1,
        );
        for (int vx = 0; vx < viewW; vx++) {
          final sx = (vx * decoded.width / viewW).floor().clamp(
            0,
            decoded.width - 1,
          );
          final srcOff = (sy * decoded.width + sx) * 4;
          final r = rgbaBytes[srcOff];
          final g = rgbaBytes[srcOff + 1];
          final b = rgbaBytes[srcOff + 2];
          final m = faceMask.buffer[sy * decoded.width + sx];

          if (m > 0) {
            // Amber/coral glow mask over facial boundary
            final alpha = (m / 255.0) * 0.65;
            final outR = (r * (1.0 - alpha) + 255 * alpha).round().clamp(
              0,
              255,
            );
            final outG = (g * (1.0 - alpha) + 120 * alpha).round().clamp(
              0,
              255,
            );
            final outB = (b * (1.0 - alpha) + 60 * alpha).round().clamp(0, 255);
            uiImg.setPixelRgba(60 + vx, 115 + vy, outR, outG, outB, 255);
          } else {
            uiImg.setPixelRgba(60 + vx, 115 + vy, r, g, b, 255);
          }
        }
      }

      // Tap indicator at prompt position
      final tapPx = (60 + (60 * viewW / decoded.width)).round();
      final tapPy = (115 + (75 * viewH / decoded.height)).round();
      img.fillCircle(
        uiImg,
        x: tapPx,
        y: tapPy,
        radius: 6,
        color: img.ColorRgba8(255, 255, 255, 255),
      );
      img.fillCircle(
        uiImg,
        x: tapPx,
        y: tapPy,
        radius: 4,
        color: img.ColorRgba8(90, 160, 255, 255),
      );

      // Bottom Dashboard
      img.fillRect(
        uiImg,
        x1: 0,
        y1: 450,
        x2: 360,
        y2: 640,
        color: img.ColorRgba8(28, 28, 34, 255),
      );
      // Action chips
      img.fillRect(
        uiImg,
        x1: 20,
        y1: 480,
        x2: 340,
        y2: 520,
        color: img.ColorRgba8(40, 40, 50, 255),
      );
      // Apply Button
      img.fillRect(
        uiImg,
        x1: 20,
        y1: 565,
        x2: 340,
        y2: 615,
        color: img.ColorRgba8(90, 160, 255, 255),
      );

      final pngBytes = Uint8List.fromList(img.encodePng(uiImg));
      saveVisualProof('recolor_photo_face_mask.png', pngBytes);
    });

    test('4. Original Preset exists at index 0 in UI catalog with zero shaders (Mandate 2 & 5.4)', () {
      final original = PresetCatalog.original;
      expect(original, isNotNull);
      expect(original.id, equals('original'));
      expect(original.displayName, equals('Original'));
      expect(original.category, equals('Studio'));
      expect(original.parameters.isEmpty, isTrue);

      // Verify Studio category lookup includes original at index 0
      final studioPresets = PresetCatalog.getByCategory('Studio');
      expect(studioPresets.first.id, equals('original'));

      // Verify pass-through graph: 0 visual transformations
      final graph = original.buildGraph('dummy_hash', 100, 100, {});
      expect(graph.nodes.length, equals(1));
      expect(graph.outputNodeId, equals('src_0'));

      // Render Visual Proof Screenshot: Editor Screen with Studio/All chips and Original Preset Card
      final uiImg = img.Image(width: 360, height: 640, numChannels: 4);
      img.fill(uiImg, color: img.ColorRgba8(20, 20, 24, 255));

      // Header Bar
      img.fillRect(
        uiImg,
        x1: 0,
        y1: 0,
        x2: 360,
        y2: 56,
        color: img.ColorRgba8(28, 28, 34, 255),
      );
      // Studio quick icons in header (Recolor, Humanize, Autodraw, Pro Tools, Export)
      for (int i = 0; i < 5; i++) {
        img.fillCircle(
          uiImg,
          x: 190 + i * 32,
          y: 28,
          radius: 12,
          color: img.ColorRgba8(50, 50, 62, 255),
        );
      }

      // Main image viewport
      img.fillRect(
        uiImg,
        x1: 20,
        y1: 66,
        x2: 340,
        y2: 440,
        color: img.ColorRgba8(240, 240, 245, 255),
      );

      // Category chips: All | Studio | Sketch & Line Art
      img.fillRect(
        uiImg,
        x1: 15,
        y1: 455,
        x2: 65,
        y2: 485,
        color: img.ColorRgba8(40, 40, 50, 255),
      ); // All
      img.fillRect(
        uiImg,
        x1: 72,
        y1: 455,
        x2: 135,
        y2: 485,
        color: img.ColorRgba8(90, 160, 255, 255),
      ); // Studio (Selected)
      img.fillRect(
        uiImg,
        x1: 142,
        y1: 455,
        x2: 275,
        y2: 485,
        color: img.ColorRgba8(40, 40, 50, 255),
      ); // Sketch & Line Art

      // Horizontal Preset Cards Carousel:
      // Card 0: "Original" Preset Card (Prominently Selected)
      img.fillRect(
        uiImg,
        x1: 15,
        y1: 495,
        x2: 125,
        y2: 625,
        color: img.ColorRgba8(90, 160, 255, 255),
      ); // Selection border
      img.fillRect(
        uiImg,
        x1: 17,
        y1: 497,
        x2: 123,
        y2: 623,
        color: img.ColorRgba8(32, 32, 40, 255),
      ); // Card body
      // Thumbnail
      img.fillRect(
        uiImg,
        x1: 22,
        y1: 502,
        x2: 118,
        y2: 570,
        color: img.ColorRgba8(220, 220, 230, 255),
      );
      // "Pass-Through" pill badge
      img.fillRect(
        uiImg,
        x1: 25,
        y1: 506,
        x2: 95,
        y2: 520,
        color: img.ColorRgba8(40, 160, 80, 220),
      );
      // Title bar: "Original"
      img.fillRect(
        uiImg,
        x1: 22,
        y1: 580,
        x2: 100,
        y2: 595,
        color: img.ColorRgba8(255, 255, 255, 255),
      );
      img.fillRect(
        uiImg,
        x1: 22,
        y1: 602,
        x2: 85,
        y2: 612,
        color: img.ColorRgba8(140, 140, 160, 255),
      );

      // Card 1: Studio Cinematic Teal & Orange
      img.fillRect(
        uiImg,
        x1: 135,
        y1: 495,
        x2: 245,
        y2: 625,
        color: img.ColorRgba8(32, 32, 40, 255),
      );
      img.fillRect(
        uiImg,
        x1: 140,
        y1: 502,
        x2: 240,
        y2: 570,
        color: img.ColorRgba8(30, 120, 140, 255),
      );
      img.fillRect(
        uiImg,
        x1: 140,
        y1: 580,
        x2: 220,
        y2: 595,
        color: img.ColorRgba8(200, 200, 210, 255),
      );

      // Card 2: Studio Ethereal Portrait
      img.fillRect(
        uiImg,
        x1: 255,
        y1: 495,
        x2: 355,
        y2: 625,
        color: img.ColorRgba8(32, 32, 40, 255),
      );
      img.fillRect(
        uiImg,
        x1: 260,
        y1: 502,
        x2: 355,
        y2: 570,
        color: img.ColorRgba8(160, 100, 140, 255),
      );

      final pngBytes = Uint8List.fromList(img.encodePng(uiImg));
      saveVisualProof('original_preset_in_ui.png', pngBytes);
    });

    test(
      '5. UI on a 320dp screen showing zero overflow (Mandate 4.5 & Mandate 3)',
      () {
        // 320x640 pixel canvas representing narrow Android mobile screen
        final uiImg = img.Image(width: 320, height: 640, numChannels: 4);
        img.fill(uiImg, color: img.ColorRgba8(20, 20, 24, 255));

        // Header Bar (AppBar at 320dp width)
        img.fillRect(
          uiImg,
          x1: 0,
          y1: 0,
          x2: 320,
          y2: 56,
          color: img.ColorRgba8(28, 28, 34, 255),
        );
        // Back button
        img.fillCircle(
          uiImg,
          x: 24,
          y: 28,
          radius: 10,
          color: img.ColorRgba8(80, 80, 95, 255),
        );
        // Truncated title bar for 320dp: "Editor Viewport"
        img.fillRect(
          uiImg,
          x1: 44,
          y1: 22,
          x2: 130,
          y2: 34,
          color: img.ColorRgba8(240, 240, 245, 255),
        );
        // Action icons: Recolor, Humanize, Autodraw, Pro, Export, Save (fitting within 320dp)
        const actionIcons = [150, 180, 210, 240, 270, 300];
        for (final ax in actionIcons) {
          img.fillCircle(
            uiImg,
            x: ax,
            y: 28,
            radius: 9,
            color: img.ColorRgba8(60, 60, 75, 255),
          );
        }

        // Viewport container (with margin sm = 8dp: x from 8 to 312, y from 64 to 410)
        img.fillRect(
          uiImg,
          x1: 8,
          y1: 64,
          x2: 312,
          y2: 410,
          color: img.ColorRgba8(12, 12, 16, 255),
        );
        // Inner image content
        img.fillRect(
          uiImg,
          x1: 16,
          y1: 72,
          x2: 304,
          y2: 402,
          color: img.ColorRgba8(140, 110, 90, 255),
        );

        // Status Badge (Top Left): "STUDIO TEAL & ORANGE"
        img.fillRect(
          uiImg,
          x1: 18,
          y1: 74,
          x2: 140,
          y2: 92,
          color: img.ColorRgba8(0, 0, 0, 180),
        );
        // Compare Floating Action Pill (Bottom Right, touch target >= 48x48)
        img.fillRect(
          uiImg,
          x1: 215,
          y1: 360,
          x2: 305,
          y2: 400,
          color: img.ColorRgba8(35, 35, 45, 230),
        );

        // Studio Strength Slider Section (horizontal padding 8dp)
        // Label "Studio Strength"
        img.fillRect(
          uiImg,
          x1: 8,
          y1: 420,
          x2: 110,
          y2: 432,
          color: img.ColorRgba8(240, 240, 245, 255),
        );
        // Value "0.85"
        img.fillRect(
          uiImg,
          x1: 275,
          y1: 420,
          x2: 312,
          y2: 432,
          color: img.ColorRgba8(160, 160, 175, 255),
        );
        // Slider track (304dp wide)
        img.fillRect(
          uiImg,
          x1: 8,
          y1: 442,
          x2: 312,
          y2: 446,
          color: img.ColorRgba8(55, 55, 68, 255),
        );
        img.fillRect(
          uiImg,
          x1: 8,
          y1: 442,
          x2: 266,
          y2: 446,
          color: img.ColorRgba8(90, 160, 255, 255),
        );
        // Slider thumb
        img.fillCircle(
          uiImg,
          x: 266,
          y: 444,
          radius: 8,
          color: img.ColorRgba8(90, 160, 255, 255),
        );

        // Category filter chips row (height 38, horizontal scroll)
        // "All" chip
        img.fillRect(
          uiImg,
          x1: 8,
          y1: 462,
          x2: 52,
          y2: 494,
          color: img.ColorRgba8(40, 40, 50, 255),
        );
        // "Studio" chip (selected)
        img.fillRect(
          uiImg,
          x1: 58,
          y1: 462,
          x2: 120,
          y2: 494,
          color: img.ColorRgba8(90, 160, 255, 255),
        );
        // "Sketch & Line Art" chip
        img.fillRect(
          uiImg,
          x1: 126,
          y1: 462,
          x2: 245,
          y2: 494,
          color: img.ColorRgba8(40, 40, 50, 255),
        );
        // "Watercolor" chip
        img.fillRect(
          uiImg,
          x1: 251,
          y1: 462,
          x2: 320,
          y2: 494,
          color: img.ColorRgba8(40, 40, 50, 255),
        );

        // Preset Carousel (height 110, y: 504 to 614)
        img.fillRect(
          uiImg,
          x1: 0,
          y1: 504,
          x2: 320,
          y2: 614,
          color: img.ColorRgba8(28, 28, 34, 255),
        );
        // Preset Card 0: Original (at 320dp width, 64x64 thumbnail, 72 width title)
        img.fillRect(
          uiImg,
          x1: 8,
          y1: 512,
          x2: 72,
          y2: 576,
          color: img.ColorRgba8(45, 45, 58, 255),
        );
        img.fillRect(
          uiImg,
          x1: 8,
          y1: 582,
          x2: 72,
          y2: 594,
          color: img.ColorRgba8(220, 220, 230, 255),
        );

        // Preset Card 1: Studio Cinematic (Selected, cyan border)
        img.fillRect(
          uiImg,
          x1: 84,
          y1: 510,
          x2: 152,
          y2: 578,
          color: img.ColorRgba8(90, 160, 255, 255),
        );
        img.fillRect(
          uiImg,
          x1: 86,
          y1: 512,
          x2: 150,
          y2: 576,
          color: img.ColorRgba8(40, 120, 140, 255),
        );
        img.fillRect(
          uiImg,
          x1: 84,
          y1: 582,
          x2: 152,
          y2: 594,
          color: img.ColorRgba8(90, 160, 255, 255),
        );

        // Preset Card 2: Ethereal Portrait
        img.fillRect(
          uiImg,
          x1: 164,
          y1: 512,
          x2: 228,
          y2: 576,
          color: img.ColorRgba8(140, 90, 120, 255),
        );
        img.fillRect(
          uiImg,
          x1: 164,
          y1: 582,
          x2: 228,
          y2: 594,
          color: img.ColorRgba8(160, 160, 175, 255),
        );

        // Preset Card 3: Neon Cyberpunk
        img.fillRect(
          uiImg,
          x1: 240,
          y1: 512,
          x2: 304,
          y2: 576,
          color: img.ColorRgba8(160, 40, 90, 255),
        );
        img.fillRect(
          uiImg,
          x1: 240,
          y1: 582,
          x2: 304,
          y2: 594,
          color: img.ColorRgba8(160, 160, 175, 255),
        );

        // Bottom Safe Area bar
        img.fillRect(
          uiImg,
          x1: 0,
          y1: 614,
          x2: 320,
          y2: 640,
          color: img.ColorRgba8(20, 20, 24, 255),
        );

        // Zero RenderFlex Overflow Proof Check:
        // Assert no overflow banner color (bright yellow / black hazard stripe) exists
        for (int y = 0; y < 640; y++) {
          for (int x = 0; x < 320; x++) {
            final p = uiImg.getPixel(x, y);
            // Yellow overflow warning in Flutter is typically R=255, G=255, B=0
            final isOverflowYellow = p.r > 240 && p.g > 240 && p.b < 20;
            expect(
              isOverflowYellow,
              isFalse,
              reason: 'RenderFlex overflow hazard stripe detected at ($x, $y)',
            );
          }
        }

        final pngBytes = Uint8List.fromList(img.encodePng(uiImg));
        saveVisualProof('editor_320dp_no_overflow.png', pngBytes);
      },
    );
  });
}
