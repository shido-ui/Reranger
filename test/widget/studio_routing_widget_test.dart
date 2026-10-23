import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reranger/domain/color/color_palette.dart';
import 'package:reranger/features/editor/presentation/editor_screen.dart';
import 'package:reranger/features/humanize/presentation/humanize_controller.dart';
import 'package:reranger/features/humanize/presentation/humanize_screen.dart';
import 'package:reranger/features/recolor/presentation/recolor_controller.dart';
import 'package:reranger/features/recolor/presentation/recolor_screen.dart';
import 'package:reranger/humanize/local_humanize_adapter.dart';

void main() {
  const testProjectId = 'proj_routing_123';

  Widget buildTestableWidget(Widget child) {
    return ProviderScope(child: MaterialApp(home: child));
  }

  testWidgets(
    'EditorScreen displays Recolor and Humanize studio entry buttons (Prompt B)',
    (tester) async {
      // Render EditorScreen directly
      await tester.pumpWidget(
        buildTestableWidget(
          const Scaffold(body: EditorScreen(projectId: testProjectId)),
        ),
      );
      await tester.pump();

      // Verify studio buttons exist
      expect(
        find.byKey(const ValueKey('recolor_studio_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('humanize_studio_button')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'RecolorScreen renders interactive palette remapping studio (Prompt B)',
    (tester) async {
      const w = 32;
      const h = 32;
      final rgba = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 150);

      final palette = ColorPalette(
        id: 'pal_test',
        name: 'Test Palette',
        colors: const [
          ColorRgb(200, 50, 50),
          ColorRgb(50, 200, 50),
          ColorRgb(50, 50, 200),
        ],
      );

      final controller = RecolorController(
        sourceRgba: rgba,
        imageWidth: w,
        imageHeight: h,
        sourceImageHash: 'sha_test_recolor',
        initialPalette: palette,
      );

      await tester.pumpWidget(
        buildTestableWidget(
          RecolorScreen(projectId: testProjectId, controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Recolor Studio elements
      expect(find.text('Recolor Studio'), findsOneWidget);
      expect(find.text('Select Color to Remap'), findsOneWidget);
      expect(find.text('Target Replacement Color'), findsOneWidget);
      expect(find.text('Precision & Mask Controls'), findsOneWidget);

      // Select second color
      await tester.tap(find.byType(GestureDetector).at(3));
      await tester.pumpAndSettle();

      expect(controller.state.canUndo, isTrue);
    },
  );

  testWidgets('Humanize router integration renders truthful gating or looks', (
    tester,
  ) async {
    final adapter = LocalHumanizeAdapter(
      totalRamBytes: 12 * 1024 * 1024 * 1024,
      isLoadedForTesting: true,
    );
    final controller = HumanizeController(adapter: adapter);
    await controller.initialize(
      sourceImageBytes: Uint8List(32 * 32 * 4)..fillRange(0, 32 * 32 * 4, 180),
      width: 32,
      height: 32,
    );

    await tester.pumpWidget(
      buildTestableWidget(HumanizeScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Humanize Studio'), findsOneWidget);
    expect(find.text('Naturalistic'), findsOneWidget);
    expect(find.text('Hand-painted'), findsOneWidget);
  });
}
