import 'dart:async';
import 'dart:io';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/services/player_terminal_backend.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Origin pin for the in-player episode candidate ladder (the episode guide's
// "fetch an absent episode" path). Harness adapted from the transition pin's
// gated NativePlayer fake; the TVMaze probe is answered through the
// navigation pin's http.runWithClient shape. Only external SDK state and
// terminal operations are scripted: the guide, the sheet, the ladder, the
// source switch and the media open remain real lib code.
class _TerminalStreams extends mk.PlatformPlayer {
  _TerminalStreams(mk.PlayerConfiguration configuration)
    : super(configuration: configuration);

  void emitPlaying(bool playing) => playingController.add(playing);
  void emitPosition(Duration position) => positionController.add(position);
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
  bool allowSourceOpen = false;
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
    if (property != 'video-zoom' &&
        !(allowSourceOpen &&
            ((property == 'stream-lavf-o' && value == '') ||
                (property == 'sub-visibility' && value == 'no') ||
                (property == 'sub-delay' && value == '0.000')))) {
      unexpected.add('setProperty:$property');
      throw StateError('Unscripted property write $property');
    }
  }

  void emitPlayback(
    Duration position, {
    bool playing = false,
    Duration duration = const Duration(minutes: 10),
  }) {
    state = state.copyWith(
      playing: playing,
      duration: duration,
      position: position,
    );
    _streams.durationController.add(state.duration);
    _streams.positionController.add(position);
    _streams.playingController.add(playing);
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

  // Terminal responses only: no ladder, switch or open policy here.
  final operations = <String>[];
  final seeks = <Duration>[];
  @override
  Future<void> pause() async {
    operations.add('pause');
    backend.state = backend.state.copyWith(playing: false);
    backend._streams.emitPlaying(false);
  }

  @override
  Future<void> play() async {
    operations.add('play');
    backend.state = backend.state.copyWith(playing: true);
    backend._streams.emitPlaying(true);
  }

  @override
  Future<void> seek(Duration position) async {
    operations.add('seek:${position.inMilliseconds}');
    seeks.add(position);
    backend.state = backend.state.copyWith(position: position);
    backend._streams.emitPosition(position);
  }

  Completer<void>? openGate;
  bool openEntered = false;
  bool openCompleted = false;
  final opened = <mk.Playable>[];
  final openPlay = <bool>[];

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    if (!backend.allowSourceOpen) {
      backend.unexpected.add('player:unexpected-open');
      throw StateError('Open outside declared ladder scenario');
    }
    operations.add('open');
    opened.add(playable);
    openPlay.add(play);
    openEntered = true;
    final gate = openGate;
    if (gate == null) throw StateError('Missing owned open gate');
    await gate.future;
    operations.add('open-done');
    openCompleted = true;
  }

  final rates = <double>[];
  @override
  Future<void> setRate(double value) async {
    rates.add(value);
    backend.state = backend.state.copyWith(rate: value);
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

// dart:io HttpClient is never reached: package:http traffic is answered by
// the zone client below, everything else is unscripted.
class _NoHttpClient implements HttpClient {
  _NoHttpClient(this.unexpected);
  final List<String> unexpected;
  @override
  bool autoUncompress = true;
  @override
  String? userAgent;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpected.add(
      'HTTP:${invocation.memberName}:${invocation.positionalArguments}',
    );
    throw StateError('Unscripted HTTP ${invocation.memberName}');
  }
}

// Metadata transport: the TVMaze connectivity probe gets an empty 400 (the
// service then treats TVMaze as unavailable); any other host is unexpected.
class _MetadataClient extends http.BaseClient {
  _MetadataClient(this.unexpected, this.requests);
  final List<String> unexpected;
  final List<String> requests;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    requests.add('${request.method} $uri');
    if (uri.host != 'api.tvmaze.com' || request.method != 'GET') {
      unexpected.add('http:${request.method} $uri');
      throw StateError('Unexpected ladder fixture request');
    }
    return http.StreamedResponse(Stream.value(const <int>[]), 400);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const brightness = MethodChannel('github.com/aaassseee/screen_brightness');
  const wake =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  late PlayerTerminalBackend? previous;
  late _Terminal terminal;
  DatabaseFactory? previousDatabaseFactory;
  Directory? ownedRoot;
  String? verifiedParent;
  Object? primaryFailure;
  StackTrace? primaryStack;
  final requests = <String>[];

  setUpAll(() {
    previousDatabaseFactory = databaseFactoryOrNull;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });
  tearDownAll(() {
    databaseFactoryOrNull = previousDatabaseFactory;
  });

  setUp(() async {
    primaryFailure = null;
    primaryStack = null;
    requests.clear();
    previous = PlayerTerminalBackend.debugOverride;
    terminal = _Terminal();
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'episode-ladder-origin');
    StorageService.resetProfileCaches();
    final parent = await Directory(
      '.dart_tool',
    ).absolute.create(recursive: true);
    verifiedParent = await parent.resolveSymbolicLinks();
    ownedRoot = await parent.createTemp('episode-ladder-origin-');
    AppStorage.debugOverride(
      documents: ownedRoot!,
      support: ownedRoot!,
      cache: ownedRoot!,
    );
    await DebrifyTvDatabase.instance.debugResetScopeState();
    await DebrifyTvDatabase.instance.database;
    await TVMazeService.clearCache();
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
    PlayerTerminalBackend.debugOverride = terminal;
  });

  tearDown(() async {
    try {
      final backend = terminal.properties;
      if (backend != null && !backend.closed) {
        // Safety only. A successful case already required host close.
        debugPrintSynchronously('LADDER_SAFETY_CLOSE');
        await binding.runAsync(() async {
          await (backend.disposal ?? backend.dispose()).timeout(
            const Duration(milliseconds: 250),
          );
        });
      }
      terminal.video?.close();
      await DebrifyTvDatabase.instance.debugResetScopeState();
      final root = ownedRoot;
      if (root != null) {
        final actual = await root.resolveSymbolicLinks();
        final parent = verifiedParent!;
        if (!actual.startsWith('$parent${Platform.pathSeparator}') ||
            !actual
                .substring(parent.length + 1)
                .startsWith('episode-ladder-origin-') ||
            actual
                .substring(parent.length + 1)
                .contains(Platform.pathSeparator)) {
          throw StateError('Owned temporary directory boundary mismatch');
        }
        await root.delete(recursive: true);
        ownedRoot = null;
      }
      expect(PlayerTerminalBackend.debugOverride, same(terminal));
      expect(terminal.unexpected, isEmpty);
    } catch (error, stack) {
      debugPrintSynchronously('LADDER_TEARDOWN $error\n$stack');
      rethrow;
    } finally {
      try {
        PlayerTerminalBackend.debugOverride = previous;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(window, null);
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          brightness,
          null,
        );
        binding.defaultBinaryMessenger.setMockMessageHandler(wake, null);
      } finally {
        StorageService.resetProfileCaches();
        AppStorage.debugReset();
        ProfileRuntime.debugReset();
        SecretVault.debugReset();
      }
    }
  });

  Controls controls(WidgetTester tester) =>
      tester.widget<Controls>(find.byType(Controls));
  // The host's video slot is the first child of its expand Stack: the video
  // texture while playable, a black Container while a transition blocks.
  Finder slot(bool Function(Widget first) matches) => find.byWidgetPredicate(
    (w) =>
        w is Stack &&
        w.fit == StackFit.expand &&
        w.children.isNotEmpty &&
        matches(w.children.first),
  );
  final videoSlot = slot((first) => first is mkv.Video);
  final blackSlot = slot(
    (first) => first is Container && first.color == Colors.black,
  );
  final fetching = find.text('Fetching S01E03…');
  final nothingFound = find.text('No playable source found for S01E03');

  // Fixed bound: 80 event turns, 50ms per frame. The root event turn lets
  // real SQLite/file Futures settle; there is no sleep.
  Future<void> reach(
    WidgetTester tester,
    bool Function() predicate, {
    String reason = 'phase',
    int turns = 80,
  }) async {
    for (var i = 0; i < turns && !predicate(); i++) {
      await tester.runAsync(() => Future<void>(() {}));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(predicate(), isTrue, reason: 'Did not complete: $reason');
  }

  // Elapse fake time frame by frame so SnackBar entrance, timer and exit
  // animations each get their own frames.
  Future<void> elapse(WidgetTester tester, Duration total) async {
    for (
      var t = Duration.zero;
      t < total;
      t += const Duration(milliseconds: 100)
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Torrent direct(int index, String name) => Torrent(
    rowid: index,
    infohash: '',
    name: name,
    sizeBytes: 1,
    createdUnix: 0,
    seeders: 0,
    leechers: 0,
    completed: 0,
    scrapedDate: 0,
    streamType: StreamType.directUrl,
    directUrl: 'https://ladder.invalid/source/$index',
  );
  Torrent pack(int index, String name, {required int seasonNumber}) => Torrent(
    rowid: index,
    infohash: 'ladder-pack-$index',
    name: name,
    sizeBytes: 1,
    createdUnix: 0,
    seeders: 0,
    leechers: 0,
    completed: 0,
    scrapedDate: 0,
    coverageType: 'seasonPack',
    seasonNumber: seasonNumber,
  );

  Future<void> withHost(
    WidgetTester tester,
    Future<void> Function(_Properties) exercise, {
    required List<Torrent> sources,
    required Future<List<PlaylistEntry>?> Function(Torrent) resolve,
    required SeriesSourceFetcher fetcher,
    void Function()? releaseOwnedGates,
  }) async {
    await HttpOverrides.runZoned(() async {
      await http.runWithClient(() async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          await tester.pumpWidget(
            MaterialApp(
              builder: (_, child) => AppThemeScope(
                theme: AppThemes.byId('spotlight'),
                child: child!,
              ),
              home: VideoPlayerScreen(
                videoUrl: '',
                title: 'Ladder S01E01',
                disableAutoResume: true,
                stremioSources: sources,
                resolveSourceToPlaylist: resolve,
                seriesSourceFetcher: fetcher,
              ),
            ),
          );
          // Fixed setup budget. Missing construction is STOP, not a loop.
          await tester.pump();
          await tester.pump();
          expect(terminal.construction, ['bootstrap', 'player', 'video']);
          final backend = terminal.properties!;
          backend.configuration.ready!();
          // No duration yet: the source switch's outgoing checkpoint save is
          // a no-op, so the ladder never waits on profile storage.
          backend.emitPlayback(
            Duration.zero,
            playing: true,
            duration: Duration.zero,
          );
          await tester.pump();
          expect(find.byType(Controls), findsOneWidget);
          expect(videoSlot, findsOneWidget);
          expect(blackSlot, findsNothing);
          expect(backend.reads, isEmpty);
          expect(terminal.player!.operations, isEmpty);
          await exercise(backend);
          expect(terminal.unexpected, isEmpty);
          expect(tester.takeException(), isNull);
        } catch (error, stack) {
          primaryFailure = error;
          primaryStack = stack;
          debugPrintSynchronously('LADDER_PRIMARY $error\n$stack');
          rethrow;
        } finally {
          try {
            Object? unmountFailure;
            StackTrace? unmountStack;
            try {
              await tester.pumpWidget(const SizedBox.shrink());
            } catch (error, stack) {
              unmountFailure = error;
              unmountStack = stack;
              rethrow;
            } finally {
              try {
                releaseOwnedGates?.call();
                final gate = terminal.player?.openGate;
                if (gate != null && !gate.isCompleted) gate.complete();
              } catch (error, stack) {
                debugPrintSynchronously('LADDER_RELEASE $error\n$stack');
                if (unmountFailure != null) {
                  Error.throwWithStackTrace(unmountFailure, unmountStack!);
                }
                rethrow;
              }
            }
            await tester.pump(const Duration(milliseconds: 250));
            final backend = terminal.properties;
            if (backend != null) {
              expect(
                backend.disposal,
                isNotNull,
                reason: 'Host must initiate real terminal disposal',
              );
              expect(
                backend.closed,
                isTrue,
                reason: 'Actual close must finish at declared cleanup boundary',
              );
              await tester.runAsync(() => backend.disposal!);
            }
            expect(VideoOutputLease.isHeld, isFalse);
            expect(terminal.unexpected, isEmpty);
            expect(tester.takeException(), isNull);
          } catch (error, stack) {
            debugPrintSynchronously('LADDER_CLEANUP $error\n$stack');
            if (primaryFailure != null) {
              Error.throwWithStackTrace(primaryFailure!, primaryStack!);
            }
            rethrow;
          }
        }
      }, () => _MetadataClient(terminal.unexpected, requests));
    }, createHttpClient: (_) => _NoHttpClient(terminal.unexpected));
  }

  // Real caller path: Controls -> host playlist sheet -> rendered
  // SeriesBrowser. The guide's own tap pops the sheet first and then reports
  // the season/episode; S01E03 is absent from the (synthetic) playlist.
  Future<void Function(int, int)> openGuide(WidgetTester tester) async {
    expect(controls(tester).hasPlaylist, isTrue);
    controls(tester).onShowPlaylist();
    final browser = find.byType(SeriesBrowser);
    await reach(tester, () => browser.evaluate().isNotEmpty, reason: 'guide');
    final rendered = tester.widget<SeriesBrowser>(browser);
    expect(rendered.showAllEpisodes, isTrue);
    Navigator.of(tester.element(browser)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(browser, findsNothing);
    return (season, episode) => rendered.onEpisodeSelected(season, episode);
  }

  testWidgets(
    'old host ladder ignores a second selection while a fetch is in flight',
    (tester) async {
      final resolved = <String>[];
      final fetched = <String>[];
      final gate = Completer<List<PlaylistEntry>?>();
      await withHost(
        tester,
        (backend) async {
          final select = await openGuide(tester);
          select(1, 3);
          await tester.pump();
          expect(fetching, findsOneWidget);
          expect(resolved, ['Ladder S01E03 first']);
          // Second request while the first resolver is still held open.
          select(1, 3);
          await tester.pump();
          await elapse(tester, const Duration(seconds: 4));
          expect(resolved, ['Ladder S01E03 first']);
          expect(fetched, isEmpty);
          expect(fetching, findsNothing); // No queued duplicate snackbar.
          gate.complete(null);
          await reach(
            tester,
            () => nothingFound.evaluate().isNotEmpty,
            reason: 'failure snackbar',
          );
          expect(fetched, ['episodes:1:3', 'packs:1:3']);
          expect(resolved, ['Ladder S01E03 first']);
          expect(terminal.player!.operations, isEmpty);
          expect(videoSlot, findsOneWidget);
          expect(blackSlot, findsNothing);
          // The guard is released: a later request runs the ladder again.
          select(1, 3);
          await tester.pump();
          expect(resolved, ['Ladder S01E03 first', 'Ladder S01E03 first']);
          await reach(
            tester,
            () => fetched.length == 4,
            reason: 'second ladder pass',
          );
          expect(fetched, [
            'episodes:1:3',
            'packs:1:3',
            'episodes:1:3',
            'packs:1:3',
          ]);
        },
        sources: [
          direct(0, 'Ladder S01E01 current'),
          direct(1, 'Ladder S01E03 first'),
        ],
        resolve: (t) {
          resolved.add(t.name);
          return gate.isCompleted ? Future.value(null) : gate.future;
        },
        fetcher: SeriesSourceFetcher(
          searchPacks: (s, e) async {
            fetched.add('packs:$s:$e');
            return null;
          },
          searchEpisodes: (s, e) async {
            fetched.add('episodes:$s:$e');
            return null;
          },
          season: 1,
          episode: 1,
        ),
        releaseOwnedGates: () {
          if (!gate.isCompleted) gate.complete(null);
        },
      );
      expect(requests, isNotEmpty);
      expect(requests.every((r) => r.contains('api.tvmaze.com')), isTrue);
    },
  );

  testWidgets(
    'old host ladder switches to the first listed candidate that resolves to the episode',
    (tester) async {
      final resolved = <String>[];
      final fetched = <String>[];
      await withHost(
        tester,
        (backend) async {
          backend.allowSourceOpen = true;
          final player = terminal.player!;
          player.openGate = Completer<void>();
          final select = await openGuide(tester);
          select(1, 3);
          await tester.pump();
          expect(fetching, findsOneWidget);
          await reach(tester, () => player.openEntered, reason: 'open');
          // The current source (index 0) is skipped; index 1 is the episode.
          expect(resolved, ['Ladder S01E03 single']);
          expect(fetched, isEmpty);
          expect(player.operations, ['pause', 'open']);
          expect(player.openPlay, [true]);
          expect(
            (player.opened.single as mk.Media).uri,
            'https://ladder.invalid/play/s01e03.mp4',
          );
          // Blocking: the black slot replaces the video while the open is held.
          expect(videoSlot, findsNothing);
          expect(find.byType(mkv.Video), findsNothing);
          expect(blackSlot, findsOneWidget);
          player.openGate!.complete();
          await reach(tester, () => player.openCompleted, reason: 'open-done');
          // The open itself carried play; the switch stays blocked until the
          // new media reports a duration and the load path settles.
          expect(player.operations, ['pause', 'open', 'open-done']);
          expect(blackSlot, findsOneWidget);
          backend.emitPlayback(Duration.zero, playing: true);
          await reach(
            tester,
            () => videoSlot.evaluate().isNotEmpty,
            reason: 'video slot restored',
            turns: 200,
          );
          expect(player.operations, ['pause', 'open', 'open-done']);
          expect(player.seeks, isEmpty);
          expect(videoSlot, findsOneWidget);
          expect(blackSlot, findsNothing);
          expect(backend.reads, isEmpty);
          expect(backend.writes.where((x) => x.$1 != 'video-zoom').toList(), [
            ('sub-delay', '0.000'),
            ('stream-lavf-o', ''),
            ('sub-visibility', 'no'),
          ]);
          expect(nothingFound, findsNothing);
          await elapse(tester, const Duration(seconds: 4));
          expect(nothingFound, findsNothing);
          expect(resolved, ['Ladder S01E03 single']);
          expect(fetched, isEmpty);
        },
        sources: [
          direct(0, 'Ladder S01E01 current'),
          direct(1, 'Ladder S01E03 single'),
          direct(2, 'Ladder S01E03 never reached'),
        ],
        resolve: (t) async {
          resolved.add(t.name);
          return const [
            PlaylistEntry(
              url: 'https://ladder.invalid/play/s01e03.mp4',
              title: 'Ladder S01E03',
            ),
          ];
        },
        fetcher: SeriesSourceFetcher(
          searchPacks: (s, e) async {
            fetched.add('packs:$s:$e');
            return null;
          },
          searchEpisodes: (s, e) async {
            fetched.add('episodes:$s:$e');
            return null;
          },
          season: 1,
          episode: 1,
        ),
      );
    },
  );

  testWidgets(
    'old host ladder rejects wrong-season packs, packs without the episode and wrong-episode singles',
    (tester) async {
      final resolved = <String>[];
      final fetched = <String>[];
      await withHost(
        tester,
        (backend) async {
          final select = await openGuide(tester);
          select(1, 3);
          await tester.pump();
          expect(fetching, findsOneWidget);
          await reach(
            tester,
            () => nothingFound.evaluate().isNotEmpty,
            reason: 'failure snackbar',
          );
          // Season-2 pack skipped by coverage; season-1 pack resolved but
          // lacks S01E03; the fetched single resolves to S01E04 (rejected);
          // the pack search comes last and throws (swallowed).
          expect(resolved, ['Ladder Season 1 pack', 'Ladder S01E03 fetched']);
          expect(fetched, ['episodes:1:3', 'packs:1:3']);
          expect(terminal.player!.operations, isEmpty);
          expect(videoSlot, findsOneWidget);
          expect(blackSlot, findsNothing);
        },
        sources: [
          direct(0, 'Ladder S01E01 current'),
          pack(1, 'Ladder Season 2 pack', seasonNumber: 2),
          pack(2, 'Ladder Season 1 pack', seasonNumber: 1),
        ],
        resolve: (t) async {
          resolved.add(t.name);
          if (t.name == 'Ladder Season 1 pack') {
            return const [
              PlaylistEntry(
                url: 'https://ladder.invalid/p/1.mp4',
                title: 'Ladder S01E01',
              ),
              PlaylistEntry(
                url: 'https://ladder.invalid/p/2.mp4',
                title: 'Ladder S01E02',
              ),
            ];
          }
          return const [
            PlaylistEntry(
              url: 'https://ladder.invalid/f/4.mp4',
              title: 'Ladder S01E04',
            ),
          ];
        },
        fetcher: SeriesSourceFetcher(
          searchPacks: (s, e) async {
            fetched.add('packs:$s:$e');
            throw StateError('pack search down');
          },
          searchEpisodes: (s, e) async {
            fetched.add('episodes:$s:$e');
            return [direct(9, 'Ladder S01E03 fetched')];
          },
          season: 1,
          episode: 1,
        ),
      );
    },
  );
}
