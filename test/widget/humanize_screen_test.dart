import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:reranger/features/humanize/presentation/humanize_controller.dart';
import 'package:reranger/features/humanize/presentation/humanize_screen.dart';
import 'package:reranger/humanize/humanize_adapter.dart';
import 'package:reranger/humanize/local_humanize_adapter.dart';

void main() {
  const gb = 1024 * 1024 * 1024;

  Uint8List createDummyImage(int w, int h) {
    final image = img.Image(width: w, height: h, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(120, 160, 200, 255));
    return Uint8List.fromList(img.encodePng(image));
  }

  Widget buildTestableWidget(
    Widget child, {
    Size size = const Size(360, 800),
    double fontScale = 1.0,
  }) {
    return MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(fontScale),
      ),
      child: MaterialApp(home: child),
    );
  }

  group('HumanizeScreen Level 1 Beginner UX & Guardrails', () {
    testWidgets('Renders <= 3 look choices and exactly one dominant CTA', (
      tester,
    ) async {
      final adapter = LocalHumanizeAdapter(
        totalRamBytes: 12 * gb,
        isLoadedForTesting: true,
      );
      final controller = HumanizeController(adapter: adapter);
      await controller.initialize(
        sourceImageBytes: createDummyImage(32, 32),
        width: 32,
        height: 32,
      );

      await tester.pumpWidget(
        buildTestableWidget(HumanizeScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Exactly 3 looks
      expect(find.text('Naturalistic'), findsOneWidget);
      expect(find.text('Hand-painted'), findsOneWidget);
      expect(find.text('Artistic Reinterpretation'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(3));

      // Single Dominant CTA
      expect(
        find.widgetWithText(ElevatedButton, 'Humanize Photo'),
        findsOneWidget,
      );

      // Disclaimer guardrail
      expect(
        find.textContaining('Higher strength re-synthesizes micro-textures'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Does not claim undetectable AI'),
        findsOneWidget,
      );
    });

    testWidgets('Selecting a look updates strength parameter appropriately', (
      tester,
    ) async {
      final adapter = LocalHumanizeAdapter(
        totalRamBytes: 12 * gb,
        isLoadedForTesting: true,
      );
      final controller = HumanizeController(adapter: adapter);
      await controller.initialize(
        sourceImageBytes: createDummyImage(32, 32),
        width: 32,
        height: 32,
      );

      await tester.pumpWidget(
        buildTestableWidget(HumanizeScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Initial is Naturalistic (20%)
      expect(find.text('20%'), findsOneWidget);

      // Tap Hand-painted (35%)
      await tester.tap(find.text('Hand-painted'));
      await tester.pumpAndSettle();
      expect(controller.selectedLook, equals(HumanizeLook.handPainted));
      expect(controller.strength, equals(0.35));
      expect(find.text('35%'), findsOneWidget);

      // Tap Artistic Reinterpretation (55%)
      await tester.tap(find.text('Artistic Reinterpretation'));
      await tester.pumpAndSettle();
      expect(controller.selectedLook, equals(HumanizeLook.artistic));
      expect(controller.strength, equals(0.55));
      expect(find.text('55%'), findsOneWidget);
    });

    testWidgets('Hold-to-compare displays ORIGINAL (BEFORE) badge', (
      tester,
    ) async {
      final adapter = LocalHumanizeAdapter(
        totalRamBytes: 12 * gb,
        isLoadedForTesting: true,
      );
      final controller = HumanizeController(adapter: adapter);
      await controller.initialize(
        sourceImageBytes: createDummyImage(32, 32),
        width: 32,
        height: 32,
      );

      await tester.pumpWidget(
        buildTestableWidget(HumanizeScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('SOURCE IMAGE'), findsOneWidget);

      // Hold down gesture
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('humanize_viewport_image'))),
      );
      await tester.pump();
      expect(find.text('ORIGINAL (BEFORE)'), findsOneWidget);

      // Release gesture
      await gesture.up();
      await tester.pump();
      expect(find.text('SOURCE IMAGE'), findsOneWidget);
    });
  });

  group('HumanizeScreen Running & Cancellation States', () {
    testWidgets(
      'Running state displays authentic progress and cancellable operation',
      (tester) async {
        final adapter = LocalHumanizeAdapter(
          totalRamBytes: 12 * gb,
          isLoadedForTesting: true,
        );
        final controller = HumanizeController(adapter: adapter);
        await controller.initialize(
          sourceImageBytes: createDummyImage(32, 32),
          width: 32,
          height: 32,
        );

        await tester.pumpWidget(
          buildTestableWidget(HumanizeScreen(controller: controller)),
        );
        await tester.pumpAndSettle();

        // Trigger humanize
        controller.humanize();
        await tester.pump(const Duration(milliseconds: 1));

        expect(controller.isRunning, isTrue);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);

        // Tap cancel
        await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
        await tester.pumpAndSettle();

        expect(controller.status, equals(HumanizeUiStatus.cancelled));
        expect(controller.isRunning, isFalse);
      },
    );
  });

  group('SCR-11: Truthful Hardware & Weights Gating View', () {
    testWidgets(
      'Unsupported hardware (< 6 GB RAM) displays informative gating card with Back CTA',
      (tester) async {
        const adapter = TruthfulUnavailableHumanizeAdapter(
          tier: HardwareTier.unsupportedOomRisk,
          reason: 'Host device total physical RAM (4096 MB) is below the minimum 6 GB threshold.',
        );
        final controller = HumanizeController(adapter: adapter);
        bool backPressed = false;

        await controller.initialize(
          sourceImageBytes: createDummyImage(32, 32),
          width: 32,
          height: 32,
        );

        await tester.pumpWidget(
          buildTestableWidget(
            HumanizeScreen(
              controller: controller,
              onBackToConventional: () => backPressed = true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(controller.isGated, isTrue);
        expect(
          find.text('Humanize Studio Unavailable on this Device'),
          findsOneWidget,
        );
        expect(
          find.textContaining('below the minimum 6 GB threshold'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(ElevatedButton, 'Back to Conventional Studio'),
          findsOneWidget,
        );

        await tester.tap(
          find.widgetWithText(ElevatedButton, 'Back to Conventional Studio'),
        );
        await tester.pumpAndSettle();
        expect(backPressed, isTrue);
      },
    );

    testWidgets(
      'Model not installed displays informative on-demand download gating card',
      (tester) async {
        final adapter = LocalHumanizeAdapter(
          totalRamBytes: 12 * gb,
          isLoadedForTesting: false, // Model not installed
        );
        final controller = HumanizeController(adapter: adapter);

        await controller.initialize(
          sourceImageBytes: createDummyImage(32, 32),
          width: 32,
          height: 32,
        );

        await tester.pumpWidget(
          buildTestableWidget(HumanizeScreen(controller: controller)),
        );
        await tester.pumpAndSettle();

        expect(controller.isGated, isTrue);
        expect(controller.status, equals(HumanizeUiStatus.modelNotInstalled));
        expect(
          find.text('Humanize Studio Unavailable on this Device'),
          findsOneWidget,
        );
        expect(
          find.textContaining('model weights are not installed'),
          findsOneWidget,
        );
      },
    );
  });

  group('Responsive Layout & Accessibility Semantics', () {
    testWidgets(
      'Compact 320x640 screen with 1.3 font scale renders without RenderFlex overflow',
      (tester) async {
        final adapter = LocalHumanizeAdapter(
          totalRamBytes: 12 * gb,
          isLoadedForTesting: true,
        );
        final controller = HumanizeController(adapter: adapter);
        await controller.initialize(
          sourceImageBytes: createDummyImage(32, 32),
          width: 32,
          height: 32,
        );

        await tester.pumpWidget(
          buildTestableWidget(
            HumanizeScreen(controller: controller),
            size: const Size(320, 640),
            fontScale: 1.3,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Controls contain accessible descriptions and tooltips', (
      tester,
    ) async {
      final adapter = LocalHumanizeAdapter(
        totalRamBytes: 12 * gb,
        isLoadedForTesting: true,
      );
      final controller = HumanizeController(adapter: adapter);
      await controller.initialize(
        sourceImageBytes: createDummyImage(32, 32),
        width: 32,
        height: 32,
      );

      await tester.pumpWidget(
        buildTestableWidget(HumanizeScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Naturalistic'),
      );
      expect(chip.tooltip, contains('De-glazes plastic AI skin'));
      expect(chip.selected, isTrue);

      expect(find.text('Anchor Subject Likeness'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });
  });
}
