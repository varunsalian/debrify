// Isolated Android TV smoke entry point. Never use as a release entry point.
// Build with -PdebrifyPersonalBuild=true and -Ptarget=tool/native_player_settings_smoke.dart.
// See native_player_settings_verification.md for fixture and run instructions.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/native_profile_projection.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_native_lock_bridge.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fixture = 'http://127.0.0.1:18769/Debrify%20Test%20Movie%20(2008).mp4';
const _remote = MethodChannel('com.debrify.app/remote_control');
const _privacy = MethodChannel('com.debrify.app/profile_privacy');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final package = await PackageInfo.fromPlatform();
  if (!kDebugMode ||
      !Platform.isAndroid ||
      package.packageName != 'com.debrify.app.personal') {
    throw StateError(
      'This probe must run in an isolated personal debug build.',
    );
  }
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Native player settings smoke test')),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await _run();
      debugPrint('SETTINGS_SMOKE ALL_PASS');
    } catch (error, stack) {
      debugPrint('SETTINGS_SMOKE FAIL $error\n$stack');
    }
  });
}

Future<void> _run() async {
  // Reuse only this probe's synthetic DB for the second, cold-start pass.
  final raw = await SharedPreferences.getInstance();
  final savedDirectory = raw.getString('player_settings_probe_directory');
  final directory = savedDirectory == null
      ? await Directory.systemTemp.createTemp('player-settings-probe-')
      : Directory(savedDirectory);
  final registry = await ProfileRegistry.open(
    path: '${directory.path}/profiles.db',
  );
  final first = savedDirectory == null
      ? await registry.createProfile(
          name: 'Settings probe A',
          role: UserProfileRole.admin,
        )
      : (await registry.getProfile(raw.getString('player_settings_probe_a')!))!;
  final second = savedDirectory == null
      ? await registry.createProfile(
          name: 'Settings probe B',
          role: UserProfileRole.admin,
        )
      : (await registry.getProfile(raw.getString('player_settings_probe_b')!))!;
  if (savedDirectory == null) {
    await registry.commitBootstrap(
      activeProfileId: first.id,
      migratedLegacyInstall: false,
    );
  }
  ProfileBootstrap.debugInstallRegistry(registry);
  final cipher = MemoryDeviceSecretCipher(
    List<int>.generate(32, (i) => i + 17),
  );
  await cipher.initialize();
  DeviceKeyProvider.debugInstallCipher(cipher);
  await raw.setString('profiles_runtime_mode_v1', 'profileCommitted');
  var epoch = 0;
  Future<void> activate(UserProfile profile) async {
    SubtitleFontService.instance.resetProfileScope();
    final scope = ProfileScope(
      profileId: profile.id,
      dataGeneration: 1,
      sessionEpoch: ++epoch,
    );
    if (ProfileRuntime.isInitialized) {
      ProfileRuntime.publish(scope);
    } else {
      ProfileRuntime.initializeCommitted(scope);
    }
    ProfileLockController.instance.activate(profile, unlocked: true);
    await _privacy.invokeMethod<void>('setSensitive', {
      'sensitive': false,
      'protectOnBackground': false,
    });
    await ProfileNativeLockBridge.debugSynchronize();
  }

  ProfileNativeLockBridge.initialize();
  await activate(first);
  if (savedDirectory != null) {
    await _play('cold-restored-profile-a');
    await _play('torbox');
    await registry.close();
    return;
  }
  await _play('defaults-movie');
  await StorageService.setTvPlayerControlsStyle('frost');
  await StorageService.setDebrifyTvPlayerStyle('network');
  await StorageService.setDefaultSubtitleLanguage('off');
  await StorageService.setPlayerNightModeIndex(3);
  for (final kind in [
    'movie',
    'episode',
    'iptv-live',
    'iptv-vod',
    'iptv-episode',
    'torbox',
    'real-debrid',
    'movie-repeat',
  ]) {
    await _play(kind);
  }
  await activate(second);
  await _play('profile-b-defaults');
  await StorageService.setTvPlayerControlsStyle('classic');
  await StorageService.setDefaultSubtitleLanguage('spa');
  await StorageService.setPlayerNightModeIndex(1);
  await _play('profile-b-custom');
  await activate(first);
  await _play('profile-a-return');

  // Exercise the actual bridge's rejection cleanup, not only the helper.
  for (final kind in ['movie', 'torbox', 'real-debrid']) {
    ProfileLockController.instance.lock();
    var rejected = false;
    try {
      await _launch(kind, () async {}, (_) async {});
    } on NativePlayerSettingsUnavailable {
      rejected = true;
    }
    if (!rejected) throw StateError('$kind launched a locked profile');
    debugPrint('SETTINGS_SMOKE PASS locked-$kind');
    await activate(first);
  }
  await _play('after-rejected-launch');
  await raw.setString('player_settings_probe_directory', directory.path);
  await raw.setString('player_settings_probe_a', first.id);
  await raw.setString('player_settings_probe_b', second.id);
  ProfileNativeLockBridge.debugReset();
  ProfileLockController.instance.dispose();
  ProfileRuntime.debugReset();
  ProfileBootstrap.debugInstallRegistry(null);
  await registry.close();
  // Kept only inside the isolated app for the cold-start check. Uninstalling
  // that probe app removes this database; it contains no credentials.
}

