import 'dart:convert';
import 'dart:io';

List<Map<String, String>> catalogManifest() {
  final lines = File('dev/tool/catalog_detail_manifest.tsv').readAsLinesSync();
  final header = lines.first.split('\t');
  return [
    for (final line in lines.skip(1))
      Map.fromIterables(header, line.split('\t')),
  ];
}

String catalogMemberPath(String original) {
  final row = catalogManifest().singleWhere(
    (r) => r['original_name'] == original,
  );
  final destination = File(row['destination_file']!);
  if (destination.existsSync() &&
      RegExp(
        r'^  [A-Za-z_][\w<>?, ]*\s+' +
            RegExp.escape(row['new_name']!) +
            r'\s*(?:\(|=>|=|;)',
        multiLine: true,
      ).hasMatch(destination.readAsStringSync())) {
    return row['destination_file']!;
  }
  return 'lib/screens/catalog_item_detail_screen.dart';
}

String catalogDetailSource() => catalogManifest()
    .where(
      (row) =>
          row['original_name']!.startsWith('_CatalogItemDetailScreenState.'),
    )
    .map((row) => catalogOriginalMember(row['original_name']!))
    .join('\n');

/// Read the one declaration selected by the manifest, retaining its doc text.
String catalogOriginalMember(String original) {
  final rows = catalogManifest();
  final row = rows.singleWhere((r) => r['original_name'] == original);
  final path = catalogMemberPath(original);
  final moved =
      path == row['destination_file'] &&
      path != 'lib/screens/catalog_item_detail_screen.dart';
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
    r'^  (?:late\s+)?(?:final\s+)?[A-Za-z][\w<>?, ]*\s+(?:get\s+)?' +
        RegExp.escape(name) +
        r'\s*(?:\(|=>|=|;)',
    multiLine: true,
  ).firstMatch(source);
  if (start == null) throw StateError('Missing member $path::$name');
  final remainder = source.substring(start.start);
  final close = RegExp(r'^  }\s*$', multiLine: true).firstMatch(remainder);
  final next = RegExp(
    r'^  (?:@override|(?:late\s+)?(?:final\s+)?[A-Za-z][\w<>?, ]*\s+(?:get\s+)?[A-Za-z_]\w*\s*(?:\(|=>|=|;))',
    multiLine: true,
  ).allMatches(remainder).skip(1).firstOrNull;
  final arrow = remainder.indexOf('=>');
  final brace = remainder.indexOf('{');
  final block =
      close != null &&
      (next == null || close.start < next.start) &&
      brace >= 0 &&
      (arrow < 0 || brace < arrow);
  final finish = start.start + (block ? close.end : remainder.indexOf(';') + 1);
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
  var member = source.substring(first, finish);
  if (moved && row['allowed_edits']!.split(',').contains('layout_body')) {
    final facade = File(
      'lib/screens/catalog_item_detail_screen.dart',
    ).readAsStringSync();
    final originalName = original.split('.').last;
    final annotation = RegExp(
      r'^  (@override\s*\n)  [A-Za-z][\w<>?, ]*\s+' +
          RegExp.escape(originalName) +
          r'\s*\(',
      multiLine: true,
    ).firstMatch(facade);
    if (annotation == null) {
      throw StateError('Missing facade override $original');
    }
    member = '${annotation[1]}$member';
  }
  return catalogOriginalNames(member, owner: owner);
}

String catalogOriginalNames(String member, {String? owner}) {
  final config =
      jsonDecode(
            File(
              'dev/tool/catalog_detail_checker_config.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final rows = catalogManifest();
  final paths = config['receiver_paths'] as Map<String, dynamic>? ?? const {};
  String rewrite(String code, String previousCode) {
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
      if (!code.contains(current)) {
        continue;
      }
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
      if (original.startsWith('_') &&
          original != current &&
          (owner == null || owner == row['destination_class'])) {
        // An implicit read of this owner's member keeps the compiler's local
        // binding. Named-argument labels and qualified external reads stay exact.
        final beforeRename = code;
        code = code.replaceAllMapped(
          RegExp(r'\b' + RegExp.escape(current) + r'\b'),
          (match) {
            final prefix =
                (previousCode + beforeRename.substring(0, match.start))
                    .trimRight();
            final suffix = beforeRename.substring(match.end).trimLeft();
            final external = prefix.endsWith('.') && !prefix.endsWith('...');
            final namedLabel =
                suffix.startsWith(':') &&
                (prefix.endsWith('(') || prefix.endsWith(','));
            return external || namedLabel ? match[0]! : original;
          },
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

  return _CatalogSourceMapper(rewrite).map(member);
}

/// Preserve comments and literal text; rewrite only Dart code/interpolations.
class _CatalogSourceMapper {
  final String Function(String, String) rewrite;
  final bool canonical;
  _CatalogSourceMapper(this.rewrite, {this.canonical = false});

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
        final value = rewrite(name[0]!, '');
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
    var previousCode = '';
    while (i < s.length) {
      final comment = s.startsWith('//', i) || s.startsWith('/*', i);
      final quoted = quote(s, i) != null;
      if (!comment && !quoted) {
        i++;
        continue;
      }
      final code = s.substring(start, i);
      out.write(rewrite(code, previousCode));
      previousCode += code;
      final end = comment ? commentEnd(s, i) : stringEnd(s, i);
      out.write(
        comment
            ? (canonical
                  ? rewrite(s.substring(i, end), previousCode)
                  : s.substring(i, end))
            : literal(s, i, end),
      );
      if (!comment) previousCode += 'literal';
      start = i = end;
    }
    out.write(rewrite(s.substring(start), previousCode));
    return out.toString();
  }
}

/// Ignore code formatting while retaining every character of literal text.
/// NUL delimiters canonicalize simple/braced interpolations without ambiguity
/// between `${name}Suffix` and `$nameSuffix`. Comments retain their tokens.
String catalogCanonicalSource(String source) => _CatalogSourceMapper(
  (code, _) => code
      .replaceAllMapped(RegExp(r',\s*([)\]}])'), (m) => m[1]!)
      .replaceAll(RegExp(r'\s+'), ''),
  canonical: true,
).map(source);

// Bound to the main State declaration and its owning lifecycle method. Only
// whitespace and one optional formatter comma are accepted at the call site.
bool catalogCompletionListenerSite(
  String source,
  String declaration,
  String notifier,
  String operation,
) {
  final stateStart = source.indexOf('class _CatalogItemDetailScreenState ');
  if (stateStart < 0) return false;
  final tail = source.substring(stateStart);
  final stateEnd = RegExp(r'^}', multiLine: true).firstMatch(tail);
  if (stateEnd == null) return false;
  final state = tail.substring(0, stateEnd.end);
  final start = RegExp(
    r'^  void ' + RegExp.escape(declaration) + r'\(\)\s*\{',
    multiLine: true,
  ).firstMatch(state);
  if (start == null) return false;
  final end = RegExp(
    r'^  }',
    multiLine: true,
  ).firstMatch(state.substring(start.end));
  if (end == null) return false;
  final body = state.substring(start.start, start.end + end.end);
  final expression = notifier.split('.').map(RegExp.escape).join(r'\s*\.\s*');
  return RegExp(
    r'^\s*' +
        expression +
        r'\s*\.\s*' +
        RegExp.escape(operation) +
        r'\s*\(\s*_loadLocalMovieFinished\s*,?\s*\)',
    multiLine: true,
  ).hasMatch(body);
}
