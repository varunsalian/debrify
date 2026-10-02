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
import 'package:debrify/features/settings/presentation/legacy_settings/settings_search_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summaries.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_updates.dart';
import 'package:debrify/features/settings/presentation/settings_layout.dart';
import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:debrify/screens/settings/app_theme_page.dart';
import 'package:debrify/screens/settings/debrify_tv_player_style_page.dart';
import 'package:debrify/screens/settings/debrify_tv_style_page.dart';
import 'package:debrify/screens/settings/desktop_sidebar_style_page.dart';
import 'package:debrify/screens/settings/detail_page_style_page.dart';
import 'package:debrify/screens/settings/detail_theme_page.dart';
import 'package:debrify/screens/settings/discover_layout_page.dart';
import 'package:debrify/screens/settings/iptv_style_page.dart';
import 'package:debrify/screens/settings/parents_guide_style_page.dart';
import 'package:debrify/screens/settings/play_loader_style_page.dart';
import 'package:debrify/screens/settings/player_dock_page.dart';
import 'package:debrify/screens/settings/player_guide_style_page.dart';
import 'package:debrify/screens/settings/settings_tv_layout.dart';
import 'package:debrify/screens/settings/text_brightness_page.dart';
import 'package:debrify/screens/settings/tv_hero_artwork_quality_page.dart';
import 'package:debrify/screens/settings/tv_home_style_page.dart';
import 'package:debrify/screens/settings/tv_player_controls_style_page.dart';
import 'package:debrify/screens/settings/tv_sidebar_style_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/theme/app_looks.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/widgets/launch/launch_ident.dart';
import 'package:flutter/material.dart';

/// Composes the existing TV and adaptive trees from live borrowed sections.
class SettingsLayoutComposition {
  SettingsLayoutComposition(
    this._summaries,
    this._firstCardFocusNode,
    this._sections,
  );
  final SettingsSummaries _summaries;
  final FocusNode _firstCardFocusNode;
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
    SettingsSearchNavigation Function() searchNavigation,
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
  SettingsSearchNavigation get _searchNavigation =>
      _sections.searchNavigation();
  SettingsUpdates get _updates => _sections.updates();

