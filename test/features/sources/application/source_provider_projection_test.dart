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
  test('toolbar warnings preserve order and exact selected provider scope', () {
    final statuses = [
      status('mediaserver:one', error: 'First error'),
      status('stremio:other', error: 'Addon error'),
      status('mediaserver:two', error: 'Second server'),
      status('mediaserver:one', error: 'Latest first error'),
    ];
    const iptv = [
      IptvSourceResult('iptv:ready', 'Ready', 'Not an error', []),
      IptvSourceResult(
        'iptv:failed',
        'Catalog',
        'Unavailable',
        [],
        retryableFailure: true,
      ),
    ];
    List<String> messages(String? key) =>
        sourceToolbarMessages(statuses: statuses, iptv: iptv, selectedKey: key);
    final all = messages(null);
    expect(all, [
      'Latest first error',
      'Second server',
      'IPTV · Catalog: Unavailable',
    ]);
    expect(messages('mediaserver:two'), ['Second server']);
    expect(messages('iptv:failed'), ['IPTV · Catalog: Unavailable']);
    expect(messages('iptv:ready'), isEmpty);
    expect(messages('unknown'), isEmpty);
    expect(() => all.clear(), throwsUnsupportedError);
  });

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
  test(
    'cinema keeps first labels, grouped counts, zero groups and priority order',
    () {
      final result = projectCinemaSourceProviders(
        torrents: [
          row('z', label: 'Row Z'),
          row('a', label: 'Row A'),
        ],
        statuses: [
          status('engine:group', name: ''),
          status('engine:group', name: 'Later'),
          status('stremio:zero', count: 2),
        ],
        iptv: [],
        priority: ['stremio:zero'],
        aliases: {'z': 'engine:group', 'a': 'engine:group'},
        retrying: {},
      );
      expect(result.map((entry) => entry.id), [
        null,
        'stremio:zero',
        'engine:group',
      ]);
      expect(result.map((entry) => entry.count), [2, 0, 2]);
      expect(result.last.label, 'Other sources');
      expect(result.first.label, 'All sources');
      expect(() => result.clear(), throwsUnsupportedError);
    },
  );

  test(
    'cinema combines status flags and retains last nonnull server error',
    () {
      final statuses = [
        status('mediaserver:one', config: 'first', error: 'First error'),
        status('mediaserver:one', config: 'second', error: 'Last error'),
        status('mediaserver:one', config: 'third', count: 1),
        status('stremio:other', error: 'Not a server message'),
      ];
      final result = projectCinemaSourceProviders(
        torrents: [],
        statuses: statuses,
        iptv: [],
        priority: [],
        aliases: {},
        retrying: {'first'},
      );
      final server = result.singleWhere(
        (entry) => entry.id == 'mediaserver:one',
      );
      expect(server.failed, isTrue);
      expect(server.loading, isTrue);
      expect(server.message, 'Last error');
      expect(
        result.singleWhere((entry) => entry.id == 'stremio:other').message,
        isNull,
      );
      final messages = sourceMediaServerMessages(statuses);
      expect(messages, {'mediaserver:one': 'Last error'});
      expect(() => messages.clear(), throwsUnsupportedError);
    },
  );

  test(
    'cinema IPTV overrides labels and publishes only retryable messages',
    () {
      final result = projectCinemaSourceProviders(
        torrents: [row('iptv:one', label: 'Row')],
        statuses: [status('iptv:one', name: 'Status')],
        iptv: [
          const IptvSourceResult(
            'iptv:one',
            'Catalog',
            'Unavailable',
            [],
            retryableFailure: true,
          ),
          const IptvSourceResult('iptv:two', 'Ready', 'No message', []),
        ],
        priority: [],
        aliases: {},
        retrying: {},
      );
      expect(result[1].label, 'IPTV · Catalog');
      expect(result[1].count, 1);
      expect(result[1].message, 'Unavailable');
      expect(result[1].failed, isFalse);
      expect(result[2].count, 0);
      expect(result[2].message, isNull);
    },
  );
}
