import 'dart:async';

import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'fake_player.dart';
import 'video_player_environment.dart';
import 'vp_fixture_actions.dart';

Torrent startupSource(
  String name, {
  StreamType type = StreamType.directUrl,
  String? url,
  String? addon,
  Map<String, String>? headers,
}) => Torrent(
  rowid: 0,
  infohash: type == StreamType.torrent
      ? '0123456789012345678901234567890123456789'
      : '',
  name: name,
  sizeBytes: 1,
  createdUnix: 0,
  seeders: 1,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
  source: addon ?? 'fixture',
  streamType: type,
  directUrl: url ?? 'https://startup.test/$name.mp4',
  stremioAddonId: addon,
  httpHeaders: headers,
);

class StartupSubscription {
  StartupSubscription(this.owner, this.channel, this.player);
  final String owner;
  final String channel;
  final FakePlayer player;
  bool cancelled = false;
  int deliveries = 0;
}

class _ObservedStream<T> extends Stream<T> {
  _ObservedStream(this.source, this.record);
  final Stream<T> source;
  final StartupSubscription? Function() record;
  @override
  bool get isBroadcast => source.isBroadcast;
  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final entry = record();
    final subscription = source.listen(
      (value) {
        if (entry != null) entry.deliveries++;
        onData?.call(value);
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return _ObservedSubscription(subscription, entry);
  }
}

class _ObservedSubscription<T> implements StreamSubscription<T> {
  _ObservedSubscription(this.source, this.entry);
  final StreamSubscription<T> source;
  final StartupSubscription? entry;
  @override
  Future<void> cancel() {
    entry?.cancelled = true;
    return source.cancel();
  }

  @override
  void onData(void Function(T)? handler) => source.onData(handler);
  @override
  void onError(Function? handler) => source.onError(handler);
  @override
  void onDone(void Function()? handler) => source.onDone(handler);
  @override
  void pause([Future<void>? resumeSignal]) => source.pause(resumeSignal);
  @override
  void resume() => source.resume();
  @override
  bool get isPaused => source.isPaused;
  @override
  Future<E> asFuture<E>([E? futureValue]) => source.asFuture(futureValue);
}

/// Drives public player/widget callbacks; never accesses State or substitutes
/// the implementation. Observes subscriptions, native entry, acknowledgement,
/// probe cancellation and caller commits as separate boundaries.
class StartupDriver {
  StartupDriver(this.t, {bool native = false, this.autoFrame = false}) {
    f = VideoPlayerEnvironment(native: native, configurePlayer: _configure);
  }
  final WidgetTester t;
  final bool autoFrame;
  late final VideoPlayerEnvironment f;
  final logs = <String>[];
  final trace = <String>[];
  final errors = <Object>[];
  final subscriptions = <StartupSubscription>[];
  final commits = <Torrent>[];
  final opens = <String>[];
  final openGates = <String, Completer<void>>{};
  final openFailures = <String, Object>{};
  final timers = <(Duration, Timer)>[];
  final periodic = <(Duration, Timer)>[];
  final timerCreated = <Timer, DateTime>{};
  final timerOrigins = <Timer, String>{};
  final replies = <String, void Function(FakePlayer)>{};
  Completer<void>? prearm;
  bool prearmEntered = false;
  Object? routeResult;
  bool routeReturned = false;
  DebugPrintCallback? previousPrint;
  ValueNotifier<VideoPlayerScreen>? screenValue;
  Future<void> Function(Torrent)? onCommit;
  FakePlayer get player => f.player;
  List<StartupSubscription> get probeSubscriptions => subscriptions
      .where((s) => s.owner == 'vod' || s.owner == 'debrid')
      .toList();
  List<StartupSubscription> get activeProbes =>
      probeSubscriptions.where((s) => !s.cancelled).toList();
  List<String> event(String event) =>
      logs.where((s) => s.contains('[StartupFailover] event=$event ')).toList();

