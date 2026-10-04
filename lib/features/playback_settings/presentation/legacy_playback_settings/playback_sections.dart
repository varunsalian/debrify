import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_audio_section.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_defaults_card.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_external_section.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_font_actions.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_actions.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_section.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_actions.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_section.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_actions.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_section.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_night_mode_section.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_player_appearance.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_player_mode_actions.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_player_mode_option.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_player_section.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_player_setters.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_player_tiles.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_settings_load.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_section.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_setters.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_video_section.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_vr_section.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_vr_setters.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_vr_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_windows_actions.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_windows_section.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_windows_state.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:flutter/material.dart';

class PlaybackSections {
  final PlaybackCoreState core;
  final PlaybackMacState mac;
  final PlaybackIosState ios;
  final PlaybackLinuxState linux;
  final PlaybackWindowsState win;
  final PlaybackVrState vr;
  final PlaybackValuesState values;
  final PlaybackSubtitleState sub;
  final PlaybackRowsState rows;
  final PlaybackSubtitleRowsState subRows;
  final PlaybackDefaultsCard defaultsCard;
  final PlaybackFontActions fontActions;
  final PlaybackIosActions iosActions;
  final PlaybackLinuxActions linuxActions;
  final PlaybackMacActions macActions;
  final PlaybackPlayerAppearance playerAppearance;
  final PlaybackPlayerModeActions playerModeActions;
  final PlaybackPlayerSetters playerSetters;
  final PlaybackSubtitleSetters subtitleSetters;
  final PlaybackVrSetters vrSetters;
  final PlaybackWindowsActions windowsActions;
  final PlaybackNightModeSection nightModeSection;
  final PlaybackPlayerModeOption playerModeOption;
  final PlaybackPlayerTiles playerTiles;
  final PlaybackSettingsLoad load;
  final PlaybackSubtitleSection subtitleSection;
  final PlaybackVideoSection videoSection;
  final PlaybackVrSection vrSection;
  final PlaybackAudioSection audioSection;
  final PlaybackIosSection iosSection;
  final PlaybackLinuxSection linuxSection;
  final PlaybackMacSection macSection;
  final PlaybackWindowsSection windowsSection;
  final PlaybackExternalSection externalSection;
  final PlaybackPlayerSection playerSection;
  PlaybackSections({
    required this.core,
    required this.mac,
    required this.ios,
    required this.linux,
    required this.win,
    required this.vr,
    required this.values,
    required this.sub,
    required this.rows,
    required this.subRows,
    required this.defaultsCard,
    required this.fontActions,
    required this.iosActions,
    required this.linuxActions,
    required this.macActions,
    required this.playerAppearance,
    required this.playerModeActions,
    required this.playerSetters,
    required this.subtitleSetters,
    required this.vrSetters,
    required this.windowsActions,
    required this.nightModeSection,
    required this.playerModeOption,
    required this.playerTiles,
    required this.load,
    required this.subtitleSection,
    required this.videoSection,
    required this.vrSection,
    required this.audioSection,
    required this.iosSection,
    required this.linuxSection,
    required this.macSection,
    required this.windowsSection,
    required this.externalSection,
    required this.playerSection,
  });
}

