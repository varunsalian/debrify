import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_vr_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_windows_state.dart';
import 'package:debrify/features/playback_settings/presentation/playback_checkbox_tile.dart';
import 'package:debrify/features/playback_settings/presentation/playback_dropdown_setting.dart';
import 'package:debrify/features/playback_settings/presentation/playback_setting_dropdown.dart';
import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/content_display_match_mode.dart';
import 'package:debrify/screens/settings/debrify_tv_player_style_page.dart';
import 'package:debrify/screens/settings/play_loader_style_page.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/player_dock_page.dart';
import 'package:debrify/screens/settings/player_guide_style_page.dart';
import 'package:debrify/screens/settings/subtitle_priority_page.dart';
import 'package:debrify/screens/settings/tv_player_controls_style_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/screens/video_player/services/network_tuning.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/services/skip_segment_service.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/player_network_storage.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/storage/skip_segments_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/deovr_utils.dart' as deovr;
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One category inside Settings → Playback. Keeps the existing storage and
/// platform-specific controls shared across the four destinations.
class ExternalPlayerSettingsPage extends StatefulWidget {
  final PlaybackSettingsSection section;

  const ExternalPlayerSettingsPage({
    super.key,
    this.section = PlaybackSettingsSection.player,
  });

  @override
  State<ExternalPlayerSettingsPage> createState() =>
      _ExternalPlayerSettingsPageState();
}

