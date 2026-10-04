# Playback settings dependencies

Original: format-only `6c8a641f`. Public widget stays unchanged.

All sections are plain legacy presentation bridges. State context and
mounted are live callbacks; parameter/builder contexts remain lexical.
The three generic row builders use only parameters, Theme and AppThemeScope.
No Riverpod, data contract, platform adapter or behavior change is introduced.

## Frozen owners

- `PlaybackCoreState` / `_core` (4 fields): `_loading`, `_contentFocusNode`, `_defaultPlayerMode`, `_firstModeFocusNode`
- `PlaybackMacState` / `_mac` (9 fields): `_selectedPlayer`, `_installedPlayers`, `_customAppPath`, `_customAppName`, `_customCommand`, `_commandController`, `_commandFocusNode`, `_commandFocused`, `_commandError`
- `PlaybackIosState` / `_ios` (7 fields): `_selectedIOSPlayer`, `_installedIOSPlayers`, `_iosCustomScheme`, `_iosSchemeController`, `_iosSchemeFocusNode`, `_iosSchemeFocused`, `_iosSchemeError`
- `PlaybackLinuxState` / `_linux` (7 fields): `_selectedLinuxPlayer`, `_installedLinuxPlayers`, `_linuxCustomCommand`, `_linuxCommandController`, `_linuxCommandFocusNode`, `_linuxCommandFocused`, `_linuxCommandError`
- `PlaybackWindowsState` / `_win` (7 fields): `_selectedWindowsPlayer`, `_installedWindowsPlayers`, `_windowsCustomCommand`, `_windowsCommandController`, `_windowsCommandFocusNode`, `_windowsCommandFocused`, `_windowsCommandError`
- `PlaybackVrState` / `_vr` (12 fields): `_vrDefaultScreenType`, `_vrDefaultStereoMode`, `_vrAutoDetectFormat`, `_vrShowDialog`, `_screenTypeFocusNode`, `_stereoModeFocusNode`, `_autoDetectFocusNode`, `_showDialogFocusNode`, `_screenTypeFocused`, `_stereoModeFocused`, `_autoDetectFocused`, `_showDialogFocused`
- `PlaybackValuesState` / `_values` (19 fields): `_isAndroidTv`, `_defaultAspectIndex`, `_nightModeIndex`, `_systemAudioEffects`, `_tvosForceSoftwareDecode`, `_audioPassthrough`, `_appleMultichannel`, `_tvosForceStereo`, `_tvosLegacyAudioOutput`, `_androidVideoRendererMode`, `_contentDisplayMatchMode`, `_startPortrait`, `_movieCompletionThreshold`, `_episodeCompletionThreshold`, `_skipSegmentsEnabled`, `_skipSegmentProvider`, `_netPatience`, `_netBuffer`, `_iptvDecoderMode`
- `PlaybackSubtitleState` / `_sub` (12 fields): `_subtitleOnlyForeignAudio`, `_subtitleForcedOnly`, `_subtitleAutoSync`, `_defaultSubtitleLanguage`, `_defaultAudioLanguage`, `_subtitleSizeIndex`, `_subtitleStyleIndex`, `_subtitleColorIndex`, `_subtitleBgIndex`, `_subtitleFontIndex`, `_subtitleBold`, `_allFonts`
- `PlaybackRowsState` / `_rows` (28 fields): `_aspectFocusNode`, `_aspectFocused`, `_contentDisplayMatchFocusNode`, `_contentDisplayMatchFocused`, `_iptvDecoderFocusNode`, `_iptvDecoderFocused`, `_androidVideoRendererFocusNode`, `_androidVideoRendererFocused`, `_tvosForceSwDecodeFocusNode`, `_tvosForceSwDecodeFocused`, `_defaultAudioLangFocusNode`, `_defaultAudioLangFocused`, `_systemAudioEffectsFocusNode`, `_systemAudioEffectsFocused`, `_audioPassthroughFocusNode`, `_audioPassthroughFocused`, `_appleMultichannelFocusNode`, `_appleMultichannelFocused`, `_tvosForceStereoFocusNode`, `_tvosForceStereoFocused`, `_tvosLegacyAudioFocusNode`, `_tvosLegacyAudioFocused`, `_startPortraitFocusNode`, `_startPortraitFocused`, `_netPatienceFocusNode`, `_netPatienceFocused`, `_netBufferFocusNode`, `_netBufferFocused`
- `PlaybackSubtitleRowsState` / `_subRows` (28 fields): `_defaultSubtitleLangFocusNode`, `_defaultSubtitleLangFocused`, `_subtitleOnlyForeignAudioFocusNode`, `_subtitleOnlyForeignAudioFocused`, `_subtitleForcedOnlyFocusNode`, `_subtitleForcedOnlyFocused`, `_subtitleAutoSyncFocusNode`, `_subtitleAutoSyncFocused`, `_subtitleSizeFocusNode`, `_subtitleSizeFocused`, `_subtitleStyleFocusNode`, `_subtitleStyleFocused`, `_subtitleColorFocusNode`, `_subtitleColorFocused`, `_subtitleBgFocusNode`, `_subtitleBgFocused`, `_subtitleFontFocusNode`, `_subtitleFontFocused`, `_subtitleBoldFocusNode`, `_subtitleBoldFocused`, `_movieCompletionThresholdFocusNode`, `_movieCompletionThresholdFocused`, `_episodeCompletionThresholdFocusNode`, `_episodeCompletionThresholdFocused`, `_skipSegmentsEnabledFocusNode`, `_skipSegmentsEnabledFocused`, `_skipSegmentProviderFocusNode`, `_skipSegmentProviderFocused`

