import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_sections.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_vr_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_windows_state.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

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
  PlaybackSections? _cachedSections;
  PlaybackSections get _sections => _cachedSections ??= createPlaybackSections(
    core: _core,
    mac: _mac,
    ios: _ios,
    linux: _linux,
    win: _win,
    vr: _vr,
    values: _values,
    sub: _sub,
    rows: _rows,
    subRows: _subRows,
    setState: setState,
    mounted: () => mounted,
    context: () => context,
    section: () => widget.section,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('playback_${widget.section.name}_settings');
    _sections.load.loadSettings();
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

  Future<void> _openPlayerSettings() async {
    await pushSettingsPage(context, const ExternalPlayerSettingsPage());
    if (mounted) await _sections.load.loadSettings();
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
                      PlaybackSettingsSection.player =>
                        _sections.playerSection.playerSettings(),
                      PlaybackSettingsSection.video =>
                        _sections.videoSection.videoSettings(),
                      PlaybackSettingsSection.audio =>
                        _sections.audioSection.audioSettings(),
                      PlaybackSettingsSection.subtitles =>
                        _sections.subtitleSection.subtitleSettings(),
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
    'loadSettings': s._sections.load.loadSettings,
    'setDefaultPlayerMode': s._sections.playerModeActions.setDefaultPlayerMode,
    'selectPlayer': s._sections.macActions.selectPlayer,
    'browseForCustomApp': s._sections.macActions.browseForCustomApp,
    'clearCustomApp': s._sections.macActions.clearCustomApp,
    'saveCustomCommand': s._sections.macActions.saveCustomCommand,
    'clearCustomCommand': s._sections.macActions.clearCustomCommand,
    'selectIOSPlayer': s._sections.iosActions.selectIOSPlayer,
    'saveIOSCustomScheme': s._sections.iosActions.saveIOSCustomScheme,
    'clearIOSCustomScheme': s._sections.iosActions.clearIOSCustomScheme,
    'selectLinuxPlayer': s._sections.linuxActions.selectLinuxPlayer,
    'saveLinuxCustomCommand': s._sections.linuxActions.saveLinuxCustomCommand,
    'clearLinuxCustomCommand': s._sections.linuxActions.clearLinuxCustomCommand,
    'selectWindowsPlayer': s._sections.windowsActions.selectWindowsPlayer,
    'saveWindowsCustomCommand':
        s._sections.windowsActions.saveWindowsCustomCommand,
    'clearWindowsCustomCommand':
        s._sections.windowsActions.clearWindowsCustomCommand,
    'setVrDefaultScreenType': s._sections.vrSetters.setVrDefaultScreenType,
    'setVrDefaultStereoMode': s._sections.vrSetters.setVrDefaultStereoMode,
    'setVrAutoDetectFormat': s._sections.vrSetters.setVrAutoDetectFormat,
    'setVrShowDialog': s._sections.vrSetters.setVrShowDialog,
    'setDefaultAspectIndex': s._sections.playerSetters.setDefaultAspectIndex,
    'setNightModeIndex': s._sections.playerSetters.setNightModeIndex,
    'setSystemAudioEffects': s._sections.playerSetters.setSystemAudioEffects,
    'setTvosForceSoftwareDecode':
        s._sections.playerSetters.setTvosForceSoftwareDecode,
    'setTvosForceStereo': s._sections.playerSetters.setTvosForceStereo,
    'setTvosLegacyAudioOutput':
        s._sections.playerSetters.setTvosLegacyAudioOutput,
    'setAudioPassthrough': s._sections.playerSetters.setAudioPassthrough,
    'setAppleMultichannel': s._sections.playerSetters.setAppleMultichannel,
    'setAndroidVideoRendererMode':
        s._sections.playerSetters.setAndroidVideoRendererMode,
    'setContentDisplayMatchMode':
        s._sections.playerSetters.setContentDisplayMatchMode,
    'setIptvDecoderMode': s._sections.playerSetters.setIptvDecoderMode,
    'setStartPortrait': s._sections.playerSetters.setStartPortrait,
    'setSubtitleOnlyForeignAudio':
        s._sections.subtitleSetters.setSubtitleOnlyForeignAudio,
    'setSubtitleForcedOnly': s._sections.subtitleSetters.setSubtitleForcedOnly,
    'setSubtitleAutoSync': s._sections.subtitleSetters.setSubtitleAutoSync,
    'completionThresholdOptions':
        s._sections.playerSetters.completionThresholdOptions,
    'completionThresholdIndex':
        s._sections.playerSetters.completionThresholdIndex,
    'setMovieCompletionThresholdIndex':
        s._sections.playerSetters.setMovieCompletionThresholdIndex,
    'setEpisodeCompletionThresholdIndex':
        s._sections.playerSetters.setEpisodeCompletionThresholdIndex,
    'setSkipSegmentsEnabled': s._sections.playerSetters.setSkipSegmentsEnabled,
    'setSkipSegmentProvider': s._sections.playerSetters.setSkipSegmentProvider,
    'setNetPatience': s._sections.playerSetters.setNetPatience,
    'setNetBuffer': s._sections.playerSetters.setNetBuffer,
    'setDefaultSubtitleLanguage':
        s._sections.subtitleSetters.setDefaultSubtitleLanguage,
    'setDefaultAudioLanguage':
        s._sections.subtitleSetters.setDefaultAudioLanguage,
    'setSubtitleSizeIndex': s._sections.subtitleSetters.setSubtitleSizeIndex,
    'setSubtitleStyleIndex': s._sections.subtitleSetters.setSubtitleStyleIndex,
    'setSubtitleColorIndex': s._sections.subtitleSetters.setSubtitleColorIndex,
    'setSubtitleBgIndex': s._sections.subtitleSetters.setSubtitleBgIndex,
    'setSubtitleFontIndex': s._sections.subtitleSetters.setSubtitleFontIndex,
    'setSubtitleBold': s._sections.subtitleSetters.setSubtitleBold,
    'loadFonts': s._sections.fontActions.loadFonts,
    'importCustomFont': s._sections.fontActions.importCustomFont,
    'removeCustomFont': s._sections.fontActions.removeCustomFont,
    'aspectLabels': s._sections.videoSection.aspectLabels,
    'subtitleLanguageIndex': s._sections.subtitleSection.subtitleLanguageIndex,
    'audioLanguageIndex': s._sections.audioSection.audioLanguageIndex,
    'openPlayerSettings': s._openPlayerSettings,
  };
}
