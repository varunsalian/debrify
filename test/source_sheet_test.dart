import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Torrent _source({
  required String name,
  required String source,
  StreamType type = StreamType.torrent,
  String? hash,
  String? coverage,
}) => Torrent(
  rowid: 0,
  infohash: hash ?? 'a' * 40,
  name: name,
  sizeBytes: 2 * 1024 * 1024 * 1024,
  createdUnix: 0,
  seeders: 12,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: source,
  streamType: type,
  coverageType: coverage,
  directUrl: type == StreamType.directUrl
      ? 'https://example.test/stream-$name'
      : null,
);

/// Owns the source list the way the player screen does: [SourceSheet] hands
/// merged lists back through onSourcesMerged and re-reads widget.sources.
class _Host extends StatefulWidget {
  final List<Torrent> initial;
  final SeriesSourceFetcher fetcher;
  const _Host({required this.initial, required this.fetcher});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<Torrent> sources = widget.initial;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: SourceSheet(
      sources: sources,
      currentSourceIndex: 0,
      resolveSource: (_) async => 'https://example.test/resolved',
      onSourceSelected: (_, _) {},
      onClose: () {},
      seriesFetcher: widget.fetcher,
      currentSeason: 1,
      currentEpisode: 2,
      onSourcesMerged: (merged) => setState(() => sources = merged),
    ),
  );
}

