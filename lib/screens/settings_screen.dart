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
import 'package:debrify/features/settings/application/settings_pending_credentials.dart';
import 'package:debrify/features/settings/presentation/settings_layout.dart';
export 'package:debrify/features/settings/application/settings_pending_credentials.dart' show shouldApplyPendingCredentialOverride;
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/detail_page_storage.dart';
import 'package:debrify/services/storage/discover_storage.dart';
import 'package:debrify/services/storage/home_appearance_storage.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/services/storage/launch_ident_storage.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/sidebar_storage.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/theme_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/storage/torrent_provider_storage.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/storage/tv_display_storage.dart';
import 'package:debrify/services/storage/webdav_server_storage.dart';
import 'package:debrify/services/storage/webdav_storage.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/app_version_info.dart';

import '../models/webdav_item.dart';
import '../models/android_video_renderer_mode.dart';
import '../models/profiles/profile_policy.dart';
import '../models/profiles/connection_resource.dart';
import '../services/main_page_bridge.dart';
import '../services/external_player_service.dart';
import '../services/play_loader_style.dart';
import '../services/subtitle_font_service.dart';
import '../services/text_brightness.dart';
import '../services/profiles/profile_runtime.dart';
import '../services/profiles/connection_resource_service.dart';
import '../services/profiles/profile_lock_controller.dart';
import '../services/profiles/profile_bootstrap.dart';
import '../utils/platform_util.dart';
import '../utils/deovr_utils.dart' as deovr;

import '../services/analytics_service.dart';
import '../services/diagnostic_log.dart';
import '../services/account_service.dart';
import '../services/mdblist/mdblist_service.dart';
import '../services/support_remote_config_service.dart';
import '../services/torbox_account_service.dart';
import '../services/premiumize_account_service.dart';
import '../services/alldebrid_account_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/android_native_downloader.dart';
import '../services/live_recording_service.dart';
import '../services/desktop_schedule_service.dart';
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
import '../widgets/detail/theme/detail_themes.dart';
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
import 'settings/settings_summary_reads.dart';
import 'settings/playback_settings_section.dart';
import 'settings/subtitle_priority_page.dart';
import 'video_player/services/subtitle_settings_service.dart';
import 'video_player/services/network_tuning.dart';
import 'profiles/profile_wall_screen.dart';
import '../services/media_server_service.dart';
import '../theme/app_looks.dart';
import '../models/tv_hero_artwork_quality.dart';
import 'package:debrify/models/tv_render_quality.dart';
import 'package:debrify/services/storage/device_storage.dart';

