import 'dart:async';
import 'dart:io';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'player_actions.dart';
import 'subtitle_apply_driver.dart';
import 'video_player_environment.dart';
import 'vp_fixture_actions.dart';

class RecordingPaths extends VideoPlayerPaths {
  RecordingPaths(super.path, this.driver);
  final RecordingDriver driver;
  Completer<String?>? gate;
  Object? failure;
  int reads = 0;
  @override
  Future<String?> getDownloadsPath() async {
    reads++;
    final activity = driver.f.actions.begin(
      'recording target directory',
      held: gate != null,
    );
    try {
      if (failure != null) throw failure!;
      return gate == null ? path : await gate!.future;
    } finally {
      activity.complete();
    }
  }
}

/// The real Record callback, real filesystem and service, S2d only for TEE.
class RecordingDriver extends SubtitleApplyDriver {
  RecordingDriver(super.t, {super.committed});
  late RecordingPaths paths;
  final captures = <DesktopRecordingCapture>[];
  final recordActions = <VpFixtureActivity>[];
  final wakeDrainMarker = Object();
  final servers = <HttpServer>[];
  final responses = <HttpResponse>[];
  final pumps = <Timer>[];
  final receivedHeaders = <String?>[];
  final realNetwork = _RecordingNetwork();
  IptvChannel channel(
    String url, {
    String name = 'Live / News',
    bool live = true,
    Map<String, String> attributes = const {},
  }) => IptvChannel(
    name: name,
    url: url,
    contentType: live ? 'live' : 'movie',
    attributes: attributes,
    httpHeaders: const {'X-Recording-Fixture': 'p13'},
  );
  Future<void> setup() async {
    await initialize();
    paths = RecordingPaths(f.directory.path, this);
    PathProviderPlatform.instance = paths;
  }

  Future<void> mountRecording({
    String? url,
    String? playingUrl,
    bool tee = true,
    bool live = true,
    String name = 'Live / News',
    String? sourceId,
    List<Map<String, dynamic>>? sources,
    Map<String, String> attributes = const {},
  }) async {
    final address = url ?? 'https://player.test/live.ts';
    await mount(
      screen: VideoPlayerScreen(
        videoUrl: playingUrl ?? address,
        title: 'Recording fixture',
        iptvChannels: [
          channel(address, name: name, live: live, attributes: attributes),
          channel(
            address.startsWith('http://127.0.0.1')
                ? Uri.parse(address).replace(path: '/other.ts').toString()
                : 'https://player.test/other.ts',
            name: 'Other',
          ),
        ],
        iptvStartIndex: 0,
        iptvSourceId: sourceId,
        iptvSources: sources,
      ),
    );
    VpS2Hooks.install(VpS2Hooks(ios: () => tee));
    expect(recordCallback, isNotNull);
    expect(offered, isTrue);
  }

  TvControls? get tvControls => find.byType(TvControls).evaluate().isEmpty
      ? null
      : t.widget<TvControls>(find.byType(TvControls));
  VoidCallback? get recordCallback =>
      tvControls == null ? playerControls(t).onRecord : tvControls!.onRecord;
  bool get offered => tvControls?.hasRecord ?? playerControls(t).hasRecord;
  void record() => observe(() {
    final dynamic callback = recordCallback!;
    final activity = f.actions.begin('public recording callback', held: true);
    recordActions.add(activity);
    final dynamic result = callback();
    if (result is Future) {
      result.then<void>(
        (_) => activity.complete(),
        onError: (Object error, StackTrace stack) {
          errors.add(error);
          activity.complete();
        },
      );
    } else {
      activity.complete();
    }
  });
  bool get active => tvControls?.isRecording ?? playerControls(t).isRecording;
  List<(String, Object?)> get propertyWrites => native.calls
      .where(
        (c) =>
            c.$1 == 'setProperty' &&
            (c.$2 as (String, String)).$1 == 'stream-record',
      )
      .toList();
  Future<String> armed() async {
    await f.until(
      t,
      () => propertyWrites.any((c) => (c.$2 as (String, String)).$2.isNotEmpty),
    );
    return (propertyWrites
                .firstWhere((c) => (c.$2 as (String, String)).$2.isNotEmpty)
                .$2
            as (String, String))
        .$2;
  }

