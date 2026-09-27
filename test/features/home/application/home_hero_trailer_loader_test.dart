import 'dart:async';
import 'package:debrify/features/home/application/home_hero_trailer_loader.dart';
import 'package:debrify/features/home/models/home_hero_trailer_resolution.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/youtube_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const _item = StremioMeta(id: 'tt1', type: 'movie', name: 'Title');
const _ready = HomeHeroTrailerResolution.ready(
  YoutubeResolvedStreams(playUrl: 'video'),
);

class _Fixture {
  bool mounted = true;
  int scope = 0;
  bool eligible = true;
  final events = <String>[];
  Future<HomeHeroTrailerResolution> Function(bool Function()) resolve =
      (_) async => _ready;
  late final loader = HomeHeroTrailerLoader(
    resolve: (_, current) {
      events.add('resolve');
      return resolve(current);
    },
    captureScopeGuard: () {
      final captured = scope;
      return () => scope == captured;
    },
  );
  void schedule({
    Duration delay = const Duration(seconds: 2),
    void Function()? reset,
    void Function()? publish,
  }) {
    loader.schedule(
      _item,
      delay: delay,
      isCurrent: () => mounted,
      reset: () {
        events.add('reset');
        reset?.call();
      },
      begin: () {
        events.add('begin');
        return eligible;
      },
      publish: (_) {
        events.add('publish');
        publish?.call();
      },
      fail: () => events.add('fail'),
    );
  }
}

void main() {
  test(
    'reset is immediate, dwell waits two seconds, failsafe waits fifteen more',
    () {
      fakeAsync((time) {
        final f = _Fixture();
        f.schedule();
        expect(f.events, ['reset']);
        time.elapse(const Duration(milliseconds: 1999));
        expect(f.events, ['reset']);
        time.elapse(const Duration(milliseconds: 1));
        expect(f.events, ['reset', 'begin', 'resolve', 'publish']);
        time.elapse(const Duration(milliseconds: 14999));
        expect(f.events.last, 'publish');
        time.elapse(const Duration(milliseconds: 1));
        expect(f.events.last, 'fail');
        f.loader.dispose();
        expect(time.nonPeriodicTimerCount, 0);
      });
    },
  );

  test('Spotlight zero dwell is an event, not synchronous resolution', () {
    fakeAsync((time) {
      final f = _Fixture();
      f.schedule(delay: Duration.zero);
      time.flushMicrotasks();
      expect(f.events, ['reset']);
      time.elapse(Duration.zero);
      expect(f.events, ['reset', 'begin', 'resolve', 'publish']);
      f.loader.dispose();
    });
  });

  test(
    'changed layout or route gate can decline after dwell without a resolve',
    () {
      fakeAsync((time) {
        final f = _Fixture();
        f.schedule();
        f.eligible = false;
        time.elapse(const Duration(seconds: 2));
        expect(f.events, ['reset', 'begin']);
        expect(time.nonPeriodicTimerCount, 0);
        f.loader.dispose();
      });
    },
  );

  for (final retire in ['replace', 'cancel', 'dispose', 'unmount', 'profile']) {
    test('$retire rejects a late playable completion', () {
      fakeAsync((time) {
        final f = _Fixture();
        final result = Completer<HomeHeroTrailerResolution>();
        f.resolve = (_) => result.future;
        f.schedule(delay: Duration.zero);
        time.elapse(Duration.zero);
        switch (retire) {
          case 'replace':
            f.schedule();
          case 'cancel':
            f.loader.cancel();
          case 'dispose':
            f.loader.dispose();
          case 'unmount':
            f.mounted = false;
          case 'profile':
            f.scope++;
        }
        result.complete(_ready);
        time.flushMicrotasks();
        expect(f.events, isNot(contains('publish')));
        expect(f.events, isNot(contains('fail')));
        f.loader.dispose();
        expect(time.nonPeriodicTimerCount, 0);
      });
    });
  }

  test(
    'retired result is silent, unavailable and errors use guarded failure',
    () {
      for (final outcome in ['retired', 'unavailable', 'error']) {
        fakeAsync((time) {
          final f = _Fixture();
          f.resolve = (_) async {
            if (outcome == 'error') throw StateError('resolve');
            return outcome == 'retired'
                ? const HomeHeroTrailerResolution.retired()
                : const HomeHeroTrailerResolution.unavailable();
          };
          f.schedule(delay: Duration.zero);
          time.elapse(Duration.zero);
          expect(f.events, [
            'reset',
            'begin',
            'resolve',
            if (outcome != 'retired') 'fail',
          ]);
          expect(time.nonPeriodicTimerCount, 0);
          f.loader.dispose();
        });
      }
    },
  );

  test(
    'failure retains the original request/mount guard without a scope check',
    () {
      fakeAsync((time) {
        final f = _Fixture();
        final result = Completer<HomeHeroTrailerResolution>();
        f.resolve = (_) => result.future;
        f.schedule(delay: Duration.zero);
        time.elapse(Duration.zero);
        f.scope++;
        result.complete(const HomeHeroTrailerResolution.unavailable());
        time.flushMicrotasks();
        expect(f.events.last, 'fail');
        f.loader.dispose();
      });
    },
  );

  test(
    'replaced request cannot clear loading when its resolver throws late',
    () {
      fakeAsync((time) {
        final f = _Fixture();
        final result = Completer<HomeHeroTrailerResolution>();
        f.resolve = (_) => result.future;
        f.schedule(delay: Duration.zero);
        time.elapse(Duration.zero);
        f.schedule();
        result.completeError(StateError('late'));
        time.flushMicrotasks();
        expect(f.events, isNot(contains('fail')));
        f.loader.dispose();
      });
    },
  );

  test('clear/replacement releases old failsafe timers as well as dwell', () {
    fakeAsync((time) {
      final f = _Fixture();
      f.schedule(delay: Duration.zero);
      time.elapse(Duration.zero);
      expect(time.nonPeriodicTimerCount, 1);
      f.schedule();
      expect(time.nonPeriodicTimerCount, 1);
      f.loader.cancel();
      expect(time.nonPeriodicTimerCount, 0);
      time.elapse(const Duration(seconds: 30));
      expect(f.events, isNot(contains('fail')));
      f.loader.dispose();
    });
  });

  test(
    'synchronous reset/publication retirement leaves no orphaned timers',
    () {
      for (final phase in ['reset', 'publish']) {
        fakeAsync((time) {
          final f = _Fixture();
          f.schedule(
            delay: Duration.zero,
            reset: phase == 'reset' ? f.loader.cancel : null,
            publish: phase == 'publish' ? f.loader.cancel : null,
          );
          time.elapse(Duration.zero);
          expect(time.nonPeriodicTimerCount, 0);
          expect(f.events, isNot(contains('fail')));
          if (phase == 'reset') expect(f.events, ['reset']);
          f.loader.dispose();
        });
      }
    },
  );
}
