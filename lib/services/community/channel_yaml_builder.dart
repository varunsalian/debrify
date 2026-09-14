import '../../models/debrify_tv_cache.dart';
import '../../models/debrify_tv_channel_record.dart';
import '../debrify_tv_cache_service.dart';

class ChannelYamlBuilder {
  static Future<String> build(DebrifyTvChannelRecord channel) async {
    final cacheEntry = await DebrifyTvCacheService.getEntryForPortableExport(
      channel.channelId,
    );
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
    final keywordStats =
        cacheEntry?.keywordStats ?? const <String, KeywordStat>{};

    // A saved pool may outlive a keyword edit or contain legacy rows with no
    // keyword association. Preserve those hashes under the first current
    // keyword rather than silently exporting an incomplete channel.
    final normalized = channel.keywords
        .map((keyword) => keyword.trim().toLowerCase())
        .toSet();
    final fallback = normalized.firstOrNull;
    final byKeyword = <String, Map<String, CachedTorrent>>{};
    for (final torrent in cachedTorrents) {
      final matches = torrent.keywords
          .map((keyword) => keyword.trim().toLowerCase())
          .where(normalized.contains)
          .toSet();
      if (matches.isEmpty && fallback != null) matches.add(fallback);
      for (final keyword in matches) {
        (byKeyword[keyword] ??= <String, CachedTorrent>{}).putIfAbsent(
          torrent.infohash,
          () => torrent,
        );
      }
    }

    for (final keyword in channel.keywords) {
      buffer.writeln('  "${escapeYamlString(keyword)}":');

      final keywordLower = keyword.trim().toLowerCase();
      final stat = keywordStats[keywordLower];
      if (stat != null) {
        buffer.writeln('    total_fetched: ${stat.totalFetched}');
        buffer.writeln('    last_searched_at: ${stat.lastSearchedAt}');
        buffer.writeln('    pages_pulled: ${stat.pagesPulled}');
        buffer.writeln('    pirate_bay_hits: ${stat.pirateBayHits}');
      }

      final matchingTorrents =
          byKeyword[keywordLower]?.values ?? const <CachedTorrent>[];

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
              '        sources: [${torrent.sources.map((source) => '"${escapeYamlString(source)}"').join(', ')}]',
            );
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
