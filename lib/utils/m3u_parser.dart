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

    // Check for M3U header (optional but common)
    int startIndex = 0;
    if (lines.first.startsWith('#EXTM3U')) {
      startIndex = 1;
    }

    String? currentName;
    String? currentLogo;
    String? currentGroup;
    int? currentDuration;
    Map<String, String> currentAttributes = {};

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

        if (currentGroup != null && currentGroup.isNotEmpty) {
          categories.add(currentGroup);
        }
      } else if (!line.startsWith('#')) {
        // This is the URL line
        if (currentName != null && line.isNotEmpty) {
          final url = line.trim();
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
            ));
          }
        }

        // Reset for next entry
        currentName = null;
        currentLogo = null;
        currentGroup = null;
        currentDuration = null;
        currentAttributes = {};
      }
    }

    // Sort categories alphabetically
    final sortedCategories = categories.toList()..sort();

    return IptvParseResult(
      channels: channels,
      categories: sortedCategories,
    );
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
