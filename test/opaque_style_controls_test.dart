import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zarq_messenger/screens/style_screen.dart';
import 'package:zarq_messenger/services/user_settings_provider.dart';
import 'package:zarq_messenger/widgets/message_bubble_style.dart';
import 'package:zarq_messenger/widgets/opaque_style_panel.dart';

Future<UserSettingsProvider> openStyle(
  WidgetTester tester, {
  bool embedded = false,
}) async {
  final settings = UserSettingsProvider();
  await tester.pump();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(home: StyleScreen(embedded: embedded)),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

Future<void> tap(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable);
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(target, 120, scrollable: scrollable);
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final saved in [null, false, true]) {
    testWidgets('Overlay honors saved $saved and persists across reopening', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        if (saved != null) 'call_overlay_circular': saved,
      });
      await openStyle(tester);
      OpaqueStylePanel panel() => tester.widget(find.byType(OpaqueStylePanel));
      expect(panel().circularOverlay, saved ?? true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('call_overlay_circular'), saved);
      await tap(tester, find.text('Horizontal bar'));
      expect(panel().circularOverlay, isFalse);
      expect(prefs.getBool('call_overlay_circular'), isFalse);
      await tester.pumpWidget(const SizedBox());
      await openStyle(tester, embedded: true);
      expect(panel().circularOverlay, isFalse);
      await tap(tester, find.text('Circular bubble'));
      expect(prefs.getBool('call_overlay_circular'), isTrue);
      expect(find.textContaining('More appearance'), findsNothing);
      expect(find.text('Notes Security'), findsNothing);
      expect(find.text('Group Screen'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Every theme, shape and palette control persists; unrelated settings survive',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'bubble_style': 'minimalist',
        'bubble_color_start': '123456',
        'bubble_color_end': '654321',
        'group_screen_style': 'dynamic',
        'encryption_animation_style': 'minimal',
        'card_bubble_color': 'green',
      });
      final settings = await openStyle(tester);
      expect(settings.bubbleStyleKey, 'minimalist');
      expect(settings.colorEndHex, '654321');
      expect(find.text('Minimal'), findsNothing);
      expect(find.text('Modern cards'), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      for (final theme in [('Dark', true), ('Light', false)]) {
        await tap(tester, find.text(theme.$1));
        expect(settings.isDarkMode, theme.$2);
      }
      for (final shape in [
        ('Soft', 'default_rounded'),
        ('Rounded', 'soft_edges'),
        ('Squared', 'square_corners'),
      ]) {
        await tap(tester, find.text(shape.$1));
        expect(settings.bubbleStyleKey, shape.$2);
        tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        final preview = tester.widget<Container>(
          find
              .ancestor(
                of: find.text('Absolutely. Same place?'),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = preview.decoration! as BoxDecoration;
        expect(
          decoration.borderRadius,
          messageBubbleRadius(true, shape.$2, 800, preview: true),
        );
      }
      await tap(tester, find.text('Soft'));
      for (final color in OpaqueStylePanel.starts) {
        final end = settings.colorEndHex;
        await tap(tester, find.byTooltip('Start colour: ${color.$1}'));
        expect(settings.colorStartHex, color.$2);
        expect(settings.colorEndHex, end);
      }
      for (final color in OpaqueStylePanel.ends) {
        final start = settings.colorStartHex;
        await tap(tester, find.byTooltip('End colour: ${color.$1}'));
        expect(settings.colorEndHex, color.$2);
        expect(settings.colorStartHex, start);
      }
      final restored = UserSettingsProvider();
      await tester.pump();
      expect(restored.colorStartHex, 'D9AD76');
      expect(restored.colorEndHex, 'B88853');
      expect(restored.bubbleStyleKey, 'default_rounded');
      expect(restored.cardBubbleColor, 'green');
      expect(restored.groupScreenStyle, 'dynamic');
      expect(restored.encryptionAnimationStyle, 'minimal');
      expect(tester.takeException(), isNull);
    },
  );

  test('Approved radii match the reference in preview and actual chat', () {
    for (final width in [320.0, 360.0, 800.0]) {
      for (final mine in [false, true]) {
        for (final preview in [false, true]) {
          expect(
            messageBubbleRadius(mine, 'soft_edges', width, preview: preview),
            BorderRadius.circular(21),
          );
          expect(
            messageBubbleRadius(
              mine,
              'square_corners',
              width,
              preview: preview,
            ),
            BorderRadius.circular(7),
          );
          final soft = messageBubbleRadius(
            mine,
            'default_rounded',
            width,
            preview: preview,
          );
          expect(mine ? soft.topRight : soft.topLeft, const Radius.circular(4));
          expect(soft.bottomLeft, Radius.circular(preview ? 14 : 16));
          expect(soft.bottomRight, Radius.circular(preview ? 14 : 16));
        }
      }
    }
  });
}
