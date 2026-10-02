import 'package:debrify/features/settings/presentation/legacy_settings/search_index/settings_search_index.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_backup.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_connection_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_connections.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_diagnostics.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_download_location.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_maintenance.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_page_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_platform_gates.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_profile_actions.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_restore.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summaries.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_updates.dart';
import 'package:flutter/material.dart';

/// Wiring for the search index; section getters retain their existing lazy reads.
class SettingsIndexComposition {
  SettingsIndexComposition(this._summaries, this._deps, this._sections);
  final SettingsSummaries _summaries;
  final ({BuildContext Function() context, bool Function() mounted}) _deps;
  final ({
    SettingsAppearanceNavigation Function() appearanceNavigation,
    SettingsBackup Function() backup,
    SettingsConnectionNavigation Function() connectionNavigation,
    SettingsConnections Function() connections,
    SettingsDiagnostics Function() diagnostics,
    SettingsDownloadLocation Function() downloadLocation,
    SettingsMaintenance Function() maintenance,
    SettingsPageNavigation Function() pageNavigation,
    SettingsPlatformGates Function() platformGates,
    SettingsProfileActions Function() profileActions,
    SettingsRestore Function() restore,
    SettingsUpdates Function() updates,
  })
  _sections;
  SettingsAppearanceNavigation get _appearanceNavigation =>
      _sections.appearanceNavigation();
  SettingsBackup get _backup => _sections.backup();
  SettingsConnectionNavigation get _connectionNavigation =>
      _sections.connectionNavigation();
  SettingsConnections get _connections => _sections.connections();
  SettingsDiagnostics get _diagnostics => _sections.diagnostics();
  SettingsDownloadLocation get _downloadLocation =>
      _sections.downloadLocation();
  SettingsMaintenance get _maintenance => _sections.maintenance();
  SettingsPageNavigation get _pageNavigation => _sections.pageNavigation();
  SettingsPlatformGates get _platformGates => _sections.platformGates();
  SettingsProfileActions get _profileActions => _sections.profileActions();
  SettingsRestore get _restore => _sections.restore();
  SettingsUpdates get _updates => _sections.updates();

