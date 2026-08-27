import 'dart:async';

import 'package:debrify/core/cloud/listing.dart';
import 'package:debrify/features/pikpak/view_model.dart';
import 'package:debrify/features/pikpak/view_state.dart';
import 'package:debrify/features/pikpak/data/repository.dart';
import 'package:debrify/features/pikpak/models/file.dart';
import 'package:debrify/features/pikpak/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

const mb = 1024 * 1024;

/// Stands in for SeriesParser, which domain will not import.
int? testSeasonOf(String name) => int.tryParse(
  RegExp(r'[Ss](\d+)[Ee]\d+').firstMatch(name)?.group(1) ?? '',
);

PikPakFile file(String name, {String? id, int size = 700 * mb}) => PikPakFile(
  id: id ?? name,
  name: name,
  kind: PikPakKind.file,
  mimeType: 'video/x-matroska',
  size: size,
  phase: PikPakPhase.complete,
);

PikPakFile folder(String name, {String? id}) => PikPakFile(
  id: id ?? name,
  name: name,
  kind: PikPakKind.folder,
  mimeType: '',
  size: 0,
  phase: PikPakPhase.complete,
);

PikPakFile other(String name) => PikPakFile(
  id: name,
  name: name,
  kind: PikPakKind.file,
  mimeType: 'text/plain',
  size: 1000,
  phase: PikPakPhase.complete,
);

