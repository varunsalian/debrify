import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';

class IptvSettingsPreferencesOwner {
  // Startup channel
  bool startupEnabled = false;
  String startupMode = StartupIptvStorage.startupIptvModeLast;
  Map<String, dynamic>? startupChannel;
  Map<String, dynamic>? lastLiveChannel;

  // Continue watching
  bool trackContinueWatching = true;

  // Embedded side preview while browsing channels. Providers count this as a
  // real stream, so users with tight connection limits can keep the stage's
  // artwork/details while preventing it from tuning.
  bool channelPreviewEnabled = true;
  int autoRefreshHours = 24;

  // Cockpit appearance (`iptv_style`). Shown only where the cockpit exists —
  // television and desktop; a phone or touch tablet would be picking a look it
  // can never see.
  String iptvStyle = IptvAppearanceStorage.kIptvStyleDefault;

  // In-player guide look (`iptv_player_guide_style`). Ungated: every
  // platform has a player — phones/desktop the Dart one, Android TV the
  // native one — and both read this pref at launch.
  String playerGuideStyle = 'classic';
}
