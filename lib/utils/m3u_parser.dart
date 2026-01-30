import '../models/iptv_playlist.dart';

/// Parser for M3U/M3U8 playlist files
class M3uParser {
  /// Parse M3U content into a list of channels
  static IptvParseResult parse(String content) {
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
          // Only add if URL looks valid
          if (url.startsWith('http://') ||
              url.startsWith('https://') ||
              url.startsWith('rtmp://') ||
              url.startsWith('rtsp://')) {
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
    var content = line.substring(8);

    // Find the comma that separates attributes from name
    final commaIndex = content.lastIndexOf(',');
    if (commaIndex != -1) {
      name = content.substring(commaIndex + 1).trim();
      content = content.substring(0, commaIndex);
    }

    // Parse duration (first part before space or attributes)
    final durationMatch = RegExp(r'^(-?\d+)').firstMatch(content);
    if (durationMatch != null) {
      duration = int.tryParse(durationMatch.group(1) ?? '');
    }

    // Parse attributes (key="value" or key='value')
    final attrRegex = RegExp(r'''(\S+?)=["']([^"']*)["']''');
    for (final match in attrRegex.allMatches(content)) {
      final key = match.group(1)?.toLowerCase();
      final value = match.group(2);
      if (key != null && value != null) {
        attributes[key] = value;
      }
    }

    return _ExtInfResult(
      name: name ?? 'Unknown Channel',
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
