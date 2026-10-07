import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/settings/recordings_page.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/legacy_theme_boundary.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'profile_fixture.dart';

const recordingsCanvas = ValueKey('recordings-original-canvas');

Finder recordingsType(String name) =>
    find.byWidgetPredicate((widget) => widget.runtimeType.toString() == name);

class RecordingsNetwork extends HttpOverrides {}

class RecordingsPaths extends PathProviderPlatform {
  RecordingsPaths(this.directory);
  final Directory directory;
  int reads = 0;
  Completer<String?>? held;
  @override
  Future<String?> getDownloadsPath() async {
    reads++;
    return held == null ? directory.path : held!.future;
  }
}

class RecordingsObserver extends NavigatorObserver {
  RecordingsObserver(this.pageKey);
  final GlobalKey pageKey;
  final players = <VideoPlayerScreen>[];
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    routes.add(route);
    if (route is MaterialPageRoute && pageKey.currentContext != null) {
      Widget built = route.builder(pageKey.currentContext!);
      if (built is LegacyThemeBoundary) built = built.child;
      if (built is Builder) built = built.builder(pageKey.currentContext!);
      if (built is VideoPlayerScreen) {
        players.add(built);
        scheduleMicrotask(() {
          if (route.isActive) navigator!.removeRoute(route);
        });
      }
    }
  }
}

class RecordingsFixture {
  final pageKey = GlobalKey();
  final navigator = GlobalKey<NavigatorState>();
  late final observer = RecordingsObserver(pageKey);
  late Directory directory;
  late RecordingsPaths paths;
  late PathProviderPlatform previousPaths;
  late ProfileRegistry registry;
  ProfileFixture? committed;
  final captures = <DesktopRecordingCapture>[];
  final servers = <HttpServer>[];
  final responses = <HttpResponse>[];
  bool television = false;
  bool drainScheduleDeadline = false;
  Directory get library => Directory('${directory.path}/Debrify/Recordings');

  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfilePreferenceBudget.debugReset();
    directory = await Directory.systemTemp.createTemp('recordings-original-');
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    registry = await ProfileRegistry.open(
      path: '${directory.path}/profiles.db',
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    IptvMediaStore.debugResetMigration();
    previousPaths = PathProviderPlatform.instance;
    paths = RecordingsPaths(directory);
    PathProviderPlatform.instance = paths;
    PlatformUtil.debugSetTvOS(false);
    PlatformUtil.debugSetAndroidTvCached(false);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    AppThemeAdapter.debugUseTestTypography = true;
    DesktopScheduleService.instance.shutdown();
  }

  DesktopSchedule schedule(
    String id, {
    DateTime? start,
    String? owner,
    String title = '',
  }) {
    final time = start ?? DateTime.now().add(const Duration(hours: 3));
    return DesktopSchedule(
      id: id,
      channelName: 'Channel $id',
      url: 'http://recordings.test/$id.ts',
      headers: const {'X-Recording': 'original'},
      startMs: time.millisecondsSinceEpoch,
      endMs: time.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      programmeTitle: title,
      ownerProfileId:
          owner ??
          (ProfileRuntime.isProfileCommitted
              ? ProfileRuntime.capture().profileId
              : 'legacy-admin-v1'),
    );
  }

  Future<ProfileFixture> profiles() async {
    await registry.close();
    final fixture = ProfileFixture();
    await fixture.open();
    committed = fixture;
    registry = fixture.registry;
    return fixture;
  }

