import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_vr_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_windows_state.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/video_player/services/network_tuning.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/services/player_gesture_settings.dart';
import 'package:debrify/services/skip_segment_service.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/player_network_storage.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/storage/skip_segments_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

typedef PlaybackSettingsLoadDependencies = ({
  BuildContext Function() context,
  PlaybackCoreState core,
  PlaybackIosState ios,
  PlaybackLinuxState linux,
  Future<void> Function() loadFonts,
  PlaybackMacState mac,
  bool Function() mounted,
  PlaybackSettingsSection Function() section,
  void Function(VoidCallback) setState,
  PlaybackSubtitleState sub,
  PlaybackValuesState values,
  PlaybackVrState vr,
  PlaybackWindowsState win,
});

class PlaybackSettingsLoad {
  final PlaybackSettingsLoadDependencies _deps;
  PlaybackSettingsLoad(this._deps);

  Future<void> loadSettings() async {
    _deps.setState(() {
      _deps.core.loading = true;
    });

    try {
      // Load default player mode
      final mode = await ExternalPlayerStorage.getDefaultPlayerMode();

      // Only Player needs external application discovery. The other categories
      // can load without waiting for native app detection.
      final needsExternalPlayers =
          _deps.section() == PlaybackSettingsSection.player;

      // Load macOS-specific settings
      Map<ExternalPlayer, bool> installed = {};
      String preferredKey = 'system_default';
      String? customAppPath;
      String? customAppName;
      String? customCommand;

      if (needsExternalPlayers && (Platform.isMacOS)) {
        installed = await ExternalPlayerService.detectInstalledPlayers();
        preferredKey = await ExternalPlayerStorage.getPreferredExternalPlayer();
        customAppPath =
            await ExternalPlayerStorage.getCustomExternalPlayerPath();
        customAppName =
            await ExternalPlayerStorage.getCustomExternalPlayerName();
        customCommand =
            await ExternalPlayerStorage.getCustomExternalPlayerCommand();
        if (!_deps.mounted()) return;
        _deps.mac.commandController.text = customCommand ?? '';
      }

      // Load iOS-specific settings
      Map<iOSExternalPlayer, bool> installedIOS = {};
      String iosPreferredKey = 'vlc';
      String? iosCustomScheme;

      if (needsExternalPlayers &&
          (PlatformUtil.isIosMobile || PlatformUtil.isTvOS)) {
        installedIOS = await ExternalPlayerService.detectInstalledIOSPlayers();
        iosPreferredKey =
            await ExternalPlayerStorage.getPreferredIOSExternalPlayer();
        iosCustomScheme =
            await ExternalPlayerStorage.getIOSCustomSchemeTemplate();
        if (!_deps.mounted()) return;
        _deps.ios.iosSchemeController.text = iosCustomScheme ?? '';
      }

      // Load Linux-specific settings
      Map<LinuxExternalPlayer, bool> installedLinux = {};
      String linuxPreferredKey = 'system_default';
      String? linuxCustomCommand;

      if (needsExternalPlayers && (Platform.isLinux)) {
        installedLinux =
            await LinuxExternalPlayerServiceExtension.detectInstalledLinuxPlayers();
        linuxPreferredKey =
            await ExternalPlayerStorage.getPreferredLinuxExternalPlayer();
        linuxCustomCommand =
            await ExternalPlayerStorage.getLinuxCustomCommand();
        if (!_deps.mounted()) return;
        _deps.linux.linuxCommandController.text = linuxCustomCommand ?? '';
      }

      // Load Windows-specific settings
      Map<WindowsExternalPlayer, bool> installedWindows = {};
      String windowsPreferredKey = 'system_default';
      String? windowsCustomCommand;

      if (needsExternalPlayers && (Platform.isWindows)) {
        installedWindows =
            await WindowsExternalPlayerServiceExtension.detectInstalledWindowsPlayers();
        windowsPreferredKey =
            await ExternalPlayerStorage.getPreferredWindowsExternalPlayer();
        windowsCustomCommand =
            await ExternalPlayerStorage.getWindowsCustomCommand();
        if (!_deps.mounted()) return;
        _deps.win.windowsCommandController.text = windowsCustomCommand ?? '';
      }

      // Load DeoVR settings (Android)
      String vrScreenType = 'dome';
      String vrStereoMode = 'sbs';
      bool vrAutoDetect = true;
      bool vrShowDialog = true;

      if (Platform.isAndroid) {
        vrScreenType = await QuickPlayStorage.getQuickPlayVrDefaultScreenType();
        vrStereoMode = await QuickPlayStorage.getQuickPlayVrDefaultStereoMode();
        vrAutoDetect = await QuickPlayStorage.getQuickPlayVrAutoDetectFormat();
        vrShowDialog = await QuickPlayStorage.getQuickPlayVrShowDialog();
      }

      // Check if running on Android TV
      bool isAndroidTv = false;
      if (Platform.isAndroid) {
        try {
          isAndroidTv = await AndroidNativeDownloader.isTelevision();
        } catch (_) {
          isAndroidTv = false;
        }
      }

      // Load Debrify Player default settings (use platform-specific aspect setting)
      final defaultAspectIndex = isAndroidTv
          ? await PlayerSettingsStorage.getPlayerDefaultAspectIndexTv()
          : await PlayerSettingsStorage.getPlayerDefaultAspectIndex();
      final nightModeIndex =
          await PlayerSettingsStorage.getPlayerNightModeIndex();
      final systemAudioEffects =
          await PlayerSettingsStorage.getPlayerSystemAudioEffects();
      final tvosForceSoftwareDecode = PlatformUtil.isTvOS
          ? await PlayerSettingsStorage.getTvosForceSoftwareDecode()
          : false;
      final tvosForceStereo = PlatformUtil.isTvOS
          ? await PlayerSettingsStorage.getTvosForceStereoAudio()
          : false;
      final tvosLegacyAudioOutput = PlatformUtil.isTvOS
          ? await PlayerSettingsStorage.getTvosLegacyAudioOutput()
          : false;
      final audioPassthrough = Platform.isAndroid
          ? await PlayerSettingsStorage.getAudioPassthroughEnabled()
          : false;
      final appleMultichannel =
          (PlatformUtil.isTvOS || PlatformUtil.isIosMobile)
          ? await PlayerSettingsStorage.getAppleMultichannelAudio()
          : false;
      final androidVideoRendererMode =
          await PlayerSettingsStorage.getAndroidVideoRendererMode();
      final contentDisplayMatchMode =
          await PlayerNetworkStorage.getContentDisplayMatchMode();
      final startPortrait =
          await PlayerSettingsStorage.getPlayerStartPortrait();
      final swipeSeek = await PlayerGestureSettings.load();
      final subtitleForcedOnly =
          await SubtitleSettingsStorage.getSubtitleForcedOnly();
      final subtitleOnlyForeignAudio =
          await SubtitleSettingsStorage.getSubtitleOnlyForeignAudio();
      final subtitleAutoSync =
          await SubtitleSettingsStorage.getSubtitleAutoSyncEnabled();
      final movieCompletionThreshold =
          await LocalCompletionStorage.getMovieCompletionThreshold();
      final episodeCompletionThreshold =
          await LocalCompletionStorage.getEpisodeCompletionThreshold();
      final skipSegmentsEnabled =
          await SkipSegmentsStorage.getSkipSegmentsEnabled();
      final storedSkipSegmentProvider =
          await SkipSegmentsStorage.getSkipSegmentProvider();
      final skipSegmentProvider =
          SkipSegmentProviders.isAvailable(storedSkipSegmentProvider)
          ? storedSkipSegmentProvider
          : SkipSegmentProviders.auto;
      final defaultSubtitleLanguage =
          await SubtitleSettingsStorage.getDefaultSubtitleLanguage();
      final defaultAudioLanguage =
          await SubtitleSettingsStorage.getDefaultAudioLanguage();
      final netPatience =
          await PlayerNetworkStorage.getNetworkConnectPatience();
      final iptvDecoderMode = await PlayerNetworkStorage.getIptvDecoderMode();
      final netBuffer = await PlayerNetworkStorage.getNetworkBufferSize();

      // Load subtitle settings
      final subtitleSettings = await SubtitleSettingsService.instance.loadAll();

      if (!_deps.mounted()) return;
      _deps.setState(() {
        _deps.core.defaultPlayerMode = mode;
        _deps.mac.installedPlayers = installed;
        _deps.mac.selectedPlayer = ExternalPlayerExtension.fromStorageKey(
          preferredKey,
        );
        _deps.mac.customAppPath = customAppPath;
        _deps.mac.customAppName = customAppName;
        _deps.mac.customCommand = customCommand;
        // iOS settings
        _deps.ios.installedIOSPlayers = installedIOS;
        _deps.ios.selectedIOSPlayer = iOSExternalPlayerExtension.fromStorageKey(
          iosPreferredKey,
        );
        _deps.ios.iosCustomScheme = iosCustomScheme;
        // Linux settings
        _deps.linux.installedLinuxPlayers = installedLinux;
        _deps.linux.selectedLinuxPlayer =
            LinuxExternalPlayerExtension.fromStorageKey(linuxPreferredKey);
        _deps.linux.linuxCustomCommand = linuxCustomCommand;
        // Windows settings
        _deps.win.installedWindowsPlayers = installedWindows;
        _deps.win.selectedWindowsPlayer =
            WindowsExternalPlayerExtension.fromStorageKey(windowsPreferredKey);
        _deps.win.windowsCustomCommand = windowsCustomCommand;
        // Other settings
        _deps.vr.vrDefaultScreenType = vrScreenType;
        _deps.vr.vrDefaultStereoMode = vrStereoMode;
        _deps.vr.vrAutoDetectFormat = vrAutoDetect;
        _deps.vr.vrShowDialog = vrShowDialog;
        _deps.values.isAndroidTv = isAndroidTv;
        _deps.values.defaultAspectIndex = defaultAspectIndex;
        _deps.values.nightModeIndex = nightModeIndex;
        _deps.values.systemAudioEffects = systemAudioEffects;
        _deps.values.tvosForceSoftwareDecode = tvosForceSoftwareDecode;
        _deps.values.audioPassthrough = audioPassthrough;
        _deps.values.appleMultichannel = appleMultichannel;
        _deps.values.tvosForceStereo = tvosForceStereo;
        _deps.values.tvosLegacyAudioOutput = tvosLegacyAudioOutput;
        _deps.values.androidVideoRendererMode = androidVideoRendererMode;
        _deps.values.contentDisplayMatchMode = contentDisplayMatchMode;
        _deps.values.iptvDecoderMode = iptvDecoderMode;
        _deps.values.startPortrait = startPortrait;
        _deps.values.swipeSeek = swipeSeek;
        _deps.sub.subtitleOnlyForeignAudio = subtitleOnlyForeignAudio;
        _deps.sub.subtitleForcedOnly = subtitleForcedOnly;
        _deps.sub.subtitleAutoSync = subtitleAutoSync;
        _deps.values.movieCompletionThreshold = movieCompletionThreshold;
        _deps.values.episodeCompletionThreshold = episodeCompletionThreshold;
        _deps.values.skipSegmentsEnabled = skipSegmentsEnabled;
        _deps.values.skipSegmentProvider = skipSegmentProvider;
        // Unknown stored value (a downgrade across versions) falls back to
        // Standard rather than crashing the dropdown.
        _deps.values.netPatience =
            NetworkTuning.patienceOptions.containsKey(netPatience)
            ? netPatience
            : NetworkTuning.standard;
        _deps.values.netBuffer =
            NetworkTuning.bufferOptions.containsKey(netBuffer)
            ? netBuffer
            : NetworkTuning.standard;
        _deps.sub.defaultSubtitleLanguage = defaultSubtitleLanguage;
        _deps.sub.defaultAudioLanguage = defaultAudioLanguage;
        _deps.sub.subtitleSizeIndex = subtitleSettings.sizeIndex;
        _deps.sub.subtitleStyleIndex = subtitleSettings.styleIndex;
        _deps.sub.subtitleColorIndex = subtitleSettings.colorIndex;
        _deps.sub.subtitleBgIndex = subtitleSettings.bgIndex;
        _deps.sub.subtitleFontIndex = subtitleSettings.fontIndex;
        _deps.sub.subtitleBold = subtitleSettings.bold;
        _deps.core.loading = false;
      });
      // Load fonts (built-in + custom) separately (async)
      _deps.loadFonts();
      // Entry focus on TV: land DPAD on the first row once content builds.
      if (PlatformUtil.isTelevision) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_deps.mounted()) return;
          // Only seed focus if nothing concrete is focused yet — a bare
          // FocusScopeNode as primary focus means DPAD is stranded.
          final primary = FocusManager.instance.primaryFocus;
          if (primary != null && primary is! FocusScopeNode) return;
          _deps.core.contentFocusNode.traversalDescendants.firstOrNull
              ?.requestFocus();
        });
      }
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _deps.core.loading = false;
      });
      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(SnackBar(content: Text('Failed to load settings: $e')));
      }
    }
  }
}
