import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/screens/debrid_downloads_screen.dart';
import 'package:debrify/screens/torbox/torbox_downloads_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// G4-5 origin pin for the chrome cluster the TorBox and Real-Debrid cloud
/// files screens each carry privately: the selection bar, the torrent search
/// bar, the view-mode dropdown, the in-folder file search bar and its result
/// card, plus the `_queryMatchesInitialTitle` gate that guards submitting a
/// torrent search in select-source mode.
///
/// The pin drives the real screens. Network is answered by a canned
/// `HttpOverrides` (copied from `cloud_folder_sort_origin_pin_test.dart`); the
/// only other seam is `SharedPreferences.setMockInitialValues`.
///
/// Quirks pinned here (keep, do not "fix"):
/// * The selection bar reads "$count selected" with the button toggling
///   between "Select All" and "Deselect All"; Delete is disabled at zero.
/// * The two hosts label their root sections differently — TorBox
///   "Torrents"/"Web Downloads", Real-Debrid "Torrent Downloads"/"DDL
///   Downloads" — and that difference is user-visible, so it stays.
/// * The torrent search bar hints "Search your torrents..." and only shows
///   its clear button while the field has text. Clearing it returns focus to
///   the field and empties the query without leaving the bar.
/// * `_queryMatchesInitialTitle` only gates when the host is BOTH in
///   select-source mode AND hidden from nav. Its tokens are the initial title
///   minus {the, a, an} and minus one-character tokens; if that leaves
///   nothing, the unfiltered tokens are used. A query matches when it
///   *contains* any token, so "prematrixed" matches "The Matrix".
/// * The view-mode dropdown is labelled "View Mode" and offers exactly "Raw"
///   and "Sort (A-Z)" — the series arrangement is built but not exposed.
/// * The file search bar hints "Search all files...", shows "Type to search
///   all files" before input and "No files found" for a miss. A hit renders a
///   card with the file name, its ' / '-joined parent path, and its size.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Relative paths in API order. The folder gives the search a non-empty
  /// parent path to render; the two loose files make Sort (A-Z) observable.
  const rawPaths = <String>[
    'Season 2/s02e01.mkv',
    'zeta.mkv',
    'Alpha.mkv',
  ];
  const rawOrder = <String>['Season 2', 'zeta.mkv', 'Alpha.mkv'];
  const sortedOrder = <String>['Season 2', 'Alpha.mkv', 'zeta.mkv'];

  late HttpOverrides? previousOverrides;
  late _CannedHttp http;

  setUp(() {
    previousOverrides = HttpOverrides.current;
  });

  tearDown(() {
    HttpOverrides.global = previousOverrides;
  });

  Future<void> useLargeViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  /// Opens [screen] on the real clock. The credential vault's AES and the
  /// hosts' key-poll loops never settle under the widget-test fake clock, so
  /// the open runs inside [WidgetTester.runAsync]; the interactions that
  /// follow are synchronous and run on the fake clock as usual.
  Future<void> openOnRealClock(
    WidgetTester tester,
    Widget screen,
    List<String> names,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: screen));
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (names.every((n) => find.text(n).evaluate().isNotEmpty)) return;
      }
    });
    await tester.pump();
    final missing = names.where((n) => find.text(n).evaluate().isEmpty);
    expect(
      missing,
      isEmpty,
      reason:
          'Rows never rendered. Requests: ${http.requests.join(', ')}. '
          'Visible: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().join(' | ')}',
    );
  }

  List<String> renderedOrder(WidgetTester tester, List<String> names) {
    final rows = <(String, double)>[
      for (final n in names) (n, tester.getTopLeft(find.text(n)).dy),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final r in rows) r.$1];
  }

  /// Both hosts arm a 10s deep-link timeout when opened with a target; it
  /// must stay silent because the torrent did open.
  Future<void> drainDeepLinkTimer(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 11));
  }

  // -- selection bar ------------------------------------------------------

  Future<void> pinSelectionBar(WidgetTester tester) async {
    // Not in selection mode yet: no bar.
    expect(find.text('0 selected'), findsNothing);

    await tester.tap(find.byIcon(Icons.checklist_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('0 selected'), findsOneWidget);
    expect(find.text('Select All'), findsOneWidget);
    expect(find.text('Deselect All'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
    // Delete is disabled while nothing is selected.
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete')).onPressed,
      isNull,
    );

    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Deselect All'), findsOneWidget);
    expect(find.text('Select All'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete')).onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Deselect All'));
    await tester.pumpAndSettle();

    expect(find.text('0 selected'), findsOneWidget);
    expect(find.text('Select All'), findsOneWidget);
  }

  // -- torrent search bar -------------------------------------------------

  Future<void> pinTorrentSearchBar(
    WidgetTester tester, {
    required String initialTitle,
  }) async {
    expect(find.text('Search your torrents...'), findsOneWidget);
    final field = find.widgetWithText(TextField, initialTitle);
    expect(field, findsOneWidget, reason: 'prefilled with the initial query');
    // The clear button rides alongside the field only while it has text.
    expect(find.byIcon(Icons.clear_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear_rounded));
    await tester.pumpAndSettle();
    expect(find.text(initialTitle), findsNothing);
    expect(find.byIcon(Icons.clear_rounded), findsNothing);
    expect(find.text('Search your torrents...'), findsOneWidget);
  }

  /// Drives the `_queryMatchesInitialTitle` gate through the real submit path.
  Future<void> pinInitialTitleGate(
    WidgetTester tester, {
    required String initialTitle,
  }) async {
    Future<void> submit(String query) async {
      await tester.enterText(find.byType(TextField).first, query);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    final refusal = 'Search must include part of "$initialTitle"';

    // No token of "The Matrix" ("matrix" — "the" is a stopword) is contained
    // in this query, so the submit is refused.
    await submit('zzz nothing');
    expect(find.text(refusal), findsOneWidget);

    // Substring, not word, matching: "prematrixed" contains "matrix".
    await submit('prematrixed');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text(refusal), findsNothing);
  }

  // -- view-mode dropdown -------------------------------------------------

  Future<void> pinViewModeDropdown(WidgetTester tester) async {
    expect(find.text('View Mode'), findsWidgets);
    final dropdown = find.byWidgetPredicate((w) => w is DropdownButtonFormField);
    expect(dropdown, findsOneWidget, reason: 'view-mode dropdown');

    expect(renderedOrder(tester, rawOrder), rawOrder);

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    // Only two choices are offered; the series arrangement is not exposed.
    expect(find.text('Raw'), findsWidgets);
    expect(find.text('Sort (A-Z)'), findsWidgets);
    expect(find.text('Series Arrange'), findsNothing);

    await tester.tap(find.text('Sort (A-Z)').last);
    await tester.pumpAndSettle();
    expect(renderedOrder(tester, sortedOrder), sortedOrder);
  }

  // -- file search bar + result card --------------------------------------

  /// [resultsReachable] is false for TorBox, whose `_performSearch` reads
  /// `_navigationStack.first.node`. That first entry is the state pushed on
  /// the way *into* the torrent — always `node: null` — so the TorBox file
  /// search can never produce a hit. Preserved as-is: pinning the bug is what
  /// stops a refactor from silently "fixing" or worsening it.
  Future<void> pinFileSearch(
    WidgetTester tester, {
    required bool resultsReachable,
  }) async {
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.text('Search all files...'), findsOneWidget);
    expect(find.text('Type to search all files'), findsOneWidget);
    // The clear button only exists once the field has text.
    expect(find.byIcon(Icons.clear), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'nosuchfile');
    await tester.pumpAndSettle();
    expect(find.text('No files found'), findsOneWidget);
    expect(find.byIcon(Icons.clear), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'e01');
    await tester.pumpAndSettle();

    if (!resultsReachable) {
      expect(find.text('No files found'), findsOneWidget);
      expect(find.text('s02e01.mkv'), findsNothing);
    } else {
      // The card carries the file name, its ' / '-joined parent path, and
      // size, behind a play affordance.
      expect(find.text('s02e01.mkv'), findsOneWidget);
      expect(find.text('Season 2'), findsOneWidget);
      expect(find.text('100 B'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    }

    // Clearing empties the results and returns the placeholder.
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('Type to search all files'), findsOneWidget);
    expect(find.text('s02e01.mkv'), findsNothing);
  }

  // =======================================================================
  // TorBox
  // =======================================================================

  group('TorBox TorboxDownloadsScreen', () {
    Map<String, dynamic> torrentJson() => {
      'id': 7,
      'hash': 'pinhash',
      'name': 'Chrome Pin',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
      'download_state': 'completed',
      'download_finished': true,
      'download_present': true,
      'cached': true,
      'files': [
        for (var i = 0; i < rawPaths.length; i++)
          {
            'id': i + 1,
            'name': rawPaths[i],
            'short_name': rawPaths[i].split('/').last,
            'size': 100,
          },
      ],
    };

    void seed({bool hiddenFromNav = false}) {
      SharedPreferences.setMockInitialValues({
        'torbox_api_key': 'pin-key',
        'torbox_hidden_from_nav': hiddenFromNav,
      });
      http = _CannedHttp({
        '/v1/api/torrents/mylist': jsonEncode({
          'success': true,
          'data': [torrentJson()],
        }),
        '/v1/api/webdl/mylist': jsonEncode({'success': true, 'data': []}),
      });
      HttpOverrides.global = http;
    }

    testWidgets('root chrome: view selector labels and the selection bar', (
      tester,
    ) async {
      seed();
      await useLargeViewport(tester);
      await openOnRealClock(
        tester,
        const TorboxDownloadsScreen(isPushedRoute: true),
        const ['Chrome Pin'],
      );

      expect(find.text('Torrents'), findsOneWidget);
      expect(find.text('Web Downloads'), findsOneWidget);

      await pinSelectionBar(tester);
    });

    testWidgets('torrent search bar and the initial-title submit gate', (
      tester,
    ) async {
      seed(hiddenFromNav: true);
      await useLargeViewport(tester);
      await openOnRealClock(
        tester,
        const TorboxDownloadsScreen(
          isPushedRoute: true,
          selectSourceMode: true,
          initialSearchQuery: 'The Matrix',
        ),
        const ['Search your torrents...'],
      );

      await pinInitialTitleGate(tester, initialTitle: 'The Matrix');
    });

    testWidgets('torrent search bar clears without leaving the bar', (
      tester,
    ) async {
      seed();
      await useLargeViewport(tester);
      await openOnRealClock(
        tester,
        const TorboxDownloadsScreen(
          isPushedRoute: true,
          selectSourceMode: true,
          initialSearchQuery: 'The Matrix',
        ),
        const ['Search your torrents...'],
      );

      await pinTorrentSearchBar(tester, initialTitle: 'The Matrix');
    });

    testWidgets('folder chrome: view-mode dropdown, file search, result card', (
      tester,
    ) async {
      seed();
      await useLargeViewport(tester);
      await openOnRealClock(
        tester,
        TorboxDownloadsScreen(
          isPushedRoute: true,
          initialTorrentToOpen: TorboxTorrent.fromJson(torrentJson()),
        ),
        rawOrder,
      );

      await pinViewModeDropdown(tester);
      await pinFileSearch(tester, resultsReachable: false);

      await drainDeepLinkTimer(tester);
      expect(
        find.text('Failed to open torrent. Please try again.'),
        findsNothing,
      );
    });
  });

  // =======================================================================
  // Real-Debrid
  // =======================================================================

  group('Real-Debrid DebridDownloadsScreen', () {
    const rdBase = '/rest/1.0';

    Map<String, dynamic> torrentInfo() => {
      'id': 't1',
      'filename': 'Chrome Pin',
      'status': 'downloaded',
      'files': [
        for (var i = 0; i < rawPaths.length; i++)
          {'id': i + 1, 'path': '/${rawPaths[i]}', 'bytes': 100, 'selected': 1},
      ],
      // One link per selected file so this is not read as a RAR archive.
      'links': [
        for (var i = 0; i < rawPaths.length; i++)
          'https://real-debrid.invalid/d/$i',
      ],
    };

    RDTorrent torrent() => RDTorrent(
      id: 't1',
      filename: 'Chrome Pin',
      hash: 'pinhash',
      bytes: 300,
      host: 'real-debrid.com',
      split: 0,
      progress: 100,
      status: 'downloaded',
      added: '2026-01-01',
      links: [
        for (var i = 0; i < rawPaths.length; i++)
          'https://real-debrid.invalid/d/$i',
      ],
    );

    void seed({bool hiddenFromNav = false, bool listTorrent = false}) {
      SharedPreferences.setMockInitialValues({
        'real_debrid_api_key': 'pin-key',
        'real_debrid_hidden_from_nav': hiddenFromNav,
      });
      http = _CannedHttp({
        '$rdBase/torrents': listTorrent
            ? jsonEncode([
                {
                  'id': 't1',
                  'filename': 'Chrome Pin',
                  'hash': 'pinhash',
                  'bytes': 300,
                  'host': 'real-debrid.com',
                  'split': 0,
                  'progress': 100,
                  'status': 'downloaded',
                  'added': '2026-01-01',
                  'links': ['https://real-debrid.invalid/d/0'],
                },
              ])
            : '[]',
        '$rdBase/downloads': '[]',
        '$rdBase/torrents/info/t1': jsonEncode(torrentInfo()),
      });
      HttpOverrides.global = http;
    }

    testWidgets('root chrome: view selector labels and the selection bar', (
      tester,
    ) async {
      seed(listTorrent: true);
      await useLargeViewport(tester);
      await openOnRealClock(
        tester,
        const DebridDownloadsScreen(isPushedRoute: true),
        const ['Chrome Pin'],
      );

      expect(find.text('Torrent Downloads'), findsOneWidget);
      expect(find.text('DDL Downloads'), findsOneWidget);

      await pinSelectionBar(tester);
    });

    testWidgets('torrent search bar and the initial-title submit gate', (
      tester,
    ) async {
      seed(hiddenFromNav: true, listTorrent: true);
      await useLargeViewport(tester);
      await openOnRealClock(
        tester,
        const DebridDownloadsScreen(
          isPushedRoute: true,
          selectSourceMode: true,
          initialSearchQuery: 'The Matrix',
        ),
        const ['Search your torrents...'],
      );

      await pinInitialTitleGate(tester, initialTitle: 'The Matrix');
    });

    testWidgets('torrent search bar clears without leaving the bar', (
      tester,
    ) async {
      seed(listTorrent: true);
      await useLargeViewport(tester);
      await openOnRealClock(
        tester,
        const DebridDownloadsScreen(
          isPushedRoute: true,
          selectSourceMode: true,
          initialSearchQuery: 'The Matrix',
        ),
        const ['Search your torrents...'],
      );

      await pinTorrentSearchBar(tester, initialTitle: 'The Matrix');
    });

    testWidgets('folder chrome: view-mode dropdown, file search, result card', (
      tester,
    ) async {
      seed();
      await useLargeViewport(tester);
      await openOnRealClock(
        tester,
        DebridDownloadsScreen(
          isPushedRoute: true,
          initialTorrentForOptions: torrent(),
        ),
        rawOrder,
      );

      await pinViewModeDropdown(tester);
      await pinFileSearch(tester, resultsReachable: true);

      await drainDeepLinkTimer(tester);
      expect(
        find.text('Failed to open torrent. Please try again.'),
        findsNothing,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Canned dart:io HTTP. package:http's IOClient goes through HttpClient(), which
// honours HttpOverrides, so this answers the screens' real service calls.
// Copied from test/cloud_folder_sort_origin_pin_test.dart.
// ---------------------------------------------------------------------------

class _CannedHttp extends HttpOverrides {
  _CannedHttp(this.routesByPath);

  /// URL path → JSON body. Anything else is an error, not a silent 400.
  final Map<String, String> routesByPath;
  final List<String> requests = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) => _CannedClient(this);
}

class _CannedClient implements HttpClient {
  _CannedClient(this.fixture);
  final _CannedHttp fixture;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    fixture.requests.add('$method ${url.path}');
    final body = fixture.routesByPath[url.path];
    if (body == null) {
      throw StateError('Unexpected request: $method $url');
    }
    return _CannedRequest(method, url, utf8.encode(body));
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CannedRequest implements HttpClientRequest {
  _CannedRequest(this.method, this.uri, this._body);

  @override
  final String method;
  @override
  final Uri uri;
  final List<int> _body;

  @override
  final HttpHeaders headers = _CannedHeaders({});
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  bool persistentConnection = true;
  @override
  bool bufferOutput = true;

  late final _CannedResponse _response = _CannedResponse(_body, {
    'content-type': ['application/json'],
    'x-total-count': ['0'],
  });

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  void add(List<int> data) {}

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  Future<HttpClientResponse> get done async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CannedResponse extends Stream<List<int>> implements HttpClientResponse {
  _CannedResponse(this._bytes, Map<String, List<String>> headerMap)
    : headers = _CannedHeaders(headerMap);

  final List<int> _bytes;

  @override
  final HttpHeaders headers;

  @override
  int get statusCode => 200;
  @override
  String get reasonPhrase => 'OK';
  @override
  int get contentLength => _bytes.length;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  List<Cookie> get cookies => const [];
  @override
  X509Certificate? get certificate => null;
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CannedHeaders implements HttpHeaders {
  _CannedHeaders(this._values);
  final Map<String, List<String>> _values;

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  String? value(String name) => _values[name.toLowerCase()]?.join(', ');

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach(action);

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = ['$value'];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => []).add('$value');
  }

  @override
  void remove(String name, Object value) {}

  @override
  void removeAll(String name) => _values.remove(name.toLowerCase());

  @override
  int contentLength = -1;
  @override
  bool chunkedTransferEncoding = false;
  @override
  bool persistentConnection = true;
  @override
  ContentType? contentType;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
