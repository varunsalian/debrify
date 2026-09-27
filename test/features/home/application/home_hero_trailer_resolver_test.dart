import 'dart:async';
import 'package:debrify/features/home/application/home_hero_trailer_dependencies.dart';
import 'package:debrify/features/home/application/home_hero_trailer_resolver.dart';
import 'package:debrify/features/home/data/home_hero_trailer_repository.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/services/youtube_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const item = StremioMeta(
  id: 'tt1',
  type: 'movie',
  name: 'Title',
  trailerYtId: 'catalog-yt',
);
const playable = YoutubeResolvedStreams(playUrl: 'video');
const backup = YoutubeResolvedStreams(playUrl: 'imdb');
MetadataTrailer trailer(String key) => MetadataTrailer(
  key: key,
  title: 'Trailer',
  language: '',
  type: 'Trailer',
  official: false,
);

class _Fixture {
  bool current = true;
  MetadataPreferences? preferences = MetadataPreferences();
  final events = <String>[];
  Future<List<MetadataTrailer>> Function(Future<String?> Function())? select;
  Future<StremioMeta?> Function(String, String) fetch = (_, _) async =>
      const StremioMeta(
        id: 'tt1',
        type: 'movie',
        name: 'Details',
        trailerYtId: 'meta-yt',
      );
  Future<YoutubeResolvedStreams?> Function(String) youtube = (_) async =>
      playable;
  Future<YoutubeResolvedStreams?> Function(String) imdb = (_) async => backup;
  late final repository = HomeHeroTrailerRepository(
    readPreferences: (current) async {
      events.add('preferences');
      return preferences;
    },
    selectTrailers: (_, original, prefs) async {
      events.add('select');
      if (select != null) return select!(original);
      final key = await original();
      return key == null || key.isEmpty ? [] : [trailer(key)];
    },
    fetchDetails: (id, type) {
      events.add('meta:$id:$type');
      return fetch(id, type);
    },
    resolveYoutube: (id) {
      events.add('youtube:$id');
      return youtube(id);
    },
    resolveImdb: (id) {
      events.add('imdb:$id');
      return imdb(id);
    },
  );
  late final resolver = HomeHeroTrailerResolver(repository);
}

