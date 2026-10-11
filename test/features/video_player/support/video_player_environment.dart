import 'dart:async';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// Existing resolved plugin interface for test doubles; app dependencies are frozen.
// ignore: depend_on_referenced_packages
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// Existing resolved plugin interface for test doubles; app dependencies are frozen.
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../../support/catalog_detail_http_transport.dart';
import 'fake_player.dart';
import 'fake_video_controller.dart';

class VideoPlayerPaths extends PathProviderPlatform {
  VideoPlayerPaths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationCachePath() async => path;
  @override
  Future<String?> getDownloadsPath() async => path;
}

class VideoPlayerWake extends WakelockPlusPlatformInterface {
  final writes = <bool>[];
  @override
  Future<void> toggle({required bool enable}) async => writes.add(enable);
  @override
  Future<bool> get enabled async => writes.isNotEmpty && writes.last;
}

class VideoPlayerBrightness extends ScreenBrightnessPlatform {
  final calls = <Object>[];
  double value = 0.5;
  @override
  Future<double> get application async {
    calls.add('read');
    return value;
  }

  @override
  Future<void> setApplicationScreenBrightness(double brightness) async {
    calls.add(brightness);
    value = brightness;
  }

  @override
  Future<void> resetApplicationScreenBrightness() async => calls.add('reset');
}

class VideoPlayerHttp extends HttpOverrides {
  final requests = <http.Request>[];
  final replies = <String, http.Response>{};
  FutureOr<http.Response> Function(http.Request)? handler;
  @override
  HttpClient createHttpClient(SecurityContext? context) => http.runWithClient(
    CatalogFixtureHttpClient.new,
    () => MockClient((request) async {
      requests.add(request);
      if (handler != null) return await handler!(request);
      return replies[request.url.toString()] ??
          http.Response(
            '{}',
            404,
            headers: {'content-type': 'application/json'},
          );
    }),
  );
}

/// Uses existing profile/storage/platform boundaries. No extra State access,
/// platform predicate or service injection is added to application code.
class VideoPlayerEnvironment {
  VideoPlayerEnvironment({this.native = false, this.committed = true});
  final bool native;
  final bool committed;
  final players = <FakePlayer>[];
  final controllers = <FakeVideoController>[];
  final creationOrder = <String>[];
  final channels = <(String, MethodCall)>[];
  static final _sharedWake = VideoPlayerWake();
  final wake = _sharedWake;
  final brightness = VideoPlayerBrightness();
  final network = VideoPlayerHttp();
  final navigator = GlobalKey<NavigatorState>();
  late Directory directory;
  ProfileRegistry? registry;
  final oldPaths = PathProviderPlatform.instance;
  final oldWake = WakelockPlusPlatformInterface.instance;
  final oldBrightness = ScreenBrightnessPlatform.instance;
  final oldHttp = HttpOverrides.current;
  final channelNames = <String>[
    'flutter/platform',
    'window_manager',
    'com.debrify.app/downloader',
    'com.debrify.app/audio_effects',
    'com.debrify.app/privacy',
  ];
  FakePlayer get player => players.last;

