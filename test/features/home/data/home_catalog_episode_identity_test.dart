import 'dart:async';

import 'package:debrify/features/home/data/home_catalog_episode_identity.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';

final addon = StremioAddon(
  id: 'origin',
  name: 'Origin',
  baseUrl: 'https://fixture.invalid/config',
  manifestUrl: 'https://fixture.invalid/config/manifest.json',
  addedAt: DateTime.utc(2026),
);
const selection = AdvancedSearchSelection(
  imdbId: 'tt123',
  isSeries: true,
  title: 'Title',
  year: '2020',
  season: 2,
  episode: 3,
  contentType: 'series',
  posterUrl: 'poster',
  initialContinuousShuffle: true,
  traktSource: true,
  traktProgressPercent: 50,
  simklSource: true,
  simklProgressPercent: 40,
  mdblistSource: true,
  mdblistProgressPercent: 30,
);

class IdentityHarness {
  bool current = true, ownerCurrent = true;
  Future<String?> Function() read = () async => null;
  final calls =
      <
        ({
          StremioAddon addon,
          String id,
          String catalog,
          int season,
          int episode,
        })
      >[];
  late final resolver = HomeCatalogEpisodeIdentity(
    readVideoId:
        ({
          required addon,
          required imdbId,
          required catalogId,
          required season,
          required episode,
        }) {
          calls.add((
            addon: addon,
            id: imdbId,
            catalog: catalogId,
            season: season,
            episode: episode,
          ));
          return read();
        },
    isCanonicalCatalog: StremioService.isCanonicalCatalogAlias,
    isCanonicalEpisode: StremioService.isCanonicalEpisodeId,
    isOwnerCurrent: () => ownerCurrent,
  );
  Future<AdvancedSearchSelection?> run({
    AdvancedSearchSelection value = selection,
    String catalog = 'tt123',
  }) => resolver.resolve(
    value,
    StremioMeta(
      id: catalog,
      type: value.contentType ?? 'series',
      name: value.title,
    ),
    addon,
    isCurrent: () => current,
  );
}

void main() {
  test(
    'movies and selections without complete coordinates bypass metadata unchanged',
    () async {
      final h = IdentityHarness()
        ..read = () async => throw StateError('must not read');
      for (final value in [
        const AdvancedSearchSelection(
          imdbId: 'tt123',
          isSeries: false,
          title: 'Movie',
          season: 1,
          episode: 1,
        ),
        const AdvancedSearchSelection(
          imdbId: 'tt123',
          isSeries: true,
          title: 'Series',
          season: 1,
        ),
        const AdvancedSearchSelection(
          imdbId: 'tt123',
          isSeries: true,
          title: 'Series',
          episode: 1,
        ),
      ]) {
        expect(await h.run(value: value), same(value));
      }
      expect(h.calls, isEmpty);
    },
  );

  for (final missing in <String?>[null, '']) {
    test(
      'canonical catalog aliases retain selection when lookup returns $missing',
      () async {
        final h = IdentityHarness()..read = () async => missing;
        for (final catalog in ['tt123', 'tmdb:123', 'trakt:123']) {
          expect(await h.run(catalog: catalog), same(selection));
        }
        expect(h.calls.map((call) => call.catalog), [
          'tt123',
          'tmdb:123',
          'trakt:123',
        ]);
      },
    );
    test('custom origin remains pinned when lookup returns $missing', () async {
      final h = IdentityHarness()..read = () async => missing;
      final result = (await h.run(catalog: 'custom-cut'))!;
      expect(result.stremioVideoId, '');
      expect(result.stremioCatalogId, 'custom-cut');
      expect(result.stremioAddonId, addon.id);
      expect(result.stremioAddonKey, addon.sourceBindingKey);
      final identity = CustomSeriesIdentity.parse(result.imdbId)!;
      expect(identity.catalogId, 'custom-cut');
      expect(identity.addonKey, addon.sourceBindingKey);
    });
  }

  test(
    'canonical episode identity returns exact original selection and lookup payload',
    () async {
      final h = IdentityHarness()..read = () async => 'tt123:2:3';
      expect(await h.run(), same(selection));
      expect(h.calls, [
        (addon: addon, id: 'tt123', catalog: 'tt123', season: 2, episode: 3),
      ]);
    },
  );

  test(
    'noncanonical video retains exact spelling and the model scope/attribution contract',
    () async {
      final h = IdentityHarness()..read = () async => ' Custom:Cut:003 ';
      final result = (await h.run(catalog: 'custom-cut'))!;
      expect(
        result.stremioVideoId,
        ' Custom:Cut:003 ',
      ); // No new trimming here.
      expect(result.initialContinuousShuffle, isTrue);
      expect(
        (result.title, result.year, result.season, result.episode),
        ('Title', '2020', 2, 3),
      );
      expect(result.posterUrl, 'poster');
      expect(result.contentType, 'series');
      expect(
        (result.traktSource, result.simklSource, result.mdblistSource),
        (false, false, false),
      );
      expect(
        (
          result.traktProgressPercent,
          result.simklProgressPercent,
          result.mdblistProgressPercent,
        ),
        (null, null, null),
      );
      expect(
        CustomSeriesIdentity.parse(result.imdbId)!.catalogId,
        'custom-cut',
      );
    },
  );

  test(
    'an episode-like ID with wrong coordinates remains a custom override',
    () async {
      final h = IdentityHarness()..read = () async => 'tt123:2:4';
      final result = (await h.run())!;
      expect(result.stremioVideoId, 'tt123:2:4');
      expect((result.season, result.episode), (2, 3));
      expect(result.stremioAddonId, addon.id);
    },
  );

  for (final owner in [false, true]) {
    test(
      '${owner ? 'profile' : 'action'} retirement stops lookup/publication',
      () async {
        final wait = Completer<String?>();
        final h = IdentityHarness()..read = () => wait.future;
        final pending = h.run();
        expect(h.calls, hasLength(1));
        if (owner) {
          h.ownerCurrent = false;
        } else {
          h.current = false;
        }
        wait.complete('custom-video');
        expect(await pending, isNull);
        expect(await h.run(), isNull);
        expect(h.calls, hasLength(1));
      },
    );
  }

  test(
    'lookup errors propagate once without an implicit retry or fallback',
    () async {
      final error = StateError('lookup failed');
      final h = IdentityHarness()..read = () async => throw error;
      await expectLater(h.run(), throwsA(same(error)));
      expect(h.calls, hasLength(1));
    },
  );

  test(
    'concurrent requests keep their own original selection and identity',
    () async {
      final waits = [Completer<String?>(), Completer<String?>()];
      var calls = 0;
      final h = IdentityHarness()..read = () => waits[calls++].future;
      final first = h.run(catalog: 'cut-a'), second = h.run(catalog: 'cut-b');
      waits[1].complete('b');
      expect((await second)!.stremioCatalogId, 'cut-b');
      waits[0].complete('a');
      expect((await first)!.stremioVideoId, 'a');
      expect(h.calls.map((call) => call.catalog), ['cut-a', 'cut-b']);
    },
  );
}
