import 'dart:async';
import 'package:debrify/screens/debrid_downloads_screen.dart';
import 'package:debrify/screens/torbox/torbox_downloads_screen.dart';
import 'package:debrify/screens/premiumize/premiumize_files_screen.dart';
import 'package:debrify/screens/alldebrid/alldebrid_files_screen.dart';
import 'package:debrify/screens/pikpak/pikpak_files_screen.dart';

import 'package:debrify/features/home/data/home_source_editing_repository.dart';
import 'package:debrify/features/home/presentation/home_source_editor.dart';
import 'package:debrify/features/sources/presentation/local_source_picker.dart';
import 'package:debrify/models/series_source.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SeriesSource source(String name) => SeriesSource(
  torrentHash: name,
  torrentName: name,
  debridService: 'rd',
  debridTorrentId: name,
  boundAt: 1,
);

class Repository extends Fake implements HomeSourceEditingRepository {
  List<SeriesSource> sources = [source('One'), source('Two')];
  final calls = <String>[];
  HomeSourceProviders available = (
    rd: false,
    torbox: false,
    premiumize: false,
    allDebrid: false,
    pikpak: false,
  );
  Completer<void>? gate;
  @override
  Future<List<SeriesSource>?> load(
    String id, {
    required bool Function() isCurrent,
  }) async {
    calls.add('load');
    await gate?.future;
    return isCurrent() ? List.of(sources) : null;
  }

  @override
  Future<bool> replace(
    String id,
    List<SeriesSource> value, {
    required bool Function() isCurrent,
  }) async {
    calls.add('replace');
    await gate?.future;
    if (!isCurrent()) return false;
    sources = List.of(value);
    return true;
  }

  @override
  Future<bool> remove(
    String id,
    SeriesSource value, {
    required bool Function() isCurrent,
  }) async {
    calls.add('remove');
    if (!isCurrent()) return false;
    sources.removeWhere((item) => item.bindingKey == value.bindingKey);
    return true;
  }

  @override
  Future<bool> save(
    String id,
    SeriesSource value, {
    required bool isMovie,
    required bool Function() isCurrent,
  }) async {
    calls.add('save:$isMovie');
    if (!isCurrent()) return false;
    sources = isMovie ? [value] : [...sources, value];
    return true;
  }

  @override
  Future<HomeSourceProviders?> providers({
    required bool Function() isCurrent,
  }) async => isCurrent() ? available : null;
}

class RouteObserver extends NavigatorObserver {
  Route<dynamic>? latest;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    latest = route;
  }
}

