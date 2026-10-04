import 'dart:convert';
import 'dart:io';

/// Read a manifest-owned declaration; absence always fails the source guard.
String spotlightOriginalMember(String originalName) {
  final lines = File('dev/tool/spotlight_board_manifest.tsv').readAsLinesSync();
  final header = lines.first.split('\t');
  final rows = [
    for (final line in lines.skip(1))
      Map.fromIterables(header, line.split('\t')),
  ];
  final row = rows.singleWhere((r) => r['original_name'] == originalName);
  final destination = File(row['destination_file']!);
  final moved = destination.existsSync();
  final owner = moved
      ? row['destination_class']!
      : originalName.split('.').first;
  final name = moved ? row['new_name']! : originalName.split('.').last;
  final file = moved
      ? destination
      : File('lib/widgets/home/spotlight_board.dart');
  final source = file.readAsStringSync();
  final classStart = RegExp(
    '^class ${RegExp.escape(owner)}\\b',
    multiLine: true,
  ).firstMatch(source);
  if (classStart == null) {
    throw StateError('Missing owner $owner in ${file.path}');
  }
  final classEnd = RegExp(
    r'^}',
    multiLine: true,
  ).firstMatch(source.substring(classStart.end));
  if (classEnd == null) {
    throw StateError('Missing owner end $owner');
  }
  final body = source.substring(
    classStart.start,
    classStart.end + classEnd.end,
  );
  final start = RegExp(
    '^  \\S[^\\n={]*\\b${RegExp.escape(name)}\\s*(?:\\(|=>|\\{)',
    multiLine: true,
  ).firstMatch(body);
  if (start == null) {
    throw StateError('Missing member $owner.$name');
  }
  var begin = start.start;
  while (begin > 0) {
    final previousEnd = begin - 1;
    final previousStart = body.lastIndexOf('\n', previousEnd - 1) + 1;
    final line = body.substring(previousStart, previousEnd).trim();
    if (!line.startsWith('///') && !line.startsWith('@')) {
      break;
    }
    begin = previousStart;
  }
  var braces = 0;
  var parentheses = 0;
  var brackets = 0;
  var arrow = false;
  var block = false;
  var end = -1;
  for (var i = start.start; i < body.length; i++) {
    final char = body[i];
    if (body.startsWith('//', i)) {
      i = body.indexOf('\n', i);
      if (i < 0) {
        break;
      }
      continue;
    }
    if (body.startsWith('/*', i)) {
      i = body.indexOf('*/', i + 2) + 1;
      continue;
    }
    if (char == "'" || char == '"') {
      final quote = body.startsWith(char * 3, i) ? char * 3 : char;
      i += quote.length;
      while (i < body.length && !body.startsWith(quote, i)) {
        if (body[i] == r'\') {
          i++;
        }
        i++;
      }
      i += quote.length - 1;
      continue;
    }
    if (body.startsWith('=>', i) && braces == 0 && parentheses == 0) {
      arrow = true;
    }
    if (char == '(') {
      parentheses++;
    } else if (char == ')') {
      parentheses--;
    } else if (char == '[') {
      brackets++;
    } else if (char == ']') {
      brackets--;
    } else if (char == '{') {
      if (parentheses == 0 && brackets == 0 && !arrow) {
        block = true;
      }
      braces++;
    } else if (char == '}') {
      braces--;
      if (block && braces == 0 && parentheses == 0) {
        end = i + 1;
        break;
      }
    } else if (char == ';' &&
        braces == 0 &&
        parentheses == 0 &&
        brackets == 0) {
      end = i + 1;
      break;
    }
  }
  if (end < 0) {
    throw StateError('Missing declaration end $owner.$name');
  }
  var member = body.substring(begin, end);
  if (!File(
        'lib/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart',
      ).existsSync() &&
      file.path == 'lib/widgets/home/spotlight_board.dart') {
    return member.replaceAll(RegExp(r'\s+'), '');
  }
  final config =
      jsonDecode(
            File(
              'dev/tool/spotlight_board_checker_config.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final view =
      (config['widget_views'] as Map<String, dynamic>?)?[originalName]
          as Map<String, dynamic>?;
  if (view != null) {
    for (final property in view['properties'] as List<dynamic>) {
      member = member.replaceAll(
        RegExp('\\bview\\s*\\.\\s*$property\\b'),
        'widget.$property',
      );
    }
    for (final property in view['statics'] as List<dynamic>) {
      member = member.replaceAll(
        RegExp('\\bview\\s*\\.\\s*$property\\b'),
        'SpotlightBoard.$property',
      );
    }
    for (final property in view['state_members'] as List<dynamic>) {
      member = member.replaceAll(
        RegExp('\\bview\\s*\\.\\s*$property\\b'),
        '$property',
      );
    }
  }
  member = member.replaceAll(RegExp(r'\b_deps\s*\.\s*setState\b'), 'setState');
  for (final getter in ['context', 'mounted']) {
    member = member.replaceAll(
      RegExp('\\b_deps\\s*\\.\\s*$getter\\s*\\(\\s*\\)'),
      getter,
    );
  }
  final paths = config['receiver_paths'] as Map<String, dynamic>;
  for (final entry in rows) {
    final original = entry['original_name']!.split('.').last;
    final current = entry['new_name']!;
    for (final path in paths.entries.where(
      (p) => p.value == entry['destination_class'],
    )) {
      final pattern = path.key.split('.').map(RegExp.escape).join(r'\s*\.\s*');
      member = member.replaceAll(
        RegExp('\\b$pattern\\s*\\.\\s*${RegExp.escape(current)}\\b'),
        original,
      );
    }
    if (current != original) {
      member = member.replaceAll(
        RegExp('(?<![.\\w])${RegExp.escape(current)}\\b'),
        original,
      );
    }
  }
  for (final entry
      in (config['type_renames'] as Map<String, dynamic>).entries) {
    member = member.replaceAll(
      RegExp('\\b${RegExp.escape(entry.value as String)}\\b'),
      entry.key,
    );
  }
  final bound =
      (config['bound_this'] as Map<String, dynamic>?)?[originalName]
          as Map<String, dynamic>?;
  if (bound != null && moved) {
    // Exactly the registered, unshadowed field; the local `card` stays local.
    member = member.replaceAll(
      RegExp(
        '(?<![.\\w])${RegExp.escape(bound['receiver'] as String)}\\b(?!\\s*\\.)',
      ),
      'this',
    );
  }
  return member.replaceAll(RegExp(r'\s+'), '');
}
