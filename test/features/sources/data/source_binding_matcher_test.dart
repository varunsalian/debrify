import 'package:debrify/features/sources/data/source_binding_matcher.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter_test/flutter_test.dart';

SeriesSource pin({
  String service = 'torbox',
  String hash = 'hash',
  String? group,
}) => SeriesSource(
  torrentHash: hash,
  torrentName: 'Saved',
  debridService: service,
  debridTorrentId: 'descriptor',
  boundAt: 0,
  addonId: 'addon',
  addonKey: 'config',
  streamKey: 'profile',
  bingeGroup: group,
  iptvPlaylistId: 'playlist',
  iptvCatalogType: 'series',
  iptvEntryKey: 'entry',
);

Torrent row({
  StreamType type = StreamType.torrent,
  String hash = 'hash',
  String config = 'config',
  String profile = 'profile',
  String? group,
  String playlist = 'playlist',
  String catalog = 'series',
  String entry = 'entry',
}) => Torrent(
  rowid: 0,
  infohash: hash,
  name: 'Row',
  source: 'fixture',
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  streamType: type,
  stremioAddonKey: config,
  stremioStreamKey: profile,
  stremioBingeGroup: group,
  iptvPlaylistId: playlist,
  iptvCatalogType: catalog,
  iptvEntryKey: entry,
);

SourceBindingMatcher matcher({bool iptv = false}) => SourceBindingMatcher(
  mediaServerKeyFor: (_) => throw StateError('Unexpected media lookup'),
  isIptv: (_) => iptv,
);

void main() {
  test('empty pins do not perform any identity lookup', () {
    final subject = SourceBindingMatcher(
      mediaServerKeyFor: (_) => throw StateError('Unexpected media lookup'),
      isIptv: (_) => throw StateError('Unexpected IPTV lookup'),
    );
    expect(subject.match([], row()), isNull);
  });

  test('saved order wins and the original binding object is returned', () {
    final first = pin();
    final second = pin(service: 'realdebrid');
    expect(matcher().match([first, second], row()), same(first));
    expect(matcher().match([second, first], row()), same(second));
  });

  test('hash matching requires torrent type and an exact nonempty hash', () {
    final subject = matcher();
    expect(subject.match([pin()], row(hash: 'HASH')), isNull);
    expect(subject.match([pin(hash: '')], row(hash: '')), isNull);
    expect(subject.match([pin()], row(type: StreamType.directUrl)), isNull);
    expect(subject.match([pin()], row(type: StreamType.externalUrl)), isNull);
  });

  test(
    'addon matching keeps configuration and group/profile compatibility',
    () {
      final subject = matcher();
      final saved = pin(
        service: SeriesSource.addonDirectService,
        group: 'group',
      );
      Torrent direct({
        String config = 'config',
        String profile = 'profile',
        String? group,
      }) => row(
        type: StreamType.directUrl,
        config: config,
        profile: profile,
        group: group,
      );
      expect(
        subject.match([saved], direct(group: 'group', profile: 'other')),
        same(saved),
      );
      expect(subject.match([saved], direct()), same(saved));
      expect(subject.match([saved], direct(group: 'different')), isNull);
      expect(
        subject.match([saved], direct(config: 'foreign', group: 'group')),
        isNull,
      );
      expect(
        subject.match([saved], row()),
        same(saved),
      ); // Existing hash fallback.
    },
  );

  test('IPTV ownership and all catalog identity fields must match', () {
    final saved = pin(service: SeriesSource.iptvDirectService, hash: '');
    final subject = matcher(iptv: true);
    expect(subject.match([saved], row()), same(saved));
    expect(matcher().match([saved], row()), isNull);
    expect(subject.match([saved], row(playlist: 'other')), isNull);
    expect(subject.match([saved], row(catalog: 'movie')), isNull);
    expect(subject.match([saved], row(entry: 'other')), isNull);
  });

  test('media lookup is conditional and stops at the first saved match', () {
    final first = pin(service: SeriesSource.mediaServerService, hash: 'first');
    final second = pin(
      service: SeriesSource.mediaServerService,
      hash: 'second',
    );
    final visited = <Torrent>[];
    final torrent = row(hash: 'unmatched');
    final subject = SourceBindingMatcher(
      mediaServerKeyFor: (row) {
        visited.add(row);
        return second.bindingKey;
      },
      isIptv: (_) => false,
    );
    expect(
      subject.match([
        pin(hash: 'unmatched-pin'),
        first,
        second,
        second,
      ], torrent),
      same(second),
    );
    expect(visited, [same(torrent), same(torrent)]);
  });

  test('identity resolution is live across calls and is not retained', () {
    final saved = pin(service: SeriesSource.mediaServerService, hash: '');
    String? key = saved.bindingKey;
    final subject = SourceBindingMatcher(
      mediaServerKeyFor: (_) => key,
      isIptv: (_) => false,
    );
    final torrent = row(hash: '');
    expect(subject.match([saved], torrent), same(saved));
    key = null;
    expect(subject.match([saved], torrent), isNull);
  });
}
