import 'dart:convert';
import 'dart:io';

List<Map<String, String>> mergedManifest() {
  final lines = File('dev/tool/merged_detail_manifest.tsv').readAsLinesSync();
  final header = lines.first.split('\t');
  return [
    for (final line in lines.skip(1))
      Map.fromIterables(header, line.split('\t')),
  ];
}

String mergedMemberPath(String original) {
  final row = mergedManifest().singleWhere(
    (r) => r['original_name'] == original,
  );
  return File(row['destination_file']!).existsSync()
      ? row['destination_file']!
      : 'lib/screens/merged_series_detail_screen.dart';
}

/// Read the one declaration selected by the manifest, retaining its doc text.
String mergedOriginalMember(String original) {
  final rows = mergedManifest();
  final row = rows.singleWhere((r) => r['original_name'] == original);
  final path = mergedMemberPath(original);
  final moved =
      path == row['destination_file'] &&
      path != 'lib/screens/merged_series_detail_screen.dart';
  final name = moved ? row['new_name']! : original.split('.').last;
  final owner = moved ? row['destination_class']! : original.split('.').first;
  final text = File(path).readAsStringSync();
  final startOwner = RegExp(
    '^class ${RegExp.escape(owner)}\\b',
    multiLine: true,
  ).firstMatch(text);
  if (startOwner == null) {
    throw StateError('Missing owner $path::$owner');
  }
  final ownerTail = text.substring(startOwner.start);
  final endOwner = RegExp(r'^}', multiLine: true).firstMatch(ownerTail);
  if (endOwner == null) {
    throw StateError('Missing owner end');
  }
  final source = ownerTail.substring(0, endOwner.end);
  final start = RegExp(
    r'^  [A-Za-z][\w<>?, ]*\s+' + RegExp.escape(name) + r'\s*\(',
    multiLine: true,
  ).firstMatch(source);
  if (start == null) {
    throw StateError('Missing method $path::$name');
  }
  final arrowEnd = source.indexOf(';', start.end);
  final end = RegExp(
    r'^  }\s*$',
    multiLine: true,
  ).firstMatch(source.substring(start.end));
  if (end == null) {
    throw StateError('Missing method end $path::$name');
  }
  var first = start.start;
  while (first > 0) {
    final previousEnd = first - 1;
    final previousStart = source.lastIndexOf('\n', previousEnd - 1) + 1;
    final line = source.substring(previousStart, previousEnd).trim();
    if (!line.startsWith('///') && line != '@override') {
      break;
    }
    first = previousStart;
  }
  final header = source.substring(start.start, source.indexOf('\n', start.end));
  final finish = header.contains('=>') ? arrowEnd + 1 : start.end + end.end;
  final member = source.substring(first, finish);
  return mergedOriginalNames(member, owner: owner);
}

