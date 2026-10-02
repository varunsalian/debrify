import 'dart:io' show Platform;
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'settings_summaries.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsPlatformGates {
  SettingsPlatformGates(this._summaries);
  final SettingsSummaries _summaries;

  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  bool get isTelevision => PlatformUtil.isTelevision;

  /// Handsets only. The player's start-orientation control is hidden on TV
  /// (no portrait to open in) and on desktop (the orientation call is a no-op
  /// there) — see ExternalPlayerSettingsPage.
  bool get isPhone => PlatformUtil.isPhone;

  /// The IPTV Appearance picker renders only where the cockpit does (every TV
  /// platform and desktop) — the SAME gate IptvSettingsPage uses for its
  /// section. This includes tvOS, where the synchronous television flag is
  /// authoritative and the Android-specific cache is always false.
  bool get iptvAppearanceSearchable =>
      PlatformUtil.isTelevision || (!kIsWeb && PlatformUtil.isDesktop);

  /// Custom launch command (macOS/Linux/Windows) or custom URL scheme (iOS).
  /// Android's external-player branch offers neither — it only explains the
  /// system app chooser. See ExternalPlayerSettingsPage's platform branches.
  bool get customPlayerCommandSupported =>
      !kIsWeb &&
      (Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows ||
          Platform.isIOS);

  /// A named preferred-player picker exists on Apple platforms and desktop.
  /// Android delegates this choice to the system app chooser instead.
  bool get preferredExternalPlayerSupported =>
      !kIsWeb &&
      (Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows ||
          Platform.isIOS);

  /// The recordings page has a working backend: the Android engine (tracked by
  /// [_summaries.recordingSearchable]) or the desktop recorder. On iOS it has neither —
  /// scheduling only raises a storage error and the library is always empty.
  bool get recordingSupported =>
      _summaries.recordingSearchable ||
      DesktopScheduleService.instance.isSupported;
}
