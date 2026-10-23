import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reranger/core/theme/color_tokens.dart';
import 'package:reranger/main.dart';

void main() {
  group('Theme, Tokens & Touch Target Accessibility Tests', () {
    testWidgets('App applies Dark Studio Theme tokens by default', (
      tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: RerangerApp()));
      await tester.pumpAndSettle();

      // Theme scaffold background must match darkBgCanvas token
      final theme = Theme.of(tester.element(find.text('RERANGER')));
      expect(
        theme.scaffoldBackgroundColor,
        equals(AppColorTokens.darkBgCanvas),
      );
      expect(theme.colorScheme.surface, equals(AppColorTokens.darkSurfaceBase));
      expect(
        theme.colorScheme.primary,
        equals(AppColorTokens.darkAccentPrimary),
      );
    });

    testWidgets(
      'Select Image CTA satisfies minimum 48dp touch target requirement',
      (tester) async {
        await tester.pumpWidget(const ProviderScope(child: RerangerApp()));
        await tester.pumpAndSettle();

        final ctaFinder = find.widgetWithText(ElevatedButton, 'Select Image');
        expect(ctaFinder, findsOneWidget);

        final ctaSize = tester.getSize(ctaFinder);
        expect(ctaSize.height, greaterThanOrEqualTo(48.0));
        expect(ctaSize.width, greaterThanOrEqualTo(48.0));
      },
    );

    testWidgets('Semantics are present and accessible', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const ProviderScope(child: RerangerApp()));
      await tester.pumpAndSettle();

      final settingsAction = find.descendant(
        of: find.byType(AppBar),
        matching: find.byTooltip('Settings'),
      );

      expect(
        tester.getSemantics(settingsAction),
        matchesSemantics(
          tooltip: 'Settings',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );

      handle.dispose();
    });
  });
}
