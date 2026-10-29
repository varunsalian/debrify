import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'settings_classic_layout.dart';
import 'settings_spotlight_category.dart' as spotlight;

class SettingsLayout extends StatelessWidget {
  final String Function() legacyReasonSummary;
  final ConnectionsSummary connections;
  final VoidCallback onOpenSearch;
  final Future<void> Function() onOpenTorrentSettings;
  final Future<void> Function() onOpenFilterSettings;
  final Future<void> Function() onOpenProviderSettings;
  final Future<void> Function() onOpenQuickPlaySettings;
  final Future<void> Function() onOpenDiscoverSettings;
  final Future<void> Function() onOpenDebrifyTvSettings;
  final Future<void> Function() onOpenPikPakSettings;
  final Future<void> Function() onOpenHomePageSettings;
  final Future<void> Function() onOpenMetadataSettings;
  final Future<void> Function() onOpenCollectionsSettings;
  final Future<void> Function() onOpenBadgesSettings;
  final Future<void> Function() onOpenCollectionListStyle;
  final Future<void> Function(PlaybackSettingsSection) onOpenPlaybackSection;
  final VoidCallback onOpenRemoteControl;
  final bool showSwitchProfile;
  final Future<void> Function() onSwitchProfile;
  final Future<void> Function() onAddProfile;
  final Future<void> Function() onEditProfile;
  final Future<void> Function() onOpenNavigationSettings;
  final bool isAndroidTv;
  final Future<void> Function() onClearDownloads;
  final Future<void> Function() onClearPlayback;
  // Settings › Storage Usage; null hides the row.
  final Future<void> Function()? onOpenStorageUsage;
  // Android-only custom download folder (SAF); null hides the row.
  final Future<void> Function()? onOpenDownloadLocation;
  final String downloadLocationSubtitle;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onRestoreBackup;
  final Future<void> Function() onOpenSyncAndMigrate;
  final Future<void> Function()? onExportDiagnosticLogs;
  final Future<void> Function() onDangerAction;
  final String appVersion;
  final Future<void> Function() onCheckForUpdates;
  final String updateSubtitle;
  final bool checkingUpdates;
  final bool autoUpdateChecksEnabled;
  final ValueChanged<bool> onToggleAutoUpdateChecks;
  final bool includeAlphaUpdates;
  final ValueChanged<bool> onToggleIncludeAlphaUpdates;
  final bool tvKeyboardEnabled;
  final ValueChanged<bool> onToggleTvKeyboard;
  final bool showSupportDonation;
  final String supportDonationLabel;
  final String supportDonationSubtitle;
  final Future<void> Function() onOpenSupportDonation;
  // Live TV & DVR.
  final Future<void> Function() onOpenRecordings;
  final Future<void> Function() onOpenIptvSettings;
  // Appearance rows. This layout is only built off-TV, so the TV-only
  // pickers (home style, discover, sidebar, screen size) live solely in
  // SettingsTvLayout's Appearance category.
  final bool showIptvAppearance;
  final String debrifyTvStyleLabel;
  final Future<void> Function() onOpenDebrifyTvStyle;
  final String textBrightnessLabel;
  final Future<void> Function() onOpenTextBrightness;
  final String launchAnimationLabel;
  final Future<void> Function() onOpenLaunchAnimation;
  final String iptvStyleLabel;
  final Future<void> Function() onOpenIptvStyle;
  final String playerGuideStyleLabel;
  final Future<void> Function() onOpenPlayerGuideStyle;
  final String playLoaderStyleLabel;
  final Future<void> Function() onOpenPlayLoaderStyle;
  final String playerDockLabel;
  final Future<void> Function() onOpenPlayerDock;
  final String detailPageStyleLabel;
  final Future<void> Function() onOpenDetailPageStyle;
  final String appThemeLabel;
  final Future<void> Function() onOpenLooks;
  final Future<void> Function() onOpenThemeTokens;
  final String themeTokensLabel;

  /// Withheld like [detailThemeLabel]: Theme Lab is a preview TOOL, not a
  /// setting — it changes nothing, and a row that changes nothing is noise in
  /// a list of rows that do. Page and wiring stay so restoring it is a few
  /// lines.
  final Future<void> Function() onOpenThemeLab;
  final Future<void> Function() onOpenAppTheme;

