import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'pastesh_decryptor.dart';

enum CatalogSource { best, works }

class IptvScraper {
  static const _catalogSubs = ['IPTV_ZONENEW', 'FreeIPTV', 'iptvguru', 'IPTVfree'];
  static const _oauthUa = 'PlayTorrio/1.3.6 (by /u/PlayTorrioApp)';
  static const _oauthClientIds = [
    'ohXpoqrZYub1kg',
    'NOe2iKrPPzwscA',
    'JrPdG8Z6dkWNxA',
  ];
  static String? _oauthToken;
  static DateTime? _oauthTokenExpiry;
  static int _oauthClientIdx = 0;
  static const _ua = 'Mozilla/5.0 (Linux; Android 11; PlayTorrio) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36';

  static const _pasteDomains = [
    'paste.sh', 'pastebin.com', 'justpaste.it', 'controlc.com',
    'pastes.dev', 'text.is', 'rentry.co',
  ];

  static final _b64 = RegExp(r'aHR0c[a-zA-Z0-9+/=]{10,}');
  static final _rawPaste = RegExp(
    r'https?://(?:paste\.sh|pastebin\.com|justpaste\.it|controlc\.com|pastes\.dev|text\.is|rentry\.co)/[a-zA-Z0-9#_=-]+',
    caseSensitive: false,
  );
  static final _urlParam = RegExp(
    r'''(https?://[^?\s"'<]+)\?(?:[^\s"'<]*?&)?(?:username|user)=([^&\s"'<]+)\s*&(?:password|pass)=([^&\s"'<]+)''',
    caseSensitive: false,
  );
  static final _label = RegExp(
    r'''(?:Portal|Host(?:\s*URL)?|H[ᴏo]s[ᴛt]|Panel|Real|URL|🔗|🌍|🌐)\W*?(https?://[^<\s"']+)[\s\S]{1,500}?(?:Username|Usu[áa]rio|Usuario|User|Us[ᴇe]r|Us[ᴜu][ᴀa]r[ɪi][ᴏo]|👤)\W*?([^\s|<"'\n]+)[\s\S]{1,200}?(?:Password|Senha|Contrase[ñn]a|Pass|P[ᴀa]ss|S[ᴇe]nh[ᴀa]|🔑)\W*?([^\s|<"'\n]+)''',
    caseSensitive: false,
  );

  static const _junkTokens = [
    'type=m3u', 'output=ts', 'password=', 'username=', 'password', 'username',
  ];

  static const _xml2Base =
      'https://raw.githubusercontent.com/akeotaseo/world_repo/main/Updater_Matrix/XML2/';
  static const _xml2ListApi =
      'https://api.github.com/repos/akeotaseo/world_repo/contents/Updater_Matrix/XML2?ref=main';
  static const _xml2FallbackFiles = <String>[
    '25.txt',
    '71.txt',
    'ABN.txt',
    'DOV.txt',
    '%5BK_B_W_%20Client%5D.txt',
    'br.txt',
    'channels_fulltime%20(OR).txt',
    'channels_fulltime.txt',
    'kgen%20(4).txt',
    'kgen.txt',
    'rg.txt',
    'x.txt',
    '%7BAllTelegram%7D2.txt',
  ];

  static List<String>? _xml2Files;
  static DateTime? _xml2FilesFetchedAt;
  static const _xml2ListTtl = Duration(hours: 6);

