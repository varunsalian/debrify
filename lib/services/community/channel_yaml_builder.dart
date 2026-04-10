import '../../models/debrify_tv_cache.dart';
import '../../models/debrify_tv_channel_record.dart';
import '../debrify_tv_cache_service.dart';

class ChannelYamlBuilder {
  static Future<String> build(DebrifyTvChannelRecord channel) async {
    final cacheEntry = await DebrifyTvCacheService.getEntry(channel.channelId);
    return buildFromEntry(channel, cacheEntry);
  }

  static String buildFromEntry(
    DebrifyTvChannelRecord channel,
    DebrifyTvChannelCacheEntry? cacheEntry,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('channel_name: "${escapeYamlString(channel.name)}"');
    buffer.writeln('avoid_nsfw: ${channel.avoidNsfw}');
    buffer.writeln('');
    buffer.writeln('keywords:');

    final cachedTorrents = cacheEntry?.torrents ?? const <CachedTorrent>[];
    final keywordStats = cacheEntry?.keywordStats ?? const <String, KeywordStat>{};

    for (final keyword in channel.keywords) {
      buffer.writeln('  "${escapeYamlString(keyword)}":');

      final keywordLower = keyword.toLowerCase();
      final stat = keywordStats[keywordLower];
      if (stat != null) {
        buffer.writeln('    total_fetched: ${stat.totalFetched}');
        buffer.writeln('    last_searched_at: ${stat.lastSearchedAt}');
        buffer.writeln('    pages_pulled: ${stat.pagesPulled}');
        buffer.writeln('    pirate_bay_hits: ${stat.pirateBayHits}');
      }

      final seen = <String>{};
      final matchingTorrents = cachedTorrents
          .where((t) => t.keywords.contains(keywordLower))
          .where((t) {
        if (seen.contains(t.infohash)) return false;
        seen.add(t.infohash);
        return true;
      }).toList();

      if (matchingTorrents.isEmpty) {
        buffer.writeln('    torrents: []');
      } else {
        buffer.writeln('    torrents:');
        for (final torrent in matchingTorrents) {
          buffer.writeln('      - infohash: ${torrent.infohash}');
          buffer.writeln('        name: "${escapeYamlString(torrent.name)}"');
          buffer.writeln('        size_bytes: ${torrent.sizeBytes}');
          buffer.writeln('        created_unix: ${torrent.createdUnix}');
          buffer.writeln('        seeders: ${torrent.seeders}');
          buffer.writeln('        leechers: ${torrent.leechers}');
          buffer.writeln('        completed: ${torrent.completed}');
          buffer.writeln('        scraped_date: ${torrent.scrapedDate}');
          if (torrent.sources.isNotEmpty) {
            buffer.writeln(
                '        sources: [${torrent.sources.map((s) => '"$s"').join(', ')}]');
          }
        }
      }
    }

    return buffer.toString();
  }

  static String escapeYamlString(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}
