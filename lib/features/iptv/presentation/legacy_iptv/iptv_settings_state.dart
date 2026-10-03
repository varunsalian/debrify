import 'dart:io' show Platform;

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_service.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Playlists and settings
class IptvSettingsState {
  final IptvService iptvService = IptvService.instance;

  List<IptvPlaylist> playlists = [];

  /// iOS only: a one-time dismissible notice that recording doesn't exist
  /// there (Apple allows no background capture and no scheduled wake-ups) —
  /// otherwise iOS users go hunting for a Record button that isn't hidden
  /// by a setting, it's hidden by the platform.
  bool showIosRecordingNotice = false;

  static const String iosNoticeDismissedPref =
      'iptv_ios_recording_notice_dismissed';

  IptvPlaylist? selectedPlaylist;

  bool settingsLoaded = false;

  /// Why the settings pass failed, if it did. [_loadSettings] is the gate in
  /// front of the whole page: it sets [settingsLoaded] on its LAST line, so
  /// any throw on the way there used to leave the bare spinner up forever with
  /// no error, no Retry and nothing on screen to name the failure — the same
  /// silent-spinner trap [_loadPlaylist] already guards against one level down.
  String? settingsError;

  /// The cockpit's visual style (`iptv_style` pref). Only the TV/desktop
  /// cockpit branch consults it — classic and touch-tablet layouts ignore it.
  IptvStyle iptvStyle = IptvStyle.fromPref(
    IptvAppearanceStorage.iptvStyleCached,
  );

  /// Whether focusing a row may open its stream in the embedded side stage.
  /// The channel identity and stage actions remain available when false; only
  /// the automatic tune is suppressed so it cannot consume a provider slot.
  bool channelPreviewEnabled = true;

  /// Desktop gets the full two-pane experience too: source rail, embedded
  /// live preview, quiet filters — hover previews, click plays.
  /// Large touch tablets use the same shell with a fixed center selector;
  /// phones and constrained tablet windows keep the single-pane list.
  static final bool isDesktop =
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
}
