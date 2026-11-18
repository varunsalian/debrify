import 'package:debrify/features/sources/data/webdav_listing_cache.dart';
import 'package:debrify/features/sources/data/webdav_quick_play_search.dart';
import 'package:debrify/features/sources/data/webdav_source_search.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_protocol_client.dart';
import 'package:flutter_test/flutter_test.dart';

const nas = WebDavConfig(
  id: 'nas',
  name: 'NAS',
  baseUrl: 'https://dav.example.com/',
  username: 'me',
  password: 'secret',
);

WebDavItem dir(String path) =>
    WebDavItem(name: path.split('/').last, path: '$path/', isDirectory: true);

WebDavItem file(String path) => WebDavItem(
  name: path.split('/').last,
  path: path,
  isDirectory: false,
  sizeBytes: 2000000000,
);

final movieRules = QuickPlayRules.debrifyDefault(isMovie: true);

void main() {
  late Map<String, List<WebDavItem>> tree;
  late List<String> calls;
  Object? rootFailure;
  Duration? rootDelay;

  setUp(() {
    WebDavSourceSearch.resetUnreachable();
    ProfileRuntime.scope.value = ProfileScope(
      profileId: 'p1',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    calls = [];
    rootFailure = null;
    rootDelay = null;
    tree = {
      '': [dir('Movies'), file('Dune.mkv')],
      'Movies/': [dir('Movies/Dune'), dir('Movies/Dune (2021)')],
      'Movies/Dune/': [file('Movies/Dune/dune-no-year.mkv')],
      'Movies/Dune (2021)/': [file('Movies/Dune (2021)/Dune.2021.mkv')],
    };
  });

  WebDavSourceSearch engine({
    WebDavSearchLimits limits = WebDavQuickPlaySearch.limits,
  }) => WebDavSourceSearch(
    servers: () async => [nas],
    enabled: () async => true,
    cache: WebDavListingCache(),
    limits: limits,
    checkAccess: (_) async {},
    listFolder: (config, path) async {
      calls.add(path);
      if (path.isEmpty && rootDelay != null) {
        await Future<void>.delayed(rootDelay!);
      }
      if (path.isEmpty && rootFailure != null) throw rootFailure!;
      return tree[path] ?? const [];
    },
  );

  Future<List<String>> play(
    QuickPlayRules rules, {
    WebDavSourceSearch? using,
    List<String?>? notes,
  }) async => [
    for (final row in await WebDavQuickPlaySearch.search(
      'tt1160419',
      'Dune',
      '2021',
      true,
      null,
      null,
      rules,
      null,
      onNote: notes?.add,
      engine: using ?? engine(),
    ))
      row.name,
  ];

  test(
    'an automatic movie pick needs the year; yearless matches stay out',
    () async {
      expect(await play(movieRules), ['Dune.2021.mkv']);
    },
  );

  test('rules that exclude direct links or addons skip WebDAV', () async {
    expect(await play(movieRules.copyWith(allowDirectLinks: false)), isEmpty);
    expect(
      await play(
        movieRules.copyWith(sourceMode: QuickPlaySourceMode.torrentsOnly),
      ),
      isEmpty,
    );
    expect(calls, isEmpty);
  });

  test('a server that did not answer is skipped for a while', () async {
    rootFailure = const WebDavException(
      kind: WebDavErrorKind.network,
      message: 'down',
    );
    expect(await play(movieRules), isEmpty);
    expect(calls, ['']);
    rootFailure = null;
    expect(await play(movieRules), isEmpty);
    expect(calls, [''], reason: 'skipped while recently unreachable');

    // The Sources page still tries it, and success clears the memory.
    final statuses = await engine().search(
      const AdvancedSearchSelection(
        imdbId: 'tt1160419',
        isSeries: false,
        title: 'Dune',
        year: '2021',
      ),
      onStatus: (_) {},
      onRows: (_, _) {},
      shouldContinue: () => true,
    );
    expect(statuses.single.phase.name, 'done');
    expect(await play(movieRules), ['Dune.2021.mkv']);
  });

  test('a wrong password is not treated as offline', () async {
    rootFailure = const WebDavException(
      kind: WebDavErrorKind.authentication,
      message: 'denied',
    );
    await play(movieRules);
    await play(movieRules);
    expect(calls, ['', '']);
  });

  test('a slow server shows a loader note, cleared when done', () async {
    rootDelay = const Duration(milliseconds: 60);
    final notes = <String?>[];
    await play(
      movieRules,
      notes: notes,
      using: engine(
        limits: const WebDavSearchLimits(slowAfter: Duration(milliseconds: 10)),
      ),
    );
    expect(notes.first, contains('Looking through WebDAV · NAS'));
    expect(notes.last, isNull);
  });

  test('a short grace stops the walk and clears its loader note', () async {
    rootDelay = const Duration(seconds: 3); // Slower than the grace.
    final notes = <String?>[];
    final run = WebDavQuickPlaySearch.start(
      'tt1160419',
      'Dune',
      '2021',
      true,
      null,
      null,
      movieRules,
      null,
      onNote: notes.add,
      engine: engine(
        limits: const WebDavSearchLimits(slowAfter: Duration(milliseconds: 10)),
      ),
    );
    final watch = Stopwatch()..start();
    expect(await WebDavQuickPlaySearch.settle(run, haveOthers: true), isEmpty);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    // The slow note appeared, and stopping cleared it.
    expect(notes.first, contains('Looking through WebDAV · NAS'));
    expect(notes.last, isNull);
    final count = notes.length;
    await run.rows;
    // Nothing more after the stop: no new note, no further folders.
    expect(notes, hasLength(count));
    expect(calls, ['']);
  });

  test('with nothing else found, the full (bounded) budget applies', () async {
    final run = WebDavQuickPlaySearch.start(
      'tt1160419',
      'Dune',
      '2021',
      true,
      null,
      null,
      movieRules,
      null,
      engine: engine(),
    );
    final rows = await WebDavQuickPlaySearch.settle(run, haveOthers: false);
    expect(rows.map((r) => r.name), ['Dune.2021.mkv']);
  });
}