PlaybackSections createPlaybackSections({
  required PlaybackCoreState core,
  required PlaybackMacState mac,
  required PlaybackIosState ios,
  required PlaybackLinuxState linux,
  required PlaybackWindowsState win,
  required PlaybackVrState vr,
  required PlaybackValuesState values,
  required PlaybackSubtitleState sub,
  required PlaybackRowsState rows,
  required PlaybackSubtitleRowsState subRows,
  required void Function(VoidCallback) setState,
  required bool Function() mounted,
  required BuildContext Function() context,
  required PlaybackSettingsSection Function() section,
}) {
  final defaultsCard = PlaybackDefaultsCard((context: context));
  final fontActions = PlaybackFontActions((
    context: context,
    mounted: mounted,
    setState: setState,
    sub: sub,
  ));
  final iosActions = PlaybackIosActions((
    context: context,
    ios: ios,
    mounted: mounted,
    setState: setState,
  ));
  final linuxActions = PlaybackLinuxActions((
    context: context,
    linux: linux,
    mounted: mounted,
    setState: setState,
  ));
  final macActions = PlaybackMacActions((
    context: context,
    mac: mac,
    mounted: mounted,
    setState: setState,
  ));
  final playerAppearance = PlaybackPlayerAppearance((
    context: context,
    values: values,
  ));
  final playerModeActions = PlaybackPlayerModeActions((
    context: context,
    core: core,
    mounted: mounted,
    setState: setState,
  ));
  final playerSetters = PlaybackPlayerSetters((
    setState: setState,
    values: values,
  ));
  final subtitleSetters = PlaybackSubtitleSetters((
    setState: setState,
    sub: sub,
  ));
  final vrSetters = PlaybackVrSetters((setState: setState, vr: vr));
  final windowsActions = PlaybackWindowsActions((
    context: context,
    mounted: mounted,
    setState: setState,
    win: win,
  ));
  final nightModeSection = PlaybackNightModeSection((
    context: context,
    setNightModeIndex: playerSetters.setNightModeIndex,
    values: values,
  ));
  final playerModeOption = PlaybackPlayerModeOption((
    core: core,
    setDefaultPlayerMode: playerModeActions.setDefaultPlayerMode,
  ));
  final playerTiles = PlaybackPlayerTiles((
    context: context,
    ios: ios,
    linux: linux,
    mac: mac,
    selectIOSPlayer: iosActions.selectIOSPlayer,
    selectLinuxPlayer: linuxActions.selectLinuxPlayer,
    selectPlayer: macActions.selectPlayer,
    selectWindowsPlayer: windowsActions.selectWindowsPlayer,
    win: win,
  ));
  final load = PlaybackSettingsLoad((
    context: context,
    core: core,
    ios: ios,
    linux: linux,
    loadFonts: fontActions.loadFonts,
    mac: mac,
    mounted: mounted,
    section: section,
    setState: setState,
    sub: sub,
    values: values,
    vr: vr,
    win: win,
  ));
  final subtitleSection = PlaybackSubtitleSection((
    context: context,
    defaultsCard: defaultsCard.defaultsCard,
    importCustomFont: fontActions.importCustomFont,
    removeCustomFont: fontActions.removeCustomFont,
    setDefaultSubtitleLanguage: subtitleSetters.setDefaultSubtitleLanguage,
    setSubtitleAutoSync: subtitleSetters.setSubtitleAutoSync,
    setSubtitleBgIndex: subtitleSetters.setSubtitleBgIndex,
    setSubtitleBold: subtitleSetters.setSubtitleBold,
    setSubtitleColorIndex: subtitleSetters.setSubtitleColorIndex,
    setSubtitleFontIndex: subtitleSetters.setSubtitleFontIndex,
    setSubtitleForcedOnly: subtitleSetters.setSubtitleForcedOnly,
    setSubtitleOnlyForeignAudio: subtitleSetters.setSubtitleOnlyForeignAudio,
    setSubtitleSizeIndex: subtitleSetters.setSubtitleSizeIndex,
    setSubtitleStyleIndex: subtitleSetters.setSubtitleStyleIndex,
    sub: sub,
    subRows: subRows,
  ));
  final videoSection = PlaybackVideoSection((
    context: context,
    defaultsCard: defaultsCard.defaultsCard,
    rows: rows,
    setAndroidVideoRendererMode: playerSetters.setAndroidVideoRendererMode,
    setContentDisplayMatchMode: playerSetters.setContentDisplayMatchMode,
    setDefaultAspectIndex: playerSetters.setDefaultAspectIndex,
    setIptvDecoderMode: playerSetters.setIptvDecoderMode,
    setTvosForceSoftwareDecode: playerSetters.setTvosForceSoftwareDecode,
    values: values,
  ));
  final vrSection = PlaybackVrSection((
    context: context,
    core: core,
    setVrAutoDetectFormat: vrSetters.setVrAutoDetectFormat,
    setVrDefaultScreenType: vrSetters.setVrDefaultScreenType,
    setVrDefaultStereoMode: vrSetters.setVrDefaultStereoMode,
    setVrShowDialog: vrSetters.setVrShowDialog,
    vr: vr,
  ));
  final audioSection = PlaybackAudioSection((
    context: context,
    defaultsCard: defaultsCard.defaultsCard,
    nightModeSettings: nightModeSection.nightModeSettings,
    rows: rows,
    setAppleMultichannel: playerSetters.setAppleMultichannel,
    setAudioPassthrough: playerSetters.setAudioPassthrough,
    setDefaultAudioLanguage: subtitleSetters.setDefaultAudioLanguage,
    setSystemAudioEffects: playerSetters.setSystemAudioEffects,
    setTvosForceStereo: playerSetters.setTvosForceStereo,
    setTvosLegacyAudioOutput: playerSetters.setTvosLegacyAudioOutput,
    sub: sub,
    values: values,
  ));
  final iosSection = PlaybackIosSection((
    buildIOSPlayerTile: playerTiles.buildIOSPlayerTile,
    clearIOSCustomScheme: iosActions.clearIOSCustomScheme,
    context: context,
    core: core,
    ios: ios,
    saveIOSCustomScheme: iosActions.saveIOSCustomScheme,
    setState: setState,
  ));
  final linuxSection = PlaybackLinuxSection((
    buildLinuxPlayerTile: playerTiles.buildLinuxPlayerTile,
    clearLinuxCustomCommand: linuxActions.clearLinuxCustomCommand,
    context: context,
    core: core,
    linux: linux,
    saveLinuxCustomCommand: linuxActions.saveLinuxCustomCommand,
    setState: setState,
  ));
  final macSection = PlaybackMacSection((
    browseForCustomApp: macActions.browseForCustomApp,
    buildPlayerTile: playerTiles.buildPlayerTile,
    clearCustomApp: macActions.clearCustomApp,
    clearCustomCommand: macActions.clearCustomCommand,
    context: context,
    core: core,
    mac: mac,
    saveCustomCommand: macActions.saveCustomCommand,
    setState: setState,
  ));
  final windowsSection = PlaybackWindowsSection((
    buildWindowsPlayerTile: playerTiles.buildWindowsPlayerTile,
    clearWindowsCustomCommand: windowsActions.clearWindowsCustomCommand,
    context: context,
    core: core,
    saveWindowsCustomCommand: windowsActions.saveWindowsCustomCommand,
    setState: setState,
    win: win,
  ));
  final externalSection = PlaybackExternalSection((
    core: core,
    iosSettings: iosSection.iosSettings,
    linuxSettings: linuxSection.linuxSettings,
    macSettings: macSection.macSettings,
    vrSettings: vrSection.vrSettings,
    windowsSettings: windowsSection.windowsSettings,
  ));
  final playerSection = PlaybackPlayerSection((
    buildPlayerModeOption: playerModeOption.buildPlayerModeOption,
    completionThresholdIndex: playerSetters.completionThresholdIndex,
    completionThresholdOptions: () => playerSetters.completionThresholdOptions,
    context: context,
    core: core,
    defaultsCard: defaultsCard.defaultsCard,
    externalPlayerSettings: externalSection.externalPlayerSettings,
    playerAppearance: playerAppearance.playerAppearance,
    rows: rows,
    setEpisodeCompletionThresholdIndex:
        playerSetters.setEpisodeCompletionThresholdIndex,
    setMovieCompletionThresholdIndex:
        playerSetters.setMovieCompletionThresholdIndex,
    setNetBuffer: playerSetters.setNetBuffer,
    setNetPatience: playerSetters.setNetPatience,
    setSkipSegmentProvider: playerSetters.setSkipSegmentProvider,
    setSkipSegmentsEnabled: playerSetters.setSkipSegmentsEnabled,
    setStartPortrait: playerSetters.setStartPortrait,
    subRows: subRows,
    values: values,
  ));
  return PlaybackSections(
    core: core,
    mac: mac,
    ios: ios,
    linux: linux,
    win: win,
    vr: vr,
    values: values,
    sub: sub,
    rows: rows,
    subRows: subRows,
    defaultsCard: defaultsCard,
    fontActions: fontActions,
    iosActions: iosActions,
    linuxActions: linuxActions,
    macActions: macActions,
    playerAppearance: playerAppearance,
    playerModeActions: playerModeActions,
    playerSetters: playerSetters,
    subtitleSetters: subtitleSetters,
    vrSetters: vrSetters,
    windowsActions: windowsActions,
    nightModeSection: nightModeSection,
    playerModeOption: playerModeOption,
    playerTiles: playerTiles,
    load: load,
    subtitleSection: subtitleSection,
    videoSection: videoSection,
    vrSection: vrSection,
    audioSection: audioSection,
    iosSection: iosSection,
    linuxSection: linuxSection,
    macSection: macSection,
    windowsSection: windowsSection,
    externalSection: externalSection,
    playerSection: playerSection,
  );
}