/// Test access to the production builders and a delayed completion helper.
@visibleForTesting
({
  List<SettingsSearchEntry> Function() index,
  List<SettingsSearchEntry> Function() leaves,
  void Function(String) snack,
}) settingsScreenTestAccess(State<SettingsScreen> state) {
  final settings = state as _SettingsScreenState;
  return (
    index: settings._buildSearchIndex,
    leaves: settings._leafSearchEntries,
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
      reloadAppearanceSummaries: () => _reloadAppearanceSummaries(),
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
      loadSummaries: () => _loadSummaries(),
      reloadAppearanceSummaries: () => _reloadAppearanceSummaries(),
      context: () => context,
      mounted: () => mounted,
      setState: setState,
    ),
  );
  late final SettingsProfileActions _profileActions = SettingsProfileActions(
    _summaries,
    (
      activeProfileMayExportDiagnostics: () => _diagnostics.activeProfileMayExportDiagnostics(),
      loadSummaries: () => _loadSummaries(),
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
      loadSummaries: () => _loadSummaries(),
      restoreProfileBackup: () => _profileActions.restoreProfileBackup(),
      context: () => context,
      mounted: () => mounted,
    ),
  );
  late final SettingsDownloadLocation _downloadLocation = SettingsDownloadLocation(
    _summaries,
    (
      loadDownloadLocation: () => _loadDownloadLocation(),
      context: () => context,
      mounted: () => mounted,
    ),
  );
  late final SettingsMaintenance _maintenance = SettingsMaintenance(
    (
      loadSummaries: () => _loadSummaries(),
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

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _isTelevision => PlatformUtil.isTelevision;

  /// Handsets only. The player's start-orientation control is hidden on TV
  /// (no portrait to open in) and on desktop (the orientation call is a no-op
  /// there) — see ExternalPlayerSettingsPage.
  bool get _isPhone => PlatformUtil.isPhone;

  /// The IPTV Appearance picker renders only where the cockpit does (every TV
  /// platform and desktop) — the SAME gate IptvSettingsPage uses for its
  /// section. This includes tvOS, where the synchronous television flag is
  /// authoritative and the Android-specific cache is always false.
  bool get _iptvAppearanceSearchable =>
      PlatformUtil.isTelevision || (!kIsWeb && PlatformUtil.isDesktop);

  /// Custom launch command (macOS/Linux/Windows) or custom URL scheme (iOS).
  /// Android's external-player branch offers neither — it only explains the
  /// system app chooser. See ExternalPlayerSettingsPage's platform branches.
  bool get _customPlayerCommandSupported =>
      !kIsWeb &&
      (Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows ||
          Platform.isIOS);

  /// A named preferred-player picker exists on Apple platforms and desktop.
  /// Android delegates this choice to the system app chooser instead.
  bool get _preferredExternalPlayerSupported =>
      !kIsWeb &&
      (Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows ||
          Platform.isIOS);

  /// The recordings page has a working backend: the Android engine (tracked by
  /// [_summaries.recordingSearchable]) or the desktop recorder. On iOS it has neither —
  /// scheduling only raises a storage error and the library is always empty.
  bool get _recordingSupported =>
      _summaries.recordingSearchable || DesktopScheduleService.instance.isSupported;

  // TV content focus handler (stored for proper unregistration)
  VoidCallback? _tvContentFocusHandler;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('settings');
    _loadSummaries();
    _loadSupportConfig();
    _loadDownloadLocation();
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

  Future<void> _loadSummaries() async {
    final startingScope = ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;
    try {
      await _loadSummariesForCurrentProfile();
    } catch (error) {
      // ProfileGate retires this subtree on a switch or lock. Never publish
      // old-profile summaries into the replacement session.
      if (!mounted ||
          ProfileLockController.instance.lockedProfileId.value != null ||
          (startingScope != null &&
              ProfileRuntime.scope.value != startingScope)) {
        return;
      }
      _summaries.summaryLoadFailed = true;
      DiagnosticLog.instance.recordEvent(
        source: 'app',
        event: 'settings_summary_load_failed',
        fields: {'errorType': DiagnosticLabel(error.runtimeType.toString())},
      );
    } finally {
      if (mounted &&
          ProfileLockController.instance.lockedProfileId.value == null &&
          (startingScope == null ||
              ProfileRuntime.scope.value == startingScope)) {
        setState(() => _summaries.loading = false);
      }
    }
  }

  Future<void> _loadSummariesForCurrentProfile() async {
    // Phase 1: Load cached/local state instantly (no network)
    final startingScope = ProfileRuntime.scope.value;
    _summaries.summaryLoadFailed = false;
    final summaries = SettingsSummaryReads(
      overrides: widget.summaryReadOverrides,
      onFailure: (label, error) {
        if (mounted && ProfileRuntime.scope.value == startingScope) {
          _summaries.summaryFailures = {..._summaries.summaryFailures, label};
          if (error is ResourceAuthorizationException) {
            _summaries.summaryUnavailable = {..._summaries.summaryUnavailable, label};
          }
        }
        DiagnosticLog.instance.recordEvent(
          source: 'app',
          event: 'settings_summary_read_failed',
          fields: <String, Object?>{
            'item': DiagnosticLabel(label),
            // Exception messages can contain server URLs or credentials.
            'errorType': DiagnosticLabel(error.runtimeType.toString()),
            if (error is ResourceAuthorizationException)
              'authorizationReason': DiagnosticLabel(
                const {
                      'Connection authority is missing',
                      'Connection authority changed',
                      'Resource is unavailable',
                      'Profile feature is disabled',
                      'Resource permission denied',
                      'Profile session is locked',
                      'Profile authorization session has ended',
                      'Profile authorization has changed',
                      'Profile storage is in maintenance mode',
                    }.contains(error.message)
                    ? error.message
                    : 'other',
              ),
          },
        );
      },
    );
    final results = await Future.wait<Object?>([
      summaries.read(
        'Real Debrid',
        () => RealDebridStorage.hasRealDebridCredential(),
        false,
      ),
      summaries.read(
        'Torbox',
        () => TorboxStorage.hasTorboxCredential(),
        false,
      ),
      summaries.read(
        'PikPak',
        () => PikPakApiService.instance.isAuthenticated(),
        false,
      ),
      summaries.read('WebDAV', () => WebdavStorage.getWebDavEnabled(), false),
      summaries.read(
        'WebDAV',
        () => WebdavServerStorage.getWebDavServers(forSettings: true),
        <WebDavConfig>[],
      ),
      summaries.read('Trakt', () => TraktStorage.hasTraktCredential(), false),
      summaries.read('Trakt', () => TraktStorage.getTraktTokenExpiry(), null),
      summaries.read('Trakt', () => TraktStorage.getTraktUsername(), null),
      summaries.read(
        'App version',
        () => AppVersionInfo.get(),
        PackageInfo(
          appName: '',
          packageName: '',
          version: 'Unavailable',
          buildNumber: '',
        ),
      ),
      summaries.read(
        'TV detection',
        () => AndroidNativeDownloader.isTelevision(),
        false,
      ),
      summaries.read(
        'Update checks',
        () => DeviceStorage.getUpdateAutoCheckEnabled(),
        false,
      ),
      summaries.read(
        'Indexer managers',
        () => TorrentProviderStorage.getIndexerManagerConfigs(forSettings: true),
        [],
      ),
      summaries.read(
        'Premiumize',
        () => PremiumizeStorage.hasPremiumizeCredential(),
        false,
      ),
      summaries.read(
        'AllDebrid',
        () => AllDebridStorage.hasAllDebridCredential(),
        false,
      ),
      summaries.read('Simkl', () => SimklStorage.hasSimklCredential(), false),
      summaries.read('Simkl', () => SimklStorage.getSimklUsername(), null),
      summaries.read(
        'MDBList',
        () => MdblistStorage.hasMdblistCredential(),
        false,
      ),
      summaries.read(
        'MDBList',
        () => MdblistStorage.getMdblistUsername(),
        null,
      ),
      summaries.read(
        'TV keyboard',
        () => TvDisplayStorage.getTvKeyboardEnabled(),
        _summaries.tvKeyboardEnabled,
      ),
      summaries.read(
        'TV scale',
        () => TvDisplayStorage.getTvUiScalePercent(),
        _summaries.tvUiScalePercent,
      ),
      summaries.read(
        'TV home',
        () => HomeAppearanceStorage.getTvHomeStyle(),
        _summaries.tvHomeStyle,
      ),
      summaries.read(
        'TV sidebar',
        () => SidebarStorage.getTvSidebarStyle(),
        _summaries.tvSidebarStyle,
      ),
      summaries.read(
        'Discover layout',
        () => DiscoverStorage.getDiscoverLayout(),
        _summaries.discoverLayout,
      ),
      summaries.read(
        'IPTV style',
        () => IptvAppearanceStorage.getIptvStyle(),
        _summaries.iptvStyle,
      ),
      summaries.read(
        'Player guide',
        () => IptvAppearanceStorage.getIptvPlayerGuideStyle(),
        _summaries.playerGuideStyle,
      ),
      summaries.read(
        'Phone navigation',
        () => SidebarStorage.getPhoneNavStyle(),
        _summaries.phoneNavStyle,
      ),
      summaries.read(
        'Text brightness',
        () => ThemeStorage.getTextBrightness(),
        _summaries.textBrightness,
      ),
      summaries.read(
        'Launch animation',
        () => LaunchIdentStorage.getLaunchAnimation(),
        _summaries.launchAnimation,
      ),
      summaries.read(
        'Detail page',
        () => DetailPageStorage.getDetailPageStyle(),
        _summaries.detailPageStyle,
      ),
      summaries.read(
        'Render quality',
        () => TvDisplayStorage.getTvRenderQuality(),
        _summaries.tvRenderQuality,
      ),
      summaries.read(
        'Detail theme',
        () => DetailPageStorage.getDetailTheme(),
        _summaries.detailTheme,
      ),
      summaries.read(
        'Parents guide',
        () => DetailPageStorage.getParentsGuideStyle(),
        _summaries.parentsGuideStyle,
      ),
      summaries.read(
        'Artwork quality',
        () => TvDisplayStorage.getTvHeroArtworkQuality(),
        _summaries.tvHeroArtworkQuality,
      ),
      summaries.read(
        'Player dock',
        () => PlayerAppearanceStorage.getPlayerDockStyle(),
        _summaries.playerDockStyle,
      ),
      summaries.read(
        'Dock palette',
        () => PlayerAppearanceStorage.getPlayerDockPalette(),
        _summaries.playerDockPalette,
      ),
      summaries.read(
        'Dock size',
        () => PlayerAppearanceStorage.getPlayerDockSize(),
        _summaries.playerDockSize,
      ),
      summaries.read(
        'Desktop sidebar',
        () => SidebarStorage.getDesktopSidebarStyle(),
        _summaries.desktopSidebarStyle,
      ),
      summaries.read(
        'Debrify TV',
        () => DebrifyTvStorage.getDebrifyTvStyle(),
        _summaries.debrifyTvStyle,
      ),
      summaries.read(
        'TV controls',
        () => PlayerAppearanceStorage.getTvPlayerControlsStyle(),
        _summaries.tvPlayerControlsStyle,
      ),
      summaries.read(
        'TV player',
        () => DebrifyTvStorage.getDebrifyTvPlayerStyle(),
        _summaries.debrifyTvPlayerStyle,
      ),
      summaries.read(
        'Play loader',
        () => PlayerAppearanceStorage.getPlayLoaderStyle(),
        _summaries.playLoaderStyle,
      ),
      summaries.read(
        'Diagnostics',
        () => _diagnostics.activeProfileMayExportDiagnostics(),
        false,
      ),
      summaries.read(
        'Pending credentials',
        () => _pendingCredentialTypes(),
        <ConnectionResourceType>{},
      ),
      summaries.read(
        'IPTV',
        () => IptvPlaylistStorage.getIptvPlaylists(forSettings: true),
        [],
      ),
      summaries.read(
        'Alpha updates',
        () => DeviceStorage.getUpdateIncludeAlphaEnabled(),
        false,
      ),
      summaries.read('Media servers', () async => (await MediaServerService.connections()).length, 0),
    ]);

    if (!mounted || ProfileRuntime.scope.value != startingScope) return;
    _summaries.summaryFailures = summaries.failures;
    _summaries.summaryUnavailable = summaries.unavailable;

    final rdConnected = results[0] as bool;
    final torConnected = results[1] as bool;
    final pikpakAuth = results[2] as bool;
    final webDavEnabled = results[3] as bool;
    final webDavServers = results[4] as List<WebDavConfig>;
    final traktConnected = results[5] as bool;
    final traktExpiry = results[6] as int?;
    final traktUsername = results[7] as String?;
    final packageInfo = results[8] as PackageInfo;
    final isAndroidTv = results[9] as bool;
    final autoCheckEnabled = results[10] as bool;
    final indexerManagers = results[11] as List;
    final premiumizeConnected = results[12] as bool;
    final allDebridConnected = results[13] as bool;
    final simklConnected = results[14] as bool;
    final simklUsername = results[15] as String?;
    final mdblistConnected = results[16] as bool;
    final mdblistUsername = results[17] as String?;
    final tvKeyboardEnabled = results[18] as bool;
    final tvUiScalePercent = results[19] as int;
    final tvHomeStyle = results[20] as String;
    final tvSidebarStyle = results[21] as String;
    final discoverLayout = results[22] as String;
    final iptvStyle = results[23] as String;
    final playerGuideStyle = results[24] as String;
    final phoneNavStyle = results[25] as String;
    final textBrightness = results[26] as String;
    final launchAnimation = results[27] as String;
    final detailPageStyle = results[28] as String;
    final tvRenderQuality = results[29] as TvRenderQuality;
    final detailTheme = results[30] as String;
    final parentsGuideStyle = results[31] as String;
    final tvHeroArtworkQuality = results[32] as TvHeroArtworkQuality;
    // Later summary fields stay appended at the END of the Future.wait above,
    // so the long-established indices 0..32 never move.
    final playerDockStyle = results[33] as String;
    final playerDockPalette = results[34] as String;
    final playerDockSize = results[35] as String;
    final desktopSidebarStyle = results[36] as String;
    final debrifyTvStyle = results[37] as String;
    final tvPlayerControlsStyle = results[38] as String;
    final debrifyTvPlayerStyle = results[39] as String;
    final playLoaderStyle = results[40] as String;
    final diagnosticExportVisible = results[41] as bool;
    final pendingCredentialTypes = results[42] as Set<ConnectionResourceType>;
    final configuredIptvPlaylists = results[43] as List;
    final includeAlphaUpdates = results[44] as bool;
    _summaries.mediaServerCount = results[45] as int;

    // Set initial state from cached data
    // Use cached account info if available
    if (rdConnected) {
      final user = AccountService.currentUser;
      _summaries.realDebridConnected = true;
      if (user != null) {
        _applyRdUserInfo(user);
      } else {
        _summaries.realDebridStatus = 'Connected';
        _summaries.realDebridCaption = 'Loading account info...';
      }
    }

    if (torConnected) {
      final torboxUser = TorboxAccountService.currentUser;
      _summaries.torboxConnected = true;
      if (torboxUser != null) {
        _applyTorboxUserInfo(torboxUser);
      } else {
        _summaries.torboxStatus = 'Connected';
        _summaries.torboxCaption = 'Loading account info...';
      }
    }

    if (premiumizeConnected) {
      final premiumizeUser = PremiumizeAccountService.currentUser;
      _summaries.premiumizeConnected = true;
      if (premiumizeUser != null) {
        _applyPremiumizeUserInfo(premiumizeUser);
      } else {
        _summaries.premiumizeStatus = 'Connected';
        _summaries.premiumizeCaption = 'Loading account info...';
      }
    }

    if (allDebridConnected) {
      final allDebridUser = AllDebridAccountService.currentUser;
      _summaries.allDebridConnected = true;
      if (allDebridUser != null) {
        _applyAllDebridUserInfo(allDebridUser);
      } else {
        _summaries.allDebridStatus = 'Connected';
        _summaries.allDebridCaption = 'Loading account info...';
      }
    }

    if (pikpakAuth) {
      _summaries.pikpakConnected = true;
      _summaries.pikpakStatus = 'Active';
      _summaries.pikpakCaption = 'Logged in';
    }

    if (webDavEnabled && webDavServers.isNotEmpty) {
      _summaries.webDavConnected = true;
      _summaries.webDavStatus = 'Active';
      final first = webDavServers.first;
      final host = Uri.tryParse(first.baseUrl)?.host;
      final label = (host != null && host.isNotEmpty) ? host : first.baseUrl;
      _summaries.webDavCaption = webDavServers.length == 1
          ? label
          : '$label (+${webDavServers.length - 1} more)';
    } else {
      _summaries.webDavConnected = false;
      _summaries.webDavStatus = 'Not connected';
      _summaries.webDavCaption = 'Tap to connect';
    }

    final traktExpired =
        traktExpiry != null &&
        DateTime.now().millisecondsSinceEpoch >= traktExpiry;
    if (traktConnected) {
      if (!traktExpired) {
        _summaries.traktConnected = true;
        _summaries.traktStatus = 'Active';
        _summaries.traktCaption = traktUsername != null
            ? 'Logged in as $traktUsername'
            : 'Logged in';
      } else {
        _summaries.traktStatus = 'Expired';
        _summaries.traktCaption = 'Tap to reconnect';
      }
    }

    // Simkl's PIN-issued tokens don't expire, so unlike Trakt there's no
    // "Expired" branch here — a stored token means connected.
    if (simklConnected) {
      _summaries.simklConnected = true;
      _summaries.simklStatus = 'Active';
      _summaries.simklCaption = simklUsername != null
          ? 'Logged in as $simklUsername'
          : 'Logged in';
    } else {
      _summaries.simklConnected = false;
      _summaries.simklStatus = 'Not connected';
      _summaries.simklCaption = 'Tap to connect';
    }

    // MDBList uses a plain API key (no expiry) — a stored key means connected.
    // Reset on the empty branch (like WebDAV above) so the card clears after a
    // logout, since this method re-runs when returning from the settings page.
    if (mdblistConnected) {
      _summaries.mdblistConnected = true;
      _summaries.mdblistStatus = 'Active';
      _summaries.mdblistCaption = mdblistUsername != null
          ? 'Logged in as $mdblistUsername'
          : 'Logged in';
    } else {
      _summaries.mdblistConnected = false;
      _summaries.mdblistStatus = 'Not connected';
      _summaries.mdblistCaption = 'Tap to connect';
    }

    if (indexerManagers.isNotEmpty) {
      _summaries.indexerManagersConfigured = true;
      _summaries.indexerManagersStatus = 'Active';
      _summaries.indexerManagersCaption =
          '${indexerManagers.length} engine${indexerManagers.length == 1 ? '' : 's'} configured';
    }

    void pending(
      Set<ConnectionResourceType> types,
      bool ownCredentialPresent,
      void Function() apply,
    ) {
      if (shouldApplyPendingCredentialOverride(
        pendingTypes: pendingCredentialTypes,
        providerTypes: types,
        ownCredentialPresent: ownCredentialPresent,
      )) {
        apply();
      }
    }

    const pendingCaption = 'credentials pending owner sign-in';
    _summaries.iptvCredentialsPending = shouldApplyPendingCredentialOverride(
      pendingTypes: pendingCredentialTypes,
      providerTypes: const {
        ConnectionResourceType.iptvM3u,
        ConnectionResourceType.iptvXtream,
        ConnectionResourceType.xmltv,
      },
      ownCredentialPresent: configuredIptvPlaylists.isNotEmpty,
    );
    pending(const {ConnectionResourceType.realDebrid}, rdConnected, () {
      _summaries.realDebridConnected = true;
      _summaries.realDebridStatus = 'Attention';
      _summaries.realDebridCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.torbox}, torConnected, () {
      _summaries.torboxConnected = true;
      _summaries.torboxStatus = 'Attention';
      _summaries.torboxCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.premiumize}, premiumizeConnected, () {
      _summaries.premiumizeConnected = true;
      _summaries.premiumizeStatus = 'Attention';
      _summaries.premiumizeCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.allDebrid}, allDebridConnected, () {
      _summaries.allDebridConnected = true;
      _summaries.allDebridStatus = 'Attention';
      _summaries.allDebridCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.pikpak}, pikpakAuth, () {
      _summaries.pikpakConnected = true;
      _summaries.pikpakStatus = 'Attention';
      _summaries.pikpakCaption = pendingCaption;
    });
    pending(
      const {ConnectionResourceType.webDav},
      webDavEnabled && webDavServers.isNotEmpty,
      () {
        _summaries.webDavConnected = true;
        _summaries.webDavStatus = 'Attention';
        _summaries.webDavCaption = pendingCaption;
      },
    );
    pending(const {ConnectionResourceType.trakt}, traktConnected, () {
      _summaries.traktConnected = true;
      _summaries.traktStatus = 'Attention';
      _summaries.traktCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.simkl}, simklConnected, () {
      _summaries.simklConnected = true;
      _summaries.simklStatus = 'Attention';
      _summaries.simklCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.mdblist}, mdblistConnected, () {
      _summaries.mdblistConnected = true;
      _summaries.mdblistStatus = 'Attention';
      _summaries.mdblistCaption = pendingCaption;
    });
    pending(
      const {ConnectionResourceType.jackett, ConnectionResourceType.prowlarr},
      indexerManagers.isNotEmpty,
      () {
        _summaries.indexerManagersConfigured = true;
        _summaries.indexerManagersStatus = 'Attention';
        _summaries.indexerManagersCaption = pendingCaption;
      },
    );

    _summaries.appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    _summaries.currentVersionName = packageInfo.version;
    _summaries.isAndroidTv = isAndroidTv;
    DiagnosticLog.instance.recordEvent(
      source: 'app',
      event: 'app_metadata',
      fields: <String, Object?>{
        'version': DiagnosticLabel(packageInfo.version),
        'build': DiagnosticLabel(packageInfo.buildNumber),
        'androidTv': isAndroidTv,
      },
    );
    _summaries.loading = false;
    _summaries.autoUpdateChecksEnabled = autoCheckEnabled;
    _summaries.includeAlphaUpdates = includeAlphaUpdates;
    _summaries.tvKeyboardEnabled = tvKeyboardEnabled;
    _summaries.tvUiScalePercent = tvUiScalePercent;
    _summaries.tvRenderQuality = tvRenderQuality;
    _summaries.tvHomeStyle = tvHomeStyle;
    _summaries.tvSidebarStyle = tvSidebarStyle;
    _summaries.discoverLayout = discoverLayout;
    _summaries.iptvStyle = iptvStyle;
    _summaries.debrifyTvStyle = debrifyTvStyle;
    _summaries.playerGuideStyle = playerGuideStyle;
    _summaries.playLoaderStyle = playLoaderStyle;
    _summaries.tvPlayerControlsStyle = tvPlayerControlsStyle;
    _summaries.debrifyTvPlayerStyle = debrifyTvPlayerStyle;
    _summaries.playerDockStyle = playerDockStyle;
    _summaries.playerDockPalette = playerDockPalette;
    _summaries.playerDockSize = playerDockSize;
    _summaries.phoneNavStyle = phoneNavStyle;
    _summaries.desktopSidebarStyle = desktopSidebarStyle;
    _summaries.textBrightness = textBrightness;
    _summaries.launchAnimation = launchAnimation;
    _summaries.detailPageStyle = detailPageStyle;
    _summaries.detailTheme = detailTheme;
    _summaries.parentsGuideStyle = parentsGuideStyle;
    _summaries.tvHeroArtworkQuality = tvHeroArtworkQuality;
    _summaries.diagnosticExportVisible = diagnosticExportVisible;

    setState(() {});

    // Phase 2: Refresh account info from network in background
    if (rdConnected) {
      AccountService.refreshUserInfo().then((_) {
        if (!mounted) return;
        final user = AccountService.currentUser;
        if (user != null) {
          setState(() => _applyRdUserInfo(user));
        }
      });
    }

    if (torConnected) {
      TorboxAccountService.refreshUserInfo().then((_) {
        if (!mounted) return;
        final torboxUser = TorboxAccountService.currentUser;
        if (torboxUser != null) {
          setState(() => _applyTorboxUserInfo(torboxUser));
        }
      });
    }

    if (premiumizeConnected) {
      PremiumizeAccountService.refreshUserInfo().then((_) {
        if (!mounted) return;
        final premiumizeUser = PremiumizeAccountService.currentUser;
        if (premiumizeUser != null) {
          setState(() => _applyPremiumizeUserInfo(premiumizeUser));
        }
      });
    }

    if (allDebridConnected) {
      AllDebridAccountService.refreshUserInfo().then((_) {
        if (!mounted) return;
        final allDebridUser = AllDebridAccountService.currentUser;
        if (allDebridUser != null) {
          setState(() => _applyAllDebridUserInfo(allDebridUser));
        }
      });
    }
  }

  Future<Set<ConnectionResourceType>> _pendingCredentialTypes() async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return const <ConnectionResourceType>{};
    }
    final scope = ProfileRuntime.capture();
    final resources = await ProfileBootstrap.registry.listGrantedResources(
      scope.profileId,
    );
    if (ProfileRuntime.scope.value != scope) {
      return const <ConnectionResourceType>{};
    }
    return resources
        .where((resource) => resource.needsReconnect)
        .map((resource) => resource.type)
        .toSet();
  }

  Future<void> _loadSupportConfig() async {
    final service = SupportRemoteConfigService.instance;
    final cached = await service.loadCachedOrFallback();
    if (mounted) {
      setState(() {
        _applySupportConfig(cached);
      });
    }

    final fresh = await service.loadConfig();
    if (!mounted) return;
    setState(() {
      _applySupportConfig(fresh);
    });
  }

  void _applySupportConfig(SupportRemoteConfig config) {
    _summaries.supportDonation = config.donation;
    _summaries.supportSettingsLabel = config.donation.settingsLabel;
    _summaries.supportSettingsSubtitle = config.donation.settingsSubtitle;
  }

  void _applyRdUserInfo(dynamic user) {
    final expiry = _tryParseDate(user.expiration);
    final bool isPremium = user.isPremium;
    final bool active =
        isPremium && (expiry == null || expiry.isAfter(DateTime.now()));
    _summaries.realDebridStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _summaries.realDebridCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _summaries.realDebridCaption = 'Premium account';
    } else if (isPremium && expiry != null) {
      _summaries.realDebridCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _summaries.realDebridCaption = 'Premium not active';
    }
  }

  void _applyTorboxUserInfo(dynamic torboxUser) {
    final expiry = torboxUser.premiumExpiresAt;
    final bool active = torboxUser.hasActiveSubscription;
    _summaries.torboxStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _summaries.torboxCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _summaries.torboxCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _summaries.torboxCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _summaries.torboxCaption = 'Premium not active';
    }
  }

  void _applyPremiumizeUserInfo(dynamic premiumizeUser) {
    final expiry = premiumizeUser.premiumUntil;
    final bool active = premiumizeUser.hasActivePremium;
    _summaries.premiumizeStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _summaries.premiumizeCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _summaries.premiumizeCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _summaries.premiumizeCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _summaries.premiumizeCaption = 'Premium not active';
    }
  }

  void _applyAllDebridUserInfo(dynamic allDebridUser) {
    final expiry = allDebridUser.premiumUntil;
    final bool active = allDebridUser.hasActivePremium;
    _summaries.allDebridStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _summaries.allDebridCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _summaries.allDebridCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _summaries.allDebridCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _summaries.allDebridCaption = 'Premium not active';
    }
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
      onOpenSearch: _openSettingsSearch,
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
      onOpenSearch: _openSettingsSearch,
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
      showIptvAppearance: _iptvAppearanceSearchable,
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

  Future<void> _openSettingsSearch() async {
    await pushSettingsPage(
      context,
      SettingsSearchPage(entries: _buildSearchIndex()),
    );
    if (!mounted) return;
    // A deep-linked page may have changed a connection/login; refresh so the
    // underlying settings surface is current when search closes.
    setState(() {});
  }

  /// Flat, searchable index of every settings destination. Built fresh on open
  /// so dynamic copy (download folder, update status, connection captions) and
  /// live toggle values are current. Navigable entries reuse the same
  /// `_openXxx` handlers the layouts wire, so actions never drift; toggle
  /// entries read/write the same state fields as their inline rows.
  ///
  /// Top-level destinations live here; in-page options are appended by
  /// [_leafSearchEntries] and deep-link to the page that hosts them (no
  /// scroll-to-highlight yet). [SettingsSearchEntry.keywords] carry the
  /// concepts a row's copy doesn't say out loud (sd card, 4k, epg, scrobble…).
  /// A few pages reachable only from outside Settings — Stremio TV's channel
  /// settings, the Addons tab — are indexed here too, since a settings search
  /// is where people look for them.
  List<SettingsSearchEntry> _buildSearchIndex() {
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

    return [
      if (ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted) ...[
        nav(
          SettingsRows.switchProfile,
          'Profiles',
          _profileActions.switchProfile,
          keywords: const [
            'profile',
            'profiles',
            'switch',
            'switch to this profile',
            'who is watching',
            'avatar',
            'pin',
            'kids',
            'account',
            'startup',
            'always ask',
            'household',
            'backup',
            'restore',
            'send to tv',
            'transfer',
            'delete profile',
            'disable profile',
          ],
        ),
        nav(
          SettingsRows.addProfile,
          'Profiles',
          _profileActions.addProfile,
          keywords: const [
            'create profile',
            'new profile',
            'add user',
            'kid',
            'member',
            'admin',
            'start from my settings',
            'copy appearance and playback defaults',
            'search by title',
            'keyword search',
            'debrify tv',
            'stremio tv',
            'live tv',
            'youtube',
            'download and record',
            'remote',
            'manage own sources',
            'cloud files',
          ],
        ),
        nav(
          SettingsRows.editProfile,
          'Profiles',
          _profileActions.editActiveProfile,
          keywords: const [
            'rename',
            'avatar',
            'pin',
            'access',
            'permissions',
            'edit user',
            'save name and avatar',
            'choose image',
            'gif',
            'set pin',
            'change pin',
            'remove pin',
            'pin protection',
            'lock when the app resumes',
            'auto-lock',
            'after 5 minutes',
            'after 15 minutes',
            'after 30 minutes',
            'after 1 hour',
            'copy appearance and playback defaults',
            'role',
            'admin',
            'member',
            'kid',
            'pages and abilities',
            'keyword search',
            'live tv',
            'youtube',
            'download and record',
            'manage own sources',
            'cloud files',
            'torrent engines',
            'debrid and cloud',
            'addons',
            'trackers and lists',
            'live tv and indexers',
            'transfer ownership',
            'diagnostics',
            're-run the questions',
            'full editor',
          ],
        ),
      ],
      // Connections
      conn(_connections.rdInfo, const [
        'debrid',
        'real-debrid',
        'rd',
        'premium',
        'api key',
        'add api key',
        'logout',
        'login',
        'account',
      ]),
      conn(_connections.torboxInfo, const [
        'debrid',
        'premium',
        'api key',
        'add api key',
        'logout',
        'login',
        'account',
      ]),
      conn(_connections.premiumizeInfo, const [
        'debrid',
        'premium',
        'api key',
        'add api key',
        'logout',
        'login',
        'account',
      ]),
      conn(_connections.allDebridInfo, const [
        'debrid',
        'ad',
        'premium',
        'api key',
        'add api key',
        'logout',
        'login',
        'account',
      ]),
      conn(_connections.pikpakInfo, const [
        'cloud',
        'storage',
        'login',
        'account',
        'email',
        'password',
        'logout',
        'change account',
        'remove account',
      ]),
      conn(_connections.webDavInfo, const [
        'cloud',
        'nas',
        'server',
        'seedbox',
        'url',
        'username',
        'password',
        'app token',
      ]),
      conn(_connections.mediaServersInfo, const ['jellyfin', 'emby', 'media server', 'nas', 'server', 'login']),
      conn(_connections.iptvInfo, const [
        'live tv',
        'm3u',
        'playlist',
        'channels',
        'epg',
        'xtream',
      ]),
      SettingsSearchEntry(
        icon: Icons.bookmark_rounded,
        title: 'IPTV lists',
        subtitle: 'Create and manage your channel lists',
        category: 'Live TV & DVR',
        keywords: const [
          'list',
          'lists',
          'favorites',
          'favourites',
          'saved channels',
          'iptv',
          'collection',
        ],
        onTap: _connectionNavigation.openIptvSettings,
      ),
      SettingsSearchEntry(
        icon: Icons.live_tv_rounded,
        title: 'Startup channel',
        subtitle: 'Open straight into a live channel when the app starts',
        category: 'Live TV & DVR',
        keywords: const [
          'startup',
          'start up',
          'boot',
          'launch',
          'auto play',
          'autoplay',
          'auto launch',
          'last watched',
          'on open',
          'iptv',
          'live tv',
        ],
        onTap: _connectionNavigation.openIptvSettings,
      ),
      SettingsSearchEntry(
        icon: Icons.history_toggle_off_rounded,
        title: 'IPTV continue watching',
        subtitle: 'Track the movies and series you start on IPTV',
        category: 'Live TV & DVR',
        keywords: const [
          'continue watching',
          'continue',
          'resume',
          'history',
          'watch history',
          'track',
          'tracking',
          'shelf',
          'iptv',
          'vod',
          'movies',
          'series',
        ],
        onTap: _connectionNavigation.openIptvSettings,
      ),
      conn(_connections.indexerManagersInfo, const [
        'indexer',
        'torznab',
        'jackett',
        'prowlarr',
        'engines',
      ]),

      // Trackers — keep this block last in the Connections neighbourhood so
      // the two categories stay contiguous; see SettingsSearchPage.
      conn(_connections.traktInfo, const [
        'scrobble',
        'sync',
        'watch history',
        'watchlist',
        'login',
        'activate',
        'device code',
        'logout',
      ], category: 'Trackers'),
      conn(_connections.trackingInfo, const [
        'scrobble',
        'sync catalog',
        'watch progress',
        'continue watching source',
        'home ticks',
      ], category: 'Trackers'),
      conn(_connections.simklInfo, const [
        'scrobble',
        'sync',
        'watch history',
        'login',
        'pin',
        'device code',
        'logout',
      ], category: 'Trackers'),
      if (kMdblistEnabled)
        conn(_connections.mdblistInfo, const ['lists', 'ratings'], category: 'Trackers'),

      // General
      nav(
        SettingsRows.homePage,
        'Home & Display',
        _pageNavigation.openHomePageSettings,
        keywords: const [
          'home page',
          'default view',
          'startup',
          'landing',
          'tab',
        ],
      ),
      nav(
        SettingsRows.badges,
        'Badges',
        _pageNavigation.openBadgesSettings,
        keywords: const ['stream badges', 'rules', 'nuvio'],
      ),
      nav(
        SettingsRows.collections,
        'Collections',
        _pageNavigation.openCollectionsSettings,
        keywords: const [
          'collections',
          'collection',
          'nuvio',
          'xperience',
          'folders',
          'import json',
        ],
      ),

      nav(
        SettingsRows.metadata,
        'Metadata',
        _pageNavigation.openMetadataSettings,
        keywords: const [
          'tmdb',
          'language',
          'poster',
          'artwork',
          'provider',
          'trailer',
        ],
      ),

      // Appearance — one contiguous block so the category groups directly
      // after Home & Display (results group by FIRST appearance). The old
      // category strings ride along as keywords: the category text is part
      // of the match haystack, and matching splits on whitespace only, so
      // dropping 'Home & Display'/'Live TV & DVR' from these entries would
      // break exact old-category searches.
      // Ungated — every platform has text. Lands on the picker.
      nav(
        SettingsRows.textBrightness,
        'Appearance',
        _appearanceNavigation.openTextBrightnessPage,
        subtitle: textBrightnessLabel(_summaries.textBrightness),
        keywords: [
          'text',
          'font',
          'color',
          'colour',
          'grey',
          'gray',
          'white',
          'dim',
          'dimmer',
          'brightness',
          'bright',
          'oled',
          'amoled',
          'contrast',
          'glare',
          'display',
          ...labels(TextBrightness.values.map((choice) => choice.label)),
        ],
      ),
      // Ungated — every platform plays the splash. Lands on the picker.
      nav(
        SettingsRows.launchAnimation,
        'Appearance',
        _appearanceNavigation.openLaunchAnimationPage,
        subtitle: launchIdentLabel(_summaries.launchAnimation),
        keywords: [
          'launch',
          'splash',
          'intro',
          'animation',
          'boot',
          'start',
          'startup',
          'logo',
          'ident',
          'opening',
          'neon',
          'chrome',
          'marquee',
          'prism',
          'monogram',
          'match app theme',
          'ident colour',
          'ident color',
          ...labels(kLaunchIdents.map((ident) => ident.label)),
        ],
      ),
      // Android TV only — the size factor is applied natively in
      // MainActivity, so the row would be inert anywhere else.
      if (_summaries.isAndroidTv)
        nav(
          SettingsRows.tvScreenSize,
          'Appearance',
          _appearanceNavigation.openTvScreenSize,
          subtitle: tvUiScaleLabel(_summaries.tvUiScalePercent),
          keywords: [
            'zoom',
            'zoomed in',
            'scale',
            'ui size',
            'text size',
            'font size',
            'bigger',
            'smaller',
            'density',
            'dpi',
            'resolution',
            'compact',
            'fit more',
            'display',
            'home & display',
            ...labels(kTvUiScaleChoices.map((choice) => choice.label)),
          ],
        ),
      // Android TV only — the render scale is applied natively in
      // MainActivity, so the row would be inert anywhere else. Keyworded for
      // the SYMPTOM: nobody searches "render scale", they search "stutter".
      if (_summaries.isAndroidTv)
        nav(
          SettingsRows.tvRenderQuality,
          'Appearance',
          _appearanceNavigation.openTvRenderQuality,
          subtitle: tvRenderQualityLabel(_summaries.tvRenderQuality),
          keywords: [
            'stutter',
            'stuttering',
            'lag',
            'laggy',
            'jank',
            'janky',
            'choppy',
            'slow',
            'smooth',
            'smoothness',
            'performance',
            'fps',
            'frame rate',
            'speed',
            'scrolling',
            'resolution',
            'render',
            'rendering',
            '720p',
            '1080p',
            'sharp',
            'sharpness',
            'blurry',
            'soft',
            'quality',
            'gpu',
            'graphics',
            'display',
            'home & display',
            ...labels(kTvRenderQualityChoices.map((choice) => choice.label)),
          ],
        ),
      // Android TV + tvOS: this controls Flutter image decode bounds, so it is
      // independent of Android's native render-scale picker above.
      if (_isTelevision)
        nav(
          SettingsRows.tvHeroArtworkQuality,
          'Appearance',
          _appearanceNavigation.openTvHeroArtworkQuality,
          subtitle: tvHeroArtworkQualityLabel(_summaries.tvHeroArtworkQuality),
          keywords: [
            'hero',
            'artwork',
            'image',
            'picture',
            'poster',
            'backdrop',
            'quality',
            'resolution',
            '1080p',
            'full hd',
            'sharp',
            'memory',
            'performance',
            'home',
            'tv',
            ...labels(
              kTvHeroArtworkQualityChoices.map((choice) => choice.label),
            ),
          ],
        ),
      // Every platform now: TV picks among the eight layouts, phones and
      // desktop between Classic and Spotlight (the picker narrows itself).
      nav(
        SettingsRows.tvHomeStyle,
        'Appearance',
        _appearanceNavigation.openTvHomeStyle,
        subtitle: tvHomeStyleLabel(
          _summaries.isAndroidTv ? _summaries.tvHomeStyle : effectiveOffTvHomeStyle(_summaries.tvHomeStyle),
        ),
        keywords: [
          'home',
          'layout',
          'home screen',
          'canvas',
          'spotlight',
          'shelf',
          'classic',
          'rows',
          'redesign',
          'view',
          'display',
          'home & display',
          ...labels(
            (_isTelevision ? kTvHomeStyleChoices : kOffTvHomeStyleChoices).map(
              (choice) => choice.label,
            ),
          ),
        ],
      ),
      nav(
        SettingsRows.profileAppearance,
        'Appearance',
        _appearanceNavigation.openProfileAppearance,
        subtitle: ProfileGateStyle.labelFor(ProfileGateStyle.cached),
        keywords: [
          'profile',
          'picker',
          'who is watching',
          'who\'s watching',
          'marquee',
          'theater',
          'portrait wall',
          'top shelf',
          'personalized top shelf',
          'apple tv',
          ...labels(ProfileGateStyle.options.map((option) => option.label)),
        ],
      ),
      if (_isTelevision ||
          MediaQuery.sizeOf(context).shortestSide >= 600 ||
          (PlatformUtil.isDesktop && MediaQuery.sizeOf(context).width >= 600))
        nav(
          SettingsRows.collectionListStyle,
          'Appearance',
          _appearanceNavigation.openCollectionListStyle,
          subtitle: 'Grid · Gallery · Filmstrip · Journal · Spotlight',
          keywords: [
            'collection', 'list', 'gallery', 'filmstrip', 'journal', 'spotlight',
          ],
        ),
      if (_summaries.isAndroidTv)
        nav(
          SettingsRows.discoverLayout,
          'Appearance',
          _appearanceNavigation.openDiscoverLayout,
          subtitle: discoverLayoutLabel(_summaries.discoverLayout),
          keywords: [
            'discover',
            'layout',
            'stage',
            'grid',
            'browse',
            'shelf',
            'catalog',
            'view',
            'posters',
            'display',
            'home & display',
            ...labels(kDiscoverLayoutChoices.map((choice) => choice.label)),
          ],
        ),
      // Android TV only — the rail is TV chrome.
      if (_summaries.isAndroidTv)
        nav(
          SettingsRows.tvSidebarStyle,
          'Appearance',
          _appearanceNavigation.openTvSidebarStyle,
          subtitle: tvSidebarStyleLabel(_summaries.tvSidebarStyle),
          keywords: [
            'sidebar',
            'nav',
            'navigation',
            'rail',
            'menu',
            'ghost',
            'island',
            'marquee',
            'badge',
            'dock',
            'display',
            'home & display',
            'order and names',
            'rename sidebar',
            ...labels(kTvSidebarStyleChoices.map((choice) => choice.label)),
          ],
        ),
      // Desktop/tablet — the wide-window rail's own picker.
      if (!_summaries.isAndroidTv && !PlatformUtil.isTelevision)
        nav(
          SettingsRows.desktopSidebarStyle,
          'Appearance',
          _appearanceNavigation.openDesktopSidebarStyle,
          subtitle: desktopSidebarStyleLabel(_summaries.desktopSidebarStyle),
          keywords: [
            'sidebar',
            'nav',
            'navigation',
            'rail',
            'menu',
            'pill',
            'desktop',
            'tablet',
            'ipad',
            'display',
            'home & display',
            'order and names',
            'rename sidebar',
            ...labels(
              kDesktopSidebarStyleChoices.map((choice) => choice.label),
            ),
          ],
        ),
      // Gated like the IPTV section itself: the picker only matters where
      // the cockpit renders (Android TV, desktop). Lands on the picker.
      if (_iptvAppearanceSearchable)
        nav(
          SettingsRows.iptvAppearance,
          'Appearance',
          _appearanceNavigation.openIptvStylePage,
          subtitle: iptvStyleLabel(_summaries.iptvStyle),
          keywords: [
            'iptv',
            'style',
            'theme',
            'look',
            'skin',
            'appearance',
            'command center',
            'first edition',
            'master control',
            'spotlight guide',
            'apple tv',
            'epg',
            'cockpit',
            'premium',
            'live tv',
            'dvr',
            'live tv & dvr',
            ...labels(kIptvStyleChoices.map((choice) => choice.label)),
          ],
        ),
      // Ungated: the pref covers every device class — the Spotlight arm has
      // a TV layout AND a phone layout. Lands on the picker.
      nav(
        SettingsRows.debrifyTvAppearance,
        'Appearance',
        _appearanceNavigation.openDebrifyTvStylePage,
        subtitle: debrifyTvStyleLabel(_summaries.debrifyTvStyle),
        keywords: [
          'debrify tv',
          'channels',
          'channel grid',
          'rail',
          'stage',
          'spotlight',
          'style',
          'layout',
          'look',
          'appearance',
          ...labels(kDebrifyTvStyleChoices.map((choice) => choice.label)),
        ],
      ),
      // Ungated: every platform has a player — phones use the Dart player,
      // Android TV the native one, and both read the pref. Lands on the
      // picker.
      nav(
        SettingsRows.playerGuideStyle,
        'Appearance',
        _appearanceNavigation.openPlayerGuideStylePage,
        subtitle: playerGuideStyleLabel(_summaries.playerGuideStyle),
        keywords: [
          'iptv',
          'player',
          'guide',
          'zap',
          'banner',
          'style',
          'theme',
          'look',
          'skin',
          'cinema glass',
          'midnight edition',
          'master control',
          'classic',
          'live tv',
          'dvr',
          'live tv & dvr',
          ...labels(
            playerGuideStyleChoicesForPlatform().map((choice) => choice.label),
          ),
        ],
      ),
      // Ungated — every platform shows a loader between Play and the
      // picture. Lands on the picker.
      nav(
        SettingsRows.playLoaderStyle,
        'Appearance',
        _appearanceNavigation.openPlayLoaderStylePage,
        subtitle: playLoaderStyleLabel(_summaries.playLoaderStyle),
        keywords: [
          'play',
          'loading',
          'loader',
          'spinner',
          'searching',
          'resolving',
          'progress',
          'marquee',
          'backdrop',
          'logo',
          'stages',
          'pipeline',
          ...labels(
            PlayLoaderStyleController.options.map((choice) => choice.label),
          ),
        ],
      ),
      // Android TV only: the skin picker for the NATIVE player's controls.
      // tvOS runs the Flutter player (one look) and phones/desktops have the
      // dock row below instead. PlatformUtil, not _isAndroidTv — the latter
      // answers the form-factor question and is true on Apple TV.
      if (PlatformUtil.isAndroidTvCached)
        nav(
          SettingsRows.tvPlayerControls,
          'Appearance',
          _appearanceNavigation.openTvPlayerControlsStylePage,
          subtitle: tvPlayerControlsStyleLabel(_summaries.tvPlayerControlsStyle),
          keywords: [
            'player',
            'controls',
            'dock',
            'buttons',
            'seekbar',
            'scrubber',
            'transport',
            'ott',
            'legacy',
            'cinema',
            'style',
            'look',
            'skin',
            ...labels(
              kTvPlayerControlsStyleChoices.map((choice) => choice.label),
            ),
          ],
        ),
      // Android TV only: the Debrify TV playback-screen style (native
      // TorboxTvPlayerActivity is the pref's only reader).
      if (PlatformUtil.isAndroidTvCached)
        nav(
          SettingsRows.debrifyTvPlayer,
          'Appearance',
          _appearanceNavigation.openDebrifyTvPlayerStylePage,
          subtitle: debrifyTvPlayerStyleLabel(_summaries.debrifyTvPlayerStyle),
          keywords: [
            'debrify tv',
            'magic tv',
            'channel',
            'player',
            'network',
            'cinema',
            'guide',
            'spotlight',
            'prestige',
            'badge',
            'quality',
            'style',
            'look',
            'skin',
            ...labels(
              kDebrifyTvPlayerStyleChoices.map((choice) => choice.label),
            ),
          ],
        ),
      if (!PlatformUtil.isTelevision)
        nav(
          SettingsRows.playerDock,
          'Appearance',
          _appearanceNavigation.openPlayerDockPage,
          subtitle: playerDockLabel(
            _summaries.playerDockStyle,
            _summaries.playerDockPalette,
            _summaries.playerDockSize,
          ),
          keywords: [
            'player',
            'controls',
            'dock',
            'buttons',
            'seekbar',
            'scrubber',
            'size',
            'colour',
            'color',
            'palette',
            'style',
            'look',
            'big',
            'small',
            'layout',
            'accent',
            ...labels(kPlayerDockStyleChoices.map((choice) => choice.label)),
            ...labels(kPlayerDockPaletteChoices.map((choice) => choice.label)),
            ...labels(kPlayerDockSizeChoices.map((choice) => choice.label)),
          ],
        ),
      // Settings SEARCH still finds it, deliberately.
      //
      // The row is gone from the Appearance list because a Look is the single
      // top-level choice now — but someone who knows the app has themes and
      // types "theme" should land somewhere, and the honest destination is the
      // Looks page rather than nothing at all.
      nav(
        SettingsRows.themeTokens,
        'Appearance',
        _appearanceNavigation.openThemeTokensPage,
        subtitle: _appearanceNavigation.themeTokensLabel,
        keywords: [
          'advanced',
          'token',
          'colour',
          'color',
          'accent',
          'background',
          'font',
          'corner',
          'motion',
        ],
      ),
      nav(
        SettingsRows.looks,
        'Appearance',
        _appearanceNavigation.openLooksPage,
        subtitle: AppLooks.active()?.label ?? 'Custom',
        keywords: [
          'app',
          'theme',
          'app theme',
          'whole app',
          'colour',
          'color',
          'palette',
          'look',
          'style',
          'skin',
          'dark',
          'light',
          'legacy',
          'classic',
          ...labels(AppLooks.all.map((look) => look.label)),
          'experimental',
          // Every theme by NAME, derived rather than typed out. The names used
          // to live on the Details Theme entry; withholding that row would
          // otherwise have made searching "velvet" or "deep field" find
          // nothing, and a hardcoded copy had already gone stale — it listed
          // the twenty old cores and none of the five new looks.
          for (final t in DetailThemes.catalogue) t.label.toLowerCase(),
        ],
      ),
      nav(
        SettingsRows.parentsGuideStyle,
        'Appearance',
        _appearanceNavigation.openParentsGuideStylePage,
        subtitle: parentsGuideStyleLabel(_summaries.parentsGuideStyle),
        keywords: [
          'parents',
          'parental',
          'guide',
          'advisory',
          'content rating',
          'severity',
          'compass',
          'classic',
          'family',
          ...labels(kParentsGuideStyleChoices.map((choice) => choice.label)),
        ],
      ),
      // Ungated: the details page opens on every platform.
      nav(
        SettingsRows.detailPageStyle,
        'Appearance',
        _appearanceNavigation.openDetailPageStylePage,
        subtitle: detailPageStyleLabel(_summaries.detailPageStyle),
        keywords: [
          'details',
          'detail',
          'page',
          'layout',
          'style',
          'theme',
          'look',
          'movie',
          'series',
          'show',
          'episodes',
          'episode list',
          'visible sections',
          'where to watch',
          'rent',
          'buy',
          'availability',
          'justwatch',
          'tmdb',
          'did you know',
          'trivia',
          'marquee',
          'dossier',
          'broadsheet',
          'stage',
          'filmstrip',
          'console',
          'classic',
          ...labels(kDetailPageStyleChoices.map((choice) => choice.label)),
        ],
      ),
      if (!PlatformUtil.isTelevision)
        nav(
          SettingsRows.navigationStyle,
          'Appearance',
          _connectionNavigation.openNavigationSettings,
          keywords: const [
            'navigation',
            'nav',
            'bottom bar',
            'tabs',
            'floating',
            'classic',
            'menu',
            'display',
            'home & display',
          ],
        ),

      nav(
        SettingsRows.player,
        'Playback',
        _pageNavigation.openExternalPlayerSettings,
        keywords: [
          'external player',
          'video player',
          if (_isAndroid) ...['system app chooser', 'vlc', 'mx player'],
          'subtitle',
          'subtitles',
          'audio track',
          'skip intro',
          'skip credits',
          'outro',
          'auto provider',
          'skipdb',
          'introdb',
          'theintrodb',
          'watch history',
          'watched',
          'completion',
          'threshold',
          'movie',
          'episode',
        ],
      ),
      nav(
        SettingsRows.remote,
        'Devices',
        _pageNavigation.openRemoteControl,
        keywords: const [
          'cast',
          'handoff',
          'phone',
          'receive',
          'send',
          'setup',
        ],
      ),
      // Search
      nav(
        SettingsRows.searchSettings,
        'Search',
        _connectionNavigation.openTorrentSettings,
        keywords: const ['engines', 'sorting', 'torrent', 'sources'],
      ),
      nav(
        SettingsRows.filterSettings,
        'Search',
        _pageNavigation.openFilterSettings,
        keywords: const [
          'quality',
          'resolution',
          '1080p',
          '4k',
          '2160p',
          'hdr',
          'language',
          'codec',
          'hevc',
          'sdr',
          'dolby vision',
          'dynamic range',
        ],
      ),
      nav(
        SettingsRows.providerSettings,
        'Search',
        _pageNavigation.openProviderSettings,
        keywords: const [
          'default provider',
          'add torrent',
          'debrid',
          'ask every time',
          'show provider selection dialog',
          'torbox',
          'real-debrid',
          'premiumize',
          'alldebrid',
          'pikpak',
        ],
      ),
      nav(
        SettingsRows.quickPlay,
        'Search',
        _pageNavigation.openQuickPlaySettings,
        keywords: const ['instant', 'auto play', 'one tap'],
      ),
      nav(
        SettingsRows.discoverDefault,
        'Discover',
        _pageNavigation.openDiscoverSettings,
        keywords: const [
          'remember last',
          'default source',
          'continue watching',
          'trakt',
          'simkl',
          'stremio addon',
          'movie tag',
          'series tag',
          'ratings',
          'poster titles',
          'hide titles',
        ],
      ),
      // "addon" was a settings search dead end. This is NOT a settings page,
      // so it opens the Addons TAB (the house switchTab idiom) rather than
      // pushing a page: the tab resolves the hub-vs-classic flag itself, and
      // the standalone `StremioAddonsPage`/`EngineImportPage` wrappers are
      // stale duplicates of the tab bodies that nothing else renders.
      // Its own category, because it does not live in a settings section.
      SettingsSearchEntry(
        icon: Icons.extension_rounded,
        title: 'Addons',
        subtitle: 'Stremio addons and torrent search engines',
        category: 'Addons',
        keywords: const [
          'addon',
          'addons',
          'stremio',
          'manifest',
          'install',
          'catalog',
          'catalogs',
          'subtitles',
          'torrentio',
          'marketplace',
          'engine',
          'engines',
          'import',
          'yaml',
          'add engine',
          'import from file',
          'remove addon',
          'delete all addons',
          'view details',
          'resources',
          'id prefixes',
          'last checked',
        ],
        onTap: () async => MainPageBridge.switchTab?.call(MainTab.addons),
      ),

      // TV Mode
      nav(
        SettingsRows.debrifyTv,
        'Live TV & DVR',
        _connectionNavigation.openDebrifyTvSettings,
        keywords: const ['channels', 'limits', 'playback', 'android tv'],
      ),
      // One row, one entry: the recordings page owns the whole DVR — a second
      // "IPTV recording" entry pointed at the same page and only split the
      // keywords. The engine/battery/concurrency switches live in IPTV
      // settings instead, and are indexed as leaves there.
      nav(
        SettingsRows.recordings,
        'Live TV & DVR',
        _pageNavigation.openRecordings,
        keywords: const [
          'record',
          'recording',
          'recordings',
          'dvr',
          'schedule',
          'scheduled',
          'timer',
          'rec',
          'library',
          'capture',
          'iptv',
          'live tv',
        ],
      ),
      nav(
        SettingsRows.iptvPlaylists,
        'Live TV & DVR',
        _connectionNavigation.openIptvSettings,
        keywords: const ['m3u', 'xtream', 'channels', 'epg', 'live tv'],
      ),
      // Reachable only from the Stremio TV screen's own gear — indexed so its
      // settings are findable where every other setting is. Categorised under
      // its own name, not a settings section it isn't a row of.
      SettingsSearchEntry(
        icon: Icons.smart_display_rounded,
        title: 'Stremio TV',
        subtitle: 'Rotation, quality, provider and playback for Stremio TV',
        category: 'Stremio TV',
        keywords: const [
          'stremio tv',
          'channel',
          'channels',
          'rotation',
          'series rotation',
          'random',
          'episodes',
          'quality',
          'debrid provider',
          'torrents first',
          'auto-refresh',
          'now playing',
          'start position',
        ],
        onTap: _connectionNavigation.openStremioTvSettings,
      ),
      SettingsSearchEntry(
        icon: SettingsRows.tvKeyboard.icon,
        title: SettingsRows.tvKeyboard.title,
        subtitle: SettingsRows.tvKeyboard.subtitle,
        category: 'Home & Display',
        keywords: const [
          'on-screen keyboard',
          'remote',
          'text input',
          'ime',
          'typing',
          // The mic key is a keyboard feature with no row of its own.
          'voice',
          'mic',
          'microphone',
          'dictation',
          'speak',
        ],
        toggleValue: () => _summaries.tvKeyboardEnabled,
        onToggle: _appearanceNavigation.toggleTvKeyboard,
      ),

      nav(
        SettingsRows.syncAndMigrate,
        'Sync and Migrate',
        _profileActions.openSyncAndMigrate,
        keywords: const [
          'webdav',
          'migration',
          'transfer',
          'apple tv',
          'tvos',
          'encrypted',
        ],
      ),

      // Downloads
      if (_downloadLocation.downloadLocationSupported)
        nav(
          SettingsRows.downloadLocation,
          'Data & Backup',
          _downloadLocation.openDownloadLocationSettings,
          subtitle: _summaries.downloadLocationSubtitle,
          keywords: const [
            'sd card',
            'folder',
            'external storage',
            'saf',
            'location',
            'path',
            'directory',
            'sd',
            'choose folder',
            'reset to default',
            'another drive',
          ],
        ),

      // Maintenance
      nav(
        SettingsRows.clearDownloads,
        'Data & Backup',
        _maintenance.clearDownloadData,
        keywords: const ['queue', 'history', 'clear', 'remove'],
      ),
      nav(
        SettingsRows.clearPlayback,
        'Data & Backup',
        _maintenance.clearPlaybackData,
        keywords: const [
          'resume',
          'watch history',
          'reset progress',
          'continue watching',
        ],
      ),

      // Backup & Restore
      nav(
        SettingsRows.createBackup,
        'Data & Backup',
        _backup.createBackup,
        keywords: const [
          'export',
          'save',
          'addons',
          'search engines',
          'all profiles',
          'shared connections',
          'encrypted',
          'password',
          'passphrase',
          'minimum 8 characters',
          'recovery code',
        ],
      ),
      nav(
        SettingsRows.restoreBackup,
        'Data & Backup',
        _restore.restoreBackup,
        keywords: const [
          'import',
          'load',
          'encrypted',
          'password',
          'passphrase',
          'unlock backup',
          'admin pin',
          'confirm admin pin',
          'profiles',
          'connections',
        ],
      ),
      if (_summaries.diagnosticExportVisible)
        nav(
          SettingsRows.exportDiagnosticLogs,
          'Data & Backup',
          _diagnostics.exportDiagnosticLogs,
          keywords: const [
            'logs',
            'diagnostics',
            'debug',
            'crash',
            'support',
            'android tv',
            'last two hours',
          ],
        ),

      // Updates
      SettingsSearchEntry(
        icon: SettingsRows.autoUpdate.icon,
        title: SettingsRows.autoUpdate.title,
        subtitle: SettingsRows.autoUpdate.subtitle,
        category: 'About',
        keywords: const ['notify', 'releases', 'startup'],
        toggleValue: () => _summaries.autoUpdateChecksEnabled,
        onToggle: _updates.toggleAutoUpdateChecks,
      ),
      SettingsSearchEntry(
        icon: SettingsRows.includeAlphaUpdates.icon,
        title: SettingsRows.includeAlphaUpdates.title,
        subtitle: SettingsRows.includeAlphaUpdates.subtitle,
        category: 'About',
        keywords: const ['alpha', 'beta', 'prerelease', 'experimental'],
        toggleValue: () => _summaries.includeAlphaUpdates,
        onToggle: _updates.toggleIncludeAlphaUpdates,
      ),
      nav(
        SettingsRows.checkUpdates,
        'About',
        _updates.checkForAppUpdates,
        subtitle: _summaries.updateSubtitle,
        keywords: const ['version', 'upgrade', 'github', 'new build'],
      ),

      // Support
      if (_summaries.supportDonation.hasProviders)
        SettingsSearchEntry(
          icon: SettingsRows.supportDebrify.icon,
          title: _summaries.supportSettingsLabel,
          subtitle: _summaries.supportSettingsSubtitle,
          category: 'About',
          keywords: const ['donate', 'tip', 'contribute', 'fund'],
          onTap: _pageNavigation.openSupportDonation,
        ),
      nav(
        SettingsRows.reddit,
        'About',
        () => launchSettingsUrl(SettingsRows.reddit.url!),
        keywords: const ['community', 'subreddit'],
      ),
      nav(
        SettingsRows.discord,
        'About',
        () => launchSettingsUrl(SettingsRows.discord.url!),
        keywords: const ['community', 'chat', 'help'],
      ),
      nav(
        SettingsRows.github,
        'About',
        () => launchSettingsUrl(SettingsRows.github.url!),
        keywords: const ['source code', 'contribute', 'issues'],
      ),

      // Danger Zone
      nav(
        SettingsRows.resetDebrify,
        'Danger Zone',
        _maintenance.resetAppData,
        destructive: true,
        keywords: const ['wipe', 'factory reset', 'clear all', 'erase'],
      ),

      // In-page options (deep-link to the page that hosts them).
      ..._leafSearchEntries(),
    ];
  }

  /// Sublevel settings that live *inside* a subpage (cache checks, post-torrent
  /// action, filters, subtitle options…). Each is grouped under its owning
  /// page's name and deep-links to that page (no scroll-to-highlight yet), so a
  /// search like "cache" or "post torrent" surfaces every provider's option.
  /// Titles mirror the real in-page labels — keep them in sync if a page's copy
  /// changes.
  List<SettingsSearchEntry> _leafSearchEntries() {
    const pageIcons = <String, IconData>{
      'Torbox': Icons.link_rounded,
      'Premiumize': Icons.link_rounded,
      'Real Debrid': Icons.link_rounded,
      'AllDebrid': Icons.link_rounded,
      'PikPak': Icons.link_rounded,
      'WebDAV': Icons.cloud_rounded,
      'Indexer Managers': Icons.manage_search_rounded,
      'Engines': Icons.search_rounded,
      'Filters': Icons.filter_list_rounded,
      'Default Provider': Icons.cloud_sync_rounded,
      'Quick Play': Icons.bolt_rounded,
      'Home Screen': Icons.home_rounded,
      'Launch Animation': Icons.animation_rounded,
      'Advanced': Icons.tune_rounded,
      'Sidebar': Icons.view_sidebar_rounded,
      'Profile Picker': Icons.switch_account_rounded,
      'Playback': Icons.open_in_new_rounded,
      'Debrify TV': Icons.live_tv_rounded,
      'Stremio TV': Icons.smart_display_rounded,
      'IPTV Playlists': Icons.playlist_play_rounded,
      'Recordings': Icons.fiber_dvr_rounded,
      'Trakt': Icons.sync_rounded,
      'Tracking': Icons.sync_alt_rounded,
      'Simkl': Icons.sync_rounded,
      'MDBList': Icons.list_alt_rounded,
      'Profiles': Icons.people_alt_rounded,
      'Remote': Icons.phonelink_rounded,
    };
    final pageOpeners = <String, Future<void> Function()>{
      'Torbox': _connectionNavigation.openTorboxSettings,
      'Premiumize': _connectionNavigation.openPremiumizeSettings,
      'Real Debrid': _connectionNavigation.openRealDebridSettings,
      'AllDebrid': _connectionNavigation.openAllDebridSettings,
      'PikPak': _connectionNavigation.openPikPakSettings,
      'WebDAV': _connectionNavigation.openWebDavSettings,
      'Indexer Managers': _connectionNavigation.openIndexerManagersSettings,
      'Engines': _connectionNavigation.openTorrentSettings,
      'Filters': _pageNavigation.openFilterSettings,
      'Default Provider': _pageNavigation.openProviderSettings,
      'Quick Play': _pageNavigation.openQuickPlaySettings,
      'Home Screen': _pageNavigation.openHomePageSettings,
      'Launch Animation': _appearanceNavigation.openLaunchAnimationPage,
      'Advanced': _appearanceNavigation.openThemeTokensPage,
      'Sidebar': _appearanceNavigation.openSidebarCustomization,
      'Profile Picker': _appearanceNavigation.openProfileAppearance,
      'Playback': _pageNavigation.openExternalPlayerSettings,
      'Debrify TV': _connectionNavigation.openDebrifyTvSettings,
      'Stremio TV': _connectionNavigation.openStremioTvSettings,
      'IPTV Playlists': _connectionNavigation.openIptvSettings,
      'Recordings': _pageNavigation.openRecordings,
      'Trakt': _connectionNavigation.openTraktSettings,
      'Tracking': _connectionNavigation.openTrackingSettings,
      'Simkl': _connectionNavigation.openSimklSettings,
      'MDBList': _connectionNavigation.openMdblistSettings,
      'Profiles': _profileActions.switchProfile,
      'Remote': _pageNavigation.openRemoteControl,
    };

    SettingsSearchEntry leaf(
      String page,
      String title,
      String subtitle,
      List<String> keywords, {
      // Overrides the page's opener for a leaf that wants a deeper landing
      // (the add-source form rather than the IPTV page's default view).
      Future<void> Function()? onTap,
    }) => SettingsSearchEntry(
      icon: pageIcons[page]!,
      title: title,
      subtitle: subtitle,
      category: page,
      keywords: keywords,
      onTap: onTap ?? pageOpeners[page]!,
    );

    List<String> optionLabels(Iterable<String> values) => [
      for (final value in values) value.toLowerCase(),
    ];

    List<String> externalPlayerLabels() {
      if (kIsWeb) return const [];
      if (Platform.isMacOS) {
        return optionLabels(
          ExternalPlayer.values.map((player) => player.displayName),
        );
      }
      if (Platform.isLinux) {
        return optionLabels(
          LinuxExternalPlayer.values.map((player) => player.displayName),
        );
      }
      if (Platform.isWindows) {
        return optionLabels(
          WindowsExternalPlayer.values.map((player) => player.displayName),
        );
      }
      if (Platform.isIOS) {
        return optionLabels(
          iOSExternalPlayer.values
              .where((player) => !PlatformUtil.isTvOS || player.availableOnTvos)
              .map((player) => player.displayName),
        );
      }
      return const [];
    }

    const audioLanguageLabels = [
      'no preference',
      'english',
      'spanish',
      'french',
      'german',
      'italian',
      'portuguese',
      'russian',
      'japanese',
      'korean',
      'chinese',
      'arabic',
      'hindi',
      'telugu',
      'dutch',
      'polish',
      'turkish',
      'swedish',
      'danish',
      'norwegian',
      'finnish',
    ];

    const subtitleLanguageLabels = [
      ...audioLanguageLabels,
      'portuguese brazil',
      'brazilian portuguese',
      'pt-br',
      'off',
      'estonian',
      'croatian',
      'serbian',
      'bosnian',
      'macedonian',
      'slovenian',
      'czech',
      'slovak',
      'hungarian',
      'romanian',
      'bulgarian',
      'ukrainian',
      'greek',
      'latvian',
      'lithuanian',
      'hebrew',
      'persian',
      'thai',
      'vietnamese',
      'indonesian',
      'malay',
      'bengali',
      'tamil',
      'marathi',
      'gujarati',
      'kannada',
      'malayalam',
      'punjabi',
    ];

    const advancedAppearanceOptions =
        <({String title, String subtitle, List<String> keywords})>[
          (
            title: 'Accent',
            subtitle: 'The colour used to mean “this one”',
            keywords: ['color', 'colour', 'theme', 'selected'],
          ),
          (
            title: 'Focus',
            subtitle: 'The colour of the cursor',
            keywords: ['cursor', 'focus color', 'focus colour', 'dpad'],
          ),
          (
            title: 'Progress',
            subtitle: 'Progress bars and watched marks',
            keywords: ['watched', 'marks', 'bar', 'state', 'colour', 'color'],
          ),
          (
            title: 'Callout',
            subtitle: 'Badges and highlights',
            keywords: ['badge', 'highlight', 'colour', 'color'],
          ),
          (
            title: 'Background',
            subtitle: 'The page behind everything',
            keywords: ['ground', 'surface', 'page', 'colour', 'color'],
          ),
          (
            title: 'Text',
            subtitle: 'The ink drawn over the background',
            keywords: ['ink', 'foreground', 'readability', 'colour', 'color'],
          ),
          (
            title: 'Corners',
            subtitle: 'How round cards are',
            keywords: ['radius', 'round', 'square', 'shape', 'cards'],
          ),
          (
            title: 'Buttons',
            subtitle: 'How round buttons and pills are',
            keywords: ['pill radius', 'round', 'square', 'shape'],
          ),
          (
            title: 'Titles',
            subtitle: 'The font used for display titles',
            keywords: ['display font', 'typeface', 'typography'],
          ),
          (
            title: 'Body',
            subtitle: 'The font used for everything else',
            keywords: ['body font', 'typeface', 'typography'],
          ),
          (
            title: 'Cursor',
            subtitle: 'How a focused item is expressed',
            keywords: [
              'focus expression',
              'ring',
              'scale',
              'lift',
              'invert',
              'flood',
              'parallax',
            ],
          ),
          (
            title: 'Character',
            subtitle: 'The tempo of app motion',
            keywords: ['motion', 'animation', 'standard', 'snap', 'glide'],
          ),
          (
            title: 'Entrances',
            subtitle: 'How new content arrives',
            keywords: ['motion', 'animation', 'transition'],
          ),
          (
            title: 'When idle',
            subtitle: 'What happens when interaction stops',
            keywords: ['idle policy', 'motion', 'animation'],
          ),
          (
            title: 'Separation',
            subtitle: 'How one surface is distinguished from another',
            keywords: ['space', 'rule', 'glass', 'fill', 'panel', 'surface'],
          ),
          (
            title: 'Scrims',
            subtitle: 'The fade behind text on artwork',
            keywords: ['scrim', 'gradient', 'artwork', 'readability'],
          ),
          (
            title: 'Frames',
            subtitle: 'How posters are edged',
            keywords: ['artwork', 'poster', 'border', 'frame'],
          ),
          (
            title: 'Grade',
            subtitle: 'Colour treatment over artwork',
            keywords: ['artwork', 'color grade', 'colour grade', 'filter'],
          ),
          (
            title: 'Room colour',
            subtitle: 'How much the page borrows from selected artwork',
            keywords: [
              'reactive room',
              'artwork',
              'ambient',
              'color',
              'colour',
            ],
          ),
          (
            title: 'Accent from artwork',
            subtitle: 'Let poster colour replace the app accent',
            keywords: ['artwork accent', 'poster', 'dynamic color', 'colour'],
          ),
          (
            title: 'Film grain',
            subtitle: 'Texture layered over the interface',
            keywords: ['grain', 'noise', 'texture', 'cinema'],
          ),
          (
            title: 'Sheen',
            subtitle: 'Highlight along the top of a surface',
            keywords: ['texture', 'highlight', 'surface'],
          ),
          (
            title: 'Vignette',
            subtitle: 'Darkening toward the screen edges',
            keywords: ['texture', 'dark edges', 'artwork'],
          ),
          (
            title: 'Focus glow',
            subtitle: 'Halo around the cursor',
            keywords: ['bloom', 'glow', 'focus', 'cursor', 'halo'],
          ),
          (
            title: 'Sound and haptics',
            subtitle: 'What a press feels and sounds like',
            keywords: ['feedback', 'sound', 'haptic', 'vibration'],
          ),
          (
            title: 'While loading',
            subtitle: 'How not-yet-arrived content appears',
            keywords: ['skeleton', 'loading', 'placeholder', 'shimmer'],
          ),
        ];

    return [
      // Debrid providers — cache checks, post-torrent action, file handling.
      leaf(
        'Torbox',
        'Check Torbox cache during searches',
        'Verify a cached copy before enabling quick actions',
        const ['cache', 'cached', 'quick action', 'badge', 'instant'],
      ),
      leaf(
        'Torbox',
        'Post-Torrent Action',
        'What happens after adding a torrent to Torbox',
        const [
          'after adding',
          'post torrent',
          'none',
          'let me choose',
          'play video',
          'download to device',
          'open in torbox',
          'add to playlist',
          'add to channel',
          'debrify tv',
        ],
      ),
      leaf(
        'Torbox',
        'Hide Torbox from Navigation',
        'Hide the Torbox tab from the nav bar',
        const ['hide', 'navigation', 'nav', 'tab'],
      ),
      leaf(
        'Torbox',
        'Enable Torbox',
        'Turn the Torbox integration on or off',
        const ['enable', 'disable', 'turn off', 'integration', 'account'],
      ),
      leaf(
        'Premiumize',
        'Check Premiumize cache during searches',
        'Show a cached badge on Premiumize results',
        const ['cache', 'cached', 'badge', 'instant'],
      ),
      leaf(
        'Premiumize',
        'Post-Torrent Action',
        'What happens after adding a torrent to Premiumize',
        const [
          'after adding',
          'post torrent',
          'none',
          'let me choose',
          'play video',
          'download to device',
          'open in premiumize',
          'add to channel',
          'debrify tv',
        ],
      ),
      leaf(
        'Premiumize',
        'Hide Premiumize from Navigation',
        'Hide the Premiumize tab from the nav bar',
        const ['hide', 'navigation', 'nav', 'tab'],
      ),
      leaf(
        'Premiumize',
        'Enable Premiumize',
        'Turn the Premiumize integration on or off',
        const ['enable', 'disable', 'turn off', 'integration', 'account'],
      ),
      leaf(
        'Real Debrid',
        'File Selection',
        'How files are picked when adding to Real-Debrid',
        const [
          'file selection',
          'smart',
          'largest',
          'video files',
          'all files',
        ],
      ),
      leaf(
        'Real Debrid',
        'Post-Torrent Action',
        'What happens after adding a torrent to Real-Debrid',
        const [
          'after adding',
          'post torrent',
          'none',
          'let me choose',
          'play video',
          'download to device',
          'open in real-debrid',
          'add to playlist',
          'add to channel',
          'debrify tv',
        ],
      ),
      leaf(
        'Real Debrid',
        'Skip blocked torrents',
        'Skip likely-blocked releases in Quick Play',
        const [
          'content filter',
          'bypass',
          'blocked',
          'web-dl',
          'webrip',
          'hdrip',
        ],
      ),
      leaf(
        'Real Debrid',
        'Hide Real Debrid from Navigation',
        'Hide the Real-Debrid tab from the nav bar',
        const ['hide', 'navigation', 'nav', 'tab'],
      ),
      leaf(
        'Real Debrid',
        'Enable Real Debrid',
        'Turn the Real-Debrid integration on or off',
        const ['enable', 'disable', 'turn off', 'integration', 'account'],
      ),
      leaf(
        'AllDebrid',
        'Post-Torrent Action',
        'What happens after adding a torrent to AllDebrid',
        const [
          'after adding',
          'post torrent',
          'none',
          'let me choose',
          'play video',
          'download to device',
        ],
      ),
      leaf(
        'AllDebrid',
        'Hide AllDebrid from Navigation',
        'Hide the AllDebrid tab from the nav bar',
        const ['hide', 'navigation', 'nav', 'tab'],
      ),
      leaf(
        'AllDebrid',
        'Enable AllDebrid',
        'Turn the AllDebrid integration on or off',
        const ['enable', 'disable', 'turn off', 'integration', 'account'],
      ),
      leaf(
        'PikPak',
        'Show Only Video Files',
        'Filter PikPak folders to video files only',
        const ['video only', 'files', 'folders', 'filter'],
      ),
      leaf(
        'PikPak',
        'Ignore Videos Under 100MB',
        'Hide small video files in PikPak',
        const ['ignore small', '100mb', 'small videos', 'filter'],
      ),
      leaf(
        'PikPak',
        'Post-Torrent Action',
        'What happens after adding a torrent to PikPak',
        const [
          'after adding',
          'post torrent',
          'none',
          'let me choose',
          'play video',
          'download to device',
          'open in pikpak',
          'add to playlist',
          'add to channel',
          'debrify tv',
        ],
      ),
      leaf(
        'PikPak',
        'Restrict Access to Folder',
        'Limit PikPak access to a single folder',
        const [
          'restrict',
          'folder',
          'access',
          'security',
          'select folder',
          'change folder',
          'remove restriction',
        ],
      ),
      leaf(
        'PikPak',
        'Hide PikPak from Navigation',
        'Hide the PikPak button and tab from the nav bar',
        const ['hide', 'navigation', 'nav', 'tab'],
      ),
      leaf(
        'PikPak',
        'Enable PikPak Integration',
        'Turn the PikPak integration on or off',
        const ['enable', 'disable', 'turn off', 'integration', 'account'],
      ),
      // Lives in the logged-OUT login form (pikpak_settings_page: the
      // `if (!_isConnected)` block), so the subtitle says where to find it
      // rather than promising a row a connected user won't see.
      leaf(
        'PikPak',
        'Reset Device ID',
        'On the PikPak login screen — issue a fresh device ID if sign-in fails',
        const ['device id', 'reset', 'login problem', 'captcha', 'sign in'],
      ),

      // WebDAV — server editor plus the three persistent switches.
      leaf(
        'WebDAV',
        'WebDAV server',
        'Add, edit, test or disconnect a WebDAV server',
        const [
          'add server',
          'another server',
          'server name',
          'server url',
          'seedbox',
          'nas',
          'username',
          'password',
          'app token',
          'save and test',
          'disconnect',
        ],
      ),
      leaf('WebDAV', 'Enable WebDAV', 'Show WebDAV features in the app', const [
        'enable',
        'disable',
        'integration',
        'cloud',
        'server',
      ]),
      leaf(
        'WebDAV',
        'Hide from navigation',
        'Keep WebDAV configured but remove its tab',
        const ['hide', 'navigation', 'nav', 'tab', 'sidebar'],
      ),
      leaf(
        'WebDAV',
        'Show videos only',
        'Hide non-video files while browsing WebDAV',
        const ['video files', 'filter', 'hide files', 'folders'],
      ),

      // Jackett / Prowlarr editor. These controls live one dialog below the
      // manager page, but the manager is the stable deep-link destination.
      leaf(
        'Indexer Managers',
        'Add or edit an indexer manager',
        'Connect a Jackett or Prowlarr server',
        const [
          'add engine',
          'edit engine',
          'type',
          'name',
          'base url',
          'api key',
          'jackett indexer id',
          'prowlarr',
          'torznab',
          'delete engine',
          'remove manager',
        ],
      ),
      leaf(
        'Indexer Managers',
        'Categories',
        'Limit a manager to Torznab category IDs',
        const ['category', 'categories', '2000', '5000', 'movies', 'series'],
      ),
      leaf(
        'Indexer Managers',
        'Max results',
        'Maximum results returned by this manager',
        const ['result limit', '25', '50', '100', '200'],
      ),
      leaf(
        'Indexer Managers',
        'Timeout seconds',
        'How long to wait for Jackett or Prowlarr',
        const ['timeout', 'connection', 'slow', '5', '600'],
      ),
      leaf(
        'Indexer Managers',
        'Enabled',
        'Include or exclude this manager from torrent searches',
        const ['enable', 'disable', 'search source', 'engine'],
      ),
      leaf(
        'Indexer Managers',
        'Test connection',
        'Check that an indexer manager is reachable',
        const ['test', 'network', 'reachable', 'jackett', 'prowlarr'],
      ),

      // Search / Filter / Provider
      leaf(
        'Engines',
        'Search engine defaults',
        'Which torrent engines searches use by default',
        const ['engine', 'engines', 'default engines', 'torrent', 'sources'],
      ),
      leaf(
        'Engines',
        'Indexer managers',
        'Jackett & Prowlarr connections for extra engines',
        const ['jackett', 'prowlarr', 'torznab', 'indexer', 'indexers'],
      ),
      leaf(
        'Filters',
        'Quality filter',
        'Default resolution filter for results',
        const ['quality', 'resolution', '4k', '2160p', '1080p', '720p', '480p'],
      ),
      leaf(
        'Filters',
        'Rip / Source filter',
        'Default release type filter',
        const [
          'rip',
          'source',
          'web-dl',
          'bluray',
          'remux',
          'brrip',
          'bdrip',
          'hdrip',
          'hdtv',
          'cam',
          'hdcam',
          'telesync',
          'dvdrip',
          'scene',
          'other',
        ],
      ),
      leaf(
        'Filters',
        'Language filter',
        'Default audio-language filter',
        const [
          'language',
          'audio',
          'english',
          'hindi',
          'spanish',
          'french',
          'german',
          'russian',
          'chinese',
          'japanese',
          'korean',
          'italian',
          'portuguese',
          'arabic',
          'multi-audio',
        ],
      ),
      leaf(
        'Filters',
        'Dynamic range',
        'Choose SDR and/or HDR torrent results',
        const [
          'sdr',
          'hdr',
          'hdr10',
          'hdr10+',
          'dolby vision',
          'dv',
          'hlg',
          'exclude hdr',
          'display',
        ],
      ),
      leaf('Filters', 'Size filter', 'Default file/pack size filter', const [
        'size',
        'gb',
        'mb',
        'file size',
        'tiny',
        'small',
        'high bitrate',
        'very large',
        'remux',
        'huge',
        'under 500 mb',
        'over 40 gb',
      ]),
      leaf(
        'Filters',
        'Clear All',
        'Remove every saved torrent-search filter',
        const ['clear filters', 'reset filters', 'remove filters', 'defaults'],
      ),
      leaf(
        'Default Provider',
        'Default Torrent Provider',
        'Which service torrents are added to',
        const [
          'default provider',
          'ask every time',
          'torbox',
          'real-debrid',
          'premiumize',
          'alldebrid',
          'pikpak',
        ],
      ),

      // Quick Play
      leaf(
        'Quick Play',
        'Play button opens',
        'Play instantly, or pick the source yourself',
        // The users who want this arrive searching for the behavior they hate,
        // not for its name — "auto play", "quick play off", "choose source".
        const [
          'auto play',
          'autoplay',
          'quick play',
          'turn off quick play',
          'choose source',
          'pick source',
          'source list',
          'always show sources',
          'always ask',
          'smart',
        ],
      ),
      leaf(
        'Quick Play',
        'Addon Priority',
        'Order engines and addons are tried',
        const ['priority', 'order', 'addons', 'engines', 'reorder', 'sources'],
      ),
      leaf(
        'Quick Play',
        'Prefer torrents',
        'Torrents first, or addon direct links first',
        const ['torrents', 'direct links', 'addons', 'prefer'],
      ),
      leaf(
        'Quick Play',
        'Streams to try',
        'How many sources Quick Play tries before giving up',
        // People search for the count they saw in the player, not its name.
        const [
          'attempts',
          'retries',
          'checking stream',
          'stream count',
          'try next',
          'failover',
          'fallback',
        ],
      ),
      leaf(
        'Quick Play',
        'Prefer season packs',
        'Grab whole seasons, or fetch one episode',
        const ['series', 'packs', 'season pack', 'episode'],
      ),
      leaf(
        'Quick Play',
        'Restore defaults',
        'Reset movie and series rules, switches and priority order',
        const ['reset', 'restore', 'default', 'undo', 'priority'],
      ),

      // Home Page
      leaf(
        'Home Screen',
        'Home Rows',
        'Choose which rows appear on Home',
        const [
          'home rows',
          'rows',
          'catalogs',
          'customize',
          'show',
          'hide',
          'arrange',
          'reorder',
          'all on',
          'all off',
          'invert',
          'continue watching',
          'trakt',
          'simkl',
          'mdblist',
          'iptv lists',
          'watchlist',
          'favorites',
          'favourites',
        ],
      ),
      leaf(
        'Home Screen',
        'Hero Source',
        'Choose which catalogs feed the Spotlight hero',
        const [
          'spotlight',
          'hero',
          'first row',
          'surprise me',
          'random',
          'my picks',
          'custom',
          'catalog',
          'reel',
        ],
      ),
      leaf(
        'Home Screen',
        'Landscape Cards',
        'Use wide 16:9 artwork instead of portrait posters',
        const [
          'landscape',
          'wide',
          '16:9',
          'poster',
          'portrait',
          'card orientation',
          'artwork',
        ],
      ),
      leaf(
        'Home Screen',
        'Continue Watching',
        'Show recently watched on Home',
        const ['continue watching', 'recently watched', 'history'],
      ),
      leaf(
        'Home Screen',
        'Hold to Quick Play',
        'Play immediately when holding a Continue Watching card',
        const [
          'hold',
          'long press',
          'quick play',
          'continue watching',
          'card action',
        ],
      ),
      leaf(
        'Home Screen',
        'Hide Provider Cards',
        'Hide debrid status cards on Home',
        const ['hide', 'provider cards', 'debrid', 'status'],
      ),
      leaf(
        'Home Screen',
        'Hide Titles and Ratings',
        'Remove title and rating text from Home cards',
        const ['hide', 'titles', 'ratings', 'cards', 'clean artwork'],
      ),
      leaf(
        'Tracking',
        'Hide watched titles',
        'Remove finished movies and shows from Home, Search and Discover',
        const [
          'hide',
          'watched',
          'seen',
          'finished',
          'completed',
          'already watched',
          'filter',
        ],
      ),
      leaf(
        'Home Screen',
        'Hide Catalog Add-on Names',
        'Remove source labels beside Home row headings',
        const [
          'hide',
          'catalog',
          'addon',
          'add-on',
          'source label',
          'row heading',
          'home cards',
        ],
      ),
      // Not on TV: TV has separate Home and Search tabs, so the page hides the
      // selector there (home_page_settings_page's !isTelevision block).
      if (!_isTelevision)
        leaf(
          'Home Screen',
          'Default view',
          'Which view Home opens on (Catalog or Keyword)',
          const [
            'default view',
            'catalog',
            'keyword',
            'landing',
            'opens on',
            'startup',
          ],
        ),
      // Both ambient-trailer surfaces now exist on every platform.
      leaf(
        'Home Screen',
        'Trailer on Home Spotlight',
        'Play a trailer in the Home and Discover hero',
        const ['trailer', 'spotlight', 'hero', 'ambient', 'autoplay'],
      ),
      leaf(
        'Home Screen',
        'Trailer on Detail Page',
        'Play a trailer behind the movie/series detail page',
        const ['trailer', 'detail page', 'preview', 'backdrop', 'autoplay'],
      ),
      leaf(
        'Home Screen',
        'Trailer Sound',
        'Play ambient Home and detail-page trailers with audio',
        const ['trailer', 'sound', 'audio', 'mute', 'silent', 'ambient'],
      ),
      leaf(
        'Home Screen',
        'Trailer volume',
        'Set the volume used by ambient trailers',
        const ['trailer', 'volume', 'sound', 'audio', 'percent', 'ambient'],
      ),
      // TV only: the native hardware-plane renderer for those trailers.
      if (_isTelevision)
        leaf(
          'Home Screen',
          'Native Trailer Surface',
          'Render trailers on a hardware surface for smoother playback',
          const [
            'native',
            'surface',
            'hardware',
            'smooth',
            'stutter',
            'glitch',
            'performance',
            'trailer',
          ],
        ),

      // Nested appearance controls that are not represented by their picker
      // choice alone.
      leaf(
        'Launch Animation',
        'Match the app theme',
        'Use the active Look\'s accent colour for the launch ident',
        const [
          'launch',
          'animation',
          'ident',
          'colour',
          'color',
          'accent',
          'look',
          'theme',
        ],
      ),
      leaf(
        'Sidebar',
        'Order & Names',
        'Reorder and rename navigation destinations',
        const [
          'sidebar items',
          'navigation',
          'reorder',
          'arrange',
          'rename',
          'labels',
          'restore default order and names',
          'reset sidebar',
        ],
      ),
      for (final option in advancedAppearanceOptions)
        leaf('Advanced', option.title, option.subtitle, option.keywords),
      leaf(
        'Advanced',
        'Reset appearance overrides',
        'Return all or one section of advanced tokens to the active Look',
        const [
          'reset',
          'restore',
          'clear changes',
          'follow the look',
          'reset colour',
          'reset ground',
          'reset shape',
          'reset type',
          'reset focus',
          'reset motion',
          'reset surfaces',
          'reset artwork',
          'reset texture',
          'reset feedback',
        ],
      ),
      if (PlatformUtil.isTvOS)
        leaf(
          'Profile Picker',
          'Personalized Top Shelf',
          'Show the unlocked active profile on the Apple TV Home Screen',
          const [
            'apple tv',
            'tvos',
            'top shelf',
            'profile',
            'home screen',
            'personalization',
          ],
        ),

      for (final section in PlaybackSettingsSection.values)
        leaf(
          'Playback',
          section.label,
          section.description,
          const [],
          onTap: () => _pageNavigation.openPlaybackSection(section),
        ),
      leaf(
        'Playback',
        'Subtitle priority',
        'Reorder embedded subtitles and subtitle addons',
        const [
          'subtitle',
          'priority',
          'order',
          'embedded',
          'addons',
          'language',
        ],
        onTap: () async {
          if (!await _profileActions.ensureProfileFeature(ProfileFeature.externalPlayers)) {
            return;
          }
          if (!mounted) return;
          await pushSettingsPage(context, const SubtitlePriorityPage());
        },
      ),
      // Player Settings
      leaf(
        'Playback',
        'Default Player',
        'Which player plays videos',
        const [
          'default player',
          'debrify player',
          'external',
          'external player',
          'built-in',
          'system app chooser',
          'deovr',
        ],
        onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.player),
      ),
      leaf(
        'Playback',
        'Default Subtitle language',
        'Preferred subtitle language',
        const [
          'subtitle',
          'subtitles',
          'language',
          'captions',
          ...subtitleLanguageLabels,
        ],
        onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.subtitles),
      ),
      leaf(
        'Playback',
        'Default Audio language',
        'Preferred audio language / track',
        const ['audio', 'language', 'track', 'dub', ...audioLanguageLabels],
        onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.audio),
      ),
      leaf(
        'Playback',
        'Subtitle Appearance',
        'Subtitle size, style, color, background & font',
        [
          'subtitle',
          'size',
          'style',
          'color',
          'background',
          'font',
          'bold',
          'outline',
          'captions',
          ...optionLabels(SubtitleSize.options.map((option) => option.label)),
          ...optionLabels(SubtitleStyle.options.map((option) => option.label)),
          ...optionLabels(SubtitleColor.options.map((option) => option.label)),
          ...optionLabels(
            SubtitleBackground.options.map((option) => option.label),
          ),
          ...optionLabels(
            SubtitleFont.builtInOptions.map((option) => option.label),
          ),
        ],
        onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.subtitles),
      ),
      leaf(
        'Playback',
        'Default Aspect Ratio',
        'Default video aspect / zoom',
        const [
          'aspect',
          'ratio',
          'zoom',
          'cinema zoom',
          'fit',
          'fill',
          'contain',
          'cover',
          'fit width',
          'fit height',
          '16:9',
          '4:3',
          '21:9',
          '1:1',
          '3:2',
          '5:4',
        ],
        onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.video),
      ),
      leaf(
        'Playback',
        'Watch completion thresholds',
        'Choose when locally tracked movies and episodes are marked watched',
        const [
          'watch history',
          'watched',
          'completion',
          'threshold',
          'movie',
          'episode',
          'series',
          'percentage',
          'percent',
          'rewatch',
        ],
        onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.player),
      ),
      leaf(
        'Playback',
        'Skip intros & credits',
        'Show manual skip buttons when timestamps are available',
        const [
          'skip intro',
          'skip credits',
          'outro',
          'opening',
          'ending',
          'skip segment',
        ],
        onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.player),
      ),
      leaf(
        'Playback',
        'Timestamp provider',
        'Choose the source for intro and outro timestamps',
        const [
          'auto',
          'skipdb',
          'introdb',
          'theintrodb',
          'provider',
          'timestamp',
          'segments',
        ],
        onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.player),
      ),
      leaf(
        'Playback',
        'Network & Buffering',
        'Connection patience & stream buffer for slow sources',
        [
          'network',
          'buffer',
          'buffering',
          'cache',
          'timeout',
          'plex',
          'slow',
          'stall',
          'patience',
          'auto-retry',
          'read-ahead',
          ...optionLabels(NetworkTuning.patienceOptions.values),
          ...optionLabels(NetworkTuning.bufferOptions.values),
        ],
        onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.player),
      ),
      if (_isAndroid)
        leaf(
          'Playback',
          'Allow system audio effects',
          'Let equalizer apps process audio (Android)',
          const ['audio effects', 'equalizer', 'wavelet', 'dolby'],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (_isAndroid)
        leaf(
          'Playback',
          'Audio passthrough (AC3 · EAC3 · DTS core)',
          'Bitstream audio to your receiver instead of decoding',
          const [
            'passthrough',
            'bitstream',
            'dts',
            'ac3',
            'dolby',
            'receiver',
            'avr',
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (PlatformUtil.isTvOS || PlatformUtil.isIosMobile)
        leaf(
          'Playback',
          'Multichannel audio (LPCM over HDMI)',
          'Surround tracks as 5.1/7.1 PCM on capable receivers',
          const [
            'multichannel',
            'surround',
            '5.1',
            '7.1',
            'lpcm',
            'audio channels',
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (PlatformUtil.isTvOS)
        leaf(
          'Playback',
          'Force software video decoding',
          'Apple TV compatibility option for videos that render wrong',
          const [
            'software decoding',
            'compatibility',
            'blue screen',
            'wrong colors',
            'hardware decoding',
            '10-bit',
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.video),
        ),
      if (PlatformUtil.isTvOS)
        leaf(
          'Playback',
          'Force stereo audio',
          'Always downmix Apple TV playback to two channels',
          const [
            'stereo',
            'downmix',
            '2 channels',
            'surround',
            'noisy',
            'distorted',
            'receiver',
            'tvos',
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (PlatformUtil.isTvOS)
        leaf(
          'Playback',
          'Use the previous audio engine',
          'Apple TV audio compatibility option',
          const [
            'legacy audio',
            'old audio engine',
            'audio output',
            'compatibility',
            'atmos',
            'no sound',
            'tvos',
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (_isAndroid && PlatformUtil.isAndroidTvCached)
        leaf(
          'Playback',
          'IPTV decoder',
          'Switch to software decoding when a channel freezes',
          const [
            'iptv',
            'decoder',
            'software',
            'hardware',
            'freeze',
            'frozen',
            'audio only',
            'no picture',
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.video),
        ),
      if (_isAndroid && !PlatformUtil.isAndroidTvCached)
        leaf(
          'Playback',
          'Video renderer',
          'Choose the Android phone/tablet video output path',
          [
            'renderer',
            'mediacodec',
            'direct surface',
            'battery',
            'performance',
            'hardware decoding',
            ...optionLabels(
              AndroidVideoRendererMode.values.map((mode) => mode.label),
            ),
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.video),
        ),
      if (_isAndroid && PlatformUtil.isAndroidTvCached)
        leaf(
          'Playback',
          'Night Mode',
          'Boost quiet sounds for late-night viewing',
          const [
            'night',
            'quiet',
            'volume',
            'dynamic range compression',
            'sleeping baby',
            'low',
            'medium',
            'high',
            'higher',
            'extreme',
            'max',
            'off',
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (PlatformUtil.supportsSubtitleAutoSync)
        leaf(
          'Playback',
          'Auto-sync addon subtitles',
          'Align downloaded subtitles to the audio automatically',
          const [
            'subtitle',
            'sync',
            'auto',
            'align',
            'timing',
            'offset',
            'experimental',
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.subtitles),
        ),
      if (_isPhone)
        leaf(
          'Playback',
          'Open the player in portrait',
          'Start videos upright instead of turning the phone landscape',
          const [
            'portrait',
            'landscape',
            'orientation',
            'rotate',
            'rotation',
            'vertical',
            'horizontal',
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.player),
        ),
      if (_preferredExternalPlayerSupported)
        leaf(
          'Playback',
          'Preferred external player',
          'Choose the external player app',
          [
            'external',
            'player app',
            'system default',
            'custom command',
            'custom url scheme',
            ...externalPlayerLabels(),
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.player),
        ),
      if (_customPlayerCommandSupported)
        leaf(
          'Playback',
          'Custom player command',
          'Custom launch command or URL scheme for an external player',
          const [
            'custom command',
            'url scheme',
            'launch',
            'arguments',
            'external',
            'save command',
            'command template',
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.player),
        ),
      leaf(
        'Playback',
        'Import Custom Font',
        'Add your own TTF/OTF font for subtitles',
        const [
          'font',
          'ttf',
          'otf',
          'import font',
          'custom font',
          'remove font',
          'delete font',
          'subtitle',
        ],
        onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.subtitles),
      ),
      // Android only: the page disables the DeoVR mode off Android and builds
      // its format controls under `Platform.isAndroid`.
      if (_isAndroid)
        leaf(
          'Playback',
          'VR / DeoVR format',
          'Screen type, stereo mode and format detection for DeoVR',
          [
            'vr',
            'deovr',
            'stereo',
            'screen type',
            '180',
            '360',
            'sbs',
            'side by side',
            'over under',
            'format',
            'auto-detect format from filename',
            'show format selection dialog',
            ...optionLabels(deovr.screenTypeLabels.values),
            ...optionLabels(deovr.stereoModeLabels.values),
          ],
          onTap: () => _pageNavigation.openPlaybackSection(PlaybackSettingsSection.player),
        ),

      // Debrify TV
      leaf(
        'Debrify TV',
        'Keyword Threshold',
        'Choose when Debrify TV fetches more or fewer results per keyword',
        const ['keyword', 'threshold', 'results', 'fetch', 'global tv mode'],
      ),
      leaf(
        'Debrify TV',
        'Batch Size',
        'Number of keywords processed in each batch',
        const ['batch', 'keywords', 'performance', 'global tv mode'],
      ),
      leaf(
        'Debrify TV',
        'Min Torrents Per Keyword',
        'Skip keywords with fewer torrent results',
        const ['minimum', 'torrents', 'keyword', 'skip', 'result count'],
      ),
      leaf(
        'Debrify TV',
        'Max Keywords (Quick Play)',
        'Limit the keywords used in Quick Play mode',
        const ['maximum', 'keyword limit', 'quick play', 'performance'],
      ),
      leaf(
        'Debrify TV',
        'Avoid NSFW Content',
        'Filter adult content out of Debrify TV results',
        const ['nsfw', 'adult', 'safe', 'filter', 'content'],
      ),
      leaf(
        'Debrify TV',
        'Prepare Torrents in Background',
        'Pre-add upcoming Real-Debrid and AllDebrid torrents',
        const [
          'background',
          'prefetch',
          'pre-fetch',
          'prepare',
          'faster playback',
          'real-debrid',
          'alldebrid',
        ],
      ),
      leaf(
        'Debrify TV',
        'Engine TV Mode',
        'Enable or disable each search engine for Debrify TV',
        const ['engine', 'tv mode enabled', 'tv mode disabled', 'toggle'],
      ),
      leaf(
        'Debrify TV',
        'Small Channel Limit',
        'Maximum results for each engine in small channel mode',
        const ['small channel', 'result limit', 'max results', 'engine'],
      ),
      leaf(
        'Debrify TV',
        'Large Channel Limit',
        'Maximum results for each engine in large channel mode',
        const ['large channel', 'result limit', 'max results', 'engine'],
      ),
      leaf(
        'Debrify TV',
        'Quick Play Limit',
        'Maximum results for each engine in Quick Play mode',
        const ['quick play', 'result limit', 'max results', 'engine'],
      ),
      leaf(
        'Debrify TV',
        'Reset to Defaults',
        'Restore the default Debrify TV engine settings',
        const ['reset', 'defaults', 'restore', 'engines'],
      ),

      // Stremio TV
      leaf(
        'Stremio TV',
        'Rotation Interval',
        'How often the now-playing item changes on movie channels',
        const ['rotation', 'interval', 'minutes', 'movie', 'change', 'shuffle'],
      ),
      leaf(
        'Stremio TV',
        'Series Rotation Interval',
        'How often the episode changes on series channels',
        const [
          'series',
          'episode',
          'rotation',
          'interval',
          'minutes',
          'change',
          'schedule',
        ],
      ),
      leaf(
        'Stremio TV',
        'Preferred Quality',
        'Prioritize streams matching this quality',
        const ['quality', '4k', '2160p', '1080p', '720p', 'resolution'],
      ),
      leaf(
        'Stremio TV',
        'Debrid Provider',
        'Which provider resolves Stremio TV torrent streams',
        const ['debrid', 'provider', 'auto', 'real-debrid', 'torbox', 'pikpak'],
      ),
      leaf(
        'Stremio TV',
        'Try torrents first',
        'Resolve torrents via debrid before trying direct streams',
        const ['torrents first', 'direct', 'stream', 'order', 'fallback'],
      ),
      leaf(
        'Stremio TV',
        'Random Episodes',
        'Pick episodes at random on series channels',
        const ['random', 'shuffle', 'episodes', 'series'],
      ),
      leaf(
        'Stremio TV',
        'Start Position',
        'Where playback begins within the current slot',
        const ['start', 'position', 'beginning', 'slot progress', 'resume'],
      ),
      leaf(
        'Stremio TV',
        'Hide Currently Playing',
        'Blur the poster and hide details for a surprise',
        const ['hide', 'spoiler', 'surprise', 'blur', 'now playing'],
      ),
      leaf(
        'Stremio TV',
        'Auto-refresh',
        'Refresh Stremio TV channels automatically',
        const ['auto refresh', 'refresh', 'update', 'channels'],
      ),

      // IPTV playlists page — the whole source/guide/startup surface.
      leaf(
        'IPTV Playlists',
        'Add a source',
        'Add an M3U link, an Xtream login, or a local file',
        const [
          'add',
          'source',
          'playlist',
          'm3u',
          'm3u8',
          'xtream',
          'login',
          'url',
          'file',
          'import',
          'from url',
          'from file',
          'browse files',
          'name your playlist',
        ],
        onTap: _connectionNavigation.openIptvAddSource,
      ),
      leaf(
        'IPTV Playlists',
        'Edit source',
        'Change a playlist name, URL, guide or Xtream credentials',
        const [
          'edit playlist',
          'rename source',
          'm3u url',
          'server',
          'username',
          'password',
          'xtream',
          'xmltv',
          'epg',
        ],
      ),
      leaf(
        'IPTV Playlists',
        'Remove source',
        'Delete an IPTV source while keeping lists and watch history',
        const [
          'remove playlist',
          'delete source',
          'disconnect',
          'shared source',
          'keep lists',
          'watch history',
        ],
      ),
      leaf(
        'IPTV Playlists',
        'Guide (EPG) source',
        'Provider guide or a custom XMLTV URL per source',
        const [
          'epg',
          'guide',
          'xmltv',
          'tv guide',
          'programme',
          'schedule',
          'now next',
          'custom guide',
        ],
      ),
      leaf(
        'IPTV Playlists',
        'Hidden categories',
        'Bring back categories you hid on the IPTV page',
        const [
          'hidden',
          'hide',
          'unhide',
          'category',
          'categories',
          'adult',
          'restore',
          'show all',
          'hide all',
          'filter categories',
          'live tv',
          'movies',
          'series',
        ],
      ),
      leaf(
        'IPTV Playlists',
        'Create list',
        'Make a custom list for saved IPTV channels',
        const [
          'channel lists',
          'new list',
          'saved channels',
          'favorites',
          'favourites',
          'collection',
        ],
      ),
      leaf(
        'IPTV Playlists',
        'Manage channel lists',
        'Rename, reorder or delete a custom IPTV list',
        const [
          'rename list',
          'move up',
          'move down',
          'reorder',
          'delete list',
          'remove list',
          'channels are kept',
        ],
      ),
      leaf(
        'IPTV Playlists',
        'Channel order',
        'Arrange channels inside Favorites and saved lists',
        const [
          'channel order',
          'manual order',
          'sort favorites',
          'sort favourites',
          'reorder channels',
          'dpad',
        ],
        onTap: _connectionNavigation.openIptvChannelOrder,
      ),
      leaf(
        'IPTV Playlists',
        'Default playlist',
        'Which source loads when you open IPTV',
        const ['default', 'playlist', 'source', 'opens', 'preferred'],
      ),
      leaf(
        'IPTV Playlists',
        'Refresh now',
        'Re-fetch channels and rebuild the catalog',
        const [
          'refresh',
          'refresh playlist',
          'reload',
          'update',
          'rebuild',
          'catalog',
          're-fetch',
          'missing channels',
        ],
      ),
      leaf(
        'IPTV Playlists',
        'Start on a channel',
        'Open straight into live TV when Debrify starts',
        const [
          'startup channel',
          'startup',
          'boot',
          'launch',
          'autoplay',
          'live tv',
        ],
      ),
      leaf(
        'IPTV Playlists',
        'Startup channel choice',
        'Start on the last watched channel or a specific channel',
        const [
          'last watched channel',
          'specific channel',
          'choose channel',
          'change channel',
          'pinned channel',
          'startup mode',
        ],
      ),
      leaf(
        'IPTV Playlists',
        'Track movies and series',
        'Add IPTV on-demand playback to Continue Watching',
        const [
          'continue watching',
          'iptv history',
          'resume',
          'vod',
          'movies',
          'series',
          'shelf',
        ],
      ),
      // The recording switches live on the IPTV page, but only where the
      // engine can actually run (Android 10+) — same gate as the DVR row.
      if (_summaries.recordingSearchable) ...[
        leaf(
          'IPTV Playlists',
          'Background recording engine',
          'Keep recordings running when you zap or leave the app',
          const [
            'background',
            'engine',
            'recording',
            'dvr',
            'scheduled',
            'player-tied',
          ],
        ),
        leaf(
          'IPTV Playlists',
          'Simultaneous recordings',
          'How many recordings can run at once',
          const [
            'simultaneous',
            'concurrent',
            'parallel',
            'at once',
            'connections',
            'limit',
          ],
        ),
        leaf(
          'IPTV Playlists',
          'Battery optimization',
          'Exclude Debrify so recordings survive doze',
          const [
            'battery',
            'doze',
            'optimization',
            'background',
            'killed',
            'stops',
          ],
        ),
      ],
      // Gated on a backend that actually records — the Android engine OR the
      // desktop recorder. NOT on [_recordingSearchable] alone (Android-only,
      // which would hide these on desktop where they work), and not ungated
      // (on iOS neither backend exists: scheduling raises a storage error and
      // the library is permanently empty).
      if (_recordingSupported) ...[
        leaf(
          'Recordings',
          'Schedule a recording',
          'Record a channel at a set date and time',
          const [
            'schedule',
            'timer',
            'record later',
            'date',
            'start time',
            'alarm',
          ],
        ),
        leaf(
          'Recordings',
          'Recordings library',
          'Your recorded files, and where they are saved',
          const [
            'library',
            'recorded',
            'files',
            'folder',
            'storage',
            'downloads',
            'delete recording',
          ],
        ),
      ],

      if (ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted) ...[
        leaf(
          'Profiles',
          'Ask who\'s watching at startup',
          'Show the profile picker whenever Debrify opens',
          const [
            'always ask',
            'profile behavior',
            'profile picker',
            'startup',
            'launch',
            'who is watching',
          ],
        ),
        leaf(
          'Profiles',
          'Send profiles to TV',
          'Transfer profiles, connections and PINs to another device',
          const [
            'household',
            'transfer',
            'pair',
            'remote',
            'connections',
            'pins',
            'setup',
          ],
        ),
        leaf(
          'Profiles',
          'Manage profiles',
          'Create, edit, switch, enable, disable or delete a profile',
          const [
            'current profile',
            'other profiles',
            'create profile',
            'edit profile',
            'switch profile',
            'delete profile',
            'disable profile',
            'enable profile',
            'name',
            'avatar',
            'save name and avatar',
            'choose image or gif',
            'pin',
            'pin protection',
            'set pin',
            'change pin',
            'remove pin',
            'access',
            'admin',
            'member',
            'kid',
            'profile diagnostics',
          ],
        ),
      ],

      // Trackers — the pages behind the connection cards.
      leaf(
        'Tracking',
        'Scrobble',
        'Choose which connected services record playback',
        const [
          'sync',
          'catalog',
          'watchlist',
          'collection',
          'history',
          'scrobble',
          'refresh',
        ],
      ),
      leaf(
        'Tracking',
        'Progress source',
        'Choose resume, progress bar and Continue Watching ownership',
        const [
          'sync',
          'catalog',
          'watchlist',
          'plan to watch',
          'history',
          'scrobble',
          'refresh',
        ],
      ),
      leaf(
        'Tracking',
        'Watched ticks',
        'Choose which histories draw watched ticks on posters',
        const ['watched', 'checkmark', 'tick', 'local', 'trakt', 'simkl'],
      ),
      if (kMdblistEnabled)
        leaf(
          'MDBList',
          'MDBList API Key',
          'Connect MDBList and browse your lists',
          const [
            'api key',
            'add api key',
            'logout',
            'lists',
            'liked',
            'supporter',
            'usage',
            'mdblist preferences',
            'open mdblist.com/preferences',
          ],
        ),

      // Remote
      leaf(
        'Remote',
        'Control another device',
        'Use this device as a remote, or send your setup to another',
        const [
          'remote',
          'control',
          'pair',
          'wifi',
          'send setup',
          'push addons',
          'handoff',
          'd-pad',
          'paired remote devices',
          'manage pairing',
        ],
      ),
      leaf(
        'Remote',
        'Receive from another device',
        'Let another device control this one or send it addons & channels',
        const [
          'receive',
          'target',
          'pair',
          'import setup',
          'addons',
          'channels',
          'sessions',
          'paired remote devices',
          'manage pairing',
        ],
      ),
    ];
  }

  void focusFirstCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _firstCardFocusNode.requestFocus();
      }
    });
  }


  Future<void> _loadDownloadLocation() async {
    if (!_downloadLocation.downloadLocationSupported) return;
    final String? name = _downloadLocation.downloadLocationUsesSaf
        ? await DeviceStorage.getDownloadTreeDisplayName()
        : await DeviceStorage.getDownloadDirPath();
    if (!mounted) return;
    setState(() {
      _summaries.downloadLocationSubtitle = name == null
          ? _downloadLocation.defaultDownloadLocationLabel
          : 'Custom: $name';
    });
  }

  /// The Appearance rows quote live pref labels, but some of those prefs
  /// also have feature-local editors (the Home Screen page's layout row, the
  /// IPTV page's Appearance/Player guide sections, and Playback). Re-read those after
  /// any route that can reach them, so the captions never go stale. Never
  /// the full [_loadSummaries] — these are local pref reads, no network.
  Future<void> _reloadAppearanceSummaries() async {
    final tvHomeStyle = await HomeAppearanceStorage.getTvHomeStyle();
    final iptvStyle = await IptvAppearanceStorage.getIptvStyle();
    final playerGuideStyle = await IptvAppearanceStorage.getIptvPlayerGuideStyle();
    final playLoaderStyle = await PlayerAppearanceStorage.getPlayLoaderStyle();
    final tvPlayerControlsStyle =
        await PlayerAppearanceStorage.getTvPlayerControlsStyle();
    final debrifyTvStyle = await DebrifyTvStorage.getDebrifyTvStyle();
    final debrifyTvPlayerStyle = await DebrifyTvStorage.getDebrifyTvPlayerStyle();
    final playerDockStyle = await PlayerAppearanceStorage.getPlayerDockStyle();
    final playerDockPalette = await PlayerAppearanceStorage.getPlayerDockPalette();
    final playerDockSize = await PlayerAppearanceStorage.getPlayerDockSize();
    if (!mounted) return;
    setState(() {
      _summaries.tvHomeStyle = tvHomeStyle;
      _summaries.iptvStyle = iptvStyle;
      _summaries.playerGuideStyle = playerGuideStyle;
      _summaries.playLoaderStyle = playLoaderStyle;
      _summaries.tvPlayerControlsStyle = tvPlayerControlsStyle;
      _summaries.debrifyTvStyle = debrifyTvStyle;
      _summaries.debrifyTvPlayerStyle = debrifyTvPlayerStyle;
      _summaries.playerDockStyle = playerDockStyle;
      _summaries.playerDockPalette = playerDockPalette;
      _summaries.playerDockSize = playerDockSize;
    });
  }

  DateTime? _tryParseDate(String value) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
