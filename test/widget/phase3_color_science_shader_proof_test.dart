import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/data/render/render_graph_executor.dart';
import 'package:reranger/features/export/data/image_exporter.dart';
import 'package:reranger/features/export/domain/export_format.dart';
import 'package:reranger/features/presets/data/preset_catalog.dart';
import 'package:reranger/features/presets/data/studio_presets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PHASE 3: Color Science & Shader Overhaul Proof Suite', () {
    const artifactDir =
        '/root/.gemini/antigravity-cli/brain/131f6c3f-f2c2-4492-b5c5-d64035cddb16';
    final evidenceDir = Directory('docs/evidence/prompt-33');

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

    test('MANDATE 1: True Cinematic Split-Toning protects human skin tones while split-toning shadows & highlights', () async {
      final executor = RenderGraphExecutor();

      // 1. Synthesize a realistic human portrait scene (160x160):
      // - Deep shadow background (L* ~ 0.15)
      // - Radiant highlight keylight (L* ~ 0.85)
      // - Natural Caucasian/Asian/Warm human skin tone face region (L* ~ 0.55, a* ~ 16, b* ~ 22)
      const width = 160;
      const height = 160;
      final portraitImg = img.Image(
        width: width,
        height: height,
        numChannels: 4,
      );

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          // Background shadow on left/top: dark neutral/slate
          if (x < 45 || y < 30) {
            final shadowLum = 25 + (x + y) % 15;
            portraitImg.setPixelRgba(
              x,
              y,
              shadowLum,
              shadowLum,
              shadowLum + 2,
              255,
            );
          }
          // Keylight highlight on top-right: bright warm white
          else if (x > 125 && y < 55) {
            portraitImg.setPixelRgba(x, y, 240, 235, 225, 255);
          }
          // Central face oval: natural warm skin tone (R=218, G=155, B=125)
          // CIELAB: L* ~ 68, a* ~ 19.5, b* ~ 24.8 (solidly in human skin locus)
          else {
            final dx = (x - 85) / 40.0;
            final dy = (y - 90) / 50.0;
            final distSq = dx * dx + dy * dy;
            if (distSq <= 1.0) {
              // Face skin tone
              portraitImg.setPixelRgba(x, y, 218, 155, 125, 255);
            } else {
              // Outer shadow transition
              final s = (40 + (x * y) % 20).clamp(20, 60);
              portraitImg.setPixelRgba(x, y, s, s, s, 255);
            }
          }
        }
      }

      final portraitPng = Uint8List.fromList(img.encodePng(portraitImg));
      final sourceHash = sha256.convert(portraitPng).toString();

      // 2. Execute Cinematic Teal & Orange preset
      final cinematicPreset = PresetCatalog.getById(
        'studio_cinematic_teal_orange',
      );
      expect(cinematicPreset, isNotNull);

      final graph = cinematicPreset!.buildGraph(sourceHash, width, height, {
        'studioStrength': 1.0,
      });

      final renderResult = await executor.execute(
        graph: graph,
        sourceImageBytes: portraitPng,
      );

      final resultImg = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: renderResult.pixelBytes.buffer,
        numChannels: 4,
      );

      // 3. Quantitative Color Science Verification:
      // A. Face Center Pixel (85, 90) must preserve natural warm skin tone
      final facePixel = resultImg.getPixel(85, 90);
      expect(
        facePixel.r,
        greaterThan(facePixel.b),
        reason: 'Skin tone must remain warm (R > B, no cyan cast)',
      );
      expect(
        facePixel.r,
        greaterThan(facePixel.g),
        reason: 'Skin tone must remain warm (R > G)',
      );
      // Assert face pixel is NOT tinted cyan/green (B should not dominate)
      expect(
        facePixel.b,
        lessThan(180),
        reason: 'Skin tones must not be turned cyan',
      );
      // Red channel should remain rich and vibrant
      expect(
        facePixel.r,
        greaterThan(180),
        reason: 'Skin tone radiance must be preserved',
      );

      // B. Shadow Region Pixel (15, 15) must be shifted toward Teal (B and G elevated relative to R)
      final shadowPixel = resultImg.getPixel(15, 15);
      expect(
        shadowPixel.b,
        greaterThanOrEqualTo(shadowPixel.r),
        reason:
            'Shadows must split-tone toward Teal/Cyan (B >= R). Observed: R=${shadowPixel.r}, G=${shadowPixel.g}, B=${shadowPixel.b}',
      );

      // C. Keylight Highlight Pixel (140, 30) must be shifted toward warm Amber/Orange (R > G > B)
      final highlightPixel = resultImg.getPixel(140, 30);
      expect(
        highlightPixel.r,
        greaterThan(highlightPixel.b),
        reason: 'Highlights must split-tone toward warm Orange (R > B)',
      );

      // 4. Save Visual Proof
      final visualProofPng = Uint8List.fromList(img.encodePng(resultImg));
      saveVisualProof('cinematic_teal_orange_face.png', visualProofPng);
      expect(visualProofPng.isNotEmpty, isTrue);
    });

    test('MANDATE 2: Coherent Noise produces silky organic paper tooth without TV static', () async {
      final executor = RenderGraphExecutor();

      // 1. Create a 256x256 smooth linear gradient from black to white
      const width = 256;
      const height = 256;
      final gradientImg = img.Image(
        width: width,
        height: height,
        numChannels: 4,
      );
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final lum = x; // 0 to 255
          gradientImg.setPixelRgba(x, y, lum, lum, lum, 255);
        }
      }

      final gradientPng = Uint8List.fromList(img.encodePng(gradientImg));
      final sourceHash = sha256.convert(gradientPng).toString();

      // 2. Apply Graphite Pencil preset (which uses GrainOverlayNode & Sobel edges)
      final graphitePencil = PresetCatalog.getById('graphite_pencil');
      expect(graphitePencil, isNotNull);

      final defaultParams = graphitePencil!.resolveParameters(null);
      final graph = graphitePencil.buildGraph(
        sourceHash,
        width,
        height,
        defaultParams,
      );

      final renderResult = await executor.execute(
        graph: graph,
        sourceImageBytes: gradientPng,
      );

      final resultImg = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: renderResult.pixelBytes.buffer,
        numChannels: 4,
      );

      // 3. Mathematical TV Static Check:
      // Raw PRNG noise causes violent, scattered high-frequency jumps between adjacent pixels.
      // True Perlin gradient noise produces continuous, smooth variations where adjacent pixel delta is strictly bounded.
      int totalNeighborSamples = 0;
      int violentSpikes =
          0; // Neighbor delta > 45 in midtones indicates raw PRNG static

      for (int y = 10; y < height - 10; y += 4) {
        for (int x = 20; x < width - 20; x += 4) {
          final p0 = resultImg.getPixel(x, y);
          final p1 = resultImg.getPixel(x + 1, y);
          final delta = (p0.r - p1.r).abs();
          totalNeighborSamples++;
          if (delta > 45) {
            violentSpikes++;
          }
        }
      }

      // TV static produces hundreds of violent salt-and-pepper spikes.
      // Perlin coherent noise with soft light <= 0.08 produces zero violent spikes.
      expect(totalNeighborSamples, greaterThan(100));
      expect(
        violentSpikes,
        equals(0),
        reason: 'Organic paper tooth must be coherent with zero TV static salt-and-pepper spikes',
      );

      // 4. Save Visual Proof
      final visualProofPng = Uint8List.fromList(img.encodePng(resultImg));
      saveVisualProof('graphite_pencil_smooth_gradient.png', visualProofPng);
      expect(visualProofPng.isNotEmpty, isTrue);
    });

    test('MANDATE 3: All 5 Studio Presets strictly hide granular sliders', () {
      final studioPresets = PresetCatalog.studioPresets;
      expect(studioPresets.length, equals(5));

      for (final preset in studioPresets) {
        expect(
          preset.isLockedStudioPreset,
          isTrue,
          reason: '${preset.id} must be marked as locked studio preset',
        );
        expect(
          preset.parameters.length,
          equals(1),
          reason:
              '${preset.id} must have exactly 1 parameter exposed to the user',
        );
        expect(
          preset.parameters.first.id,
          equals('studioStrength'),
          reason:
              '${preset.id} parameter must be studioStrength (all internal parameters derived)',
        );
      }
    });

    test('MANDATE 4: Original preset is a pure pass-through at 0% Realism and runs Stealth on export at 80% Realism', () async {
      final originalPreset = PresetCatalog.getById('original');
      expect(originalPreset, isNotNull);
      expect(originalPreset, equals(StudioPresets.original));

      final dummy = img.Image(width: 48, height: 48, numChannels: 4);
      for (int y = 0; y < 48; y++) {
        for (int x = 0; x < 48; x++) {
          dummy.setPixelRgba(x, y, (x * 5) % 256, (y * 5) % 256, 128, 255);
        }
      }
      final dummyPng = Uint8List.fromList(img.encodePng(dummy));
      final dummyHash = sha256.convert(dummyPng).toString();

      final graph = originalPreset!.buildGraph(dummyHash, 48, 48, {});
      expect(
        graph.nodes.length,
        equals(1),
        reason:
            'Original preset DAG must contain only 1 node (SourceImageNode)',
      );
      expect(
        graph.outputNodeId,
        equals('src_0'),
        reason: 'Original output must be src_0 directly',
      );

      // 1. Pass-through test: Realism = 0%
      final executor = RenderGraphExecutor();
      final rawResult = await executor.execute(
        graph: graph,
        sourceImageBytes: dummyPng,
      );
      final rawDecoded = dummy.getBytes(order: img.ChannelOrder.rgba);
      expect(
        rawResult.pixelBytes,
        equals(rawDecoded),
        reason:
            'At 0% Realism, Original preset must be byte-for-byte identical',
      );

      // 2. Export test at 0% Realism
      final exporter = ImageExporter();
      final export0 = exporter.encode(
        sourceImage: dummy,
        config: const ExportConfiguration(
          format: ExportImageFormat.png,
          scale: 1.0,
          realism: 0.0,
        ),
      );
      expect(export0.bytes.isNotEmpty, isTrue);

      // 3. Export test at 80% Realism:
      // Must apply ARMORAttackNode + SensorNoiseNode on target pixels, strip metadata,
      // but NOT apply visual shaders (like duotone/vibrancy color shifts).
      final export80 = exporter.encode(
        sourceImage: dummy,
        config: const ExportConfiguration(
          format: ExportImageFormat.png,
          scale: 1.0,
          realism: 0.8,
        ),
      );
      expect(
        export80.bytes,
        isNot(equals(export0.bytes)),
        reason: 'At 80% Realism, Stealth Engine V2 must apply UAP perturbations to alter AI detection',
      );

      final stealthImg = img.decodePng(export80.bytes)!;
      // Verify overall image structure is preserved (no duotone or color destruction)
      double totalDiff = 0.0;
      for (int y = 0; y < 48; y++) {
        for (int x = 0; x < 48; x++) {
          final origP = dummy.getPixel(x, y);
          final stealthP = stealthImg.getPixel(x, y);
          final diff =
              (origP.r - stealthP.r).abs() +
              (origP.g - stealthP.g).abs() +
              (origP.b - stealthP.b).abs();
          totalDiff += diff;
        }
      }
      final meanPixelDiff = totalDiff / (48 * 48 * 3);
      // Adversarial noise is subtle (< 12 levels per channel), not a visual destruction shader
      expect(
        meanPixelDiff,
        lessThan(15.0),
        reason:
            'Stealth Engine perturbation must be visually imperceptible (mean diff $meanPixelDiff < 15.0)',
      );
    });
  });
}