  late final SettingsSearchIndex searchIndex = SettingsSearchIndex(_summaries, (
    addProfile: _profileActions.addProfile,
    allDebridInfo: () => _connections.allDebridInfo,
    checkForAppUpdates: _updates.checkForAppUpdates,
    clearDownloadData: _maintenance.clearDownloadData,
    clearPlaybackData: _maintenance.clearPlaybackData,
    context: _deps.context,
    createBackup: _backup.createBackup,
    customPlayerCommandSupported: () =>
        _platformGates.customPlayerCommandSupported,
    downloadLocationSupported: () =>
        _downloadLocation.downloadLocationSupported,
    editActiveProfile: _profileActions.editActiveProfile,
    ensureProfileFeature: _profileActions.ensureProfileFeature,
    exportDiagnosticLogs: _diagnostics.exportDiagnosticLogs,
    indexerManagersInfo: () => _connections.indexerManagersInfo,
    iptvAppearanceSearchable: () => _platformGates.iptvAppearanceSearchable,
    iptvInfo: () => _connections.iptvInfo,
    isAndroid: () => _platformGates.isAndroid,
    isPhone: () => _platformGates.isPhone,
    isTelevision: () => _platformGates.isTelevision,
    mdblistInfo: () => _connections.mdblistInfo,
    mediaServersInfo: () => _connections.mediaServersInfo,
    mounted: _deps.mounted,
    openAllDebridSettings: _connectionNavigation.openAllDebridSettings,
    openBadgesSettings: _pageNavigation.openBadgesSettings,
    openCollectionListStyle: _appearanceNavigation.openCollectionListStyle,
    openCollectionsSettings: _pageNavigation.openCollectionsSettings,
    openDebrifyTvPlayerStylePage:
        _appearanceNavigation.openDebrifyTvPlayerStylePage,
    openDebrifyTvSettings: _connectionNavigation.openDebrifyTvSettings,
    openDebrifyTvStylePage: _appearanceNavigation.openDebrifyTvStylePage,
    openDesktopSidebarStyle: _appearanceNavigation.openDesktopSidebarStyle,
    openDetailPageStylePage: _appearanceNavigation.openDetailPageStylePage,
    openDiscoverLayout: _appearanceNavigation.openDiscoverLayout,
    openDiscoverSettings: _pageNavigation.openDiscoverSettings,
    openDownloadLocationSettings:
        _downloadLocation.openDownloadLocationSettings,
    openExternalPlayerSettings: _pageNavigation.openExternalPlayerSettings,
    openFilterSettings: _pageNavigation.openFilterSettings,
    openHomePageSettings: _pageNavigation.openHomePageSettings,
    openIndexerManagersSettings:
        _connectionNavigation.openIndexerManagersSettings,
    openIptvAddSource: _connectionNavigation.openIptvAddSource,
    openIptvChannelOrder: _connectionNavigation.openIptvChannelOrder,
    openIptvSettings: _connectionNavigation.openIptvSettings,
    openIptvStylePage: _appearanceNavigation.openIptvStylePage,
    openLaunchAnimationPage: _appearanceNavigation.openLaunchAnimationPage,
    openLooksPage: _appearanceNavigation.openLooksPage,
    openMdblistSettings: _connectionNavigation.openMdblistSettings,
    openMetadataSettings: _pageNavigation.openMetadataSettings,
    openNavigationSettings: _connectionNavigation.openNavigationSettings,
    openParentsGuideStylePage: _appearanceNavigation.openParentsGuideStylePage,
    openPikPakSettings: _connectionNavigation.openPikPakSettings,
    openPlayLoaderStylePage: _appearanceNavigation.openPlayLoaderStylePage,
    openPlaybackSection: _pageNavigation.openPlaybackSection,
    openPlayerDockPage: _appearanceNavigation.openPlayerDockPage,
    openPlayerGuideStylePage: _appearanceNavigation.openPlayerGuideStylePage,
    openPremiumizeSettings: _connectionNavigation.openPremiumizeSettings,
    openProfileAppearance: _appearanceNavigation.openProfileAppearance,
    openProviderSettings: _pageNavigation.openProviderSettings,
    openQuickPlaySettings: _pageNavigation.openQuickPlaySettings,
    openRealDebridSettings: _connectionNavigation.openRealDebridSettings,
    openRecordings: _pageNavigation.openRecordings,
    openRemoteControl: _pageNavigation.openRemoteControl,
    openSidebarCustomization: _appearanceNavigation.openSidebarCustomization,
    openSimklSettings: _connectionNavigation.openSimklSettings,
    openStremioTvSettings: _connectionNavigation.openStremioTvSettings,
    openSupportDonation: _pageNavigation.openSupportDonation,
    openSyncAndMigrate: _profileActions.openSyncAndMigrate,
    openTextBrightnessPage: _appearanceNavigation.openTextBrightnessPage,
    openThemeTokensPage: _appearanceNavigation.openThemeTokensPage,
    openTorboxSettings: _connectionNavigation.openTorboxSettings,
    openTorrentSettings: _connectionNavigation.openTorrentSettings,
    openTrackingSettings: _connectionNavigation.openTrackingSettings,
    openTraktSettings: _connectionNavigation.openTraktSettings,
    openTvHeroArtworkQuality: _appearanceNavigation.openTvHeroArtworkQuality,
    openTvHomeStyle: _appearanceNavigation.openTvHomeStyle,
    openTvPlayerControlsStylePage:
        _appearanceNavigation.openTvPlayerControlsStylePage,
    openTvRenderQuality: _appearanceNavigation.openTvRenderQuality,
    openTvScreenSize: _appearanceNavigation.openTvScreenSize,
    openTvSidebarStyle: _appearanceNavigation.openTvSidebarStyle,
    openWebDavSettings: _connectionNavigation.openWebDavSettings,
    pikpakInfo: () => _connections.pikpakInfo,
    preferredExternalPlayerSupported: () =>
        _platformGates.preferredExternalPlayerSupported,
    premiumizeInfo: () => _connections.premiumizeInfo,
    rdInfo: () => _connections.rdInfo,
    recordingSupported: () => _platformGates.recordingSupported,
    resetAppData: _maintenance.resetAppData,
    restoreBackup: _restore.restoreBackup,
    simklInfo: () => _connections.simklInfo,
    switchProfile: _profileActions.switchProfile,
    themeTokensLabel: () => _appearanceNavigation.themeTokensLabel,
    toggleAutoUpdateChecks: _updates.toggleAutoUpdateChecks,
    toggleIncludeAlphaUpdates: _updates.toggleIncludeAlphaUpdates,
    toggleTvKeyboard: _appearanceNavigation.toggleTvKeyboard,
    torboxInfo: () => _connections.torboxInfo,
    trackingInfo: () => _connections.trackingInfo,
    traktInfo: () => _connections.traktInfo,
    webDavInfo: () => _connections.webDavInfo,
  ));
}
