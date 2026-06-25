import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class IptvClient {
  static const _ua = 'VLC/3.0.20 LibVLC/3.0.20';

  static String _enc(String s) => Uri.encodeComponent(s);

  static Future<String?> _httpGet(String url, {Duration? timeout}) async {
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = _ua
        ..headers['Accept'] = 'application/json,*/*';
      final stream =
          await req.send().timeout(timeout ?? const Duration(seconds: 10));
      if (stream.statusCode < 200 || stream.statusCode >= 300) return null;
      return await stream.stream.bytesToString();
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> login(IptvPortal p,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final url =
        '${p.url}/player_api.php?username=${_enc(p.username)}&password=${_enc(p.password)}';
    final text = await _httpGet(url, timeout: timeout);
    if (text == null) return null;
    try {
      final root = json.decode(text) as Map<String, dynamic>;
      final info = (root['user_info'] as Map<String, dynamic>?) ?? root;
      final auth = info['auth']?.toString();
      final status = (info['status']?.toString() ?? '').toLowerCase();
      final ok = auth == '1' || status == 'active' || root.containsKey('user_info');
      if (!ok) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  static Future<VerifiedPortal?> verifyOrNull(IptvPortal p,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final info = await login(p, timeout: timeout);
    if (info == null) return null;
    return VerifiedPortal(
      portal: p,
      name: (info['username']?.toString() ?? '').isNotEmpty
          ? info['username'].toString()
          : p.username,
      expiry: _formatExpiry(info['exp_date']?.toString()),
      maxConnections: info['max_connections']?.toString() ?? '1',
      activeConnections: info['active_cons']?.toString() ?? '0',
    );
  }

  static String _formatExpiry(String? raw) {
    if (raw == null) return 'Unknown';
    final ts = int.tryParse(raw);
    if (ts == null) return 'Unknown';
    try {
      final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return raw;
    }
  }

  static Future<List<IptvCategory>> categories(
      IptvPortal p, IptvSection kind) async {
    final action = switch (kind) {
      IptvSection.live => 'get_live_categories',
      IptvSection.vod => 'get_vod_categories',
      IptvSection.series => 'get_series_categories',
    };
    final url = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}&action=$action';
    final text = await _httpGet(url, timeout: const Duration(seconds: 8));
    if (text == null) return [];
    try {
      final arr = json.decode(text) as List;
      return arr
          .map((e) {
            final o = e as Map<String, dynamic>;
            return IptvCategory(
              id: o['category_id']?.toString() ?? '',
              name: o['category_name']?.toString() ?? '',
            );
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<IptvStream>> streams(
      IptvPortal p, IptvSection kind, String categoryId) async {
    final action = switch (kind) {
      IptvSection.live => 'get_live_streams',
      IptvSection.vod => 'get_vod_streams',
      IptvSection.series => 'get_series',
    };
    final base = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}&action=$action';
    final url = categoryId.isEmpty ? base : '$base&category_id=${_enc(categoryId)}';
    final text = await _httpGet(url, timeout: const Duration(seconds: 15));
    if (text == null) return [];
    try {
      final arr = json.decode(text) as List;
      return arr.map((e) {
        final o = e as Map<String, dynamic>;
        final ext = switch (kind) {
          IptvSection.live => 'ts',
          IptvSection.vod => () {
              final v = o['container_extension']?.toString() ?? '';
              return v.isEmpty ? 'mp4' : v;
            }(),
          IptvSection.series => '',
        };
        final id = switch (kind) {
          IptvSection.series => () {
              final v = o['series_id']?.toString() ?? '';
              return v.isEmpty ? (o['id']?.toString() ?? '') : v;
            }(),
          _ => () {
              final v = o['stream_id']?.toString() ?? '';
              return v.isEmpty ? (o['id']?.toString() ?? '') : v;
            }(),
        };
        return IptvStream(
          streamId: id,
          name: () {
            final n = o['name']?.toString() ?? '';
            return n.isEmpty ? (o['title']?.toString() ?? '') : n;
          }(),
          icon: () {
            final i = o['stream_icon']?.toString() ?? '';
            return i.isEmpty ? (o['cover']?.toString() ?? '') : i;
          }(),
          categoryId: o['category_id']?.toString() ?? '',
          containerExt: ext,
          epgChannelId: o['epg_channel_id']?.toString() ?? '',
          kind: switch (kind) {
            IptvSection.live => 'live',
            IptvSection.vod => 'vod',
            IptvSection.series => 'series',
          },
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<IptvEpisode>> seriesEpisodes(
      IptvPortal p, String seriesId) async {
    final url = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}&action=get_series_info&series_id=${_enc(seriesId)}';
    final text = await _httpGet(url, timeout: const Duration(seconds: 15));
    if (text == null) return [];
    try {
      final root = json.decode(text) as Map<String, dynamic>;
      final episodesObj = root['episodes'] as Map<String, dynamic>?;
      if (episodesObj == null) return [];
      final out = <IptvEpisode>[];
      episodesObj.forEach((seasonKey, value) {
        final arr = value as List?;
        if (arr == null) return;
        final seasonNum = int.tryParse(seasonKey) ?? 0;
        for (final e in arr) {
          final o = e as Map<String, dynamic>?;
          if (o == null) continue;
          final info = o['info'] as Map<String, dynamic>?;
          out.add(IptvEpisode(
            id: o['id']?.toString() ?? '',
            title: o['title']?.toString() ?? '',
            containerExt: () {
              final c = o['container_extension']?.toString() ?? '';
              return c.isEmpty ? 'mp4' : c;
            }(),
            season: seasonNum,
            episode: (o['episode_num'] is num)
                ? (o['episode_num'] as num).toInt()
                : (int.tryParse(o['episode_num']?.toString() ?? '') ?? 0),
            plot: info?['plot']?.toString() ?? '',
            image: info?['movie_image']?.toString() ?? '',
          ));
        }
      });
      out.sort((a, b) {
        final s = a.season.compareTo(b.season);
        return s != 0 ? s : a.episode.compareTo(b.episode);
      });
      return out;
    } catch (_) {
      return [];
    }
  }

  static String streamUrl(IptvPortal p, IptvStream s) {
    final user = _enc(p.username);
    final pass = _enc(p.password);
    switch (s.kind) {
      case 'live':
        return '${p.url}/live/$user/$pass/${s.streamId}.${s.containerExt}';
      case 'vod':
        return '${p.url}/movie/$user/$pass/${s.streamId}.${s.containerExt}';
      default:
        return '';
    }
  }

  static String episodeUrl(IptvPortal p, IptvEpisode e) =>
      '${p.url}/series/${_enc(p.username)}/${_enc(p.password)}/${e.id}.${e.containerExt}';

  static Future<List<EpgEntry>> shortEpg(
    IptvPortal p,
    String streamId, {
    int limit = 2,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (streamId.isEmpty) return const [];
    final url = '${p.url}/player_api.php?username=${_enc(p.username)}'
        '&password=${_enc(p.password)}'
        '&action=get_short_epg&stream_id=${_enc(streamId)}&limit=$limit';
    final text = await _httpGet(url, timeout: timeout);
    if (text == null) return const [];
    try {
      final root = json.decode(text);
      final List arr = root is Map<String, dynamic>
          ? (root['epg_listings'] as List? ?? const [])
          : (root is List ? root : const []);
      DateTime? parseTs(dynamic v) {
        if (v == null) return null;
        final s = v.toString();
        final secs = int.tryParse(s);
        if (secs != null && secs > 1000000000) {
          return DateTime.fromMillisecondsSinceEpoch(secs * 1000, isUtc: true)
              .toLocal();
        }
        try {
          return DateTime.parse(s.replaceFirst(' ', 'T')).toLocal();
        } catch (_) {
          return null;
        }
      }

      String decode64(dynamic v) {
        if (v == null) return '';
        final s = v.toString();
        if (s.isEmpty) return '';
        try {
          return utf8.decode(base64.decode(s), allowMalformed: true).trim();
        } catch (_) {
          return s;
        }
      }

      final out = <EpgEntry>[];
      for (final e in arr) {
        if (e is! Map<String, dynamic>) continue;
        final start = parseTs(e['start_timestamp']) ?? parseTs(e['start']);
        final stop = parseTs(e['stop_timestamp']) ?? parseTs(e['end']);
        if (start == null || stop == null) continue;
        out.add(EpgEntry(
          title: decode64(e['title']),
          description: decode64(e['description']),
          start: start,
          stop: stop,
        ));
      }
      out.sort((a, b) => a.start.compareTo(b.start));
      return out;
    } catch (_) {
      return const [];
    }
  }
}

class IptvVerifier {
  static const _parallel = 4;

  static Future<List<VerifiedPortal>> verifyUntil({
    required List<IptvPortal> portals,
    int target = 5,
    void Function(int checked, int total, int alive)? onProgress,
    void Function(VerifiedPortal v)? onAlive,
    void Function(IptvPortal p)? onAttempted,
    bool Function()? isCancelled,
  }) async {
    if (portals.isEmpty) return const [];

    var nextIdx = 0;
    var checked = 0;
    final alive = <VerifiedPortal>[];
    final completer = Completer<void>();
    var stopped = false;

    void stop() {
      if (!stopped) {
        stopped = true;
        if (!completer.isCompleted) completer.complete();
      }
    }

    Future<void> worker() async {
      while (!stopped) {
        if (isCancelled?.call() == true) {
          stop();
          break;
        }
        if (alive.length >= target) {
          stop();
          break;
        }
        final idx = nextIdx++;
        if (idx >= portals.length) break;
        onAttempted?.call(portals[idx]);
        VerifiedPortal? v;
        try {
          v = await IptvClient.verifyOrNull(portals[idx]);
        } catch (_) {
          v = null;
        }
        if (stopped) break;
        checked++;
        if (v != null && alive.length < target) {
          alive.add(v);
          onAlive?.call(v);
        }
        onProgress?.call(checked, portals.length, alive.length);
        if (alive.length >= target) {
          stop();
          break;
        }
      }
    }

    final workers = List.generate(
      _parallel.clamp(1, portals.length),
      (_) => worker(),
    );
    await Future.any([
      Future.wait(workers),
      completer.future,
    ]);
    return List.unmodifiable(alive);
  }
}

class AliveProgress {
  final int checked;
  final int total;
  final int alive;
  const AliveProgress(this.checked, this.total, this.alive);
}

class IptvAliveChecker {
  static const int _minBytes = 16 * 1024;
  static const int _maxBytes = 64 * 1024;
  static const Duration _timeout = Duration(seconds: 8);
  static const int _concurrency = 24;

  static Future<void> launchCheck({
    required List<MapEntry<String, String>> streams,
    required Future<void> Function(String id, bool alive) onResult,
    required Future<void> Function(AliveProgress p) onProgress,
    required Future<void> Function() onDone,
    bool Function()? isCancelled,
  }) async {
    var checked = 0;
    var alive = 0;
    final total = streams.length;
    final pending = List<MapEntry<String, String>>.from(streams);

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() == true) return;
        if (pending.isEmpty) return;
        final job = pending.removeAt(0);
        final ok = await _isAlive(job.value);
        if (isCancelled?.call() == true) return;
        checked++;
        if (ok) alive++;
        await onResult(job.key, ok);
        await onProgress(AliveProgress(checked, total, alive));
      }
    }

    final workers = List.generate(_concurrency, (_) => worker());
    await Future.wait(workers);
    if (isCancelled?.call() != true) await onDone();
  }

  static Future<bool> _isAlive(String url) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..followRedirects = true
        ..headers['User-Agent'] = 'VLC/3.0.20 LibVLC/3.0.20'
        ..headers['Accept'] = '*/*'
        ..headers['Connection'] = 'keep-alive'
        ..headers['Range'] = 'bytes=0-${_maxBytes - 1}';
      final resp = await client.send(req).timeout(_timeout);
      final code = resp.statusCode;
      if (code != 206 && (code < 200 || code >= 300)) return false;
      final ct = (resp.headers['content-type'] ?? '').toLowerCase();
      if (_isDeadContentType(ct)) return false;

      final buf = <int>[];
      var ended = true;
      try {
        await for (final chunk in resp.stream.timeout(_timeout)) {
          buf.addAll(chunk);
          if (buf.length >= _maxBytes) {
            ended = false;
            break;
          }
          if (buf.length >= _minBytes) {
            ended = false;
            break;
          }
        }
      } catch (_) {
      }

      final isM3U8 = ct.contains('mpegurl') || url.toLowerCase().contains('.m3u8');
      if (isM3U8) {
        final headStr = utf8.decode(
            buf.sublist(0, buf.length < 1024 ? buf.length : 1024),
            allowMalformed: true);
        return headStr.contains('#EXTM3U');
      }
      if (ended && buf.length < _minBytes) return false;
      final cl = int.tryParse(resp.headers['content-length'] ?? '') ?? -1;
      if (cl >= 1 && cl <= 5_000_000) return false;

      if (buf.isNotEmpty && buf[0] == 0x47) {
        var validTs = true;
        var checkedPackets = 0;
        var i = 0;
        while (i < buf.length - 188 && checkedPackets < 10) {
          if (buf[i] != 0x47) {
            validTs = false;
            break;
          }
          checkedPackets++;
          i += 188;
        }
        if (validTs && checkedPackets >= 3) return true;
      }
      if (buf.length >= 8) {
        final s = String.fromCharCodes(buf.sublist(4, 8));
        if (s == 'ftyp') return true;
      }
      if (_hasVideoSignature(buf)) return true;
      if (buf.length >= 32 * 1024) return true;
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  static bool _isDeadContentType(String ct) =>
      ct.contains('text/html') ||
      ct.contains('application/json') ||
      ct.contains('text/xml') ||
      ct.contains('text/plain');

  static bool _hasVideoSignature(List<int> buf) {
    if (buf.length < 4) return false;
    if (buf[0] == 0x47) return true;
    if (buf.length >= 7) {
      final s = String.fromCharCodes(buf.sublist(0, 7));
      if (s == '#EXTM3U') return true;
    }
    if (buf.length >= 4) {
      final s = String.fromCharCodes(buf.sublist(0, 4));
      if (s == '#EXT') return true;
    }
    if (buf[0] == 0xFF && (buf[1] & 0xE0) == 0xE0) return true;
    if (buf[0] == 0x1A && buf[1] == 0x45 && buf[2] == 0xDF && buf[3] == 0xA3) {
      return true;
    }
    if (buf[0] == 0x4F && buf[1] == 0x67 && buf[2] == 0x67 && buf[3] == 0x53) {
      return true;
    }
    if (buf[0] == 0x00 && buf[1] == 0x00 && buf[2] == 0x00 && buf[3] == 0x01) {
      return true;
    }
    if (buf[0] == 0x00 && buf[1] == 0x00 && buf[2] == 0x01 && (buf[3] & 0xFF) >= 0xB0) {
      return true;
    }
    return false;
  }
}