  Widget buildTvLayout() {
    return SettingsTvLayout(
      connections: [
        _connections.rdInfo,
        _connections.torboxInfo,
        _connections.premiumizeInfo,
        _connections.allDebridInfo,
        _connections.pikpakInfo,
        _connections.webDavInfo,
        _connections.mediaServersInfo,
        _connections.iptvInfo,
        _connections.indexerManagersInfo,
      ],
      // Watch history lives on its own rail category — Connections had grown
      // to ten cards covering five unrelated jobs.
      tracking: _connections.trackingInfo,
      trackers: [
        _connections.traktInfo,
        _connections.simklInfo,
        // MDBList hidden for the alpha (unfinished) — see [kMdblistEnabled].
        if (kMdblistEnabled) _connections.mdblistInfo,
      ],
      firstFocusNode: _firstCardFocusNode,
      onOpenSearch: _searchNavigation.openSettingsSearch,
      onOpenHomePageSettings: _pageNavigation.openHomePageSettings,
      onOpenMetadataSettings: _pageNavigation.openMetadataSettings,
      onOpenCollectionsSettings: _pageNavigation.openCollectionsSettings,
      onOpenBadgesSettings: _pageNavigation.openBadgesSettings,
      onOpenPlaybackSection: _pageNavigation.openPlaybackSection,
      onOpenRemoteControl: _pageNavigation.openRemoteControl,
      showSwitchProfile:
          ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted,
      onSwitchProfile: _profileActions.switchProfile,
      onAddProfile: _profileActions.addProfile,
      onEditProfile: _profileActions.editActiveProfile,
      onOpenTorrentSettings: _connectionNavigation.openTorrentSettings,
      onOpenFilterSettings: _pageNavigation.openFilterSettings,
      onOpenProviderSettings: _pageNavigation.openProviderSettings,
      onOpenQuickPlaySettings: _pageNavigation.openQuickPlaySettings,
      onOpenDiscoverSettings: _pageNavigation.openDiscoverSettings,
      onOpenDebrifyTvSettings: _connectionNavigation.openDebrifyTvSettings,
      onClearDownloads: _maintenance.clearDownloadData,
      onClearPlayback: _maintenance.clearPlaybackData,
      onOpenDownloadLocation: _downloadLocation.downloadLocationSupported
          ? _downloadLocation.openDownloadLocationSettings
          : null,
      downloadLocationSubtitle: _summaries.downloadLocationSubtitle,
      onCreateBackup: _backup.createBackup,
      onRestoreBackup: _restore.restoreBackup,
      onOpenSyncAndMigrate: _profileActions.openSyncAndMigrate,
      onExportDiagnosticLogs: _summaries.diagnosticExportVisible
          ? _diagnostics.exportDiagnosticLogs
          : null,
      onDangerAction: _maintenance.resetAppData,
      appVersion: _summaries.appVersion,
      onCheckForUpdates: _updates.checkForAppUpdates,
      updateSubtitle: _summaries.updateSubtitle,
      checkingUpdates: _summaries.checkingUpdates,
      autoUpdateChecksEnabled: _summaries.autoUpdateChecksEnabled,
      onToggleAutoUpdateChecks: _updates.toggleAutoUpdateChecks,
      includeAlphaUpdates: _summaries.includeAlphaUpdates,
      onToggleIncludeAlphaUpdates: _updates.toggleIncludeAlphaUpdates,
      tvKeyboardEnabled: _summaries.tvKeyboardEnabled,
      onToggleTvKeyboard: _appearanceNavigation.toggleTvKeyboard,
      textBrightnessLabel: textBrightnessLabel(_summaries.textBrightness),
      onOpenTextBrightness: _appearanceNavigation.openTextBrightnessPage,
      launchAnimationLabel: launchIdentLabel(_summaries.launchAnimation),
      onOpenLaunchAnimation: _appearanceNavigation.openLaunchAnimationPage,
      tvUiScalePercent: _summaries.tvUiScalePercent,
      onOpenTvScreenSize: _appearanceNavigation.openTvScreenSize,
      tvRenderQualityLabel: tvRenderQualityLabel(_summaries.tvRenderQuality),
      onOpenTvRenderQuality: _appearanceNavigation.openTvRenderQuality,
      tvHeroArtworkQualityLabel: tvHeroArtworkQualityLabel(
        _summaries.tvHeroArtworkQuality,
      ),
      onOpenTvHeroArtworkQuality:
          _appearanceNavigation.openTvHeroArtworkQuality,
      tvSidebarStyleLabel: tvSidebarStyleLabel(_summaries.tvSidebarStyle),
      onOpenTvSidebarStyle: _appearanceNavigation.openTvSidebarStyle,
      discoverLayoutLabel: discoverLayoutLabel(_summaries.discoverLayout),
      onOpenDiscoverLayout: _appearanceNavigation.openDiscoverLayout,
      onOpenCollectionListStyle: _appearanceNavigation.openCollectionListStyle,
      tvHomeStyleLabel: tvHomeStyleLabel(_summaries.tvHomeStyle),
      onOpenTvHomeStyle: _appearanceNavigation.openTvHomeStyle,
      profileAppearanceLabel: ProfileGateStyle.labelFor(
        ProfileGateStyle.cached,
      ),
      onOpenProfileAppearance: _appearanceNavigation.openProfileAppearance,
      iptvStyleLabel: iptvStyleLabel(_summaries.iptvStyle),
      onOpenIptvStyle: _appearanceNavigation.openIptvStylePage,
      debrifyTvStyleLabel: debrifyTvStyleLabel(_summaries.debrifyTvStyle),
      onOpenDebrifyTvStyle: _appearanceNavigation.openDebrifyTvStylePage,
      playerGuideStyleLabel: playerGuideStyleLabel(_summaries.playerGuideStyle),
      playLoaderStyleLabel: playLoaderStyleLabel(_summaries.playLoaderStyle),
      onOpenPlayLoaderStyle: _appearanceNavigation.openPlayLoaderStylePage,
      onOpenPlayerGuideStyle: _appearanceNavigation.openPlayerGuideStylePage,
      tvPlayerControlsStyleLabel: tvPlayerControlsStyleLabel(
        _summaries.tvPlayerControlsStyle,
      ),
      onOpenTvPlayerControlsStyle:
          _appearanceNavigation.openTvPlayerControlsStylePage,
      debrifyTvPlayerStyleLabel: debrifyTvPlayerStyleLabel(
        _summaries.debrifyTvPlayerStyle,
      ),
      onOpenDebrifyTvPlayerStyle:
          _appearanceNavigation.openDebrifyTvPlayerStylePage,
      detailPageStyleLabel: detailPageStyleLabel(_summaries.detailPageStyle),
      onOpenDetailPageStyle: _appearanceNavigation.openDetailPageStylePage,
      appThemeLabel: appThemeLabel(AppThemeController.instance.id),
      looksLabel: AppLooks.active()?.label ?? 'Custom',
      onOpenLooks: _appearanceNavigation.openLooksPage,
      onOpenThemeTokens: _appearanceNavigation.openThemeTokensPage,
      themeTokensLabel: _appearanceNavigation.themeTokensLabel,
      onOpenThemeLab: _appearanceNavigation.openThemeLab,
      onOpenAppTheme: _appearanceNavigation.openAppThemePage,
      detailThemeLabel: detailThemeLabel(_summaries.detailTheme),
      onOpenDetailTheme: _appearanceNavigation.openDetailThemePage,
      parentsGuideStyleLabel: parentsGuideStyleLabel(
        _summaries.parentsGuideStyle,
      ),
      onOpenParentsGuideStyle: _appearanceNavigation.openParentsGuideStylePage,
      onOpenRecordings: _pageNavigation.openRecordings,
      onOpenIptvSettings: _connectionNavigation.openIptvSettings,
      showSupportDonation: _summaries.supportDonation.hasProviders,
      supportDonationLabel: _summaries.supportSettingsLabel,
      supportDonationSubtitle: _summaries.supportSettingsSubtitle,
      onOpenSupportDonation: _pageNavigation.openSupportDonation,
    );
  }