## Per-entry wiring checklist

For each row, review actual bindings before scaffold pinning: same owners,
parameter types/defaults/named arguments, direct callback member and receiver,
live context/mounted/section, lexical contexts, no construction-time action.

| Original leaf | Step / destination | Reads | Writes | Calls / tear-offs | Context |
| --- | --- | --- | --- | --- | --- |
| `ExternalPlayerSettingsPage` | 0 / `external_player_settings_page.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._loading` | 2 / `playback_core_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._contentFocusNode` | 2 / `playback_core_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._defaultPlayerMode` | 2 / `playback_core_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._selectedPlayer` | 2 / `playback_mac_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._installedPlayers` | 2 / `playback_mac_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._customAppPath` | 2 / `playback_mac_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._customAppName` | 2 / `playback_mac_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._customCommand` | 2 / `playback_mac_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._commandController` | 2 / `playback_mac_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._commandFocusNode` | 2 / `playback_mac_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._commandFocused` | 2 / `playback_mac_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._commandError` | 2 / `playback_mac_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._selectedIOSPlayer` | 2 / `playback_ios_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._installedIOSPlayers` | 2 / `playback_ios_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._iosCustomScheme` | 2 / `playback_ios_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._iosSchemeController` | 2 / `playback_ios_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._iosSchemeFocusNode` | 2 / `playback_ios_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._iosSchemeFocused` | 2 / `playback_ios_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._iosSchemeError` | 2 / `playback_ios_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._selectedLinuxPlayer` | 2 / `playback_linux_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._installedLinuxPlayers` | 2 / `playback_linux_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._linuxCustomCommand` | 2 / `playback_linux_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._linuxCommandController` | 2 / `playback_linux_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._linuxCommandFocusNode` | 2 / `playback_linux_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._linuxCommandFocused` | 2 / `playback_linux_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._linuxCommandError` | 2 / `playback_linux_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._selectedWindowsPlayer` | 2 / `playback_windows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._installedWindowsPlayers` | 2 / `playback_windows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._windowsCustomCommand` | 2 / `playback_windows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._windowsCommandController` | 2 / `playback_windows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._windowsCommandFocusNode` | 2 / `playback_windows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._windowsCommandFocused` | 2 / `playback_windows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._windowsCommandError` | 2 / `playback_windows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._vrDefaultScreenType` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._vrDefaultStereoMode` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._vrAutoDetectFormat` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._vrShowDialog` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._isAndroidTv` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._defaultAspectIndex` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._nightModeIndex` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._systemAudioEffects` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._tvosForceSoftwareDecode` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._audioPassthrough` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._appleMultichannel` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._tvosForceStereo` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._tvosLegacyAudioOutput` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._androidVideoRendererMode` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._contentDisplayMatchMode` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._startPortrait` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleOnlyForeignAudio` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleForcedOnly` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleAutoSync` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._movieCompletionThreshold` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._episodeCompletionThreshold` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._skipSegmentsEnabled` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._skipSegmentProvider` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._netPatience` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._netBuffer` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._defaultSubtitleLanguage` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._defaultAudioLanguage` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleSizeIndex` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleStyleIndex` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleColorIndex` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleBgIndex` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleFontIndex` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleBold` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._allFonts` | 2 / `playback_subtitle_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._firstModeFocusNode` | 2 / `playback_core_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._aspectFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._defaultAudioLangFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._defaultSubtitleLangFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._systemAudioEffectsFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._tvosForceSwDecodeFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._audioPassthroughFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._appleMultichannelFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._tvosForceStereoFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._tvosLegacyAudioFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._androidVideoRendererFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._contentDisplayMatchFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._iptvDecoderFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._startPortraitFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleOnlyForeignAudioFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleForcedOnlyFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleAutoSyncFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._movieCompletionThresholdFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._episodeCompletionThresholdFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._skipSegmentsEnabledFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._skipSegmentProviderFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleSizeFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleStyleFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleColorFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleBgFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleFontFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleBoldFocusNode` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._netPatienceFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._netBufferFocusNode` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._aspectFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._defaultAudioLangFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._defaultSubtitleLangFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._systemAudioEffectsFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._tvosForceSwDecodeFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._audioPassthroughFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._appleMultichannelFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._tvosForceStereoFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._tvosLegacyAudioFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._androidVideoRendererFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._contentDisplayMatchFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._iptvDecoderFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._iptvDecoderMode` | 2 / `playback_values_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._startPortraitFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleOnlyForeignAudioFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleForcedOnlyFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleAutoSyncFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._movieCompletionThresholdFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._episodeCompletionThresholdFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._skipSegmentsEnabledFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._skipSegmentProviderFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleSizeFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleStyleFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleColorFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleBgFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleFontFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleBoldFocused` | 2 / `playback_subtitle_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._netPatienceFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._netBufferFocused` | 2 / `playback_rows_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._screenTypeFocusNode` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._stereoModeFocusNode` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._autoDetectFocusNode` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._showDialogFocusNode` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._screenTypeFocused` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._stereoModeFocused` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._autoDetectFocused` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._showDialogFocused` | 2 / `playback_vr_state.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState.initState` | 0 / `external_player_settings_page.dart` | _androidVideoRendererFocusNode, _appleMultichannelFocusNode, _aspectFocusNode, _audioPassthroughFocusNode, _autoDetectFocusNode, _commandFocusNode, _contentDisplayMatchFocusNode, _defaultAudioLangFocusNode, _defaultSubtitleLangFocusNode, _episodeCompletionThresholdFocusNode, _iosSchemeFocusNode, _iptvDecoderFocusNode, _linuxCommandFocusNode, _movieCompletionThresholdFocusNode, _netBufferFocusNode, _netPatienceFocusNode, _screenTypeFocusNode, _showDialogFocusNode, _skipSegmentProviderFocusNode, _skipSegmentsEnabledFocusNode, _startPortraitFocusNode, _stereoModeFocusNode, _subtitleAutoSyncFocusNode, _subtitleBgFocusNode, _subtitleBoldFocusNode, _subtitleColorFocusNode, _subtitleFontFocusNode, _subtitleForcedOnlyFocusNode, _subtitleOnlyForeignAudioFocusNode, _subtitleSizeFocusNode, _subtitleStyleFocusNode, _systemAudioEffectsFocusNode, _tvosForceStereoFocusNode, _tvosForceSwDecodeFocusNode, _tvosLegacyAudioFocusNode, _windowsCommandFocusNode | _androidVideoRendererFocused, _appleMultichannelFocused, _aspectFocused, _audioPassthroughFocused, _autoDetectFocused, _commandFocused, _contentDisplayMatchFocused, _defaultAudioLangFocused, _defaultSubtitleLangFocused, _episodeCompletionThresholdFocused, _iosSchemeFocused, _iptvDecoderFocused, _linuxCommandFocused, _movieCompletionThresholdFocused, _netBufferFocused, _netPatienceFocused, _screenTypeFocused, _showDialogFocused, _skipSegmentProviderFocused, _skipSegmentsEnabledFocused, _startPortraitFocused, _stereoModeFocused, _subtitleAutoSyncFocused, _subtitleBgFocused, _subtitleBoldFocused, _subtitleColorFocused, _subtitleFontFocused, _subtitleForcedOnlyFocused, _subtitleOnlyForeignAudioFocused, _subtitleSizeFocused, _subtitleStyleFocused, _systemAudioEffectsFocused, _tvosForceStereoFocused, _tvosForceSwDecodeFocused, _tvosLegacyAudioFocused, _windowsCommandFocused | _loadSettings | — |
| `_ExternalPlayerSettingsPageState.dispose` | 0 / `external_player_settings_page.dart` | _androidVideoRendererFocusNode, _appleMultichannelFocusNode, _aspectFocusNode, _audioPassthroughFocusNode, _autoDetectFocusNode, _commandController, _commandFocusNode, _contentDisplayMatchFocusNode, _contentFocusNode, _defaultAudioLangFocusNode, _defaultSubtitleLangFocusNode, _episodeCompletionThresholdFocusNode, _firstModeFocusNode, _iosSchemeController, _iosSchemeFocusNode, _iptvDecoderFocusNode, _linuxCommandController, _linuxCommandFocusNode, _movieCompletionThresholdFocusNode, _netBufferFocusNode, _netPatienceFocusNode, _screenTypeFocusNode, _showDialogFocusNode, _skipSegmentProviderFocusNode, _skipSegmentsEnabledFocusNode, _startPortraitFocusNode, _stereoModeFocusNode, _subtitleAutoSyncFocusNode, _subtitleBgFocusNode, _subtitleBoldFocusNode, _subtitleColorFocusNode, _subtitleFontFocusNode, _subtitleForcedOnlyFocusNode, _subtitleOnlyForeignAudioFocusNode, _subtitleSizeFocusNode, _subtitleStyleFocusNode, _systemAudioEffectsFocusNode, _tvosForceStereoFocusNode, _tvosForceSwDecodeFocusNode, _tvosLegacyAudioFocusNode, _windowsCommandController, _windowsCommandFocusNode | — | — | — |
| `_ExternalPlayerSettingsPageState._loadSettings` | 3 / `playback_settings_load.dart` | _commandController, _contentFocusNode, _iosSchemeController, _linuxCommandController, _windowsCommandController | _androidVideoRendererMode, _appleMultichannel, _audioPassthrough, _contentDisplayMatchMode, _customAppName, _customAppPath, _customCommand, _defaultAspectIndex, _defaultAudioLanguage, _defaultPlayerMode, _defaultSubtitleLanguage, _episodeCompletionThreshold, _installedIOSPlayers, _installedLinuxPlayers, _installedPlayers, _installedWindowsPlayers, _iosCustomScheme, _iptvDecoderMode, _isAndroidTv, _linuxCustomCommand, _loading, _movieCompletionThreshold, _netBuffer, _netPatience, _nightModeIndex, _selectedIOSPlayer, _selectedLinuxPlayer, _selectedPlayer, _selectedWindowsPlayer, _skipSegmentProvider, _skipSegmentsEnabled, _startPortrait, _subtitleAutoSync, _subtitleBgIndex, _subtitleBold, _subtitleColorIndex, _subtitleFontIndex, _subtitleForcedOnly, _subtitleOnlyForeignAudio, _subtitleSizeIndex, _subtitleStyleIndex, _systemAudioEffects, _tvosForceSoftwareDecode, _tvosForceStereo, _tvosLegacyAudioOutput, _vrAutoDetectFormat, _vrDefaultScreenType, _vrDefaultStereoMode, _vrShowDialog, _windowsCustomCommand | _loadFonts | live State |
| `_ExternalPlayerSettingsPageState._setDefaultPlayerMode` | 3 / `playback_player_mode_actions.dart` | — | _defaultPlayerMode | — | live State |
| `_ExternalPlayerSettingsPageState._selectPlayer` | 3 / `playback_mac_actions.dart` | — | _selectedPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._browseForCustomApp` | 3 / `playback_mac_actions.dart` | — | _customAppName, _customAppPath, _selectedPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._clearCustomApp` | 3 / `playback_mac_actions.dart` | _selectedPlayer | _customAppName, _customAppPath, _selectedPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._saveCustomCommand` | 3 / `playback_mac_actions.dart` | _commandController | _commandError, _customCommand, _selectedPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._clearCustomCommand` | 3 / `playback_mac_actions.dart` | _commandController, _selectedPlayer | _commandError, _customCommand, _selectedPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._selectIOSPlayer` | 3 / `playback_ios_actions.dart` | — | _selectedIOSPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._saveIOSCustomScheme` | 3 / `playback_ios_actions.dart` | _iosSchemeController | _iosCustomScheme, _iosSchemeError, _selectedIOSPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._clearIOSCustomScheme` | 3 / `playback_ios_actions.dart` | _iosSchemeController, _selectedIOSPlayer | _iosCustomScheme, _iosSchemeError, _selectedIOSPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._selectLinuxPlayer` | 3 / `playback_linux_actions.dart` | — | _selectedLinuxPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._saveLinuxCustomCommand` | 3 / `playback_linux_actions.dart` | _linuxCommandController | _linuxCommandError, _linuxCustomCommand, _selectedLinuxPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._clearLinuxCustomCommand` | 3 / `playback_linux_actions.dart` | _linuxCommandController, _selectedLinuxPlayer | _linuxCommandError, _linuxCustomCommand, _selectedLinuxPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._selectWindowsPlayer` | 3 / `playback_windows_actions.dart` | — | _selectedWindowsPlayer | — | live State |
| `_ExternalPlayerSettingsPageState._saveWindowsCustomCommand` | 3 / `playback_windows_actions.dart` | _windowsCommandController | _selectedWindowsPlayer, _windowsCommandError, _windowsCustomCommand | — | live State |
| `_ExternalPlayerSettingsPageState._clearWindowsCustomCommand` | 3 / `playback_windows_actions.dart` | _selectedWindowsPlayer, _windowsCommandController | _selectedWindowsPlayer, _windowsCommandError, _windowsCustomCommand | — | live State |
| `_ExternalPlayerSettingsPageState._setVrDefaultScreenType` | 4 / `playback_vr_setters.dart` | — | _vrDefaultScreenType | — | — |
| `_ExternalPlayerSettingsPageState._setVrDefaultStereoMode` | 4 / `playback_vr_setters.dart` | — | _vrDefaultStereoMode | — | — |
| `_ExternalPlayerSettingsPageState._setVrAutoDetectFormat` | 4 / `playback_vr_setters.dart` | — | _vrAutoDetectFormat | — | — |
| `_ExternalPlayerSettingsPageState._setVrShowDialog` | 4 / `playback_vr_setters.dart` | — | _vrShowDialog | — | — |
| `_ExternalPlayerSettingsPageState._setDefaultAspectIndex` | 4 / `playback_player_setters.dart` | _isAndroidTv | _defaultAspectIndex | — | — |
| `_ExternalPlayerSettingsPageState._setNightModeIndex` | 4 / `playback_player_setters.dart` | — | _nightModeIndex | — | — |
| `_ExternalPlayerSettingsPageState._setSystemAudioEffects` | 4 / `playback_player_setters.dart` | — | _systemAudioEffects | — | — |
| `_ExternalPlayerSettingsPageState._setTvosForceSoftwareDecode` | 4 / `playback_player_setters.dart` | — | _tvosForceSoftwareDecode | — | — |
| `_ExternalPlayerSettingsPageState._setTvosForceStereo` | 4 / `playback_player_setters.dart` | — | _tvosForceStereo | — | — |
| `_ExternalPlayerSettingsPageState._setTvosLegacyAudioOutput` | 4 / `playback_player_setters.dart` | — | _tvosLegacyAudioOutput | — | — |
| `_ExternalPlayerSettingsPageState._setAudioPassthrough` | 4 / `playback_player_setters.dart` | — | _audioPassthrough | — | — |
| `_ExternalPlayerSettingsPageState._setAppleMultichannel` | 4 / `playback_player_setters.dart` | — | _appleMultichannel | — | — |
| `_ExternalPlayerSettingsPageState._setAndroidVideoRendererMode` | 4 / `playback_player_setters.dart` | — | _androidVideoRendererMode | — | — |
| `_ExternalPlayerSettingsPageState._setContentDisplayMatchMode` | 4 / `playback_player_setters.dart` | — | _contentDisplayMatchMode | — | — |
| `_ExternalPlayerSettingsPageState._setIptvDecoderMode` | 4 / `playback_player_setters.dart` | — | _iptvDecoderMode | — | — |
| `_ExternalPlayerSettingsPageState._setStartPortrait` | 4 / `playback_player_setters.dart` | — | _startPortrait | — | — |
| `_ExternalPlayerSettingsPageState._setSubtitleOnlyForeignAudio` | 4 / `playback_subtitle_setters.dart` | — | _subtitleOnlyForeignAudio | — | — |
| `_ExternalPlayerSettingsPageState._setSubtitleForcedOnly` | 4 / `playback_subtitle_setters.dart` | — | _subtitleForcedOnly | — | — |
| `_ExternalPlayerSettingsPageState._setSubtitleAutoSync` | 4 / `playback_subtitle_setters.dart` | — | _subtitleAutoSync | — | — |
| `_ExternalPlayerSettingsPageState._completionThresholdOptions` | 4 / `playback_player_setters.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._completionThresholdIndex` | 4 / `playback_player_setters.dart` | _completionThresholdOptions | — | — | — |
| `_ExternalPlayerSettingsPageState._setMovieCompletionThresholdIndex` | 4 / `playback_player_setters.dart` | _completionThresholdOptions | _movieCompletionThreshold | — | — |
| `_ExternalPlayerSettingsPageState._setEpisodeCompletionThresholdIndex` | 4 / `playback_player_setters.dart` | _completionThresholdOptions | _episodeCompletionThreshold | — | — |
| `_ExternalPlayerSettingsPageState._setSkipSegmentsEnabled` | 4 / `playback_player_setters.dart` | — | _skipSegmentsEnabled | — | — |
| `_ExternalPlayerSettingsPageState._setSkipSegmentProvider` | 4 / `playback_player_setters.dart` | — | _skipSegmentProvider | — | — |
| `_ExternalPlayerSettingsPageState._setNetPatience` | 4 / `playback_player_setters.dart` | — | _netPatience | — | — |
| `_ExternalPlayerSettingsPageState._setNetBuffer` | 4 / `playback_player_setters.dart` | — | _netBuffer | — | — |
| `_ExternalPlayerSettingsPageState._setDefaultSubtitleLanguage` | 4 / `playback_subtitle_setters.dart` | — | _defaultSubtitleLanguage | — | — |
| `_ExternalPlayerSettingsPageState._setDefaultAudioLanguage` | 4 / `playback_subtitle_setters.dart` | — | _defaultAudioLanguage | — | — |
| `_ExternalPlayerSettingsPageState._setSubtitleSizeIndex` | 4 / `playback_subtitle_setters.dart` | — | _subtitleSizeIndex | — | — |
| `_ExternalPlayerSettingsPageState._setSubtitleStyleIndex` | 4 / `playback_subtitle_setters.dart` | — | _subtitleStyleIndex | — | — |
| `_ExternalPlayerSettingsPageState._setSubtitleColorIndex` | 4 / `playback_subtitle_setters.dart` | — | _subtitleColorIndex | — | — |
| `_ExternalPlayerSettingsPageState._setSubtitleBgIndex` | 4 / `playback_subtitle_setters.dart` | — | _subtitleBgIndex | — | — |
| `_ExternalPlayerSettingsPageState._setSubtitleFontIndex` | 4 / `playback_subtitle_setters.dart` | — | _subtitleFontIndex | — | — |
| `_ExternalPlayerSettingsPageState._setSubtitleBold` | 4 / `playback_subtitle_setters.dart` | — | _subtitleBold | — | — |
| `_ExternalPlayerSettingsPageState._loadFonts` | 4 / `playback_font_actions.dart` | — | _allFonts, _subtitleFontIndex | — | — |
| `_ExternalPlayerSettingsPageState._importCustomFont` | 4 / `playback_font_actions.dart` | — | — | _loadFonts | live State |
| `_ExternalPlayerSettingsPageState._removeCustomFont` | 4 / `playback_font_actions.dart` | — | — | _loadFonts | live State |
| `_ExternalPlayerSettingsPageState._aspectLabels` | 4 / `playback_video_section.dart` | _isAndroidTv | — | — | — |
| `_ExternalPlayerSettingsPageState._nightModeLabels` | 4 / `playback_night_mode_section.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleLanguageOptions` | 4 / `playback_subtitle_section.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._subtitleLanguageIndex` | 4 / `playback_subtitle_section.dart` | _defaultSubtitleLanguage, _subtitleLanguageOptions | — | — | — |
| `_ExternalPlayerSettingsPageState._audioLanguageOptions` | 4 / `playback_audio_section.dart` | — | — | — | — |
| `_ExternalPlayerSettingsPageState._audioLanguageIndex` | 4 / `playback_audio_section.dart` | _audioLanguageOptions, _defaultAudioLanguage | — | — | — |
| `_ExternalPlayerSettingsPageState._buildPlayerTile` | 5 / `playback_player_tiles.dart` | _customAppName, _customAppPath, _customCommand, _installedPlayers, _selectedPlayer | — | _selectPlayer | live State |
| `_ExternalPlayerSettingsPageState._buildIOSPlayerTile` | 5 / `playback_player_tiles.dart` | _installedIOSPlayers, _iosCustomScheme, _selectedIOSPlayer | — | _selectIOSPlayer | live State |
| `_ExternalPlayerSettingsPageState._buildLinuxPlayerTile` | 5 / `playback_player_tiles.dart` | _installedLinuxPlayers, _linuxCustomCommand, _selectedLinuxPlayer | — | _selectLinuxPlayer | live State |
| `_ExternalPlayerSettingsPageState._buildWindowsPlayerTile` | 5 / `playback_player_tiles.dart` | _installedWindowsPlayers, _selectedWindowsPlayer, _windowsCustomCommand | — | _selectWindowsPlayer | live State |
| `_ExternalPlayerSettingsPageState._buildPlayerModeOption` | 5 / `playback_player_mode_option.dart` | _defaultPlayerMode | — | _setDefaultPlayerMode | parameter / lexical |
| `_ExternalPlayerSettingsPageState._buildDropdownSetting` | 1 / `playback_dropdown_setting.dart` | — | — | — | parameter / lexical |
| `_ExternalPlayerSettingsPageState._buildCheckboxTile` | 1 / `playback_checkbox_tile.dart` | — | — | — | parameter / lexical |
| `_ExternalPlayerSettingsPageState._buildSettingDropdown` | 1 / `playback_setting_dropdown.dart` | — | — | — | parameter / lexical |
| `_ExternalPlayerSettingsPageState._defaultsCard` | 5 / `playback_defaults_card.dart` | — | — | — | live State |
| `_ExternalPlayerSettingsPageState._openPlayerSettings` | 0 / `external_player_settings_page.dart` | — | — | _loadSettings | live State |
| `_ExternalPlayerSettingsPageState._playerAppearance` | 5 / `playback_player_appearance.dart` | _isAndroidTv | — | — | live State |
| `_ExternalPlayerSettingsPageState._playerSettings` | 5 / `playback_player_section.dart` | _completionThresholdOptions, _defaultPlayerMode, _episodeCompletionThreshold, _episodeCompletionThresholdFocusNode, _episodeCompletionThresholdFocused, _firstModeFocusNode, _movieCompletionThreshold, _movieCompletionThresholdFocusNode, _movieCompletionThresholdFocused, _netBuffer, _netBufferFocusNode, _netBufferFocused, _netPatience, _netPatienceFocusNode, _netPatienceFocused, _setEpisodeCompletionThresholdIndex, _setMovieCompletionThresholdIndex, _setNetBuffer, _setNetPatience, _setSkipSegmentProvider, _setSkipSegmentsEnabled, _setStartPortrait, _skipSegmentProvider, _skipSegmentProviderFocusNode, _skipSegmentProviderFocused, _skipSegmentsEnabled, _skipSegmentsEnabledFocusNode, _skipSegmentsEnabledFocused, _startPortrait, _startPortraitFocusNode, _startPortraitFocused | — | _buildCheckboxTile, _buildDropdownSetting, _buildPlayerModeOption, _buildSettingDropdown, _completionThresholdIndex, _defaultsCard, _externalPlayerSettings, _playerAppearance | live State |
| `_ExternalPlayerSettingsPageState._videoSettings` | 5 / `playback_video_section.dart` | _androidVideoRendererFocusNode, _androidVideoRendererFocused, _androidVideoRendererMode, _aspectFocusNode, _aspectFocused, _aspectLabels, _contentDisplayMatchFocusNode, _contentDisplayMatchFocused, _contentDisplayMatchMode, _defaultAspectIndex, _iptvDecoderFocusNode, _iptvDecoderFocused, _iptvDecoderMode, _isAndroidTv, _setAndroidVideoRendererMode, _setContentDisplayMatchMode, _setIptvDecoderMode, _setTvosForceSoftwareDecode, _tvosForceSoftwareDecode, _tvosForceSwDecodeFocusNode, _tvosForceSwDecodeFocused | — | _buildCheckboxTile, _buildDropdownSetting, _buildSettingDropdown, _defaultsCard, _setDefaultAspectIndex | live State |
| `_ExternalPlayerSettingsPageState._audioSettings` | 5 / `playback_audio_section.dart` | _appleMultichannel, _appleMultichannelFocusNode, _appleMultichannelFocused, _audioLanguageIndex, _audioLanguageOptions, _audioPassthrough, _audioPassthroughFocusNode, _audioPassthroughFocused, _defaultAudioLangFocusNode, _defaultAudioLangFocused, _setAppleMultichannel, _setAudioPassthrough, _setSystemAudioEffects, _setTvosForceStereo, _setTvosLegacyAudioOutput, _systemAudioEffects, _systemAudioEffectsFocusNode, _systemAudioEffectsFocused, _tvosForceStereo, _tvosForceStereoFocusNode, _tvosForceStereoFocused, _tvosLegacyAudioFocusNode, _tvosLegacyAudioFocused, _tvosLegacyAudioOutput | — | _buildCheckboxTile, _buildSettingDropdown, _defaultsCard, _nightModeSettings, _setDefaultAudioLanguage | live State |
| `_ExternalPlayerSettingsPageState._nightModeSettings` | 5 / `playback_night_mode_section.dart` | _isAndroidTv, _nightModeIndex, _nightModeLabels | — | _setNightModeIndex | live State |
| `_ExternalPlayerSettingsPageState._subtitleSettings` | 5 / `playback_subtitle_section.dart` | _allFonts, _defaultSubtitleLangFocusNode, _defaultSubtitleLangFocused, _importCustomFont, _setSubtitleAutoSync, _setSubtitleForcedOnly, _setSubtitleOnlyForeignAudio, _subtitleAutoSync, _subtitleAutoSyncFocusNode, _subtitleAutoSyncFocused, _subtitleBgFocusNode, _subtitleBgFocused, _subtitleBgIndex, _subtitleBold, _subtitleBoldFocusNode, _subtitleBoldFocused, _subtitleColorFocusNode, _subtitleColorFocused, _subtitleColorIndex, _subtitleFontFocusNode, _subtitleFontFocused, _subtitleFontIndex, _subtitleForcedOnly, _subtitleForcedOnlyFocusNode, _subtitleForcedOnlyFocused, _subtitleLanguageIndex, _subtitleLanguageOptions, _subtitleOnlyForeignAudio, _subtitleOnlyForeignAudioFocusNode, _subtitleOnlyForeignAudioFocused, _subtitleSizeFocusNode, _subtitleSizeFocused, _subtitleSizeIndex, _subtitleStyleFocusNode, _subtitleStyleFocused, _subtitleStyleIndex | — | _buildCheckboxTile, _buildSettingDropdown, _defaultsCard, _removeCustomFont, _setDefaultSubtitleLanguage, _setSubtitleBgIndex, _setSubtitleBold, _setSubtitleColorIndex, _setSubtitleFontIndex, _setSubtitleSizeIndex, _setSubtitleStyleIndex | live State |
| `_ExternalPlayerSettingsPageState._externalPlayerSettings` | 5 / `playback_external_section.dart` | _autoDetectFocusNode, _autoDetectFocused, _browseForCustomApp, _clearCustomApp, _clearCustomCommand, _clearIOSCustomScheme, _clearLinuxCustomCommand, _clearWindowsCustomCommand, _commandController, _commandError, _commandFocusNode, _commandFocused, _customAppName, _customAppPath, _customCommand, _defaultPlayerMode, _iosCustomScheme, _iosSchemeController, _iosSchemeError, _iosSchemeFocusNode, _iosSchemeFocused, _linuxCommandController, _linuxCommandError, _linuxCommandFocusNode, _linuxCommandFocused, _linuxCustomCommand, _saveCustomCommand, _saveIOSCustomScheme, _saveLinuxCustomCommand, _saveWindowsCustomCommand, _screenTypeFocusNode, _screenTypeFocused, _selectedIOSPlayer, _selectedLinuxPlayer, _selectedPlayer, _selectedWindowsPlayer, _setVrAutoDetectFormat, _setVrDefaultScreenType, _setVrDefaultStereoMode, _setVrShowDialog, _showDialogFocusNode, _showDialogFocused, _stereoModeFocusNode, _stereoModeFocused, _vrAutoDetectFormat, _vrDefaultScreenType, _vrDefaultStereoMode, _vrShowDialog, _windowsCommandController, _windowsCommandError, _windowsCommandFocusNode, _windowsCommandFocused, _windowsCustomCommand | _commandError, _iosSchemeError, _linuxCommandError, _windowsCommandError | _buildCheckboxTile, _buildDropdownSetting, _buildIOSPlayerTile, _buildLinuxPlayerTile, _buildPlayerTile, _buildWindowsPlayerTile | live State |
| `_ExternalPlayerSettingsPageState.build` | 6 / `playback_settings_layout.dart` | _contentFocusNode, _defaultPlayerMode, _loading | — | _audioSettings, _playerSettings, _subtitleSettings, _videoSettings | — |

## Static and helper ownership

- `_nightModeLabels` stays static on PlaybackNightModeSection.
- `_audioLanguageOptions` stays static on PlaybackAudioSection.
- `_subtitleLanguageOptions` stays static on PlaybackSubtitleSection.
- `_completionThresholdOptions` reads storage on PlaybackPlayerSetters.
- `_aspectLabels` and both language index getters read their original owners.
- NetworkTuning and SubtitleSettingsService files stay byte-identical.

## Lifecycle / facade simulation

- Normally formatted simulation: **351 physical lines**; cap **400**.
- Short descriptive handles do not collide with any original field.
- No lifecycle statement moves, splits or gains an initialization.
- Exit milestone for retained State sections/platform/storage/localization is
  the future Riverpod/data/capability/localization migration described in the plan.

### Step-0 simulation breakdown

Measured artifact: `.git/refactor-evidence/playback_settings/facade-simulation.dart.txt`;
AST span breakdown in `facade-simulation-breakdown.json`. It is a sizing sketch,
not a compiling implementation; final imports/bindings are measured again in step 7.

- widget: 14 physical lines.
- initState: 240 physical lines.
- dispose: 47 physical lines.
- composition getter: 17 physical lines.
- self-push: 4 physical lines.
- build forwarder: 2 physical lines.
- accessor forwarder: 6 physical lines.
- remaining imports, class header, owner handles and whitespace: 21 physical lines.

### Final measured facade and wiring

Compiling final facade: **365 formatted physical lines**, under the 400 cap.
`final-facade-breakdown.json` records widget 14, initState 240, dispose 47,
composition getter 17, self-push 4, build forwarder 2, accessor forwarder 4,
and remaining imports/handles/header/whitespace 37. Against the 351-line sketch,
remaining lines add 16 and the accessor drops two. Lifecycle stays whole.

All 214 entries are located at their registered destinations in
`final-wiring-checklist.json`; original comment-token multiset is exact (192).
Per-step wiring reviews precede scaffold pins. Composition borrows original owner
instances and real action tear-offs; context, mounted and section remain live.
The frozen 191-key accessor body lives in `playback_settings_test_access.dart`
over `PlaybackSections`; the facade keeps its original typed State parameter.
Its State self-push callback is stored as the same borrowed tear-off used by layout.
