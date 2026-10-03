import 'dart:convert';
import 'dart:io';

/// Resolve the production declaration through the move manifest, then read
/// only its owning method. Missing declaration/end markers are test failures.
String iptvOriginalMember(String originalName) {
  final lines = File('dev/tool/iptv_manifest.tsv').readAsLinesSync();
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
      : 'lib/widgets/iptv/iptv_results_view.dart';
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
  var member = source.substring(start.start, start.end + end.end);
  final config =
      jsonDecode(File('dev/tool/iptv_checker_config.json').readAsStringSync())
          as Map<String, dynamic>;
  // These are exactly the registered live State callbacks. Builder/dialog
  // contexts remain source text and the verbatim checker checks their scope.
  for (final receiver in ['_deps', 'deps']) {
    for (final name in ['mounted', 'context']) {
      member = member.replaceAll('$receiver.$name()', name);
    }
  }
  final paths = config['receiver_paths'] as Map<String, dynamic>? ?? const {};
  for (final path in paths.keys) {
    member = member.replaceAll(RegExp(r'\b' + RegExp.escape(path) + r'\.'), '');
  }
  for (final receiver in config['receivers'] as List<dynamic>) {
    member = member.replaceAll(
      RegExp(r'\b' + RegExp.escape(receiver as String) + r'\.'),
      '',
    );
  }
  for (final entry in rows) {
    final original = entry['original_name']!.split('.').last;
    final current = entry['new_name']!;
    if (original == current) continue;
    member = member.replaceAll(
      RegExp(r'\b' + RegExp.escape(current) + r'\b'),
      original,
    );
  }
  return member;
}