  Widget buildLayout(BuildContext context) {
    return SettingsLayout(
      legacyReasonSummary: () => ProfileBootstrap.legacyReasonSummary,
      connections: ConnectionsSummary(
        realDebrid: _connections.rdInfo,
        torbox: _connections.torboxInfo,
        premiumize: _connections.premiumizeInfo,
        allDebrid: _connections.allDebridInfo,
        pikpak: _connections.pikpakInfo,
        webDav: _connections.webDavInfo,
        mediaServers: _connections.mediaServersInfo,
        iptv: _connections.iptvInfo,
        trakt: _connections.traktInfo,
        simkl: _connections.simklInfo,
        tracking: _connections.trackingInfo,
        // MDBList hidden for the alpha (unfinished) — see [kMdblistEnabled].
        mdblist: kMdblistEnabled ? _connections.mdblistInfo : null,
        indexerManagers: _connections.indexerManagersInfo,
        firstCardFocusNode: _firstCardFocusNode,
      ),
      onOpenSearch: _searchNavigation.openSettingsSearch,
      onOpenTorrentSettings: _connectionNavigation.openTorrentSettings,
      onOpenFilterSettings: _pageNavigation.openFilterSettings,
      onOpenProviderSettings: _pageNavigation.openProviderSettings,
      onOpenQuickPlaySettings: _pageNavigation.openQuickPlaySettings,
      onOpenDiscoverSettings: _pageNavigation.openDiscoverSettings,
      onOpenDebrifyTvSettings: _connectionNavigation.openDebrifyTvSettings,
      onOpenPikPakSettings: _connectionNavigation.openPikPakSettings,
      onOpenHomePageSettings: _pageNavigation.openHomePageSettings,
      onOpenMetadataSettings: _pageNavigation.openMetadataSettings,
      onOpenCollectionsSettings: _pageNavigation.openCollectionsSettings,
      onOpenBadgesSettings: _pageNavigation.openBadgesSettings,
      onOpenCollectionListStyle: _appearanceNavigation.openCollectionListStyle,
      onOpenPlaybackSection: _pageNavigation.openPlaybackSection,
      onOpenRemoteControl: _pageNavigation.openRemoteControl,
      showSwitchProfile:
          ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted,
      onSwitchProfile: _profileActions.switchProfile,
      onAddProfile: _profileActions.addProfile,
      onEditProfile: _profileActions.editActiveProfile,
      onOpenNavigationSettings: _connectionNavigation.openNavigationSettings,
      isAndroidTv: _summaries.isAndroidTv,
      onClearDownloads: _maintenance.clearDownloadData,
      onClearPlayback: _maintenance.clearPlaybackData,
      onOpenDownloadLocation: _downloadLocation.downloadLocationSupported
          ? _downloadLocation.openDownloadLocationSettings
          : null,
      downloadLocationSubtitle: _summaries.downloadLocationSubtitle,
      onCreateBackup: _backup.createBackup,
      onRestoreBackup: _restore.restoreBackup,
      onOpenSyncAndMigrate: _profileActions.openSyncAndMigrate,
      onExportDiagnosticLogs: _summaries.diagnosticExportVisible
          ? _diagnostics.exportDiagnosticLogs
          : null,
      onDangerAction: _maintenance.resetAppData,
      appVersion: _summaries.appVersion,
      onCheckForUpdates: _updates.checkForAppUpdates,
      updateSubtitle: _summaries.updateSubtitle,
      checkingUpdates: _summaries.checkingUpdates,
      autoUpdateChecksEnabled: _summaries.autoUpdateChecksEnabled,
      onToggleAutoUpdateChecks: _updates.toggleAutoUpdateChecks,
      includeAlphaUpdates: _summaries.includeAlphaUpdates,
      onToggleIncludeAlphaUpdates: _updates.toggleIncludeAlphaUpdates,
      tvKeyboardEnabled: _summaries.tvKeyboardEnabled,
      onToggleTvKeyboard: _appearanceNavigation.toggleTvKeyboard,
      showSupportDonation: _summaries.supportDonation.hasProviders,
      supportDonationLabel: _summaries.supportSettingsLabel,
      supportDonationSubtitle: _summaries.supportSettingsSubtitle,
      onOpenSupportDonation: _pageNavigation.openSupportDonation,
      onOpenRecordings: _pageNavigation.openRecordings,
      onOpenIptvSettings: _connectionNavigation.openIptvSettings,
      showIptvAppearance: _platformGates.iptvAppearanceSearchable,
      textBrightnessLabel: textBrightnessLabel(_summaries.textBrightness),
      onOpenTextBrightness: _appearanceNavigation.openTextBrightnessPage,
      launchAnimationLabel: launchIdentLabel(_summaries.launchAnimation),
      onOpenLaunchAnimation: _appearanceNavigation.openLaunchAnimationPage,
      iptvStyleLabel: iptvStyleLabel(_summaries.iptvStyle),
      onOpenIptvStyle: _appearanceNavigation.openIptvStylePage,
      debrifyTvStyleLabel: debrifyTvStyleLabel(_summaries.debrifyTvStyle),
      onOpenDebrifyTvStyle: _appearanceNavigation.openDebrifyTvStylePage,
      playerGuideStyleLabel: playerGuideStyleLabel(_summaries.playerGuideStyle),
      playLoaderStyleLabel: playLoaderStyleLabel(_summaries.playLoaderStyle),
      onOpenPlayLoaderStyle: _appearanceNavigation.openPlayLoaderStylePage,
      playerDockLabel: playerDockLabel(
        _summaries.playerDockStyle,
        _summaries.playerDockPalette,
        _summaries.playerDockSize,
      ),
      onOpenPlayerDock: _appearanceNavigation.openPlayerDockPage,
      onOpenPlayerGuideStyle: _appearanceNavigation.openPlayerGuideStylePage,
      detailPageStyleLabel: detailPageStyleLabel(_summaries.detailPageStyle),
      onOpenDetailPageStyle: _appearanceNavigation.openDetailPageStylePage,
      appThemeLabel: appThemeLabel(AppThemeController.instance.id),
      onOpenLooks: _appearanceNavigation.openLooksPage,
      onOpenThemeTokens: _appearanceNavigation.openThemeTokensPage,
      themeTokensLabel: _appearanceNavigation.themeTokensLabel,
      onOpenThemeLab: _appearanceNavigation.openThemeLab,
      onOpenAppTheme: _appearanceNavigation.openAppThemePage,
      detailThemeLabel: detailThemeLabel(_summaries.detailTheme),
      onOpenDetailTheme: _appearanceNavigation.openDetailThemePage,
      parentsGuideStyleLabel: parentsGuideStyleLabel(
        _summaries.parentsGuideStyle,
      ),
      onOpenParentsGuideStyle: _appearanceNavigation.openParentsGuideStylePage,
      phoneNavStyleLabel: _summaries.phoneNavStyle == 'floating'
          ? 'Floating button'
          : 'Classic bar',
      desktopSidebarStyleLabel: desktopSidebarStyleLabel(
        _summaries.desktopSidebarStyle,
      ),
      onOpenDesktopSidebarStyle: _appearanceNavigation.openDesktopSidebarStyle,
      profileAppearanceLabel: ProfileGateStyle.labelFor(
        ProfileGateStyle.cached,
      ),
      onOpenProfileAppearance: _appearanceNavigation.openProfileAppearance,
    );
  }
}
