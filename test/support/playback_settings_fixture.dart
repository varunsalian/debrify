import 'dart:async';
import 'dart:io';

import 'package:debrify/screens/settings/external_player_settings_page.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class PlaybackPreferences extends InMemorySharedPreferencesStore {
  PlaybackPreferences() : super.empty();
  final writes = <(String, Object?)>[];
  Completer<void>? holdWrite;
  Completer<void>? holdRead;
  bool failRead = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes.add((key.replaceFirst('flutter.', ''), value));
    await holdWrite?.future;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    writes.add((key.replaceFirst('flutter.', ''), null));
    await holdWrite?.future;
    return super.remove(key);
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    await holdRead?.future;
    if (failRead) throw StateError('fixture preference read');
    return super.getAllWithParameters(parameters);
  }
}

class PlaybackPicker extends FilePicker {
  FilePickerResult? result;
  Completer<FilePickerResult?>? pending;
  final calls = <Map<String, Object?>>[];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls.add({
      'type': type,
      'allowMultiple': allowMultiple,
      'allowedExtensions': allowedExtensions,
      'dialogTitle': dialogTitle,
    });
    return pending == null ? result : await pending!.future;
  }
}

class PlaybackPaths extends PathProviderPlatform {
  PlaybackPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationCachePath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class PlaybackUrls extends UrlLauncherPlatform {
  final schemes = <String>[];
  @override
  LinkDelegate? get linkDelegate => null;
  @override
  Future<bool> canLaunch(String url) async {
    schemes.add(url);
    return false;
  }
}

class PlaybackFixture {
  final key = GlobalKey<State<ExternalPlayerSettingsPage>>();
  final navigator = GlobalKey<NavigatorState>();
  final picker = PlaybackPicker();
  final urls = PlaybackUrls();
  final tvCalls = <MethodCall>[];
  final externalPicker = FilePicker.platform;
  final externalPaths = PathProviderPlatform.instance;
  final externalUrls = UrlLauncherPlatform.instance;
  late Directory directory;
  Map<String, Object?> get access =>
      playbackSettingsTestAccess(key.currentState!);
  dynamic member(String name) => access[name];

  Future<void> initialize() async {
    directory = await Directory.systemTemp.createTemp('playback-settings-');
    AppStorage.debugReset();
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
    );
    PathProviderPlatform.instance = PlaybackPaths(directory.path);
    FilePicker.platform = picker;
    UrlLauncherPlatform.instance = urls;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('debrify/tvurl'), (
          call,
        ) async {
          tvCalls.add(call);
          return false;
        });
  }

  Future<void> mount(
    WidgetTester tester, {
    PlaybackSettingsSection section = PlaybackSettingsSection.player,
    bool wait = true,
    Widget? home,
  }) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: ThemeData.dark(),
          home:
              home ??
              RepaintBoundary(
                key: const ValueKey('playback-canvas'),
                child: ExternalPlayerSettingsPage(key: key, section: section),
              ),
        ),
      ),
    );
    if (wait && home == null) await loaded(tester);
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(ready(), isTrue, reason: 'Original playback action did not finish');
  }

  Future<void> loaded(WidgetTester tester) async {
    await until(
      tester,
      () => key.currentState != null && member('loading') == false,
    );
    // The original page intentionally drops loadFonts' Future. Drain its real
    // microtasks before clearing singleton profile caches or starting another
    // fixture; pumpAndSettle only drains the widget test's fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // addPostFrameCallback does not itself schedule a frame.
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    SubtitleFontService.instance.resetProfileScope();
    for (final font in List<SubtitleFont>.of(
      (await tester.runAsync(SubtitleFontService.instance.getCustomFonts))!,
    )) {
      await tester.runAsync(
        () => SubtitleFontService.instance.removeCustomFont(font.id),
      );
    }
    SubtitleSettingsService.instance.resetProfileScope();
    SubtitleFontService.instance.resetProfileScope();
    FilePicker.platform = externalPicker;
    PathProviderPlatform.instance = externalPaths;
    UrlLauncherPlatform.instance = externalUrls;
    AppStorage.debugReset();
    await tester.runAsync(() => directory.delete(recursive: true));
    tester.view.reset();
    PlatformUtil.debugSetTvOS(null);
    PlatformUtil.debugSetAndroidTvCached(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('debrify/tvurl'), null);
  }
}

late PlaybackPreferences playbackPreferences;
late SharedPreferences playbackRawPreferences;

void playbackHarness() {
  setUpAll(() async {
    FilePicker.platform = PlaybackPicker();
    SharedPreferences.setMockInitialValues({});
    playbackPreferences = PlaybackPreferences();
    SharedPreferencesStorePlatform.instance = playbackPreferences;
    playbackRawPreferences = await SharedPreferences.getInstance();
  });
  setUp(() async {
    await playbackRawPreferences.clear();
    playbackPreferences.writes.clear();
    playbackPreferences.holdRead = null;
    playbackPreferences.holdWrite = null;
    playbackPreferences.failRead = false;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SubtitleSettingsService.instance.resetProfileScope();
    SubtitleFontService.instance.resetProfileScope();
    PlatformUtil.debugSetTvOS(false);
    PlatformUtil.debugSetAndroidTvCached(false);
    AppStorage.debugReset();
  });
}

Future<void> playbackSeed(Map<String, Object> values) async {
  for (final entry in values.entries) {
    final value = entry.value;
    if (value is bool) {
      await playbackRawPreferences.setBool(entry.key, value);
    } else if (value is int) {
      await playbackRawPreferences.setInt(entry.key, value);
    } else if (value is String) {
      await playbackRawPreferences.setString(entry.key, value);
    } else if (value is List<String>) {
      await playbackRawPreferences.setStringList(entry.key, value);
    } else {
      throw StateError('Unsupported fixture preference ${entry.key}');
    }
  }
  playbackPreferences.writes.clear();
}

Future<void> playbackCase(
  WidgetTester tester,
  Future<void> Function(PlaybackFixture) body,
) async {
  final fixture = PlaybackFixture();
  await tester.runAsync(fixture.initialize);
  try {
    await body(fixture);
  } finally {
    await fixture.close(tester);
  }
}
