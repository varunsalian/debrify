import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/screens/video_player/services/iptv_live_recovery.dart';

/// The recovery state machine is the one piece of the IPTV resilience plan
/// that is pure logic — so it gets real tests. The semantics pinned here are
/// shared with the native player's IptvLiveRecovery.kt (same episode rules);
/// a behavior change on one side should be made on both, and this file is
/// the executable statement of what those rules are.
void main() {
  late List<String> log;
  late bool eligible;
  late IptvLiveRecovery machine;

  IptvLiveRecovery build() => IptvLiveRecovery(
    isEligible: () => eligible,
    performRetune: (source, attempt) => log.add('retune:$source:$attempt'),
    onEpisodeVisible: (attempt) => log.add('pill:$attempt'),
    onRecovered: () => log.add('recovered'),
    onSurrender: (source) => log.add('surrender:$source'),
    // fake_async fakes package:clock's zone clock, not DateTime.now().
    now: () => clock.now(),
  );

  setUp(() {
    log = [];
    eligible = true;
    machine = build();
  });

  test('first drop retunes immediately and invisibly', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      expect(machine.onEnded(), isTrue);
      async.elapse(Duration.zero);
      expect(log, ['retune:ended:1']);
      expect(log.where((l) => l.startsWith('pill')), isEmpty,
          reason: 'a first instant retune must not show the pill');
    });
  });

  test('ladder climbs 0/1/3/5s then 10s, and the pill appears', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      // Each attempt fails: ENDED arrives again after every retune.
      for (var i = 0; i < 6; i++) {
        expect(machine.onEnded(), isTrue);
        // Simulate the retune actually happening (owner calls back in),
        // then real time passing before the next failure — a genuine
        // failure of the new attempt always lands after the 300ms stale
        // debounce.
        async.elapse(const Duration(seconds: 10));
        machine.expectRetune = true;
        machine.onTuneStarted();
        async.elapse(const Duration(milliseconds: 400));
      }
      final retunes = log.where((l) => l.startsWith('retune')).toList();
      expect(retunes, [
        'retune:ended:1',
        'retune:ended:2',
        'retune:ended:3',
        'retune:ended:4',
        'retune:ended:5',
        'retune:ended:6',
      ]);
      expect(log, contains('pill:2'),
          reason: 'second attempt makes the episode visible');
    });
  });

  test('surrender after the 75s budget, then user retry resets it', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      // Keep failing until surrender.
      var guard = 0;
      while (!machine.isSurrendered && guard < 50) {
        machine.onEnded();
        async.elapse(const Duration(seconds: 11));
        if (!machine.isSurrendered) {
          machine.expectRetune = true;
          machine.onTuneStarted();
        }
        guard++;
      }
      expect(machine.isSurrendered, isTrue);
      expect(log, contains('surrender:ended'));
      expect(machine.onEnded(), isTrue,
          reason: 'surrendered machine still claims live events (owns them)');
      final retunesBefore =
          log.where((l) => l.startsWith('retune')).length;
      async.elapse(const Duration(seconds: 30));
      expect(log.where((l) => l.startsWith('retune')).length, retunesBefore,
          reason: 'no retunes while surrendered');

      machine.userRetry('play-press');
      async.elapse(Duration.zero);
      expect(machine.isSurrendered, isFalse);
      expect(log.last, 'retune:play-press:1');
    });
  });

  test('a real zap resets the episode; a recovery retune keeps it', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      machine.onEnded();
      async.elapse(Duration.zero); // attempt 1 fires
      machine.expectRetune = true;
      machine.onTuneStarted(); // recovery's own re-open
      async.elapse(const Duration(milliseconds: 400)); // past stale debounce
      machine.onEnded();
      async.elapse(const Duration(seconds: 2)); // attempt 2 (1s delay)
      expect(log.where((l) => l.startsWith('retune')).last, 'retune:ended:2',
          reason: 'episode survived the recovery retune');

      machine.onTuneStarted(); // REAL zap: no expectRetune
      async.elapse(const Duration(milliseconds: 400)); // past stale debounce
      machine.onEnded();
      async.elapse(Duration.zero);
      expect(log.where((l) => l.startsWith('retune')).last, 'retune:ended:1',
          reason: 'real zap reset the attempt counter');
    });
  });

  test('15s of advancing playback closes the episode', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      machine.onEnded();
      async.elapse(Duration.zero);
      machine.expectRetune = true;
      machine.onTuneStarted();
      machine.onFirstFrame();
      expect(log, contains('recovered'));
      // Position advances for >15s (ticks every second).
      for (var i = 0; i < 20; i++) {
        machine.onProgress(Duration(seconds: i), wantsPlayback: true);
        async.elapse(const Duration(seconds: 1));
      }
      expect(machine.episodeActive, isFalse);
      machine.onEnded();
      async.elapse(Duration.zero);
      expect(log.where((l) => l.startsWith('retune')).last, 'retune:ended:1',
          reason: 'closed episode means the next drop starts at attempt 1');
    });
  });

  test('stall detector fires only when playback is wanted', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      machine.onFirstFrame();
      machine.onProgress(const Duration(seconds: 5), wantsPlayback: true);
      // Frozen position, user paused: no recovery.
      for (var i = 0; i < 20; i++) {
        async.elapse(const Duration(seconds: 1));
        machine.onProgress(const Duration(seconds: 5), wantsPlayback: false);
      }
      expect(log.where((l) => l.startsWith('retune')), isEmpty);
      // Frozen position, playback wanted: recovery after the stall window.
      for (var i = 0; i < 13; i++) {
        async.elapse(const Duration(seconds: 1));
        machine.onProgress(const Duration(seconds: 5), wantsPlayback: true);
      }
      async.elapse(Duration.zero);
      expect(log.where((l) => l.startsWith('retune:stall')), isNotEmpty);
    });
  });

  test('a tune that never frames trips the 20s watchdog', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      async.elapse(const Duration(seconds: 19));
      expect(log.where((l) => l.startsWith('retune')), isEmpty,
          reason: 'still inside the watchdog window');
      async.elapse(const Duration(seconds: 2));
      expect(log.where((l) => l.startsWith('retune:tune-watchdog')),
          isNotEmpty,
          reason: 'codex r2 finding 11: a socket that opens but never '
              'yields a frame or error must not stay black forever');
    });
  });

  test('a framed tune never trips the watchdog', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      machine.onFirstFrame();
      async.elapse(const Duration(seconds: 30));
      expect(log.where((l) => l.startsWith('retune')), isEmpty);
    });
  });

  test('advancing position alone counts as recovery (audio-only channels)', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      machine.onEnded();
      async.elapse(Duration.zero);
      machine.expectRetune = true;
      machine.onTuneStarted();
      // No onFirstFrame ever — audio-only. Position advances instead.
      machine.onProgress(const Duration(seconds: 1), wantsPlayback: true);
      expect(log, contains('recovered'),
          reason: 'codex r2 finding 12: audio-only streams must close '
              'episodes via position advance, not video params');
      for (var i = 2; i < 20; i++) {
        machine.onProgress(Duration(seconds: i), wantsPlayback: true);
        async.elapse(const Duration(seconds: 1));
      }
      expect(machine.episodeActive, isFalse);
    });
  });

  test('events within 300ms of a retune are stale and coalesced', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      machine.onEnded();
      async.elapse(Duration.zero); // attempt 1 fires
      // The dying old stream's queued ENDED lands right after the retune.
      machine.onEnded();
      async.elapse(const Duration(milliseconds: 100));
      expect(log.where((l) => l.startsWith('retune')).length, 1,
          reason: 'codex r2 finding 2: stale death throes must not '
              'double-schedule');
      // A genuine later failure still climbs the ladder.
      async.elapse(const Duration(milliseconds: 400));
      machine.onEnded();
      async.elapse(const Duration(seconds: 2));
      expect(log.where((l) => l.startsWith('retune')).length, 2);
    });
  });

  test('ineligible events are declined, not queued', () {
    fakeAsync((async) {
      eligible = false;
      machine.onTuneStarted();
      expect(machine.onEnded(), isFalse);
      expect(machine.onError(), isFalse);
      async.elapse(const Duration(seconds: 30));
      expect(log, isEmpty);
    });
  });

  test('cancel kills a pending retune', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      machine.onEnded();
      machine.onEnded(); // second request while pending: coalesced
      machine.cancel();
      async.elapse(const Duration(seconds: 30));
      expect(log.where((l) => l.startsWith('retune')), isEmpty);
    });
  });

  test('eligibility is re-checked when the timer fires', () {
    fakeAsync((async) {
      machine.onTuneStarted();
      machine.onEnded();
      async.elapse(Duration.zero);
      machine.expectRetune = true;
      machine.onTuneStarted();
      machine.onEnded(); // schedules attempt 2 at 1s
      eligible = false; // zap to VOD in the gap
      async.elapse(const Duration(seconds: 5));
      expect(log.where((l) => l.startsWith('retune')).length, 1,
          reason: 'attempt 2 must starve once eligibility is gone');
    });
  });
}