void main() {
  late _FakeDrive drive;
  late List<PikPakBrowseEffect> effects;

  setUp(() {
    drive = _FakeDrive();
    effects = [];
  });

  PikPakBrowseViewModel controllerFor({
    bool preferTrash = true,
    String? restrictedRootId,
  }) {
    final c = PikPakBrowseViewModel(
      drive: drive,
      preferTrash: () async => preferTrash,
      seasonOf: testSeasonOf,
      restrictedRootId: restrictedRootId,
      restrictedRootName: 'Kids',
    );
    c.listenForEffects(effects.add);
    return c;
  }

  group('load', () {
    test('populates the folder and reports whether more remains', () async {
      drive.pages = [
        (files: [folder('Season 1'), file('ep1.mkv')], nextPageToken: 'p2'),
      ];
      final c = controllerFor();

      await c.load();

      expect(c.state.visible.map((f) => f.name), ['Season 1', 'ep1.mkv']);
      expect(c.state.hasMore, isTrue);
      expect(c.state.isLoading, isFalse);
      expect(c.state.initialLoad, isFalse);
    });

    test('applies the size filter, and folders survive it', () async {
      drive.pages = [
        (
          files: [folder('Season 1'), file('sample.mkv', size: 5 * mb), file('ep.mkv')],
          nextPageToken: null,
        ),
      ];
      final c = controllerFor();

      await c.load();

      expect(c.state.visible.map((f) => f.name), ['Season 1', 'ep.mkv']);
    });

    test('a failure surfaces as state, not an exception', () async {
      drive.error = StateError('network down');
      final c = controllerFor();

      await c.load();

      expect(c.state.error, contains('network down'));
      expect(c.state.isLoading, isFalse);
      expect(c.state.initialLoad, isFalse);
    });

    test('asks the view to move focus once a load lands', () async {
      drive.pages = [(files: [file('ep.mkv')], nextPageToken: null)];
      final c = controllerFor();

      await c.load();

      expect(effects, contains(isA<PikPakFocusFirstItem>()));
    });

    test('a second load supersedes the first, so a stale page cannot land',
        () async {
      final first = Completer<({List<PikPakFile> files, String? nextPageToken})>();
      drive.pending = first;
      final c = controllerFor();

      final stale = c.load();
      drive.pending = null;
      drive.pages = [(files: [file('fresh.mkv')], nextPageToken: null)];
      await c.refresh();

      first.complete((files: [file('stale.mkv')], nextPageToken: null));
      await stale;

      expect(c.state.visible.map((f) => f.name), ['fresh.mkv']);
    });

    test('a load in flight does not block the next one', () async {
      final gate = Completer<({List<PikPakFile> files, String? nextPageToken})>();
      drive.pending = gate;
      final c = controllerFor();

      final a = c.load();
      final b = c.load();
      gate.complete((files: [file('ep.mkv')], nextPageToken: null));
      await Future.wait([a, b]);

      // Both were issued - a Refresh must never be silently swallowed by a
      // slow load already running - and the token guard decides which lands.
      expect(drive.listCalls, 2);
      expect(c.state.visible.map((f) => f.name), ['ep.mkv']);
    });
  });

  group('restricted profile', () {
    test('starts pinned to its folder and Back will not leave it', () async {
      drive.pages = [(files: [file('ep.mkv')], nextPageToken: null)];
      final c = controllerFor(restrictedRootId: 'kids-folder');

      await c.load();

      expect(c.state.folderId, 'kids-folder');
      expect(c.state.atRestrictedRoot, isTrue);
      expect(await c.goUp(), isFalse);
      expect(c.state.folderId, 'kids-folder');
    });

    test('a deleted pinned folder is reported, not silently replaced by root',
        () async {
      drive.error = StateError('not found');
      drive.restrictedFolderExists = false;
      final c = controllerFor(restrictedRootId: 'kids-folder');

      await c.load();

      expect(effects, contains(isA<PikPakRestrictedFolderLost>()));
      expect(c.state.error, isEmpty);
    });

    test('a plain network error on the pinned folder is just an error', () async {
      drive.error = StateError('timeout');
      drive.restrictedFolderExists = true;
      final c = controllerFor(restrictedRootId: 'kids-folder');

      await c.load();

      expect(effects.whereType<PikPakRestrictedFolderLost>(), isEmpty);
      expect(c.state.error, contains('timeout'));
    });
  });

  group('paging', () {
    test('appends the next page', () async {
      drive.pages = [
        (files: [file('a.mkv')], nextPageToken: 'p2'),
        (files: [file('b.mkv')], nextPageToken: null),
      ];
      final c = controllerFor();

      await c.load();
      await c.loadMore();

      expect(c.state.visible.map((f) => f.name), ['a.mkv', 'b.mkv']);
      expect(c.state.hasMore, isFalse);
    });

    test('does nothing when the folder has no more pages', () async {
      drive.pages = [(files: [file('a.mkv')], nextPageToken: null)];
      final c = controllerFor();

      await c.load();
      await c.loadMore();

      expect(drive.listCalls, 1);
    });

    test('a failed page keeps what was already shown', () async {
      drive.pages = [(files: [file('a.mkv')], nextPageToken: 'p2')];
      final c = controllerFor();
      await c.load();

      drive.error = StateError('page failed');
      await c.loadMore();

      expect(c.state.visible.map((f) => f.name), ['a.mkv']);
      expect(c.state.isLoadingMore, isFalse);
      expect(
        effects.whereType<PikPakNotify>().last.message,
        contains('Failed to load more'),
      );
    });
  });

  group('navigation', () {
    test('walking into a folder loads it and deepens the path', () async {
      drive.pages = [
        (files: [folder('Season 1', id: 's1')], nextPageToken: null),
        (files: [file('ep1.mkv')], nextPageToken: null),
      ];
      final c = controllerFor();
      await c.load();

      await c.openFolder(c.state.visible.first);

      expect(c.state.folderId, 's1');
      expect(c.state.folderName, 'Season 1');
      expect(c.state.visible.map((f) => f.name), ['ep1.mkv']);
    });

    test('Back returns false at the root so the view can pop the route',
        () async {
      final c = controllerFor();

      expect(await c.goUp(), isFalse);
    });

    test('a season group is entered without a fetch', () async {
      final group = PikPakFile.seasonGroup(
        season: 1,
        files: [file('ep1.mkv'), file('ep2.mkv')],
      );
      final c = controllerFor();

      c.openVirtualFolder(group);

      expect(c.state.inVirtualFolder, isTrue);
      expect(c.state.visible.map((f) => f.name), ['ep1.mkv', 'ep2.mkv']);
      expect(drive.listCalls, 0);
    });

    test('leaving a season group does not reload either', () async {
      final c = controllerFor();
      c.openVirtualFolder(
        PikPakFile.seasonGroup(season: 1, files: [file('ep1.mkv')]),
      );

      expect(await c.goUp(), isTrue);
      expect(c.state.inVirtualFolder, isFalse);
      expect(drive.listCalls, 0);
    });
  });

  group('view mode', () {
    test('sortedAZ orders the loaded folder', () async {
      drive.pages = [
        (files: [file('10. b.mkv'), file('2. a.mkv')], nextPageToken: null),
      ];
      final c = controllerFor();
      await c.load();

      await c.setViewMode(CloudViewMode.sortedAZ);

      expect(c.state.visible.map((f) => f.name), ['2. a.mkv', '10. b.mkv']);
    });

    test('series arrange scans the whole subtree, not the loaded page', () async {
      drive.pages = [
        (files: [folder('pack', id: 'pack')], nextPageToken: null),
        (files: const [], nextPageToken: null),
      ];
      drive.recursive = [
        file('Show S01E01.mkv'),
        file('Show S02E01.mkv'),
        file('Show S01E02.mkv'),
      ];
      final c = controllerFor();
      await c.load();
      await c.openFolder(c.state.files.first);

      await c.setViewMode(CloudViewMode.seriesArrange);

      expect(drive.recursiveCalls, 1);
      expect(c.state.visible.map((f) => f.name), ['Season 1', 'Season 2']);
      expect(c.state.visible.first.children, hasLength(2));
    });

    test('a failed scan falls back to sorted and says so', () async {
      drive.pages = [
        (files: [folder('pack', id: 'pack')], nextPageToken: null),
        (files: [file('b.mkv'), file('a.mkv')], nextPageToken: null),
      ];
      final c = controllerFor();
      await c.load();
      await c.openFolder(c.state.files.first);

      drive.recursiveError = StateError('scan failed');
      await c.setViewMode(CloudViewMode.seriesArrange);

      expect(c.state.viewMode, CloudViewMode.sortedAZ);
      expect(c.state.visible.map((f) => f.name), ['a.mkv', 'b.mkv']);
      expect(
        effects.whereType<PikPakNotify>().last.message,
        contains('sorted instead'),
      );
    });

    test('the mode is remembered per folder', () async {
      drive.pages = [
        (files: [folder('one', id: 'one')], nextPageToken: null),
        (files: const [], nextPageToken: null),
      ];
      final c = controllerFor();
      await c.load();
      await c.setViewMode(CloudViewMode.sortedAZ);
      await c.openFolder(folder('one', id: 'one'));

      expect(c.state.viewMode, CloudViewMode.raw);
    });
  });

  group('selection', () {
    Future<PikPakBrowseViewModel> loaded() async {
      drive.pages = [
        (
          files: [folder('Season 1'), file('a.mkv'), file('b.mkv')],
          nextPageToken: null,
        ),
      ];
      final c = controllerFor();
      await c.load();
      return c;
    }

    test('folders are not selectable — PikPak deletes their contents too',
        () async {
      final c = await loaded();

      c.toggleSelectAll();

      expect(c.state.selectedIds, {'a.mkv', 'b.mkv'});
    });

    test('select all toggles back off', () async {
      final c = await loaded();

      c.toggleSelectAll();
      c.toggleSelectAll();

      expect(c.state.selectedIds, isEmpty);
    });

    test('individual toggling adds and removes', () async {
      final c = await loaded();

      c.toggleSelected('a.mkv');
      c.toggleSelected('b.mkv');
      c.toggleSelected('a.mkv');

      expect(c.state.selectedIds, {'b.mkv'});
    });

    test('navigating away drops the selection', () async {
      final c = await loaded();
      c.toggleSelecting();
      c.toggleSelected('a.mkv');

      await c.openFolder(folder('Season 1'));

      expect(c.state.selecting, isFalse);
      expect(c.state.selectedIds, isEmpty);
    });
  });

  group('delete', () {
    test('honours the trash preference and refreshes', () async {
      drive.pages = [
        (files: [file('a.mkv')], nextPageToken: null),
        (files: const [], nextPageToken: null),
      ];
      final c = controllerFor(preferTrash: true);
      await c.load();

      await c.delete(['a.mkv']);

      expect(drive.trashed, ['a.mkv']);
      expect(drive.deleted, isEmpty);
      expect(drive.listCalls, 2);
      expect(effects.whereType<PikPakNotify>().last.message, 'Moved to trash');
    });

    test('deletes permanently when that is the preference', () async {
      drive.pages = [(files: const [], nextPageToken: null)];
      final c = controllerFor(preferTrash: false);

      await c.delete(['a.mkv', 'b.mkv']);

      expect(drive.deleted, ['a.mkv', 'b.mkv']);
      expect(
        effects.whereType<PikPakNotify>().first.message,
        'Deleted 2 items',
      );
    });

    test('a refusal is reported and nothing is reloaded', () async {
      drive.deleteSucceeds = false;
      final c = controllerFor();

      await c.delete(['a.mkv']);

      final notify = effects.whereType<PikPakNotify>().last;
      expect(notify.isError, isTrue);
      expect(drive.listCalls, 0);
    });

    test('an empty selection does nothing at all', () async {
      final c = controllerFor();

      await c.delete([]);

      expect(drive.trashed, isEmpty);
      expect(effects, isEmpty);
    });
  });

  group('search', () {
    test('searches the whole subtree, not just the loaded page', () async {
      drive.pages = [
        (files: [folder('pack', id: 'pack')], nextPageToken: null),
        (files: const [], nextPageToken: null),
      ];
      drive.recursive = [file('The Wire S01E01.mkv'), file('Other.mkv')];
      final c = controllerFor();
      await c.load();
      await c.openFolder(folder('pack', id: 'pack'));

      await c.search('wire');

      expect(c.state.results.map((f) => f.name), ['The Wire S01E01.mkv']);
    });

    test('an empty query clears the results', () async {
      final c = controllerFor();

      await c.search('   ');

      expect(c.state.results, isEmpty);
      expect(drive.recursiveCalls, 0);
    });

    test('closing search forgets the query', () async {
      drive.pages = [(files: [file('a.mkv')], nextPageToken: null)];
      final c = controllerFor();
      await c.load();
      c.openSearch();
      await c.search('a');

      c.closeSearch();

      expect(c.state.searching, isFalse);
      expect(c.state.query, isEmpty);
      expect(c.state.visible.map((f) => f.name), ['a.mkv']);
    });
  });

  group('lifecycle', () {
    test('effects raised before the view attaches are held, not dropped',
        () async {
      final c = PikPakBrowseViewModel(
        drive: drive,
        preferTrash: () async => true,
        seasonOf: testSeasonOf,
      );
      drive.pages = [(files: const [], nextPageToken: null)];

      await c.load();
      final seen = <PikPakBrowseEffect>[];
      c.listenForEffects(seen.add);

      expect(seen, contains(isA<PikPakFocusFirstItem>()));
    });

    test('a response landing after disposal changes nothing', () async {
      final gate = Completer<({List<PikPakFile> files, String? nextPageToken})>();
      drive.pending = gate;
      final c = controllerFor();

      final pending = c.load();
      c.dispose();
      gate.complete((files: [file('late.mkv')], nextPageToken: null));
      await pending;

      expect(c.state.visible, isEmpty);
      expect(effects, isEmpty);
    });
  });

  group('groupIntoSeasons', () {
    test('leaves real folders and non-video files alone', () {
      final out = groupIntoSeasons([
        folder('Extras'),
        file('Show S01E01.mkv'),
        other('readme.txt'),
      ], seasonOf: testSeasonOf);

      expect(out.map((f) => f.name), ['Extras', 'Season 1', 'readme.txt']);
    });

    test('an episode naming no season is still shown, under season 1', () {
      final out = groupIntoSeasons(
        [file('mystery.mkv')],
        seasonOf: testSeasonOf,
      );

      expect(out.single.name, 'Season 1');
      expect(out.single.children.single.name, 'mystery.mkv');
    });

    test('a listing with no videos is returned untouched', () {
      final items = [folder('a'), other('b.txt')];

      expect(groupIntoSeasons(items, seasonOf: testSeasonOf), same(items));
    });

    test('seasons come out in numeric order', () {
      final out = groupIntoSeasons([
        file('Show S10E01.mkv'),
        file('Show S02E01.mkv'),
      ], seasonOf: testSeasonOf);

      expect(out.map((f) => f.name), ['Season 2', 'Season 10']);
    });
  });
}

