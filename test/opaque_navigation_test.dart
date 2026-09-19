import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zarq_messenger/widgets/opaque_navigation.dart';

void main() {
  for (final width in [320.0, 360.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'Five destinations and four friend tabs work at $width dark=$dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var selected = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: DefaultTabController(
                length: 4,
                child: Builder(
                  builder: (context) => StatefulBuilder(
                    builder: (context, update) => Scaffold(
                      body: Column(
                        children: [
                          OpaqueFriendTabs(
                            controller: DefaultTabController.of(context),
                            isDark: dark,
                          ),
                          const Expanded(
                            child: TabBarView(
                              children: [
                                Text('my-list'),
                                Text('received-list'),
                                Text('sent-list'),
                                Text('find-list'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      bottomNavigationBar: OpaqueBottomNavigation(
                        index: selected,
                        isDark: dark,
                        onSelected: (index) => update(() => selected = index),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          for (var i = 0; i < OpaqueBottomNavigation.destinations.length; i++) {
            await tester.tap(
              find.text(OpaqueBottomNavigation.destinations[i].$1),
            );
            await tester.pumpAndSettle();
            expect(selected, i);
          }
          expect(find.text('Groups'), findsNothing);
          for (final tab in [
            ('Received', 'received-list'),
            ('Sent', 'sent-list'),
            ('Find Friends', 'find-list'),
            ('My Friends', 'my-list'),
          ]) {
            await tester.tap(find.text(tab.$1));
            await tester.pumpAndSettle();
            expect(find.text(tab.$2).hitTestable(), findsOneWidget);
          }
          final first = tester.getCenter(find.text('My Friends')).dx;
          final second = tester.getCenter(find.text('Received')).dx;
          expect(second - first, closeTo(width / 4, 1));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
