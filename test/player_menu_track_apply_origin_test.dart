import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/services/player_terminal_backend.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/playback_progress_store.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Pins the player-menu track-apply operations (subtitles off, embedded
// subtitle, audio, addon subtitle) as the real screen wires them into
// `PlayerMenuPanel`. Harness adapted from
// test/player_presentation_controls_origin_test.dart: only external SDK state
// and terminal operations are scripted (track lists, setAudioTrack /
// setSubtitleTrack, the `sub-visibility` property, dart:io HTTP, path_provider).
// The menu is opened through `Controls.onShowTracks()` on a single-file launch
// whose `contentImdbId` is set, so no metadata fetch runs.
//
// The token-race branch (content switching while an addon download is in
// flight: `token != _addonSubtitleFetchToken || !mounted`) is source-preserved
// and not driven here; it needs a mid-download content switch.
class _TerminalStreams extends mk.PlatformPlayer {
  _TerminalStreams(mk.PlayerConfiguration configuration)
    : super(configuration: configuration);
}

class _Properties implements mk.NativePlayer {
  _Properties(mk.PlayerConfiguration configuration, this.unexpected)
    : _streams = _TerminalStreams(configuration);

  final _TerminalStreams _streams;
  @override
  mk.PlayerConfiguration get configuration => _streams.configuration;
  @override
  mk.PlayerState get state => _streams.state;
  @override
  set state(mk.PlayerState value) => _streams.state = value;
  @override
  mk.PlayerStream get stream => _streams.stream;

  final List<String> unexpected;
  final reads = <String>[];
  final writes = <(String, String)>[];
  bool closed = false;
  Future<void>? disposal;
  @override
  Future<String> getProperty(
    String property, {
    bool waitForInitialization = true,
  }) async {
    reads.add(property);
    unexpected.add('getProperty:$property');
    throw StateError('Unscripted property $property');
  }

  @override
  Future<void> setProperty(
    String property,
    String value, {
    bool waitForInitialization = true,
  }) async {
    writes.add((property, value));
    if (property != 'video-zoom' && property != 'sub-visibility') {
      unexpected.add('setProperty:$property');
      throw StateError('Unscripted property write $property');
    }
  }

  void emitPlayback(Duration position) {
    state = state.copyWith(
      playing: true,
      duration: const Duration(minutes: 10),
      position: position,
    );
    _streams.durationController.add(state.duration);
    _streams.positionController.add(position);
    _streams.playingController.add(true);
  }

  /// Real embedded tracks, as libmpv publishes them after demux. The host's
  /// restore path waits for a non-placeholder subtitle id before proceeding.
  void emitTracks() {
    state = state.copyWith(
      tracks: const mk.Tracks(
        audio: [
          mk.AudioTrack('auto', null, null),
          mk.AudioTrack('no', null, null),
          mk.AudioTrack('1', 'Stereo', 'jpn'),
          mk.AudioTrack('2', 'Commentary', 'jpn'),
        ],
        subtitle: [
          mk.SubtitleTrack('auto', null, null),
          mk.SubtitleTrack('no', null, null),
          mk.SubtitleTrack('3', 'Full', 'jpn'),
        ],
      ),
    );
    _streams.tracksController.add(state.tracks);
  }

  void applyTrack(mk.Track track) {
    state = state.copyWith(track: track);
    _streams.trackController.add(track);
  }

  @override
  Future<void> dispose({bool synchronized = true}) =>
      disposal ??= closeStreams();
  Future<void> closeStreams() async {
    await _streams.dispose();
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add('native:${invocation.memberName}');
    throw StateError('Unexpected native API ${invocation.memberName}');
  }
}

class _Player implements mk.Player {
  _Player(this.backend);
  final _Properties backend;

  @override
  mk.PlatformPlayer? get platform => backend;
  @override
  set platform(mk.PlatformPlayer? value) =>
      throw StateError('Unexpected platform replacement');
  @override
  mk.PlayerState get state => backend.state;
  @override
  mk.PlayerStream get stream => backend.stream;
  @override
  Future<void> dispose() => backend.dispose();

  final rates = <double>[];
  @override
  Future<void> setRate(double value) async {
    rates.add(value);
    backend.state = backend.state.copyWith(rate: value);
  }

  /// Subtitle selections in order; external (URI) tracks are recorded by
  /// their file path.
  final subtitleCalls = <String>[];
  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) async {
    subtitleCalls.add(track.id);
    backend.applyTrack(backend.state.track.copyWith(subtitle: track));
  }

  final audioCalls = <String>[];
  @override
  Future<void> setAudioTrack(mk.AudioTrack track) async {
    audioCalls.add(track.id);
    backend.applyTrack(backend.state.track.copyWith(audio: track));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    backend.unexpected.add('player:${invocation.memberName}');
    throw StateError('Unexpected player API ${invocation.memberName}');
  }
}

