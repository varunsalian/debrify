import 'package:archive/archive.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/services/debrify_tv_channel_archive_service.dart';
import 'package:debrify/services/debrify_tv_zip_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'selected channels round-trip with their complete saved pools',
    () async {
      final first = _source(
        id: 'first',
        name: '../Science \\ Fiction: Night',
        keyword: 'science fiction',
        hashes: const <String>['hash-one', 'hash-two'],
        orphanLastHash: true,
        sources: const <String>['custom"engine', r'custom\engine'],
      );
      final second = _source(
        id: 'second',
        name: '../Science \\ Fiction: Night',
        keyword: 'comedy',
        hashes: const <String>['hash-three'],
      );

      final bytes = await DebrifyTvChannelArchiveService.buildZip(
        <DebrifyTvChannelArchiveSource>[first, second],
      );
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);

      expect(archive.files, hasLength(2));
      expect(archive.files.map((file) => file.name), <String>[
        '001-Science-Fiction-Night.yaml',
        '002-Science-Fiction-Night.yaml',
      ]);
      expect(
        archive.files.every(
          (file) => !file.name.contains('/') && !file.name.contains(r'\'),
        ),
        isTrue,
      );

      final imported = DebrifyTvZipImporter.parseZip(bytes);
      expect(imported.failures, isEmpty);
      expect(imported.channels, hasLength(2));
      // Equal display names are legal archive members; importing resolves any
      // destination name collision later. Both payloads must still be present.
      final poolSignatures = imported.channels.map((channel) {
        final hashes =
            channel.torrents.map((torrent) => torrent.infohash).toList()
              ..sort();
        return hashes.join(',');
      }).toList()..sort();
      expect(poolSignatures, <String>['hash-one,hash-two', 'hash-three']);
      final escapedSourceChannel = imported.channels.singleWhere(
        (channel) =>
            channel.torrents.any((torrent) => torrent.infohash == 'hash-one'),
      );
      expect(
        escapedSourceChannel.torrents
            .singleWhere((torrent) => torrent.infohash == 'hash-one')
            .sources
            .toSet(),
        <String>{'custom"engine', r'custom\engine'},
      );
    },
  );

  test('empty selection is rejected before archive work starts', () {
    expect(
      () => DebrifyTvChannelArchiveService.buildZip(
        const <DebrifyTvChannelArchiveSource>[],
      ),
      throwsArgumentError,
    );
  });
}

DebrifyTvChannelArchiveSource _source({
  required String id,
  required String name,
  required String keyword,
  required List<String> hashes,
  bool orphanLastHash = false,
  List<String> sources = const <String>['archive-test'],
}) {
  final now = DateTime.utc(2026, 8, 29);
  final channel = DebrifyTvChannelRecord(
    channelId: id,
    name: name,
    keywords: <String>[keyword],
    avoidNsfw: true,
    channelNumber: 1,
    createdAt: now,
    updatedAt: now,
  );
  return DebrifyTvChannelArchiveSource(
    channel: channel,
    cacheEntry: DebrifyTvChannelCacheEntry(
      version: 1,
      channelId: id,
      normalizedKeywords: <String>[keyword],
      fetchedAt: now.millisecondsSinceEpoch,
      status: DebrifyTvCacheStatus.ready,
      errorMessage: null,
      torrents: <CachedTorrent>[
        for (var index = 0; index < hashes.length; index++)
          CachedTorrent(
            rowid: index,
            infohash: hashes[index],
            name: 'Saved title $index',
            sizeBytes: 1000 + index,
            createdUnix: 100 + index,
            seeders: 10 + index,
            leechers: index,
            completed: 20 + index,
            scrapedDate: 200 + index,
            sources: sources,
            keywords: orphanLastHash && index == hashes.length - 1
                ? const <String>[]
                : <String>[keyword],
          ),
      ],
      keywordStats: <String, KeywordStat>{
        keyword: KeywordStat(
          totalFetched: hashes.length,
          lastSearchedAt: 123,
          pagesPulled: 1,
          pirateBayHits: 0,
        ),
      },
    ),
  );
}
