import 'package:debrify/features/debrify_tv/application/debrify_tv_random_start.dart';
import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/engine/settings_manager.dart';
import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/utils/debrify_tv_filters.dart';

class DebrifyTvSettingsState {
  final SettingsManager settingsManager = SettingsManager();
  final Map<String, bool> tvEngineStates = <String, bool>{};
  final Map<String, int> tvSmallChannelMaxByEngine = <String, int>{};
  final Map<String, int> tvLargeChannelMaxByEngine = <String, int>{};
  final Map<String, int> tvQuickPlayMaxByEngine = <String, int>{};
  int channelBatchSize = 4;
  int keywordThreshold = 10;
  int minTorrentsPerKeyword = 5;
  // Quick Play limits
  int quickPlayMaxKeywords = 5;
  // Advanced options
  bool startRandom = true;
  int randomStartPercent = randomStartPercentDefault;
  bool hideSeekbar = true;
  bool showChannelName = true;
  bool showVideoTitle = true;
  bool hideOptions = false;
  bool hideBackButton = false;
  String provider = DebrifyTvConstants.providerRealDebrid;
  // Quick play options
  bool quickStartRandom = true;
  int quickRandomStartPercent = randomStartPercentDefault;
  bool quickHideSeekbar = true;
  bool quickShowChannelName = true;
  bool quickShowVideoTitle = true;
  bool quickHideOptions = false;
  bool quickHideBackButton = false;
  bool quickAvoidNsfw = true;

  /// The viewer-scoped, role-locked NSFW rail: forced for a child profile
  /// regardless of any channel's stored flag or dialog toggle. Evaluated
  /// live so a profile switch retunes filtering without a rebuild dance.
  bool get viewerForcesNsfw =>
      !ProfilePolicyGuard.allowsSync(ProfileFeature.allowAdultContent);
  bool rdSkipBlockedTorrents = true;
  String quickProvider = DebrifyTvConstants.providerRealDebrid;
  // Debrify TV playback filters. Shared by channels and quick play (one
  // Debrify TV feed preference, unlike provider/NSFW which are per-scope).
  // Quality narrows torrents by release name; size narrows FILES once a
  // provider has returned them. See DebrifyTvFilters for why they split.
  DebrifyTvFilters tvFilters = const DebrifyTvFilters.empty();
  bool rdAvailable = false;
  bool torboxAvailable = false;
  bool pikpakAvailable = false;
  bool premiumizeAvailable = false;
  bool allDebridAvailable = false;
  bool isAndroidTv = false;
}
