import 'package:debrify/features/settings/presentation/legacy_settings/search_index/settings_search_index.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_platform_gates.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_search_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summary_refresh.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summary_loader.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_account_captions.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_updates.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_diagnostics.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_page_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_connection_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_profile_actions.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_backup.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_restore.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_download_location.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_maintenance.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_release_details.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_snacks.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_summaries.dart';
import 'package:debrify/features/settings/presentation/legacy_settings/settings_connections.dart';
import 'package:debrify/features/settings/presentation/settings_layout.dart';
export 'package:debrify/features/settings/application/settings_pending_credentials.dart' show shouldApplyPendingCredentialOverride;
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';

import '../models/profiles/profile_policy.dart';
import '../services/main_page_bridge.dart';
import '../services/profiles/profile_runtime.dart';
import '../services/profiles/profile_bootstrap.dart';

import '../services/analytics_service.dart';
import '../services/mdblist/mdblist_service.dart';
import '../services/live_recording_service.dart';
import '../services/update_service.dart';
import 'settings/settings_tv_layout.dart';
import 'settings/settings_search.dart';
import 'settings/discover_layout_page.dart';
import 'settings/iptv_style_page.dart';
import 'settings/debrify_tv_style_page.dart';
import 'settings/text_brightness_page.dart';
import '../widgets/launch/launch_ident.dart';
import 'settings/detail_page_style_page.dart';
import 'settings/app_theme_page.dart';
import 'settings/detail_theme_page.dart';
import '../theme/app_theme_controller.dart';
import 'settings/parents_guide_style_page.dart';
import 'settings/player_dock_page.dart';
import 'settings/play_loader_style_page.dart';
import 'settings/player_guide_style_page.dart';
import 'settings/tv_player_controls_style_page.dart';
import 'settings/debrify_tv_player_style_page.dart';
import 'settings/tv_home_style_page.dart';
import 'settings/tv_hero_artwork_quality_page.dart';
import 'settings/desktop_sidebar_style_page.dart';
import 'settings/tv_sidebar_style_page.dart';
import 'settings/widgets/settings_widgets.dart';
import 'profiles/profile_wall_screen.dart';
import '../theme/app_looks.dart';

