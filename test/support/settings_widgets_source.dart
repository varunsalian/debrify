import 'dart:convert';
import 'dart:io';

const settingsWidgetsFacade =
    'lib/screens/settings/widgets/settings_widgets.dart';
const settingsWidgetsFeature = 'lib/features/settings_widgets/presentation';

List<Map<String, String>> settingsWidgetsManifest() {
  final lines = File(
    'dev/tool/settings_widgets_manifest.tsv',
  ).readAsLinesSync();
  final header = lines.first.split('\t');
  return [
    for (final line in lines.skip(1))
      Map.fromIterables(header, line.split('\t')),
  ];
}

bool get settingsWidgetsComplete => RegExp(
  r'SETTINGS_WIDGETS_COMPLETE\s*=\s*True',
).hasMatch(File('dev/tool/check_search_architecture.py').readAsStringSync());

class SettingsWidgetsSpan {
  final String name;
  final int start;
  final int end;
  const SettingsWidgetsSpan(this.name, this.start, this.end);
}

class _Token {
  final String text;
  final int start;
  final int end;
  const _Token(this.text, this.start, this.end);
}

/// Lexical scanner: comments, raw/triple strings and nested interpolation are
/// skipped together, so punctuation inside them cannot end a declaration.
class _Scanner {
  final String text;
  _Scanner(this.text);

  bool quote(int i) =>
      text[i] == "'" ||
      text[i] == '"' ||
      (text[i] == 'r' &&
          i + 1 < text.length &&
          (text[i + 1] == "'" || text[i + 1] == '"'));

  int commentEnd(int i) {
    if (text.startsWith('//', i)) {
      final end = text.indexOf('\n', i);
      return end < 0 ? text.length : end;
    }
    var depth = 1;
    var j = i + 2;
    while (j < text.length && depth > 0) {
      if (text.startsWith('/*', j)) {
        depth++;
        j += 2;
      } else if (text.startsWith('*/', j)) {
        depth--;
        j += 2;
      } else {
        j++;
      }
    }
    if (depth != 0) {
      throw StateError('Unclosed comment');
    }
    return j;
  }

  int interpolationEnd(int i) {
    var depth = 1;
    var j = i + 1;
    while (j < text.length && depth > 0) {
      if (text.startsWith('//', j) || text.startsWith('/*', j)) {
        j = commentEnd(j);
      } else if (quote(j)) {
        j = stringEnd(j);
      } else {
        if (text[j] == '{') {
          depth++;
        }
        if (text[j] == '}') {
          depth--;
        }
        j++;
      }
    }
    if (depth != 0) {
      throw StateError('Unclosed interpolation');
    }
    return j;
  }

  int stringEnd(int i) {
    final raw = text[i] == 'r';
    final q = i + (raw ? 1 : 0);
    final delimiter = text.startsWith(text[q] * 3, q) ? text[q] * 3 : text[q];
    var j = q + delimiter.length;
    while (j < text.length) {
      if (text.startsWith(delimiter, j)) {
        return j + delimiter.length;
      }
      if (!raw && text[j] == r'\') {
        j += 2;
      } else if (!raw && text.startsWith(r'${', j)) {
        j = interpolationEnd(j + 1);
      } else {
        j++;
      }
    }
    throw StateError('Unclosed string');
  }

  List<_Token> tokens() {
    final result = <_Token>[];
    var i = 0;
    while (i < text.length) {
      if (RegExp(r'\s').hasMatch(text[i])) {
        i++;
      } else if (text.startsWith('//', i) || text.startsWith('/*', i)) {
        i = commentEnd(i);
      } else if (quote(i)) {
        final end = stringEnd(i);
        result.add(_Token(text.substring(i, end), i, end));
        i = end;
      } else {
        final identifier = RegExp(
          r'^[A-Za-z_$][\w$]*',
        ).firstMatch(text.substring(i));
        final end = identifier != null
            ? i + identifier[0]!.length
            : text.startsWith('=>', i)
            ? i + 2
            : i + 1;
        result.add(_Token(text.substring(i, end), i, end));
        i = end;
      }
    }
    return result;
  }
}

