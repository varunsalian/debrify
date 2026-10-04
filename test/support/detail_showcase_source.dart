import 'dart:convert';
import 'dart:io';

const showcaseFacade = 'lib/widgets/detail/showcase_parts.dart';
const showcaseFeature = 'lib/features/detail_showcase/presentation';

List<Map<String, String>> showcaseManifest() {
  final lines = File('dev/tool/detail_showcase_manifest.tsv').readAsLinesSync();
  final header = lines.first.split('\t');
  return [
    for (final line in lines.skip(1))
      Map.fromIterables(header, line.split('\t')),
  ];
}

bool get showcaseComplete => RegExp(
  r'DETAIL_SHOWCASE_COMPLETE\s*=\s*True',
).hasMatch(File('dev/tool/check_search_architecture.py').readAsStringSync());

String? _declaration(String source, String name) {
  final escaped = RegExp.escape(name);
  final start = RegExp(
    '^(?:class $escaped\\b|(?:const(?: \\w+)?|[A-Za-z_][\\w<>?]*) $escaped\\s*(?:\\(|=))',
    multiLine: true,
  ).firstMatch(source);
  if (start == null) {
    return null;
  }
  var first = start.start;
  while (first > 0) {
    final end = first - 1;
    final begin = source.lastIndexOf('\n', end - 1) + 1;
    if (!source.substring(begin, end).trim().startsWith('///')) {
      break;
    }
    first = begin;
  }
  final tail = source.substring(start.start);
  final end =
      tail.startsWith('class ') ||
          (tail.substring(0, tail.indexOf('\n')).contains('{') &&
              !tail.substring(0, tail.indexOf('\n')).contains('=>'))
      ? RegExp(r'^}', multiLine: true).firstMatch(tail)?.end
      : tail.indexOf(';') + 1;
  if (end == null || end <= 0) {
    throw StateError('Missing declaration end: $name');
  }
  return source.substring(first, start.start + end);
}

String showcaseOriginalNames(String source) {
  final config =
      jsonDecode(
            File(
              'dev/tool/detail_showcase_checker_config.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final aliases = config['file_aliases'] as List<dynamic>? ?? [];
  return _ShowcaseSourceMapper((code, _) {
    for (final alias in aliases) {
      code = code.replaceAll(
        RegExp('\\b${RegExp.escape(alias['alias'] as String)}\\b'),
        alias['original_name'] as String,
      );
    }
    return code;
  }).map(source);
}

/// Select exactly one physical declaration; a missing or duplicated leaf fails.
String showcaseDeclaration(String name) {
  final row = showcaseManifest().singleWhere((r) => r['original_name'] == name);
  final paths = {showcaseFacade, row['destination_file']!};
  final found = <String>[];
  for (final path in paths) {
    final file = File(path);
    if (file.existsSync()) {
      final declaration = _declaration(
        file.readAsStringSync(),
        row['new_name']!,
      );
      if (declaration != null) {
        found.add(declaration);
      }
    }
  }
  if (found.length != 1) {
    throw StateError('$name has ${found.length} physical declarations');
  }
  return showcaseOriginalNames(found.single);
}

String showcaseSource() => showcaseManifest()
    .map((r) => showcaseDeclaration(r['original_name']!))
    .join('\n\n');

/// Unconditional feature scan, also valid before the directory is created.
Map<String, String> showcasePhysicalFiles() => {
  showcaseFacade: File(showcaseFacade).readAsStringSync(),
  ...{
    for (final f
        in Directory(showcaseFeature).existsSync()
            ? Directory(
                showcaseFeature,
              ).listSync(recursive: true).whereType<File>()
            : <File>[])
      if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
  },
};

/// Preserve comments and literal text; rewrite only Dart code/interpolations.
class _ShowcaseSourceMapper {
  final String Function(String, String) rewrite;
  _ShowcaseSourceMapper(this.rewrite);

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
        out.write('\${$value}');
        j = finish;
      } else if (s[j] == r'$') {
        final name = RegExp(r'^[A-Za-z_]\w*').firstMatch(s.substring(j + 1));
        if (name == null) {
          out.write(s[j++]);
          continue;
        }
        final value = rewrite(name[0]!, '');
        out.write(
          RegExp(r'^[A-Za-z_]\w*$').hasMatch(value)
              ? r'$' + value
              : '\${$value}',
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
      out.write(comment ? s.substring(i, end) : literal(s, i, end));
      if (!comment) previousCode += 'literal';
      start = i = end;
    }
    out.write(rewrite(s.substring(start), previousCode));
    return out.toString();
  }
}
