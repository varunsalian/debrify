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
  if (startOwner == null) throw StateError('Missing owner $path::$owner');
  final ownerTail = text.substring(startOwner.start);
  final endOwner = RegExp(r'^}', multiLine: true).firstMatch(ownerTail);
  if (endOwner == null) throw StateError('Missing owner end');
  final source = ownerTail.substring(0, endOwner.end);
  final start = RegExp(
    r'^  [A-Za-z][\w<>?, ]*\s+' + RegExp.escape(name) + r'\s*\(',
    multiLine: true,
  ).firstMatch(source);
  if (start == null) throw StateError('Missing method $path::$name');
  final arrowEnd = source.indexOf(';', start.end);
  final end = RegExp(
    r'^  }\s*$',
    multiLine: true,
  ).firstMatch(source.substring(start.end));
  if (end == null) throw StateError('Missing method end $path::$name');
  var first = start.start;
  while (first > 0) {
    final previousEnd = first - 1;
    final previousStart = source.lastIndexOf('\n', previousEnd - 1) + 1;
    final line = source.substring(previousStart, previousEnd).trim();
    if (!line.startsWith('///') && line != '@override') break;
    first = previousStart;
  }
  final header = source.substring(start.start, source.indexOf('\n', start.end));
  final finish = header.contains('=>') ? arrowEnd + 1 : start.end + end.end;
  final member = source.substring(first, finish);
  return moved ? mergedOriginalNames(member) : member;
}

String mergedOriginalNames(String member) {
  final config =
      jsonDecode(
            File(
              'dev/tool/merged_detail_checker_config.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  member = member.replaceAll('_deps.setState', 'setState');
  for (final receiver in ['_deps', 'deps']) {
    for (final name in ['mounted', 'context']) {
      member = member.replaceAll('$receiver.$name()', name);
    }
  }
  for (final getter in config['live_getter_callbacks'] as List<dynamic>) {
    member = member.replaceAll('_deps.$getter()', '$getter');
  }
  for (final getter in config['live_widget_getters'] as List<dynamic>) {
    member = member.replaceAll('_deps.$getter()', 'widget.$getter');
  }
  final paths = config['receiver_paths'] as Map<String, dynamic>? ?? const {};
  final rows = mergedManifest();
  for (final row in rows) {
    final original = row['original_name']!.split('.').last;
    final current = row['new_name']!;
    for (final path in paths.entries.where(
      (p) => p.value == row['destination_class'],
    )) {
      member = member.replaceAll(
        RegExp(
          r'\b' +
              path.key.split('.').map(RegExp.escape).join(r'\s*\.\s*') +
              r'\s*\.\s*' +
              RegExp.escape(current) +
              r'\b',
        ),
        original,
      );
    }
    member = member.replaceAll(
      RegExp(r'\b(?:_deps|deps)\s*\.\s*' + RegExp.escape(current) + r'\b'),
      original,
    );
    if (original != current &&
        rows.where((r) => r['new_name'] == current).length == 1) {
      member = member.replaceAll(
        RegExp(r'(?<![.\w])' + RegExp.escape(current) + r'\b(?!\s*:)'),
        original,
      );
    }
  }
  return member.replaceAllMapped(
    RegExp(r'\$\{(_[A-Za-z][A-Za-z0-9]*)\}'),
    (m) => '\$${m[1]}',
  );
}
