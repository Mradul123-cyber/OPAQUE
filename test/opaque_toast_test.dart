import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zarq_messenger/widgets/opaque_toast.dart';

void main() {
  testWidgets('Toast stays directly above navigation even with a tall FAB', (tester) async {
    const navKey = Key('navigation');
    late BuildContext toastContext;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      bottomNavigationBar: const SizedBox(key: navKey, height: 72),
      floatingActionButton: const SizedBox(width: 44, height: 180),
      body: Builder(builder: (context) {
        toastContext = context;
        return const SizedBox();
      }),
    )));
    OpaqueToast.info(toastContext, 'Friend blocked');
    await tester.pumpAndSettle();
    final navTop = tester.getTopLeft(find.byKey(navKey)).dy;
    final textBottom = tester.getBottomLeft(find.text('Friend blocked')).dy;
    // Twelve pixels below the pill, plus ten pixels of internal padding.
    expect(navTop - textBottom, closeTo(22, 1));
    expect(tester.takeException(), isNull);
    OpaqueToast.info(toastContext, 'Friend unblocked');
    await tester.pumpAndSettle();
    expect(find.text('Friend blocked'), findsNothing);
    expect(find.text('Friend unblocked'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