void main() {
  testWidgets('groups by add-on while retaining original selection indexes', (
    tester,
  ) async {
    int? selectedIndex;
    final sources = [
      _source(name: 'Current 2160p WEB-DL', source: 'stremio:torrentio'),
      _source(name: 'Comet result 1080p', source: 'stremio:comet'),
      _source(
        name: 'Direct result',
        source: 'stremio:torrentio',
        type: StreamType.directUrl,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceSheet(
            sources: sources,
            currentSourceIndex: 0,
            resolveSource: (_) async => 'https://example.test/resolved',
            onSourceSelected: (index, _) => selectedIndex = index,
            onClose: () {},
          ),
        ),
      ),
    );

    expect(find.text('All add-ons'), findsOneWidget);
    expect(find.text('Torrentio'), findsOneWidget);
    expect(find.text('Comet'), findsOneWidget);
    expect(find.text('DIRECT'), findsOneWidget);

    await tester.tap(find.text('Torrentio'));
    await tester.pump();
    await tester.tap(find.text('Direct result'));
    await tester.pump();

    expect(selectedIndex, 2);
  });

  testWidgets('uses a compact source browser without overflowing in portrait', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: SourceSheet(
          sources: [
            _source(
              name:
                  'A deliberately long complete-series source title 2160p WEB-DL',
              source: 'stremio:torrentio',
            ),
            _source(name: 'Another source 1080p', source: 'stremio:comet'),
          ],
          currentSourceIndex: 0,
          resolveSource: (_) async => 'https://example.test/resolved',
          onSourceSelected: (_, _) {},
          onClose: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('All add-ons'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not move above the first source without load more', (
    tester,
  ) async {
    int? selectedIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: SourceSheet(
          sources: [
            _source(name: 'Current', source: 'stremio:torrentio'),
            _source(name: 'Second', source: 'stremio:comet'),
          ],
          currentSourceIndex: 0,
          resolveSource: (_) async => 'https://example.test/resolved',
          onSourceSelected: (index, _) => selectedIndex = index,
          onClose: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(selectedIndex, 1);
  });

  testWidgets('activates load more from the row above the first source', (
    tester,
  ) async {
    var searches = 0;
    final fetcher = SeriesSourceFetcher(
      season: 1,
      episode: 1,
      searchPacks: (_, _) async {
        searches++;
        return <Torrent>[];
      },
      searchEpisodes: (_, _) async => <Torrent>[],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SourceSheet(
          sources: [_source(name: 'Current', source: 'stremio:torrentio')],
          currentSourceIndex: 0,
          resolveSource: (_) async => 'https://example.test/resolved',
          onSourceSelected: (_, _) {},
          onClose: () {},
          seriesFetcher: fetcher,
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(searches, 1);
  });

  testWidgets('closes from the visible DPAD close control', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SourceSheet(
          sources: [_source(name: 'Current', source: 'stremio:torrentio')],
          currentSourceIndex: 0,
          resolveSource: (_) async => 'https://example.test/resolved',
          onSourceSelected: (_, _) {},
          onClose: () => closed = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('source-sheet-close')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(closed, isTrue);
  });

  testWidgets(
    'a zero-result addon shows as a group whose Fetch merges direct links '
    'instantly, with NO pack probe for a direct-only addon',
    (tester) async {
      var packProbes = 0;
      final fetcher = SeriesSourceFetcher(
        season: 1,
        episode: 2,
        searchPacks: (_, _) async => <Torrent>[],
        searchEpisodes: (_, _) async => <Torrent>[],
        packsFetched: true,
        episodesFetched: true,
        listAddons: () async => const [SourceAddonRef('comet-id', 'Comet')],
        fetchAddonEpisodes: (addonId, s, e) async {
          expect(addonId, 'comet-id');
          expect((s, e), (1, 2));
          return [
            _source(
              name: 'Comet direct S01E02',
              source: 'stremio:comet',
              type: StreamType.directUrl,
              hash: '',
            ),
          ];
        },
        fetchAddonPacks: (_, _) async {
          packProbes++;
          return <Torrent>[];
        },
      );
      await tester.pumpWidget(
        _Host(
          initial: [_source(name: 'Pinned pack', source: 'pinned')],
          fetcher: fetcher,
        ),
      );
      await tester.pump();
      await tester.pump();

      // The placeholder group exists despite zero Comet results.
      expect(find.text('Comet'), findsOneWidget);
      await tester.tap(find.text('Comet'));
      await tester.pump();
      expect(find.text('Fetch results'), findsOneWidget);

      await tester.tap(find.text('Fetch results'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Comet direct S01E02'), findsOneWidget);
      expect(packProbes, 0, reason: 'direct-only results must not probe packs');
    },
  );

  testWidgets(
    'magnet-bearing episode results trigger the lazy season-pack probe',
    (tester) async {
      final fetcher = SeriesSourceFetcher(
        season: 1,
        episode: 2,
        searchPacks: (_, _) async => <Torrent>[],
        searchEpisodes: (_, _) async => <Torrent>[],
        packsFetched: true,
        episodesFetched: true,
        listAddons: () async => const [
          SourceAddonRef('torrentio-id', 'Torrentio'),
        ],
        fetchAddonEpisodes: (_, _, _) async => [
          _source(
            name: 'Torrentio S01E02 1080p',
            source: 'stremio:torrentio',
            hash: 'b' * 40,
          ),
        ],
        fetchAddonPacks: (addonId, s) async {
          expect((addonId, s), ('torrentio-id', 1));
          return [
            _source(
              name: 'Torrentio S01 Complete',
              source: 'stremio:torrentio',
              hash: 'c' * 40,
              coverage: 'seasonPack',
            ),
          ];
        },
      );
      await tester.pumpWidget(
        _Host(
          initial: [_source(name: 'Pinned pack', source: 'pinned')],
          fetcher: fetcher,
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Torrentio'));
      await tester.pump();
      await tester.tap(find.text('Fetch results'));
      // Episode merge lands first; the pack probe is a separate later merge.
      await tester.pump();
      await tester.pump();
      expect(find.text('Torrentio S01E02 1080p'), findsOneWidget);
      await tester.pump();
      await tester.pump();
      expect(find.text('Torrentio S01 Complete'), findsOneWidget);
    },
  );

  testWidgets(
    'same-named addons share ONE group and Fetch asks every one of them',
    (tester) async {
      final fetchedIds = <String>[];
      final fetcher = SeriesSourceFetcher(
        season: 1,
        episode: 2,
        searchPacks: (_, _) async => <Torrent>[],
        searchEpisodes: (_, _) async => <Torrent>[],
        packsFetched: true,
        episodesFetched: true,
        listAddons: () async => const [
          SourceAddonRef('comet-a', 'Comet'),
          SourceAddonRef('comet-b', 'Comet'),
        ],
        fetchAddonEpisodes: (addonId, _, _) async {
          fetchedIds.add(addonId);
          return addonId == 'comet-b'
              ? [
                  _source(
                    name: 'Comet B direct',
                    source: 'stremio:comet',
                    type: StreamType.directUrl,
                    hash: '',
                  ),
                ]
              : <Torrent>[];
        },
      );
      await tester.pumpWidget(
        _Host(
          initial: [_source(name: 'Pinned pack', source: 'pinned')],
          fetcher: fetcher,
        ),
      );
      await tester.pump();
      await tester.pump();

      // One group, not two duplicates.
      expect(find.text('Comet'), findsOneWidget);
      await tester.tap(find.text('Comet'));
      await tester.pump();
      await tester.tap(find.text('Fetch results'));
      await tester.pump();
      await tester.pump();

      expect(fetchedIds, ['comet-a', 'comet-b']);
      expect(find.text('Comet B direct'), findsOneWidget);
    },
  );

  testWidgets('a failed per-addon fetch keeps the row as a retry', (
    tester,
  ) async {
    var calls = 0;
    final fetcher = SeriesSourceFetcher(
      season: 1,
      episode: 2,
      searchPacks: (_, _) async => <Torrent>[],
      searchEpisodes: (_, _) async => <Torrent>[],
      packsFetched: true,
      episodesFetched: true,
      listAddons: () async => const [SourceAddonRef('comet-id', 'Comet')],
      fetchAddonEpisodes: (_, _, _) async {
        calls++;
        return null;
      },
    );
    await tester.pumpWidget(
      _Host(
        initial: [_source(name: 'Pinned pack', source: 'pinned')],
        fetcher: fetcher,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Comet'));
    await tester.pump();
    await tester.tap(find.text('Fetch results'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Fetch failed — try again'), findsOneWidget);
    await tester.tap(find.text('Fetch failed — try again'));
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('uses horizontal DPAD navigation for compact add-ons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? selectedIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: SourceSheet(
          sources: [
            _source(name: 'Torrentio result', source: 'stremio:torrentio'),
            _source(name: 'Current Comet result', source: 'stremio:comet'),
          ],
          currentSourceIndex: 1,
          resolveSource: (_) async => 'https://example.test/resolved',
          onSourceSelected: (index, _) => selectedIndex = index,
          onClose: () {},
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(selectedIndex, 0);
  });
}
