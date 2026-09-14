import 'package:debrify/services/player_visibility.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_save_feedback.dart';
import 'package:debrify/widgets/webdav_sync/webdav_save_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dot = find.byKey(const ValueKey('webdav-sync-dot'));
  testWidgets('both player owners hide all feedback without losing receipts', (
    tester,
  ) async {
    final feedback = WebDavSyncSaveFeedback()..setEnabled(true);
    final flutterPlayer = Object();
    final nativePlayer = Object();
    addTearDown(() {
      PlayerVisibility.closed(flutterPlayer);
      PlayerVisibility.closed(nativePlayer);
      feedback.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: WebDavSaveStatus(
          feedback: feedback,
          child: const Scaffold(body: Text('Player')),
        ),
      ),
    );
    feedback.saved(1);
    await tester.pump();
    expect(dot, findsOneWidget);
    PlayerVisibility.opened(flutterPlayer);
    await tester.pump();
    expect(dot, findsNothing);
    feedback.saved(2);
    feedback.waiting();
    await tester.pump(const Duration(seconds: 4));
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    expect(feedback.hasPending, isTrue);
    PlayerVisibility.opened(nativePlayer);
    PlayerVisibility.closed(flutterPlayer);
    await tester.pump();
    expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
    feedback.finished(2, published: true);
    await tester.pump();
    expect(find.text('Synced to WebDAV'), findsNothing);
    feedback.saved(3);
    feedback.waiting();
    await tester.pump();
    PlayerVisibility.closed(nativePlayer);
    await tester.pump();
    expect(dot, findsNothing);
    feedback.started();
    await tester.pump();
    expect(dot, findsOneWidget);
    expect(feedback.hasPending, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'phone dot pulses without text or blocking navigation and hides when idle',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final feedback = WebDavSyncSaveFeedback()..setEnabled(true);
      addTearDown(feedback.dispose);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              WebDavSaveStatus(feedback: feedback, child: child!),
          home: Scaffold(
            bottomNavigationBar: SizedBox(
              height: 80,
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('Discover'),
              ),
            ),
          ),
        ),
      );
      expect(dot, findsNothing);
      feedback.saved(1);
      await tester.pump();
      expect(dot, findsOneWidget);
      expect(tester.getSize(dot), const Size(6, 6));
      expect(tester.getRect(dot).right, 370);
      expect(tester.getRect(dot).bottom, 824);
      final fade = find
          .ancestor(of: dot, matching: find.byType(FadeTransition))
          .first;
      final opacity = tester.widget<FadeTransition>(fade).opacity;
      expect(opacity.value, closeTo(0.3, 0.001));
      await tester.pump(const Duration(milliseconds: 900));
      expect(opacity.value, closeTo(1, 0.001));
      await tester.pump(const Duration(milliseconds: 900));
      expect(opacity.value, closeTo(0.3, 0.001));
      expect(find.textContaining('Saved locally'), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Discover'));
      expect(taps, 1);
      await tester.tapAt(tester.getCenter(dot));
      expect(taps, 2);
      feedback.waiting();
      await tester.pump();
      expect(dot, findsNothing);
      expect(find.text('Retry'), findsNothing);
      feedback.started();
      await tester.pump();
      expect(dot, findsOneWidget);
      feedback.finished(1, published: true);
      await tester.pump();
      expect(dot, findsNothing);
      expect(find.text('Synced to WebDAV'), findsNothing);
      feedback.saved(2);
      feedback.setEnabled(false);
      await tester.pump();
      expect(dot, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reduced motion is steady and feedback replacement detaches listeners',
    (tester) async {
      final first = WebDavSyncSaveFeedback()
        ..setEnabled(true)
        ..saved(1);
      final second = WebDavSyncSaveFeedback()..setEnabled(true);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Future<void> show(WebDavSyncSaveFeedback feedback, bool reduceMotion) =>
          tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduceMotion),
                child: WebDavSaveStatus(
                  feedback: feedback,
                  child: const Scaffold(),
                ),
              ),
            ),
          );
      await show(first, true);
      final fade = find
          .ancestor(of: dot, matching: find.byType(FadeTransition))
          .first;
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await show(first, false);
      await tester.pump(const Duration(milliseconds: 450));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await show(second, false);
      await tester.pumpAndSettle();
      expect(dot, findsNothing);
      first.saved(2);
      expect(tester.binding.hasScheduledFrame, isFalse);
      second.saved(1);
      await tester.pump();
      expect(dot, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      second.saved(2);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'pending publication is restored after restart and cleared only on success',
    () async {
      SharedPreferences.setMockInitialValues({
        WebDavSyncSaveFeedback.pendingKey: true,
      });
      final feedback = WebDavSyncSaveFeedback(persistent: true);
      await feedback.initialize();
      feedback.setEnabled(true);
      expect(feedback.hasPending, isTrue);
      expect(feedback.phase, WebDavSavePhase.pending);
      feedback.finished(feedback.revision, published: false);
      await Future<void>.delayed(Duration.zero);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          WebDavSyncSaveFeedback.pendingKey,
        ),
        isTrue,
      );
      feedback.finished(feedback.revision, published: true);
      await Future<void>.delayed(Duration.zero);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          WebDavSyncSaveFeedback.pendingKey,
        ),
        isFalse,
      );
      feedback.dispose();
    },
  );

  test('inactive retry never leaves a permanent spinner', () async {
    final feedback = WebDavSyncSaveFeedback()
      ..setEnabled(true)
      ..saved(1);
    feedback.finished(1, published: false);
    feedback.retryAction = () async {};
    await feedback.retry();
    expect(feedback.phase, WebDavSavePhase.pending);
    expect(feedback.hasPending, isTrue);
    feedback.dispose();
  });

  test('a cycle acknowledges only the edits in its starting snapshot', () {
    final feedback = WebDavSyncSaveFeedback()..setEnabled(true);
    feedback.saved(1);
    feedback.started();
    feedback.saved(2);
    feedback.finished(1, published: true);
    expect(feedback.hasPending, isTrue);
    expect(feedback.confirmedRevision, 1);
    feedback.finished(2, published: false);
    expect(feedback.phase, WebDavSavePhase.pending);
    feedback.finished(2, published: true);
    expect(feedback.phase, WebDavSavePhase.synced);
    expect(feedback.hasPending, isFalse);
    feedback.dispose();
  });

  test('disarming hides feedback without acknowledging pending saves', () {
    final feedback = WebDavSyncSaveFeedback()
      ..setEnabled(true)
      ..saved(1);
    feedback.setEnabled(false);
    expect(feedback.phase, WebDavSavePhase.inactive);
    expect(feedback.hasPending, isTrue);
    feedback.setEnabled(true);
    expect(feedback.phase, WebDavSavePhase.pending);
    feedback.dispose();
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'dot expires after ten seconds, reduced motion: $reducedMotion',
      (tester) async {
        final feedback = WebDavSyncSaveFeedback()..setEnabled(true);
        final player = Object();
        addTearDown(() {
          PlayerVisibility.closed(player);
          feedback.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: WebDavSaveStatus(
                feedback: feedback,
                child: const Scaffold(),
              ),
            ),
          ),
        );
        feedback.saved(1);
        await tester.pump();
        expect(dot, findsOneWidget);
        await tester.pump(const Duration(seconds: 9));
        feedback.saved(2);
        feedback.started();
        feedback.timedOut();
        await tester.pump();
        expect(dot, findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        expect(dot, findsNothing);
        expect(feedback.phase, WebDavSavePhase.syncing);
        expect(feedback.hasPending, isTrue);
        feedback.saved(3);
        PlayerVisibility.opened(player);
        await tester.pump();
        PlayerVisibility.closed(player);
        await tester.pump(const Duration(seconds: 20));
        expect(dot, findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.textContaining('saved locally'), findsNothing);
        feedback.waiting();
        feedback.started();
        await tester.pump();
        expect(dot, findsOneWidget);
        await tester.pump(const Duration(seconds: 10));
        expect(dot, findsNothing);
        feedback.finished(3, published: true);
        await tester.pump();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