class _TexturelessVideo implements mkv.VideoController {
  _TexturelessVideo(this.player, this.unexpected);
  @override
  final mk.Player player;
  final List<String> unexpected;
  @override
  final platform = Completer<mkv.PlatformVideoController>();
  @override
  final notifier = ValueNotifier<mkv.PlatformVideoController?>(null);
  @override
  final id = ValueNotifier<int?>(null);
  @override
  final rect = ValueNotifier<Rect?>(null);

  void close() {
    notifier.dispose();
    id.dispose();
    rect.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add('video:${invocation.memberName}');
    throw StateError('Unexpected video API ${invocation.memberName}');
  }
}

class _Terminal extends PlayerTerminalBackend {
  final construction = <String>[];
  final unexpected = <String>[];
  _Properties? properties;
  _Player? player;
  _TexturelessVideo? video;

  @override
  void ensureInitialized() {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('bootstrap');
  }

  @override
  mk.Player createPlayer({required mk.PlayerConfiguration configuration}) {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('player');
    expect(configuration.logLevel, mk.MPVLogLevel.error);
    expect(configuration.ready, isNotNull);
    properties = _Properties(configuration, unexpected);
    return player = _Player(properties!);
  }

  @override
  mkv.VideoController createVideoController(
    mk.Player player, {
    required mkv.VideoControllerConfiguration configuration,
  }) {
    expect(PlayerTerminalBackend.debugOverride, same(this));
    construction.add('video');
    expect(player, same(this.player));
    return video = _TexturelessVideo(player, unexpected);
  }
}

const _title = 'Menu track fixture';
const _subtitleUrl = 'https://subs.example.test/subs/en.srt';
const _subtitlePath = '/subs/en.srt';
const _srtBody = '1\n00:00:01,000 --> 00:00:02,000\nHello\n';

