import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import '../settings_summaries.dart';
import 'settings_index_builder.dart';
import 'settings_index_slice_01.dart';
import 'settings_index_slice_02.dart';
import 'settings_index_slice_03.dart';
import 'settings_index_slice_04.dart';
import 'settings_index_slice_05.dart';
import 'settings_index_slice_06.dart';
import 'settings_index_slice_07.dart';
import 'settings_index_slice_08.dart';
import 'settings_index_slice_09.dart';
import 'settings_index_slice_10.dart';
import 'settings_index_slice_11.dart';
import 'settings_leaf_builder.dart';
import 'settings_leaf_slice_01.dart';
import 'settings_leaf_slice_02.dart';
import 'settings_leaf_slice_03.dart';
import 'settings_leaf_slice_04.dart';
import 'settings_leaf_slice_05.dart';
import 'settings_leaf_slice_06.dart';
import 'settings_leaf_slice_07.dart';
import 'settings_leaf_slice_08.dart';
import 'settings_leaf_slice_09.dart';
import 'settings_leaf_slice_10.dart';
import 'settings_leaf_slice_11.dart';

class SettingsSearchIndex {
  SettingsSearchIndex(this._summaries, this._deps);
  final SettingsSummaries _summaries;
  final ({
    Future<void> Function() addProfile,
    ConnectionInfo Function() allDebridInfo,
    Future<void> Function() checkForAppUpdates,
    Future<void> Function() clearDownloadData,
    Future<void> Function() clearPlaybackData,
    Future<void> Function() openStorageUsage,
    BuildContext Function() context,
    Future<void> Function() createBackup,
    bool Function() customPlayerCommandSupported,
    bool Function() downloadLocationSupported,
    Future<void> Function() editActiveProfile,
    Future<bool> Function(ProfileFeature feature) ensureProfileFeature,
    Future<void> Function() exportDiagnosticLogs,
    ConnectionInfo Function() indexerManagersInfo,
    bool Function() iptvAppearanceSearchable,
    ConnectionInfo Function() iptvInfo,
    bool Function() isAndroid,
    bool Function() isPhone,
    bool Function() isTelevision,
    ConnectionInfo Function() mdblistInfo,
    ConnectionInfo Function() mediaServersInfo,
    bool Function() mounted,
    Future<void> Function() openAllDebridSettings,
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
    Future<void> Function() openIndexerManagersSettings,
    Future<void> Function() openIptvAddSource,
    Future<void> Function() openIptvChannelOrder,
    Future<void> Function() openIptvSettings,
    Future<void> Function() openIptvStylePage,
    Future<void> Function() openLaunchAnimationPage,
    Future<void> Function() openLooksPage,
    Future<void> Function() openMdblistSettings,
    Future<void> Function() openMetadataSettings,
    Future<void> Function() openNavigationSettings,
    Future<void> Function() openParentsGuideStylePage,
    Future<void> Function() openPikPakSettings,
    Future<void> Function() openPlayLoaderStylePage,
    Future<void> Function(PlaybackSettingsSection section) openPlaybackSection,
    Future<void> Function() openPlayerDockPage,
    Future<void> Function() openPlayerGuideStylePage,
    Future<void> Function() openPremiumizeSettings,
    Future<void> Function() openProfileAppearance,
    Future<void> Function() openProviderSettings,
    Future<void> Function() openQuickPlaySettings,
    Future<void> Function() openRealDebridSettings,
    Future<void> Function() openRecordings,
    Future<void> Function() openRemoteControl,
    Future<void> Function() openSidebarCustomization,
    Future<void> Function() openSimklSettings,
    Future<void> Function() openStremioTvSettings,
    Future<void> Function() openSupportDonation,
    Future<void> Function() openSyncAndMigrate,
    Future<void> Function() openTextBrightnessPage,
    Future<void> Function() openThemeTokensPage,
    Future<void> Function() openTorboxSettings,
    Future<void> Function() openTorrentSettings,
    Future<void> Function() openTrackingSettings,
    Future<void> Function() openTraktSettings,
    Future<void> Function() openTvHeroArtworkQuality,
    Future<void> Function() openTvHomeStyle,
    Future<void> Function() openTvPlayerControlsStylePage,
    Future<void> Function() openTvRenderQuality,
    Future<void> Function() openTvScreenSize,
    Future<void> Function() openTvSidebarStyle,
    Future<void> Function() openWebDavSettings,
    ConnectionInfo Function() pikpakInfo,
    bool Function() preferredExternalPlayerSupported,
    ConnectionInfo Function() premiumizeInfo,
    ConnectionInfo Function() rdInfo,
    bool Function() recordingSupported,
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
  _deps;

  /// Flat, searchable index of every settings destination. Built fresh on open
  /// so dynamic copy (download folder, update status, connection captions) and
  /// live toggle values are current. Navigable entries reuse the same
  /// `_openXxx` handlers the layouts wire, so actions never drift; toggle
  /// entries read/write the same state fields as their inline rows.
  ///
  /// Top-level destinations live here; in-page options are appended by
  /// [leafSearchEntries] and deep-link to the page that hosts them (no
  /// scroll-to-highlight yet). [SettingsSearchEntry.keywords] carry the
  /// concepts a row's copy doesn't say out loud (sd card, 4k, epg, scrobble…).
  /// A few pages reachable only from outside Settings — Stremio TV's channel
  /// settings, the Addons tab — are indexed here too, since a settings search
  /// is where people look for them.
  List<SettingsSearchEntry> buildSearchIndex() {
    final b = SettingsIndexBuilder(_summaries, (
      addProfile: _deps.addProfile,
      allDebridInfo: _deps.allDebridInfo,
      checkForAppUpdates: _deps.checkForAppUpdates,
      clearDownloadData: _deps.clearDownloadData,
      clearPlaybackData: _deps.clearPlaybackData,
      openStorageUsage: _deps.openStorageUsage,
      context: _deps.context,
      createBackup: _deps.createBackup,
      downloadLocationSupported: _deps.downloadLocationSupported,
      editActiveProfile: _deps.editActiveProfile,
      exportDiagnosticLogs: _deps.exportDiagnosticLogs,
      indexerManagersInfo: _deps.indexerManagersInfo,
      iptvAppearanceSearchable: _deps.iptvAppearanceSearchable,
      iptvInfo: _deps.iptvInfo,
      isAndroid: _deps.isAndroid,
      isTelevision: _deps.isTelevision,
      leafSearchEntries: leafSearchEntries,
      mdblistInfo: _deps.mdblistInfo,
      mediaServersInfo: _deps.mediaServersInfo,
      openBadgesSettings: _deps.openBadgesSettings,
      openCollectionListStyle: _deps.openCollectionListStyle,
      openCollectionsSettings: _deps.openCollectionsSettings,
      openDebrifyTvPlayerStylePage: _deps.openDebrifyTvPlayerStylePage,
      openDebrifyTvSettings: _deps.openDebrifyTvSettings,
      openDebrifyTvStylePage: _deps.openDebrifyTvStylePage,
      openDesktopSidebarStyle: _deps.openDesktopSidebarStyle,
      openDetailPageStylePage: _deps.openDetailPageStylePage,
      openDiscoverLayout: _deps.openDiscoverLayout,
      openDiscoverSettings: _deps.openDiscoverSettings,
      openDownloadLocationSettings: _deps.openDownloadLocationSettings,
      openExternalPlayerSettings: _deps.openExternalPlayerSettings,
      openFilterSettings: _deps.openFilterSettings,
      openHomePageSettings: _deps.openHomePageSettings,
      openIptvSettings: _deps.openIptvSettings,
      openIptvStylePage: _deps.openIptvStylePage,
      openLaunchAnimationPage: _deps.openLaunchAnimationPage,
      openLooksPage: _deps.openLooksPage,
      openMetadataSettings: _deps.openMetadataSettings,
      openNavigationSettings: _deps.openNavigationSettings,
      openParentsGuideStylePage: _deps.openParentsGuideStylePage,
      openPlayLoaderStylePage: _deps.openPlayLoaderStylePage,
      openPlayerDockPage: _deps.openPlayerDockPage,
      openPlayerGuideStylePage: _deps.openPlayerGuideStylePage,
      openProfileAppearance: _deps.openProfileAppearance,
      openProviderSettings: _deps.openProviderSettings,
      openQuickPlaySettings: _deps.openQuickPlaySettings,
      openRecordings: _deps.openRecordings,
      openRemoteControl: _deps.openRemoteControl,
      openStremioTvSettings: _deps.openStremioTvSettings,
      openSupportDonation: _deps.openSupportDonation,
      openSyncAndMigrate: _deps.openSyncAndMigrate,
      openTextBrightnessPage: _deps.openTextBrightnessPage,
      openThemeTokensPage: _deps.openThemeTokensPage,
      openTorrentSettings: _deps.openTorrentSettings,
      openTvHeroArtworkQuality: _deps.openTvHeroArtworkQuality,
      openTvHomeStyle: _deps.openTvHomeStyle,
      openTvPlayerControlsStylePage: _deps.openTvPlayerControlsStylePage,
      openTvRenderQuality: _deps.openTvRenderQuality,
      openTvScreenSize: _deps.openTvScreenSize,
      openTvSidebarStyle: _deps.openTvSidebarStyle,
      pikpakInfo: _deps.pikpakInfo,
      premiumizeInfo: _deps.premiumizeInfo,
      rdInfo: _deps.rdInfo,
      resetAppData: _deps.resetAppData,
      restoreBackup: _deps.restoreBackup,
      simklInfo: _deps.simklInfo,
      switchProfile: _deps.switchProfile,
      themeTokensLabel: _deps.themeTokensLabel,
      toggleAutoUpdateChecks: _deps.toggleAutoUpdateChecks,
      toggleIncludeAlphaUpdates: _deps.toggleIncludeAlphaUpdates,
      toggleTvKeyboard: _deps.toggleTvKeyboard,
      torboxInfo: _deps.torboxInfo,
      trackingInfo: _deps.trackingInfo,
      traktInfo: _deps.traktInfo,
      webDavInfo: _deps.webDavInfo,
    ));
    return [
      ...b.indexSlice1(),
      ...b.indexSlice2(),
      ...b.indexSlice3(),
      ...b.indexSlice4(),
      ...b.indexSlice5(),
      ...b.indexSlice6(),
      ...b.indexSlice7(),
      ...b.indexSlice8(),
      ...b.indexSlice9(),
      ...b.indexSlice10(),
      ...b.indexSlice11(),
    ];
  }

  /// Sublevel settings that live *inside* a subpage (cache checks, post-torrent
  /// action, filters, subtitle options…). Each is grouped under its owning
  /// page's name and deep-links to that page (no scroll-to-highlight yet), so a
  /// search like "cache" or "post torrent" surfaces every provider's option.
  /// Titles mirror the real in-page labels — keep them in sync if a page's copy
  /// changes.
  List<SettingsSearchEntry> leafSearchEntries() {
    final b = SettingsLeafBuilder(_summaries, (
      context: _deps.context,
      customPlayerCommandSupported: _deps.customPlayerCommandSupported,
      ensureProfileFeature: _deps.ensureProfileFeature,
      isAndroid: _deps.isAndroid,
      isPhone: _deps.isPhone,
      isTelevision: _deps.isTelevision,
      mounted: _deps.mounted,
      openAllDebridSettings: _deps.openAllDebridSettings,
      openDebrifyTvSettings: _deps.openDebrifyTvSettings,
      openExternalPlayerSettings: _deps.openExternalPlayerSettings,
      openFilterSettings: _deps.openFilterSettings,
      openHomePageSettings: _deps.openHomePageSettings,
      openIndexerManagersSettings: _deps.openIndexerManagersSettings,
      openIptvAddSource: _deps.openIptvAddSource,
      openIptvChannelOrder: _deps.openIptvChannelOrder,
      openIptvSettings: _deps.openIptvSettings,
      openLaunchAnimationPage: _deps.openLaunchAnimationPage,
      openMdblistSettings: _deps.openMdblistSettings,
      openPikPakSettings: _deps.openPikPakSettings,
      openPlaybackSection: _deps.openPlaybackSection,
      openPremiumizeSettings: _deps.openPremiumizeSettings,
      openProfileAppearance: _deps.openProfileAppearance,
      openProviderSettings: _deps.openProviderSettings,
      openQuickPlaySettings: _deps.openQuickPlaySettings,
      openRealDebridSettings: _deps.openRealDebridSettings,
      openRecordings: _deps.openRecordings,
      openRemoteControl: _deps.openRemoteControl,
      openSidebarCustomization: _deps.openSidebarCustomization,
      openSimklSettings: _deps.openSimklSettings,
      openStremioTvSettings: _deps.openStremioTvSettings,
      openThemeTokensPage: _deps.openThemeTokensPage,
      openTorboxSettings: _deps.openTorboxSettings,
      openTorrentSettings: _deps.openTorrentSettings,
      openTrackingSettings: _deps.openTrackingSettings,
      openTraktSettings: _deps.openTraktSettings,
      openWebDavSettings: _deps.openWebDavSettings,
      preferredExternalPlayerSupported: _deps.preferredExternalPlayerSupported,
      recordingSupported: _deps.recordingSupported,
      switchProfile: _deps.switchProfile,
    ));
    return [
      ...b.leafSlice1(),
      ...b.leafSlice2(),
      ...b.leafSlice3(),
      ...b.leafSlice4(),
      ...b.leafSlice5(),
      ...b.leafSlice6(),
      ...b.leafSlice7(),
      ...b.leafSlice8(),
      ...b.leafSlice9(),
      ...b.leafSlice10(),
      ...b.leafSlice11(),
    ];
  }
}