  /// Still plumbed, deliberately: the Details Theme ROW is withheld from the
  /// Appearance list because App Theme write-through-mirrors into
  /// `detail_theme`, so two rows set the same thing and one silently
  /// overwrote the other. The page and its wiring stay so restoring the row is
  /// a few lines rather than an archaeology exercise — the same
  /// withheld-not-deleted pattern `kDetailThemesShipped` uses.
  final String detailThemeLabel;
  final Future<void> Function() onOpenDetailTheme;
  final String parentsGuideStyleLabel;
  final Future<void> Function() onOpenParentsGuideStyle;
  final String phoneNavStyleLabel;
  final String desktopSidebarStyleLabel;
  final Future<void> Function() onOpenDesktopSidebarStyle;
  final String profileAppearanceLabel;
  final Future<void> Function() onOpenProfileAppearance;

  const SettingsLayout({
    super.key,
    required this.connections,
    required this.legacyReasonSummary,
    required this.onOpenSearch,
    required this.onOpenTorrentSettings,
    required this.onOpenFilterSettings,
    required this.onOpenProviderSettings,
    required this.onOpenQuickPlaySettings,
    required this.onOpenDiscoverSettings,
    required this.onOpenDebrifyTvSettings,
    required this.onOpenPikPakSettings,
    required this.onOpenHomePageSettings,
    required this.onOpenMetadataSettings,
    required this.onOpenCollectionsSettings,
    required this.onOpenBadgesSettings,
    required this.onOpenCollectionListStyle,
    required this.onOpenPlaybackSection,
    required this.onOpenRemoteControl,
    required this.showSwitchProfile,
    required this.onSwitchProfile,
    required this.onAddProfile,
    required this.onEditProfile,
    required this.onOpenNavigationSettings,
    required this.isAndroidTv,
    required this.onClearDownloads,
    required this.onClearPlayback,
    this.onOpenStorageUsage,
    this.onOpenDownloadLocation,
    this.downloadLocationSubtitle = '',
    required this.onCreateBackup,
    required this.onRestoreBackup,
    required this.onOpenSyncAndMigrate,
    this.onExportDiagnosticLogs,
    required this.onDangerAction,
    required this.appVersion,
    required this.onCheckForUpdates,
    required this.updateSubtitle,
    required this.checkingUpdates,
    required this.autoUpdateChecksEnabled,
    required this.onToggleAutoUpdateChecks,
    required this.includeAlphaUpdates,
    required this.onToggleIncludeAlphaUpdates,
    required this.tvKeyboardEnabled,
    required this.onToggleTvKeyboard,
    required this.showSupportDonation,
    required this.supportDonationLabel,
    required this.supportDonationSubtitle,
    required this.onOpenSupportDonation,
    required this.onOpenRecordings,
    required this.onOpenIptvSettings,
    required this.showIptvAppearance,
    required this.debrifyTvStyleLabel,
    required this.onOpenDebrifyTvStyle,
    required this.textBrightnessLabel,
    required this.onOpenTextBrightness,
    required this.launchAnimationLabel,
    required this.onOpenLaunchAnimation,
    required this.iptvStyleLabel,
    required this.onOpenIptvStyle,
    required this.playerGuideStyleLabel,
    required this.onOpenPlayerGuideStyle,
    required this.playLoaderStyleLabel,
    required this.onOpenPlayLoaderStyle,
    required this.playerDockLabel,
    required this.onOpenPlayerDock,
    required this.detailPageStyleLabel,
    required this.onOpenDetailPageStyle,
    required this.appThemeLabel,
    required this.onOpenLooks,
    required this.onOpenThemeTokens,
    required this.themeTokensLabel,
    required this.onOpenThemeLab,
    required this.onOpenAppTheme,
    required this.detailThemeLabel,
    required this.onOpenDetailTheme,
    required this.parentsGuideStyleLabel,
    required this.onOpenParentsGuideStyle,
    required this.phoneNavStyleLabel,
    required this.desktopSidebarStyleLabel,
    required this.onOpenDesktopSidebarStyle,
    required this.profileAppearanceLabel,
    required this.onOpenProfileAppearance,
  });

  List<ConnectionInfo> get providerConnections => [
    connections.realDebrid,
    connections.torbox,
    connections.premiumize,
    connections.allDebrid,
    connections.pikpak,
    connections.webDav,
    if (connections.mediaServers != null) connections.mediaServers!,
    connections.indexerManagers,
    connections.iptv,
  ];

  List<ConnectionInfo> get trackerServices => [
    connections.trakt,
    connections.simkl,
    if (connections.mdblist != null) connections.mdblist!,
  ];

  bool showsLargeCollectionStyles(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= 600 ||
      (PlatformUtil.isDesktop && MediaQuery.sizeOf(context).width >= 600);

  Widget buildSpotlightCategory(BuildContext context, int category) =>
      spotlight.buildSpotlightCategory(this, context, category);

  @override
  Widget build(BuildContext context) =>
      buildClassicSettingsLayout(this, context);
}
