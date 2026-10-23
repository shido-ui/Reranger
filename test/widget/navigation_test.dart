import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reranger/main.dart';

void main() {
  group('Navigation & Shell States Widget Tests', () {
    testWidgets(
      'App launches into HomeScreen with wordmark and Select Image CTA',
      (tester) async {
        await tester.pumpWidget(const ProviderScope(child: RerangerApp()));
        await tester.pumpAndSettle();

        // Home Screen Verification
        expect(find.text('RERANGER'), findsOneWidget);
        expect(find.text('Select Image'), findsOneWidget);
        expect(find.text('100% On-Device Photo Studio'), findsOneWidget);
        expect(find.byIcon(Icons.settings_outlined), findsAtLeastNWidgets(1));
      },
    );

    testWidgets(
      'Navigation bar navigates between Home, Creations, and Settings',
      (tester) async {
        await tester.pumpWidget(const ProviderScope(child: RerangerApp()));
        await tester.pumpAndSettle();

        // 1. Navigate to Creations
        await tester.tap(find.text('Creations'));
        await tester.pumpAndSettle();

        expect(find.text('No Creations Saved Yet'), findsOneWidget);
        expect(find.text('Creations'), findsWidgets);

        // 2. Navigate to Settings
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        expect(find.text('DEVICE & RUNTIME CAPABILITIES'), findsOneWidget);
        expect(find.text('PRIVACY & LICENSES'), findsOneWidget);
        expect(
          find.text('100% Local On-Device (Offline-First)'),
          findsOneWidget,
        );

        // 3. Navigate back to Home
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(find.text('RERANGER'), findsOneWidget);
        expect(find.text('Select Image'), findsOneWidget);
      },
    );

    testWidgets('Tapping Settings icon on Home app bar navigates to Settings', (
      tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: RerangerApp()));
      await tester.pumpAndSettle();

      // Tap settings action in app bar specifically
      final settingsAction = find.descendant(
        of: find.byType(AppBar),
        matching: find.byTooltip('Settings'),
      );
      await tester.tap(settingsAction);
      await tester.pumpAndSettle();

      expect(find.text('DEVICE & RUNTIME CAPABILITIES'), findsOneWidget);
      expect(find.text('Open Source Licenses'), findsOneWidget);
    });
  });
}