  Future<void> initialize() async {
    final common = Process.runSync('git', [
      'rev-parse',
      '--path-format=absolute',
      '--git-common-dir',
    ]).stdout.toString().trim();
    final parent = Directory(
      '$common/refactor-evidence/vplayer/p1/harness-runtime',
    );
    await parent.create(recursive: true);
    directory = await parent.createTemp('case-');
    wake.writes.clear();
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfilePolicyGuard.updateActiveProfile(null);
    ProfilePreferenceBudget.debugReset();
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
    );
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    if (committed) {
      registry = await ProfileRegistry.open(
        path: '${directory.path}/profiles.db',
      );
      final profile = await registry!.createProfile(
        name: 'Player fixture',
        role: UserProfileRole.admin,
      );
      await registry!.commitBootstrap(
        activeProfileId: profile.id,
        migratedLegacyInstall: false,
      );
      final cipher = MemoryDeviceSecretCipher(List.generate(32, (i) => i + 1));
      await cipher.initialize();
      DeviceKeyProvider.debugInstallCipher(cipher);
      ProfileBootstrap.debugInstallRegistry(registry);
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: profile.id, dataGeneration: 1, sessionEpoch: 1),
      );
      ProfilePolicyGuard.updateActiveProfile(profile);
    } else {
      ProfileRuntime.initializeLegacy();
    }
    IptvMediaStore.debugResetMigration();
    SubtitleSettingsService.instance.resetProfileScope();
    SubtitleFontService.instance.resetProfileScope();
    PlatformUtil.debugSetTvOS(false);
    PlatformUtil.debugSetAndroidTvCached(false);
    AppThemeAdapter.debugUseTestTypography = true;
    PathProviderPlatform.instance = VideoPlayerPaths(directory.path);
    WakelockPlusPlatformInterface.instance = wake;
    ScreenBrightnessPlatform.instance = brightness;
    HttpOverrides.global = network;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in channelNames) {
      messenger.setMockMethodCallHandler(
        name == 'flutter/platform'
            ? SystemChannels.platform
            : MethodChannel(name),
        (call) async {
          channels.add((name, call));
          if (name == 'com.debrify.app/downloader') {
            if (call.method == 'isTelevision') return false;
            throw StateError('Unexpected downloader call ${call.method}');
          }
          return null;
        },
      );
    }
    VideoPlayerScreenTestHooks.install(
      VideoPlayerScreenTestHooks(
        ensureInitialized: () => creationOrder.add('media-kit-init'),
        createPlayer: (configuration) {
          creationOrder.add('player');
          final player = FakePlayer(configuration, native: native);
          players.add(player);
          player.onOpen = () {
            player.publishFrame();
            controllers.last.publishFrame();
          };
          return player;
        },
        createVideoController: (player, configuration) {
          creationOrder.add('video-controller');
          final controller = FakeVideoController(player, configuration);
          controllers.add(controller);
          return controller;
        },
      ),
    );
  }

  Future<void> advance(
    WidgetTester tester, [
    Duration time = Duration.zero,
  ]) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(time);
    expect(tester.takeException(), isNull);
  }

  Future<void> until(
    WidgetTester tester,
    bool Function() condition, {
    String? reason,
  }) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await advance(tester, const Duration(milliseconds: 20));
    }
    expect(condition(), isTrue, reason: reason);
  }

  Future<T> finish<T>(WidgetTester tester, Future<T> future) async {
    var completed = false;
    late T value;
    Object? failure;
    future.then(
      (result) {
        value = result;
        completed = true;
      },
      onError: (Object error) {
        failure = error;
        completed = true;
      },
    );
    await until(
      tester,
      () => completed,
      reason: 'Original action must complete',
    );
    if (failure != null) throw failure!;
    return value;
  }

  Future<void> mount(WidgetTester tester, VideoPlayerScreen screen) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData.dark(),
        home: screen,
      ),
    );
    await until(
      tester,
      () => controllers.isNotEmpty,
      reason: 'Original must create player and controller',
    );
    expect(player.readyDelivered, isFalse);
    player.deliverReady();
    await until(
      tester,
      () => player.calls.any((call) => call.$1 == 'open'),
      reason: 'Original must open media',
    );
    for (var i = 0; i < 20; i++) {
      await advance(tester, const Duration(milliseconds: 100));
    }
    expect(find.byType(mkv.Video), findsOneWidget);
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await advance(tester, const Duration(milliseconds: 50));
  }

  Future<void> close(
    WidgetTester tester, {
    Future<void> Function()? inspectStorage,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await until(
      tester,
      () => players.every((p) => p.disposed.isCompleted),
      reason: 'Original disposal must complete',
    );
    await advance(tester, const Duration(milliseconds: 500));
    expect(VideoOutputLease.isHeld, isFalse);
    // Widget binding checks pending timers when the test ends; the fixture
    // never cancels production timers or uses an unbounded pumpAndSettle.
    for (final controller in controllers) {
      controller.close();
    }
    for (final player in players) {
      await player.closeStreams();
    }
    VideoPlayerScreenTestHooks.install(null);
    for (var i = 0; i < 20; i++) {
      await advance(tester, const Duration(milliseconds: 50));
    }
    if (inspectStorage != null) await tester.runAsync(inspectStorage);
    var databaseClosed = false;
    DebrifyTvDatabase.instance.debugResetScopeState().then(
      (_) => databaseClosed = true,
    );
    await until(
      tester,
      () => databaseClosed,
      reason: 'Database scope cleanup must drain',
    );
    await tester.runAsync(() async {
      await registry?.close();
    });
    ProfilePolicyGuard.updateActiveProfile(null);
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    SubtitleSettingsService.instance.resetProfileScope();
    SubtitleFontService.instance.resetProfileScope();
    AppStorage.debugReset();
    PathProviderPlatform.instance = oldPaths;
    WakelockPlusPlatformInterface.instance = oldWake;
    ScreenBrightnessPlatform.instance = oldBrightness;
    HttpOverrides.global = oldHttp;
    for (final name in channelNames) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            name == 'flutter/platform'
                ? SystemChannels.platform
                : MethodChannel(name),
            null,
          );
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}
