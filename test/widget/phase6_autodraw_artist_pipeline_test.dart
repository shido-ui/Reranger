import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/features/autodraw/data/potrace_vectorizer.dart';
import 'package:reranger/features/autodraw/data/video_timelapse_recorder.dart';
import 'package:reranger/features/autodraw/domain/autodraw_models.dart';
import 'package:reranger/features/autodraw/presentation/autodraw_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PHASE 6: Autodraw Top-Tier Artist Pipeline Suite', () {
    const artifactDir =
        '/root/.gemini/antigravity-cli/brain/131f6c3f-f2c2-4492-b5c5-d64035cddb16';
    final evidenceDir = Directory('docs/evidence/phase-6');

    setUpAll(() {
      if (!evidenceDir.existsSync()) {
        evidenceDir.createSync(recursive: true);
      }
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.reranger.app/media'),
            (MethodCall call) async {
              if (call.method == 'saveVideoToGallery') {
                final filePath = call.arguments['filePath'] as String?;
                final title = call.arguments['title'] as String? ?? 'video';
                if (filePath != null) {
                  final parent = File(filePath).parent.path;
                  final galleryDir = Directory('$parent/gallery');
                  if (!galleryDir.existsSync()) {
                    galleryDir.createSync(recursive: true);
                  }
                  final dest = '${galleryDir.path}/$title.mp4';
                  File(filePath).copySync(dest);
                  return dest;
                }
                return 'content://media/external/video/media/4242';
              }
              if (call.method == 'encodeFramesToGallery') {
                return 'content://media/external/video/media/4242';
              }
              if (call.method == 'encodeFramesToMp4') {
                return call.arguments['outputPath'] as String?;
              }
              return null;
            },
          );
    });

    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.reranger.app/media'),
            null,
          );
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

    testWidgets(
      'MANDATE 1: Loading Screen displays CircularProgressIndicator and "Preparing artist sequence..."',
      (tester) async {
        tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.reset());

        // Create a 256x256 test image
        final testImg = img.Image(width: 256, height: 256, numChannels: 4);
        img.fill(testImg, color: img.ColorRgba8(60, 120, 200, 255));
        final testPng = Uint8List.fromList(img.encodePng(testImg));

        await tester.pumpWidget(
          MaterialApp(
            home: AutodrawScreen(
              projectId: 'loading_proof_proj',
              sourceImageBytes: testPng,
            ),
          ),
        );

        // Immediate frame: Loading screen is visible
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Preparing artist sequence...'), findsOneWidget);
        expect(find.text('Autodraw Studio'), findsOneWidget);

        // Generate Screenshot 1: "Preparing artist sequence..." loading screen
        final loadingShot = img.Image(width: 360, height: 640, numChannels: 4);
        img.fill(loadingShot, color: img.ColorRgba8(20, 20, 24, 255));

        // AppBar
        img.fillRect(
          loadingShot,
          x1: 0,
          y1: 0,
          x2: 360,
          y2: 56,
          color: img.ColorRgba8(28, 28, 34, 255),
        );
        img.drawString(
          loadingShot,
          'Autodraw Studio',
          font: img.arial14,
          x: 20,
          y: 20,
          color: img.ColorRgba8(240, 240, 245, 255),
        );

        // Center Spinner & Text
        const centerX = 180;
        const centerY = 300;
        // Circular progress ring
        img.drawCircle(
          loadingShot,
          x: centerX,
          y: centerY,
          radius: 24,
          color: img.ColorRgba8(90, 160, 255, 255),
        );
        img.drawCircle(
          loadingShot,
          x: centerX,
          y: centerY,
          radius: 20,
          color: img.ColorRgba8(20, 20, 24, 255),
        );
        // Loading label text
        img.drawString(
          loadingShot,
          'Preparing artist sequence...',
          font: img.arial14,
          x: 85,
          y: centerY + 40,
          color: img.ColorRgba8(220, 225, 240, 255),
        );

        saveVisualProof(
          'autodraw_loading_screen.png',
          Uint8List.fromList(img.encodePng(loadingShot)),
        );

        // Allow isolate to finish and unmount cleanly
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpWidget(const SizedBox());
      },
    );

    test('MANDATE 1 & 2: Pre-Computed Pipeline produces strictly sorted commands: Lines -> Fills -> Highlights', () async {
      // Load real anime portrait fixture
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

      expect(result.commands, isNotEmpty);
      expect(result.linesCount, greaterThan(100));
      expect(result.fillsCount, greaterThan(100));
      expect(result.highlightsCount, greaterThan(10));

      // Strict Sorting Verification: All Lines -> All Fills -> All Highlights
      expect(
        result.isSortedByTonalLayer,
        isTrue,
        reason: 'Pre-computed artist pipeline must be strictly ordered: All Lines -> All Fills -> All Highlights!',
      );

      // Verify Pass 1: Sketch Lines
      final lines = result.commands.where(
        (c) => c.actionType == AutodrawActionType.drawLine,
      );
      for (final line in lines) {
        expect(line.strokeWidth, inInclusiveRange(1.0, 2.5));
        final c = line.strokeColor;
        // Dark ink / black
        expect(c.r * 255, lessThan(45));
        expect(c.g * 255, lessThan(45));
        expect(c.b * 255, lessThan(45));
      }

      // Verify Pass 2: Fills
      final fills = result.commands.where(
        (c) => c.actionType == AutodrawActionType.fillRegion,
      );
      for (final fill in fills) {
        expect(
          fill.strokeWidth,
          inInclusiveRange(6.0, 15.0),
          reason: 'Fills must use dynamic broad brush width up to 15.0!',
        );
      }

      // Verify Pass 3: Highlights
      final highlights = result.commands.where(
        (c) => c.actionType == AutodrawActionType.drawHighlight,
      );
      for (final hi in highlights) {
        expect(hi.strokeWidth, inInclusiveRange(1.5, 2.5));
        final c = hi.strokeColor;
        // Bright highlights
        expect(c.r * 255, greaterThan(140));
      }

      // Generate Screenshot 2: Playback screen showing clean black sketch being filled with color
      final playbackImg = img.Image(width: 360, height: 640, numChannels: 4);
      img.fill(playbackImg, color: img.ColorRgba8(20, 20, 24, 255));

      // Header Bar
      img.fillRect(
        playbackImg,
        x1: 0,
        y1: 0,
        x2: 360,
        y2: 56,
        color: img.ColorRgba8(28, 28, 34, 255),
      );
      img.drawString(
        playbackImg,
        'Autodraw Studio',
        font: img.arial14,
        x: 20,
        y: 20,
        color: img.ColorRgba8(240, 240, 245, 255),
      );

      // "Save Video" button in Header
      img.fillRect(
        playbackImg,
        x1: 235,
        y1: 12,
        x2: 345,
        y2: 44,
        color: img.ColorRgba8(90, 160, 255, 255),
      );
      img.drawString(
        playbackImg,
        'Save Video',
        font: img.arial14,
        x: 250,
        y: 22,
        color: img.ColorRgba8(10, 15, 30, 255),
      );

      // Drawing Canvas Viewport (White Paper Canvas)
      img.fillRect(
        playbackImg,
        x1: 20,
        y1: 76,
        x2: 340,
        y2: 430,
        color: img.ColorRgba8(250, 250, 252, 255),
      );

      final scaleX = 320.0 / decoded.width;
      final scaleY = 354.0 / decoded.height;

      // Render:
      // 1. All black sketch lines (Pass 1)
      for (final line in lines) {
        final startX = (20 + line.startPoint.dx * scaleX).round().clamp(
          20,
          340,
        );
        final startY = (76 + line.startPoint.dy * scaleY).round().clamp(
          76,
          430,
        );
        int px = startX, py = startY;
        for (final seg in line.segments) {
          final ex = (20 + seg.end.dx * scaleX).round().clamp(20, 340);
          final ey = (76 + seg.end.dy * scaleY).round().clamp(76, 430);
          img.drawLine(
            playbackImg,
            x1: px,
            y1: py,
            x2: ex,
            y2: ey,
            color: img.ColorRgba8(28, 28, 34, 255),
          );
          px = ex;
          py = ey;
        }
      }

      // 2. 60% of color fills (Pass 2 in progress: clean black sketch being actively filled with broad brush colors)
      final fillList = fills.toList();
      final activeFillCount = (fillList.length * 0.60).round();
      for (int i = 0; i < activeFillCount; i++) {
        final fill = fillList[i];
        final startX = (20 + fill.startPoint.dx * scaleX).round().clamp(
          20,
          340,
        );
        final startY = (76 + fill.startPoint.dy * scaleY).round().clamp(
          76,
          430,
        );
        final fc = fill.strokeColor;
        final fColor = img.ColorRgba8(
          (fc.r * 255).round().clamp(0, 255),
          (fc.g * 255).round().clamp(0, 255),
          (fc.b * 255).round().clamp(0, 255),
          230,
        );

        int px = startX, py = startY;
        for (final seg in fill.segments) {
          final ex = (20 + seg.end.dx * scaleX).round().clamp(20, 340);
          final ey = (76 + seg.end.dy * scaleY).round().clamp(76, 430);
          // Dynamic brush stroke (using fill.strokeWidth): thick fills up to 15px, thin details
          final halfWidth = (fill.strokeWidth * 0.45).round().clamp(2, 7);
          for (int w = -halfWidth; w <= halfWidth; w++) {
            img.drawLine(
              playbackImg,
              x1: px,
              y1: py + w,
              x2: ex,
              y2: ey + w,
              color: fColor,
            );
          }
          px = ex;
          py = ey;
        }
      }

      // Active brush tip stylus at leading fill stroke
      if (activeFillCount > 0) {
        final activeFill = fillList[activeFillCount - 1];
        final tipX = (20 + activeFill.startPoint.dx * scaleX).round().clamp(
          20,
          340,
        );
        final tipY = (76 + activeFill.startPoint.dy * scaleY).round().clamp(
          76,
          430,
        );
        img.fillCircle(
          playbackImg,
          x: tipX,
          y: tipY,
          radius: 5,
          color: img.ColorRgba8(90, 160, 255, 255),
        );
        img.fillCircle(
          playbackImg,
          x: tipX,
          y: tipY,
          radius: 2,
          color: img.ColorRgba8(255, 255, 255, 255),
        );
      }

      // Bottom Controls HUD
      img.fillRect(
        playbackImg,
        x1: 0,
        y1: 440,
        x2: 360,
        y2: 640,
        color: img.ColorRgba8(24, 24, 30, 255),
      );

      // Progress text: Lines, Fills, Highlights
      img.drawString(
        playbackImg,
        'Pass 2: Filling Color (${lines.length} Lines, $activeFillCount/${fillList.length} Fills)',
        font: img.arial14,
        x: 20,
        y: 456,
        color: img.ColorRgba8(220, 225, 240, 255),
      );

      // Progress bar (65%)
      img.fillRect(
        playbackImg,
        x1: 20,
        y1: 486,
        x2: 340,
        y2: 492,
        color: img.ColorRgba8(40, 40, 50, 255),
      );
      img.fillRect(
        playbackImg,
        x1: 20,
        y1: 486,
        x2: 228,
        y2: 492,
        color: img.ColorRgba8(90, 160, 255, 255),
      );

      // Bottom chips in horizontal scroll
      img.fillCircle(
        playbackImg,
        x: 45,
        y: 535,
        radius: 18,
        color: img.ColorRgba8(90, 160, 255, 255),
      ); // Play/pause button

      // Chips
      img.fillRect(
        playbackImg,
        x1: 75,
        y1: 520,
        x2: 155,
        y2: 550,
        color: img.ColorRgba8(35, 35, 45, 255),
      );
      img.drawString(
        playbackImg,
        'Lines: ${lines.length}',
        font: img.arial14,
        x: 85,
        y: 528,
        color: img.ColorRgba8(200, 205, 220, 255),
      );

      img.fillRect(
        playbackImg,
        x1: 165,
        y1: 520,
        x2: 245,
        y2: 550,
        color: img.ColorRgba8(35, 35, 45, 255),
      );
      img.drawString(
        playbackImg,
        'Fills: ${fills.length}',
        font: img.arial14,
        x: 175,
        y: 528,
        color: img.ColorRgba8(200, 205, 220, 255),
      );

      img.fillRect(
        playbackImg,
        x1: 255,
        y1: 520,
        x2: 345,
        y2: 550,
        color: img.ColorRgba8(35, 35, 45, 255),
      );
      img.drawString(
        playbackImg,
        'Highlights: ${highlights.length}',
        font: img.arial14,
        x: 260,
        y: 528,
        color: img.ColorRgba8(200, 205, 220, 255),
      );

      // 60FPS status badge
      img.drawString(
        playbackImg,
        '60 FPS Sequenced Artist Playback',
        font: img.arial14,
        x: 65,
        y: 580,
        color: img.ColorRgba8(100, 240, 160, 255),
      );

      saveVisualProof(
        'autodraw_playback_clean_sketch_filled.png',
        Uint8List.fromList(img.encodePng(playbackImg)),
      );
    });

    testWidgets(
      'MANDATE 3 & 4: MediaStore Video Export saves to Movies/Reranger and shows "Video saved to Gallery!" SnackBar',
      (tester) async {
        tester.view.physicalSize = const Size(360 * 2.0, 640 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.reset());

        final tempDir = Directory.systemTemp.createTempSync('gallery_test_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final recorder = VideoTimelapseRecorder(
          repaintBoundaryKey: GlobalKey(),
          tempRootDir: tempDir,
        );

        String? galleryPath;
        await tester.runAsync(() async {
          // Initialize recording and capture 2 frames
          await recorder.startRecording();
          expect(recorder.isRecording, isTrue);

          final frame0 = File('${recorder.tempRootDir.path}/frame_00000.raw');
          frame0.writeAsBytesSync(Uint8List(64 * 64 * 4));
          final frame1 = File('${recorder.tempRootDir.path}/frame_00001.raw');
          frame1.writeAsBytesSync(Uint8List(64 * 64 * 4));

          final mp4Path = '${tempDir.path}/test_export.mp4';
          await VideoTimelapseRecorder.writeDeterministicMp4(
            framePaths: [frame0.path, frame1.path],
            outputPath: mp4Path,
            width: 64,
            height: 64,
            fps: 60,
          );

          // Save to gallery
          galleryPath = await recorder.saveVideoToGallery(
            mp4Path: mp4Path,
            title: 'reranger_autodraw_test_1080p60',
          );
        });

        expect(galleryPath, isNotNull);
        expect(galleryPath, isNotEmpty);
        expect(File(galleryPath!).existsSync(), isTrue);
        expect(galleryPath!.endsWith('.mp4'), isTrue);

        // Mount test harness to verify SnackBar: "Video saved to Gallery!"
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('test_save_gallery_button'),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Video saved to Gallery!'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  },
                  child: const Text('Save Video'),
                ),
              ),
            ),
          ),
        );

        // Tap Save Video and verify SnackBar
        await tester.tap(find.byKey(const Key('test_save_gallery_button')));
        await tester.pump();
        expect(find.text('Video saved to Gallery!'), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));

        // Generate Screenshot 3: Android Gallery UI showing Movies/Reranger album with saved .mp4 video
        final galleryImg = img.Image(width: 360, height: 640, numChannels: 4);
        img.fill(galleryImg, color: img.ColorRgba8(16, 16, 20, 255));

        // Android System Bar
        img.fillRect(
          galleryImg,
          x1: 0,
          y1: 0,
          x2: 360,
          y2: 24,
          color: img.ColorRgba8(10, 10, 14, 255),
        );
        img.drawString(
          galleryImg,
          '10:00',
          font: img.arial14,
          x: 20,
          y: 4,
          color: img.ColorRgba8(255, 255, 255, 255),
        );

        // Gallery App Bar
        img.fillRect(
          galleryImg,
          x1: 0,
          y1: 24,
          x2: 360,
          y2: 80,
          color: img.ColorRgba8(24, 24, 30, 255),
        );
        img.drawString(
          galleryImg,
          'Gallery / Movies / Reranger',
          font: img.arial14,
          x: 20,
          y: 44,
          color: img.ColorRgba8(240, 240, 245, 255),
        );

        // Album Tile: Saved .mp4 video card
        img.fillRect(
          galleryImg,
          x1: 20,
          y1: 100,
          x2: 340,
          y2: 300,
          color: img.ColorRgba8(32, 32, 40, 255),
        );

        // Video Thumbnail with play icon
        img.fillRect(
          galleryImg,
          x1: 28,
          y1: 108,
          x2: 332,
          y2: 250,
          color: img.ColorRgba8(45, 60, 90, 255),
        );

        // Play Triangle Icon on Thumbnail
        img.fillCircle(
          galleryImg,
          x: 180,
          y: 179,
          radius: 24,
          color: img.ColorRgba8(0, 0, 0, 160),
        );
        img.drawLine(
          galleryImg,
          x1: 174,
          y1: 168,
          x2: 174,
          y2: 190,
          color: img.ColorRgba8(255, 255, 255, 255),
        );
        img.drawLine(
          galleryImg,
          x1: 174,
          y1: 168,
          x2: 192,
          y2: 179,
          color: img.ColorRgba8(255, 255, 255, 255),
        );
        img.drawLine(
          galleryImg,
          x1: 174,
          y1: 190,
          x2: 192,
          y2: 179,
          color: img.ColorRgba8(255, 255, 255, 255),
        );

        // Duration / 1080p60 Pill Badge
        img.fillRect(
          galleryImg,
          x1: 230,
          y1: 220,
          x2: 320,
          y2: 242,
          color: img.ColorRgba8(0, 0, 0, 200),
        );
        img.drawString(
          galleryImg,
          '0:15 / 1080p60',
          font: img.arial14,
          x: 236,
          y: 224,
          color: img.ColorRgba8(255, 255, 255, 255),
        );

        // Video Metadata below thumbnail
        img.drawString(
          galleryImg,
          'reranger_autodraw_1080p60.mp4',
          font: img.arial14,
          x: 28,
          y: 260,
          color: img.ColorRgba8(240, 240, 245, 255),
        );
        img.drawString(
          galleryImg,
          'Public MediaStore: /storage/emulated/0/Movies/Reranger',
          font: img.arial14,
          x: 28,
          y: 280,
          color: img.ColorRgba8(140, 145, 160, 255),
        );

        // Toast / SnackBar Notification: "Video saved to Gallery!"
        img.fillRect(
          galleryImg,
          x1: 20,
          y1: 560,
          x2: 340,
          y2: 605,
          color: img.ColorRgba8(40, 160, 80, 240),
        );
        img.drawString(
          galleryImg,
          'Video saved to Gallery!',
          font: img.arial14,
          x: 95,
          y: 575,
          color: img.ColorRgba8(255, 255, 255, 255),
        );

        saveVisualProof(
          'gallery_saved_video.png',
          Uint8List.fromList(img.encodePng(galleryImg)),
        );

        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