StremioSubtitle _addonSubtitle() => const StremioSubtitle(
  id: 's1',
  url: _subtitleUrl,
  lang: 'eng',
  label: 'English',
  source: 'Fixture addon',
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  const wake =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  late PlayerTerminalBackend? previous;
  late HttpOverrides? previousOverrides;
  late _Terminal terminal;
  late _CannedHttp http;
  late Directory root;
  Object? primaryFailure;
  StackTrace? primaryStack;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    previous = PlayerTerminalBackend.debugOverride;
    previousOverrides = HttpOverrides.current;
    terminal = _Terminal();
    http = _CannedHttp({});
    HttpOverrides.global = http;
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'menu-track-apply-origin');
    StorageService.resetProfileCaches();
    root = await Directory('.dart_tool').absolute.createTemp('menu-track-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(window, (
      call,
    ) async {
      switch (call.method) {
        case 'setFullScreen':
        case 'setBounds':
          return null;
        case 'getBounds':
          return {'x': 0.0, 'y': 0.0, 'width': 1280.0, 'height': 720.0};
        case 'isFullScreen':
          return false;
        default:
          terminal.unexpected.add('window:${call.method}');
          throw StateError('Unexpected window call ${call.method}');
      }
    });
    binding.defaultBinaryMessenger.setMockMessageHandler(
      wake,
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, (
      call,
    ) async {
      if (call.method == 'resetApplicationScreenBrightness') return null;
      terminal.unexpected.add('brightness:${call.method}');
      throw StateError('Unexpected brightness call ${call.method}');
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (
      call,
    ) async {
      if (call.method == 'getTemporaryDirectory') return root.path;
      terminal.unexpected.add('path_provider:${call.method}');
      throw StateError('Unexpected path_provider call ${call.method}');
    });
    PlayerTerminalBackend.debugOverride = terminal;
  });

  tearDown(() async {
    try {
      if (terminal.properties != null && !terminal.properties!.closed) {
        await terminal.properties!.dispose();
      }
      terminal.video?.close();
      await DebrifyTvDatabase.instance.debugResetScopeState();
      expect(PlayerTerminalBackend.debugOverride, same(terminal));
    } catch (error, stack) {
      debugPrintSynchronously('MENU_TRACK_TEARDOWN $error\n$stack');
      if (primaryFailure != null) {
        Error.throwWithStackTrace(primaryFailure!, primaryStack!);
      }
      rethrow;
    } finally {
      PlayerTerminalBackend.debugOverride = previous;
      HttpOverrides.global = previousOverrides;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(brightness, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathProvider,
        null,
      );
      binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
      StorageService.resetProfileCaches();
      AppStorage.debugReset();
      ProfileRuntime.debugReset();
      SecretVault.debugReset();
    }
  });

  Future<void> withHost(
    WidgetTester tester,
    Future<void> Function(_Properties) exercise,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    primaryFailure = null;
    primaryStack = null;
    try {
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              AppThemeScope(theme: AppThemes.byId('spotlight'), child: child!),
          home: const VideoPlayerScreen(
            videoUrl: '',
            title: _title,
            disableAutoResume: true,
            contentImdbId: 'tt0000001',
          ),
        ),
      );
      // Accepted fixture construction bound, not a behavior timing assertion.
      for (var i = 0; i < 20 && terminal.video == null; i++) {
        await tester.pump();
      }
      expect(terminal.construction, ['bootstrap', 'player', 'video']);
      final backend = terminal.properties!;
      backend.configuration.ready!();
      backend.emitTracks();
      backend.emitPlayback(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(Controls), findsOneWidget);
      expect(backend.reads, isEmpty);
      await exercise(backend);
      expect(terminal.unexpected, isEmpty);
    } catch (error, stack) {
      primaryFailure = error;
      primaryStack = stack;
      debugPrintSynchronously('MENU_TRACK_PRIMARY $error\n$stack');
      rethrow;
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 250));
        if (terminal.properties != null) await terminal.properties!.dispose();
        expect(VideoOutputLease.isHeld, isFalse);
        expect(terminal.unexpected, isEmpty);
      } catch (error, stack) {
        debugPrintSynchronously('MENU_TRACK_CLEANUP $error\n$stack');
        if (primaryFailure != null) {
          Error.throwWithStackTrace(primaryFailure!, primaryStack!);
        }
        rethrow;
      }
    }
  }

  PlayerMenuPanel menu(WidgetTester tester) =>
      tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));

  /// Opens the Subtitles pane the way the Controls bar does, then lets the
  /// startup restore (which waits for real tracks) settle with no stored
  /// preference, so every later player call belongs to the menu.
  Future<PlayerMenuPanel> openMenu(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    tester.widget<Controls>(find.byType(Controls)).onShowTracks();
    await tester.pump();
    await tester.pump();
    expect(find.byType(PlayerMenuPanel), findsOneWidget);
    expect(terminal.player!.subtitleCalls, isEmpty);
    expect(terminal.player!.audioCalls, isEmpty);
    expect(
      await PlaybackProgressStore.getVideoTrackPreferences(videoTitle: _title),
      isNull,
    );
    return menu(tester);
  }

  /// Drives an apply future across the 50 ms decoder-settle delay inside
  /// `setSubtitleTrackWithDiagnostics` and the panel's own microtasks.
  Future<T> settle<T>(WidgetTester tester, Future<T> future) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }
    return future;
  }

  Future<Map<String, dynamic>?> storedPrefs() =>
      PlaybackProgressStore.getVideoTrackPreferences(videoTitle: _title);

  testWidgets(
    'subtitles off applies the no track through diagnostics and persists (audio, no)',
    (tester) async {
      await withHost(tester, (backend) async {
        final panel = await openMenu(tester);
        final audioId = panel.selectedAudioId;
        expect(audioId, 'auto');
        final writesBefore = backend.writes.length;

        final ok = await settle(tester, panel.onSubtitlesOff(audioId));

        expect(ok, isTrue);
        expect(terminal.player!.subtitleCalls, ['no']);
        expect(terminal.player!.audioCalls, isEmpty);
        expect(backend.writes.skip(writesBefore).toList(), [
          ('sub-visibility', 'no'),
        ]);
        expect(backend.state.track.subtitle.id, 'no');
        final prefs = await storedPrefs();
        expect(prefs, isNotNull);
        expect(prefs!['audioTrackId'], audioId);
        expect(prefs['subtitleTrackId'], 'no');
        expect(find.byType(SnackBar), findsNothing);
      });
    },
  );

  testWidgets(
    'embedded subtitle with a missing id fails with the exact message and no player call; a present id applies and persists',
    (tester) async {
      await withHost(tester, (backend) async {
        final panel = await openMenu(tester);
        final audioId = panel.selectedAudioId;

        final missing = await settle(
          tester,
          panel.onEmbeddedSubtitleSelected('missing', audioId),
        );

        expect(missing, isFalse);
        expect(terminal.player!.subtitleCalls, isEmpty);
        expect(backend.writes.where((w) => w.$1 == 'sub-visibility'), isEmpty);
        expect(
          find.text(
            'That subtitle track is no longer available. Try another track.',
          ),
          findsOneWidget,
        );
        expect(await storedPrefs(), isNull);

        final present = await settle(
          tester,
          panel.onEmbeddedSubtitleSelected('3', audioId),
        );

        expect(present, isTrue);
        expect(terminal.player!.subtitleCalls, ['3']);
        expect(backend.state.track.subtitle.id, '3');
        final prefs = await storedPrefs();
        expect(prefs!['audioTrackId'], audioId);
        expect(prefs['subtitleTrackId'], '3');
      });
    },
  );

  testWidgets(
    'audio select sets the track and persists it with the current subtitle; an unknown id is ignored',
    (tester) async {
      await withHost(tester, (backend) async {
        final panel = await openMenu(tester);

        await settle(tester, panel.onAudioSelected('2', 'no'));

        expect(terminal.player!.audioCalls, ['2']);
        expect(terminal.player!.subtitleCalls, isEmpty);
        expect(backend.state.track.audio.id, '2');
        final prefs = await storedPrefs();
        expect(prefs!['audioTrackId'], '2');
        expect(prefs['subtitleTrackId'], 'no');
        final updatedAt = prefs['updatedAt'];

        await settle(tester, panel.onAudioSelected('9', 'no'));

        expect(terminal.player!.audioCalls, ['2']);
        final after = await storedPrefs();
        expect(after!['audioTrackId'], '2');
        expect(after['updatedAt'], updatedAt);
      });
    },
  );

  testWidgets(
    'addon subtitle with an HTTP 500 fails with the exact message and no player call',
    (tester) async {
      http.routes[_subtitlePath] = const _Canned(500, '');
      await withHost(tester, (backend) async {
        final panel = await openMenu(tester);
        final audioId = panel.selectedAudioId;

        final ok = await settle(
          tester,
          panel.onAddonSubtitleSelected(_addonSubtitle(), audioId),
        );

        expect(ok, isFalse);
        expect(http.requests, ['GET $_subtitlePath']);
        expect(terminal.player!.subtitleCalls, isEmpty);
        expect(backend.writes.where((w) => w.$1 == 'sub-visibility'), isEmpty);
        expect(
          find.text(
            'Couldn’t load subtitles. Check your connection or try another track.',
          ),
          findsOneWidget,
        );
        expect(await storedPrefs(), isNull);
      });
    },
  );

  testWidgets(
    'addon subtitle with an HTTP 200 downloads, applies the file track and persists stremio:<id>',
    (tester) async {
      http.routes[_subtitlePath] = const _Canned(200, _srtBody);
      await withHost(tester, (backend) async {
        final panel = await openMenu(tester);
        final audioId = panel.selectedAudioId;

        // The controller writes the download to a real temp file
        // (`writeAsBytes` + `rename`), which never settles on the fake
        // clock; run this apply on the real event loop.
        final ok = await tester.runAsync(
          () => panel.onAddonSubtitleSelected(_addonSubtitle(), audioId),
        );
        await tester.pump();

        expect(ok, isTrue);
        expect(http.requests, ['GET $_subtitlePath']);
        expect(terminal.player!.subtitleCalls, hasLength(1));
        final applied = backend.state.track.subtitle;
        expect(applied.uri, isTrue);
        expect(applied.title, 'English');
        expect(applied.language, 'eng');
        expect(File(applied.id).existsSync(), isTrue);
        expect(File(applied.id).path, startsWith(root.path));
        expect(backend.writes.where((w) => w.$1 == 'sub-visibility'), [
          ('sub-visibility', 'no'),
        ]);
        final prefs = await storedPrefs();
        expect(prefs!['audioTrackId'], audioId);
        expect(prefs['subtitleTrackId'], 'stremio:s1');
        expect(find.byType(SnackBar), findsNothing);
      });
    },
  );
}

