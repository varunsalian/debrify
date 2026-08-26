import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/utils/m3u_parser.dart';

/// Per-channel HTTP headers: playlists declare them in several dialects and a
/// player is expected to honor all of them. Dropping them makes a channel that
/// needs a specific UA/Referer fail with no visible reason — and for providers
/// that ship one UA line per entry, that is the entire playlist.
void main() {
  group('M3uParser per-channel headers', () {
    test('reads #EXTVLCOPT user-agent and referrer', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1 tvg-id="a" group-title="News",Channel A
#EXTVLCOPT:http-user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130
#EXTVLCOPT:http-referrer=https://example.com/player
http://host/live/a.m3u8
''');

      expect(result.channels, hasLength(1));
      expect(
        result.channels.first.httpHeaders['User-Agent'],
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130',
      );
      expect(
        result.channels.first.httpHeaders['Referer'],
        'https://example.com/player',
      );
    });

    test('reads inline EXTINF attributes', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1 tvg-id="b" http-user-agent="VLC/3.0.20" group-title="Sports",Channel B
http://host/live/b.m3u8
''');

      expect(result.channels.first.httpHeaders['User-Agent'], 'VLC/3.0.20');
      // The name parse must not be disturbed by the extra attribute.
      expect(result.channels.first.name, 'Channel B');
    });

    test('reads #EXTHTTP json', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1,Channel C
#EXTHTTP:{"User-Agent":"Kodi/20","Cookie":"session=xyz"}
http://host/live/c.ts
''');

      expect(result.channels.first.httpHeaders['User-Agent'], 'Kodi/20');
      expect(result.channels.first.httpHeaders['Cookie'], 'session=xyz');
    });

    test('splits |-suffixed URL options off the URL', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1,Channel D
http://host/live/d.ts|User-Agent=TiviMate/4.7.0&Referer=http://host/
''');

      final channel = result.channels.single;
      // Left joined, the pipe segment is part of the URL and the channel 404s.
      expect(channel.url, 'http://host/live/d.ts');
      expect(channel.httpHeaders['User-Agent'], 'TiviMate/4.7.0');
      expect(channel.httpHeaders['Referer'], 'http://host/');
    });

    test('a literal | in the URL is not mistaken for options', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1,Channel D2
http://host/live/d2.ts?token=abc|def
''');

      // Nothing after the pipe parses as Key=Value, so it's part of the URL —
      // truncating there would break a channel that works today.
      expect(
        result.channels.single.url,
        'http://host/live/d2.ts?token=abc|def',
      );
      expect(result.channels.single.httpHeaders, isEmpty);
    });

    test('unknown but header-shaped URL options survive', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1,Channel D3
http://host/live/d3.ts|Authorization=Bearer xyz
''');

      expect(result.channels.single.url, 'http://host/live/d3.ts');
      expect(result.channels.single.httpHeaders['Authorization'], 'Bearer xyz');
    });

    test('#EXTVLCOPT non-header options are ignored', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1,Channel E
#EXTVLCOPT:network-caching=1000
http://host/live/e.m3u8
''');

      expect(result.channels.single.httpHeaders, isEmpty);
    });

    test('headers do not leak from one channel to the next', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1,Channel F
#EXTVLCOPT:http-user-agent=AgentF
http://host/live/f.m3u8
#EXTINF:-1,Channel G
http://host/live/g.m3u8
''');

      expect(result.channels, hasLength(2));
      expect(result.channels[0].httpHeaders['User-Agent'], 'AgentF');
      expect(result.channels[1].httpHeaders, isEmpty);
    });

    test('malformed #EXTHTTP keeps the channel', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1,Channel H
#EXTHTTP:{not json
http://host/live/h.m3u8
''');

      expect(result.channels, hasLength(1));
      expect(result.channels.single.httpHeaders, isEmpty);
    });
  });

  group('IptvChannel.playbackHeaders', () {
    test('fills in a browser UA when the playlist named none', () {
      final channel = IptvChannel(name: 'X', url: 'http://host/x.ts');

      // Without this mpv/ffmpeg sends Lavf/<version>, which IPTV panels block.
      expect(channel.playbackHeaders['User-Agent'], kIptvDefaultUserAgent);
    });

    test("keeps the playlist's own UA and other headers", () {
      final channel = IptvChannel(
        name: 'X',
        url: 'http://host/x.ts',
        httpHeaders: const {'User-Agent': 'VLC/3.0.20', 'Referer': 'http://r/'},
      );

      expect(channel.playbackHeaders['User-Agent'], 'VLC/3.0.20');
      expect(channel.playbackHeaders['Referer'], 'http://r/');
    });

    test('does not add a duplicate UA under different casing', () {
      final channel = IptvChannel(
        name: 'X',
        url: 'http://host/x.ts',
        httpHeaders: const {'user-agent': 'VLC/3.0.20'},
      );

      expect(channel.playbackHeaders.length, 1);
      expect(channel.playbackHeaders['user-agent'], 'VLC/3.0.20');
    });
  });

  group('M3U live classification', () {
    test('zero-duration EPGenius entries remain live and guide-eligible', () {
      final result = M3uParser.parse('''
#EXTM3U url-tvg="https://example.com/guide.xml.gz"
#EXTINF:0 CUID="1495580" tvg-name="AWE" tvg-id="awe.us" group-title="TV Guide",AWE
https://example.com/live/awe.ts
''');

      expect(result.epgUrl, 'https://example.com/guide.xml.gz');
      expect(result.channels.single.duration, 0);
      expect(result.channels.single.tvgId, 'awe.us');
      expect(result.channels.single.isLive, isTrue);
    });

    test('positive-duration M3U entries remain VOD', () {
      final channel = IptvChannel(
        name: 'Movie',
        url: 'https://example.com/movie.mp4',
        duration: 5400,
      );

      expect(channel.isLive, isFalse);
    });
  });
}
