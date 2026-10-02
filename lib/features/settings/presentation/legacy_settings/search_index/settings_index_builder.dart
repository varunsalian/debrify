import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import '../settings_summaries.dart';

class SettingsIndexBuilder {
  SettingsIndexBuilder(this.summaries, this.deps);
  final SettingsSummaries summaries;
  final ({
    Future<void> Function() addProfile,
    ConnectionInfo Function() allDebridInfo,
    Future<void> Function() checkForAppUpdates,
    Future<void> Function() clearDownloadData,
    Future<void> Function() clearPlaybackData,
    BuildContext Function() context,
    Future<void> Function() createBackup,
    bool Function() downloadLocationSupported,
    Future<void> Function() editActiveProfile,
    Future<void> Function() exportDiagnosticLogs,
    ConnectionInfo Function() indexerManagersInfo,
    bool Function() iptvAppearanceSearchable,
    ConnectionInfo Function() iptvInfo,
    bool Function() isAndroid,
    bool Function() isTelevision,
    List<SettingsSearchEntry> Function() leafSearchEntries,
    ConnectionInfo Function() mdblistInfo,
    ConnectionInfo Function() mediaServersInfo,
    Future<void> Function() openBadgesSettings,
    Future<void> Function() openCollectionListStyle,
    Future<void> Function() openCollectionsSettings,
    Future<void> Function() openDebrifyTvPlayerStylePage,
    Future<void> Function() openDebrifyTvSettings,
    Future<void> Function() openDebrifyTvStylePage,
    Future<void> Function() openDesktopSidebarStyle,
    Future<void> Function() openDetailPageStylePage,
    Future<void> Function() openDiscoverLayout,
    Future<void> Function() openDiscoverSettings,
    Future<void> Function() openDownloadLocationSettings,
    Future<void> Function() openExternalPlayerSettings,
    Future<void> Function() openFilterSettings,
    Future<void> Function() openHomePageSettings,
    Future<void> Function() openIptvSettings,
    Future<void> Function() openIptvStylePage,
    Future<void> Function() openLaunchAnimationPage,
    Future<void> Function() openLooksPage,
    Future<void> Function() openMetadataSettings,
    Future<void> Function() openNavigationSettings,
    Future<void> Function() openParentsGuideStylePage,
    Future<void> Function() openPlayLoaderStylePage,
    Future<void> Function() openPlayerDockPage,
    Future<void> Function() openPlayerGuideStylePage,
    Future<void> Function() openProfileAppearance,
    Future<void> Function() openProviderSettings,
    Future<void> Function() openQuickPlaySettings,
    Future<void> Function() openRecordings,
    Future<void> Function() openRemoteControl,
    Future<void> Function() openStremioTvSettings,
    Future<void> Function() openSupportDonation,
    Future<void> Function() openSyncAndMigrate,
    Future<void> Function() openTextBrightnessPage,
    Future<void> Function() openThemeTokensPage,
    Future<void> Function() openTorrentSettings,
    Future<void> Function() openTvHeroArtworkQuality,
    Future<void> Function() openTvHomeStyle,
    Future<void> Function() openTvPlayerControlsStylePage,
    Future<void> Function() openTvRenderQuality,
    Future<void> Function() openTvScreenSize,
    Future<void> Function() openTvSidebarStyle,
    ConnectionInfo Function() pikpakInfo,
    ConnectionInfo Function() premiumizeInfo,
    ConnectionInfo Function() rdInfo,
    Future<void> Function() resetAppData,
    Future<void> Function() restoreBackup,
    ConnectionInfo Function() simklInfo,
    Future<void> Function() switchProfile,
    String Function() themeTokensLabel,
    Future<void> Function(bool enabled) toggleAutoUpdateChecks,
    Future<void> Function(bool enabled) toggleIncludeAlphaUpdates,
    Future<void> Function(bool enabled) toggleTvKeyboard,
    ConnectionInfo Function() torboxInfo,
    ConnectionInfo Function() trackingInfo,
    ConnectionInfo Function() traktInfo,
    ConnectionInfo Function() webDavInfo,
  })
  deps;

  SettingsSearchEntry conn(
    ConnectionInfo info,
    List<String> keywords, {
    // Trakt/Simkl/MDBList now live under their own heading; search results
    // must say where the thing actually is.
    String category = 'Connections',
  }) => SettingsSearchEntry(
    icon: Icons.link_rounded,
    title: info.title,
    subtitle: info.caption,
    category: category,
    keywords: ['integration', ...keywords],
    onTap: info.onTap,
  );

  SettingsSearchEntry nav(
    SettingsRowContent c,
    String category,
    Future<void> Function() onTap, {
    List<String> keywords = const [],
    String? subtitle,
    bool destructive = false,
  }) => SettingsSearchEntry(
    icon: c.icon,
    title: c.title,
    subtitle: subtitle ?? c.subtitle,
    category: category,
    keywords: keywords,
    destructive: destructive,
    onTap: onTap,
  );

  List<String> labels(Iterable<String> values) => [
    for (final value in values) value.toLowerCase(),
  ];
}
