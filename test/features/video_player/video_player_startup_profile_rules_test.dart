import 'dart:async';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/widgets/playback_startup_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/local_completion_driver.dart';
import 'support/startup_driver.dart';
import 'support/vp_fixture_actions.dart';

/// Select just the storage await in the real Quick Play call chain. Other
/// initialization loaders still complete; this does not substitute their data.
class _RulesCapture {
  bool armed = true;
  final pending = <void Function()>[];
  T run<T>(T Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      registerUnaryCallback:
          <R, V>(self, parent, zone, R Function(V) callback) {
            final stack = StackTrace.current.toString();
            final selected =
                stack.contains('ProfilePreferences.instance') &&
                stack.contains('getQuickPlayRules');
            return parent.registerUnaryCallback(zone, (V value) {
              if (armed &&
                  selected &&
                  value is SharedPreferences &&
                  (R.toString() == 'void' || R.toString() == 'dynamic')) {
                armed = false;
                pending.add(
                  VpFixtureActions.heldCallback(
                    'P16 rules capture',
                    () => zone.runUnary(callback, value),
                  ),
                );
                return null as R;
              }
              return callback(value);
            });
          },
    ),
  );
  void release() {
    armed = false;
    final copied = List<void Function()>.of(pending);
    pending.clear();
    for (final p in copied) {
      p();
    }
  }
}

void main() {
  for (final boundary in ['before profile capture', 'after rules delivery']) {
    for (final crossing in ['A to B', 'A to B to A']) {
      testWidgets(
        'P16 Quick Play $boundary across $crossing pins the actual profile capture moment',
        (t) async {
          final d = StartupDriver(t);
          await d.initialize();
          final origin = ProfileRuntime.capture();
          final incoming = await completionIncomingProfile(t, d.f);
          await d.f.finish(
            t,
            ProfileRuntime.withCapturedScope(
              incoming,
              () => QuickPlayStorage.setQuickPlayRules(
                QuickPlayRules.debrifyDefault(
                  isMovie: true,
                ).copyWith(maxAttempts: 1, tryNextOnFailure: true),
                isMovie: true,
              ),
            ),
          );
          await completionActivate(t, d.f, origin);
          await d.rules(attempts: 3);
          final capture = _RulesCapture()
            ..armed = boundary == 'before profile capture';
          final delivered = CompletionDelivery(
            'openInitialVodWithFailover',
            (v) => v is QuickPlayRules,
          )..armed = boundary == 'after rules delivery';
          final sources = List.generate(
            3,
            (i) => startupSource('profile-rules-$i'),
          );
          for (final s in sources) {
            d.openFailures[s.directUrl!] = StateError(
              'fixture source unavailable',
            );
          }
          try {
            await capture.run(
              () => delivered.run(
                () => d.begin(d.screen(sources: sources, failover: true)),
              ),
            );
            await d.f.until(
              t,
              () => capture.pending.isNotEmpty || delivered.pending.isNotEmpty,
            );
            expect(d.opens, isEmpty);
            await completionActivate(t, d.f, incoming);
            if (crossing == 'A to B to A') {
              await completionActivate(t, d.f, origin);
            }
            expect(
              capture.pending.isNotEmpty || delivered.pending.isNotEmpty,
              isTrue,
            );
            capture.release();
            delivered.release();
            await d.f.until(t, () => d.event('exhausted').isNotEmpty);
            final count =
                boundary == 'before profile capture' && crossing == 'A to B'
                ? 1
                : 3;
            expect(d.opens, sources.take(count).map((s) => s.directUrl));
            expect(
              d.event('begin').singleOrNull,
              contains('maxAttempts=$count'),
            );
            expect(d.commits, isEmpty);
          } finally {
            capture.release();
            delivered.release();
            await d.close();
          }
        },
      );
    }
  }
  for (final disposed in [false, true]) {
    testWidgets(
      'P16 delayed rules preserve debrid overlay refresh and mounted guard disposed=$disposed',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        await d.rules();
        final delivery = CompletionDelivery(
          'openInitialVodWithFailover',
          (v) => v is QuickPlayRules,
        );
        final a = startupSource('delayed-debrid', type: StreamType.torrent);
        final ack = d.openGates[a.directUrl!] = Completer<void>();
        try {
          await delivery.run(
            () => d.begin(d.screen(sources: [a], failover: true)),
          );
          await d.f.until(t, () => delivery.pending.isNotEmpty);
          await d.tick(const Duration(seconds: 4));
          expect(d.opens, isEmpty);
          expect(find.byType(PlaybackStartupView), findsOneWidget);
          if (disposed) {
            await t.pumpWidget(const SizedBox.shrink());
            await d.f.until(t, () => d.player.disposed.isCompleted);
          }
          delivery.release();
          if (disposed) {
            await d.tick(const Duration(seconds: 13));
            await d.f.until(t, () => d.activeProbes.isEmpty);
            expect(d.opens, isEmpty);
            expect(d.commits, isEmpty);
            expect(d.errors, isEmpty);
            expect(
              d.periodic.where((r) => r.$1 == const Duration(seconds: 6)),
              isEmpty,
            );
          } else {
            await d.openEntered();
            expect(ack.isCompleted, isFalse);
            expect(d.event('candidate_result'), isEmpty);
            expect(find.byType(PlaybackStartupView), findsNothing);
            d.frame();
            await d.result();
            expect(d.commits, isEmpty);
            ack.complete();
            await d.committed();
          }
        } finally {
          delivery.release();
          ack.completeIfPending();
          await d.close();
        }
      },
    );
  }
}
