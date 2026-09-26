import 'package:debrify/features/sources/application/source_result_preparation.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter_test/flutter_test.dart';

const episode = AdvancedSearchSelection(
  imdbId: 'tt1',
  isSeries: true,
  title: 'Series',
  season: 1,
  episode: 2,
);
const series = AdvancedSearchSelection(
  imdbId: 'tt1',
  isSeries: true,
  title: 'Series',
);
const pin = SeriesSource(
  torrentHash: '',
  torrentName: 'Saved',
  debridService: SeriesSource.addonDirectService,
  debridTorrentId: '',
  boundAt: 0,
  addonId: 'addon',
  addonKey: 'config',
  streamKey: 'preferred',
  streamIndex: 2,
  bingeGroup: 'group',
);
const torrentPin = SeriesSource(
  torrentHash: 'hash',
  torrentName: 'Torrent',
  debridService: 'torbox',
  debridTorrentId: 'id',
  boundAt: 0,
);

Torrent row(
  String name, {
  bool direct = true,
  String config = 'config',
  String key = 'preferred',
  String group = 'group',
}) => Torrent(
  rowid: 0,
  infohash: name,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'stremio:$config',
  streamType: direct ? StreamType.directUrl : StreamType.torrent,
  directUrl: direct ? 'https://example.com/$name' : null,
  stremioAddonKey: config,
  stremioStreamKey: key,
  stremioBingeGroup: group,
  stremioStreamIndex: 2,
);

void main() {
  final cached = row('cached');
  ({List<Torrent> torrents, bool cachedEpisodeInserted}) prepare(
    List<Torrent> rows, {
    AdvancedSearchSelection selection = episode,
    bool searching = false,
    bool bind = false,
    List<SeriesSource> bound = const [pin],
    bool Function(Torrent)? iptv,
  }) => prepareSourceResults(
    rows,
    selection: selection,
    bindMode: bind,
    isIptvSource: iptv ?? (_) => false,
    searching: searching,
    cachedEpisodeSource: cached,
    bound: bound,
  );

  test(
    'episode query preserves all rows, prioritizing same-addon direct URLs',
    () {
      final pack = row('Series S01 pack', direct: false);
      final stream = row('untagged direct URL');
      final input = [pack, stream];
      final result = prepare(input, searching: true);
      expect(result.torrents, [same(stream), same(pack)]);
      expect(input, [same(pack), same(stream)]);
      expect(result.cachedEpisodeInserted, isFalse);
      expect(() => result.torrents.clear(), throwsUnsupportedError);
    },
  );

  test('cached fallback arrives only after completion and counts as a row', () {
    expect(prepare([], searching: true).torrents, isEmpty);
    final result = prepare([]);
    expect(result.cachedEpisodeInserted, isTrue);
    expect(result.torrents, [same(cached)]);
  });

  test(
    'matching direct stream suppresses cache, another configuration cannot',
    () {
      final matching = row('matching');
      expect(prepare([matching]).torrents, [same(matching)]);
      expect(prepare([matching]).cachedEpisodeInserted, isFalse);
      final other = row('other', config: 'other-config');
      expect(prepare([other]).torrents, [same(cached), same(other)]);
    },
  );

  test('explicit binge-group miss retains cached fallback', () {
    final wrongGroup = row('same key, wrong group', group: 'other');
    expect(prepare([wrongGroup]).cachedEpisodeInserted, isTrue);
    final sameGroup = row('same group, changed key', key: 'new');
    expect(prepare([sameGroup]).cachedEpisodeInserted, isFalse);
  });

  test('only first saved source determines cache eligibility', () {
    expect(prepare([], bound: []).torrents, isEmpty);
    expect(prepare([], bound: [torrentPin, pin]).torrents, isEmpty);
    expect(prepare([], bound: [pin, torrentPin]).torrents, [same(cached)]);
  });

  test('whole-series excludes direct singles except IPTV when binding', () {
    final stream = row('IPTV stream');
    final addon = row('addon stream');
    expect(
      prepare([stream, addon], selection: series, bound: []).torrents,
      isEmpty,
    );
    final result = prepare(
      [stream, addon],
      selection: series,
      bound: [],
      bind: true,
      iptv: (torrent) => identical(torrent, stream),
    );
    expect(result.torrents, [same(stream)]);
  });
}
