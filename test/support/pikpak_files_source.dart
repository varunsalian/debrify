import 'dart:convert';
import 'dart:io';

/// Resolve the production declaration through the move manifest, then read
/// only its owning method. Missing declaration/end markers are test failures.
String pikpakOriginalMember(String originalName) {
  final lines = File('dev/tool/pikpak_manifest.tsv').readAsLinesSync();
  final header = lines.first.split('\t');
  final rows = [
    for (final line in lines.skip(1))
      Map.fromIterables(header, line.split('\t')),
  ];
  final row = rows.singleWhere((row) => row['original_name'] == originalName);
  final destination = File(row['destination_file']!);
  final moved = destination.existsSync();
  final path = moved
      ? row['destination_file']!
      : 'lib/screens/pikpak/pikpak_files_screen.dart';
  final name = moved ? row['new_name']! : originalName.split('.').last;
  final fileSource = File(path).readAsStringSync();
  final owner = moved
      ? row['destination_class']!
      : originalName.split('.').first;
  final ownerMarker = RegExp(
    r'^class ' + RegExp.escape(owner) + r'\b',
    multiLine: true,
  ).firstMatch(fileSource);
  if (ownerMarker == null) throw StateError('Missing owner: $path::$owner');
  final ownerEnd = RegExp(
    r'^}',
    multiLine: true,
  ).firstMatch(fileSource.substring(ownerMarker.end));
  if (ownerEnd == null) throw StateError('Missing owner end: $path::$owner');
  final source = fileSource.substring(
    ownerMarker.start,
    ownerMarker.end + ownerEnd.end,
  );
  final start = RegExp(
    r'^  \S[^\n]*\b' + RegExp.escape(name) + r'\s*\(',
    multiLine: true,
  ).firstMatch(source);
  if (start == null) throw StateError('Missing method marker: $path::$name');
  final end = RegExp(
    r'^  }\s*$',
    multiLine: true,
  ).firstMatch(source.substring(start.end));
  if (end == null) throw StateError('Missing method end: $path::$name');
  var memberStart = start.start;
  while (memberStart > 0) {
    final previousEnd = memberStart - 1;
    final previousStart = source.lastIndexOf('\n', previousEnd - 1) + 1;
    final line = source.substring(previousStart, previousEnd).trim();
    if (!line.startsWith('///') && line != '@override') break;
    memberStart = previousStart;
  }
  var member = source.substring(memberStart, start.end + end.end);
  final config =
      jsonDecode(File('dev/tool/pikpak_checker_config.json').readAsStringSync())
          as Map<String, dynamic>;
  // These are exactly the registered live State callbacks. Builder/dialog
  // contexts remain source text and the verbatim checker checks their scope.
  member = member.replaceAll('_deps.setState', 'setState');
  for (final receiver in ['_deps', 'deps']) {
    for (final name in ['mounted', 'context']) {
      member = member.replaceAll('$receiver.$name()', name);
    }
  }
  for (final getter in config['live_getter_callbacks'] as List<dynamic>) {
    member = member.replaceAll('_deps.$getter()', '$getter');
  }
  final paths = config['receiver_paths'] as Map<String, dynamic>? ?? const {};
  for (final entry in rows) {
    final original = entry['original_name']!.split('.').last;
    final current = entry['new_name']!;
    final owner = entry['destination_class']!;
    for (final path in paths.entries.where((path) => path.value == owner)) {
      member = member.replaceAll(
        RegExp(
          r'\b' +
              RegExp.escape(path.key) +
              r'\.' +
              RegExp.escape(current) +
              r'\b',
        ),
        original,
      );
    }
    member = member.replaceAll(
      RegExp(r'\b(?:_deps|deps)\.' + RegExp.escape(current) + r'\b'),
      original,
    );
    // Unqualified names are methods/types, never a moved field's public name.
    final field = entry['step'] == '2';
    if (original != current && !field) {
      member = member.replaceAll(
        RegExp(r'(?<![.\w])' + RegExp.escape(current) + r'\b(?!\s*:)'),
        original,
      );
    }
  }
  for (final getter in config['live_widget_getters'] as List<dynamic>) {
    member = member.replaceAll('_deps.$getter()', 'widget.$getter');
  }
  member = member.replaceAllMapped(
    RegExp(r'\$\{(_[A-Za-z][A-Za-z0-9]*)\}'),
    (match) => '\$${match[1]}',
  );
  return member;
}
