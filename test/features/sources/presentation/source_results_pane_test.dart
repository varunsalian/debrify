import 'package:debrify/features/sources/presentation/source_results_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'user drag alone freezes results; list stays lazy and controller borrowed',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var userScrolls = 0;
      var parentNotifications = 0;
      final built = <int>{};
      Future<void> mount(int count) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: NotificationListener<ScrollNotification>(
                onNotification: (_) {
                  parentNotifications++;
                  return false;
                },
                child: SourceResultsPane(
                  count: count,
                  controller: controller,
                  isTelevision: true,
                  redesign: true,
                  onUserScroll: () => userScrolls++,
                  emptyBuilder: (_) => const Center(child: Text('Empty')),
                  pendingResults: const Text('Arrivals'),
                  itemBuilder: (_, index) {
                    built.add(index);
                    return SizedBox(height: 50, child: Text('Row $index'));
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await mount(100);
      expect(built.length, lessThan(100));
      expect(find.text('Arrivals'), findsOneWidget);
      controller.jumpTo(80);
      await tester.pump();
      expect(userScrolls, 0);
      expect(parentNotifications, greaterThan(0));
      await tester.drag(find.byType(ListView), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(userScrolls, 1);
      await mount(0);
      expect(find.byType(ListView), findsNothing);
      expect(find.text('Empty'), findsOneWidget);
      expect(find.text('Arrivals'), findsOneWidget);
      expect(controller.hasClients, isFalse);
      await mount(100);
      expect(controller.hasClients, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