Future<void> _play(String kind) async {
  final finished = Completer<void>();
  var advanced = false;
  // Previous failure signature: Settings retains values, native publication denied.
  await NativeProfileProjection.invalidate();
  debugPrint('SETTINGS_SMOKE BEGIN $kind');
  final launched = await _launch(
    kind,
    () async {
      if (!finished.isCompleted) finished.complete();
    },
    (progress) async {
      if ((progress['positionMs'] as num? ?? 0) > 500) advanced = true;
    },
  );
  if (!launched) throw StateError('$kind did not launch');
  await Future<void>.delayed(const Duration(seconds: 9));
  // Use the app's existing remote-control API; no external UI automation.
  for (var attempt = 0; attempt < 5 && !finished.isCompleted; attempt++) {
    await _remote.invokeMethod<bool>('injectKeyEvent', {'keyCode': 4});
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  await finished.future.timeout(const Duration(seconds: 5));
  if (!kind.contains('iptv-live') &&
      kind != 'torbox' &&
      kind != 'real-debrid' &&
      !advanced) {
    throw StateError('$kind produced no advancing playback checkpoint');
  }
  debugPrint('SETTINGS_SMOKE PASS $kind progress=$advanced');
  await Future<void>.delayed(const Duration(milliseconds: 800));
}

Future<bool> _launch(
  String kind,
  Future<void> Function() finished,
  Future<void> Function(Map<String, dynamic>) progress,
) {
  if (kind == 'torbox') {
    return AndroidTvPlayerBridge.launchTorboxPlayback(
      initialUrl: _fixture,
      title: 'Settings probe',
      magnets: [],
      requestNext: () async => null,
      onFinished: finished,
    );
  }
  if (kind == 'real-debrid') {
    return AndroidTvPlayerBridge.launchRealDebridPlayback(
      initialUrl: _fixture,
      title: 'Settings probe',
      requestNext: () async => null,
      onFinished: finished,
    );
  }
  final iptv = kind.startsWith('iptv-');
  final episode = kind.contains('episode');
  final contentType = kind == 'iptv-live'
      ? 'live'
      : episode
      ? 'series'
      : 'vod';
  return AndroidTvPlayerBridge.launchTorrentPlayback(
    payload: {
      'title': 'Settings probe',
      'startIndex': 0,
      'contentType': iptv
          ? contentType
          : episode
          ? 'series'
          : 'movie',
      if (iptv) 'mode': 'iptv',
      iptv ? 'channels' : 'items': [
        {
          'id': 'probe',
          'name': 'Settings probe',
          'title': 'Settings probe',
          'url': _fixture,
          'index': 0,
          'contentType': contentType,
          if (episode) 'season': 1,
          if (episode) 'episode': 1,
        },
      ],
    },
    onFinished: finished,
    onProgress: progress,
  );
}