/// Return all top-level declaration spans, including leading documentation.
/// Generics do not contain declaration terminators; all three bracket kinds
/// and expression bodies are tracked independently of generic punctuation.
List<SettingsWidgetsSpan> settingsWidgetsSpans(String source) {
  final tokens = _Scanner(source).tokens();
  final result = <SettingsWidgetsSpan>[];
  var cursor = 0;
  var i = 0;
  while (i < tokens.length) {
    final begin = i;
    final stack = <String>[];
    var variable = false;
    var arrow = false;
    var complete = false;
    while (i < tokens.length && !complete) {
      final value = tokens[i].text;
      if (stack.isEmpty && value == '=') {
        variable = true;
      }
      if (stack.isEmpty && value == '=>') {
        arrow = true;
      }
      if (value == '(' || value == '[' || value == '{') {
        stack.add(value);
      } else if (value == ')' || value == ']' || value == '}') {
        final expected = {')': '(', ']': '[', '}': '{'}[value];
        if (stack.isEmpty || stack.removeLast() != expected) {
          throw StateError('Unbalanced declaration');
        }
        complete = value == '}' && stack.isEmpty && !variable && !arrow;
      } else if (value == ';' && stack.isEmpty) {
        complete = true;
      }
      i++;
    }
    if (!complete) {
      throw StateError('Unclosed declaration');
    }
    final chunk = tokens.sublist(begin, i);
    final end = chunk.last.end;
    if (!{'import', 'export', 'library', 'part'}.contains(chunk.first.text)) {
      String? name;
      final classIndex = chunk.indexWhere(
        (t) => t.text == 'class' || t.text == 'enum',
      );
      if (classIndex >= 0 && classIndex < 3) {
        name = chunk[classIndex + 1].text;
      } else {
        for (var j = 1; j < chunk.length; j++) {
          final value = chunk[j].text;
          if (value == '=' || value == ';' || value == '(') {
            if (chunk[j - 1].text == '>') {
              var depth = 1;
              var k = j - 2;
              while (k >= 0 && depth > 0) {
                if (chunk[k].text == '>') {
                  depth++;
                }
                if (chunk[k].text == '<') {
                  depth--;
                }
                k--;
              }
              name = chunk[k].text;
            } else {
              name = chunk[j - 1].text;
            }
            break;
          }
        }
      }
      if (name == null) {
        throw StateError('Unknown declaration at ${chunk.first.start}');
      }
      var start = chunk.first.start;
      var gap = cursor;
      final scanner = _Scanner(source);
      while (gap < chunk.first.start) {
        if (RegExp(r'\s').hasMatch(source[gap])) {
          gap++;
        } else if (source.startsWith('//', gap) ||
            source.startsWith('/*', gap)) {
          final documentation =
              source.startsWith('///', gap) || source.startsWith('/**', gap);
          if (documentation && start == chunk.first.start) {
            start = gap;
          } else if (!documentation) {
            start = chunk.first.start;
          }
          gap = scanner.commentEnd(gap);
        } else {
          throw StateError('Unexpected declaration gap');
        }
      }
      result.add(SettingsWidgetsSpan(name, start, end));
    }
    cursor = end;
  }
  return result;
}

String settingsWidgetsDeclaration(String name, {String root = '.'}) {
  final row = settingsWidgetsManifest().singleWhere(
    (r) => r['original_name'] == name,
  );
  final found = <String>[];
  for (final path in {settingsWidgetsFacade, row['destination_file']!}) {
    final file = File('$root/$path');
    if (file.existsSync()) {
      final source = file.readAsStringSync();
      for (final span in settingsWidgetsSpans(source)) {
        if (span.name == name) {
          found.add(source.substring(span.start, span.end));
        }
      }
    }
  }
  if (found.length != 1) {
    throw StateError('$name has ${found.length} physical declarations');
  }
  return found.single;
}

String settingsWidgetsSource({String root = '.'}) => settingsWidgetsManifest()
    .map((r) => settingsWidgetsDeclaration(r['original_name']!, root: root))
    .join('\n\n');

Map<String, String> settingsWidgetsPhysicalFiles() => {
  settingsWidgetsFacade: File(settingsWidgetsFacade).readAsStringSync(),
  if (Directory(settingsWidgetsFeature).existsSync())
    for (final f in Directory(
      settingsWidgetsFeature,
    ).listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart')) f.path: f.readAsStringSync(),
};

/// Tool protocol used by reader_check; tests call the same frozen functions.
void main(List<String> args) {
  if (args.first == 'spans') {
    final source = File(args[1]).readAsStringSync();
    stdout.write(
      jsonEncode([
        for (final span in settingsWidgetsSpans(source))
          {
            'name': span.name,
            'start': source.substring(0, span.start).runes.length,
            'end': source.substring(0, span.end).runes.length,
          },
      ]),
    );
  } else if (args.first == 'read') {
    stdout.write(settingsWidgetsDeclaration(args[2], root: args[1]));
  } else {
    throw ArgumentError('Expected spans or read');
  }
}
