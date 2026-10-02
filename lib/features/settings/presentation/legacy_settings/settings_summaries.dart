import 'package:debrify/models/tv_hero_artwork_quality.dart';
import 'package:debrify/models/tv_render_quality.dart';
import 'package:debrify/services/play_loader_style.dart';
import 'package:debrify/services/storage/detail_page_storage.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/tv_display_storage.dart';
import 'package:debrify/services/support_remote_config_service.dart';

/// Summary values owned by one Settings State, with the original defaults.
class SettingsSummaries {
  bool loading = true;
  Set<String> summaryFailures = {};
  bool summaryLoadFailed = false;
  Set<String> summaryUnavailable = {};
  bool isAndroidTv = false;

  /// IPTV recording engine availability (Android 10+); gates its search entry.
  bool recordingSearchable = false;
  bool realDebridConnected = false;
  String realDebridStatus = 'Not connected';
  String realDebridCaption = 'Tap to connect';
  bool torboxConnected = false;
  String torboxStatus = 'Not connected';
  String torboxCaption = 'Tap to connect';
  bool premiumizeConnected = false;
  String premiumizeStatus = 'Not connected';
  String premiumizeCaption = 'Tap to connect';
  bool allDebridConnected = false;
  String allDebridStatus = 'Not connected';
  String allDebridCaption = 'Tap to connect';
  bool pikpakConnected = false;
  String pikpakStatus = 'Not connected';
  String pikpakCaption = 'Tap to connect';
  bool webDavConnected = false;
  String webDavStatus = 'Not connected';
  String webDavCaption = 'Tap to connect';
  bool iptvCredentialsPending = false;
  bool traktConnected = false;
  String traktStatus = 'Not connected';
  String traktCaption = 'Tap to connect';
  bool simklConnected = false;
  String simklStatus = 'Not connected';
  String simklCaption = 'Tap to connect';
  bool mdblistConnected = false;
  String mdblistStatus = 'Not connected';
  String mdblistCaption = 'Tap to connect';
  bool indexerManagersConfigured = false;
  String indexerManagersStatus = 'Not configured';
  String indexerManagersCaption = 'Connect Jackett or Prowlarr';
  String appVersion = '';
  String currentVersionName = '';
  bool checkingUpdates = false;
  String updateSubtitle = 'Check for new builds from GitHub releases';
  bool autoUpdateChecksEnabled = true;
  bool includeAlphaUpdates = false;
  bool diagnosticExportVisible = false;
  bool exportingDiagnostics = false;
  bool tvKeyboardEnabled = true;
  int tvUiScalePercent = TvDisplayStorage.kTvUiScaleDefault;
  TvRenderQuality tvRenderQuality = TvRenderQuality.auto;
  TvHeroArtworkQuality tvHeroArtworkQuality = TvHeroArtworkQuality.automatic;
  String tvHomeStyle = 'canvas';
  String discoverLayout = 'stage';
  String tvSidebarStyle = 'ghost';
  String iptvStyle = IptvAppearanceStorage.kIptvStyleDefault;
  String debrifyTvStyle = 'grid';
  String playerGuideStyle = 'classic';
  String playLoaderStyle = PlayLoaderStyleController.defaultStyle;
  String tvPlayerControlsStyle = 'ott';
  String debrifyTvPlayerStyle = 'cinema';
  String playerDockStyle = 'classic';
  String playerDockPalette = 'ultraviolet';
  String playerDockSize = 'auto';
  // The placeholder the Appearance row shows for the one frame before the
  // async load lands; a literal here would flash the wrong label.
  String detailPageStyle = DetailPageStorage.kDetailPageStyleDefault;
  String detailTheme = 'signal';
  String parentsGuideStyle = 'compass';
  String phoneNavStyle = 'classic';
  String desktopSidebarStyle = 'rail';
  String textBrightness = 'bright';
  String launchAnimation = 'trace';
  String downloadLocationSubtitle = 'Downloads/Debrify (default)';
  SupportDonationConfig supportDonation = SupportDonationConfig.empty;
  String supportSettingsLabel = 'Support Debrify';
  String supportSettingsSubtitle = 'Help fund development with a donation';
  int mediaServerCount = 0;
}
