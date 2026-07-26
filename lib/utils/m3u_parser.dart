import 'dart:convert';

import '../models/iptv_playlist.dart';

/// Parser for M3U/M3U8 playlist files
class M3uParser {
  /// Decode raw playlist bytes as UTF-8 so non-ASCII channel names survive,
  /// falling back to latin1 for legacy playlists. Shared by the URL-fetch and
  /// file-import paths so both decode identically.
  static String decodeBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  /// Parse M3U content into a list of channels
  static IptvParseResult parse(String content) {
    // Strip a UTF-8 BOM so the #EXTM3U header is recognized
    if (content.startsWith('﻿')) {
      content = content.substring(1);
    }
    final lines = content.split('\n').map((l) => l.trim()).toList();
    final channels = <IptvChannel>[];
    final categories = <String>{};

    if (lines.isEmpty) {
      return const IptvParseResult(
        channels: [],
        categories: [],
        error: 'Empty playlist',
      );
    }

    // Check for M3U header (optional but common). It may declare the
    // playlist's XMLTV guide via url-tvg= / x-tvg-url=.
    int startIndex = 0;
    String? epgUrl;
    if (lines.first.startsWith('#EXTM3U')) {
      startIndex = 1;
      epgUrl = _parseHeaderEpgUrl(lines.first);
    }

    String? currentName;
    String? currentLogo;
    String? currentGroup;
    int? currentDuration;
    Map<String, String> currentAttributes = {};
    Map<String, String> currentHeaders = {};

    for (int i = startIndex; i < lines.length; i++) {
      final line = lines[i];

      if (line.isEmpty || line.startsWith('#EXTGRP')) {
        continue;
      }

      if (line.startsWith('#EXTINF:')) {
        // Parse EXTINF line: #EXTINF:duration tvg-attributes,Channel Name
        final parsed = _parseExtInf(line);
        currentDuration = parsed.duration;
        currentName = parsed.name;
        currentLogo = parsed.attributes['tvg-logo'];
        currentGroup = parsed.attributes['group-title'];
        currentAttributes = parsed.attributes;
        // Some playlists declare the channel's headers inline on the EXTINF
        // line; the #EXTVLCOPT/#EXTHTTP lines below may then add or override.
        currentHeaders = _headersFromAttributes(parsed.attributes);

        if (currentGroup != null && currentGroup.isNotEmpty) {
          categories.add(currentGroup);
        }
      } else if (line.startsWith('#EXTVLCOPT:')) {
        _applyVlcOption(line.substring(11), currentHeaders);
      } else if (line.startsWith('#EXTHTTP:')) {
        _applyExtHttp(line.substring(9), currentHeaders);
      } else if (!line.startsWith('#')) {
        // This is the URL line
        if (currentName != null && line.isNotEmpty) {
          // `url|User-Agent=…` entries carry their headers in the URL itself.
          final (url, urlHeaders) = _splitUrlOptions(line.trim());
          // Accept playable stream schemes; keep the list curated so
          // non-playable entries (plugin://, file://, ...) stay filtered out.
          if (RegExp(r'^(https?|rtmps?|rtsps?|udp|rtp|mms[ht]?|srt)://',
                  caseSensitive: false)
              .hasMatch(url)) {
            channels.add(IptvChannel(
              name: currentName,
              url: url,
              logoUrl: currentLogo,
              group: currentGroup,
              duration: currentDuration,
              attributes: currentAttributes,
              // Most channels declare none, and a big playlist is tens of
              // thousands of these — don't hand each one its own empty map.
              httpHeaders: currentHeaders.isEmpty && urlHeaders.isEmpty
                  ? const {}
                  : {...currentHeaders, ...urlHeaders},
            ));
          }
        }

        // Reset for next entry
        currentName = null;
        currentLogo = null;
        currentGroup = null;
        currentDuration = null;
        currentAttributes = {};
        currentHeaders = {};
      }
    }

    // Sort categories alphabetically
    final sortedCategories = categories.toList()..sort();

    return IptvParseResult(
      channels: channels,
      categories: sortedCategories,
      epgUrl: epgUrl,
    );
  }