String mergedOriginalNames(String member, {String? owner}) {
  final config =
      jsonDecode(
            File(
              'dev/tool/merged_detail_checker_config.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final rows = mergedManifest();
  final paths = config['receiver_paths'] as Map<String, dynamic>? ?? const {};
  String rewrite(String code) {
    code = code.replaceAll('_deps.setState', 'setState');
    for (final receiver in ['_deps', 'deps']) {
      for (final name in ['mounted', 'context']) {
        code = code.replaceAll('$receiver.$name()', name);
      }
    }
    for (final getter in config['live_getter_callbacks'] as List<dynamic>) {
      code = code.replaceAll('_deps.$getter()', '$getter');
    }
    for (final getter in config['live_widget_getters'] as List<dynamic>) {
      code = code.replaceAll('_deps.$getter()', 'widget.$getter');
    }
    for (final row in rows) {
      final original = row['original_name']!.split('.').last;
      final current = row['new_name']!;
      final receivers = [
        ...paths.entries
            .where((p) => p.value == row['destination_class'])
            .map((p) => p.key),
        ...config['receivers'] as List<dynamic>,
      ];
      for (final receiver in receivers) {
        code = code.replaceAll(
          RegExp(
            r'\b' +
                receiver
                    .toString()
                    .split('.')
                    .map(RegExp.escape)
                    .join(r'\s*\.\s*') +
                r'\s*\.\s*' +
                RegExp.escape(current) +
                r'\b',
          ),
          original,
        );
      }
      // Only declaration names are unqualified after a move. Values always
      // use their actual owner's receiver, keeping same-named locals intact.
      if (original != current &&
          (owner == null || owner == row['destination_class'])) {
        code = code.replaceAllMapped(
          RegExp(
            r'(^[ \t]+[A-Za-z_][\w<>?, ]*\s+)' +
                RegExp.escape(current) +
                r'(?=\s*(?:\(|=>|[;=]))',
            multiLine: true,
          ),
          (m) => '${m[1]}$original',
        );
      }
    }
    for (final alias in config['type_aliases'] as List<dynamic>? ?? const []) {
      code = code.replaceAll(
        RegExp(r'\b' + RegExp.escape(alias['alias'] as String) + r'\b'),
        alias['original_name'] as String,
      );
    }
    return code;
  }

  return _MergedSourceMapper(rewrite).map(member);
}

/// Preserve comments and literal text; rewrite only Dart code/interpolations.
class _MergedSourceMapper {
  final String Function(String) rewrite;
  final bool canonical;
  _MergedSourceMapper(this.rewrite, {this.canonical = false});

  (String, int, bool)? quote(String s, int i) {
    final raw =
        s[i] == 'r' && i + 1 < s.length && (s[i + 1] == "'" || s[i + 1] == '"');
    final j = i + (raw ? 1 : 0);
    if (s[j] != "'" && s[j] != '"') {
      return null;
    }
    final single = s[j];
    final delimiter = s.startsWith(single * 3, j) ? single * 3 : single;
    return (delimiter, j + delimiter.length, raw);
  }

  int commentEnd(String s, int i) {
    if (s.startsWith('//', i)) {
      final end = s.indexOf('\n', i);
      return end < 0 ? s.length : end;
    }
    var depth = 1;
    var j = i + 2;
    while (j < s.length && depth > 0) {
      if (s.startsWith('/*', j)) {
        depth++;
        j += 2;
      } else if (s.startsWith('*/', j)) {
        depth--;
        j += 2;
      } else {
        j++;
      }
    }
    if (depth != 0) {
      throw StateError('Unclosed source comment');
    }
    return j;
  }

  int braceEnd(String s, int i) {
    var depth = 1;
    var j = i + 1;
    while (j < s.length && depth > 0) {
      if (s.startsWith('//', j) || s.startsWith('/*', j)) {
        j = commentEnd(s, j);
      } else if (quote(s, j) != null) {
        j = stringEnd(s, j);
      } else {
        if (s[j] == '{') {
          depth++;
        }
        if (s[j] == '}') {
          depth--;
        }
        j++;
      }
    }
    if (depth != 0) {
      throw StateError('Unclosed source interpolation');
    }
    return j;
  }

  int stringEnd(String s, int i) {
    final q = quote(s, i)!;
    var j = q.$2;
    while (j < s.length) {
      if (s.startsWith(q.$1, j)) {
        return j + q.$1.length;
      }
      if (!q.$3 && s[j] == r'\') {
        j += 2;
      } else if (!q.$3 && s.startsWith(r'${', j)) {
        j = braceEnd(s, j + 1);
      } else {
        j++;
      }
    }
    throw StateError('Unclosed source literal');
  }

  String literal(String s, int i, int end) {
    final q = quote(s, i)!;
    if (q.$3) {
      return s.substring(i, end);
    }
    final out = StringBuffer(s.substring(i, q.$2));
    var j = q.$2;
    final stop = end - q.$1.length;
    while (j < stop) {
      if (s[j] == r'\') {
        out.write(s.substring(j, j + 2));
        j += 2;
      } else if (s.startsWith(r'${', j)) {
        final finish = braceEnd(s, j + 1);
        final value = map(s.substring(j + 2, finish - 1));
        out.write(canonical ? '\u0000{$value}\u0000' : '\${$value}');
        j = finish;
      } else if (s[j] == r'$') {
        final name = RegExp(r'^[A-Za-z_]\w*').firstMatch(s.substring(j + 1));
        if (name == null) {
          out.write(s[j++]);
          continue;
        }
        final value = rewrite(name[0]!);
        out.write(
          canonical
              ? '\u0000{$value}\u0000'
              : (RegExp(r'^[A-Za-z_]\w*$').hasMatch(value)
                    ? r'$' + value
                    : '\${$value}'),
        );
        j += name[0]!.length + 1;
      } else {
        out.write(s[j++]);
      }
    }
    out.write(q.$1);
    return out.toString();
  }

  String map(String s) {
    final out = StringBuffer();
    var i = 0;
    var start = 0;
    while (i < s.length) {
      final comment = s.startsWith('//', i) || s.startsWith('/*', i);
      final quoted = quote(s, i) != null;
      if (!comment && !quoted) {
        i++;
        continue;
      }
      out.write(rewrite(s.substring(start, i)));
      final end = comment ? commentEnd(s, i) : stringEnd(s, i);
      out.write(
        comment
            ? (canonical ? rewrite(s.substring(i, end)) : s.substring(i, end))
            : literal(s, i, end),
      );
      start = i = end;
    }
    out.write(rewrite(s.substring(start)));
    return out.toString();
  }
}

/// Ignore code formatting while retaining every character of literal text.
/// NUL delimiters canonicalize simple/braced interpolations without ambiguity
/// between `${name}Suffix` and `$nameSuffix`. Comments retain their tokens.
String mergedCanonicalSource(String source) => _MergedSourceMapper(
  (code) => code
      .replaceAllMapped(RegExp(r',\s*([)\]}])'), (m) => m[1]!)
      .replaceAll(RegExp(r'\s+'), ''),
  canonical: true,
).map(source);
