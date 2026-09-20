// ignore_for_file: avoid_print
// Read-only local catalog audit. Never selects URLs, headers, or credentials.
// Usage: dart run tool/audit_iptv_titles.dart /absolute/path/iptv_catalog.db
import 'dart:convert';
import 'dart:io';
import 'package:debrify/utils/iptv_title.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Pass the catalog database path');
  final query = await Process.run('sqlite3', [
    '-readonly',
    '-json',
    args.single,
    "SELECT c.name,c.content_type FROM channels c JOIN catalogs a ON c.catalog_key=a.catalog_key AND c.generation=a.generation WHERE c.content_type IN ('vod','series')",
  ]);
  if (query.exitCode != 0) throw StateError('Read-only catalog query failed');
  final rows = (jsonDecode(query.stdout as String) as List).cast<Map>();
  var empty = 0;
  final clock = Stopwatch()..start();
  for (final row in rows) {
    if (IptvTitle.parse(row['name'] as String).exact.isEmpty) empty++;
  }
  print(
    'Parsed ${rows.length} VOD titles in ${clock.elapsedMilliseconds}ms; empty keys: $empty',
  );
  for (final target in [
    ('Game of Thrones', 2011, 'series'),
    ('The Avengers', 2012, 'vod'),
    ('Dune', 2021, 'vod'),
    ('Blade Runner', 1982, 'vod'),
    ('Blade Runner 2049', 2017, 'vod'),
    ('Total Recall', 1990, 'vod'),
    ('Total Recall', 2012, 'vod'),
    ('It', 2017, 'vod'),
    ('1917', 2019, 'vod'),
    ('Breaking Bad', 2008, 'series'),
    ('The Office', 2005, 'series'),
    ('House of the Dragon', 2022, 'series'),
    ('The Last of Us', 2023, 'series'),
  ]) {
    final matches = rows
        .where(
          (r) =>
              r['content_type'] == target.$3 &&
              IptvTitle.matches(
                r['name'] as String,
                target.$1,
                year: target.$2,
              ),
        )
        .toList();
    print('${target.$1} (${target.$2}): ${matches.length} title candidates');
    for (final row in matches) {
      print('  ${row['name']}');
    }
  }
  print(
    'Title candidates are not verified metadata identities or episode availability.',
  );
}
