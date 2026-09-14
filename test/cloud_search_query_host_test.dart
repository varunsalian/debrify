import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/debrid_downloads_screen.dart';
import 'package:debrify/screens/torbox/torbox_downloads_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Narrowed from 4cb9a57e's host characterization. These tests invoke the real
// mounted search field's submit callback; no private state or submit mock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpOverrides? previous;
  late _CannedHttp http;

  setUp(() {
    previous = HttpOverrides.current;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'cloud-query-test');
    PlatformUtil.debugSetAndroidTvCached(true);
  });
  tearDown(() {
    HttpOverrides.global = previous;
    PlatformUtil.debugSetAndroidTvCached(null);
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });

  Future<void> settle(WidgetTester tester, [bool Function()? ready]) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (ready?.call() ?? i >= 4) return;
      }
    });
    await tester.pump();
    if (ready != null) {
      expect(ready(), isTrue, reason: http.requests.join('\n'));
    }
  }

  Widget screen(bool torbox, bool select, String? title) => torbox
      ? TorboxDownloadsScreen(
          isPushedRoute: true,
          selectSourceMode: select,
          initialSearchQuery: title,
        )
      : DebridDownloadsScreen(
          isPushedRoute: true,
          selectSourceMode: select,
          initialSearchQuery: title,
        );

  Future<void> open(
    WidgetTester tester,
    bool torbox,
    bool select,
    bool hidden, {
    String title = 'The Matrix',
    bool emptySearch = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    SharedPreferences.setMockInitialValues({
      'real_debrid_api_key': 'test-only-key',
      'real_debrid_hidden_from_nav': hidden,
      'torbox_api_key': 'test-only-key',
      'torbox_hidden_from_nav': hidden,
    });
    http = _CannedHttp(torbox, emptySearch: emptySearch);
    HttpOverrides.global = http;
    await tester.runAsync(
      () => tester.pumpWidget(MaterialApp(home: screen(torbox, select, title))),
    );
    await settle(
      tester,
      () => select ? http.searchCalls == 1 : http.requests.length >= 2,
    );
    await settle(tester);
    if (!select) {
      await tester.tap(find.byTooltip('Search torrents'));
      await tester.pump();
    }
    expect(find.byType(TvTextField), findsOneWidget);
  }

  Future<void> submit(WidgetTester tester, String query) async {
    final field = tester.widget<TvTextField>(find.byType(TvTextField));
    field.focusNode!.requestFocus();
    await tester.pump();
    field.controller.text = query;
    field.onSubmitted!(query);
    await tester.pump();
  }

  bool fieldFocused(WidgetTester tester) => tester
      .widget<TvTextField>(find.byType(TvTextField))
      .focusNode!
      .hasPrimaryFocus;
  String? getFocus() => FocusManager.instance.primaryFocus?.debugLabel;

  for (final torbox in [false, true]) {
    final host = torbox ? 'TorBox' : 'RD';
    final resultFocus = torbox ? 'torbox-first-item' : 'rd-first-item';
    for (final select in [false, true]) {
      for (final hidden in [false, true]) {
        testWidgets('$host submit guard select=$select hidden=$hidden', (
          tester,
        ) async {
          await open(tester, torbox, select, hidden);
          final before = http.searchCalls;
          await submit(tester, 'Unrelated');
          await settle(tester);
          final blocked = select && hidden;
          expect(
            find.text('Search must include part of "The Matrix"'),
            blocked ? findsOneWidget : findsNothing,
          );
          expect(http.searchCalls, before + (!select ? 1 : 0));
          if (blocked) {
            expect(fieldFocused(tester), isTrue);
          } else {
            expect(find.text('Unrelated result'), findsOneWidget);
            expect(getFocus(), resultFocus);
          }
          final after = http.searchCalls;
          // Substring/case matching and host-only trimming, retained results.
          await submit(tester, '  PreMaTrIxEd  ');
          await settle(tester);
          expect(find.text('prematrixed'), findsOneWidget);
          expect(getFocus(), resultFocus);
          expect(http.searchCalls, after);
          // Empty submit must neither change the result query nor fetch.
          await submit(tester, '   ');
          await settle(tester);
          expect(fieldFocused(tester), isTrue);
          expect(find.text('prematrixed'), findsOneWidget);
          expect(http.searchCalls, after);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 11));
        });
      }
    }

    for (final invalid in ['Unrelated', '   ']) {
      testWidgets('$host rejected "$invalid" cancels pending submit focus', (
        tester,
      ) async {
        await open(tester, torbox, true, true, emptySearch: true);
        final gate = Completer<void>();
        http.searchGate = gate.future;
        http.emptySearch = false;
        try {
          await submit(tester, 'prematrixed');
          await settle(tester, () => http.searchCalls == 2);
          expect(fieldFocused(tester), isTrue);
          await submit(tester, invalid);
          gate.complete();
          await settle(
            tester,
            () => find.text('prematrixed').evaluate().isNotEmpty,
          );
          await settle(tester);
          expect(
            fieldFocused(tester),
            isTrue,
            reason: 'Late results must not take focus',
          );
          expect(http.searchCalls, 2);
          // Reusing those results re-arms focus without another fetch.
          await submit(tester, 'prematrixed');
          await settle(tester);
          expect(getFocus(), resultFocus);
          expect(http.searchCalls, 2);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await settle(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 11));
        }
      });
    }
  }
}

class _CannedHttp extends HttpOverrides {
  _CannedHttp(this.torbox, {this.emptySearch = false});
  final bool torbox;
  bool emptySearch;
  Future<void>? searchGate;
  int searchCalls = 0;
  final requests = <String>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) => _CannedClient(this);

  Future<String> respond(Uri url) async {
    requests.add(url.toString());
    final search = url.queryParameters['limit'] == (torbox ? '1000' : '2000');
    if (search) {
      searchCalls++;
      await searchGate;
    }
    final titles = search && emptySearch
        ? <String>[]
        : ['The Matrix', 'prematrixed', 'Unrelated result'];
    if (url.path.endsWith('/downloads')) return '[]';
    if (url.path.endsWith('/webdl/mylist')) return '{"success":true,"data":[]}';
    if (url.path.endsWith('/torrents/mylist')) {
      return jsonEncode({
        'success': true,
        'data': [
          for (var i = 0; i < titles.length; i++)
            {
              'id': i + 1,
              'hash': 'test-$i',
              'name': titles[i],
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
              'download_state': 'completed',
              'download_finished': true,
              'download_present': true,
              'cached': true,
              'files': [],
            },
        ],
      });
    }
    if (url.path.endsWith('/torrents')) {
      return jsonEncode([
        for (var i = 0; i < titles.length; i++)
          {
            'id': '$i',
            'filename': titles[i],
            'hash': 'test-$i',
            'bytes': 100,
            'host': 'real-debrid.com',
            'split': 0,
            'progress': 100,
            'status': 'downloaded',
            'added': '2026-01-01',
            'links': [],
          },
      ]);
    }
    throw StateError('Unexpected fixture request: $url');
  }
}

class _CannedClient implements HttpClient {
  _CannedClient(this.fixture);
  final _CannedHttp fixture;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final body = await fixture.respond(url);
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