/// Test access to the production builders and a delayed completion helper.
@visibleForTesting
({
  List<SettingsSearchEntry> Function() index,
  List<SettingsSearchEntry> Function() leaves,
  void Function(String) snack,
}) settingsScreenTestAccess(State<SettingsScreen> state) {
  final settings = state as _SettingsScreenState;
  return (
    index: settings._searchIndex.buildSearchIndex,
    leaves: settings._searchIndex.leafSearchEntries,
    snack: settings._snacks.showSnack,
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.summaryReadOverrides = const {}});

  @visibleForTesting
  final Map<String, Future<Object?> Function()> summaryReadOverrides;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsSearchIndex _searchIndex = SettingsSearchIndex(
  _summaries,
  (
    addProfile: _profileActions.addProfile,
    allDebridInfo: () => _connections.allDebridInfo,
    checkForAppUpdates: _updates.checkForAppUpdates,
    clearDownloadData: _maintenance.clearDownloadData,
    clearPlaybackData: _maintenance.clearPlaybackData,
    context: () => context,
    createBackup: _backup.createBackup,
    customPlayerCommandSupported: () => _platformGates.customPlayerCommandSupported,
    downloadLocationSupported: () => _downloadLocation.downloadLocationSupported,
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
    mounted: () => mounted,
    openAllDebridSettings: _connectionNavigation.openAllDebridSettings,
    openBadgesSettings: _pageNavigation.openBadgesSettings,
    openCollectionListStyle: _appearanceNavigation.openCollectionListStyle,
    openCollectionsSettings: _pageNavigation.openCollectionsSettings,
    openDebrifyTvPlayerStylePage: _appearanceNavigation.openDebrifyTvPlayerStylePage,
    openDebrifyTvSettings: _connectionNavigation.openDebrifyTvSettings,
    openDebrifyTvStylePage: _appearanceNavigation.openDebrifyTvStylePage,
    openDesktopSidebarStyle: _appearanceNavigation.openDesktopSidebarStyle,
    openDetailPageStylePage: _appearanceNavigation.openDetailPageStylePage,
    openDiscoverLayout: _appearanceNavigation.openDiscoverLayout,
    openDiscoverSettings: _pageNavigation.openDiscoverSettings,
    openDownloadLocationSettings: _downloadLocation.openDownloadLocationSettings,
    openExternalPlayerSettings: _pageNavigation.openExternalPlayerSettings,
    openFilterSettings: _pageNavigation.openFilterSettings,
    openHomePageSettings: _pageNavigation.openHomePageSettings,
    openIndexerManagersSettings: _connectionNavigation.openIndexerManagersSettings,
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
    openTvPlayerControlsStylePage: _appearanceNavigation.openTvPlayerControlsStylePage,
    openTvRenderQuality: _appearanceNavigation.openTvRenderQuality,
    openTvScreenSize: _appearanceNavigation.openTvScreenSize,
    openTvSidebarStyle: _appearanceNavigation.openTvSidebarStyle,
    openWebDavSettings: _connectionNavigation.openWebDavSettings,
    pikpakInfo: () => _connections.pikpakInfo,
    preferredExternalPlayerSupported: () => _platformGates.preferredExternalPlayerSupported,
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
  ),
);
  late final SettingsPlatformGates _platformGates = SettingsPlatformGates(
    _summaries,
  );
  late final SettingsSearchNavigation _searchNavigation = SettingsSearchNavigation(
    (
      buildSearchIndex: () => _searchIndex.buildSearchIndex(),
      context: () => context,
      mounted: () => mounted,
      setState: setState,
    ),
  );
  late final SettingsSummaryRefresh _summaryRefresh = SettingsSummaryRefresh(
    _summaries,
    (
      loadSummariesForCurrentProfile: () => _summaryLoader.loadSummariesForCurrentProfile(),
      defaultDownloadLocationLabel: () => _downloadLocation.defaultDownloadLocationLabel,
      downloadLocationSupported: () => _downloadLocation.downloadLocationSupported,
      downloadLocationUsesSaf: () => _downloadLocation.downloadLocationUsesSaf,
      mounted: () => mounted,
      setState: setState,
    ),
  );
  late final SettingsSummaryLoader _summaryLoader = SettingsSummaryLoader(
    _summaries,
    (
      applyAllDebridUserInfo: (dynamic allDebridUser) => _accountCaptions.applyAllDebridUserInfo(allDebridUser),
      applyPremiumizeUserInfo: (dynamic premiumizeUser) => _accountCaptions.applyPremiumizeUserInfo(premiumizeUser),
      applyRdUserInfo: (dynamic user) => _accountCaptions.applyRdUserInfo(user),
      applyTorboxUserInfo: (dynamic torboxUser) => _accountCaptions.applyTorboxUserInfo(torboxUser),
      pendingCredentialTypes: () => _summaryRefresh.pendingCredentialTypes(),
      activeProfileMayExportDiagnostics: () => _diagnostics.activeProfileMayExportDiagnostics(),
      mounted: () => mounted,
      setState: setState,
      summaryReadOverrides: () => widget.summaryReadOverrides,
    ),
  );
  late final SettingsAccountCaptions _accountCaptions = SettingsAccountCaptions(
    _summaries,
  );
  late final SettingsUpdates _updates = SettingsUpdates(
    _summaries,
    (
      ensureProfileFeature: (ProfileFeature feature) => _profileActions.ensureProfileFeature(feature),
      showReleaseDetails: (UpdateSummary summary) => _releaseDetails.showReleaseDetails(summary),
      showSnack: (String message) => _snacks.showSnack(message),
      mounted: () => mounted,
      setState: setState,
    ),
  );
  late final SettingsDiagnostics _diagnostics = SettingsDiagnostics(
    _summaries,
    (
      context: () => context,
      mounted: () => mounted,
      setState: setState,
    ),
  );
  late final SettingsPageNavigation _pageNavigation = SettingsPageNavigation(
    _summaries,
    (
      ensureProfileFeature: (ProfileFeature feature) => _profileActions.ensureProfileFeature(feature),
      reloadAppearanceSummaries: () => _summaryRefresh.reloadAppearanceSummaries(),
      context: () => context,
      mounted: () => mounted,
      setState: setState,
    ),
  );
  late final SettingsConnectionNavigation _connectionNavigation = SettingsConnectionNavigation(
    _summaries,
    (
      ensureProfileFeature: (ProfileFeature feature) => _profileActions.ensureProfileFeature(feature),
      focusFirstCard: () => focusFirstCard(),
      loadSummaries: () => _summaryRefresh.loadSummaries(),
      reloadAppearanceSummaries: () => _summaryRefresh.reloadAppearanceSummaries(),
      context: () => context,
      mounted: () => mounted,
      setState: setState,
    ),
  );
  late final SettingsProfileActions _profileActions = SettingsProfileActions(
    _summaries,
    (
      activeProfileMayExportDiagnostics: () => _diagnostics.activeProfileMayExportDiagnostics(),
      loadSummaries: () => _summaryRefresh.loadSummaries(),
      context: () => context,
      mounted: () => mounted,
      setState: setState,
    ),
  );
  late final SettingsBackup _backup = SettingsBackup(
    (
      createProfileBackup: () => _profileActions.createProfileBackup(),
      context: () => context,
      mounted: () => mounted,
    ),
  );
  late final SettingsRestore _restore = SettingsRestore(
    (
      loadSummaries: () => _summaryRefresh.loadSummaries(),
      restoreProfileBackup: () => _profileActions.restoreProfileBackup(),
      context: () => context,
      mounted: () => mounted,
    ),
  );
  late final SettingsDownloadLocation _downloadLocation = SettingsDownloadLocation(
    _summaries,
    (
      loadDownloadLocation: () => _summaryRefresh.loadDownloadLocation(),
      context: () => context,
      mounted: () => mounted,
    ),
  );
  late final SettingsMaintenance _maintenance = SettingsMaintenance(
    (
      loadSummaries: () => _summaryRefresh.loadSummaries(),
      context: () => context,
      mounted: () => mounted,
    ),
  );
  late final SettingsReleaseDetails _releaseDetails = SettingsReleaseDetails(
    _summaries,
    (
      openReleasesPage: (Uri url) => _updates.openReleasesPage(url),
      startAndroidUpdateDownload: (AppRelease release) => _updates.startAndroidUpdateDownload(release),
      context: () => context,
      mounted: () => mounted,
    ),
  );
  late final SettingsAppearanceNavigation _appearanceNavigation = SettingsAppearanceNavigation(
    _summaries,
    (
      context: () => context,
      mounted: () => mounted,
      setState: setState,
    ),
  );
  late final SettingsSnacks _snacks = SettingsSnacks(
    (
      context: () => context,
      mounted: () => mounted,
    ),
  );
  final SettingsSummaries _summaries = SettingsSummaries();
  late final SettingsConnections _connections = SettingsConnections(
    _summaries,
    (
      openAllDebridSettings: _connectionNavigation.openAllDebridSettings,
      openIndexerManagersSettings: _connectionNavigation.openIndexerManagersSettings,
      openIptvSettings: _connectionNavigation.openIptvSettings,
      openMdblistSettings: _connectionNavigation.openMdblistSettings,
      openMediaServerSettings: _connectionNavigation.openMediaServerSettings,
      openPikPakSettings: _connectionNavigation.openPikPakSettings,
      openPremiumizeSettings: _connectionNavigation.openPremiumizeSettings,
      openRealDebridSettings: _connectionNavigation.openRealDebridSettings,
      openSimklSettings: _connectionNavigation.openSimklSettings,
      openTorboxSettings: _connectionNavigation.openTorboxSettings,
      openTrackingSettings: _connectionNavigation.openTrackingSettings,
      openTraktSettings: _connectionNavigation.openTraktSettings,
      openWebDavSettings: _connectionNavigation.openWebDavSettings,
    ),
  );

  // Focus node for the first connection card (Real-Debrid) for TV navigation
  final FocusNode _firstCardFocusNode = FocusNode(debugLabel: 'firstCardFocus');

  // ── Platform gates for search entries ───────────────────────────────────
  // A search result must never open a page that has no matching control, so
  // any indexed row whose page renders it conditionally is gated on the SAME
  // condition the page uses.

  // TV content focus handler (stored for proper unregistration)
  VoidCallback? _tvContentFocusHandler;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('settings');
    _summaryRefresh.loadSummaries();
    _summaryRefresh.loadSupportConfig();
    _summaryRefresh.loadDownloadLocation();
    // IPTV recording exists where its engine can run (Android 10+, or pre-Q
    // with the grantable legacy storage path) — the search index must not
    // advertise it elsewhere.
    if (!kIsWeb && Platform.isAndroid) {
      LiveRecordingService.engineSupport().then((support) {
        if (support != 'unsupported' && mounted) {
          setState(() => _summaries.recordingSearchable = true);
        }
      });
    }

    // Register TV sidebar focus handler (tab index 8 = Settings)
    _tvContentFocusHandler = () {
      _firstCardFocusNode.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(8, _tvContentFocusHandler!);
  }

  @override
  void dispose() {
    if (_tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        8,
        _tvContentFocusHandler!,
      );
    }
    _firstCardFocusNode.dispose();
    _updates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The whole tab renders under the scoped settings theme so inline
    // Material widgets (progress spinners, switches) match the subpages.
    // Dialogs shown from this State's context sit ABOVE this Theme, so they
    // go through showSettingsDialog instead.
    if (_summaries.loading) {
      return Theme(
        data: settingsPageTheme(context),
        child: const SettingsSkeleton(),
      );
    }

    return Theme(
      data: settingsPageTheme(context),
      child: Column(
        children: [
          if (_summaries.summaryLoadFailed || _summaries.summaryFailures.isNotEmpty)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  "Some items couldn't load — open them to retry or sign in.",
                  key: const ValueKey('settings-summary-attention'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          Expanded(
            child: _summaries.isAndroidTv ? _buildTvLayout() : _buildLayout(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTvLayout() {
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
      onOpenTvHeroArtworkQuality: _appearanceNavigation.openTvHeroArtworkQuality,
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
      onOpenTvPlayerControlsStyle: _appearanceNavigation.openTvPlayerControlsStylePage,
      debrifyTvPlayerStyleLabel: debrifyTvPlayerStyleLabel(
        _summaries.debrifyTvPlayerStyle,
      ),
      onOpenDebrifyTvPlayerStyle: _appearanceNavigation.openDebrifyTvPlayerStylePage,
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
      parentsGuideStyleLabel: parentsGuideStyleLabel(_summaries.parentsGuideStyle),
      onOpenParentsGuideStyle: _appearanceNavigation.openParentsGuideStylePage,
      onOpenRecordings: _pageNavigation.openRecordings,
      onOpenIptvSettings: _connectionNavigation.openIptvSettings,
      showSupportDonation: _summaries.supportDonation.hasProviders,
      supportDonationLabel: _summaries.supportSettingsLabel,
      supportDonationSubtitle: _summaries.supportSettingsSubtitle,
      onOpenSupportDonation: _pageNavigation.openSupportDonation,
    );
  }

  Widget _buildLayout(BuildContext context) {
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
      parentsGuideStyleLabel: parentsGuideStyleLabel(_summaries.parentsGuideStyle),
      onOpenParentsGuideStyle: _appearanceNavigation.openParentsGuideStylePage,
      phoneNavStyleLabel: _summaries.phoneNavStyle == 'floating'
          ? 'Floating button'
          : 'Classic bar',
      desktopSidebarStyleLabel: desktopSidebarStyleLabel(_summaries.desktopSidebarStyle),
      onOpenDesktopSidebarStyle: _appearanceNavigation.openDesktopSidebarStyle,
      profileAppearanceLabel: ProfileGateStyle.labelFor(
        ProfileGateStyle.cached,
      ),
      onOpenProfileAppearance: _appearanceNavigation.openProfileAppearance,
    );
  }

  void focusFirstCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _firstCardFocusNode.requestFocus();
      }
    });
  }

}