void main() {
  test(
    'catalog YouTube bypasses details and playable output bypasses backup',
    () async {
      final f = _Fixture();
      final result = await f.resolver.resolve(item, isCurrent: () => f.current);
      expect(result.streams, same(playable));
      expect(result.retired, isFalse);
      expect(f.events, ['preferences', 'select', 'youtube:catalog-yt']);
    },
  );

  test(
    'missing catalog trailer fetches details using explicit canonical identity',
    () async {
      final f = _Fixture();
      final result = await f.resolver.resolve(
        const StremioMeta(
          id: 'tmdb:1',
          imdbId: 'tt9',
          type: 'series',
          name: 'Mapped',
        ),
        isCurrent: () => true,
      );
      expect(result.streams, same(playable));
      expect(f.events, [
        'preferences',
        'select',
        'meta:tt9:series',
        'youtube:meta-yt',
      ]);
    },
  );

  test(
    'provider-selected trailer can resolve unmapped titles without original lookup',
    () async {
      final f = _Fixture();
      f.select = (_) async => [trailer('selected')];
      final result = await f.resolver.resolve(
        const StremioMeta(id: 'custom', type: 'movie', name: 'Custom'),
        isCurrent: () => true,
      );
      expect(result.streams, same(playable));
      expect(f.events, ['preferences', 'select', 'youtube:selected']);
    },
  );

  test(
    'backup respects selected-provider fallback and first-candidate precedence',
    () async {
      for (final provider in ['current', 'tmdb']) {
        for (final fallback in [false, true]) {
          final f = _Fixture();
          f.preferences = MetadataPreferences(
            providers: {MetadataCategory.trailers: provider},
            fallback: fallback,
          );
          f.select = (_) async => [trailer('first'), trailer('second')];
          f.youtube = (_) async => const YoutubeResolvedStreams();
          final result = await f.resolver.resolve(item, isCurrent: () => true);
          final allowed = provider == 'current' || fallback;
          expect(result.streams, allowed ? same(backup) : isNull);
          expect(f.events, [
            'preferences',
            'select',
            'youtube:first',
            if (allowed) 'imdb:tt1',
          ]);
          expect(result.retired, isFalse);
        }
      }
    },
  );

  test(
    'empty first candidate skips YouTube and still permits IMDb backup',
    () async {
      final f = _Fixture();
      f.select = (_) async => [trailer(''), trailer('ignored')];
      final result = await f.resolver.resolve(item, isCurrent: () => true);
      expect(result.streams, same(backup));
      expect(f.events, ['preferences', 'select', 'imdb:tt1']);
    },
  );

  test('optional meta failure can recover through IMDb', () async {
    final f = _Fixture();
    f.fetch = (_, _) async => throw StateError('meta unavailable');
    final result = await f.resolver.resolve(
      const StremioMeta(id: 'tt1', type: 'movie', name: 'Title'),
      isCurrent: () => true,
    );
    expect(result.streams, same(backup));
    expect(f.events, ['preferences', 'select', 'meta:tt1:movie', 'imdb:tt1']);
  });

  test(
    'no mapping or unplayable backup is unavailable rather than retired',
    () async {
      final unmapped = _Fixture();
      final noId = await unmapped.resolver.resolve(
        const StremioMeta(id: 'custom', type: 'movie', name: 'Custom'),
        isCurrent: () => true,
      );
      expect(noId.streams, isNull);
      expect(noId.retired, isFalse);
      expect(unmapped.events, ['preferences', 'select']);
      final f = _Fixture();
      f.youtube = (_) async => null;
      f.imdb = (_) async => const YoutubeResolvedStreams();
      final empty = await f.resolver.resolve(item, isCurrent: () => true);
      expect(empty.streams, isNull);
      expect(empty.retired, isFalse);
    },
  );

  test(
    'unavailable preferences retain the caller guarded-failure path',
    () async {
      final f = _Fixture();
      f.current = false;
      f.preferences = null;
      final result = await f.resolver.resolve(item, isCurrent: () => f.current);
      expect(result.retired, isFalse);
      expect(result.streams, isNull);
      expect(f.events, ['preferences']);
    },
  );

  for (final stage in ['candidates', 'youtube', 'imdb']) {
    test(
      'retired $stage completion stops remaining work without failure publication',
      () async {
        final f = _Fixture();
        final started = Completer<void>();
        final release = Completer<void>();
        if (stage == 'candidates') {
          f.select = (_) async {
            started.complete();
            await release.future;
            return [trailer('late')];
          };
        } else if (stage == 'youtube') {
          f.youtube = (_) async {
            started.complete();
            await release.future;
            return null;
          };
        } else {
          f.youtube = (_) async => null;
          f.imdb = (_) async {
            started.complete();
            await release.future;
            return backup;
          };
        }
        final future = f.resolver.resolve(item, isCurrent: () => f.current);
        await started.future;
        f.current = false;
        release.complete();
        final result = await future;
        expect(result.retired, isTrue);
        expect(result.streams, isNull);
        if (stage == 'candidates') expect(f.events, ['preferences', 'select']);
        if (stage == 'youtube') {
          expect(f.events, ['preferences', 'select', 'youtube:catalog-yt']);
        }
      },
    );
  }

  test(
    'resolver errors keep original caller error handling rather than starting backup',
    () async {
      final f = _Fixture();
      f.youtube = (_) async => throw StateError('resolve failed');
      await expectLater(
        f.resolver.resolve(item, isCurrent: () => true),
        throwsStateError,
      );
      expect(f.events, ['preferences', 'select', 'youtube:catalog-yt']);
    },
  );

  test(
    'Riverpod injects services without resolving during construction',
    () async {
      final f = _Fixture();
      final container = ProviderContainer.test(
        overrides: [
          homeHeroTrailerRepositoryProvider.overrideWithValue(f.repository),
        ],
      );
      final resolver = container.read(homeHeroTrailerResolverProvider);
      expect(f.events, isEmpty);
      final result = await resolver.resolve(item, isCurrent: () => true);
      expect(result.streams, same(playable));
      expect(f.events, ['preferences', 'select', 'youtube:catalog-yt']);
    },
  );
}