  Future<void> started() => f.until(t, () => active);
  Future<void> dismissNotice() async {
    await f.advance(t, const Duration(milliseconds: 300));
    final notice = find.byType(SnackBar);
    if (notice.evaluate().isNotEmpty) {
      ScaffoldMessenger.of(t.element(notice.first)).removeCurrentSnackBar();
      await f.advance(t);
    }
  }

  Future<void> background() async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      t.binding.handleAppLifecycleStateChanged(state);
      await f.advance(t);
    }
  }

  Future<void> foreground() async {
    if (t.binding.lifecycleState == AppLifecycleState.paused) {
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await f.advance(t);
    }
    if (t.binding.lifecycleState == AppLifecycleState.hidden) {
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await f.advance(t);
    }
    if (t.binding.lifecycleState != AppLifecycleState.resumed) {
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await f.advance(t);
    }
  }

  Future<void> zap() async {
    final next = tvControls?.onNext ?? playerControls(t).onNext;
    expect(next, isNotNull);
    observe(next!);
    await f.advance(t);
  }

  Future<String> loopback() async => (await t.runAsync(() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(server);
    server.listen((request) {
      receivedHeaders.add(request.headers.value('X-Recording-Fixture'));
      final response = request.response;
      responses.add(response);
      response.bufferOutput = false;
      response.headers.contentType = ContentType('video', 'mp2t');
      void emit() {
        try {
          response.add(List.filled(188, 0x47));
        } catch (_) {}
      }

      emit();
      // Real loopback timer, serialized writes and explicit cancellation.
      pumps.add(
        Timer.periodic(const Duration(milliseconds: 20), (_) => emit()),
      );
    });
    return 'http://127.0.0.1:${server.port}/live.ts';
  }))!;
  void desktopRecord() =>
      HttpOverrides.runWithHttpOverrides(record, realNetwork);
  Future<DesktopRecordingCapture> captured(String url) async {
    await f.until(
      t,
      () => DesktopRecordingService.instance.captureForUrl(url) != null,
    );
    final capture = DesktopRecordingService.instance.captureForUrl(url)!;
    captures.add(capture);
    await f.until(t, () => capture.bytes >= 188);
    return capture;
  }

  Future<void> removePlayer() async {
    VpS2Hooks.install(null);
    await t.pumpWidget(const SizedBox());
    await f.until(t, () => player.disposed.isCompleted);
  }

  @override
  Future<void> close() async {
    paths.gate?.completeIfPending(paths.path);
    await f.until(
      t,
      () => recordActions.every((a) => a.isCompleted),
      reason: 'Public recording callbacks must finish before capture cleanup',
    );
    await f.finish(t, DesktopRecordingService.instance.stopAll());
    await t.runAsync(() async {
      for (final server in servers) {
        await server.close(force: true);
      }
      for (final response in responses) {
        try {
          await response.close();
        } catch (_) {}
      }
    });
    for (final timer in pumps) {
      timer.cancel();
    }
    await f.actions.settle(t);
    await foreground();
    // Drain jobs/artifacts while their profile registry and filesystem still exist.
    VpS2Hooks.install(null);
    await super.close();
    late Future<void> wakeDrained;
    await t.runAsync(() async {
      wakeDrained = PlayerDisplayControls.instance.setWakelockOwner(
        wakeDrainMarker,
        false,
      );
    });
    await f.finish(t, wakeDrained);
  }
}

class _RecordingNetwork extends HttpOverrides {}

extension on Completer<String?> {
  void completeIfPending(String path) {
    if (!isCompleted) complete(path);
  }
}
