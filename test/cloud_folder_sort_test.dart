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

/// Public-screen contract for the folder-view "Sort (A-Z)" ordering that the
/// Real-Debrid and TorBox files screens each implement privately
/// (`_applySortedView`, `_extractSeasonNumber`, `_extractLeadingNumber`).
///
/// The pin drives the real screens: a deep-linked torrent is opened, the
/// view-mode dropdown is switched, and the rendered row order is asserted.
/// Network is answered by a canned `HttpOverrides`; no other seam is used.
///
/// Quirks pinned here (keep, do not "fix"):
/// * Raw view keeps the API's file order, folders and files interleaved.
/// * Sorted view puts folders first. Folders whose name carries a number
///   ("Season 2", "Chapter 10", "Lesson_5") sort numerically and ahead of
///   folders without one; the rest sort case-insensitively.
/// * Files that start with a number followed by a separator ("2. x", "10 -",
///   "05_") sort numerically and ahead of the rest, which sort
///   case-insensitively. "Alpha.mkv" is not numbered; "2. Alpha.mkv" is.
/// * The dropdown offers only "Raw" and "Sort (A-Z)".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Scrambled on purpose: the raw view must keep this order.
  const rawOrder = <String>[
    'Season 10',
    'zeta.mkv',
    'Extras',
    '10. Zulu.mkv',
    'Season 2',
    '2. Alpha.mkv',
    'Alpha.mkv',
    'Lesson_5',
    'chapter-3',
    'Season_01',
    '05_Episode.mkv',
    '3no-separator.mkv',
  ];
  const sortedOrder = <String>[
    'Season_01',
    'Season 2',
    'chapter-3',
    'Lesson_5',
    'Season 10',
    'Extras',
    '2. Alpha.mkv',
    '05_Episode.mkv',
    '10. Zulu.mkv',
    '3no-separator.mkv',
    'Alpha.mkv',
    'zeta.mkv',
  ];

  /// Relative paths in raw order; folders get one file each so they render.
  const rawPaths = <String>[
    'Season 10/s10e01.mkv',
    'zeta.mkv',
    'Extras/making-of.mkv',
    '10. Zulu.mkv',
    'Season 2/s02e01.mkv',
    '2. Alpha.mkv',
    'Alpha.mkv',
    'Lesson_5/lesson.mkv',
    'chapter-3/chapter.mkv',
    'Season_01/s01e01.mkv',
    '05_Episode.mkv',
    '3no-separator.mkv',
  ];

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
  /// the open runs inside [WidgetTester.runAsync]; the dropdown interaction
  /// that follows is synchronous and runs on the fake clock as usual.
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

  Future<void> chooseView(WidgetTester tester, String mode) async {
    final dropdown = find.byWidgetPredicate(
      (w) => w is DropdownButtonFormField,
    );
    expect(dropdown, findsOneWidget, reason: 'view-mode dropdown');
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    // Only two choices are offered; the series arrangement is not exposed.
    expect(find.text('Series Arrange'), findsNothing);
    await tester.tap(find.text(mode).last);
    await tester.pumpAndSettle();
  }

  /// Both hosts arm a 10s deep-link timeout when opened with a target; it
  /// must stay silent because the torrent did open.
  Future<void> drainDeepLinkTimer(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 11));
  }

  group('TorBox TorboxDownloadsScreen', () {
    TorboxTorrent torrent() => TorboxTorrent.fromJson({
      'id': 7,
      'hash': 'pinhash',
      'name': 'Sort Pin',
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
            'size': 100 + i,
          },
      ],
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({'torbox_api_key': 'pin-key'});
      http = _CannedHttp({
        '/v1/api/torrents/mylist': jsonEncode({'success': true, 'data': []}),
        '/v1/api/webdl/mylist': jsonEncode({'success': true, 'data': []}),
      });
      HttpOverrides.global = http;
    });

    testWidgets('raw view keeps API order; Sort (A-Z) reorders the tree', (
      tester,
    ) async {
      await useLargeViewport(tester);
      await openOnRealClock(
        tester,
        TorboxDownloadsScreen(
          isPushedRoute: true,
          initialTorrentToOpen: torrent(),
        ),
        rawOrder,
      );
      expect(renderedOrder(tester, rawOrder), rawOrder);

      await chooseView(tester, 'Sort (A-Z)');
      expect(renderedOrder(tester, sortedOrder), sortedOrder);

      // Sorting must not mutate the API order retained for Raw view.
      await chooseView(tester, 'Raw');
      expect(renderedOrder(tester, rawOrder), rawOrder);

      await drainDeepLinkTimer(tester);
      expect(
        find.text('Failed to open torrent. Please try again.'),
        findsNothing,
      );
    });
  });

  group('Real-Debrid DebridDownloadsScreen', () {
    const rdBase = '/rest/1.0';

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'real_debrid_api_key': 'pin-key',
      });
      http = _CannedHttp({
        '$rdBase/torrents': '[]',
        '$rdBase/downloads': '[]',
        '$rdBase/torrents/info/t1': jsonEncode({
          'id': 't1',
          'filename': 'Sort Pin',
          'status': 'downloaded',
          'files': [
            for (var i = 0; i < rawPaths.length; i++)
              {
                'id': i + 1,
                'path': '/${rawPaths[i]}',
                'bytes': 100 + i,
                'selected': 1,
              },
          ],
          // One link per selected file so this is not read as a RAR archive.
          'links': [
            for (var i = 0; i < rawPaths.length; i++)
              'https://real-debrid.invalid/d/$i',
          ],
        }),
      });
      HttpOverrides.global = http;
    });

    testWidgets('raw view keeps API order; Sort (A-Z) reorders the tree', (
      tester,
    ) async {
      await useLargeViewport(tester);
      final torrent = RDTorrent(
        id: 't1',
        filename: 'Sort Pin',
        hash: 'pinhash',
        bytes: 700,
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
      await openOnRealClock(
        tester,
        DebridDownloadsScreen(
          isPushedRoute: true,
          initialTorrentForOptions: torrent,
        ),
        rawOrder,
      );
      expect(renderedOrder(tester, rawOrder), rawOrder);

      await chooseView(tester, 'Sort (A-Z)');
      expect(renderedOrder(tester, sortedOrder), sortedOrder);

      // Sorting must not mutate the API order retained for Raw view.
      await chooseView(tester, 'Raw');
      expect(renderedOrder(tester, rawOrder), rawOrder);

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
