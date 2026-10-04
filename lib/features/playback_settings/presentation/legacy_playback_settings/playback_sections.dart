import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_actions.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_actions.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_actions.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_player_mode_actions.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_settings_load.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_vr_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_windows_actions.dart';
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
  final PlaybackIosActions iosActions;
  final PlaybackLinuxActions linuxActions;
  final PlaybackMacActions macActions;
  final PlaybackPlayerModeActions playerModeActions;
  final PlaybackSettingsLoad load;
  final PlaybackWindowsActions windowsActions;
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
    required this.iosActions,
    required this.linuxActions,
    required this.macActions,
    required this.playerModeActions,
    required this.load,
    required this.windowsActions,
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
  required Future<void> Function() loadFonts,
}) {
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
  final playerModeActions = PlaybackPlayerModeActions((
    context: context,
    core: core,
    mounted: mounted,
    setState: setState,
  ));
  final load = PlaybackSettingsLoad((
    context: context,
    core: core,
    ios: ios,
    linux: linux,
    loadFonts: loadFonts,
    mac: mac,
    mounted: mounted,
    section: section,
    setState: setState,
    sub: sub,
    values: values,
    vr: vr,
    win: win,
  ));
  final windowsActions = PlaybackWindowsActions((
    context: context,
    mounted: mounted,
    setState: setState,
    win: win,
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
    iosActions: iosActions,
    linuxActions: linuxActions,
    macActions: macActions,
    playerModeActions: playerModeActions,
    load: load,
    windowsActions: windowsActions,
  );
}
