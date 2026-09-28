import 'package:debrify/features/home/presentation/home_detail_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    'normal',
    'covered',
    'replaced',
    'retired',
    'before-push',
  ]) {
    testWidgets('detail route ownership: $scenario', (tester) async {
      final key = GlobalKey<NavigatorState>();
      var current = true, returns = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: const Scaffold(body: Text('Home')),
        ),
      );
      final owner = HomeDetailRoute(
        name: 'detail',
        isOwnerCurrent: () => current,
        onClosed: () => returns++,
      );
      if (scenario == 'before-push') current = false;
      final closed = owner.push(
        key.currentState!,
        (_) => const Scaffold(body: Text('Original')),
      );
      await tester.pumpAndSettle();
      if (scenario == 'before-push') {
        await closed;
        expect(find.text('Original'), findsNothing);
        expect(returns, 0);
        return;
      }
      expect(owner.isActive, isTrue);
      if (scenario == 'replaced') {
        key.currentState!.pop();
        await tester.pumpAndSettle();
        expect(owner.isActive, isFalse);
        expect(returns, 1);
      }
      if (scenario == 'covered' || scenario == 'replaced') {
        final newer = key.currentState!.push<void>(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'detail'),
            builder: (_) => const Scaffold(body: Text('Newer')),
          ),
        );
        await tester.pumpAndSettle();
        expect(owner.closeIfCurrent(), isFalse);
        await tester.pumpAndSettle();
        expect(find.text('Newer'), findsOneWidget);
        key.currentState!.pop();
        await newer;
        await tester.pumpAndSettle();
      }
      if (scenario == 'retired') {
        current = false;
        expect(owner.isActive, isFalse);
        expect(owner.closeIfCurrent(), isFalse);
        key.currentState!.pop();
      } else if (scenario != 'replaced') {
        expect(owner.closeIfCurrent(), isTrue);
      }
      await closed;
      await tester.pumpAndSettle();
      expect(returns, scenario == 'retired' ? 0 : 1);
      expect(owner.closeIfCurrent(), isFalse);
      expect(find.text('Home'), findsOneWidget);
    });
  }
}
