import 'dart:convert';
import 'dart:ui' show Color;

/// A Nuvio-compatible stream badge ruleset (`badges.json`): regex rules that
/// decorate a stream entry with small labelled chips — provider, release
/// format, resolution, HDR, audio codec, language.
///
/// The file shape is `{ "groups": [...], "filters": [...] }`. A rule matches
/// when its pattern hits the stream's name or its description; a leading
/// `(?i)` selects case-insensitive matching, as the Nuvio Badge Studio does.
/// Invalid patterns are kept in the ruleset (so they round-trip) but never
/// match.
class StreamBadgeRuleset {
  final List<StreamBadgeGroup> groups;
  final List<StreamBadgeRule> rules;

  const StreamBadgeRuleset({required this.groups, required this.rules});

  static const StreamBadgeRuleset empty = StreamBadgeRuleset(
    groups: [],
    rules: [],
  );

  int get enabledCount => rules.where((r) => r.enabled).length;

  /// Rules whose pattern failed to compile (reported on import).
  List<StreamBadgeRule> get invalidRules =>
      rules.where((r) => r.regex == null).toList();

  /// Parse a `badges.json` document. Throws [FormatException] with a
  /// user-readable message when the text is not JSON or has no rules.
  static StreamBadgeRuleset parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      throw const FormatException('The file is not valid JSON.');
    }
    return fromJson(decoded);
  }

  /// [parse], with null instead of an exception for an unreadable document.
  static StreamBadgeRuleset? tryParse(String jsonText) {
    try {
      return parse(jsonText);
    } catch (_) {
      return null;
    }
  }

  static StreamBadgeRuleset fromJson(Object? decoded) {
    Object? root = decoded;
    if (root is Map && root['badges'] is Map) root = root['badges'];
    if (root is! Map) {
      throw const FormatException(
        'Expected a badges file with "groups" and "filters".',
      );
    }
    final rawGroups = root['groups'];
    final rawRules = root['filters'] ?? root['rules'] ?? root['badges'];
    final groups = <StreamBadgeGroup>[
      if (rawGroups is List)
        for (final g in rawGroups)
          if (StreamBadgeGroup.fromJson(g) case final group?) group,
    ];
    final rules = <StreamBadgeRule>[
      if (rawRules is List)
        for (final r in rawRules)
          if (StreamBadgeRule.fromJson(r) case final rule?) rule,
    ];
    if (rules.isEmpty) {
      throw const FormatException('The file contains no badge rules.');
    }
    return StreamBadgeRuleset(groups: groups, rules: rules);
  }

  Map<String, dynamic> toJson() => {
    'groups': [for (final g in groups) g.toJson()],
    'filters': [for (final r in rules) r.toJson()],
  };
}

class StreamBadgeGroup {
  final String id;
  final String name;
  final Color? color;

  const StreamBadgeGroup({required this.id, required this.name, this.color});

  static StreamBadgeGroup? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _str(json['id']);
    if (id == null) return null;
    return StreamBadgeGroup(
      id: id,
      name: _str(json['name']) ?? id,
      color: parseBadgeColor(json['color']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (color != null) 'color': encodeBadgeColor(color!),
    'isExpanded': true,
  };
}

enum StreamBadgeStyle {
  filled,
  outlined,
  filledBordered;

  static StreamBadgeStyle parse(Object? raw) {
    final s = (raw is String ? raw : '').trim().toLowerCase();
    if (s.contains('outlined')) return StreamBadgeStyle.outlined;
    if (s.contains('border')) return StreamBadgeStyle.filledBordered;
    return StreamBadgeStyle.filled;
  }

  String get storageValue => switch (this) {
    StreamBadgeStyle.filled => 'filled',
    StreamBadgeStyle.outlined => 'outlined',
    StreamBadgeStyle.filledBordered => 'filled and bordered',
  };

  bool get fills => this != StreamBadgeStyle.outlined;
  bool get borders => this != StreamBadgeStyle.filled;
}

class StreamBadgeRule {
  final String id;
  final String groupId;
  final String name;
  final String pattern;
  final bool enabled;
  final String? imageUrl;
  final Color? tagColor;
  final Color? textColor;
  final Color? borderColor;
  final StreamBadgeStyle style;

  /// Compiled [pattern], or null when it isn't a valid regular expression.
  final RegExp? regex;

  StreamBadgeRule({
    required this.id,
    required this.groupId,
    required this.name,
    required this.pattern,
    this.enabled = true,
    this.imageUrl,
    this.tagColor,
    this.textColor,
    this.borderColor,
    this.style = StreamBadgeStyle.filled,
  }) : regex = compileBadgePattern(pattern);

  bool matches(String text) => regex?.hasMatch(text) ?? false;

  static StreamBadgeRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final pattern = _str(json['pattern']) ?? _str(json['regex']);
    final name = _str(json['name']) ?? _str(json['label']);
    if (pattern == null || name == null) return null;
    final type = _str(json['type']);
    if (type != null && type != 'filter') return null;
    return StreamBadgeRule(
      id: _str(json['id']) ?? name,
      groupId: _str(json['groupId']) ?? '',
      name: name,
      pattern: pattern,
      enabled: json['isEnabled'] != false && json['enabled'] != false,
      imageUrl: _str(json['imageURL']) ?? _str(json['imageUrl']),
      tagColor: parseBadgeColor(json['tagColor']),
      textColor: parseBadgeColor(json['textColor']),
      borderColor: parseBadgeColor(json['borderColor']),
      style: StreamBadgeStyle.parse(json['tagStyle']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'name': name,
    'pattern': pattern,
    'type': 'filter',
    'isEnabled': enabled,
    if (imageUrl != null) 'imageURL': imageUrl,
    if (tagColor != null) 'tagColor': encodeBadgeColor(tagColor!),
    'tagStyle': style.storageValue,
    if (textColor != null) 'textColor': encodeBadgeColor(textColor!),
    if (borderColor != null) 'borderColor': encodeBadgeColor(borderColor!),
  };
}

/// Compile a badges.json pattern. A leading `(?i)` becomes case-insensitive
/// matching (Dart's RegExp has no inline flags); anything Dart rejects
/// yields null rather than an exception, so one bad rule never breaks a
/// ruleset.
RegExp? compileBadgePattern(String pattern) {
  var source = pattern.trim();
  var caseSensitive = true;
  while (source.startsWith('(?i)')) {
    caseSensitive = false;
    source = source.substring(4);
  }
  if (source.isEmpty) return null;
  try {
    return RegExp(source, caseSensitive: caseSensitive);
  } catch (_) {
    return null;
  }
}

/// `#RRGGBB` or `#AARRGGBB` (Nuvio's Android-style ARGB). Null for anything
/// else, including the fully transparent placeholders some presets use.
Color? parseBadgeColor(Object? raw) {
  if (raw is! String) return null;
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  if ((value >> 24) & 0xFF == 0) return null;
  return Color(value);
}

String encodeBadgeColor(Color c) {
  final v = c.toARGB32();
  return '#${v.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
