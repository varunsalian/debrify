import 'dart:io';

class SubtitleCue {
  final int startMs;
  final int endMs;
  final String text;

  const SubtitleCue({
    required this.startMs,
    required this.endMs,
    required this.text,
  });
}

class SubtitleCueParser {
  static Future<List<SubtitleCue>> parseFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return [];

    final bytes = await file.readAsBytes();

    final content = String.fromCharCodes(bytes);

    final lower = filePath.toLowerCase();
    if (lower.endsWith('.srt')) {
      return _parseSrt(content);
    } else if (lower.endsWith('.vtt')) {
      return _parseVtt(content);
    } else if (lower.endsWith('.ass') || lower.endsWith('.ssa')) {
      return _parseAss(content);
    }
    return _parseSrt(content);
  }

  static List<SubtitleCue> _parseSrt(String content) {
    final cues = <SubtitleCue>[];
    final blocks = content
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 2) continue;

      // Find the timing line (contains " --> ")
      int timingIdx = -1;
      for (int i = 0; i < lines.length && i < 3; i++) {
        if (lines[i].contains('-->')) {
          timingIdx = i;
          break;
        }
      }
      if (timingIdx < 0) continue;

      final timing = lines[timingIdx];
      final parts = timing.split('-->');
      if (parts.length != 2) continue;

      final startMs = _parseTimestamp(parts[0].trim());
      final endMs = _parseTimestamp(parts[1].trim());
      if (startMs < 0 || endMs < 0) continue;

      final text = lines
          .sublist(timingIdx + 1)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'\{[^}]+\}'), '')
          .trim();
      if (text.isEmpty) continue;

      cues.add(SubtitleCue(startMs: startMs, endMs: endMs, text: text));
    }

    cues.sort((a, b) => a.startMs.compareTo(b.startMs));
    return cues;
  }

  static List<SubtitleCue> _parseVtt(String content) {
    final cues = <SubtitleCue>[];
    final normalized = content.replaceAll('\r\n', '\n');

    // Skip the WEBVTT header
    final headerEnd = normalized.indexOf('\n\n');
    final body = headerEnd >= 0 ? normalized.substring(headerEnd + 2) : normalized;

    final blocks = body.split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.isEmpty) continue;

      int timingIdx = -1;
      for (int i = 0; i < lines.length && i < 3; i++) {
        if (lines[i].contains('-->')) {
          timingIdx = i;
          break;
        }
      }
      if (timingIdx < 0) continue;

      final timing = lines[timingIdx].split('-->');
      if (timing.length != 2) continue;

      // VTT timestamps may omit hours
      final startMs = _parseTimestamp(timing[0].trim());
      final endMs = _parseTimestamp(timing[1].trim());
      if (startMs < 0 || endMs < 0) continue;

      final text = lines
          .sublist(timingIdx + 1)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .trim();
      if (text.isEmpty) continue;

      cues.add(SubtitleCue(startMs: startMs, endMs: endMs, text: text));
    }

    cues.sort((a, b) => a.startMs.compareTo(b.startMs));
    return cues;
  }

  static List<SubtitleCue> _parseAss(String content) {
    final cues = <SubtitleCue>[];
    final lines = content.replaceAll('\r\n', '\n').split('\n');

    // Find [Events] section and parse Format line
    bool inEvents = false;
    int textFieldIndex = -1;
    int startFieldIndex = -1;
    int endFieldIndex = -1;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.toLowerCase() == '[events]') {
        inEvents = true;
        continue;
      }
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        inEvents = false;
        continue;
      }

      if (!inEvents) continue;

      if (trimmed.toLowerCase().startsWith('format:')) {
        final fields = trimmed
            .substring(7)
            .split(',')
            .map((f) => f.trim().toLowerCase())
            .toList();
        startFieldIndex = fields.indexOf('start');
        endFieldIndex = fields.indexOf('end');
        textFieldIndex = fields.indexOf('text');
        continue;
      }

      if (!trimmed.toLowerCase().startsWith('dialogue:')) continue;
      if (textFieldIndex < 0 || startFieldIndex < 0 || endFieldIndex < 0) continue;

      final afterDialogue = trimmed.substring(trimmed.indexOf(':') + 1);
      // Split only up to textFieldIndex commas — text field may contain commas
      final parts = <String>[];
      int fieldStart = 0;
      int commaCount = 0;
      for (int i = 0; i < afterDialogue.length; i++) {
        if (afterDialogue[i] == ',' && commaCount < textFieldIndex) {
          parts.add(afterDialogue.substring(fieldStart, i).trim());
          fieldStart = i + 1;
          commaCount++;
        }
      }
      parts.add(afterDialogue.substring(fieldStart).trim());

      if (parts.length <= textFieldIndex) continue;

      final startMs = _parseAssTimestamp(parts[startFieldIndex]);
      final endMs = _parseAssTimestamp(parts[endFieldIndex]);
      if (startMs < 0 || endMs < 0) continue;

      var text = parts[textFieldIndex];
      // Strip ASS override tags like {\an8}, {\pos(x,y)}, etc.
      text = text.replaceAll(RegExp(r'\{[^}]*\}'), '');
      // Replace \N and \n with newline
      text = text.replaceAll(r'\N', '\n').replaceAll(r'\n', '\n');
      text = text.trim();
      if (text.isEmpty) continue;

      cues.add(SubtitleCue(startMs: startMs, endMs: endMs, text: text));
    }

    cues.sort((a, b) => a.startMs.compareTo(b.startMs));
    return cues;
  }

  /// Parse SRT/VTT timestamp: "HH:MM:SS,mmm" or "HH:MM:SS.mmm" or "MM:SS.mmm"
  static int _parseTimestamp(String ts) {
    // Strip position info after timestamp (VTT allows "00:00:00.000 position:...")
    final cleaned = ts.split(' ').first.replaceAll(',', '.');
    final parts = cleaned.split(':');

    try {
      if (parts.length == 3) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final secParts = parts[2].split('.');
        final s = int.parse(secParts[0]);
        final ms = secParts.length > 1
            ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
            : 0;
        return h * 3600000 + m * 60000 + s * 1000 + ms;
      } else if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final secParts = parts[1].split('.');
        final s = int.parse(secParts[0]);
        final ms = secParts.length > 1
            ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
            : 0;
        return m * 60000 + s * 1000 + ms;
      }
    } catch (_) {}
    return -1;
  }

  /// Parse ASS timestamp: "H:MM:SS.cc" (centiseconds)
  static int _parseAssTimestamp(String ts) {
    final parts = ts.trim().split(':');
    if (parts.length != 3) return -1;
    try {
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final secParts = parts[2].split('.');
      final s = int.parse(secParts[0]);
      final cs = secParts.length > 1 ? int.parse(secParts[1].padRight(2, '0').substring(0, 2)) : 0;
      return h * 3600000 + m * 60000 + s * 1000 + cs * 10;
    } catch (_) {
      return -1;
    }
  }
}
