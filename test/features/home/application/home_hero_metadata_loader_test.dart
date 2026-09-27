import 'dart:async';
import 'package:debrify/features/home/application/home_hero_metadata_loader.dart';
import 'package:debrify/features/home/data/home_hero_metadata_repository.dart';
import 'package:debrify/models/hero_metadata_presentation.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const title = StremioMeta(id: 'tt1', type: 'movie', name: 'Catalog');
const details = StremioMeta(id: 'tt1', type: 'movie', name: 'Details');
const translated = StremioMeta(id: 'tt1', type: 'movie', name: 'Translated');

MetadataPreferences _currentPreferences() => MetadataPreferences(
  features: const {},
  providers: {
    for (final category in MetadataCategory.values)
      category: MetadataPreferences.current,
  },
);

class _Fixture {
  bool mounted = true;
  int scope = 0;
  final events = <String>[];
  final accepted = <HeroMetadataPresentation>[];
  Future<MetadataPreferences> Function() preferences = () async =>
      _currentPreferences();
  Future<StremioMeta?> Function(String, String) fetch = (_, _) async => details;
  Future<MetadataPresentation> Function(
    StremioMeta,
    MetadataPreferences,
    bool Function(),
  )
  present = (item, prefs, current) async =>
      const MetadataPresentation(translated);
  late final repository = HomeHeroMetadataRepository(
    readPreferences: (current) async {
      events.add('preferences');
      if (!current()) return null;
      try {
        final result = await preferences();
        return current() ? result : null;
      } catch (_) {
        return null;
      }
    },
    fetchDetails: (id, type) {
      events.add('fetch:$id:$type');
      return fetch(id, type);
    },
    present: (item, prefs, current) {
      events.add('present:${item.name}:${current()}');
      return present(item, prefs, current);
    },
  );
  late final loader = HomeHeroMetadataLoader(
    repository: repository,
    captureScopeGuard: () {
      final captured = scope;
      return () => scope == captured;
    },
  );
  void load([StremioMeta item = title]) => unawaited(
    loader.load(item, isCurrent: () => mounted, onResolved: accepted.add),
  );
}