class Fixture {
  final observer = RouteObserver();
  final repository = Repository();
  bool current = true, localEnabled = true;
  String? id = 'tt1';
  String type = 'series';
  int refreshes = 0, torrents = 0, keywords = 0, localPicks = 0;
  final messages = <String>[];
  Future<void>? pending;
  late HomeSourceEditor editor;
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) {
            editor = HomeSourceEditor(
              context: context,
              item: StremioMeta(id: 'tt1', type: type, name: 'Show'),
              id: id,
              repository: repository,
              isCurrent: () => current,
              refreshBindings: () async {
                refreshes++;
              },
              showMessage: messages.add,
              openTorrent: (_) => torrents++,
              openKeyword: (_) => keywords++,
              localPicker: LocalSourcePicker(
                androidFolderSelection: false,
                disabledReason: localEnabled ? null : 'Unavailable',
                file: (_, {canContinue}) async => source('Local'),
                movieFolder: (_, {required title, year, canContinue}) async =>
                    source('Local'),
                seriesFolder: (_, {required title, canContinue}) async {
                  localPicks++;
                  return source('Local');
                },
              ),
            );
            return Scaffold(
              body: TextButton(
                onPressed: () => pending = editor.open(),
                child: const Text('Edit'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final provider in [
    'Real-Debrid',
    'TorBox',
    'Premiumize',
    'AllDebrid',
    'PikPak',
  ]) {
    testWidgets(
      '$provider route retains selection mode and guarded save callback',
      (tester) async {
        final f = Fixture();
        f.repository.sources = [];
        f.repository.available = (
          rd: true,
          torbox: true,
          premiumize: true,
          allDebrid: true,
          pikpak: true,
        );
        await f.mount(tester);
        await tester.ensureVisible(find.text(provider));
        await tester.tap(find.text(provider));
        final route = f.observer.latest as MaterialPageRoute;
        final destination = route.builder(f.editor.context);
        Future<void> Function(SeriesSource)? save;
        switch (destination) {
          case DebridDownloadsScreen screen:
            expect(screen.selectSourceMode, isTrue);
            expect(screen.initialSearchQuery, 'Show');
            save =
                screen.onSourceSelected as Future<void> Function(SeriesSource)?;
          case TorboxDownloadsScreen screen:
            expect(screen.selectSourceMode, isTrue);
            expect(screen.initialSearchQuery, 'Show');
            save =
                screen.onSourceSelected as Future<void> Function(SeriesSource)?;
          case PremiumizeFilesScreen screen:
            expect(screen.selectSourceMode, isTrue);
            expect(screen.initialSearchQuery, 'Show');
            save = screen.onSourceSelected;
          case AllDebridFilesScreen screen:
            expect(screen.selectSourceMode, isTrue);
            expect(screen.initialSearchQuery, 'Show');
            save = screen.onSourceSelected;
          case PikPakFilesScreen screen:
            expect(screen.selectSourceMode, isTrue);
            save = screen.onSourceSelected;
          default:
            fail('Unexpected provider route: ${destination.runtimeType}');
        }
        expect(save, isNotNull);
        await save!(source('Cloud'));
        expect(f.refreshes, 1);
        f.current = false;
        await save(source('Late'));
        expect(f.repository.sources.map((s) => s.torrentName), ['Cloud']);
        expect(f.refreshes, 1);
        Navigator.of(f.editor.context).pop();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'series editor retains source labels and saves reorder before refresh',
    (tester) async {
      final f = Fixture();
      await f.mount(tester);
      expect(find.text('Series Sources (2)'), findsOneWidget);
      expect(find.text('Real-Debrid'), findsNWidgets(2));
      f.repository.gate = Completer<void>();
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          // Intentionally exercise the callback retained by the legacy widget.
          // ignore: deprecated_member_use
          .onReorder!(0, 2);
      await tester.pump();
      expect(f.refreshes, 0);
      f.repository.gate!.complete();
      await tester.pumpAndSettle();
      expect(f.repository.sources.map((s) => s.torrentName), ['Two', 'One']);
      expect(f.refreshes, 1);
    },
  );

  testWidgets(
    'movie editor has no reorder list and deleting final source closes it',
    (tester) async {
      final f = Fixture()..type = 'movie';
      f.repository.sources = [source('One')];
      await f.mount(tester);
      expect(find.text('Movie Source'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.text('Change Source'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove source'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(f.refreshes, 1);
    },
  );

  testWidgets('closing during delete reload cannot update disposed dialog', (
    tester,
  ) async {
    final f = Fixture();
    await f.mount(tester);
    f.repository.gate = Completer<void>();
    await tester.tap(find.byTooltip('Remove source').first);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    f.repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(f.refreshes, 0);
  });

  testWidgets('clear all refreshes and closes only the editor', (tester) async {
    final f = Fixture();
    await f.mount(tester);
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(f.repository.sources, isEmpty);
    expect(f.refreshes, 1);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('empty bindings use local picker and guarded series save', (
    tester,
  ) async {
    final f = Fixture();
    f.repository.sources = [];
    await f.mount(tester);
    await tester.tap(find.text('Local File or Folder'));
    await tester.pumpAndSettle();
    expect(f.localPicks, 1);
    expect(f.repository.calls, contains('save:false'));
    expect(f.messages, ['Local source set: Local']);
    expect(f.refreshes, 1);
  });

  testWidgets('no cloud or local provider goes straight to torrent search', (
    tester,
  ) async {
    final f = Fixture()..localEnabled = false;
    f.repository.sources = [];
    await f.mount(tester);
    expect(f.torrents, 1);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('retired picker ignores keyword dispatch', (tester) async {
    final f = Fixture();
    f.repository.sources = [];
    await f.mount(tester);
    f.current = false;
    await tester.tap(find.text('Keyword Search'));
    await tester.pumpAndSettle();
    expect(f.keywords, 0);
  });

  testWidgets(
    'missing identity reports existing message without opening picker',
    (tester) async {
      final f = Fixture()..id = null;
      await f.mount(tester);
      expect(f.messages, ['No IMDb match to pin a source for "Show".']);
      expect(f.repository.calls, isEmpty);
    },
  );
}
