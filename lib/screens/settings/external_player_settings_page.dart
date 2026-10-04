import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_sections.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_settings_test_access.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_vr_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_windows_state.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/analytics_service.dart';
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
    openPlayerSettings: _openPlayerSettings,
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
  Widget build(BuildContext context) => _sections.layout.build(context);
}

@visibleForTesting
Map<String, Object?> playbackSettingsTestAccess(
  State<ExternalPlayerSettingsPage> state,
) => playbackTestAccess((state as _ExternalPlayerSettingsPageState)._sections);