  Future<void> seedSchedules(List<DesktopSchedule> schedules) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'desktop_recording_schedules_v1',
      jsonEncode([for (final schedule in schedules) schedule.toJson()]),
    );
  }

  Future<File> file(String name, {int bytes = 1024, DateTime? modified}) async {
    await library.create(recursive: true);
    final file = File('${library.path}/$name');
    final sink = await file.open(mode: FileMode.write);
    await sink.truncate(bytes);
    await sink.close();
    await file.setLastModified(modified ?? DateTime(2024, 3, 1, 12));
    return file;
  }

  Future<DesktopRecordingCapture> capture({
    int bytes = 188,
    String? path,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servers.add(server);
    final connected = Completer<void>();
    server.listen((request) async {
      responses.add(request.response);
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType('video', 'mp2t');
      if (bytes > 0) request.response.add(List.filled(bytes, 0x47));
      await request.response.flush();
      if (!connected.isCompleted) connected.complete();
    });
    final capture = await HttpOverrides.runWithHttpOverrides(
      () => DesktopRecordingService.instance.start(
        url: 'http://127.0.0.1:${server.port}/capture.ts',
        path: path ?? '${library.path}/Capture_${captures.length}.ts',
        channelName: 'Live ${captures.length}',
        headers: const {},
      ),
      RecordingsNetwork(),
    );
    expect(capture, isNotNull, reason: 'public desktop capture starts');
    captures.add(capture!);
    if (bytes > 0) {
      await connected.future.timeout(const Duration(seconds: 10));
      for (var i = 0; i < 200 && capture.bytes != bytes; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(capture.bytes, bytes, reason: 'real HTTP bytes reached capture');
    }
    return capture;
  }

  Future<void> settle(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 3)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await settle(tester, frames: 1);
    }
    expect(ready(), isTrue, reason: 'recordings public boundary ready');
  }

  Future<void> mount(WidgetTester tester, {bool wait = true}) async {
    PlatformUtil.debugSetAndroidTvCached(television);
    tester.view.physicalSize = television
        ? const Size(1920, 1080)
        : const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        locale: const Locale('en', 'US'),
        theme: AppThemeAdapter.themed(
          AppThemes.byId('spotlight'),
          TextBrightness.bright,
        ).copyWith(platform: TargetPlatform.macOS),
        builder: (context, child) => AppThemeScope(
          theme: AppThemes.byId('spotlight'),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.noScaling,
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
        home: RepaintBoundary(
          key: recordingsCanvas,
          child: RecordingsPage(key: pageKey),
        ),
      ),
    );
    if (wait) {
      await until(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      );
      await settle(tester);
    }
  }

  Future<void> revision(WidgetTester tester, {bool desktop = false}) async {
    if (desktop) {
      DesktopRecordingService.instance.revision.value++;
    } else {
      LiveRecordingService.schedulesRevision.value++;
    }
    await settle(tester);
  }

  ValueNotifier<DateTime> clock(WidgetTester tester) =>
      tester
              .widget<ValueListenableBuilder<DateTime>>(
                find.byType(ValueListenableBuilder<DateTime>).first,
              )
              .valueListenable
          as ValueNotifier<DateTime>;

  Focus focus(WidgetTester tester, Finder within) => tester.widget<Focus>(
    find.descendant(of: within, matching: find.byType(Focus)).first,
  );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    if (paths.held != null && !paths.held!.isCompleted) {
      paths.held!.complete(directory.path);
    }
    await tester.pumpWidget(const SizedBox());
    DesktopScheduleService.instance.shutdown();
    final owned = {...captures, ...DesktopRecordingService.instance.captures};
    for (final capture in owned) {
      var closed = false;
      final stopping = capture.stop().then((_) => closed = true);
      for (var i = 0; i < 200 && !closed; i++) {
        await settle(tester, frames: 1);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(
        closed,
        true,
        reason: 'fixture awaits capture shutdown before resetting profile',
      );
      await stopping;
    }
    await tester.runAsync(() async {
      for (final server in servers) {
        await server.close(force: true);
      }
    });
    // stop() closes the pipe; its registry/artifact continuation then drains.
    await settle(tester);
    if (drainScheduleDeadline) {
      // The original scheduler's per-capture deadline is intentionally outside
      // shutdown()'s timer map. The stopped capture makes its late stop inert.
      await tester.pump(const Duration(days: 1));
    }
    await tester.runAsync(() async {
      await DebrifyTvDatabase.instance.closeScope();
      ProfileBootstrap.debugInstallRegistry(null);
      if (committed == null) {
        await registry.close();
      } else {
        await committed!.close();
      }
    });
    await settle(tester);
    PathProviderPlatform.instance = previousPaths;
    PlatformUtil.debugSetTvOS(null);
    PlatformUtil.debugSetAndroidTvCached(null);
    debugDefaultTargetPlatformOverride = null;
    AppThemeAdapter.debugUseTestTypography = false;
    ProfileRuntime.debugReset();
    ProfilePreferenceBudget.debugReset();
    AppStorage.debugReset();
    tester.view.reset();
    await tester.runAsync(() => directory.delete(recursive: true));
  }
}

Future<void> recordingsCase(
  WidgetTester tester,
  Future<void> Function(RecordingsFixture fixture) body,
) async {
  final fixture = RecordingsFixture();
  await tester.runAsync(fixture.initialize);
  try {
    await body(fixture);
  } finally {
    await fixture.dispose(tester);
  }
}
