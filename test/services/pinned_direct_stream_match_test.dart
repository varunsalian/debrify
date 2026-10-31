// A saved direct source that misses the next episode is recorded with a
// fixed reason, so a user's diagnostics export can tell a season pack that
// lost its episode from a single-episode release or an empty addon reply.

import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/pinned_direct_stream_match.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent stream(String key, {String? group}) => Torrent(
  rowid: 0,
  infohash: 'url:$key',
  name: key,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: 'stremio:addon',
  streamType: StreamType.directUrl,
  directUrl: 'https://cdn.test/$key',
  stremioStreamKey: key,
  stremioBingeGroup: group,
);

void main() {
  final offered = [stream('b', group: 'torrentio|${'e' * 40}')];

  test('nothing offered', () {
    expect(pinnedDirectMissReason(const [], 'g'), 'no_direct_streams');
  });

  test('a season pack group that disappeared', () {
    final pack = 'torrentio|${'f6f9d41c' * 5}';

    expect(
      matchPinnedDirectStream(
        offered,
        streamKey: 'a',
        streamIndex: 0,
        bingeGroup: pack,
      ),
      isNull,
    );
    expect(pinnedDirectMissReason(offered, pack), 'pack_group_missing');
  });

  test('a single-episode release group that disappeared', () {
    expect(
      pinnedDirectMissReason(offered, 'torrentio|720p|DEMAND'),
      'binge_group_missing',
    );
  });

  test('an ungrouped stream profile that disappeared', () {
    expect(pinnedDirectMissReason(offered, null), 'profile_missing');
  });
}
