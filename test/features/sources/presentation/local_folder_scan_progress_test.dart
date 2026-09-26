import 'dart:async';

import 'package:debrify/features/sources/presentation/local_folder_scan_progress.dart';
import 'package:debrify/models/local_source_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Routes extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

void main() {
  late BuildContext page;
  late GlobalKey<NavigatorState> navigator;
  late Routes routes;
  Future<void> host(WidgetTester tester, {bool nested = false}) async {
    navigator = GlobalKey<NavigatorState>();
    routes = Routes();
    Widget origin() => Builder(
      builder: (context) {
        page = context;
        return const Scaffold(body: Text('Origin'));
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [routes],
        home: nested ? const Scaffold(body: Text('Landing')) : origin(),
      ),
    );
    if (nested) {
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => origin()),
        ),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('progress blocks Back and returns the original scan result', (
    tester,
  ) async {
    await host(tester);
    final scan = Completer<List<LocalSourceDocument>>();
    final pending = readLocalFolderWithProgress(page, scan: () => scan.future);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Reading local folder…'), findsOneWidget);
    expect((routes.pushed.last as DialogRoute).barrierDismissible, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(routes.pushed.last.isActive, isTrue);
    final result = <LocalSourceDocument>[];
    scan.complete(result);
    expect(await pending, same(result));
    await tester.pumpAndSettle();
    expect(find.text('Reading local folder…'), findsNothing);
    expect(navigator.currentState!.canPop(), isFalse);
  });

  testWidgets('scan error propagates after removing progress', (tester) async {
    await host(tester);
    final scan = Completer<List<LocalSourceDocument>>();
    final pending = readLocalFolderWithProgress(page, scan: () => scan.future);
    final failure = StateError('scan failed');
    final checked = expectLater(pending, throwsA(same(failure)));
    await tester.pump(const Duration(milliseconds: 300));
    scan.completeError(failure);
    await checked;
    await tester.pumpAndSettle();
    expect(find.text('Reading local folder…'), findsNothing);
    expect(navigator.currentState!.canPop(), isFalse);
  });

  testWidgets('retired entry dispatches neither scan nor route', (
    tester,
  ) async {
    await host(tester);
    var calls = 0;
    final result = await readLocalFolderWithProgress(
      page,
      scan: () async {
        calls++;
        return [];
      },
      canContinue: () => false,
    );
    expect(result, isEmpty);
    expect(calls, 0);
    expect(routes.pushed, hasLength(1));
  });

  for (final change in [
    'route_above',
    'loader_removed',
    'origin_removed',
    'navigator_disposed',
  ]) {
    testWidgets('retired scan cleans only its progress after $change', (
      tester,
    ) async {
      await host(tester, nested: change == 'origin_removed');
      final origin = routes.pushed.last;
      final scan = Completer<List<LocalSourceDocument>>();
      var active = true;
      final pending = readLocalFolderWithProgress(
        page,
        scan: () => scan.future,
        canContinue: () => active,
      );
      await tester.pump(const Duration(milliseconds: 300));
      final progress = routes.pushed.last;
      if (change == 'route_above') {
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('New screen')),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
      } else if (change == 'loader_removed') {
        navigator.currentState!.removeRoute(progress);
        await tester.pump();
      } else if (change == 'origin_removed') {
        navigator.currentState!.removeRoute(origin);
        await tester.pump();
      } else {
        await tester.pumpWidget(const SizedBox());
      }
      active = false;
      scan.complete([
        const LocalSourceDocument(
          uri: 'content://fixture',
          name: 'Movie.mkv',
          relativePath: 'Movie.mkv',
          isDirectory: false,
          sizeBytes: 1,
          modifiedAt: 0,
        ),
      ]);
      expect(await pending, isEmpty);
      await tester.pumpAndSettle();
      expect(find.text('Reading local folder…'), findsNothing);
      if (change == 'route_above') {
        expect(find.text('New screen'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('Origin'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
