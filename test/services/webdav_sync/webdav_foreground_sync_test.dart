import 'dart:async';

import 'package:debrify/services/player_display_controls.dart';
import 'package:debrify/widgets/webdav_sync/webdav_foreground_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('landscape timeout and resume content stays scrollable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final done = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => runWebDavForegroundSync(
              context,
              stage: 'Restoring and finishing sync setup…',
              progressLimit: const Duration(seconds: 1),
              displayControls: PlayerDisplayControls(
                toggleWakelock: (_) async {},
              ),
              operation: (_) => done.future,
            ),
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.tap(find.text('Hide progress'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    done.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final failure in [false, true]) {
    testWidgets(
      'completion cleans up and preserves result (failure=$failure)',
      (tester) async {
        final done = Completer<int>();
        final wake = <bool>[];
        Object? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    try {
                      result = await runWebDavForegroundSync(
                        context,
                        stage: 'Checking account',
                        displayControls: PlayerDisplayControls(
                          toggleWakelock: (v) async => wake.add(v),
                        ),
                        operation: (stage) {
                          stage('Uploading');
                          return done.future;
                        },
                      );
                    } catch (error) {
                      result = error;
                    }
                  },
                  child: const Text('Start'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('Start'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Uploading'), findsOneWidget);
        expect(wake.last, isTrue);
        final error = StateError('offline');
        if (failure) {
          done.completeError(error);
        } else {
          done.complete(7);
        }
        await tester.pumpAndSettle();
        expect(result, failure ? same(error) : 7);
        expect(find.text('Syncing with WebDAV'), findsNothing);
        expect(wake.last, isFalse);
      },
    );
  }

  testWidgets('completion removes only its own route', (tester) async {
    final done = Completer<void>();
    late BuildContext host;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            host = context;
            return TextButton(
              onPressed: () => runWebDavForegroundSync(
                context,
                stage: 'Syncing',
                displayControls: PlayerDisplayControls(
                  toggleWakelock: (_) async {},
                ),
                operation: (_) => done.future,
              ),
              child: const Text('Start'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    unawaited(
      showDialog<void>(
        context: host,
        builder: (_) =>
            const AlertDialog(title: Text('Replacement confirmation')),
      ),
    );
    await tester.pump();
    done.complete();
    await tester.pumpAndSettle();
    expect(find.text('Replacement confirmation'), findsOneWidget);
    Navigator.of(host).pop();
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeout and hiding do not cancel or finish the operation', (
    tester,
  ) async {
    final done = Completer<int>();
    final wake = <bool>[];
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              await runWebDavForegroundSync(
                context,
                stage: 'Syncing',
                progressLimit: const Duration(seconds: 1),
                displayControls: PlayerDisplayControls(
                  toggleWakelock: (v) async => wake.add(v),
                ),
                operation: (_) => done.future,
              );
              completed = true;
            },
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Sync is taking longer'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(wake.last, isTrue);
    expect(completed, isFalse);
    await tester.tap(find.text('Hide progress'));
    await tester.pumpAndSettle();
    expect(wake.last, isFalse);
    expect(completed, isFalse);
    done.complete(1);
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background releases wake and return explains interruption', (
    tester,
  ) async {
    final done = Completer<void>();
    final wake = <bool>[];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => runWebDavForegroundSync(
              context,
              stage: 'Syncing',
              displayControls: PlayerDisplayControls(
                toggleWakelock: (v) async => wake.add(v),
              ),
              operation: (_) => done.future,
            ),
            child: const Text('Start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(wake.last, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(wake.last, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(wake.last, isTrue);
    expect(find.textContaining('may have interrupted'), findsOneWidget);
    done.complete();
    await tester.pumpAndSettle();
    expect(wake.last, isFalse);
  });
}