  static Future<List<String>> _getXml2Files() async {
    final cached = _xml2Files;
    final fetchedAt = _xml2FilesFetchedAt;
    if (cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _xml2ListTtl) {
      return cached;
    }
    try {
      final resp = await http.get(Uri.parse(_xml2ListApi), headers: {
        'User-Agent': _ua,
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final decoded = json.decode(resp.body);
        if (decoded is List) {
          final entries = <MapEntry<String, int>>[];
          for (final entry in decoded) {
            if (entry is! Map) continue;
            if (entry['type'] != 'file') continue;
            final name = entry['name']?.toString();
            if (name == null || !name.toLowerCase().endsWith('.txt')) continue;
            final size =
                int.tryParse('${entry['size'] ?? ''}') ?? 1 << 30;
            entries.add(MapEntry(Uri.encodeComponent(name), size));
          }
          if (entries.isNotEmpty) {
            entries.sort((a, b) => a.value.compareTo(b.value));
            final files = entries.map((e) => e.key).toList(growable: false);
            _xml2Files = files;
            _xml2FilesFetchedAt = DateTime.now();
            return files;
          }
        }
      }
    } catch (e) {
      debugPrint('[XML2] list failed: $e');
    }
    _xml2Files = _xml2FallbackFiles;
    _xml2FilesFetchedAt = DateTime.now();
    return _xml2FallbackFiles;
  }

  static Future<ScrapePage> scrapeCatalogPage({
    int maxResults = 50,
    String? after,
    CatalogSource source = CatalogSource.best,
  }) async {
    switch (source) {
      case CatalogSource.best:
        String? redditAfter;
        if (after != null && after.startsWith('reddit:')) {
          final t = after.substring(7);
          redditAfter = t.isEmpty ? null : t;
        } else if (after != null && after.isNotEmpty) {
          redditAfter = after;
        }
        return _scrapeRedditCatalog(maxResults: maxResults, after: redditAfter);
      case CatalogSource.works:
        final files = await _getXml2Files();
        final idx = after == null
            ? 0
            : int.tryParse(after.substring('xml2:'.length)) ?? 0;
        if (idx < files.length) {
          return _scrapeXml2File(idx, files);
        }
        return const ScrapePage(portals: [], nextAfter: null);
    }
  }

  static Future<ScrapePage> _scrapeXml2File(
      int idx, List<String> files) async {
    final encoded = files[idx];
    final url = '$_xml2Base$encoded';
    final pretty = Uri.decodeComponent(encoded).replaceAll('.txt', '');

    String? body;
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': _ua,
        'Accept': 'text/plain,*/*',
      }).timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        body = resp.body;
      }
    } catch (e) {
      debugPrint('[XML2]   fetch failed: $e');
    }

    final next = idx + 1 < files.length ? 'xml2:${idx + 1}' : null;
    if (body == null || body.isEmpty) {
      return ScrapePage(portals: const [], nextAfter: next);
    }

    final extracted = _extractPortals(body, 'XML2/$pretty');
    return ScrapePage(portals: extracted, nextAfter: next);
  }

  static Future<ScrapePage> _scrapeRedditCatalog(
      {int maxResults = 50, String? after}) async {
    final out = <String, IptvPortal>{};

    var subIdx = 0;
    String? redditAfter;
    if (after != null && after.isNotEmpty) {
      final parts = after.split(':');
      if (parts.length >= 3) {
        subIdx = int.tryParse(parts[1]) ?? 0;
        redditAfter = parts.sublist(2).join(':');
        if (redditAfter.isEmpty || redditAfter == 'null') redditAfter = null;
      } else if (parts.length == 2) {
        redditAfter = parts[1];
        if (redditAfter.isEmpty || redditAfter == 'null') redditAfter = null;
      }
    }
    if (subIdx >= _catalogSubs.length) subIdx = 0;
    final currentSub = _catalogSubs[subIdx];

    final catalogJson = await _fetchCatalogOAuth(
        sub: currentSub, after: redditAfter);
    if (catalogJson != null) {
      Map<String, dynamic>? data;
      try {
        data = (json.decode(catalogJson) as Map<String, dynamic>)['data']
            as Map<String, dynamic>?;
      } catch (e) {
        debugPrint('[Catalog] JSON parse failed: $e');
      }
      if (data != null) {
        final posts = data['children'] as List? ?? [];
        final nextAfterRaw = data['after']?.toString();
        final hasMore = nextAfterRaw != null &&
            nextAfterRaw.isNotEmpty &&
            nextAfterRaw != 'null';
        String? nextAfter;
        if (hasMore) {
          nextAfter = 'reddit:$subIdx:$nextAfterRaw';
        } else if (subIdx + 1 < _catalogSubs.length) {
          nextAfter = 'reddit:${subIdx + 1}:';
        }

        for (final post in posts) {
          if (out.length >= maxResults) break;
          final pdata =
              ((post as Map<String, dynamic>)['data']) as Map<String, dynamic>?;
          if (pdata == null) continue;
          final title = pdata['title']?.toString() ?? '';
          final body = '$title ${pdata['selftext']?.toString() ?? ''}'.trim();
          _processPostBody(body, out, maxResults);
        }

        await _processDeepLinks(posts, out, maxResults);

        return ScrapePage(portals: out.values.toList(), nextAfter: nextAfter);
      }
    }

    final rssBody = await _fetchCatalogRss(sub: currentSub, after: redditAfter);
    if (rssBody == null) {
      if (subIdx + 1 < _catalogSubs.length) {
        return ScrapePage(
            portals: const [], nextAfter: 'reddit:${subIdx + 1}:');
      }
      return const ScrapePage(portals: [], nextAfter: null);
    }

    final entryRe = RegExp(r'<entry>(.*?)</entry>', dotAll: true);
    final contentRe = RegExp(r'<content[^>]*>(.*?)</content>', dotAll: true);
    final idRe = RegExp(r'<id>(t3_[^<]+)</id>');

    final entries = entryRe.allMatches(rssBody).toList();
    final postIds = idRe.allMatches(rssBody).map((m) => m.group(1)!).toList();
    final lastPostId = postIds.isNotEmpty ? postIds.last : null;
    String? nextAfter;
    if (lastPostId != null && entries.length >= 20) {
      nextAfter = 'reddit:$subIdx:$lastPostId';
    } else if (subIdx + 1 < _catalogSubs.length) {
      nextAfter = 'reddit:${subIdx + 1}:';
    }

    for (final entry in entries) {
      if (out.length >= maxResults) break;
      final entryText = entry.group(1)!;
      final contentMatch = contentRe.firstMatch(entryText);
      final rawContent = _decodeXmlEntities(contentMatch?.group(1) ?? '');
      final body = rawContent
          .replaceAll(
            RegExp(r'<(?:p|br|div|li|h\d)[^>]*>', caseSensitive: false),
            '\n',
          )
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      _processPostBody(body, out, maxResults);
    }

    return ScrapePage(portals: out.values.toList(), nextAfter: nextAfter);
  }

  static void _processPostBody(
      String body, Map<String, IptvPortal> out, int maxResults) {
    final direct = _extractPortals(body, 'Catalog');
    for (final p in direct) {
      if (out.length >= maxResults) break;
      out.putIfAbsent(p.key, () => p);
    }
  }

  static Future<void> _processDeepLinks(
      List posts, Map<String, IptvPortal> out, int maxResults) async {
    for (final post in posts) {
      if (out.length >= maxResults) break;
      final pdata =
          ((post as Map<String, dynamic>)['data']) as Map<String, dynamic>?;
      if (pdata == null) continue;
      final title = pdata['title']?.toString() ?? '';
      final body = '$title ${pdata['selftext']?.toString() ?? ''}'.trim();

      final deepLinks = <String>[];
      for (final m in _b64.allMatches(body)) {
        try {
          final decoded = utf8.decode(base64.decode(m.group(0)!),
              allowMalformed: true);
          if (decoded.startsWith('http') && _isPasteSite(decoded)) {
            deepLinks.add(decoded);
          } else if (!decoded.startsWith('http') && decoded.contains(':')) {
            _extractPortals(decoded, 'Catalog (decoded)')
                .forEach((p) => out.putIfAbsent(p.key, () => p));
          }
        } catch (_) {}
      }
      for (final m in _rawPaste.allMatches(body)) {
        deepLinks.add(m.group(0)!);
      }
      final unique = deepLinks.toSet().take(4);
      for (final dl in unique) {
        if (out.length >= maxResults) break;
        final text = await _fetchPaste(dl);
        if (text == null || text.isEmpty) continue;
        final found = _extractPortals(text, 'Catalog (deep)');
        for (final p in found) {
          out.putIfAbsent(p.key, () => p);
        }
      }
    }
  }

  static List<IptvPortal> _extractPortals(String rawText, String source) {
    if (rawText.length < 15 || _isJunkCode(rawText)) return const [];
    final cleaned = rawText
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll(
          RegExp(r'<(?:p|br|div|li|h\d)[^>]*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '');

    final acc = <String, IptvPortal>{};
    for (final m in _urlParam.allMatches(cleaned)) {
      _finalize(acc, m.group(1)!, m.group(2)!, m.group(3)!, source);
    }
    for (final m in _label.allMatches(cleaned)) {
      _finalize(acc, m.group(1)!, m.group(2)!, m.group(3)!, source);
    }
    return acc.values.toList();
  }

  static bool _isJunkCode(String text) {
    const markers = [
      'Array.isArray', 'prototype.', 'function(', 'var ', 'const ',
      'let ', 'return!', 'void ', '.message}', 'window.', 'document.',
    ];
    var hits = 0;
    for (final m in markers) {
      if (text.contains(m)) hits++;
      if (hits >= 2) return true;
    }
    return false;
  }

  static void _finalize(Map<String, IptvPortal> acc, String rawUrl,
      String rawUser, String rawPass, String source) {
    final url = _cleanPortalUrl(rawUrl);
    final user = _cleanCred(rawUser);
    final pass = _cleanCred(rawPass);
    if (url.isEmpty || user.length < 3 || pass.length < 3) return;
    if (user.contains('http') || pass.contains('http')) return;
    final lu = user.toLowerCase();
    final lp = pass.toLowerCase();
    for (final j in _junkTokens) {
      if (lu.contains(j) || lp.contains(j)) return;
    }
    final p = IptvPortal(url: url, username: user, password: pass, source: source);
    acc.putIfAbsent(p.key, () => p);
  }

  static String _cleanPortalUrl(String raw) {
    var clean = raw.replaceAll(RegExp(r'\s+'), '');
    final qIdx = clean.indexOf('?');
    if (qIdx >= 0) clean = clean.substring(0, qIdx);
    clean = clean.trim();
    if (clean.contains('@')) {
      clean = 'http://${clean.substring(clean.lastIndexOf('@') + 1)}';
    }
    clean = clean.replaceAll(
      RegExp(
        r'/(?:get|live|portal|c|index|playlist|player_api|xmltv|index\.php|portal\.php)\.php$',
        caseSensitive: false,
      ),
      '',
    );
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (!clean.startsWith('http')) clean = 'http://$clean';
    return clean;
  }

  static String _cleanCred(String raw) {
    var s = raw;
    while (s.startsWith('=')) {
      s = s.substring(1);
    }
    final parts = s.split(RegExp(r'[ \n&?]'));
    return parts.isEmpty ? '' : parts.first.trim();
  }

  static bool _isPasteSite(String url) =>
      _pasteDomains.any((d) => url.contains(d));

  static Future<String?> _fetchPaste(String url) async {
    if (url.contains('paste.sh/') && url.contains('#')) {
      final out = await PasteShDecryptor.decrypt(url);
      return out.isEmpty ? null : out;
    }
    if (url.contains('pastebin.com/') && !url.contains('/raw/')) {
      final id = _lastPathSegment(url);
      return _httpGetText('https://pastebin.com/raw/$id');
    }
    if (url.contains('pastes.dev/')) {
      final id = _lastPathSegment(url);
      return _httpGetText('https://api.pastes.dev/$id');
    }
    if (url.contains('rentry.co/') && !url.contains('/raw')) {
      final id = _lastPathSegment(url);
      return _httpGetText('https://rentry.co/$id/raw');
    }
    return _httpGetText(url);
  }

  static String _lastPathSegment(String url) {
    var s = url;
    final h = s.indexOf('#');
    if (h >= 0) s = s.substring(0, h);
    final q = s.indexOf('?');
    if (q >= 0) s = s.substring(0, q);
    final slash = s.lastIndexOf('/');
    return slash >= 0 ? s.substring(slash + 1) : s;
  }

  static Future<String?> _httpGetText(String url) async {
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': _ua,
        'Accept': 'text/html,application/json,*/*',
      }).timeout(const Duration(seconds: 15));
      return resp.body;
    } catch (e) {
      return null;
    }
  }

  static String _decodeXmlEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#32;', ' ');

  static Future<String?> _getOAuthToken() async {
    if (_oauthToken != null &&
        _oauthTokenExpiry != null &&
        DateTime.now().isBefore(_oauthTokenExpiry!)) {
      return _oauthToken;
    }
    for (var i = 0; i < _oauthClientIds.length; i++) {
      final idx = (_oauthClientIdx + i) % _oauthClientIds.length;
      final clientId = _oauthClientIds[idx];
      try {
        final resp = await http.post(
          Uri.parse('https://www.reddit.com/api/v1/access_token'),
          headers: {
            'User-Agent': _oauthUa,
            'Authorization':
                'Basic ${base64.encode(utf8.encode('$clientId:'))}',
          },
          body: {
            'grant_type':
                'https://oauth.reddit.com/grants/installed_client',
            'device_id': 'DO_NOT_TRACK_THIS_DEVICE',
          },
        ).timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final token = data['access_token'] as String?;
          final expiresIn = data['expires_in'] as int? ?? 3600;
          if (token != null && token.isNotEmpty) {
            _oauthToken = token;
            _oauthTokenExpiry = DateTime.now()
                .add(Duration(seconds: expiresIn - 60));
            _oauthClientIdx = idx;
            return token;
          }
        }
      } catch (e) {
        debugPrint('[Catalog] OAuth auth error (client #$idx): $e');
      }
    }
    _oauthClientIdx =
        (_oauthClientIdx + 1) % _oauthClientIds.length;
    _oauthToken = null;
    _oauthTokenExpiry = null;
    return null;
  }

  static Future<String?> _fetchCatalogOAuth(
      {required String sub, String? after}) async {
    final token = await _getOAuthToken();
    if (token == null) return null;

    final base =
        'https://oauth.reddit.com/r/$sub/new?limit=100&sort=new&raw_json=1';
    final url = (after == null || after.isEmpty)
        ? base
        : '$base&after=$after';

    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': _oauthUa,
        'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final t = resp.body.trimLeft();
        if (t.startsWith('{') || t.startsWith('[')) return resp.body;
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        _oauthToken = null;
        _oauthTokenExpiry = null;
      }
    } catch (e) {
      debugPrint('[Catalog]   OAuth failed: $e');
    }
    return null;
  }

  static Future<String?> _fetchCatalogRss(
      {required String sub, String? after}) async {
    final base =
        'https://www.reddit.com/r/$sub/new/.rss?limit=25';
    final url = (after == null || after.isEmpty)
        ? base
        : '$base&after=$after';

    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': _oauthUa,
        'Accept': 'application/atom+xml, application/xml, */*',
      }).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 && resp.body.contains('<entry>')) {
        return resp.body;
      }
    } catch (e) {
      debugPrint('[Catalog]   RSS failed: $e');
    }
    return null;
  }
}
