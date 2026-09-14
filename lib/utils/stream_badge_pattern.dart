/// Compile a badges.json pattern. Leading global `i`, `s`, and `m` flags
/// become Dart RegExp options, including combined and repeated flag groups.
/// Dart does not accept these global prefixes; anything it otherwise rejects
/// yields null rather than an exception, so one bad rule never breaks a
/// ruleset.
RegExp? compileBadgePattern(String pattern) {
  var source = pattern.trim();
  var caseSensitive = true;
  var dotAll = false;
  var multiLine = false;
  final leadingFlags = RegExp(r'^\(\?([ism]+)\)');
  while (true) {
    final match = leadingFlags.firstMatch(source);
    if (match == null) break;
    final flags = match.group(1)!;
    if (flags.contains('i')) caseSensitive = false;
    if (flags.contains('s')) dotAll = true;
    if (flags.contains('m')) multiLine = true;
    source = source.substring(match.end);
  }
  if (source.isEmpty) return null;
  try {
    return RegExp(
      source,
      caseSensitive: caseSensitive,
      dotAll: dotAll,
      multiLine: multiLine,
    );
  } catch (_) {
    return null;
  }
}