class _ExternalPlayerSettingsPageState
    extends State<ExternalPlayerSettingsPage> {
  final _core = PlaybackCoreState();
  final _mac = PlaybackMacState();
  final _ios = PlaybackIosState();
  final _linux = PlaybackLinuxState();
  final _win = PlaybackWindowsState();
  final _vr = PlaybackVrState();
  final _values = PlaybackValuesState();
  final _sub = PlaybackSubtitleState();
  final _rows = PlaybackRowsState();
  final _subRows = PlaybackSubtitleRowsState();

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('playback_${widget.section.name}_settings');
    _loadSettings();
    _mac.commandFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _mac.commandFocused = _mac.commandFocusNode.hasFocus;
      });
    });
    _ios.iosSchemeFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _ios.iosSchemeFocused = _ios.iosSchemeFocusNode.hasFocus;
      });
    });
    _linux.linuxCommandFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _linux.linuxCommandFocused = _linux.linuxCommandFocusNode.hasFocus;
      });
    });
    _win.windowsCommandFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _win.windowsCommandFocused = _win.windowsCommandFocusNode.hasFocus;
      });
    });
    _vr.screenTypeFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _vr.screenTypeFocused = _vr.screenTypeFocusNode.hasFocus;
      });
    });
    _vr.stereoModeFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _vr.stereoModeFocused = _vr.stereoModeFocusNode.hasFocus;
      });
    });
    _vr.autoDetectFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _vr.autoDetectFocused = _vr.autoDetectFocusNode.hasFocus;
      });
    });
    _vr.showDialogFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _vr.showDialogFocused = _vr.showDialogFocusNode.hasFocus;
      });
    });
    // Debrify Player focus listeners
    _rows.aspectFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.aspectFocused = _rows.aspectFocusNode.hasFocus;
      });
    });
    _rows.defaultAudioLangFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.defaultAudioLangFocused =
            _rows.defaultAudioLangFocusNode.hasFocus;
      });
    });
    _subRows.defaultSubtitleLangFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.defaultSubtitleLangFocused =
            _subRows.defaultSubtitleLangFocusNode.hasFocus;
      });
    });
    _rows.systemAudioEffectsFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.systemAudioEffectsFocused =
            _rows.systemAudioEffectsFocusNode.hasFocus;
      });
    });
    _rows.tvosForceSwDecodeFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.tvosForceSwDecodeFocused =
            _rows.tvosForceSwDecodeFocusNode.hasFocus;
      });
    });
    _rows.audioPassthroughFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.audioPassthroughFocused =
            _rows.audioPassthroughFocusNode.hasFocus;
      });
    });
    _rows.appleMultichannelFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.appleMultichannelFocused =
            _rows.appleMultichannelFocusNode.hasFocus;
      });
    });
    _rows.tvosForceStereoFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.tvosForceStereoFocused = _rows.tvosForceStereoFocusNode.hasFocus;
      });
    });
    _rows.tvosLegacyAudioFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.tvosLegacyAudioFocused = _rows.tvosLegacyAudioFocusNode.hasFocus;
      });
    });
    _rows.androidVideoRendererFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.androidVideoRendererFocused =
            _rows.androidVideoRendererFocusNode.hasFocus;
      });
    });
    _rows.contentDisplayMatchFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.contentDisplayMatchFocused =
            _rows.contentDisplayMatchFocusNode.hasFocus;
      });
    });
    _rows.iptvDecoderFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.iptvDecoderFocused = _rows.iptvDecoderFocusNode.hasFocus;
      });
    });
    _rows.startPortraitFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.startPortraitFocused = _rows.startPortraitFocusNode.hasFocus;
      });
    });
    _subRows.subtitleOnlyForeignAudioFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.subtitleOnlyForeignAudioFocused =
            _subRows.subtitleOnlyForeignAudioFocusNode.hasFocus;
      });
    });
    _subRows.subtitleForcedOnlyFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.subtitleForcedOnlyFocused =
            _subRows.subtitleForcedOnlyFocusNode.hasFocus;
      });
    });
    _subRows.subtitleAutoSyncFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.subtitleAutoSyncFocused =
            _subRows.subtitleAutoSyncFocusNode.hasFocus;
      });
    });
    _subRows.movieCompletionThresholdFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.movieCompletionThresholdFocused =
            _subRows.movieCompletionThresholdFocusNode.hasFocus;
      });
    });
    _subRows.episodeCompletionThresholdFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.episodeCompletionThresholdFocused =
            _subRows.episodeCompletionThresholdFocusNode.hasFocus;
      });
    });
    _subRows.skipSegmentsEnabledFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.skipSegmentsEnabledFocused =
            _subRows.skipSegmentsEnabledFocusNode.hasFocus;
      });
    });
    _subRows.skipSegmentProviderFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.skipSegmentProviderFocused =
            _subRows.skipSegmentProviderFocusNode.hasFocus;
      });
    });
    _subRows.subtitleSizeFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.subtitleSizeFocused = _subRows.subtitleSizeFocusNode.hasFocus;
      });
    });
    _subRows.subtitleStyleFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.subtitleStyleFocused =
            _subRows.subtitleStyleFocusNode.hasFocus;
      });
    });
    _subRows.subtitleColorFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.subtitleColorFocused =
            _subRows.subtitleColorFocusNode.hasFocus;
      });
    });
    _subRows.subtitleBgFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.subtitleBgFocused = _subRows.subtitleBgFocusNode.hasFocus;
      });
    });
    _subRows.subtitleFontFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.subtitleFontFocused = _subRows.subtitleFontFocusNode.hasFocus;
      });
    });
    _subRows.subtitleBoldFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _subRows.subtitleBoldFocused = _subRows.subtitleBoldFocusNode.hasFocus;
      });
    });
    _rows.netPatienceFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.netPatienceFocused = _rows.netPatienceFocusNode.hasFocus;
      });
    });
    _rows.netBufferFocusNode.addListener(() {
      if (!mounted) return;
      setState(() {
        _rows.netBufferFocused = _rows.netBufferFocusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _mac.commandController.dispose();
    _mac.commandFocusNode.dispose();
    _ios.iosSchemeController.dispose();
    _ios.iosSchemeFocusNode.dispose();
    _linux.linuxCommandController.dispose();
    _linux.linuxCommandFocusNode.dispose();
    _win.windowsCommandController.dispose();
    _win.windowsCommandFocusNode.dispose();
    _core.firstModeFocusNode.dispose();
    _core.contentFocusNode.dispose();
    _vr.screenTypeFocusNode.dispose();
    _vr.stereoModeFocusNode.dispose();
    _vr.autoDetectFocusNode.dispose();
    _vr.showDialogFocusNode.dispose();
    // Debrify Player focus nodes
    _rows.aspectFocusNode.dispose();
    _rows.defaultAudioLangFocusNode.dispose();
    _subRows.defaultSubtitleLangFocusNode.dispose();
    _rows.systemAudioEffectsFocusNode.dispose();
    _rows.tvosForceSwDecodeFocusNode.dispose();
    _rows.audioPassthroughFocusNode.dispose();
    _rows.appleMultichannelFocusNode.dispose();
    _rows.tvosForceStereoFocusNode.dispose();
    _rows.tvosLegacyAudioFocusNode.dispose();
    _rows.androidVideoRendererFocusNode.dispose();
    _rows.contentDisplayMatchFocusNode.dispose();
    _rows.iptvDecoderFocusNode.dispose();
    _rows.startPortraitFocusNode.dispose();
    _subRows.subtitleOnlyForeignAudioFocusNode.dispose();
    _subRows.subtitleForcedOnlyFocusNode.dispose();
    _subRows.subtitleAutoSyncFocusNode.dispose();
    _subRows.movieCompletionThresholdFocusNode.dispose();
    _subRows.episodeCompletionThresholdFocusNode.dispose();
    _subRows.skipSegmentsEnabledFocusNode.dispose();
    _subRows.skipSegmentProviderFocusNode.dispose();
    _subRows.subtitleSizeFocusNode.dispose();
    _subRows.subtitleStyleFocusNode.dispose();
    _subRows.subtitleColorFocusNode.dispose();
    _subRows.subtitleBgFocusNode.dispose();
    _subRows.subtitleFontFocusNode.dispose();
    _subRows.subtitleBoldFocusNode.dispose();
    _rows.netPatienceFocusNode.dispose();
    _rows.netBufferFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _core.loading = true;
    });

    try {
      // Load default player mode
      final mode = await ExternalPlayerStorage.getDefaultPlayerMode();

      // Only Player needs external application discovery. The other categories
      // can load without waiting for native app detection.
      final needsExternalPlayers =
          widget.section == PlaybackSettingsSection.player;

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
        if (!mounted) return;
        _mac.commandController.text = customCommand ?? '';
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
        if (!mounted) return;
        _ios.iosSchemeController.text = iosCustomScheme ?? '';
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
        if (!mounted) return;
        _linux.linuxCommandController.text = linuxCustomCommand ?? '';
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
        if (!mounted) return;
        _win.windowsCommandController.text = windowsCustomCommand ?? '';
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

      if (!mounted) return;
      setState(() {
        _core.defaultPlayerMode = mode;
        _mac.installedPlayers = installed;
        _mac.selectedPlayer = ExternalPlayerExtension.fromStorageKey(
          preferredKey,
        );
        _mac.customAppPath = customAppPath;
        _mac.customAppName = customAppName;
        _mac.customCommand = customCommand;
        // iOS settings
        _ios.installedIOSPlayers = installedIOS;
        _ios.selectedIOSPlayer = iOSExternalPlayerExtension.fromStorageKey(
          iosPreferredKey,
        );
        _ios.iosCustomScheme = iosCustomScheme;
        // Linux settings
        _linux.installedLinuxPlayers = installedLinux;
        _linux.selectedLinuxPlayer =
            LinuxExternalPlayerExtension.fromStorageKey(linuxPreferredKey);
        _linux.linuxCustomCommand = linuxCustomCommand;
        // Windows settings
        _win.installedWindowsPlayers = installedWindows;
        _win.selectedWindowsPlayer =
            WindowsExternalPlayerExtension.fromStorageKey(windowsPreferredKey);
        _win.windowsCustomCommand = windowsCustomCommand;
        // Other settings
        _vr.vrDefaultScreenType = vrScreenType;
        _vr.vrDefaultStereoMode = vrStereoMode;
        _vr.vrAutoDetectFormat = vrAutoDetect;
        _vr.vrShowDialog = vrShowDialog;
        _values.isAndroidTv = isAndroidTv;
        _values.defaultAspectIndex = defaultAspectIndex;
        _values.nightModeIndex = nightModeIndex;
        _values.systemAudioEffects = systemAudioEffects;
        _values.tvosForceSoftwareDecode = tvosForceSoftwareDecode;
        _values.audioPassthrough = audioPassthrough;
        _values.appleMultichannel = appleMultichannel;
        _values.tvosForceStereo = tvosForceStereo;
        _values.tvosLegacyAudioOutput = tvosLegacyAudioOutput;
        _values.androidVideoRendererMode = androidVideoRendererMode;
        _values.contentDisplayMatchMode = contentDisplayMatchMode;
        _values.iptvDecoderMode = iptvDecoderMode;
        _values.startPortrait = startPortrait;
        _sub.subtitleOnlyForeignAudio = subtitleOnlyForeignAudio;
        _sub.subtitleForcedOnly = subtitleForcedOnly;
        _sub.subtitleAutoSync = subtitleAutoSync;
        _values.movieCompletionThreshold = movieCompletionThreshold;
        _values.episodeCompletionThreshold = episodeCompletionThreshold;
        _values.skipSegmentsEnabled = skipSegmentsEnabled;
        _values.skipSegmentProvider = skipSegmentProvider;
        // Unknown stored value (a downgrade across versions) falls back to
        // Standard rather than crashing the dropdown.
        _values.netPatience =
            NetworkTuning.patienceOptions.containsKey(netPatience)
            ? netPatience
            : NetworkTuning.standard;
        _values.netBuffer = NetworkTuning.bufferOptions.containsKey(netBuffer)
            ? netBuffer
            : NetworkTuning.standard;
        _sub.defaultSubtitleLanguage = defaultSubtitleLanguage;
        _sub.defaultAudioLanguage = defaultAudioLanguage;
        _sub.subtitleSizeIndex = subtitleSettings.sizeIndex;
        _sub.subtitleStyleIndex = subtitleSettings.styleIndex;
        _sub.subtitleColorIndex = subtitleSettings.colorIndex;
        _sub.subtitleBgIndex = subtitleSettings.bgIndex;
        _sub.subtitleFontIndex = subtitleSettings.fontIndex;
        _sub.subtitleBold = subtitleSettings.bold;
        _core.loading = false;
      });
      // Load fonts (built-in + custom) separately (async)
      _loadFonts();
      // Entry focus on TV: land DPAD on the first row once content builds.
      if (PlatformUtil.isTelevision) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Only seed focus if nothing concrete is focused yet — a bare
          // FocusScopeNode as primary focus means DPAD is stranded.
          final primary = FocusManager.instance.primaryFocus;
          if (primary != null && primary is! FocusScopeNode) return;
          _core.contentFocusNode.traversalDescendants.firstOrNull
              ?.requestFocus();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _core.loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load settings: $e')));
      }
    }
  }

  Future<void> _setDefaultPlayerMode(String mode) async {
    try {
      await ExternalPlayerStorage.setDefaultPlayerMode(mode);
      setState(() {
        _core.defaultPlayerMode = mode;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  Future<void> _selectPlayer(ExternalPlayer player) async {
    try {
      await ExternalPlayerStorage.setPreferredExternalPlayer(player.storageKey);
      setState(() {
        _mac.selectedPlayer = player;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  Future<void> _browseForCustomApp() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['app'],
        dialogTitle: 'Select Video Player Application',
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null) {
          final appName = path.split('/').last.replaceAll('.app', '');

          await ExternalPlayerStorage.setCustomExternalPlayerPath(path);
          await ExternalPlayerStorage.setCustomExternalPlayerName(appName);
          await ExternalPlayerStorage.setPreferredExternalPlayer('custom_app');

          setState(() {
            _mac.customAppPath = path;
            _mac.customAppName = appName;
            _mac.selectedPlayer = ExternalPlayer.customApp;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select application: $e')),
        );
      }
    }
  }

  Future<void> _clearCustomApp() async {
    try {
      await ExternalPlayerStorage.setCustomExternalPlayerPath(null);
      await ExternalPlayerStorage.setCustomExternalPlayerName(null);

      if (_mac.selectedPlayer == ExternalPlayer.customApp) {
        await ExternalPlayerStorage.setPreferredExternalPlayer(
          'system_default',
        );
        setState(() {
          _mac.selectedPlayer = ExternalPlayer.systemDefault;
        });
      }

      setState(() {
        _mac.customAppPath = null;
        _mac.customAppName = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear custom app: $e')),
        );
      }
    }
  }

  Future<void> _saveCustomCommand() async {
    final command = _mac.commandController.text.trim();

    final validation = ExternalPlayerService.validateCustomCommand(command);
    if (!validation.isValid) {
      setState(() {
        _mac.commandError = validation.errorMessage;
      });
      return;
    }

    try {
      await ExternalPlayerStorage.setCustomExternalPlayerCommand(command);
      await ExternalPlayerStorage.setPreferredExternalPlayer('custom_command');

      setState(() {
        _mac.customCommand = command;
        _mac.commandError = null;
        _mac.selectedPlayer = ExternalPlayer.customCommand;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Custom command saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save command: $e')));
      }
    }
  }

  Future<void> _clearCustomCommand() async {
    try {
      await ExternalPlayerStorage.setCustomExternalPlayerCommand(null);

      if (_mac.selectedPlayer == ExternalPlayer.customCommand) {
        await ExternalPlayerStorage.setPreferredExternalPlayer(
          'system_default',
        );
        setState(() {
          _mac.selectedPlayer = ExternalPlayer.systemDefault;
        });
      }

      _mac.commandController.clear();
      setState(() {
        _mac.customCommand = null;
        _mac.commandError = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to clear command: $e')));
      }
    }
  }

  // iOS external player settings methods
  Future<void> _selectIOSPlayer(iOSExternalPlayer player) async {
    try {
      await ExternalPlayerStorage.setPreferredIOSExternalPlayer(
        player.storageKey,
      );
      setState(() {
        _ios.selectedIOSPlayer = player;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  Future<void> _saveIOSCustomScheme() async {
    final scheme = _ios.iosSchemeController.text.trim();

    final validation = validateCustomScheme(scheme);
    if (!validation.isValid) {
      setState(() {
        _ios.iosSchemeError = validation.errorMessage;
      });
      return;
    }

    try {
      await ExternalPlayerStorage.setIOSCustomSchemeTemplate(scheme);
      await ExternalPlayerStorage.setPreferredIOSExternalPlayer(
        'custom_scheme',
      );

      setState(() {
        _ios.iosCustomScheme = scheme;
        _ios.iosSchemeError = null;
        _ios.selectedIOSPlayer = iOSExternalPlayer.customScheme;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Custom URL scheme saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save URL scheme: $e')),
        );
      }
    }
  }

  Future<void> _clearIOSCustomScheme() async {
    try {
      await ExternalPlayerStorage.setIOSCustomSchemeTemplate(null);

      if (_ios.selectedIOSPlayer == iOSExternalPlayer.customScheme) {
        await ExternalPlayerStorage.setPreferredIOSExternalPlayer('vlc');
        setState(() {
          _ios.selectedIOSPlayer = iOSExternalPlayer.vlc;
        });
      }

      _ios.iosSchemeController.clear();
      setState(() {
        _ios.iosCustomScheme = null;
        _ios.iosSchemeError = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear URL scheme: $e')),
        );
      }
    }
  }

  // Linux external player settings methods
  Future<void> _selectLinuxPlayer(LinuxExternalPlayer player) async {
    try {
      await ExternalPlayerStorage.setPreferredLinuxExternalPlayer(
        player.storageKey,
      );
      setState(() {
        _linux.selectedLinuxPlayer = player;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  Future<void> _saveLinuxCustomCommand() async {
    final command = _linux.linuxCommandController.text.trim();

    final validation = validateLinuxCustomCommand(command);
    if (!validation.isValid) {
      setState(() {
        _linux.linuxCommandError = validation.errorMessage;
      });
      return;
    }

    try {
      await ExternalPlayerStorage.setLinuxCustomCommand(command);
      await ExternalPlayerStorage.setPreferredLinuxExternalPlayer(
        'custom_command',
      );

      setState(() {
        _linux.linuxCustomCommand = command;
        _linux.linuxCommandError = null;
        _linux.selectedLinuxPlayer = LinuxExternalPlayer.customCommand;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Custom command saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save command: $e')));
      }
    }
  }

  Future<void> _clearLinuxCustomCommand() async {
    try {
      await ExternalPlayerStorage.setLinuxCustomCommand(null);

      if (_linux.selectedLinuxPlayer == LinuxExternalPlayer.customCommand) {
        await ExternalPlayerStorage.setPreferredLinuxExternalPlayer(
          'system_default',
        );
        setState(() {
          _linux.selectedLinuxPlayer = LinuxExternalPlayer.systemDefault;
        });
      }

      _linux.linuxCommandController.clear();
      setState(() {
        _linux.linuxCustomCommand = null;
        _linux.linuxCommandError = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to clear command: $e')));
      }
    }
  }

  // Windows external player settings methods
  Future<void> _selectWindowsPlayer(WindowsExternalPlayer player) async {
    try {
      await ExternalPlayerStorage.setPreferredWindowsExternalPlayer(
        player.storageKey,
      );
      setState(() {
        _win.selectedWindowsPlayer = player;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  Future<void> _saveWindowsCustomCommand() async {
    final command = _win.windowsCommandController.text.trim();

    final validation = validateWindowsCustomCommand(command);
    if (!validation.isValid) {
      setState(() {
        _win.windowsCommandError = validation.errorMessage;
      });
      return;
    }

    try {
      await ExternalPlayerStorage.setWindowsCustomCommand(command);
      await ExternalPlayerStorage.setPreferredWindowsExternalPlayer(
        'custom_command',
      );

      setState(() {
        _win.windowsCustomCommand = command;
        _win.windowsCommandError = null;
        _win.selectedWindowsPlayer = WindowsExternalPlayer.customCommand;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Custom command saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save command: $e')));
      }
    }
  }

  Future<void> _clearWindowsCustomCommand() async {
    try {
      await ExternalPlayerStorage.setWindowsCustomCommand(null);

      if (_win.selectedWindowsPlayer == WindowsExternalPlayer.customCommand) {
        await ExternalPlayerStorage.setPreferredWindowsExternalPlayer(
          'system_default',
        );
        setState(() {
          _win.selectedWindowsPlayer = WindowsExternalPlayer.systemDefault;
        });
      }

      _win.windowsCommandController.clear();
      setState(() {
        _win.windowsCustomCommand = null;
        _win.windowsCommandError = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to clear command: $e')));
      }
    }
  }

  // DeoVR settings setters
  Future<void> _setVrDefaultScreenType(String screenType) async {
    setState(() => _vr.vrDefaultScreenType = screenType);
    await QuickPlayStorage.setQuickPlayVrDefaultScreenType(screenType);
  }

  Future<void> _setVrDefaultStereoMode(String stereoMode) async {
    setState(() => _vr.vrDefaultStereoMode = stereoMode);
    await QuickPlayStorage.setQuickPlayVrDefaultStereoMode(stereoMode);
  }

  Future<void> _setVrAutoDetectFormat(bool autoDetect) async {
    setState(() => _vr.vrAutoDetectFormat = autoDetect);
    await QuickPlayStorage.setQuickPlayVrAutoDetectFormat(autoDetect);
  }

  Future<void> _setVrShowDialog(bool showDialog) async {
    setState(() => _vr.vrShowDialog = showDialog);
    await QuickPlayStorage.setQuickPlayVrShowDialog(showDialog);
  }

  // Debrify Player settings setters
  Future<void> _setDefaultAspectIndex(int index) async {
    setState(() => _values.defaultAspectIndex = index);
    // Use platform-specific storage key
    if (_values.isAndroidTv) {
      await PlayerSettingsStorage.setPlayerDefaultAspectIndexTv(index);
    } else {
      await PlayerSettingsStorage.setPlayerDefaultAspectIndex(index);
    }
  }

  Future<void> _setNightModeIndex(int index) async {
    setState(() => _values.nightModeIndex = index);
    await PlayerSettingsStorage.setPlayerNightModeIndex(index);
  }

  Future<void> _setSystemAudioEffects(bool enabled) async {
    setState(() => _values.systemAudioEffects = enabled);
    await PlayerSettingsStorage.setPlayerSystemAudioEffects(enabled);
  }

  Future<void> _setTvosForceSoftwareDecode(bool enabled) async {
    setState(() => _values.tvosForceSoftwareDecode = enabled);
    await PlayerSettingsStorage.setTvosForceSoftwareDecode(enabled);
  }

  Future<void> _setTvosForceStereo(bool enabled) async {
    setState(() => _values.tvosForceStereo = enabled);
    await PlayerSettingsStorage.setTvosForceStereoAudio(enabled);
  }

  Future<void> _setTvosLegacyAudioOutput(bool enabled) async {
    setState(() => _values.tvosLegacyAudioOutput = enabled);
    await PlayerSettingsStorage.setTvosLegacyAudioOutput(enabled);
  }

  Future<void> _setAudioPassthrough(bool enabled) async {
    setState(() => _values.audioPassthrough = enabled);
    await PlayerSettingsStorage.setAudioPassthroughEnabled(enabled);
  }

  Future<void> _setAppleMultichannel(bool enabled) async {
    setState(() => _values.appleMultichannel = enabled);
    await PlayerSettingsStorage.setAppleMultichannelAudio(enabled);
  }

  Future<void> _setAndroidVideoRendererMode(String storageKey) async {
    final mode = AndroidVideoRendererMode.fromStorage(storageKey);
    setState(() => _values.androidVideoRendererMode = mode);
    await PlayerSettingsStorage.setAndroidVideoRendererMode(mode);
  }

  Future<void> _setContentDisplayMatchMode(String storageKey) async {
    final mode = ContentDisplayMatchMode.fromStorage(storageKey);
    setState(() => _values.contentDisplayMatchMode = mode);
    await PlayerNetworkStorage.setContentDisplayMatchMode(mode);
  }

  Future<void> _setIptvDecoderMode(String value) async {
    setState(() => _values.iptvDecoderMode = value);
    await PlayerNetworkStorage.setIptvDecoderMode(value);
  }

  Future<void> _setStartPortrait(bool enabled) async {
    setState(() => _values.startPortrait = enabled);
    await PlayerSettingsStorage.setPlayerStartPortrait(enabled);
  }

  Future<void> _setSubtitleOnlyForeignAudio(bool enabled) async {
    setState(() => _sub.subtitleOnlyForeignAudio = enabled);
    await SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(enabled);
  }

  Future<void> _setSubtitleForcedOnly(bool enabled) async {
    setState(() => _sub.subtitleForcedOnly = enabled);
    await SubtitleSettingsStorage.setSubtitleForcedOnly(enabled);
  }

  Future<void> _setSubtitleAutoSync(bool enabled) async {
    setState(() => _sub.subtitleAutoSync = enabled);
    await SubtitleSettingsStorage.setSubtitleAutoSyncEnabled(enabled);
  }

  List<int> get _completionThresholdOptions =>
      LocalCompletionStorage.localCompletionThresholdOptions;

  int _completionThresholdIndex(int value) {
    final index = _completionThresholdOptions.indexOf(value);
    return index < 0
        ? _completionThresholdOptions.indexOf(
            LocalCompletionStorage.defaultLocalCompletionThreshold,
          )
        : index;
  }

  Future<void> _setMovieCompletionThresholdIndex(int index) async {
    final value = _completionThresholdOptions[index];
    setState(() => _values.movieCompletionThreshold = value);
    await LocalCompletionStorage.setMovieCompletionThreshold(value);
  }

  Future<void> _setEpisodeCompletionThresholdIndex(int index) async {
    final value = _completionThresholdOptions[index];
    setState(() => _values.episodeCompletionThreshold = value);
    await LocalCompletionStorage.setEpisodeCompletionThreshold(value);
  }

  Future<void> _setSkipSegmentsEnabled(bool enabled) async {
    setState(() => _values.skipSegmentsEnabled = enabled);
    await SkipSegmentsStorage.setSkipSegmentsEnabled(enabled);
  }

  Future<void> _setSkipSegmentProvider(String provider) async {
    setState(() => _values.skipSegmentProvider = provider);
    await SkipSegmentsStorage.setSkipSegmentProvider(provider);
  }

  Future<void> _setNetPatience(String value) async {
    setState(() => _values.netPatience = value);
    await PlayerNetworkStorage.setNetworkConnectPatience(value);
  }

  Future<void> _setNetBuffer(String value) async {
    setState(() => _values.netBuffer = value);
    await PlayerNetworkStorage.setNetworkBufferSize(value);
  }

  Future<void> _setDefaultSubtitleLanguage(String? languageCode) async {
    setState(() => _sub.defaultSubtitleLanguage = languageCode);
    await SubtitleSettingsStorage.setDefaultSubtitleLanguage(languageCode);
  }

  Future<void> _setDefaultAudioLanguage(String? languageCode) async {
    setState(() => _sub.defaultAudioLanguage = languageCode);
    await SubtitleSettingsStorage.setDefaultAudioLanguage(languageCode);
  }

  Future<void> _setSubtitleSizeIndex(int index) async {
    setState(() => _sub.subtitleSizeIndex = index);
    await SubtitleSettingsService.instance.setSizeIndex(index);
  }

  Future<void> _setSubtitleStyleIndex(int index) async {
    setState(() => _sub.subtitleStyleIndex = index);
    await SubtitleSettingsService.instance.setStyleIndex(index);
  }

  Future<void> _setSubtitleColorIndex(int index) async {
    setState(() => _sub.subtitleColorIndex = index);
    await SubtitleSettingsService.instance.setColorIndex(index);
  }

  Future<void> _setSubtitleBgIndex(int index) async {
    setState(() => _sub.subtitleBgIndex = index);
    await SubtitleSettingsService.instance.setBgIndex(index);
  }

  Future<void> _setSubtitleFontIndex(int index) async {
    setState(() => _sub.subtitleFontIndex = index);
    await SubtitleFontService.instance.setFontIndex(index);
  }

  Future<void> _setSubtitleBold(bool value) async {
    setState(() => _sub.subtitleBold = value);
    await SubtitleSettingsService.instance.setBold(value);
  }

  Future<void> _loadFonts() async {
    final allFonts = await SubtitleFontService.instance.getAllFonts();
    final selectedIndex = await SubtitleFontService.instance
        .getSelectedFontIndex();
    if (mounted) {
      setState(() {
        _sub.allFonts = allFonts;
        _sub.subtitleFontIndex = selectedIndex;
      });
    }
  }

  Future<void> _importCustomFont() async {
    try {
      // FileType.any instead of custom: Android's MIME mapping for `ttf`/`otf`
      // is unreliable and throws PlatformException("Unsupported filter"). We
      // validate the extension ourselves below.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      // Reject only a clearly-wrong extension; if the picker's display name has
      // no extension (some Android SAF providers), let the font service try it
      // rather than wrongly rejecting a valid font.
      final lowerName = file.name.toLowerCase();
      final hasExtension = lowerName.contains('.');
      if (hasExtension &&
          !lowerName.endsWith('.ttf') &&
          !lowerName.endsWith('.otf')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a .ttf or .otf font file'),
            ),
          );
        }
        return;
      }
      if (file.path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access selected file')),
          );
        }
        return;
      }

      final newFont = await SubtitleFontService.instance.importCustomFont(
        file.path!,
        file.name,
      );

      if (newFont != null) {
        await _loadFonts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Font "${newFont.label}" imported successfully'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to import font')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error importing font: $e')));
      }
    }
  }

  Future<void> _removeCustomFont(SubtitleFont font) async {
    await SubtitleFontService.instance.removeCustomFont(font.id);
    await _loadFonts();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Font "${font.label}" removed')));
    }
  }

  // Aspect labels
  List<String> get _aspectLabels => _values.isAndroidTv
      ? ['Fit', 'Fill', 'Zoom', 'Cinema Zoom']
      : [
          'Contain',
          'Cover',
          'Fit Width',
          'Fit Height',
          '16:9',
          '4:3',
          '21:9',
          '1:1',
          '3:2',
          '5:4',
          'Cinema Zoom',
        ];

  static const List<String> _nightModeLabels = [
    'Off',
    'Low',
    'Medium',
    'High',
    'Higher',
    'Extreme',
    'Max',
    'Sleeping Baby',
  ];

  // Subtitle language options: (code, label)
  static const List<(String?, String)> _subtitleLanguageOptions = [
    (null, 'No Preference'),
    ('off', 'Off'),
    ('en', 'English'),
    ('es', 'Spanish'),
    ('fr', 'French'),
    ('de', 'German'),
    ('it', 'Italian'),
    ('pt', 'Portuguese'),
    ('pt-BR', 'Portuguese (Brazil)'),
    ('ru', 'Russian'),
    ('ja', 'Japanese'),
    ('ko', 'Korean'),
    ('zh', 'Chinese'),
    ('ar', 'Arabic'),
    ('hi', 'Hindi'),
    ('te', 'Telugu'),
    ('nl', 'Dutch'),
    ('pl', 'Polish'),
    ('tr', 'Turkish'),
    ('sv', 'Swedish'),
    ('da', 'Danish'),
    ('no', 'Norwegian'),
    ('fi', 'Finnish'),
    ('et', 'Estonian'),
    ('hr', 'Croatian'),
    ('sr', 'Serbian'),
    ('bs', 'Bosnian'),
    ('mk', 'Macedonian'),
    ('sl', 'Slovenian'),
    ('cs', 'Czech'),
    ('sk', 'Slovak'),
    ('hu', 'Hungarian'),
    ('ro', 'Romanian'),
    ('bg', 'Bulgarian'),
    ('uk', 'Ukrainian'),
    ('el', 'Greek'),
    ('lv', 'Latvian'),
    ('lt', 'Lithuanian'),
    ('he', 'Hebrew'),
    ('fa', 'Persian'),
    ('th', 'Thai'),
    ('vi', 'Vietnamese'),
    ('id', 'Indonesian'),
    ('ms', 'Malay'),
    ('bn', 'Bengali'),
    ('ta', 'Tamil'),
    ('mr', 'Marathi'),
    ('gu', 'Gujarati'),
    ('kn', 'Kannada'),
    ('ml', 'Malayalam'),
    ('pa', 'Punjabi'),
  ];

  int get _subtitleLanguageIndex {
    final idx = _subtitleLanguageOptions.indexWhere(
      (opt) => opt.$1 == _sub.defaultSubtitleLanguage,
    );
    return idx >= 0 ? idx : 0;
  }

  // Audio language options: (code, label) - no "Off" option for audio
  static const List<(String?, String)> _audioLanguageOptions = [
    (null, 'No Preference'),
    ('en', 'English'),
    ('es', 'Spanish'),
    ('fr', 'French'),
    ('de', 'German'),
    ('it', 'Italian'),
    ('pt', 'Portuguese'),
    ('ru', 'Russian'),
    ('ja', 'Japanese'),
    ('ko', 'Korean'),
    ('zh', 'Chinese'),
    ('ar', 'Arabic'),
    ('hi', 'Hindi'),
    ('te', 'Telugu'),
    ('nl', 'Dutch'),
    ('pl', 'Polish'),
    ('tr', 'Turkish'),
    ('sv', 'Swedish'),
    ('da', 'Danish'),
    ('no', 'Norwegian'),
    ('fi', 'Finnish'),
  ];

  int get _audioLanguageIndex {
    final idx = _audioLanguageOptions.indexWhere(
      (opt) => opt.$1 == _sub.defaultAudioLanguage,
    );
    return idx >= 0 ? idx : 0;
  }

  Widget _buildPlayerTile(ExternalPlayer player) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final isInstalled = _mac.installedPlayers[player] ?? false;
    final isCustomApp = player == ExternalPlayer.customApp;
    final isCustomCommand = player == ExternalPlayer.customCommand;
    final isSystemDefault = player == ExternalPlayer.systemDefault;

    bool canSelect;
    if (isSystemDefault) {
      canSelect = true;
    } else if (isCustomApp) {
      canSelect = _mac.customAppPath != null;
    } else if (isCustomCommand) {
      canSelect = _mac.customCommand != null && _mac.customCommand!.isNotEmpty;
    } else {
      canSelect = isInstalled;
    }

    String subtitle;
    Color? subtitleColor;

    if (isSystemDefault) {
      subtitle = 'Uses system default video player';
    } else if (isCustomApp) {
      if (_mac.customAppPath != null) {
        subtitle = _mac.customAppName ?? _mac.customAppPath!;
      } else {
        subtitle = 'No application selected';
        subtitleColor = t.dim;
      }
    } else if (isCustomCommand) {
      if (_mac.customCommand != null && _mac.customCommand!.isNotEmpty) {
        final displayCmd = _mac.customCommand!.length > 40
            ? '${_mac.customCommand!.substring(0, 40)}...'
            : _mac.customCommand!;
        subtitle = displayCmd;
      } else {
        subtitle = 'No command configured';
        subtitleColor = t.dim;
      }
    } else if (isInstalled) {
      subtitle = 'Installed';
      subtitleColor = t.success;
    } else {
      subtitle = 'Not found';
      subtitleColor = t.danger;
    }

    return RadioListTile<ExternalPlayer>(
      value: player,
      groupValue: canSelect ? _mac.selectedPlayer : null,
      onChanged: canSelect
          ? (value) {
              if (value != null) {
                _selectPlayer(value);
              }
            }
          : null,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.14),
          borderRadius: app.shape.br(10),
        ),
        child: Icon(player.icon, color: canSelect ? t.accent : t.dim2),
      ),
      title: Text(
        player.displayName,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: canSelect ? app.core.tx : t.dim2,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: subtitleColor ?? t.dim),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildIOSPlayerTile(iOSExternalPlayer player) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final isInstalled = _ios.installedIOSPlayers[player] ?? false;
    final isCustom = player == iOSExternalPlayer.customScheme;

    String subtitle;
    Color? subtitleColor;

    if (isCustom) {
      if (_ios.iosCustomScheme != null && _ios.iosCustomScheme!.isNotEmpty) {
        final displayScheme = _ios.iosCustomScheme!.length > 40
            ? '${_ios.iosCustomScheme!.substring(0, 40)}...'
            : _ios.iosCustomScheme!;
        subtitle = displayScheme;
      } else {
        subtitle = 'No URL scheme configured';
        subtitleColor = t.dim;
      }
    } else {
      subtitle = player.description;
      if (isInstalled) {
        subtitleColor = t.success;
        subtitle = 'Likely installed • ${player.description}';
      }
    }

    return RadioListTile<iOSExternalPlayer>(
      value: player,
      groupValue: _ios.selectedIOSPlayer,
      onChanged: (value) {
        if (value != null) {
          _selectIOSPlayer(value);
        }
      },
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.14),
          borderRadius: app.shape.br(10),
        ),
        child: Icon(player.icon, color: t.accent),
      ),
      title: Text(
        player.displayName,
        style: TextStyle(fontWeight: FontWeight.w500, color: app.core.tx),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: subtitleColor ?? t.dim),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildLinuxPlayerTile(LinuxExternalPlayer player) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final isInstalled = _linux.installedLinuxPlayers[player] ?? false;
    final isCustom = player == LinuxExternalPlayer.customCommand;

    String subtitle;
    Color? subtitleColor;

    if (isCustom) {
      if (_linux.linuxCustomCommand != null &&
          _linux.linuxCustomCommand!.isNotEmpty) {
        final displayCommand = _linux.linuxCustomCommand!.length > 40
            ? '${_linux.linuxCustomCommand!.substring(0, 40)}...'
            : _linux.linuxCustomCommand!;
        subtitle = displayCommand;
      } else {
        subtitle = 'No command configured';
        subtitleColor = t.dim;
      }
    } else {
      subtitle = player.description;
      if (isInstalled) {
        subtitleColor = t.success;
        subtitle = 'Installed • ${player.description}';
      }
    }

    return RadioListTile<LinuxExternalPlayer>(
      value: player,
      groupValue: _linux.selectedLinuxPlayer,
      onChanged: (value) {
        if (value != null) {
          _selectLinuxPlayer(value);
        }
      },
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.14),
          borderRadius: app.shape.br(10),
        ),
        child: Icon(player.icon, color: t.accent),
      ),
      title: Text(
        player.displayName,
        style: TextStyle(fontWeight: FontWeight.w500, color: app.core.tx),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: subtitleColor ?? t.dim),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildWindowsPlayerTile(WindowsExternalPlayer player) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final isInstalled = _win.installedWindowsPlayers[player] ?? false;
    final isCustom = player == WindowsExternalPlayer.customCommand;

    String subtitle;
    Color? subtitleColor;

    if (isCustom) {
      if (_win.windowsCustomCommand != null &&
          _win.windowsCustomCommand!.isNotEmpty) {
        final displayCommand = _win.windowsCustomCommand!.length > 40
            ? '${_win.windowsCustomCommand!.substring(0, 40)}...'
            : _win.windowsCustomCommand!;
        subtitle = displayCommand;
      } else {
        subtitle = 'No command configured';
        subtitleColor = t.dim;
      }
    } else {
      subtitle = player.description;
      if (isInstalled) {
        subtitleColor = t.success;
        subtitle = 'Installed • ${player.description}';
      }
    }

    return RadioListTile<WindowsExternalPlayer>(
      value: player,
      groupValue: _win.selectedWindowsPlayer,
      onChanged: (value) {
        if (value != null) {
          _selectWindowsPlayer(value);
        }
      },
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.14),
          borderRadius: app.shape.br(10),
        ),
        child: Icon(player.icon, color: t.accent),
      ),
      title: Text(
        player.displayName,
        style: TextStyle(fontWeight: FontWeight.w500, color: app.core.tx),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: subtitleColor ?? t.dim),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildPlayerModeOption(
    BuildContext context, {
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    bool recommended = false,
    bool disabled = false,
    FocusNode? focusNode,
  }) {
    final t = AppThemeScope.of(context).settings;
    final theme = Theme.of(context);
    final isSelected = _core.defaultPlayerMode == value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      // Non-focusable wrapper only observes the InkWell's focus so the row
      // can paint a DPAD focus ring (same idiom as the Night Mode rows).
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        child: Builder(
          builder: (context) {
            final isFocused = Focus.of(context).hasFocus;
            return InkWell(
              focusNode: focusNode,
              canRequestFocus: !disabled,
              onTap: disabled ? null : () => _setDefaultPlayerMode(value),
              borderRadius: BorderRadius.circular(12),
              // Snap, don't tween — per-keypress decoration lerps jank TVs.
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected || isFocused
                      ? t.panel2
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isFocused || isSelected ? t.accent : t.line,
                    width: isFocused || isSelected ? 2 : 1,
                  ),
                  boxShadow: isFocused
                      ? [
                          BoxShadow(
                            color: t.accent.withValues(alpha: 0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    // The row is the single focus stop — the inner Radio must
                    // not add a second DPAD stop.
                    ExcludeFocus(
                      child: Radio<String>(
                        value: value,
                        groupValue: _core.defaultPlayerMode,
                        onChanged: disabled
                            ? null
                            : (v) => _setDefaultPlayerMode(v!),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      icon,
                      size: 20,
                      color: isSelected
                          ? t.accent
                          : disabled
                          ? t.dim2
                          : t.dim,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: disabled ? t.dim2 : null,
                                ),
                              ),
                              if (recommended) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: t.accent.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Default',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: t.accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: disabled ? t.dim2 : t.dim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _defaultsCard(String title, String subtitle, List<Widget> children) {
    final theme = Theme.of(context);
    final t = AppThemeScope.of(context).settings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Future<void> _openPlayerSettings() async {
    await pushSettingsPage(context, const ExternalPlayerSettingsPage());
    if (mounted) await _loadSettings();
  }

  Widget _playerAppearance() => SettingsSection(
    title: 'Appearance',
    blurb: 'The same player styles available in Appearance settings.',
    children: [
      // Match Appearance: Apple TV uses TV controls, not the player dock.
      if (_values.isAndroidTv || !PlatformUtil.isTelevision)
        SettingsTile.spec(
          SettingsRows.playerDock,
          subtitle: _values.isAndroidTv
              ? 'Control style'
              : 'Style, colour and size',
          onTap: () async {
            await pushSettingsPage(
              context,
              _values.isAndroidTv
                  ? const TvPlayerControlsStylePage()
                  : const PlayerDockPage(),
            );
          },
        ),
      if (_values.isAndroidTv)
        SettingsTile.spec(
          SettingsRows.debrifyTvPlayer,
          subtitle: 'Debrify TV playback-screen style',
          onTap: () async {
            await pushSettingsPage(context, const DebrifyTvPlayerStylePage());
          },
        ),
      SettingsTile.spec(
        SettingsRows.playerGuideStyle,
        subtitle: 'In-player IPTV guide style',
        onTap: () async {
          await pushSettingsPage(context, const PlayerGuideStylePage());
        },
      ),
      SettingsTile.spec(
        SettingsRows.playLoaderStyle,
        subtitle: 'Playback loading-screen style',
        onTap: () async {
          await pushSettingsPage(context, const PlayLoaderStylePage());
        },
      ),
    ],
  );

  List<Widget> _playerSettings() {
    final theme = Theme.of(context);
    final t = AppThemeScope.of(context).settings;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Default Player',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose which player to use when playing videos',
                style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
              ),
              const SizedBox(height: 16),
              _buildPlayerModeOption(
                context,
                value: 'debrify',
                title: 'Debrify Player',
                subtitle: 'Use the built-in video player',
                icon: Icons.play_circle_filled_rounded,
                recommended: true,
                focusNode: _core.firstModeFocusNode,
              ),
              _buildPlayerModeOption(
                context,
                value: 'external',
                title: 'External Player',
                subtitle: Platform.isMacOS
                    ? 'Open videos in your preferred external player'
                    : 'Choose which app to use when opening videos',
                icon: Icons.open_in_new_rounded,
              ),
              _buildPlayerModeOption(
                context,
                value: 'deovr',
                title: 'DeoVR',
                subtitle: 'Use this only on VR devices',
                icon: Icons.vrpano,
                disabled: !Platform.isAndroid,
              ),
            ],
          ),
        ),
      ),

      if (_core.defaultPlayerMode == 'debrify') ...[
        const SizedBox(height: 16),
        if (PlatformUtil.isPhone) ...[
          _defaultsCard(
            'When playback starts',
            'Choose the starting orientation',
            [
              // Start orientation (phones only — a TV has no
              // portrait, and a desktop window ignores the
              // preferred-orientation call entirely). Gated on the
              // WARM flag, not this page's `_isAndroidTv`: that one
              // is loaded async and starts false, so a TV would
              // paint the row and then drop it.
              if (PlatformUtil.isPhone) ...[
                const SizedBox(height: 4),
                buildCheckboxTile(
                  context,
                  title: 'Open the player in portrait',
                  subtitle:
                      'Start videos upright instead of turning the '
                      'phone landscape. The player\'s rotate button '
                      'switches to landscape whenever you want it.',
                  value: _values.startPortrait,
                  onChanged: _setStartPortrait,
                  focusNode: _rows.startPortraitFocusNode,
                  isFocused: _rows.startPortraitFocused,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
        ],
        // Local completion is deliberately independent from tracker
        // scrobbling: Trakt and Simkl keep their own watched rules.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Watch History',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mark locally tracked videos watched after this much playback. Trakt and Simkl keep their own rules.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                buildSettingDropdown(
                  context,
                  label: 'Mark movies watched at',
                  value: _completionThresholdIndex(
                    _values.movieCompletionThreshold,
                  ),
                  items: _completionThresholdOptions
                      .map((value) => '$value%')
                      .toList(),
                  onChanged: _setMovieCompletionThresholdIndex,
                  focusNode: _subRows.movieCompletionThresholdFocusNode,
                  isFocused: _subRows.movieCompletionThresholdFocused,
                ),
                const SizedBox(height: 12),
                buildSettingDropdown(
                  context,
                  label: 'Mark episodes watched at',
                  value: _completionThresholdIndex(
                    _values.episodeCompletionThreshold,
                  ),
                  items: _completionThresholdOptions
                      .map((value) => '$value%')
                      .toList(),
                  onChanged: _setEpisodeCompletionThresholdIndex,
                  focusNode: _subRows.episodeCompletionThresholdFocusNode,
                  isFocused: _subRows.episodeCompletionThresholdFocused,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Community intro/outro timestamps. This belongs to the
        // built-in player because external players own their own UI
        // and cannot display Debrify's manual skip button.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Skip Segments',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Show manual skip buttons when community timestamps are available',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 8),
                buildCheckboxTile(
                  context,
                  title: 'Skip intros & credits',
                  subtitle:
                      'Show a button during supported intros and outros. Playback is never skipped automatically.',
                  value: _values.skipSegmentsEnabled,
                  onChanged: _setSkipSegmentsEnabled,
                  focusNode: _subRows.skipSegmentsEnabledFocusNode,
                  isFocused: _subRows.skipSegmentsEnabledFocused,
                ),
                const SizedBox(height: 12),
                buildDropdownSetting(
                  context,
                  label: 'Timestamp provider',
                  value: _values.skipSegmentProvider,
                  items: SkipSegmentProviders.availableLabels,
                  onChanged: _setSkipSegmentProvider,
                  focusNode: _subRows.skipSegmentProviderFocusNode,
                  isFocused: _subRows.skipSegmentProviderFocused,
                  enabled: _values.skipSegmentsEnabled,
                ),
                const SizedBox(height: 10),
                Text(
                  _values.skipSegmentProvider == SkipSegmentProviders.auto
                      ? 'Checks every available source and prefers SkipDB, then TheIntroDB, then IntroDB.'
                      : 'Coverage varies by series, episode, and video release.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim2),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Network & Buffering: the escape hatch for slow stream
        // origins (Plex-backed addons, remote seedboxes). Standard
        // leaves both players untouched — the Debrify (mpv) player
        // reads the presets directly; the native Android TV player
        // gets them via the launch payload.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Network & Buffering',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'For stream sources that stall or time out — '
                  'Plex-backed addons, remote servers. Standard '
                  'leaves playback exactly as before.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                buildDropdownSetting(
                  context,
                  label: 'Connection patience',
                  value: _values.netPatience,
                  items: NetworkTuning.patienceOptions,
                  onChanged: _setNetPatience,
                  focusNode: _rows.netPatienceFocusNode,
                  isFocused: _rows.netPatienceFocused,
                ),
                const SizedBox(height: 12),
                buildDropdownSetting(
                  context,
                  label: 'Stream buffer',
                  value: _values.netBuffer,
                  items: NetworkTuning.bufferOptions,
                  onChanged: _setNetBuffer,
                  focusNode: _rows.netBufferFocusNode,
                  isFocused: _rows.netBufferFocused,
                ),
                const SizedBox(height: 10),
                Text(
                  'Patience raises connection timeouts and adds '
                  'automatic retries where the player supports '
                  'them. Bigger buffers ride over origin stalls '
                  'but use more memory. Live TV keeps its own '
                  'tuned pipeline. Restart playback to apply.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim2),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        _playerAppearance(),
      ],
      ..._externalPlayerSettings(),
    ];
  }

  List<Widget> _videoSettings() {
    final theme = Theme.of(context);
    final t = AppThemeScope.of(context).settings;
    return [
      _defaultsCard('Picture & decoding', 'Default picture fit and device compatibility', [
        // Default Aspect
        buildSettingDropdown(
          context,
          label: 'Default Aspect',
          value: _values.defaultAspectIndex,
          items: _aspectLabels,
          onChanged: (index) => _setDefaultAspectIndex(index),
          focusNode: _rows.aspectFocusNode,
          isFocused: _rows.aspectFocused,
        ),
        const SizedBox(height: 12),

        if (_values.isAndroidTv || PlatformUtil.isTvOS) ...[
          buildDropdownSetting(
            context,
            label: 'Match content display',
            value: _values.contentDisplayMatchMode.storageKey,
            items: {
              for (final mode in ContentDisplayMatchMode.values)
                mode.storageKey: mode.label,
            },
            onChanged: _setContentDisplayMatchMode,
            focusNode: _rows.contentDisplayMatchFocusNode,
            isFocused: _rows.contentDisplayMatchFocused,
          ),
          const SizedBox(height: 6),
          Text(
            switch (_values.contentDisplayMatchMode) {
              ContentDisplayMatchMode.systemDefault =>
                'Keeps the player’s existing platform behavior. Choose a matching mode to request content-specific output.',
              ContentDisplayMatchMode.off =>
                'Disables player-requested display matching. Restart playback to apply.',
              ContentDisplayMatchMode.frameRate =>
                PlatformUtil.isTvOS
                    ? 'Requests the source frame rate from Apple TV. Apple TV Settings → Video and Audio → Match Content → Match Frame Rate must be enabled.'
                    : 'Keeps the current output resolution and selects a compatible refresh rate. A brief black screen during a mode switch is normal.',
              ContentDisplayMatchMode.frameRateAndResolution =>
                PlatformUtil.isTvOS
                    ? 'Sends Apple TV the source frame rate, dimensions, and video format. tvOS chooses the output mode and may keep its configured resolution; resolution matching is best-effort. Match Content must be enabled in Apple TV settings.'
                    : 'Selects the closest output resolution and compatible refresh rate. A brief black screen during a mode switch is normal.',
            },
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  _values.contentDisplayMatchMode ==
                      ContentDisplayMatchMode.systemDefault
                  ? t.dim
                  : t.warning,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Android TV only. A frozen picture with running
        // audio on live IPTV is almost always the box's
        // hardware decoder choking on the stream — a device
        // defect, which is why every IPTV player ships this
        // switch rather than trying to auto-detect it.
        if (Platform.isAndroid && _values.isAndroidTv) ...[
          const SizedBox(height: 12),
          buildDropdownSetting(
            context,
            label: 'IPTV decoder',
            value: _values.iptvDecoderMode,
            items: const {
              'auto': 'Automatic',
              'hardware': 'Hardware',
              'software': 'Software',
            },
            onChanged: _setIptvDecoderMode,
            focusNode: _rows.iptvDecoderFocusNode,
            isFocused: _rows.iptvDecoderFocused,
          ),
          const SizedBox(height: 6),
          Text(
            _values.iptvDecoderMode == 'software'
                ? 'Software decoding fixes channels that freeze '
                      'while audio keeps playing, at the cost of '
                      'more CPU. Re-open the channel to apply.'
                : 'Switch to Software if a channel freezes but '
                      'audio keeps playing. Re-open the channel '
                      'to apply.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: _values.iptvDecoderMode == 'auto' ? t.dim : t.warning,
            ),
          ),
        ],

        // Android phone/tablet only. Android TV already uses
        // native Media3 + SurfaceView; Apple and desktop
        // platforms have different decoder APIs entirely.
        if (Platform.isAndroid && !_values.isAndroidTv) ...[
          const SizedBox(height: 12),
          buildDropdownSetting(
            context,
            label: 'Video renderer',
            value: _values.androidVideoRendererMode.storageKey,
            items: {
              for (final mode in AndroidVideoRendererMode.values)
                mode.storageKey: mode.label,
            },
            onChanged: _setAndroidVideoRendererMode,
            focusNode: _rows.androidVideoRendererFocusNode,
            isFocused: _rows.androidVideoRendererFocused,
          ),
          const SizedBox(height: 6),
          Text(
            '${_values.androidVideoRendererMode.description} '
            'Restart playback to apply. Use Automatic if a '
            'video is black, has incorrect colors, or loses '
            'a feature.',
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  _values.androidVideoRendererMode ==
                      AndroidVideoRendererMode.automatic
                  ? t.dim
                  : t.warning,
            ),
          ),
        ],

        // Apple TV only. The automatic 10-bit remedy
        // (PLAYER_TVOS_10BIT_PLAN.md) handles what it can
        // detect; this forces software decoding for
        // anything it cannot — wrong colors on a
        // clean-reading format, most likely.
        if (PlatformUtil.isTvOS) ...[
          const SizedBox(height: 4),
          buildCheckboxTile(
            context,
            title: 'Force software video decoding',
            subtitle:
                'Compatibility option if a video plays with '
                'wrong colors or a blank picture. Slower — '
                '4K may stutter. Applies from the next '
                'playback.',
            value: _values.tvosForceSoftwareDecode,
            onChanged: _setTvosForceSoftwareDecode,
            focusNode: _rows.tvosForceSwDecodeFocusNode,
            isFocused: _rows.tvosForceSwDecodeFocused,
          ),
        ],
      ]),
    ];
  }

  List<Widget> _audioSettings() {
    return [
      _defaultsCard(
        'Audio defaults',
        'Language and sound output for the built-in player',
        [
          // Default Audio Language
          buildSettingDropdown(
            context,
            label: 'Default Audio',
            value: _audioLanguageIndex,
            items: _audioLanguageOptions.map((opt) => opt.$2).toList(),
            onChanged: (index) =>
                _setDefaultAudioLanguage(_audioLanguageOptions[index].$1),
            focusNode: _rows.defaultAudioLangFocusNode,
            isFocused: _rows.defaultAudioLangFocused,
          ),
          const SizedBox(height: 12),

          // System audio effects (Android only). Off by
          // default because enabling it switches the audio
          // output backend — see _attachAudioEffectSession in
          // the player screen.
          if (Platform.isAndroid) ...[
            const SizedBox(height: 4),
            buildCheckboxTile(
              context,
              title: 'Allow system audio effects',
              subtitle:
                  'Let equalizer apps (Wavelet, Dolby, etc.) process playback. '
                  'Changes the audio output — restart playback to apply.',
              value: _values.systemAudioEffects,
              onChanged: _setSystemAudioEffects,
              focusNode: _rows.systemAudioEffectsFocusNode,
              isFocused: _rows.systemAudioEffectsFocused,
            ),
            // Bitstream passthrough (AUDIO_FIDELITY_PLAN.md).
            // Opt-in: a route that misreports support plays
            // silence, and only the user knows their chain.
            const SizedBox(height: 4),
            buildCheckboxTile(
              context,
              title: 'Audio passthrough (AC3 · EAC3 · DTS core)',
              subtitle:
                  'Send the original bitstream to your receiver '
                  'instead of decoding. Requires an HDMI chain '
                  'that supports it — if you hear silence, turn '
                  'this off. Restart playback to apply.',
              value: _values.audioPassthrough,
              onChanged: _setAudioPassthrough,
              focusNode: _rows.audioPassthroughFocusNode,
              isFocused: _rows.audioPassthroughFocused,
            ),
          ],

          // Apple multichannel LPCM (AUDIO_FIDELITY_PLAN.md).
          // Opt-in until AirPlay/spatial routes are proven.
          if (PlatformUtil.isTvOS || PlatformUtil.isIosMobile) ...[
            const SizedBox(height: 4),
            buildCheckboxTile(
              context,
              title: 'Multichannel audio (LPCM over HDMI)',
              subtitle:
                  'Output surround tracks as 5.1/7.1 PCM when '
                  'the connected receiver supports it, instead '
                  'of stereo. Restart playback to apply.',
              value: _values.appleMultichannel,
              onChanged: _setAppleMultichannel,
              focusNode: _rows.appleMultichannelFocusNode,
              isFocused: _rows.appleMultichannelFocused,
            ),
          ],

          // Apple TV audio diagnostics. The player normally
          // decides both of these from the output route; these
          // let a reporter narrow an audio problem without
          // waiting on a custom build.
          if (PlatformUtil.isTvOS) ...[
            const SizedBox(height: 4),
            buildCheckboxTile(
              context,
              title: 'Force stereo audio',
              subtitle:
                  'Always downmix to 2 channels, whatever the '
                  'TV or receiver reports. Try this if '
                  'surround sound is noisy or distorted. '
                  'Restart playback to apply.',
              value: _values.tvosForceStereo,
              onChanged: _setTvosForceStereo,
              focusNode: _rows.tvosForceStereoFocusNode,
              isFocused: _rows.tvosForceStereoFocused,
            ),
            const SizedBox(height: 4),
            buildCheckboxTile(
              context,
              title: 'Use the previous audio engine',
              subtitle:
                  'Go back to the audio output used before '
                  'August 2026. It has no sound at all when '
                  'Dolby Atmos is enabled, so only use it if '
                  'the current one misbehaves. Restart '
                  'playback to apply.',
              value: _values.tvosLegacyAudioOutput,
              onChanged: _setTvosLegacyAudioOutput,
              focusNode: _rows.tvosLegacyAudioFocusNode,
              isFocused: _rows.tvosLegacyAudioFocused,
            ),
          ],
        ],
      ),
      ..._nightModeSettings(),
    ];
  }

  List<Widget> _nightModeSettings() {
    final theme = Theme.of(context);
    final t = AppThemeScope.of(context).settings;
    return [
      // Night Mode (Android TV only)
      if (_values.isAndroidTv) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.nightlight_round, color: t.accent, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Night Mode',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Boosts quiet sounds for late-night viewing without disturbing others',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                ...List.generate(_nightModeLabels.length, (index) {
                  final isSelected = _values.nightModeIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Focus(
                      // Observer only: the InkWell below is the
                      // focus stop; a focusable wrapper would make
                      // each row cost two DPAD presses.
                      canRequestFocus: false,
                      skipTraversal: true,
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent) {
                          if (isActivateKey(event.logicalKey)) {
                            _setNightModeIndex(index);
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Builder(
                        builder: (context) {
                          final isFocused = Focus.of(context).hasFocus;
                          return InkWell(
                            onTap: () => _setNightModeIndex(index),
                            borderRadius: BorderRadius.circular(8),
                            // Snap, don't tween (TV GPU rule).
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? t.panel2
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isFocused
                                      ? t.accent
                                      : isSelected
                                      ? t.accent
                                      : t.line,
                                  width: isFocused || isSelected ? 2 : 1,
                                ),
                                boxShadow: isFocused
                                    ? [
                                        BoxShadow(
                                          color: t.accent.withValues(
                                            alpha: 0.25,
                                          ),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  // Single focus stop per row —
                                  // keep the Radio off the DPAD
                                  // traversal order.
                                  ExcludeFocus(
                                    child: Radio<int>(
                                      value: index,
                                      groupValue: _values.nightModeIndex,
                                      onChanged: (v) => _setNightModeIndex(v!),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _nightModeLabels[index],
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: isSelected || isFocused
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (index == 0) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: t.accent.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'Recommended',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: t.accent,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _subtitleSettings() {
    final theme = Theme.of(context);
    final t = AppThemeScope.of(context).settings;
    return [
      SettingsSection(
        title: '',
        children: [
          SettingsTile(
            icon: Icons.low_priority_rounded,
            title: 'Subtitle priority',
            subtitle:
                'Choose the order of embedded subtitles and subtitle addons',
            onTap: () async {
              await pushSettingsPage(context, const SubtitlePriorityPage());
            },
          ),
        ],
      ),
      const SizedBox(height: 16),
      _defaultsCard(
        'Subtitle defaults',
        'Preferred language and timing for the built-in player',
        [
          // Default Subtitle Language
          buildSettingDropdown(
            context,
            label: 'Default Subtitle',
            value: _subtitleLanguageIndex,
            items: _subtitleLanguageOptions.map((opt) => opt.$2).toList(),
            onChanged: (index) =>
                _setDefaultSubtitleLanguage(_subtitleLanguageOptions[index].$1),
            focusNode: _subRows.defaultSubtitleLangFocusNode,
            isFocused: _subRows.defaultSubtitleLangFocused,
          ),

          const SizedBox(height: 4),
          buildCheckboxTile(
            context,
            title: 'Subtitles when audio differs',
            subtitle:
                'Choose a Default Audio language in Playback → Audio. '
                'Subtitles stay off for matching or unknown audio; '
                'manual subtitle choices take priority.',
            value: _sub.subtitleOnlyForeignAudio,
            onChanged: _setSubtitleOnlyForeignAudio,
            focusNode: _subRows.subtitleOnlyForeignAudioFocusNode,
            isFocused: _subRows.subtitleOnlyForeignAudioFocused,
          ),

          const SizedBox(height: 4),
          buildCheckboxTile(
            context,
            title: 'Forced subtitles only',
            subtitle:
                'Automatically use embedded tracks marked forced in your Default Subtitle language '
                '(English if unset). No match means off; Default Subtitle Off disables it. '
                'Overrides Subtitles when audio differs; manual choices take priority.',
            value: _sub.subtitleForcedOnly,
            onChanged: _setSubtitleForcedOnly,
            focusNode: _subRows.subtitleForcedOnlyFocusNode,
            isFocused: _subRows.subtitleForcedOnlyFocused,
          ),

          // Only platforms whose bundled native player is
          // built with the required passive analysis filters
          // (see PlatformUtil.supportsSubtitleAutoSync).
          if (PlatformUtil.supportsSubtitleAutoSync) ...[
            const SizedBox(height: 4),
            buildCheckboxTile(
              context,
              title: 'Auto-sync addon subtitles (experimental)',
              subtitle:
                  'Quietly align downloaded subtitles to the audio '
                  'as you watch. Applies only on a confident match; '
                  'manual timing always wins.',
              value: _sub.subtitleAutoSync,
              onChanged: _setSubtitleAutoSync,
              focusNode: _subRows.subtitleAutoSyncFocusNode,
              isFocused: _subRows.subtitleAutoSyncFocused,
            ),
          ],
        ],
      ),
      const SizedBox(height: 16),
      // Subtitle Appearance
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Subtitle Appearance',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Customize how subtitles look',
                style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
              ),
              const SizedBox(height: 16),

              // Size
              buildSettingDropdown(
                context,
                label: 'Size',
                value: _sub.subtitleSizeIndex,
                items: SubtitleSize.options.map((o) => o.label).toList(),
                onChanged: (index) => _setSubtitleSizeIndex(index),
                focusNode: _subRows.subtitleSizeFocusNode,
                isFocused: _subRows.subtitleSizeFocused,
              ),
              const SizedBox(height: 12),

              // Style
              buildSettingDropdown(
                context,
                label: 'Style',
                value: _sub.subtitleStyleIndex,
                items: SubtitleStyle.options.map((o) => o.label).toList(),
                onChanged: (index) => _setSubtitleStyleIndex(index),
                focusNode: _subRows.subtitleStyleFocusNode,
                isFocused: _subRows.subtitleStyleFocused,
              ),
              const SizedBox(height: 12),

              // Color
              buildSettingDropdown(
                context,
                label: 'Color',
                value: _sub.subtitleColorIndex,
                items: SubtitleColor.options.map((o) => o.label).toList(),
                onChanged: (index) => _setSubtitleColorIndex(index),
                focusNode: _subRows.subtitleColorFocusNode,
                isFocused: _subRows.subtitleColorFocused,
              ),
              const SizedBox(height: 12),

              // Background
              buildSettingDropdown(
                context,
                label: 'Background',
                value: _sub.subtitleBgIndex,
                items: SubtitleBackground.options.map((o) => o.label).toList(),
                onChanged: (index) => _setSubtitleBgIndex(index),
                focusNode: _subRows.subtitleBgFocusNode,
                isFocused: _subRows.subtitleBgFocused,
              ),
              const SizedBox(height: 12),

              // Font
              buildSettingDropdown(
                context,
                label: 'Font',
                value: _sub.subtitleFontIndex,
                items: _sub.allFonts
                    .map((f) => f.isCustom ? '${f.label} (Custom)' : f.label)
                    .toList(),
                onChanged: (index) => _setSubtitleFontIndex(index),
                focusNode: _subRows.subtitleFontFocusNode,
                isFocused: _subRows.subtitleFontFocused,
              ),
              const SizedBox(height: 12),

              // Bold
              buildSettingDropdown(
                context,
                label: 'Bold',
                value: _sub.subtitleBold ? 1 : 0,
                items: const ['Off', 'On'],
                onChanged: (index) => _setSubtitleBold(index == 1),
                focusNode: _subRows.subtitleBoldFocusNode,
                isFocused: _subRows.subtitleBoldFocused,
              ),

              // Import custom font button (always visible)
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _importCustomFont,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Import Custom Font (TTF/OTF)'),
                  // Default focus overlay is too faint for TV —
                  // paint an explicit accent ring + lit fill.
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (s) => s.contains(WidgetState.focused) ? t.panel2 : null,
                    ),
                    side: WidgetStateProperty.resolveWith(
                      (s) => s.contains(WidgetState.focused)
                          ? BorderSide(color: t.accent, width: 2)
                          : null,
                    ),
                  ),
                ),
              ),

              // List of custom fonts with delete buttons
              if (_sub.allFonts.any((f) => f.isCustom)) ...[
                const SizedBox(height: 12),
                Text(
                  'Custom Fonts',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: t.dim,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                ..._sub.allFonts
                    .where((f) => f.isCustom)
                    .map(
                      (font) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(Icons.text_fields, size: 16, color: t.dim),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                font.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      _sub
                                              .allFonts[_sub.subtitleFontIndex]
                                              .id ==
                                          font.id
                                      ? t.accent
                                      : t.dim,
                                  fontWeight:
                                      _sub
                                              .allFonts[_sub.subtitleFontIndex]
                                              .id ==
                                          font.id
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _removeCustomFont(font),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: t.danger,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              tooltip: 'Remove font',
                              // DPAD focus must be unmistakable.
                              style: ButtonStyle(
                                backgroundColor:
                                    WidgetStateProperty.resolveWith(
                                      (s) => s.contains(WidgetState.focused)
                                          ? t.panel2
                                          : null,
                                    ),
                                side: WidgetStateProperty.resolveWith(
                                  (s) => s.contains(WidgetState.focused)
                                      ? BorderSide(color: t.accent, width: 2)
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],

              const SizedBox(height: 16),

              // Preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Builder(
                    builder: (context) {
                      final previewSize =
                          SubtitleSize.options[_sub.subtitleSizeIndex].sizePx *
                          0.4;
                      final data = SubtitleSettingsData(
                        sizeIndex: _sub.subtitleSizeIndex,
                        styleIndex: _sub.subtitleStyleIndex,
                        colorIndex: _sub.subtitleColorIndex,
                        bgIndex: _sub.subtitleBgIndex,
                        bold: _sub.subtitleBold,
                        fontIndex: _sub.subtitleFontIndex,
                        fontFamily:
                            _sub.subtitleFontIndex < _sub.allFonts.length
                            ? _sub.allFonts[_sub.subtitleFontIndex].fontFamily
                            : null,
                      );
                      return Text(
                        'Sample Subtitle',
                        // Built by the same code the player uses,
                        // at the preview's size — a preview that
                        // styles text its own way is a preview
                        // that can lie about bold.
                        style: data.buildTextStyle(fontSizePx: previewSize),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _externalPlayerSettings() {
    final theme = Theme.of(context);
    final t = AppThemeScope.of(context).settings;
    return [
      // Android External Player info
      if (Platform.isAndroid && _core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'When enabled, you will be able to choose which app to use when opening videos. Install VLC, MX Player, or other video player apps to see them in the chooser.',
        ),
      ],

      // iOS + Apple TV player selection (same catalog; tvOS shows
      // only the players that ship an Apple TV app)
      if ((PlatformUtil.isIosMobile || PlatformUtil.isTvOS) &&
          _core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Preferred Player',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Select the app to open videos with. Make sure the app is installed from the App Store.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
              ),
              const SizedBox(height: 8),
              // tvOS lists only players with a real Apple TV app —
              // a row that can never launch is worse than no row.
              ...[
                for (final (i, player)
                    in iOSExternalPlayer.values
                        .where((p) => !PlatformUtil.isTvOS || p.availableOnTvos)
                        .indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _buildIOSPlayerTile(player),
                ],
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],

      // iOS Custom URL Scheme configuration
      if ((PlatformUtil.isIosMobile || PlatformUtil.isTvOS) &&
          _core.defaultPlayerMode == 'external' &&
          _ios.selectedIOSPlayer == iOSExternalPlayer.customScheme) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.code_rounded, color: t.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Custom URL Scheme',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Define a custom URL scheme to launch videos',
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _ios.iosSchemeFocused
                        ? [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: TvTextField(
                    controller: _ios.iosSchemeController,
                    // The surrounding Container draws this field's focus ring;
                    // skip the shell's fallback ring so they don't double up.
                    shellRing: false,
                    focusNode: _ios.iosSchemeFocusNode,
                    decoration: InputDecoration(
                      labelText: 'URL Scheme Template',
                      hintText: 'myplayer://play?url={url}',
                      helperText: 'Use {url} for the video URL',
                      helperMaxLines: 2,
                      errorText: _ios.iosSchemeError,
                      prefixIcon: const Icon(Icons.link_rounded),
                    ),
                    onChanged: (_) {
                      if (_ios.iosSchemeError != null) {
                        setState(() {
                          _ios.iosSchemeError = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saveIOSCustomScheme,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save'),
                      ),
                    ),
                    if (_ios.iosCustomScheme != null &&
                        _ios.iosCustomScheme!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _clearIOSCustomScheme,
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.panel2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Examples',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'vlc://{url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'infuse://x-callback-url/play?url={url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'customapp://stream?video={url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],

      // iOS external player info
      if ((PlatformUtil.isIosMobile || PlatformUtil.isTvOS) &&
          _core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'Videos will open in the selected app using URL schemes. Make sure the player app is installed from the App Store.',
        ),
      ],

      // Linux-specific player selection
      if (Platform.isLinux && _core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Preferred Player',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Select the player to open videos with. Players marked as "Installed" were detected on your system.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
              ),
              const SizedBox(height: 8),
              _buildLinuxPlayerTile(LinuxExternalPlayer.systemDefault),
              const Divider(height: 1),
              _buildLinuxPlayerTile(LinuxExternalPlayer.vlc),
              const Divider(height: 1),
              _buildLinuxPlayerTile(LinuxExternalPlayer.mpv),
              const Divider(height: 1),
              _buildLinuxPlayerTile(LinuxExternalPlayer.celluloid),
              const Divider(height: 1),
              _buildLinuxPlayerTile(LinuxExternalPlayer.smplayer),
              const Divider(height: 1),
              _buildLinuxPlayerTile(LinuxExternalPlayer.customCommand),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],

      // Linux Custom Command configuration
      if (Platform.isLinux &&
          _core.defaultPlayerMode == 'external' &&
          _linux.selectedLinuxPlayer == LinuxExternalPlayer.customCommand) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.terminal_rounded, color: t.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Custom Command',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Define a custom command to launch videos',
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _linux.linuxCommandFocused
                        ? [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: TvTextField(
                    controller: _linux.linuxCommandController,
                    // The surrounding Container draws this field's focus ring;
                    // skip the shell's fallback ring so they don't double up.
                    shellRing: false,
                    focusNode: _linux.linuxCommandFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Command Template',
                      hintText: 'vlc --fullscreen {url}',
                      helperText: 'Use {url} for video URL, {title} for title',
                      helperMaxLines: 2,
                      errorText: _linux.linuxCommandError,
                      prefixIcon: const Icon(Icons.code_rounded),
                    ),
                    onChanged: (_) {
                      if (_linux.linuxCommandError != null) {
                        setState(() {
                          _linux.linuxCommandError = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saveLinuxCustomCommand,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save'),
                      ),
                    ),
                    if (_linux.linuxCustomCommand != null &&
                        _linux.linuxCustomCommand!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _clearLinuxCustomCommand,
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.panel2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Examples',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'vlc --fullscreen {url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'mpv --title="{title}" {url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'celluloid {url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],

      // Linux external player info
      if (Platform.isLinux && _core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'Videos will open in the selected player via command line. Make sure the player is installed on your system.',
        ),
      ],

      // Windows-specific player selection
      if (Platform.isWindows && _core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Preferred Player',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Select the player to open videos with. Players marked as "Installed" were detected on your system.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
              ),
              const SizedBox(height: 8),
              _buildWindowsPlayerTile(WindowsExternalPlayer.systemDefault),
              const Divider(height: 1),
              _buildWindowsPlayerTile(WindowsExternalPlayer.vlc),
              const Divider(height: 1),
              _buildWindowsPlayerTile(WindowsExternalPlayer.mpv),
              const Divider(height: 1),
              _buildWindowsPlayerTile(WindowsExternalPlayer.mpcHc),
              const Divider(height: 1),
              _buildWindowsPlayerTile(WindowsExternalPlayer.potPlayer),
              const Divider(height: 1),
              _buildWindowsPlayerTile(WindowsExternalPlayer.customCommand),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],

      // Windows Custom Command configuration
      if (Platform.isWindows &&
          _core.defaultPlayerMode == 'external' &&
          _win.selectedWindowsPlayer ==
              WindowsExternalPlayer.customCommand) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.terminal_rounded, color: t.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Custom Command',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Define a custom command to launch videos',
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _win.windowsCommandFocused
                        ? [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: TvTextField(
                    controller: _win.windowsCommandController,
                    // The surrounding Container draws this field's focus ring;
                    // skip the shell's fallback ring so they don't double up.
                    shellRing: false,
                    focusNode: _win.windowsCommandFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Command Template',
                      hintText: 'vlc --fullscreen {url}',
                      helperText: 'Use {url} for video URL, {title} for title',
                      helperMaxLines: 2,
                      errorText: _win.windowsCommandError,
                      prefixIcon: const Icon(Icons.code_rounded),
                    ),
                    onChanged: (_) {
                      if (_win.windowsCommandError != null) {
                        setState(() {
                          _win.windowsCommandError = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saveWindowsCustomCommand,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save'),
                      ),
                    ),
                    if (_win.windowsCustomCommand != null &&
                        _win.windowsCustomCommand!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _clearWindowsCustomCommand,
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.panel2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Examples',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'vlc --fullscreen {url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'mpv --title="{title}" {url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '"C:\\Program Files\\MPC-HC\\mpc-hc64.exe" {url} /play',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],

      // Windows external player info
      if (Platform.isWindows && _core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'Videos will open in the selected player. For MPC-HC and PotPlayer, the app checks common installation paths. Use Custom Command if the player is installed elsewhere.',
        ),
      ],

      // macOS-specific player selection
      if (Platform.isMacOS && _core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Preferred Player',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildPlayerTile(ExternalPlayer.systemDefault),
              const Divider(height: 1),
              _buildPlayerTile(ExternalPlayer.vlc),
              const Divider(height: 1),
              _buildPlayerTile(ExternalPlayer.iina),
              const Divider(height: 1),
              _buildPlayerTile(ExternalPlayer.mpv),
              const Divider(height: 1),
              _buildPlayerTile(ExternalPlayer.quickTime),
              const Divider(height: 1),
              _buildPlayerTile(ExternalPlayer.infuse),
              const Divider(height: 1),
              _buildPlayerTile(ExternalPlayer.customApp),
              const Divider(height: 1),
              _buildPlayerTile(ExternalPlayer.customCommand),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],

      // Custom App configuration (macOS only, when selected)
      if (Platform.isMacOS &&
          _core.defaultPlayerMode == 'external' &&
          _mac.selectedPlayer == ExternalPlayer.customApp) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_open_rounded, color: t.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Custom App',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Select a .app to use as your video player',
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                if (_mac.customAppPath != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.panel2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.apps_rounded, color: t.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _mac.customAppName ?? 'Custom App',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                _mac.customAppPath!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: t.dim,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _browseForCustomApp,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: Text(
                          _mac.customAppPath == null ? 'Browse' : 'Change',
                        ),
                      ),
                    ),
                    if (_mac.customAppPath != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _clearCustomApp,
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],

      // Custom Command configuration (macOS only, when selected)
      if (Platform.isMacOS &&
          _core.defaultPlayerMode == 'external' &&
          _mac.selectedPlayer == ExternalPlayer.customCommand) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.code_rounded, color: t.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Custom Command',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Define a custom shell command to launch videos',
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: _mac.commandFocused
                        ? Border.all(color: t.accent, width: 1.8)
                        : null,
                    boxShadow: _mac.commandFocused
                        ? [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: TvTextField(
                    controller: _mac.commandController,
                    // The surrounding Container draws this field's focus ring;
                    // skip the shell's fallback ring so they don't double up.
                    shellRing: false,
                    focusNode: _mac.commandFocusNode,
                    // Directional (non-wrapping): DOWN on the last
                    // row must not jump back to the top of the page.
                    onDownArrow: () => FocusScope.of(
                      context,
                    ).focusInDirection(TraversalDirection.down),
                    onUpArrow: () => FocusScope.of(
                      context,
                    ).focusInDirection(TraversalDirection.up),
                    decoration: InputDecoration(
                      labelText: 'Command',
                      hintText: 'vlc --fullscreen {url}',
                      helperText: 'Use {url} for video URL, {title} for title',
                      helperMaxLines: 2,
                      errorText: _mac.commandError,
                      prefixIcon: const Icon(Icons.terminal_rounded),
                    ),
                    onChanged: (_) {
                      if (_mac.commandError != null) {
                        setState(() {
                          _mac.commandError = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saveCustomCommand,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save Command'),
                      ),
                    ),
                    if (_mac.customCommand != null &&
                        _mac.customCommand!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _clearCustomCommand,
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.panel2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Examples',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'vlc --fullscreen {url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'mpv --fs --title="{title}" {url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '/opt/homebrew/bin/mpv {url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],

      // macOS external player info
      if (Platform.isMacOS && _core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'Players marked as "Not found" are not installed on your system. Install them via the App Store, Homebrew, or their official websites.',
        ),
      ],

      // DeoVR settings (Android only, when selected)
      if (Platform.isAndroid && _core.defaultPlayerMode == 'deovr') ...[
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.vrpano, color: t.accent, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'DeoVR Settings',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // VR Format Settings
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Default VR Format',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Used when format cannot be detected from filename',
                      style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                    ),
                    const SizedBox(height: 16),

                    // Screen Type dropdown
                    buildDropdownSetting(
                      context,
                      label: 'Screen Type',
                      value: _vr.vrDefaultScreenType,
                      items: deovr.screenTypeLabels,
                      onChanged: _setVrDefaultScreenType,
                      focusNode: _vr.screenTypeFocusNode,
                      isFocused: _vr.screenTypeFocused,
                    ),
                    const SizedBox(height: 12),

                    // Stereo Mode dropdown
                    buildDropdownSetting(
                      context,
                      label: 'Stereo Mode',
                      value: _vr.vrDefaultStereoMode,
                      items: deovr.stereoModeLabels,
                      onChanged: _setVrDefaultStereoMode,
                      focusNode: _vr.stereoModeFocusNode,
                      isFocused: _vr.stereoModeFocused,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Checkboxes
              buildCheckboxTile(
                context,
                title: 'Auto-detect format from filename',
                subtitle: 'Parse filename for VR markers (180, 360, SBS, etc.)',
                value: _vr.vrAutoDetectFormat,
                onChanged: _setVrAutoDetectFormat,
                focusNode: _vr.autoDetectFocusNode,
                isFocused: _vr.autoDetectFocused,
              ),
              buildCheckboxTile(
                context,
                title: 'Show format selection dialog',
                subtitle: 'Confirm VR format before launching DeoVR',
                value: _vr.vrShowDialog,
                onChanged: _setVrShowDialog,
                focusNode: _vr.showDialogFocusNode,
                isFocused: _vr.showDialogFocused,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'DeoVR must be installed on your device. All videos will open in DeoVR with the selected VR format settings.',
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final isSupportedPlatform =
        Platform.isMacOS ||
        Platform.isAndroid ||
        PlatformUtil.isIosMobile ||
        PlatformUtil.isTvOS ||
        Platform.isLinux ||
        Platform.isWindows;
    if (!isSupportedPlatform) {
      return SettingsPageScaffold(
        title: section.label,
        body: const Center(
          child: Text('Player settings are not available on this platform'),
        ),
      );
    }
    if (_core.loading) {
      return SettingsPageScaffold(
        title: section.label,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final managedExternally =
        section != PlaybackSettingsSection.player &&
        _core.defaultPlayerMode != 'debrify';
    return SettingsPageScaffold(
      title: section.label,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Focus(
              focusNode: _core.contentFocusNode,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsPageHeader(
                    icon: section.icon,
                    title: section.label,
                    subtitle: section.description,
                  ),
                  const SizedBox(height: 16),
                  if (managedExternally) ...[
                    SettingsInfoBanner(
                      text:
                          '${_core.defaultPlayerMode == 'deovr' ? 'DeoVR' : 'Your external player'} manages these settings. Choose Debrify Player to configure its defaults.',
                    ),
                    const SizedBox(height: 16),
                    SettingsSection(
                      title: '',
                      children: [
                        SettingsTile(
                          icon: Icons.play_circle_outline_rounded,
                          title: 'Choose player',
                          subtitle: 'Open Player settings',
                          onTap: _openPlayerSettings,
                        ),
                      ],
                    ),
                  ] else
                    ...switch (section) {
                      PlaybackSettingsSection.player => _playerSettings(),
                      PlaybackSettingsSection.video => _videoSettings(),
                      PlaybackSettingsSection.audio => _audioSettings(),
                      PlaybackSettingsSection.subtitles => _subtitleSettings(),
                    },
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
Map<String, Object?> playbackSettingsTestAccess(
  State<ExternalPlayerSettingsPage> state,
) {
  final s = state as _ExternalPlayerSettingsPageState;
  return {
    'loading': s._core.loading,
    'contentFocusNode': s._core.contentFocusNode,
    'defaultPlayerMode': s._core.defaultPlayerMode,
    'selectedPlayer': s._mac.selectedPlayer,
    'installedPlayers': Map.unmodifiable(s._mac.installedPlayers),
    'customAppPath': s._mac.customAppPath,
    'customAppName': s._mac.customAppName,
    'customCommand': s._mac.customCommand,
    'commandController': s._mac.commandController,
    'commandFocusNode': s._mac.commandFocusNode,
    'commandFocused': s._mac.commandFocused,
    'commandError': s._mac.commandError,
    'selectedIOSPlayer': s._ios.selectedIOSPlayer,
    'installedIOSPlayers': Map.unmodifiable(s._ios.installedIOSPlayers),
    'iosCustomScheme': s._ios.iosCustomScheme,
    'iosSchemeController': s._ios.iosSchemeController,
    'iosSchemeFocusNode': s._ios.iosSchemeFocusNode,
    'iosSchemeFocused': s._ios.iosSchemeFocused,
    'iosSchemeError': s._ios.iosSchemeError,
    'selectedLinuxPlayer': s._linux.selectedLinuxPlayer,
    'installedLinuxPlayers': Map.unmodifiable(s._linux.installedLinuxPlayers),
    'linuxCustomCommand': s._linux.linuxCustomCommand,
    'linuxCommandController': s._linux.linuxCommandController,
    'linuxCommandFocusNode': s._linux.linuxCommandFocusNode,
    'linuxCommandFocused': s._linux.linuxCommandFocused,
    'linuxCommandError': s._linux.linuxCommandError,
    'selectedWindowsPlayer': s._win.selectedWindowsPlayer,
    'installedWindowsPlayers': Map.unmodifiable(s._win.installedWindowsPlayers),
    'windowsCustomCommand': s._win.windowsCustomCommand,
    'windowsCommandController': s._win.windowsCommandController,
    'windowsCommandFocusNode': s._win.windowsCommandFocusNode,
    'windowsCommandFocused': s._win.windowsCommandFocused,
    'windowsCommandError': s._win.windowsCommandError,
    'vrDefaultScreenType': s._vr.vrDefaultScreenType,
    'vrDefaultStereoMode': s._vr.vrDefaultStereoMode,
    'vrAutoDetectFormat': s._vr.vrAutoDetectFormat,
    'vrShowDialog': s._vr.vrShowDialog,
    'isAndroidTv': s._values.isAndroidTv,
    'defaultAspectIndex': s._values.defaultAspectIndex,
    'nightModeIndex': s._values.nightModeIndex,
    'systemAudioEffects': s._values.systemAudioEffects,
    'tvosForceSoftwareDecode': s._values.tvosForceSoftwareDecode,
    'audioPassthrough': s._values.audioPassthrough,
    'appleMultichannel': s._values.appleMultichannel,
    'tvosForceStereo': s._values.tvosForceStereo,
    'tvosLegacyAudioOutput': s._values.tvosLegacyAudioOutput,
    'androidVideoRendererMode': s._values.androidVideoRendererMode,
    'contentDisplayMatchMode': s._values.contentDisplayMatchMode,
    'startPortrait': s._values.startPortrait,
    'subtitleOnlyForeignAudio': s._sub.subtitleOnlyForeignAudio,
    'subtitleForcedOnly': s._sub.subtitleForcedOnly,
    'subtitleAutoSync': s._sub.subtitleAutoSync,
    'movieCompletionThreshold': s._values.movieCompletionThreshold,
    'episodeCompletionThreshold': s._values.episodeCompletionThreshold,
    'skipSegmentsEnabled': s._values.skipSegmentsEnabled,
    'skipSegmentProvider': s._values.skipSegmentProvider,
    'netPatience': s._values.netPatience,
    'netBuffer': s._values.netBuffer,
    'defaultSubtitleLanguage': s._sub.defaultSubtitleLanguage,
    'defaultAudioLanguage': s._sub.defaultAudioLanguage,
    'subtitleSizeIndex': s._sub.subtitleSizeIndex,
    'subtitleStyleIndex': s._sub.subtitleStyleIndex,
    'subtitleColorIndex': s._sub.subtitleColorIndex,
    'subtitleBgIndex': s._sub.subtitleBgIndex,
    'subtitleFontIndex': s._sub.subtitleFontIndex,
    'subtitleBold': s._sub.subtitleBold,
    'allFonts': List<SubtitleFont>.unmodifiable(s._sub.allFonts),
    'firstModeFocusNode': s._core.firstModeFocusNode,
    'aspectFocusNode': s._rows.aspectFocusNode,
    'defaultAudioLangFocusNode': s._rows.defaultAudioLangFocusNode,
    'defaultSubtitleLangFocusNode': s._subRows.defaultSubtitleLangFocusNode,
    'systemAudioEffectsFocusNode': s._rows.systemAudioEffectsFocusNode,
    'tvosForceSwDecodeFocusNode': s._rows.tvosForceSwDecodeFocusNode,
    'audioPassthroughFocusNode': s._rows.audioPassthroughFocusNode,
    'appleMultichannelFocusNode': s._rows.appleMultichannelFocusNode,
    'tvosForceStereoFocusNode': s._rows.tvosForceStereoFocusNode,
    'tvosLegacyAudioFocusNode': s._rows.tvosLegacyAudioFocusNode,
    'androidVideoRendererFocusNode': s._rows.androidVideoRendererFocusNode,
    'contentDisplayMatchFocusNode': s._rows.contentDisplayMatchFocusNode,
    'iptvDecoderFocusNode': s._rows.iptvDecoderFocusNode,
    'startPortraitFocusNode': s._rows.startPortraitFocusNode,
    'subtitleOnlyForeignAudioFocusNode':
        s._subRows.subtitleOnlyForeignAudioFocusNode,
    'subtitleForcedOnlyFocusNode': s._subRows.subtitleForcedOnlyFocusNode,
    'subtitleAutoSyncFocusNode': s._subRows.subtitleAutoSyncFocusNode,
    'movieCompletionThresholdFocusNode':
        s._subRows.movieCompletionThresholdFocusNode,
    'episodeCompletionThresholdFocusNode':
        s._subRows.episodeCompletionThresholdFocusNode,
    'skipSegmentsEnabledFocusNode': s._subRows.skipSegmentsEnabledFocusNode,
    'skipSegmentProviderFocusNode': s._subRows.skipSegmentProviderFocusNode,
    'subtitleSizeFocusNode': s._subRows.subtitleSizeFocusNode,
    'subtitleStyleFocusNode': s._subRows.subtitleStyleFocusNode,
    'subtitleColorFocusNode': s._subRows.subtitleColorFocusNode,
    'subtitleBgFocusNode': s._subRows.subtitleBgFocusNode,
    'subtitleFontFocusNode': s._subRows.subtitleFontFocusNode,
    'subtitleBoldFocusNode': s._subRows.subtitleBoldFocusNode,
    'netPatienceFocusNode': s._rows.netPatienceFocusNode,
    'netBufferFocusNode': s._rows.netBufferFocusNode,
    'aspectFocused': s._rows.aspectFocused,
    'defaultAudioLangFocused': s._rows.defaultAudioLangFocused,
    'defaultSubtitleLangFocused': s._subRows.defaultSubtitleLangFocused,
    'systemAudioEffectsFocused': s._rows.systemAudioEffectsFocused,
    'tvosForceSwDecodeFocused': s._rows.tvosForceSwDecodeFocused,
    'audioPassthroughFocused': s._rows.audioPassthroughFocused,
    'appleMultichannelFocused': s._rows.appleMultichannelFocused,
    'tvosForceStereoFocused': s._rows.tvosForceStereoFocused,
    'tvosLegacyAudioFocused': s._rows.tvosLegacyAudioFocused,
    'androidVideoRendererFocused': s._rows.androidVideoRendererFocused,
    'contentDisplayMatchFocused': s._rows.contentDisplayMatchFocused,
    'iptvDecoderFocused': s._rows.iptvDecoderFocused,
    'iptvDecoderMode': s._values.iptvDecoderMode,
    'startPortraitFocused': s._rows.startPortraitFocused,
    'subtitleOnlyForeignAudioFocused':
        s._subRows.subtitleOnlyForeignAudioFocused,
    'subtitleForcedOnlyFocused': s._subRows.subtitleForcedOnlyFocused,
    'subtitleAutoSyncFocused': s._subRows.subtitleAutoSyncFocused,
    'movieCompletionThresholdFocused':
        s._subRows.movieCompletionThresholdFocused,
    'episodeCompletionThresholdFocused':
        s._subRows.episodeCompletionThresholdFocused,
    'skipSegmentsEnabledFocused': s._subRows.skipSegmentsEnabledFocused,
    'skipSegmentProviderFocused': s._subRows.skipSegmentProviderFocused,
    'subtitleSizeFocused': s._subRows.subtitleSizeFocused,
    'subtitleStyleFocused': s._subRows.subtitleStyleFocused,
    'subtitleColorFocused': s._subRows.subtitleColorFocused,
    'subtitleBgFocused': s._subRows.subtitleBgFocused,
    'subtitleFontFocused': s._subRows.subtitleFontFocused,
    'subtitleBoldFocused': s._subRows.subtitleBoldFocused,
    'netPatienceFocused': s._rows.netPatienceFocused,
    'netBufferFocused': s._rows.netBufferFocused,
    'screenTypeFocusNode': s._vr.screenTypeFocusNode,
    'stereoModeFocusNode': s._vr.stereoModeFocusNode,
    'autoDetectFocusNode': s._vr.autoDetectFocusNode,
    'showDialogFocusNode': s._vr.showDialogFocusNode,
    'screenTypeFocused': s._vr.screenTypeFocused,
    'stereoModeFocused': s._vr.stereoModeFocused,
    'autoDetectFocused': s._vr.autoDetectFocused,
    'showDialogFocused': s._vr.showDialogFocused,
    'loadSettings': s._loadSettings,
    'setDefaultPlayerMode': s._setDefaultPlayerMode,
    'selectPlayer': s._selectPlayer,
    'browseForCustomApp': s._browseForCustomApp,
    'clearCustomApp': s._clearCustomApp,
    'saveCustomCommand': s._saveCustomCommand,
    'clearCustomCommand': s._clearCustomCommand,
    'selectIOSPlayer': s._selectIOSPlayer,
    'saveIOSCustomScheme': s._saveIOSCustomScheme,
    'clearIOSCustomScheme': s._clearIOSCustomScheme,
    'selectLinuxPlayer': s._selectLinuxPlayer,
    'saveLinuxCustomCommand': s._saveLinuxCustomCommand,
    'clearLinuxCustomCommand': s._clearLinuxCustomCommand,
    'selectWindowsPlayer': s._selectWindowsPlayer,
    'saveWindowsCustomCommand': s._saveWindowsCustomCommand,
    'clearWindowsCustomCommand': s._clearWindowsCustomCommand,
    'setVrDefaultScreenType': s._setVrDefaultScreenType,
    'setVrDefaultStereoMode': s._setVrDefaultStereoMode,
    'setVrAutoDetectFormat': s._setVrAutoDetectFormat,
    'setVrShowDialog': s._setVrShowDialog,
    'setDefaultAspectIndex': s._setDefaultAspectIndex,
    'setNightModeIndex': s._setNightModeIndex,
    'setSystemAudioEffects': s._setSystemAudioEffects,
    'setTvosForceSoftwareDecode': s._setTvosForceSoftwareDecode,
    'setTvosForceStereo': s._setTvosForceStereo,
    'setTvosLegacyAudioOutput': s._setTvosLegacyAudioOutput,
    'setAudioPassthrough': s._setAudioPassthrough,
    'setAppleMultichannel': s._setAppleMultichannel,
    'setAndroidVideoRendererMode': s._setAndroidVideoRendererMode,
    'setContentDisplayMatchMode': s._setContentDisplayMatchMode,
    'setIptvDecoderMode': s._setIptvDecoderMode,
    'setStartPortrait': s._setStartPortrait,
    'setSubtitleOnlyForeignAudio': s._setSubtitleOnlyForeignAudio,
    'setSubtitleForcedOnly': s._setSubtitleForcedOnly,
    'setSubtitleAutoSync': s._setSubtitleAutoSync,
    'completionThresholdOptions': s._completionThresholdOptions,
    'completionThresholdIndex': s._completionThresholdIndex,
    'setMovieCompletionThresholdIndex': s._setMovieCompletionThresholdIndex,
    'setEpisodeCompletionThresholdIndex': s._setEpisodeCompletionThresholdIndex,
    'setSkipSegmentsEnabled': s._setSkipSegmentsEnabled,
    'setSkipSegmentProvider': s._setSkipSegmentProvider,
    'setNetPatience': s._setNetPatience,
    'setNetBuffer': s._setNetBuffer,
    'setDefaultSubtitleLanguage': s._setDefaultSubtitleLanguage,
    'setDefaultAudioLanguage': s._setDefaultAudioLanguage,
    'setSubtitleSizeIndex': s._setSubtitleSizeIndex,
    'setSubtitleStyleIndex': s._setSubtitleStyleIndex,
    'setSubtitleColorIndex': s._setSubtitleColorIndex,
    'setSubtitleBgIndex': s._setSubtitleBgIndex,
    'setSubtitleFontIndex': s._setSubtitleFontIndex,
    'setSubtitleBold': s._setSubtitleBold,
    'loadFonts': s._loadFonts,
    'importCustomFont': s._importCustomFont,
    'removeCustomFont': s._removeCustomFont,
    'aspectLabels': s._aspectLabels,
    'subtitleLanguageIndex': s._subtitleLanguageIndex,
    'audioLanguageIndex': s._audioLanguageIndex,
    'openPlayerSettings': s._openPlayerSettings,
  };
}
