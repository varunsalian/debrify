import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_record.dart';
import 'package:debrify/services/community/channel_yaml_builder.dart';
import 'package:debrify/services/debrify_tv_zip_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'dedicated Remote channel payload carries the complete saved hash pool',
    () {
      final now = DateTime.utc(2026, 8, 29);
      final channel = DebrifyTvChannelRecord(
        channelId: 'source-channel',
        name: 'Remote Pool',
        keywords: const <String>['science fiction'],
        avoidNsfw: true,
        channelNumber: 7,
        createdAt: now,
        updatedAt: now,
      );
      const hashes = <String>[
        'hash-one',
        'hash-two',
        'hash-orphan',
        'hash-legacy',
      ];
      final entry = DebrifyTvChannelCacheEntry(
        version: 1,
        channelId: channel.channelId,
        normalizedKeywords: const <String>['science fiction'],
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
              sources: const <String>['remote-source'],
              keywords: index == 2
                  ? const ['old keyword']
                  : index == 3
                  ? const []
                  : const [' Science Fiction '],
            ),
        ],
        keywordStats: const <String, KeywordStat>{
          'science fiction': KeywordStat(
            totalFetched: 2,
            lastSearchedAt: 123,
            pagesPulled: 1,
            pirateBayHits: 0,
          ),
        },
      );

      final yaml = ChannelYamlBuilder.buildFromEntry(channel, entry);
      final imported = DebrifyTvZipImporter.parseYaml(
        sourceName: 'remote-transfer',
        content: yaml,
      );

      expect(imported.channelName, 'Remote Pool');
      expect(imported.normalizedKeywords, <String>['science fiction']);
      expect(
        imported.torrents.map((torrent) => torrent.infohash).toSet(),
        hashes.toSet(),
      );
      expect(imported.torrentCount, hashes.length);
    },
  );
}