  void _configure(FakePlayer p) {
    p.observeStream = (name, source) => _ObservedStream(source, () {
      final stack = StackTrace.current.toString();
      final owner = stack.contains('tryOpenStartupVod')
          ? 'vod'
          : stack.contains('openStartupDebridDirect')
          ? 'debrid'
          : stack.contains('watchStremioTvStartup')
          ? 'tv'
          : null;
      if (owner == null) return null;
      final entry = StartupSubscription(owner, name, p);
      subscriptions.add(entry);
      trace.add('subscribe:$owner:$name');
      return entry;
    });
    p.heldOperation = (name, value) =>
        name == 'open' &&
        openGates.containsKey(
          ((value as (mk.Playable, bool)).$1 as mk.Media).uri,
        );
    p.beforeOperation = (name, value) async {
      if (name != 'open') return;
      final url = ((value as (mk.Playable, bool)).$1 as mk.Media).uri;
      opens.add(url);
      trace.add('native-open:$url');
      await openGates[url]?.future;
      trace.add('open-operation-release:$url');
      if (openFailures.containsKey(url)) throw openFailures.remove(url)!;
    };
    p.onOpenAcknowledged = () {
      trace.add('open-ack:${p.state.playlist.medias.first.uri}');
    };
    p.onOpen = () {
      final url = p.state.playlist.medias.first.uri;
      trace.add('published-open:$url');
      if (replies.containsKey(url)) {
        replies[url]!(p);
      } else if (autoFrame) {
        p.publishFrame();
        f.controllers.last.publishFrame();
      }
    };
    if (p.platform case final FakeNativePlayer native) {
      native.heldOperation = (name, value) =>
          name == 'setProperty' &&
          (value as (String, String)).$1 == 'stream-lavf-o' &&
          prearm != null &&
          !prearm!.isCompleted;
      native.beforeOperation = (name, value) async {
        if (name == 'setProperty' &&
            (value as (String, String)).$1 == 'stream-lavf-o') {
          prearmEntered = true;
          trace.add('pre-arm');
          await prearm?.future;
          trace.add('setup-complete');
        }
      };
    }
  }

  Future<void> initialize() async {
    await t.runAsync(f.initialize);
    previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
      previousPrint!(message, wrapWidth: wrapWidth);
    };
  }

  Future<void> rules({
    int attempts = 3,
    bool tryNext = true,
    bool series = false,
  }) => f.finish(
    t,
    QuickPlayStorage.setQuickPlayRules(
      QuickPlayRules.debrifyDefault(
        isMovie: !series,
      ).copyWith(maxAttempts: attempts, tryNextOnFailure: tryNext),
      isMovie: !series,
    ),
  );

  VideoPlayerScreen screen({
    String? type = 'movie',
    List<Torrent>? sources,
    String? url,
    int? index,
    bool failover = false,
    String? provider,
    bool commitCallback = true,
    Future<String?> Function(Torrent)? resolve,
    Future<List<PlaylistEntry>?> Function(
      Torrent, {
      bool Function()? canContinue,
    })?
    playlist,
    Future<void> Function()? exhausted,
    List<PlaylistEntry>? entries,
    int? season,
    int? episode,
    String? id,
    double? startAtPercent,
    bool trakt = false,
    bool simkl = false,
    bool mdblist = false,
  }) => VideoPlayerScreen(
    videoUrl:
        url ??
        (sources?.isNotEmpty == true ? sources!.first.directUrl : null) ??
        'https://startup.test/original.mp4',
    title: 'P16 startup',
    contentType: type,
    contentSeason: season,
    contentEpisode: episode,
    contentImdbId: id,
    startAtPercent: startAtPercent,
    traktScrobble: trakt,
    simklScrobble: simkl,
    mdblistScrobble: mdblist,
    playlist: entries,
    stremioSources: sources,
    stremioCurrentSourceIndex: index,
    startupFailoverEnabled: failover,
    startupResolverProvider: provider,
    resolveStremioSource: resolve,
    resolveSourceToPlaylist: playlist,
    onStartupSourcesExhausted: exhausted,
    onStremioSourceCommitted: !commitCallback
        ? null
        : (source) async {
            commits.add(source);
            trace.add('caller-commit:${source.name}');
            await onCommit?.call(source);
          },
  );

