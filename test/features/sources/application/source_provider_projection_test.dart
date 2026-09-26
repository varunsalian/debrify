import 'package:debrify/features/sources/application/source_provider_projection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent row(String source, {String? label}) => Torrent(
  rowid: 0,
  infohash: source,
  name: source,
  source: source,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  addonDisplayName: label,
);
AddonSearchStatus status(
  String key, {
  String name = 'Status',
  String config = 'config',
  int count = 0,
  String? error,
}) => AddonSearchStatus(
  addonId: 'addon',
  addonKey: config,
  sourceKey: key,
  name: name,
  count: count,
  error: error,
);
SourceProviderProjection project({
  List<Torrent> rows = const [],
  List<AddonSearchStatus> statuses = const [],
  List<IptvSourceResult> iptv = const [],
  List<String> priority = const [],
  Map<String, String> aliases = const {},
  Set<String> retrying = const {},
}) => projectSourceProviders(
  torrents: rows,
  statuses: statuses,
  iptv: iptv,
  priority: priority,
  aliases: aliases,
  retrying: retrying,
);

void main() {
  test('one ready source hides strip while preserving All eligibility', () {
    final result = project(rows: [row('stremio:one')]);
    expect(result.visible, isFalse);
    expect(result.showAll, isTrue);
    expect(result.options.single.label, 'One');
    expect(result.retries, isEmpty);
    expect(project().showAll, isFalse);
  });

  test('aliases group sorted sources and status labels precede row labels', () {
    final result = project(
      rows: [
        row('z', label: 'Row Z'),
        row('a', label: 'Row A'),
        row('stremio:other'),
      ],
      aliases: {'z': 'engine:group', 'a': 'engine:group'},
      statuses: [status('engine:group', name: '', error: 'failed')],
      priority: ['stremio:other', 'engine:group'],
    );
    expect(result.options.map((o) => o.key), ['stremio:other', 'engine:group']);
    expect(result.options.last.label, '');
    expect(result.options.last.retryable, isFalse);
    expect(result.retries, isEmpty);
  });

  test('retry-only strip uses final matching status and exact request key', () {
    final first = status('stremio:empty', config: 'old');
    final last = status('stremio:empty', config: 'new', error: 'timeout');
    final result = project(
      statuses: [first, last, status('stremio:ready', count: 2)],
      retrying: {'new'},
    );
    expect(result.visible, isTrue);
    expect(result.showAll, isFalse);
    expect(result.options.single.key, 'stremio:empty');
    expect(result.options.single.retryable, isTrue);
    expect(result.options.single.retrying, isTrue);
    expect(result.options.single.failed, isTrue);
    expect(result.retries['stremio:empty'], same(last));
    expect(() => result.retries.clear(), throwsUnsupportedError);
    expect(() => result.options.clear(), throwsUnsupportedError);
  });

  test('zero-result status is actionable without being a failure', () {
    final result = project(
      statuses: [status('stremio:empty')],
      retrying: {'addon'},
    );
    expect(result.options.single.retryable, isTrue);
    expect(result.options.single.failed, isFalse);
    expect(result.options.single.retrying, isFalse);
  });

  test('IPTV identity supplies label and exposes a lone failed catalog', () {
    final result = project(
      rows: [row('iptv:one', label: 'Row')],
      statuses: [status('iptv:one', name: 'Status', error: 'failed')],
      iptv: [
        const IptvSourceResult(
          'iptv:one',
          'Catalog',
          'Unavailable',
          [],
          retryableFailure: true,
        ),
      ],
    );
    expect(result.visible, isTrue);
    expect(result.showAll, isTrue);
    expect(result.options.single.label, 'IPTV · Catalog');
    expect(result.options.single.retryable, isFalse);
    expect(
      sourceProviderLabel(
        'iptv:one',
        iptv: [
          const IptvSourceResult('iptv:one', 'First', '', []),
          const IptvSourceResult('iptv:one', 'Second', '', []),
        ],
      ),
      'IPTV · First',
    );
  });
}
