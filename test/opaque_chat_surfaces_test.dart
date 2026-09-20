import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zarq_messenger/widgets/opaque_chat_surfaces.dart';

void main() {
  testWidgets(
    'Modern confirmation fits large text and preserves cancel/confirm',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var confirmed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => OpaqueChatConfirmation(
                    icon: Icons.block,
                    title: 'Block this person?',
                    description: 'Stop messages from this person.',
                    note: 'You can unblock them anytime from the chat menu.',
                    actionLabel: 'Block user',
                    onConfirm: () {
                      confirmed++;
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(confirmed, 0);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Block user'));
      await tester.tap(find.text('Block user'));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('Dialog remains usable at large text in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (context) => OpaqueChatDialog(
                      title: const Text('Delete for everyone?'),
                      content: const Text(
                        'These messages will be deleted for all participants.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(context, 'delete_for_everyone'),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(result, 'delete_for_everyone');
    });
  }
  testWidgets('Notice wraps without overflow and sheet returns media choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                const MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: OpaqueEncryptionNotice(),
                ),
                TextButton(
                  child: const Text('Media'),
                  onPressed: () async {
                    result = await showModalBottomSheet<bool>(
                      context: context,
                      builder: (context) => OpaqueChatSheet(
                        title: 'Choose media',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              title: const Text('Photo'),
                              onTap: () => Navigator.pop(context, false),
                            ),
                            ListTile(
                              title: const Text('Video'),
                              onTap: () => Navigator.pop(context, true),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
