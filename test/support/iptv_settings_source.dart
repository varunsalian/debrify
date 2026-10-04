import 'dart:convert';
import 'dart:io';

/// Resolve the production declaration through the move manifest, then read
/// only its owning method. Missing declaration/end markers are test failures.
String iptvSettingsOriginalMember(String originalName) {
  final lines = File('dev/tool/iptv_settings_manifest.tsv').readAsLinesSync();
  final header = lines.first.split('\t');
  final rows = [
    for (final line in lines.skip(1))
      Map.fromIterables(header, line.split('\t')),
  ];
  final row =
      rows.where((row) => row['original_name'] == originalName).firstOrNull ??
      {
        'destination_file': 'lib/screens/settings/iptv_settings_page.dart',
        'destination_class': '_IptvSettingsPageState',
        'new_name': originalName.split('.').last,
      };
  final destination = File(row['destination_file']!);
  final moved = destination.existsSync();
  final path = moved
      ? row['destination_file']!
      : 'lib/screens/settings/iptv_settings_page.dart';
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
  final formatting =
      jsonDecode(
            File(
              'dev/tool/iptv_settings_context_exceptions.json',
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
    String pattern(List<dynamic> values) => values
        .map((value) {
          final closing = const [')', ']', '}'].contains(value);
          return '${closing ? '(?:,$gap)?' : ''}${RegExp.escape(value as String)}';
        })
        .join(gap);
    final recorded = RegExp(
      '(${pattern((site['condition_tokens'] ?? site['prefix_tokens']) as List<dynamic>)}$gap)'
      '\\{$gap${pattern(site['body_tokens'] as List<dynamic>)}$gap\\}',
    );
    String compactPrefix(String value) => value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r',(?=[)\]}])'), '');
    final expectedPrefix = compactPrefix(
      (site['prefix_tokens'] as List<dynamic>).join(' '),
    );
    final matches = recorded.allMatches(member).where((match) {
      return compactPrefix(member.substring(0, match.start) + match[1]!) ==
          expectedPrefix;
    }).toList();
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
              'dev/tool/iptv_settings_checker_config.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  if (moved &&
      originalName == '_IptvSettingsPageState.build' &&
      row['allowed_edits']!.split(',').contains('root_build_forwarder')) {
    // The exact named exception removes @override from the plain section.
    // The checker separately requires State's annotated, exact forwarder.
    final exception =
        (config['named_exceptions']
                as Map<String, dynamic>)['root_build_forwarder']
            as List<dynamic>;
    if (exception[0] != originalName ||
        exception[1] != path ||
        member.trimLeft().startsWith('@override')) {
      throw StateError('Root build annotation registration changed');
    }
    member = '  @override\n$member';
  }
  for (final entry
      in (config['borrowed_resource_aliases'] as Map<String, dynamic>? ??
              const {})
          .entries) {
    member = member.replaceAll(
      '_deps.${entry.key}',
      (entry.value as String).split('.').last,
    );
  }
  for (final entry
      in (config['live_getter_aliases'] as Map<String, dynamic>? ?? const {})
          .entries) {
    member = member.replaceAll(
      '_deps.${entry.key}()',
      (entry.value as String).split('.').last,
    );
  }
  // These are exactly the registered live State callbacks. Builder/dialog
  // contexts remain source text and the verbatim checker checks their scope.
  member = member.replaceAll(RegExp(r'\b_deps\s*\.\s*setState\b'), 'setState');
  for (final receiver in ['_deps', 'deps']) {
    for (final name in ['mounted', 'context']) {
      member = member.replaceAll(
        RegExp('\\b$receiver\\s*\\.\\s*$name\\s*\\(\\s*\\)'),
        name,
      );
    }
  }
  for (final getter in config['live_getter_callbacks'] as List<dynamic>) {
    member = member.replaceAll('_deps.$getter()', '$getter');
  }
  for (final getter in config['live_widget_getters'] as List<dynamic>) {
    member = member.replaceAll('_deps.$getter()', 'widget.$getter');
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
    // Unqualified names are methods/types, never a moved field's public name.
    final field = entry['destination_file']!.endsWith('_owner.dart');
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
  return member;
}
