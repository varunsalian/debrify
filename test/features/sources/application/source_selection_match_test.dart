import 'package:debrify/features/sources/application/source_selection_match.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter_test/flutter_test.dart';

SeriesSource pin({
  String service = SeriesSource.addonDirectService,
  String? group,
  int index = 9,
}) => SeriesSource(
  torrentHash: '',
  torrentName: '',
  debridService: service,
  debridTorrentId: '',
  boundAt: 0,
  addonId: 'addon',
  addonKey: 'config',
  streamKey: 'profile',
  streamIndex: index,
  bingeGroup: group,
  iptvPlaylistId: 'list',
  iptvCatalogType: 'series',
  iptvEntryKey: 'entry',
);
Torrent row({
  String source = 'stremio:addon',
  String config = 'config',
  String profile = 'profile',
  String? group,
  int? index,
  String entry = 'entry',
}) => Torrent(
  rowid: 0,
  infohash: '',
  name: 'Row',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: source,
  streamType: StreamType.directUrl,
  stremioAddonKey: config,
  stremioStreamKey: profile,
  stremioBingeGroup: group,
  stremioStreamIndex: index,
  iptvPlaylistId: 'list',
  iptvCatalogType: 'series',
  iptvEntryKey: entry,
);
SourceSelectionMatch match(List<SeriesSource> saved, List<Torrent> rows) =>
    matchSelectedSource(
      saved: saved,
      torrents: rows,
      mediaServerKeyFor: (_) =>
          throw StateError('media lookup outside media branch'),
    );

void main() {
  test(
    'only primary pin participates and missing selection retains reasons',
    () {
      expect(match([], [row()]).diagnostics!['reason'], 'no_saved_source');
      final result = match([pin(service: 'torbox'), pin()], [row()]);
      expect(result.source, isNull);
      expect(result.diagnostics!['reason'], 'primary_not_direct');
    },
  );

  test(
    'media matching stops at first key match and omits legacy match log',
    () {
      final saved = pin(service: SeriesSource.mediaServerService);
      final miss = row();
      final selected = row();
      final ignored = row();
      final visited = <Torrent>[];
      final result = matchSelectedSource(
        saved: [saved],
        torrents: [miss, selected, ignored],
        mediaServerKeyFor: (torrent) {
          visited.add(torrent);
          return identical(torrent, selected) ? saved.bindingKey : null;
        },
      );
      expect(result.source, same(selected));
      expect(visited, [same(miss), same(selected)]);
      expect(result.diagnostics, isNull);
    },
  );

  test('IPTV requires ownership and complete catalog identity', () {
    final saved = pin(service: SeriesSource.iptvDirectService);
    final selected = row(source: 'iptv:list');
    final result = match(
      [saved],
      [row(), row(source: 'iptv:list', entry: 'other'), selected],
    );
    expect(result.source, same(selected));
    expect(result.diagnostics!['reason'], 'matched');
    expect(
      match([saved], [row()]).diagnostics!['reason'],
      'iptv_entry_not_found',
    );
  });

  test('addon candidates sort by index without reordering published rows', () {
    final high = row(index: 7);
    final low = row(index: null);
    final wrongConfig = row(config: 'other', index: 9);
    final rows = [high, low, wrongConfig];
    final result = match([pin()], rows);
    expect(result.source, same(low));
    expect(rows, [same(high), same(low), same(wrongConfig)]);
    expect(result.diagnostics!['direct_results'], 3);
    expect(result.diagnostics!['addon_matches'], 2);
    expect(result.diagnostics!['profile_matches'], 2);
    expect(result.diagnostics!['matched_stream_index'], isNull);
    expect(() => result.diagnostics!.clear(), throwsUnsupportedError);
  });

  test('explicit binge group never falls back to another group', () {
    final result = match([pin(group: 'saved')], [row(group: 'other')]);
    expect(result.source, isNull);
    expect(result.diagnostics!['reason'], 'binge_group_not_found');
    final selected = row(group: 'saved', profile: 'changed');
    expect(match([pin(group: 'saved')], [selected]).source, same(selected));
  });

  test('addon configuration and stream identity misses stay distinct', () {
    expect(
      match([pin()], [row(config: 'other')]).diagnostics!['reason'],
      'addon_configuration_not_found',
    );
    expect(
      match([pin()], [row(profile: 'other')]).diagnostics!['reason'],
      'stream_identity_not_found',
    );
  });
}
