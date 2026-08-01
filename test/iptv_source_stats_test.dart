import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_source_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IptvSourceStatsLoader.ago', () {
    final now = DateTime(2026, 8, 1, 12);

    test('renders each bucket', () {
      String at(Duration d) =>
          IptvSourceStatsLoader.ago(now.subtract(d), now: now);
      expect(at(const Duration(seconds: 20)), 'just now');
      expect(at(const Duration(minutes: 5)), '5m ago');
      expect(at(const Duration(hours: 2)), '2h ago');
      expect(at(const Duration(days: 3)), '3d ago');
      expect(at(const Duration(days: 14)), '2w ago');
      expect(at(const Duration(days: 90)), '3mo ago');
      expect(at(const Duration(days: 800)), '2y ago');
    });

    test('never ingested reads as never, not as a stale timestamp', () {
      expect(IptvSourceStatsLoader.ago(null), 'never');
    });

    test('a clock that jumped backwards still reads sanely', () {
      expect(
        IptvSourceStatsLoader.ago(now.add(const Duration(hours: 3)), now: now),
        'just now',
      );
    });
  });

  group('IptvSourceStatsLoader.count', () {
    test('groups thousands', () {
      expect(IptvSourceStatsLoader.count(0), '0');
      expect(IptvSourceStatsLoader.count(999), '999');
      expect(IptvSourceStatsLoader.count(1000), '1,000');
      expect(IptvSourceStatsLoader.count(12480), '12,480');
      expect(IptvSourceStatsLoader.count(1234567), '1,234,567');
    });
  });

  group('read() without a catalog DB', () {
    test('a local file reports uncached rather than zero channels', () {
      final stats = IptvSourceStatsLoader.read(
        IptvPlaylist(
          id: 'local',
          name: 'backup.m3u',
          url: '',
          content: '#EXTM3U',
          addedAt: DateTime(2026),
        ),
      );
      // "Not loaded" and "empty" must not look alike — the pane branches on
      // `cached` to avoid presenting one as the other.
      expect(stats.cached, isFalse);
      expect(stats.live, 0);
      expect(stats.guide, IptvGuideSource.none);
    });

    test('a custom EPG URL is reported even with nothing ingested', () {
      final stats = IptvSourceStatsLoader.read(
        IptvPlaylist(
          id: 'local2',
          name: 'backup.m3u',
          url: '',
          content: '#EXTM3U',
          epgUrl: 'https://example.com/guide.xml.gz',
          addedAt: DateTime(2026),
        ),
      );
      expect(stats.guide, IptvGuideSource.custom);
    });

    test('a closed catalog DB yields no stats instead of throwing', () {
      final stats = IptvSourceStatsLoader.read(
        IptvPlaylist(
          id: 'remote',
          name: 'Freeview',
          url: 'https://example.com/playlist.m3u',
          addedAt: DateTime(2026),
        ),
      );
      expect(stats.cached, isFalse);
    });
  });

  group('IptvSourceStats', () {
    test('hasVodSplit only when a VOD catalog actually has rows', () {
      const m3u = IptvSourceStats(
        cached: true,
        live: 1204,
        movies: 0,
        series: 0,
        categories: 42,
        refreshedAt: null,
        guide: IptvGuideSource.none,
      );
      expect(m3u.hasVodSplit, isFalse);

      const xtream = IptvSourceStats(
        cached: true,
        live: 12480,
        movies: 8912,
        series: 1043,
        categories: 310,
        refreshedAt: null,
        guide: IptvGuideSource.provider,
      );
      expect(xtream.hasVodSplit, isTrue);
      expect(xtream.total, 22435);
    });
  });

  group('guide reporting', () {
    test('an Xtream login always reports a provider guide', () {
      // Panels serve per-stream get_short_epg plus their own xmltv.php, which
      // is what IptvEpgService.isEpgCapable keys on. It is NOT recoverable
      // from the catalog: only the M3U ingest path ever writes epg_url.
      final stats = IptvSourceStatsLoader.read(
        IptvPlaylist(
          id: 'xc',
          name: 'Panel',
          url: '',
          serverUrl: 'http://panel.example:8080',
          username: 'u',
          password: 'p',
          addedAt: DateTime(2026),
        ),
      );
      expect(stats.guide, IptvGuideSource.provider);
    });

    test('a custom XMLTV URL outranks the panel guide', () {
      final stats = IptvSourceStatsLoader.read(
        IptvPlaylist(
          id: 'xc2',
          name: 'Panel',
          url: '',
          serverUrl: 'http://panel.example:8080',
          username: 'u',
          password: 'p',
          epgUrl: 'https://example.com/guide.xml.gz',
          addedAt: DateTime(2026),
        ),
      );
      expect(stats.guide, IptvGuideSource.custom);
    });

    test('an imported file with url-tvg in its header has a guide', () {
      // Local playback reparses the stored content and honours the header,
      // so reporting "none" here would be plainly false.
      final stats = IptvSourceStatsLoader.read(
        IptvPlaylist(
          id: 'f1',
          name: 'file.m3u',
          url: '',
          content:
              '#EXTM3U url-tvg="https://example.com/g.xml.gz"\n'
              '#EXTINF:-1,News\nhttp://x/1.ts\n',
          addedAt: DateTime(2026),
        ),
      );
      expect(stats.guide, IptvGuideSource.provider);
    });

    test('an imported file without a guide header reports none', () {
      final stats = IptvSourceStatsLoader.read(
        IptvPlaylist(
          id: 'f2',
          name: 'file.m3u',
          url: '',
          content: '#EXTM3U\n#EXTINF:-1,News\nhttp://x/1.ts\n',
          addedAt: DateTime(2026),
        ),
      );
      expect(stats.guide, IptvGuideSource.none);
    });

    test('only the header line is consulted, not the body', () {
      // A channel line mentioning url-tvg must not be mistaken for a header
      // declaration - and a huge body must not be scanned.
      final stats = IptvSourceStatsLoader.read(
        IptvPlaylist(
          id: 'f3',
          name: 'file.m3u',
          url: '',
          content:
              '#EXTM3U\n'
              '#EXTINF:-1 url-tvg="https://example.com/g.xml",News\n'
              'http://x/1.ts\n',
          addedAt: DateTime(2026),
        ),
      );
      expect(stats.guide, IptvGuideSource.none);
    });
  });

  test('a catalog just under a year old is not reported as 0y', () {
    final now = DateTime(2026, 8, 1, 12);
    for (final days in [359, 360, 364]) {
      final label = IptvSourceStatsLoader.ago(
        now.subtract(Duration(days: days)),
        now: now,
      );
      expect(label, isNot(startsWith('0')), reason: '$days days -> $label');
      expect(label, endsWith('mo ago'), reason: '$days days -> $label');
    }
    expect(
      IptvSourceStatsLoader.ago(
        now.subtract(const Duration(days: 365)),
        now: now,
      ),
      '1y ago',
    );
  });
}