  T observe<T>(T Function() action) => runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      handleUncaughtError: (self, parent, zone, error, stack) =>
          errors.add(error),
      createTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createTimer(zone, duration, callback);
        timers.add((duration, timer));
        timerCreated[timer] = t.binding.clock.now();
        timerOrigins[timer] = StackTrace.current.toString();
        return timer;
      },
      createPeriodicTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createPeriodicTimer(zone, duration, callback);
        periodic.add((duration, timer));
        return timer;
      },
    ),
  );

  Future<void> begin(VideoPlayerScreen screen) => observe(() async {
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: f.navigator,
        theme: ThemeData.dark(),
        home: const Scaffold(body: Text('P16 launcher')),
      ),
    );
    screenValue = ValueNotifier(screen);
    f.navigator.currentState!
        .push<Object?>(
          MaterialPageRoute(
            builder: (_) => ValueListenableBuilder<VideoPlayerScreen>(
              valueListenable: screenValue!,
              builder: (_, value, _) => value,
            ),
          ),
        )
        .then((value) {
          routeReturned = true;
          routeResult = value;
        });
    await f.until(t, () => f.players.isNotEmpty);
    expect(player.readyDelivered, isFalse);
    player.deliverReady();
    await f.advance(t);
  });

  Future<void> update(VideoPlayerScreen screen) async {
    screenValue!.value = screen;
    await tick();
  }

  Future<void> openEntered([int count = 1]) => f.until(
    t,
    () => opens.length >= count,
    reason: 'Real candidate must enter native open',
  );
  Future<void> result({int count = 1}) =>
      f.until(t, () => event('candidate_result').length >= count);
  Future<void> tick([Duration duration = Duration.zero]) =>
      f.advance(t, duration);
  Future<void> settle() => f.actions.settle(t);
  Future<void> initialized() => f.until(
    t,
    () => periodic.any((row) => row.$1 == const Duration(seconds: 6)),
    reason:
        'The original startup continuation must finish before ordinary teardown',
  );
  Future<void> committed([int count = 1]) => f.until(
    t,
    () => commits.length >= count,
    reason: 'Caller commit proves probe has returned',
  );
  void frame({
    Duration duration = const Duration(minutes: 20),
    FakePlayer? target,
  }) {
    (target ?? player).publishFrame(duration: duration);
    f.controllers.last.publishFrame();
  }

  Future<SourceSheet> sheet({
    Duration duration = const Duration(milliseconds: 300),
  }) async {
    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tick(duration);
    expect(find.byType(SourceSheet), findsOneWidget);
    return t.widget<SourceSheet>(find.byType(SourceSheet));
  }

  VpFixtureTask<void> select(SourceSheet sheet, int index, String url) =>
      observe(
        () => f.actions.start('P16 public source selection', () async {
          final dynamic callback = sheet.onSourceSelected;
          final dynamic result = callback(index, url);
          if (result is Future) await result;
        }, held: true),
      );

  Future<void> close() async {
    prearm?.completeIfPending();
    for (final gate in openGates.values) {
      gate.completeIfPending();
    }
    try {
      await tick();
      if (activeProbes.isNotEmpty) {
        for (final p in f.players) {
          p.emit('error', 'fixture shutdown pending candidate');
        }
        await tick();
      }
      final succeeded =
          event('candidate_result').any((line) => line.contains('ok=true')) ||
          (subscriptions.any((s) => s.owner == 'tv') &&
              player.state.duration > Duration.zero);
      if (find.byType(VideoPlayerScreen).evaluate().isNotEmpty &&
          succeeded &&
          !routeReturned) {
        await initialized();
      }
      await f.close(t);
      expect(
        activeProbes,
        isEmpty,
        reason: 'Every original probe continuation cancels its subscriptions',
      );
      expect(errors, isEmpty);
    } finally {
      screenValue?.dispose();
      if (previousPrint != null) debugPrint = previousPrint!;
      VpS2Hooks.install(null);
    }
  }
}

extension StartupGateRelease on Completer<void> {
  void completeIfPending() {
    if (!isCompleted) complete();
  }
}