  /// XMLTV guide URL from the `#EXTM3U` header: `url-tvg="…"` (also seen as
  /// `x-tvg-url=`, quoted or bare). The value may be a comma-separated list;
  /// only the first entry is used.
  static String? _parseHeaderEpgUrl(String header) {
    final match = RegExp(
      '''(?:url-tvg|x-tvg-url)=(?:"([^"]*)"|'([^']*)'|(\\S+))''',
      caseSensitive: false,
    ).firstMatch(header);
    if (match == null) return null;
    final value =
        (match.group(1) ?? match.group(2) ?? match.group(3) ?? '').trim();
    if (value.isEmpty) return null;
    final first = value.split(',').first.trim();
    if (!first.startsWith('http')) return null;
    return first;
  }

  // ── Per-channel HTTP headers ────────────────────────────────────────────
  //
  // Playlists declare these in several dialects and players are expected to
  // honor all of them. Dropping them (as we used to) makes a channel that
  // needs a specific UA or Referer fail with no visible reason — and for a
  // provider that ships one UA line per entry, that is the whole playlist.

  /// Playlist option name → HTTP header name. Returns null for options that
  /// aren't headers at all (`#EXTVLCOPT:network-caching`, ...).
  static String? _headerNameFor(String key) {
    switch (key.trim().toLowerCase()) {
      case 'http-user-agent':
      case 'user-agent':
      case 'useragent':
        return 'User-Agent';
      case 'http-referrer':
      case 'http-referer':
      case 'referrer':
      case 'referer':
        return 'Referer';
      case 'http-origin':
      case 'origin':
        return 'Origin';
      case 'http-cookie':
      case 'cookie':
        return 'Cookie';
    }
    return null;
  }

  /// Headers declared inline on the EXTINF line, e.g.
  /// `#EXTINF:-1 http-user-agent="Mozilla/5.0 ..." group-title="News",BBC`.
  static Map<String, String> _headersFromAttributes(
    Map<String, String> attributes,
  ) {
    final headers = <String, String>{};
    attributes.forEach((key, value) {
      final name = _headerNameFor(key);
      if (name != null && value.isNotEmpty) headers[name] = value;
    });
    return headers;
  }

