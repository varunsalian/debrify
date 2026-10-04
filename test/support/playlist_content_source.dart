import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Resolve the production declaration through the move manifest, then read
/// only its owning method. Missing declaration/end markers are test failures.
String playlistContentOriginalMember(String originalName) {
  final lines = File(
    'dev/tool/playlist_content_manifest.tsv',
  ).readAsLinesSync();
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
      : 'lib/screens/playlist_content_view_screen.dart';
  final name = moved ? row['new_name']! : originalName.split('.').last;
  final fileSource = File(path).readAsStringSync();
  final owner = moved
      ? row['destination_class']!
      : originalName.split('.').first;
  final ownerMarker = RegExp(
    r'^class ' + RegExp.escape(owner) + r'\b',
    multiLine: true,
  ).firstMatch(fileSource);
  if (ownerMarker == null && owner.isNotEmpty) {
    throw StateError('Missing owner: $path::$owner');
  }
  final ownerEnd = owner.isEmpty
      ? null
      : RegExp(
          r'^}',
          multiLine: true,
        ).firstMatch(fileSource.substring(ownerMarker!.end));
  if (ownerEnd == null && owner.isNotEmpty) {
    throw StateError('Missing owner end: $path::$owner');
  }
  final source = owner.isEmpty
      ? fileSource
      : fileSource.substring(
          ownerMarker!.start,
          ownerMarker.end + ownerEnd!.end,
        );
  final indent = owner.isEmpty ? '' : '  ';
  final start = RegExp(
    '^$indent\\S[^\\n]*\\b${RegExp.escape(name)}\\s*\\(',
    multiLine: true,
  ).firstMatch(source);
  if (start == null) throw StateError('Missing method marker: $path::$name');
  final end = RegExp(
    '^$indent}\\s*\$',
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
  final formatting =
      jsonDecode(
            File(
              'dev/tool/playlist_content_context_exceptions.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final site in formatting['sites'] as List<dynamic>) {
    if (site['file'] != row['destination_file'] ||
        site['owner'] != row['destination_class'] ||
        site['method'] != row['new_name'] ||
        site['kind'] != 'formatter_if_braces') {
      continue;
    }
    const gap = r'(?:\s|//[^\n]*\n|/\*[\s\S]*?\*/)*';
    String pattern(List<dynamic> values) =>
        values.map((value) => RegExp.escape(value as String)).join(gap);
    final prefix = site['prefix_source'] is String
        ? RegExp.escape(site['prefix_source'] as String)
        : pattern(site['prefix_tokens'] as List<dynamic>) + gap;
    final recorded = RegExp(
      '($prefix)'
      '\\{$gap${pattern(site['body_tokens'] as List<dynamic>)}$gap\\}',
    );
    final matches = recorded.allMatches(member).toList();
    if (matches.length != 1) {
      throw StateError('Recorded formatter site changed: $originalName');
    }
    final match = matches.single;
    member = member.replaceRange(
      match.start,
      match.end,
      '${match[1]}${(site['body_tokens'] as List<dynamic>).join(' ')}',
    );
  }
  final config =
      jsonDecode(
            File(
              'dev/tool/playlist_content_checker_config.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  // These are exactly the registered live State callbacks. Builder/dialog
  // contexts remain source text and the verbatim checker checks their scope.
  member = member.replaceAll(RegExp(r'\b_deps\s*\.\s*setState\b'), 'setState');
  for (final receiver in ['_deps', 'deps']) {
    for (final name in ['mounted', 'context']) {
      member = member.replaceAll(
        RegExp(r'\b' + receiver + r'\s*\.\s*' + name + r'\s*\(\s*\)'),
        name,
      );
    }
  }
  for (final getter in config['live_getter_callbacks'] as List<dynamic>) {
    member = member.replaceAll(
      RegExp(r'\b_deps\s*\.\s*' + getter + r'\s*\(\s*\)'),
      '$getter',
    );
  }
  for (final getter in config['live_widget_getters'] as List<dynamic>) {
    member = member.replaceAll(
      RegExp(r'\b_deps\s*\.\s*' + getter + r'\s*\(\s*\)'),
      'widget.$getter',
    );
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
    if (owner.isNotEmpty) {
      member = member
          .split('\n')
          .map((line) {
            if (!line.trimLeft().startsWith('///')) return line;
            return line.replaceAll(
              RegExp(
                r'\b' +
                    RegExp.escape(owner) +
                    r'\.' +
                    RegExp.escape(current) +
                    r'\b',
              ),
              original,
            );
          })
          .join('\n');
    }
    // Unqualified names are methods/types, never a moved field's public name.
    final field = entry['step'] == '2';
    if (original != current && !field) {
      member = member.replaceAll(
        RegExp(r'(?<![.\w])' + RegExp.escape(current) + r'\b(?!\s*:)'),
        original,
      );
    }
  }
  member = member.replaceAllMapped(
    RegExp(r'\$\{(_[A-Za-z][A-Za-z0-9]*)\}'),
    (match) => '\$${match[1]}',
  );
  if (originalName.endsWith('.build')) {
    member = member.replaceFirst(RegExp(r'@override\s*'), '');
  }
  return normalizePlaylistContentFormattingCommas(member, originalName);
}

/// Only AST-proven optional formatter punctuation at frozen prefix hashes.
/// Original fixtures and every meaningful source assertion remain unchanged.
String normalizePlaylistContentFormattingCommas(String member, String name) {
  final metadata = File(
    'dev/tool/playlist_content_source_formatting_commas.json',
  );
  if (!metadata.existsSync()) return member;
  final table = jsonDecode(metadata.readAsStringSync()) as Map<String, dynamic>;
  final sites = table[name] as List<dynamic>? ?? const [];
  if (sites.isEmpty) return member;
  var result = member.replaceAll(RegExp(r'\s+'), '');
  for (final site in sites) {
    final offset = site['offset'] as int;
    if (offset >= result.length ||
        sha256.convert(utf8.encode(result.substring(0, offset))).toString() !=
            site['prefix_sha256']) {
      throw StateError('Formatter comma prefix changed: $name at $offset');
    }
    final closer = site['closer'] as String;
    if (site['kind'] == 'remove') {
      if (result.substring(offset).startsWith(',$closer')) {
        result = result.replaceRange(offset, offset + 1, '');
      } else if (!result.substring(offset).startsWith(closer)) {
        throw StateError('Formatter comma changed: $name at $offset');
      }
    } else if (site['kind'] == 'insert') {
      if (result.substring(offset).startsWith(closer)) {
        result = result.replaceRange(offset, offset, ',');
      } else if (!result.substring(offset).startsWith(',$closer')) {
        throw StateError('Original comma changed: $name at $offset');
      }
    } else {
      throw StateError('Unknown formatter comma kind: $name');
    }
  }
  return result;
}