// ---------------------------------------------------------------------------
// Canned dart:io HTTP. package:http's IOClient goes through HttpClient(), which
// honours HttpOverrides, so this answers the controller's real download call.
// ---------------------------------------------------------------------------

class _Canned {
  const _Canned(this.status, this.body);
  final int status;
  final String body;
}

class _CannedHttp extends HttpOverrides {
  _CannedHttp(this.routes);

  /// URL path → response. Anything else is an error, not a silent 400.
  final Map<String, _Canned> routes;
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
    final canned = fixture.routes[url.path];
    if (canned == null) {
      throw StateError('Unexpected request: $method $url');
    }
    return _CannedRequest(method, url, canned);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _CannedRequest implements HttpClientRequest {
  _CannedRequest(this.method, this.uri, this._canned);

  @override
  final String method;
  @override
  final Uri uri;
  final _Canned _canned;

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

  late final _CannedResponse _response = _CannedResponse(
    _canned.status,
    utf8.encode(_canned.body),
    {
      'content-type': ['text/plain'],
    },
  );

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
  _CannedResponse(this.statusCode, this._bytes, Map<String, List<String>> map)
    : headers = _CannedHeaders(map);

  final List<int> _bytes;

  @override
  final HttpHeaders headers;

  @override
  final int statusCode;
  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Error';
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
