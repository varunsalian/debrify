import 'dart:async';

import 'package:debrify/services/startup_stream_policy.dart';
// Flutter's test SDK supplies fake_async transitively for deterministic timers.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final identity in ['addon', 'name', 'url']) {
    test('AIOStreams $identity identity rejects a decoded error clip', () {
      fakeAsync((clock) {
        final probe = _ChannelProbe(
          addonId: identity == 'addon' ? 'org.aiostreams.addon' : null,
          sourceName: identity == 'name' ? 'AIOStreams | RD' : null,
          url: identity == 'url'
              ? 'https://aiostreams.example/error.mp4'
              : null,
        );
        expect(probe.watch.blocksProgress, isTrue);
        probe.durations.add(const Duration(seconds: 30));
        probe.widths.add(1920);
        probe.positions.add(const Duration(seconds: 29));
        probe.completed.add(true);
        clock.flushMicrotasks();
        expect(probe.failures, 1);
        expect(probe.accepted, 0);
        expect(probe.completions, 0);
        expect(probe.watch.blocksProgress, isTrue);
        probe.watch.dispose();
        expect(
          probe.watch.blocksProgress,
          isTrue,
          reason: 'Rejected clip must not write a final checkpoint on exit',
        );
        probe.dispose();
      });
    });
  }

  test(
    'AIOStreams waits for late duration even after a positive seek position',
    () {
      fakeAsync((clock) {
        final probe = _ChannelProbe(addonId: 'aiostreams');
        probe.widths.add(1920);
        probe.positions.add(const Duration(seconds: 20));
        clock.flushMicrotasks();
        expect(probe.watch.isPending, isTrue);
        expect(probe.watch.blocksProgress, isTrue);
        clock.elapse(const Duration(milliseconds: 500));
        probe.durations.add(const Duration(seconds: 30));
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 2));
        expect(probe.failures, 1);
        expect(probe.accepted, 0);
        expect(clock.pendingTimers, isEmpty);
        probe.dispose();
      });
    },
  );

  test(
    'AIOStreams EOF during metadata grace cannot complete the programme',
    () {
      fakeAsync((clock) {
        final probe = _ChannelProbe(addonId: 'aiostreams');
        probe.widths.add(1920);
        probe.positions.add(const Duration(milliseconds: 100));
        clock.flushMicrotasks();
        probe.completed.add(true);
        clock.flushMicrotasks();
        expect(probe.failures, 1);
        expect(probe.completions, 0);
        expect(probe.watch.blocksProgress, isTrue);
        probe.dispose();
      });
    },
  );

  for (final duration in [
    const Duration(minutes: 3),
    const Duration(hours: 1),
  ]) {
    test(
      'valid AIOStreams duration $duration enables progress and completion',
      () {
        fakeAsync((clock) {
          final probe = _ChannelProbe(addonId: 'aiostreams');
          clock.elapse(const Duration(minutes: 2));
          expect(probe.failures, 0);
          expect(clock.pendingTimers, isEmpty);
          probe.durations.add(duration);
          probe.widths.add(1920);
          probe.positions.add(const Duration(milliseconds: 100));
          clock.flushMicrotasks();
          expect(probe.accepted, 1);
          expect(probe.watch.blocksProgress, isFalse);
          probe.completed.add(true);
          clock.flushMicrotasks();
          expect(probe.completions, 1);
          expect(probe.failures, 0);
          probe.dispose();
        });
      },
    );
  }

  test('unknown AIOStreams duration retains the existing metadata grace', () {
    fakeAsync((clock) {
      final probe = _ChannelProbe(addonId: 'aiostreams');
      probe.widths.add(1920);
      probe.positions.add(const Duration(milliseconds: 100));
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(probe.accepted, 1);
      expect(probe.watch.blocksProgress, isFalse);
      expect(probe.failures, 0);
      probe.dispose();
    });
  });

  test('metadata grace cannot release or fail an abandoned channel', () {
    fakeAsync((clock) {
      final probe = _ChannelProbe(addonId: 'aiostreams');
      probe.widths.add(1920);
      probe.positions.add(const Duration(milliseconds: 100));
      clock.flushMicrotasks();
      probe.current = false;
      probe.watch.dispose();
      clock.elapse(const Duration(seconds: 2));
      expect(probe.accepted, 0);
      expect(probe.failures, 0);
      expect(clock.pendingTimers, isEmpty);
      probe.dispose();
    });
  });

  test('short non-AIOStreams content retains normal completion', () {
    fakeAsync((clock) {
      final probe = _ChannelProbe(sourceName: 'Other addon');
      probe.durations.add(const Duration(seconds: 30));
      probe.widths.add(1920);
      probe.positions.add(const Duration(milliseconds: 100));
      clock.flushMicrotasks();
      probe.completed.add(true);
      clock.flushMicrotasks();
      expect(probe.failures, 0);
      expect(probe.accepted, 1);
      expect(probe.completions, 1);
      probe.dispose();
    });
  });

  test(
    'connection error after a successful open reports startup failure once',
    () {
      fakeAsync((clock) {
        final probe = _ChannelProbe();
        bool? opened;
        StartupStreamPolicy.openInitialMedia(
          hasResolvedUrl: true,
          hasExternalAudio: false,
          isLiveIptv: false,
          isStremioTv: true,
          openDirect: () async {},
          openValidated: () async => fail('No VOD watchdog for a channel'),
        ).then((value) => opened = value);
        clock.flushMicrotasks();
        expect(opened, isTrue);
        probe.errors.add('Failed to open input: Connection refused');
        clock.flushMicrotasks();
        expect(probe.failures, 1);
        expect(probe.watch.hasFailed, isTrue);
        probe.errors.add(
          'Error opening/initializing the selected video_out device.',
        );
        clock.flushMicrotasks();
        expect(probe.failures, 1);
        probe.dispose();
      });
    },
  );

  test(
    'slow channel remains pending without a watchdog until video advances',
    () {
      fakeAsync((clock) {
        final probe = _ChannelProbe();
        clock.elapse(const Duration(minutes: 2));
        expect(probe.watch.isPending, isTrue);
        expect(probe.failures, 0);
        expect(clock.pendingTimers, isEmpty);
        probe.widths.add(1920);
        probe.positions.add(const Duration(milliseconds: 100));
        clock.flushMicrotasks();
        expect(probe.watch.isPending, isFalse);
        probe.errors.add('Nonfatal log message after startup');
        clock.flushMicrotasks();
        expect(probe.failures, 0);
        probe.dispose();
      });
    },
  );

  test('durationless stalled video still reports a terminal startup error', () {
    fakeAsync((clock) {
      final probe = _ChannelProbe();
      probe.widths.add(1920);
      probe.positions.add(Duration.zero);
      clock.flushMicrotasks();
      expect(probe.watch.isPending, isTrue);
      probe.errors.add('HTTP 403 Forbidden');
      clock.flushMicrotasks();
      expect(probe.failures, 1);
      probe.dispose();
    });
  });

  test('queued errors cannot fail a replaced or disposed channel', () {
    fakeAsync((clock) {
      for (final cancel in [false, true]) {
        final probe = _ChannelProbe();
        probe.errors.add('Connection refused');
        if (cancel) {
          probe.watch.dispose();
        } else {
          probe.current = false;
        }
        clock.flushMicrotasks();
        expect(probe.failures, 0);
        probe.dispose();
      }
    });
  });

  test(
    'renderer handoff watches the new backend and preserves the pending slot',
    () {
      fakeAsync((clock) {
        final oldBackend = _ChannelProbe();
        final seek = DeferredStartupSeek()..arm(0.4, epoch: 1);
        // The existing renderer-error listener starts recovery first, invalidates
        // the old instance, then reopens the same media on the new backend.
        final restartWatch = oldBackend.watch.isPending;
        oldBackend.current = false;
        oldBackend.errors.add('Video output initialization failed');
        clock.flushMicrotasks();
        expect(oldBackend.failures, 0);
        expect(restartWatch, isTrue);
        seek.carryTo(fromEpoch: 1, toEpoch: 2);
        final newBackend = _ChannelProbe();
        clock.elapse(const Duration(seconds: 90));
        expect(
          seek.take(const Duration(hours: 1), epoch: 2),
          const Duration(minutes: 24),
        );
        expect(seek.take(const Duration(hours: 1), epoch: 2), isNull);
        newBackend.errors.add('Connection refused on reopened media');
        clock.flushMicrotasks();
        expect(newBackend.failures, 1);
        oldBackend.dispose();
        newBackend.dispose();
      });
    },
  );

  test('renderer restart cannot revive a cancelled or consumed slot seek', () {
    for (final consumed in [false, true]) {
      final seek = DeferredStartupSeek()..arm(0.4, epoch: 1);
      if (consumed) {
        seek.take(const Duration(hours: 1), epoch: 1);
      } else {
        seek.cancel();
      }
      seek.carryTo(fromEpoch: 1, toEpoch: 2);
      expect(seek.take(const Duration(hours: 1), epoch: 2), isNull);
    }
  });

  test(
    'recoverable renderer error preserves startup regardless of listener order',
    () {
      fakeAsync((clock) {
        final probe = _ChannelProbe(deferRendererError: true);
        probe.errors.add('Video output initialization failed');
        clock.flushMicrotasks();
        expect(probe.watch.isPending, isTrue);
        expect(probe.failures, 0);
        // A failed automatic renderer has no further renderer recovery to defer.
        probe.deferRendererError = false;
        probe.errors.add('Video output initialization failed');
        clock.flushMicrotasks();
        expect(probe.failures, 1);
        probe.dispose();
      });
    },
  );

  test('renderer restart refuses a slot belonging to a different epoch', () {
    final seek = DeferredStartupSeek()..arm(0.4, epoch: 1);
    seek.carryTo(fromEpoch: 2, toEpoch: 3);
    expect(seek.take(const Duration(hours: 1), epoch: 3), isNull);
  });

  test('late channel duration applies the initial slot position only once', () {
    fakeAsync((clock) {
      final seek = DeferredStartupSeek()..arm(0.4, epoch: 1);
      expect(seek.take(Duration.zero, epoch: 1), isNull);
      clock.elapse(const Duration(seconds: 90));
      expect(seek.take(Duration.zero, epoch: 1), isNull);
      expect(
        seek.take(const Duration(hours: 1), epoch: 1),
        const Duration(minutes: 24),
      );
      expect(seek.take(const Duration(hours: 1), epoch: 1), isNull);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('late duration cannot seek a replacement channel or source', () {
    final seek = DeferredStartupSeek()..arm(0.4, epoch: 1);
    expect(seek.take(const Duration(hours: 2), epoch: 2), isNull);
    expect(seek.take(const Duration(hours: 1), epoch: 1), isNull);
  });

  test('user seek or media teardown cancels a pending slot position', () {
    final seek = DeferredStartupSeek()..arm(0.4, epoch: 1);
    seek.cancel();
    expect(seek.take(const Duration(hours: 1), epoch: 1), isNull);
  });

  test('a later armed slot replaces the outgoing initial position', () {
    final seek = DeferredStartupSeek()..arm(0.4, epoch: 1);
    seek.cancel();
    seek.arm(0.2, epoch: 2);
    expect(
      seek.take(const Duration(hours: 1), epoch: 2),
      const Duration(minutes: 12),
    );
  });

  for (final fraction in <double?>[null, 0, -0.5]) {
    test('initial fraction $fraction requires no deferred seek', () {
      final seek = DeferredStartupSeek()..arm(fraction, epoch: 1);
      expect(seek.take(const Duration(hours: 1), epoch: 1), isNull);
    });
  }

  test('deferred position preserves the existing end-of-file clamp', () {
    final seek = DeferredStartupSeek()..arm(1, epoch: 1);
    expect(
      seek.take(const Duration(seconds: 100), epoch: 1),
      const Duration(seconds: 99),
    );
  });

  test(
    'slow Stremio TV startup stays on its original open past VOD deadlines',
    () {
      fakeAsync((clock) {
        final pendingOpen = Completer<void>();
        var directOpens = 0;
        var validatedOpens = 0;
        bool? result;
        StartupStreamPolicy.openInitialMedia(
          hasResolvedUrl: true,
          hasExternalAudio: false,
          isLiveIptv: false,
          isStremioTv: true,
          openDirect: () {
            directOpens++;
            return pendingOpen.future;
          },
          openValidated: () async {
            validatedOpens++;
            return false;
          },
        ).then((value) => result = value);

        clock.elapse(const Duration(seconds: 90));
        expect(result, isNull);
        expect(directOpens, 1);
        expect(validatedOpens, 0);
        pendingOpen.complete();
        clock.flushMicrotasks();
        expect(result, isTrue);
        expect(directOpens, 1, reason: 'Do not reopen a single-use stream URL');
        expect(validatedOpens, 0);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'Stremio TV open errors still propagate to existing player handling',
    () async {
      final error = StateError('Connection refused');
      await expectLater(
        StartupStreamPolicy.openInitialMedia(
          hasResolvedUrl: true,
          hasExternalAudio: false,
          isLiveIptv: false,
          isStremioTv: true,
          openDirect: () async => throw error,
          openValidated: () async =>
              fail('Channel failure must not enter VOD fallback'),
        ),
        throwsA(same(error)),
      );
    },
  );

  for (final accepted in [true, false]) {
    test('ordinary VOD preserves validator result $accepted', () async {
      var validatedOpens = 0;
      final result = await StartupStreamPolicy.openInitialMedia(
        hasResolvedUrl: true,
        hasExternalAudio: false,
        isLiveIptv: false,
        isStremioTv: false,
        openDirect: () async => fail('Ordinary VOD must still be validated'),
        openValidated: () async {
          validatedOpens++;
          return accepted;
        },
      );
      expect(result, accepted);
      expect(validatedOpens, 1);
    });
  }

  for (final mode in ['live IPTV', 'external audio']) {
    test('$mode retains its existing direct-open path', () async {
      var directOpens = 0;
      final result = await StartupStreamPolicy.openInitialMedia(
        hasResolvedUrl: true,
        hasExternalAudio: mode == 'external audio',
        isLiveIptv: mode == 'live IPTV',
        isStremioTv: false,
        openDirect: () async {
          directOpens++;
        },
        openValidated: () async => fail('$mode must not enter VOD validation'),
      );
      expect(result, isTrue);
      expect(directOpens, 1);
    });
  }

  for (final mode in ['VOD', 'Stremio TV', 'live IPTV', 'external audio']) {
    test(
      'missing $mode launch URL preserves failed-resolution handling',
      () async {
        var validatedOpens = 0;
        final result = await StartupStreamPolicy.openInitialMedia(
          hasResolvedUrl: false,
          hasExternalAudio: mode == 'external audio',
          isLiveIptv: mode == 'live IPTV',
          isStremioTv: mode == 'Stremio TV',
          openDirect: () async =>
              fail('An empty URL must not be opened directly'),
          openValidated: () async {
            validatedOpens++;
            return false;
          },
        );
        expect(result, isFalse);
        expect(validatedOpens, 1);
      },
    );
  }
}

class _ChannelProbe {
  _ChannelProbe({
    this.deferRendererError = false,
    String? addonId,
    String? sourceName,
    String? url,
  }) {
    // The screen's completion listener is installed before its startup watch.
    _completionSub = completed.stream.listen((done) {
      if (done && !watch.blocksProgress) completions++;
    });
    watch = ChannelStartupWatch(
      errors: errors.stream,
      widths: widths.stream,
      positions: positions.stream,
      durations: durations.stream,
      completed: completed.stream,
      addonId: addonId,
      sourceName: sourceName,
      url: url,
      isCurrent: () => current,
      onFailure: () => failures++,
      onReady: () => accepted++,
      shouldDeferError: (error) =>
          deferRendererError && error == 'Video output initialization failed',
    );
  }

  final errors = StreamController<String>.broadcast();
  final widths = StreamController<int?>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  final completed = StreamController<bool>.broadcast();
  late final ChannelStartupWatch watch;
  late final StreamSubscription<bool> _completionSub;
  var current = true;
  var failures = 0;
  var accepted = 0;
  var completions = 0;
  bool deferRendererError;

  void dispose() {
    watch.dispose();
    unawaited(_completionSub.cancel());
    unawaited(errors.close());
    unawaited(widths.close());
    unawaited(positions.close());
    unawaited(durations.close());
    unawaited(completed.close());
  }
}