  /// `#EXTVLCOPT:http-user-agent=Mozilla/5.0 (Windows ...)` — one option per
  /// line, the value unquoted and free to contain '=' and spaces.
  static void _applyVlcOption(String option, Map<String, String> headers) {
    final eq = option.indexOf('=');
    if (eq <= 0) return;
    final name = _headerNameFor(option.substring(0, eq));
    if (name == null) return;
    var value = option.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isNotEmpty) headers[name] = value;
  }

  /// `#EXTHTTP:{"User-Agent":"...","Referer":"..."}` — the keys are already
  /// HTTP header names, so they pass through as written.
  static void _applyExtHttp(String raw, Map<String, String> headers) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is String && key.trim().isNotEmpty && value != null) {
          headers[key.trim()] = value.toString();
        }
      });
    } catch (_) {
      // Malformed #EXTHTTP: the channel still plays with whatever else it
      // declared, rather than losing the entry.
    }
  }

  /// Split a `url|User-Agent=X&Referer=Y` entry into the bare URL and its
  /// headers. Left joined, the pipe segment is part of the URL we hand the
  /// player, so every channel in such a playlist 404s.
  ///
  /// A '|' that yields no options at all is left alone: it's a (technically
  /// illegal but real) literal pipe inside the URL — usually in a token —
  /// and truncating there would break a channel that works today.
  static (String, Map<String, String>) _splitUrlOptions(String raw) {
    final pipe = raw.indexOf('|');
    if (pipe < 0) return (raw, const {});
    final headers = <String, String>{};
    // Both separators are in the wild: `|A=1|B=2` and `|A=1&B=2`.
    for (final part in raw.substring(pipe + 1).split(RegExp(r'[|&]'))) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      final rawKey = part.substring(0, eq).trim();
      // Unknown keys pass through when they read as a header name — a server
      // ignores request headers it doesn't know, but dropping a real one
      // (Authorization, X-...) would break the channel.
      final name = _headerNameFor(rawKey) ??
          (RegExp(r'^[A-Za-z][A-Za-z0-9-]*$').hasMatch(rawKey) ? rawKey : null);
      if (name == null) continue;
      final value = _decodeOption(part.substring(eq + 1).trim());
      if (value.isNotEmpty) headers[name] = value;
    }
    if (headers.isEmpty) return (raw, const {});
    return (raw.substring(0, pipe).trim(), headers);
  }

  /// Pipe-suffix values are percent-encoded in some playlists and plain in
  /// others; a malformed escape must not cost us the header.
  static String _decodeOption(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  /// Parse EXTINF line
  static _ExtInfResult _parseExtInf(String line) {
    // Format: #EXTINF:duration [attributes],Channel Name
    // Example: #EXTINF:-1 tvg-id="ch1" tvg-logo="http://..." group-title="Sports",ESPN

    String? name;
    int? duration;
    final attributes = <String, String>{};

    // Remove #EXTINF: prefix
    final content = line.substring(8);

    // Parse quoted attributes (key="value" or key='value') first; the
    // backreference keeps apostrophes inside double-quoted values intact.
    final attrRegex = RegExp(r'''(\S+?)=(["'])(.*?)\2''');
    final attrMatches = attrRegex.allMatches(content).toList();
    final searchFrom = attrMatches.isEmpty ? 0 : attrMatches.last.end;

    // The name is everything after the first comma that follows the quoted
    // attributes and is not itself inside quotes; names may contain commas.
    int commaIndex = -1;
    String? quoteChar;
    for (int i = searchFrom; i < content.length; i++) {
      final c = content[i];
      if (quoteChar != null) {
        if (c == quoteChar) quoteChar = null;
      } else if (c == '"' || c == "'") {
        quoteChar = c;
      } else if (c == ',') {
        commaIndex = i;
        break;
      }
    }
    // An unquoted attribute (key=value) before the comma means the comma may
    // sit inside an attribute value; prefer the last comma as separator then.
    if (commaIndex != -1 &&
        content.substring(searchFrom, commaIndex).contains('=')) {
      commaIndex = content.lastIndexOf(',');
    }
    // A stray/unclosed quote can swallow the rest of the line; fall back to
    // the last comma so malformed-but-real-world lines still yield a name.
    if (commaIndex == -1) {
      final fallback = content.lastIndexOf(',');
      if (fallback >= searchFrom) {
        commaIndex = fallback;
      }
    }

    if (commaIndex != -1) {
      name = content.substring(commaIndex + 1).trim();
    }

    // Parse duration (first part before space or attributes)
    final durationMatch = RegExp(r'^(-?\d+)').firstMatch(content);
    if (durationMatch != null) {
      duration = int.tryParse(durationMatch.group(1) ?? '');
    }

    for (final match in attrMatches) {
      // Ignore anything that merely looks like an attribute inside the name.
      if (commaIndex != -1 && match.start > commaIndex) break;
      final key = match.group(1)?.toLowerCase();
      final value = match.group(3);
      if (key != null && value != null) {
        attributes[key] = value;
      }
    }

    // Fall back to tvg-name for entries without a display name
    if (name == null || name.isEmpty) {
      name = attributes['tvg-name'];
    }

    return _ExtInfResult(
      name: (name == null || name.isEmpty) ? 'Unknown Channel' : name,
      duration: duration,
      attributes: attributes,
    );
  }
}

class _ExtInfResult {
  final String name;
  final int? duration;
  final Map<String, String> attributes;

  _ExtInfResult({
    required this.name,
    this.duration,
    required this.attributes,
  });
}