void main() {
  test(
    'debounce starts after preferences and load does not await the timer',
    () {
      fakeAsync((time) {
        final f = _Fixture();
        final prefs = Completer<MetadataPreferences>();
        f.preferences = () => prefs.future;
        var returned = false;
        f.loader
            .load(title, isCurrent: () => true, onResolved: f.accepted.add)
            .then((_) => returned = true);
        time.elapse(const Duration(seconds: 1));
        expect(f.events, ['preferences']);
        expect(returned, isFalse);
        prefs.complete(_currentPreferences());
        time.flushMicrotasks();
        expect(returned, isTrue);
        time.elapse(const Duration(milliseconds: 139));
        expect(f.events, ['preferences']);
        time.elapse(const Duration(milliseconds: 1));
        expect(f.events, [
          'preferences',
          'fetch:tt1:movie',
          'present:Details:true',
        ]);
        expect(f.accepted.single.name, 'Details');
        f.loader.dispose();
      });
    },
  );

  test('late preferences cannot replace a newer timer', () {
    fakeAsync((time) {
      final f = _Fixture();
      final old = Completer<MetadataPreferences>();
      f.preferences = () => old.future;
      f.load();
      f.preferences = () async => _currentPreferences();
      f.load(const StremioMeta(id: 'tt2', type: 'series', name: 'Next'));
      time.flushMicrotasks();
      old.complete(_currentPreferences());
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 140));
      expect(f.events.where((e) => e.startsWith('fetch:')), [
        'fetch:tt2:series',
      ]);
      expect(f.accepted, hasLength(1));
      f.loader.dispose();
    });
  });

  test(
    'late detail result keeps service relevance guard and cannot publish',
    () {
      fakeAsync((time) {
        final f = _Fixture();
        final old = Completer<StremioMeta?>();
        f.fetch = (_, _) => old.future;
        f.load();
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 140));
        f.fetch = (_, _) async => translated;
        f.load(const StremioMeta(id: 'tt2', type: 'movie', name: 'Next'));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 140));
        old.complete(details);
        time.flushMicrotasks();
        expect(f.accepted.single.name, 'Translated');
        expect(f.events, contains('present:Details:false'));
        f.loader.dispose();
      });
    },
  );

  test('complete catalog and unmapped current-provider items skip details', () {
    fakeAsync((time) {
      final f = _Fixture();
      f.load();
      time.flushMicrotasks();
      f.load(
        const StremioMeta(
          id: 'tt2',
          type: 'movie',
          name: 'Complete',
          background: 'art',
          description: 'plot',
          runtime: '90m',
          logo: 'logo',
          imdbRating: 8,
        ),
      );
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 200));
      f.load(const StremioMeta(id: 'custom', type: 'movie', name: 'Custom'));
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 200));
      expect(f.events, ['preferences', 'preferences', 'preferences']);
      expect(f.accepted, isEmpty);
      f.loader.dispose();
    });
  });

  test(
    'selected provider can enrich unmapped catalog without a details fetch',
    () {
      fakeAsync((time) {
        final f = _Fixture();
        final prefs = MetadataPreferences(
          providers: {MetadataCategory.information: 'tmdb'},
        );
        f.preferences = () async => prefs;
        f.load(const StremioMeta(id: 'custom', type: 'movie', name: 'Custom'));
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 140));
        expect(f.events, ['preferences', 'present:Custom:true']);
        expect(f.accepted.single.name, 'Translated');
        expect(f.accepted.single.preferences, same(prefs));
        f.loader.dispose();
      });
    },
  );

  for (final retire in ['cancel', 'dispose', 'profile', 'unmount']) {
    test(
      '$retire rejects waiting preferences, timers and late presentations',
      () {
        for (final stage in ['preferences', 'timer', 'presentation']) {
          fakeAsync((time) {
            final f = _Fixture();
            final prefs = Completer<MetadataPreferences>();
            final presentation = Completer<MetadataPresentation>();
            if (stage == 'preferences') f.preferences = () => prefs.future;
            if (stage == 'presentation') {
              f.present = (_, _, _) => presentation.future;
            }
            f.load();
            time.flushMicrotasks();
            if (stage == 'presentation') {
              time.elapse(const Duration(milliseconds: 140));
            }
            switch (retire) {
              case 'cancel':
                f.loader.cancel();
              case 'dispose':
                f.loader.dispose();
              case 'profile':
                f.scope++;
              case 'unmount':
                f.mounted = false;
            }
            if (stage == 'preferences') prefs.complete(_currentPreferences());
            if (stage == 'presentation') {
              presentation.complete(const MetadataPresentation(translated));
            }
            time.flushMicrotasks();
            time.elapse(const Duration(seconds: 1));
            expect(f.accepted, isEmpty);
            if (stage != 'presentation') expect(f.events, ['preferences']);
            f.loader.dispose();
          });
        }
      },
    );
  }

  test(
    'optional preferences/details/presentation failures leave prior display alone',
    () {
      for (final stage in [
        'preferences',
        'details',
        'presentation',
        'null-details',
      ]) {
        fakeAsync((time) {
          final f = _Fixture();
          if (stage == 'preferences') {
            f.preferences = () async => throw StateError('read');
          }
          if (stage == 'details') {
            f.fetch = (_, _) async => throw StateError('fetch');
          }
          if (stage == 'presentation') {
            f.present = (_, _, _) async => throw StateError('present');
          }
          if (stage == 'null-details') f.fetch = (_, _) async => null;
          f.load();
          time.flushMicrotasks();
          time.elapse(const Duration(milliseconds: 140));
          expect(f.accepted, isEmpty);
          f.loader.dispose();
        });
      }
    },
  );
}
