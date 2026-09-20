import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zarq_messenger/about_screen.dart';
import 'package:zarq_messenger/screens/markdown_viewer_screen.dart';
import 'package:zarq_messenger/services/global_call_manager.dart';
import 'package:zarq_messenger/services/user_settings_provider.dart';

Future<UserSettingsProvider> openPage(
  WidgetTester tester,
  Widget page, {
  double scale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = UserSettingsProvider();
  await tester.pump();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: GlobalCallManager()),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return settings;
}

void main() {
  testWidgets('About reacts to saved theme and fits narrow enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = await openPage(tester, const AboutScreen(), scale: 2);
    await settings.saveSettings(isDarkMode: true);
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('OPAQUE').first);
    expect(title.style!.color, Colors.white);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFF19202A),
    );
    await tester.scrollUntilVisible(find.text('Contact Support'), 250);
    expect(tester.takeException(), isNull);
  });

  for (final entry in <(String, String, String)>[
    ('Privacy Policy', 'Privacy Policy', 'assets/privacy_policy.md'),
    ('Terms of Service', 'Terms of Service', 'assets/terms_of_service.md'),
    ('Contact Support', 'Contact & Support', 'assets/contact_support.md'),
  ]) {
    testWidgets('${entry.$1} opens its existing asset and returns to About', (
      tester,
    ) async {
      await openPage(tester, const AboutScreen());
      await tester.scrollUntilVisible(find.text(entry.$1), 250);
      await tester.tap(find.text(entry.$1));
      await tester.pumpAndSettle();
      final page = tester.widget<MarkdownViewerScreen>(
        find.byType(MarkdownViewerScreen),
      );
      expect(page.assetPath, entry.$3);
      expect(page.title, entry.$2);
      final markdown = tester.widget<Markdown>(find.byType(Markdown));
      expect(markdown.data, contains('opaquelabs.in@gmail.com'));
      expect(markdown.selectable, isTrue);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(AboutScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Missing document shows recoverable error', (tester) async {
    await openPage(
      tester,
      const MarkdownViewerScreen(
        title: 'Missing document',
        assetPath: 'assets/not-present.md',
      ),
    );
    expect(find.text('Could not load this document.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load this document.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
