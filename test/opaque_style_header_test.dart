import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zarq_messenger/services/user_settings_provider.dart';
import 'package:zarq_messenger/widgets/opaque_header.dart';
import 'package:zarq_messenger/widgets/opaque_style_panel.dart';

void main() {
  testWidgets('Style edits persist without overwriting unrelated preferences', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'bubble_color_start': '123456',
      'bubble_color_end': '654321',
      'group_screen_style': 'dynamic',
      'card_bubble_color': 'green',
    });
    final settings = UserSettingsProvider();
    await tester.pump();
    bool? overlay;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer<UserSettingsProvider>(
              builder: (_, value, __) => OpaqueStylePanel(
                settings: value,
                circularOverlay: true,
                onOverlayChanged: (v) => overlay = v,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(settings.colorStartHex, '123456');
    expect(settings.colorEndHex, '654321');
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.isDarkMode, isTrue);
    await tester.tap(find.text('Squared'));
    await tester.pumpAndSettle();
    expect(settings.bubbleStyleKey, 'square_corners');
    await tester.ensureVisible(find.byTooltip('Start colour: Mint'));
    await tester.tap(find.byTooltip('Start colour: Mint'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('End colour: Violet'));
    await tester.tap(find.byTooltip('End colour: Violet'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bubble_color_start'), '70B9A4');
    expect(prefs.getString('bubble_color_end'), '8066B8');
    expect(prefs.getBool('is_dark_mode'), isTrue);
    expect(prefs.getString('group_screen_style'), 'dynamic');
    expect(prefs.getString('card_bubble_color'), 'green');
    await tester.scrollUntilVisible(
      find.text('Horizontal bar'),
      120,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('Horizontal bar'));
    await tester.pumpAndSettle();
    expect(overlay, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('Header stays centred and menu works at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? selected;
      bool profileOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: OpaqueHeader(
              isDark: false,
              profile: const ColoredBox(color: Colors.grey),
              onProfile: () => profileOpened = true,
              menuItems: const [
                PopupMenuItem(value: 'settings', child: Text('Settings')),
              ],
              onMenuSelected: (value) => selected = value,
            ),
          ),
        ),
      );
      final brand = find.bySemanticsLabel('OPAQUE');
      expect(tester.getCenter(brand).dx, closeTo(width / 2, .5));
      await tester.tap(find.byTooltip('Your profile'));
      expect(profileOpened, isTrue);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(selected, 'settings');
      expect(tester.takeException(), isNull);
    });
  }
}
