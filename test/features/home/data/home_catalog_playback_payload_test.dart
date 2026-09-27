import 'package:debrify/features/home/data/home_catalog_playback_payload.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/play_loader_art.dart';
import 'package:debrify/models/playback_resume_policy.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

StremioAddon addon(String id) => StremioAddon(
  id: id,
  name: id,
  baseUrl: 'https://fixture.invalid/$id',
  manifestUrl: 'https://fixture.invalid/$id/manifest.json',
  addedAt: DateTime.utc(2026),
);
AdvancedSearchSelection selection(
  String id, {
  bool series = false,
  String? type,
}) => AdvancedSearchSelection(
  imdbId: id,
  title: 'Fixture',
  isSeries: series,
  contentType: type,
);

void main() {
  test(
    'raw catalog movie and channel IDs remain usable for addon stream lookup',
    () {
      for (final (id, type) in [
        ('kitsu:7', 'movie'),
        ('iptv:channel-7', 'tv'),
        ('', 'channel'),
      ]) {
        final selected = homeCatalogMovieSelection(
          StremioMeta(
            id: id,
            type: type,
            name: 'Raw title',
            year: '2026',
            poster: 'https://art.invalid/poster',
          ),
        );
        expect(selected.imdbId, id);
        expect(selected.isSeries, isFalse);
        expect(selected.title, 'Raw title');
        expect(selected.contentType, type);
        expect(selected.year, '2026');
        expect(selected.posterUrl, 'https://art.invalid/poster');
        expect(selected.season, isNull);
        expect(selected.episode, isNull);
        expect(selected.traktSource, isFalse);
        expect(selected.simklSource, isFalse);
        expect(selected.mdblistSource, isFalse);
        expect(selected.initialContinuousShuffle, isFalse);
        expect(selected.fromCatalogItemDetail, isFalse);
        expect(selected.fromCatalogEpisodeDrillDown, isFalse);
      }
    },
  );

  test('resolved progress identity wins over the raw catalog ID', () {
    const imdb = StremioMeta(
      id: 'provider-cut',
      imdbId: 'tt123',
      type: 'movie',
      name: 'Fixture',
    );
    expect(homeCatalogMovieSelection(imdb).imdbId, 'tt123');
    const native = StremioMeta(id: 'tmdb:123', type: 'movie', name: 'Native');
    expect(homeCatalogMovieSelection(native).imdbId, 'tmdb:movie:123');
    final custom = const CustomSeriesIdentity('configuration-A', 'cut:7').id;
    expect(
      homeCatalogMovieSelection(
        StremioMeta(id: 'cut:7', imdbId: custom, type: 'movie', name: 'Custom'),
      ).imdbId,
      custom,
    );
  });

  test(
    'movie resume values and source attribution are passed independently',
    () {
      final selected = homeCatalogMovieSelection(
        const StremioMeta(id: 'tt123', type: 'movie', name: 'Fixture'),
        isTraktSource: true,
        isMdblistSource: true,
        traktProgressPercent: 100,
        simklProgressPercent: 0,
        mdblistProgressPercent: 42,
      );
      expect(
        selected.traktProgressPercent,
        100,
      ); // Eligibility is owned by the readers/player.
      expect(selected.simklProgressPercent, 0);
      expect(selected.mdblistProgressPercent, 42);
      expect(selected.traktSource, isTrue);
      expect(selected.simklSource, isFalse);
      expect(selected.mdblistSource, isTrue);
      final meta = homeCatalogPlaybackMeta(selected, fallbackAddonId: null);
      expect(meta.traktProgressPercent, 100);
      expect(meta.simklProgressPercent, 0);
      expect(meta.mdblistProgressPercent, 42);
      expect(meta.traktScrobble, isTrue);
      expect(meta.simklScrobble, isFalse);
      expect(meta.mdblistScrobble, isTrue);
      expect(meta.resumePolicy, PlaybackResumePolicy.catalogCanonical);
    },
  );

  test(
    'metadata admits the existing IMDb native and custom identity forms only',
    () {
      final custom = const CustomSeriesIdentity('configuration-A', 'cut:7').id;
      for (final id in [
        'tt123',
        'ttarbitrary',
        'tmdb:123',
        'tmdb:movie:123',
        'simkl:456',
        custom,
        'custom-series:malformed',
      ]) {
        expect(
          homeCatalogPlaybackMeta(selection(id), fallbackAddonId: null).imdbId,
          id,
        );
      }
      for (final id in [
        'TT123',
        '',
        'iptv:channel-7',
        'kitsu:7',
        'tmdb:series:123',
      ]) {
        expect(
          homeCatalogPlaybackMeta(selection(id), fallbackAddonId: null).imdbId,
          isNull,
        );
      }
    },
  );

  test(
    'configured catalog origin wins over explicit and ambient addon IDs',
    () {
      final source = addon('configured');
      final item = StremioMeta(
        id: 'catalog-cut',
        type: 'movie',
        name: 'Fixture',
        sourceAddon: source,
      );
      final meta = homeCatalogPlaybackMeta(
        selection('tt123'),
        fallbackAddonId: 'ambient',
        addonId: 'explicit',
        catalogItem: item,
      );
      expect(meta.addonId, 'configured');
      expect(meta.catalogItem, same(item));
      expect(meta.catalogItem!.sourceAddon, same(source));
      expect(
        homeCatalogPlaybackMeta(
          selection('tt123'),
          fallbackAddonId: 'ambient',
          addonId: 'explicit',
        ).addonId,
        'explicit',
      );
      expect(
        homeCatalogPlaybackMeta(
          selection('tt123'),
          fallbackAddonId: 'ambient',
        ).addonId,
        'ambient',
      );
      expect(
        homeCatalogPlaybackMeta(
          selection('tt123'),
          fallbackAddonId: null,
        ).addonId,
        isNull,
      );
      expect(
        homeCatalogPlaybackMeta(
          selection('tt123'),
          fallbackAddonId: 'ambient',
          addonId: '',
        ).addonId,
        '',
      );
      expect(
        homeCatalogPlaybackMeta(
          selection('tt123'),
          fallbackAddonId: 'ambient',
          addonId: 'explicit',
          catalogItem: item.withSourceAddon(addon('')),
        ).addonId,
        '',
      );
    },
  );

  test(
    'episode identity shuffle artwork and all tracker flags survive handoff',
    () {
      const selected = AdvancedSearchSelection(
        imdbId: 'tt123',
        isSeries: true,
        title: 'Series',
        year: '2026',
        season: 3,
        episode: 7,
        posterUrl: 'https://art.invalid/poster',
        initialContinuousShuffle: true,
        stremioAddonId: 'manifest',
        stremioAddonKey: 'configuration',
        stremioCatalogId: 'cut:7',
        stremioVideoId: 'special-episode',
        traktSource: true,
        traktProgressPercent: 11,
        simklSource: true,
        simklProgressPercent: 22,
        mdblistSource: true,
        mdblistProgressPercent: 33,
      );
      const art = PlayLoaderArt(logoUrl: 'https://art.invalid/logo');
      final meta = homeCatalogPlaybackMeta(
        selected,
        fallbackAddonId: 'ambient',
        art: art,
      );
      expect(meta.title, 'Series');
      expect(meta.year, '2026');
      expect(meta.contentType, 'series');
      expect(meta.season, 3);
      expect(meta.episode, 7);
      expect(meta.posterUrl, selected.posterUrl);
      expect(meta.initialContinuousShuffle, isTrue);
      expect(meta.stremioAddonId, 'manifest');
      expect(meta.stremioAddonKey, 'configuration');
      expect(meta.stremioCatalogId, 'cut:7');
      expect(meta.stremioVideoId, 'special-episode');
      expect(meta.traktScrobble, isTrue);
      expect(meta.traktProgressPercent, 11);
      expect(meta.simklScrobble, isTrue);
      expect(meta.simklProgressPercent, 22);
      expect(meta.mdblistScrobble, isTrue);
      expect(meta.mdblistProgressPercent, 33);
      expect(meta.art, same(art));
      expect(meta.resumePolicy, PlaybackResumePolicy.catalogCanonical);
    },
  );

  test(
    'absent content type falls back to movie and explicit types are retained',
    () {
      final plain = homeCatalogPlaybackMeta(
        selection('tt123'),
        fallbackAddonId: null,
      );
      expect(plain.contentType, 'movie');
      expect(plain.art, isNull);
      expect(plain.traktProgressPercent, isNull);
      expect(plain.simklProgressPercent, isNull);
      expect(plain.mdblistProgressPercent, isNull);
      expect(
        homeCatalogPlaybackMeta(
          selection('iptv:7', type: 'tv'),
          fallbackAddonId: null,
        ).contentType,
        'tv',
      );
      expect(
        homeCatalogPlaybackMeta(
          selection('tt123', series: true, type: ''),
          fallbackAddonId: null,
        ).contentType,
        '',
      );
    },
  );
}
