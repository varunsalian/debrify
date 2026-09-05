import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_save_feedback.dart';
import 'package:debrify/widgets/webdav_sync/webdav_save_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  for (final outcome in [
    'timeout',
    'continue',
    'success',
    'failure',
    'disabled',
  ]) {
    testWidgets(
      'profile save dialog handles $outcome without canceling pending work',
      (tester) async {
        final feedback = WebDavSyncSaveFeedback()
          ..setEnabled(outcome != 'disabled');
        var returned = false;
        await tester.pumpWidget(
          MaterialApp(
            builder: (_, child) =>
                WebDavSaveStatus(feedback: feedback, child: child!),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final before = feedback.revision;
                    if (feedback.enabled) feedback.saved(1);
                    await showWebDavSaveProgress(
                      context,
                      before,
                      feedback: feedback,
                    );
                    returned = true;
                  },
                  child: const Text('Save'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (outcome == 'disabled') {
          expect(find.byType(AlertDialog), findsNothing);
        } else {
          expect(find.byType(AlertDialog), findsOneWidget);
          switch (outcome) {
            case 'timeout':
              await tester.pump(const Duration(seconds: 15));
            case 'continue':
              await tester.tap(find.text('Continue in background'));
            case 'success':
              feedback.finished(1, published: true);
            case 'failure':
              feedback.finished(1, published: false);
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(AlertDialog), findsNothing);
          expect(feedback.hasPending, outcome != 'success');
          if (outcome == 'timeout') {
            expect(
              find.text('Sync is taking longer. Your change is saved locally.'),
              findsOneWidget,
            );
          }
          if (outcome == 'failure') expect(find.text('Retry'), findsOneWidget);
        }
        expect(returned, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        feedback.dispose();
      },
    );
  }
}
