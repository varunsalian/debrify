import 'package:debrify/widgets/debrid_loading_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RouteLog extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

void main() {
  for (final suppressed in [false, true]) {
    testWidgets(
      'owned loader retains route/Back contract (suppressed: $suppressed)',
      (tester) async {
        final observer = RouteLog();
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            home: Builder(
              builder: (value) {
                context = value;
                return const Scaffold(body: Text('Home'));
              },
            ),
          ),
        );
        final handle = DebridLoadingOverlay.show(
          context,
          provider: 'Fixture',
          torrentName: 'Fixture title',
          suppressVisual: suppressed,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final route = observer.pushed.last as RawDialogRoute<void>;
        expect(route.barrierDismissible, isFalse);
        expect(
          route.barrierColor,
          suppressed ? Colors.transparent : Colors.black.withValues(alpha: 0.7),
        );
        expect(
          route.transitionDuration,
          suppressed ? Duration.zero : const Duration(milliseconds: 300),
        );
        expect(
          find.text('Adding to Fixture'),
          suppressed ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('Fixture title'),
          suppressed ? findsNothing : findsOneWidget,
        );
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(route.isActive, suppressed);
        handle.dismiss();
        handle.dismiss();
        await tester.pumpAndSettle();
        expect(route.isActive, isFalse);
        expect(find.text('Home'), findsOneWidget);
        expect(Navigator.of(context).canPop(), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('normal dismissal keeps exit animation and is idempotent', (
    tester,
  ) async {
    final observer = RouteLog();
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold(body: Text('Home'));
          },
        ),
      ),
    );
    final handle = DebridLoadingOverlay.showTorbox(context, 'Fixture');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    handle.dismiss();
    handle.dismiss();
    await tester.pump();
    expect(find.text('Adding to Torbox'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Adding to Torbox'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Adding to Torbox'), findsNothing);
    expect(Navigator.of(context).canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loader belongs to root navigator when launched from nested route',
    (tester) async {
      final root = RouteLog();
      final nested = RouteLog();
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [root],
          home: Navigator(
            observers: [nested],
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (value) {
                context = value;
                return const Scaffold(body: Text('Nested'));
              },
            ),
          ),
        ),
      );
      final handle = DebridLoadingOverlay.showRealDebrid(context, 'Fixture');
      await tester.pump();
      expect(root.pushed, hasLength(2));
      expect(nested.pushed, hasLength(1));
      handle.dismiss();
      await tester.pumpAndSettle();
      expect(root.pushed.last.isActive, isFalse);
      expect(nested.pushed.single.isCurrent, isTrue);
      expect(find.text('Nested'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
