import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Player extends StatefulWidget {
  const _Player({required this.onDispose});
  final VoidCallback onDispose;
  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  int position = 42;
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text('Player $position'));
}

void main() {
  testWidgets(
    'a new player replaces parked playback even without PiP callbacks',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      var disposals = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Browse')),
        ),
      );
      final first = IosPipPlayerRoute<void>(
        builder: (_) => _Player(onDispose: () => disposals++),
      );
      navigator.currentState!.push(first);
      await tester.pumpAndSettle();
      first.session.park();
      await tester.pumpAndSettle();
      navigator.currentState!.push(
        IosPipPlayerRoute<void>(
          builder: (_) => const Scaffold(body: Text('New video')),
        ),
      );
      await tester.pumpAndSettle();
      expect(disposals, 1);
      expect(first.session.wasReplaced, isTrue);
      expect(first.session.restore(), isFalse);
      expect(find.text('New video'), findsOneWidget);
    },
  );

  testWidgets(
    'parked completion delivers its result without popping browsing',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Browse')),
        ),
      );
      final route = IosPipPlayerRoute<Map<String, dynamic>>(
        builder: (_) => _Player(onDispose: () {}),
      );
      final result = navigator.currentState!.push(route);
      await tester.pumpAndSettle();
      route.session.park();
      await tester.pumpAndSettle();
      route.session.close({'quickPlayNext': true});
      await tester.pumpAndSettle();
      expect(await result, {'quickPlayNext': true});
      expect(find.text('Browse'), findsOneWidget);
      expect(navigator.currentState!.canPop(), isFalse);
    },
  );

  testWidgets(
    'PiP releases navigation and restores the same player above browsing',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      var disposals = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Browse')),
        ),
      );
      final route = IosPipPlayerRoute<String>(
        builder: (_) => _Player(onDispose: () => disposals++),
      );
      var completed = false;
      final result = navigator.currentState!.push(route).then((value) {
        completed = true;
        return value;
      });
      await tester.pumpAndSettle();
      final player = tester.state<_PlayerState>(find.byType(_Player));
      player.position = 123;
      expect(route.session.park(), isTrue);
      await tester.pumpAndSettle();
      expect(disposals, 0);
      expect(completed, isFalse);
      expect(find.text('Browse'), findsOneWidget);
      expect(find.byType(_Player), findsNothing);
      expect(navigator.currentState!.canPop(), isFalse);

      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another detail')),
        ),
      );
      await tester.pumpAndSettle();
      expect(route.session.restore(), isTrue);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(_Player)), same(player));
      expect(find.text('Player 123'), findsOneWidget);
      expect(disposals, 0);
      // A second PiP cycle must preserve the original caller's result too.
      expect(route.session.park(), isTrue);
      await tester.pumpAndSettle();
      expect(completed, isFalse);
      expect(route.session.restore(), isTrue);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(_Player)), same(player));
      navigator.currentState!.pop('finished');
      await tester.pumpAndSettle();
      expect(find.text('Another detail'), findsOneWidget);
      expect(disposals, 1);
      expect(await result, 'finished');
      expect(route.session.restore(), isFalse);
    },
  );

  testWidgets('closing parked PiP disposes once without changing browsing', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    var disposals = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Browse')),
      ),
    );
    final route = IosPipPlayerRoute<void>(
      builder: (_) => _Player(onDispose: () => disposals++),
    );
    navigator.currentState!.push(route);
    await tester.pumpAndSettle();
    route.session.park();
    await tester.pumpAndSettle();
    route.session.close();
    route.session.close();
    await tester.pumpAndSettle();
    expect(disposals, 1);
    expect(find.text('Browse'), findsOneWidget);
    expect(route.session.restore(), isFalse);
  });

  testWidgets('a covered player cannot dismiss a newer route to enter PiP', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    var disposals = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Browse')),
      ),
    );
    final route = IosPipPlayerRoute<void>(
      builder: (_) => _Player(onDispose: () => disposals++),
    );
    navigator.currentState!.push(route);
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Newer route')),
      ),
    );
    await tester.pumpAndSettle();
    expect(route.session.park(), isFalse);
    expect(find.text('Newer route'), findsOneWidget);
    expect(disposals, 0);
  });
}
