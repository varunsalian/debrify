import 'dart:collection';

import '../models/stream_badge_rules.dart';

/// Evaluates the enabled badge rules of one or more rulesets against a
/// stream's name and description.
///
/// A rule fires when its pattern matches the name OR the description (the
/// Nuvio Badge Studio semantics). Results are memoised per (name,
/// description) pair in a small LRU, since source lists rebuild often and
/// the same stream text recurs across rebuilds.
class StreamBadgeMatcher {
  StreamBadgeMatcher(List<StreamBadgeRuleset> rulesets)
    : rules = [
        for (final set in rulesets)
          for (final r in set.rules)
            if (r.enabled && r.regex != null) r,
      ];

  static final StreamBadgeMatcher empty = StreamBadgeMatcher(const []);

  /// Enabled, compilable rules in ruleset order.
  final List<StreamBadgeRule> rules;

  bool get isEmpty => rules.isEmpty;

  static const int _cacheMax = 400;
  final LinkedHashMap<String, List<StreamBadgeRule>> _cache = LinkedHashMap();

  /// Rules that match [name] or [description], in ruleset order. The list is
  /// shared across calls with the same inputs; do not mutate it.
  List<StreamBadgeRule> matchesFor({
    required String name,
    String? description,
  }) {
    if (rules.isEmpty) return const [];
    // NUL cannot occur in either half, so the key is unambiguous.
    final key = '$name\u0000${description ?? ''}';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final out = <StreamBadgeRule>[
      for (final r in rules)
        if (r.matches(name) ||
            (description != null &&
                description.isNotEmpty &&
                r.matches(description)))
          r,
    ];
    _cache[key] = out;
    if (_cache.length > _cacheMax) _cache.remove(_cache.keys.first);
    return out;
  }
}