class _FakeDrive implements PikPakRepository {
  List<({List<PikPakFile> files, String? nextPageToken})> pages = [];
  List<PikPakFile> recursive = [];
  Object? error;
  Object? recursiveError;
  Completer<({List<PikPakFile> files, String? nextPageToken})>? pending;
  bool deleteSucceeds = true;
  bool restrictedFolderExists = true;

  int listCalls = 0;
  int recursiveCalls = 0;
  final List<String> trashed = [];
  final List<String> deleted = [];

  @override
  Future<({List<PikPakFile> files, String? nextPageToken})> listFiles({
    String? parentId,
    int limit = 50,
    String? pageToken,
  }) {
    listCalls++;
    final held = pending;
    if (held != null) return held.future;
    if (error != null) {
      final e = error!;
      error = null;
      return Future.error(e);
    }
    if (pages.isEmpty) {
      return Future.value((files: <PikPakFile>[], nextPageToken: null));
    }
    return Future.value(pages.removeAt(0));
  }

  @override
  Future<List<PikPakFile>> listFilesRecursive({
    required String folderId,
    int limit = 50,
    bool includePaths = false,
  }) {
    recursiveCalls++;
    if (recursiveError != null) return Future.error(recursiveError!);
    return Future.value(recursive);
  }

  @override
  Future<bool> batchTrashFiles(List<String> fileIds) {
    trashed.addAll(fileIds);
    return Future.value(deleteSucceeds);
  }

  @override
  Future<bool> batchDeleteFiles(List<String> fileIds) {
    deleted.addAll(fileIds);
    return Future.value(deleteSucceeds);
  }

  @override
  Future<bool> verifyRestrictedFolderExists() =>
      Future.value(restrictedFolderExists);

  @override
  Future<PikPakFile> getFileDetails(String fileId) =>
      Future.value(file(fileId));

  @override
  Future<PikPakTask> addOfflineDownload(
    String magnetLink, {
    String? parentFolderId,
  }) => Future.value(
    const PikPakTask(
      id: 't1',
      name: 'added',
      fileId: 'f1',
      phase: PikPakPhase.running,
    ),
  );

  @override
  Future<PikPakTask> getTaskStatus(String taskId) => Future.value(
    const PikPakTask(
      id: 't1',
      name: 'added',
      fileId: 'f1',
      phase: PikPakPhase.complete,
    ),
  );

  @override
  Future<bool> isAuthenticated() => Future.value(true);

  @override
  Future<String?> getEmail() => Future.value('someone@example.test');
}
