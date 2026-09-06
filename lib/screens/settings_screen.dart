import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform, exit;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/app_version_info.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/webdav_item.dart';
import '../models/android_video_renderer_mode.dart';
import '../models/profiles/profile_policy.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/user_profile.dart';
import '../services/main_page_bridge.dart';
import '../services/external_player_service.dart';
import '../services/play_loader_style.dart';
import '../services/subtitle_font_service.dart';
import '../services/text_brightness.dart';
import '../services/profiles/profile_runtime.dart';
import '../services/profiles/connection_resource_service.dart';
import '../services/profiles/portable_profile_package.dart';
import '../services/profiles/profile_app_lifecycle_participant.dart';
import '../services/profiles/profile_lifecycle.dart';
import '../services/profiles/profile_lock_controller.dart';
import '../services/profiles/profile_authorization.dart';
import '../services/profiles/profile_bootstrap.dart';
import '../services/profiles/profile_device_reset_service.dart';
import '../services/profiles/profile_reset_service.dart';
import '../services/webdav_sync/webdav_sync_library_models.dart';
import '../utils/platform_util.dart';
import '../utils/deovr_utils.dart' as deovr;

import '../services/analytics_service.dart';
import '../services/diagnostic_log.dart';
import '../services/account_service.dart';
import '../services/backup_restore_service.dart';
import '../services/iptv_transfer_payload.dart';
import '../services/download_service.dart';
import '../services/mdblist/mdblist_service.dart';
import '../services/simkl/simkl_service.dart';
import '../services/storage_service.dart';
import '../services/support_remote_config_service.dart';
import '../services/torbox_account_service.dart';
import '../services/premiumize_account_service.dart';
import '../services/alldebrid_account_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/stremio_service.dart';
import '../services/android_native_downloader.dart';
import '../services/live_recording_service.dart';
import '../services/desktop_schedule_service.dart';
import '../services/update_service.dart';
import '../widgets/support_donation_chooser_dialog.dart';
import '../widgets/tv_text_field.dart';
import 'settings/debrify_tv_settings_page.dart';
import 'settings/settings_tv_layout.dart';
import 'settings/settings_spotlight_shell.dart';
import 'settings/settings_search.dart';
import 'settings/discover_layout_page.dart';
import 'settings/discover_settings_page.dart';
import 'settings/iptv_style_page.dart';
import 'settings/debrify_tv_style_page.dart';
import 'settings/text_brightness_page.dart';
import 'settings/launch_animation_page.dart';
import '../widgets/launch/launch_ident.dart';
import 'settings/detail_page_style_page.dart';
import 'settings/app_theme_page.dart';
import 'settings/looks_page.dart';
import 'settings/theme_tokens_page.dart';
import 'settings/theme_lab_page.dart';
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
import 'settings/tv_render_quality_page.dart';
import 'settings/tv_hero_artwork_quality_page.dart';
import 'settings/tv_screen_size_page.dart';
import 'settings/recordings_page.dart';
import 'settings/desktop_sidebar_style_page.dart';
import 'settings/tv_sidebar_style_page.dart';
import 'settings/sidebar_customization_page.dart';
import 'settings/profile_backup_flows.dart';
import 'settings/sync_and_migrate_page.dart';
import 'settings/profile_appearance_page.dart';
import 'settings/widgets/settings_widgets.dart';
import 'settings/pikpak_settings_page.dart';
import 'settings/settings_summary_reads.dart';
import 'settings/real_debrid_settings_page.dart';
import 'settings/iptv_settings_page.dart';
import 'settings/iptv_channel_order_page.dart';
import 'settings/collections_settings_page.dart';
import 'settings/home_page_settings_page.dart';
import 'settings/torbox_settings_page.dart';
import 'settings/premiumize_settings_page.dart';
import 'settings/alldebrid_settings_page.dart';
import 'settings/torrent_settings_page.dart';
import 'settings/filter_settings_page.dart';
import 'settings/indexer_managers_settings_page.dart';
import 'settings/provider_settings_page.dart';
import 'settings/quick_play_settings_page.dart';
import 'settings/external_player_settings_page.dart';
import 'video_player/services/subtitle_settings_service.dart';
import 'video_player/services/network_tuning.dart';
import 'settings/profiles_settings_page.dart';
import 'profiles/profile_setup_flow.dart';
import 'profiles/profile_wall_screen.dart';
import 'settings/trakt_settings_page.dart';
import 'settings/simkl_settings_page.dart';
import 'settings/mdblist_settings_page.dart';
import 'settings/tracking_settings_page.dart';
import 'settings/webdav_settings_page.dart';
import 'settings/stremio_tv_settings_page.dart';
import '../widgets/remote/remote_role_picker_screen.dart';
import '../theme/app_looks.dart';
import '../theme/app_theme_scope.dart';
import '../models/tv_hero_artwork_quality.dart';

@visibleForTesting
bool shouldApplyPendingCredentialOverride({
  required Set<ConnectionResourceType> pendingTypes,
  required Set<ConnectionResourceType> providerTypes,
  required bool ownCredentialPresent,
}) => !ownCredentialPresent && pendingTypes.any(providerTypes.contains);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.summaryReadOverrides = const {}});

  @visibleForTesting
  final Map<String, Future<Object?> Function()> summaryReadOverrides;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  Set<String> _summaryFailures = {};
  bool _summaryLoadFailed = false;
  Set<String> _summaryUnavailable = {};
  bool _isAndroidTv = false;

  // Focus node for the first connection card (Real-Debrid) for TV navigation
  final FocusNode _firstCardFocusNode = FocusNode(debugLabel: 'firstCardFocus');

  /// IPTV recording engine availability (Android 10+); gates its search entry.
  bool _recordingSearchable = false;

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

  /// The IPTV Appearance picker renders only where the cockpit does (Android
  /// TV, desktop) — the SAME gate IptvSettingsPage uses for its section
  /// (PlatformUtil's cache, not this screen's own `_isAndroidTv`, which
  /// handles probe failures differently and could disagree).
  bool get _iptvAppearanceSearchable =>
      PlatformUtil.isAndroidTvCached ||
      (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows));

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
  /// [_recordingSearchable]) or the desktop recorder. On iOS it has neither —
  /// scheduling only raises a storage error and the library is always empty.
  bool get _recordingSupported =>
      _recordingSearchable || DesktopScheduleService.instance.isSupported;

  // TV content focus handler (stored for proper unregistration)
  VoidCallback? _tvContentFocusHandler;

  bool _realDebridConnected = false;
  String _realDebridStatus = 'Not connected';
  String _realDebridCaption = 'Tap to connect';

  bool _torboxConnected = false;
  String _torboxStatus = 'Not connected';
  String _torboxCaption = 'Tap to connect';

  bool _premiumizeConnected = false;
  String _premiumizeStatus = 'Not connected';
  String _premiumizeCaption = 'Tap to connect';

  bool _allDebridConnected = false;
  String _allDebridStatus = 'Not connected';
  String _allDebridCaption = 'Tap to connect';

  bool _pikpakConnected = false;
  String _pikpakStatus = 'Not connected';
  String _pikpakCaption = 'Tap to connect';

  bool _webDavConnected = false;
  String _webDavStatus = 'Not connected';
  String _webDavCaption = 'Tap to connect';

  bool _iptvCredentialsPending = false;

  bool _traktConnected = false;
  String _traktStatus = 'Not connected';
  String _traktCaption = 'Tap to connect';

  bool _simklConnected = false;
  String _simklStatus = 'Not connected';
  String _simklCaption = 'Tap to connect';

  bool _mdblistConnected = false;
  String _mdblistStatus = 'Not connected';
  String _mdblistCaption = 'Tap to connect';

  bool _indexerManagersConfigured = false;
  String _indexerManagersStatus = 'Not configured';
  String _indexerManagersCaption = 'Connect Jackett or Prowlarr';

  String _appVersion = '';
  String _currentVersionName = '';
  bool _checkingUpdates = false;
  String _updateSubtitle = 'Check for new builds from GitHub releases';
  StreamSubscription<Map<String, dynamic>>? _updateDownloadSub;
  String? _updateDownloadTaskId;
  bool _autoUpdateChecksEnabled = true;
  bool _diagnosticExportVisible = false;
  bool _exportingDiagnostics = false;
  bool _tvKeyboardEnabled = true;
  int _tvUiScalePercent = StorageService.kTvUiScaleDefault;
  TvRenderQuality _tvRenderQuality = TvRenderQuality.auto;
  TvHeroArtworkQuality _tvHeroArtworkQuality = TvHeroArtworkQuality.automatic;
  String _tvHomeStyle = 'canvas';
  String _discoverLayout = 'stage';
  String _tvSidebarStyle = 'ghost';
  String _iptvStyle = 'command';
  String _debrifyTvStyle = 'grid';
  String _playerGuideStyle = 'classic';
  String _playLoaderStyle = PlayLoaderStyleController.defaultStyle;
  String _tvPlayerControlsStyle = 'marquee';
  String _debrifyTvPlayerStyle = 'cinema';
  String _playerDockStyle = 'classic';
  String _playerDockPalette = 'ultraviolet';
  String _playerDockSize = 'auto';
  // The placeholder the Appearance row shows for the one frame before the
  // async load lands; a literal here would flash the wrong label.
  String _detailPageStyle = StorageService.kDetailPageStyleDefault;
  String _detailTheme = 'signal';
  String _parentsGuideStyle = 'compass';
  String _phoneNavStyle = 'classic';
  String _desktopSidebarStyle = 'rail';
  String _textBrightness = 'bright';
  String _launchAnimation = 'trace';
  String _downloadLocationSubtitle = 'Downloads/Debrify (default)';
  SupportDonationConfig _supportDonation = SupportDonationConfig.empty;
  String _supportSettingsLabel = 'Support Debrify';
  String _supportSettingsSubtitle = 'Help fund development with a donation';

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
          setState(() => _recordingSearchable = true);
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
    _updateDownloadSub?.cancel();
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
      _summaryLoadFailed = true;
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
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _activeProfileMayExportDiagnostics() async {
    // saveBackupFile has no user-retrievable destination on physical tvOS.
    // Keep this hidden until diagnostics use the authenticated Remote
    // transfer flow, as profile backups already do on Apple TV.
    if (PlatformUtil.isTvOS) return false;
    try {
      if (ProfileRuntime.mode == ProfileRuntimeMode.legacyCompatibility) {
        // A legacy install has one implicit device owner/admin.
        return true;
      }
      final registry = ProfileBootstrap.registry;
      final authorization = await ProfileAuthorizationContext.capture(registry);
      final actor = await authorization.validate(registry);
      return actor.role == UserProfileRole.admin;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadSummariesForCurrentProfile() async {
    // Phase 1: Load cached/local state instantly (no network)
    final startingScope = ProfileRuntime.scope.value;
    _summaryLoadFailed = false;
    final summaries = SettingsSummaryReads(
      overrides: widget.summaryReadOverrides,
      onFailure: (label, error) {
        if (mounted && ProfileRuntime.scope.value == startingScope) {
          _summaryFailures = {..._summaryFailures, label};
          if (error is ResourceAuthorizationException) {
            _summaryUnavailable = {..._summaryUnavailable, label};
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
        () => StorageService.hasRealDebridCredential(),
        false,
      ),
      summaries.read(
        'Torbox',
        () => StorageService.hasTorboxCredential(),
        false,
      ),
      summaries.read(
        'PikPak',
        () => PikPakApiService.instance.isAuthenticated(),
        false,
      ),
      summaries.read('WebDAV', () => StorageService.getWebDavEnabled(), false),
      summaries.read(
        'WebDAV',
        () => StorageService.getWebDavServers(forSettings: true),
        <WebDavConfig>[],
      ),
      summaries.read('Trakt', () => StorageService.hasTraktCredential(), false),
      summaries.read('Trakt', () => StorageService.getTraktTokenExpiry(), null),
      summaries.read('Trakt', () => StorageService.getTraktUsername(), null),
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
        () => StorageService.getUpdateAutoCheckEnabled(),
        false,
      ),
      summaries.read(
        'Indexer managers',
        () => StorageService.getIndexerManagerConfigs(forSettings: true),
        [],
      ),
      summaries.read(
        'Premiumize',
        () => StorageService.hasPremiumizeCredential(),
        false,
      ),
      summaries.read(
        'AllDebrid',
        () => StorageService.hasAllDebridCredential(),
        false,
      ),
      summaries.read('Simkl', () => StorageService.hasSimklCredential(), false),
      summaries.read('Simkl', () => StorageService.getSimklUsername(), null),
      summaries.read(
        'MDBList',
        () => StorageService.hasMdblistCredential(),
        false,
      ),
      summaries.read(
        'MDBList',
        () => StorageService.getMdblistUsername(),
        null,
      ),
      summaries.read(
        'TV keyboard',
        () => StorageService.getTvKeyboardEnabled(),
        _tvKeyboardEnabled,
      ),
      summaries.read(
        'TV scale',
        () => StorageService.getTvUiScalePercent(),
        _tvUiScalePercent,
      ),
      summaries.read(
        'TV home',
        () => StorageService.getTvHomeStyle(),
        _tvHomeStyle,
      ),
      summaries.read(
        'TV sidebar',
        () => StorageService.getTvSidebarStyle(),
        _tvSidebarStyle,
      ),
      summaries.read(
        'Discover layout',
        () => StorageService.getDiscoverLayout(),
        _discoverLayout,
      ),
      summaries.read(
        'IPTV style',
        () => StorageService.getIptvStyle(),
        _iptvStyle,
      ),
      summaries.read(
        'Player guide',
        () => StorageService.getIptvPlayerGuideStyle(),
        _playerGuideStyle,
      ),
      summaries.read(
        'Phone navigation',
        () => StorageService.getPhoneNavStyle(),
        _phoneNavStyle,
      ),
      summaries.read(
        'Text brightness',
        () => StorageService.getTextBrightness(),
        _textBrightness,
      ),
      summaries.read(
        'Launch animation',
        () => StorageService.getLaunchAnimation(),
        _launchAnimation,
      ),
      summaries.read(
        'Detail page',
        () => StorageService.getDetailPageStyle(),
        _detailPageStyle,
      ),
      summaries.read(
        'Render quality',
        () => StorageService.getTvRenderQuality(),
        _tvRenderQuality,
      ),
      summaries.read(
        'Detail theme',
        () => StorageService.getDetailTheme(),
        _detailTheme,
      ),
      summaries.read(
        'Parents guide',
        () => StorageService.getParentsGuideStyle(),
        _parentsGuideStyle,
      ),
      summaries.read(
        'Artwork quality',
        () => StorageService.getTvHeroArtworkQuality(),
        _tvHeroArtworkQuality,
      ),
      summaries.read(
        'Player dock',
        () => StorageService.getPlayerDockStyle(),
        _playerDockStyle,
      ),
      summaries.read(
        'Dock palette',
        () => StorageService.getPlayerDockPalette(),
        _playerDockPalette,
      ),
      summaries.read(
        'Dock size',
        () => StorageService.getPlayerDockSize(),
        _playerDockSize,
      ),
      summaries.read(
        'Desktop sidebar',
        () => StorageService.getDesktopSidebarStyle(),
        _desktopSidebarStyle,
      ),
      summaries.read(
        'Debrify TV',
        () => StorageService.getDebrifyTvStyle(),
        _debrifyTvStyle,
      ),
      summaries.read(
        'TV controls',
        () => StorageService.getTvPlayerControlsStyle(),
        _tvPlayerControlsStyle,
      ),
      summaries.read(
        'TV player',
        () => StorageService.getDebrifyTvPlayerStyle(),
        _debrifyTvPlayerStyle,
      ),
      summaries.read(
        'Play loader',
        () => StorageService.getPlayLoaderStyle(),
        _playLoaderStyle,
      ),
      summaries.read(
        'Diagnostics',
        () => _activeProfileMayExportDiagnostics(),
        false,
      ),
      summaries.read(
        'Pending credentials',
        () => _pendingCredentialTypes(),
        <ConnectionResourceType>{},
      ),
      summaries.read(
        'IPTV',
        () => StorageService.getIptvPlaylists(forSettings: true),
        [],
      ),
    ]);

    if (!mounted || ProfileRuntime.scope.value != startingScope) return;
    _summaryFailures = summaries.failures;
    _summaryUnavailable = summaries.unavailable;

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

    // Set initial state from cached data
    // Use cached account info if available
    if (rdConnected) {
      final user = AccountService.currentUser;
      _realDebridConnected = true;
      if (user != null) {
        _applyRdUserInfo(user);
      } else {
        _realDebridStatus = 'Connected';
        _realDebridCaption = 'Loading account info...';
      }
    }

    if (torConnected) {
      final torboxUser = TorboxAccountService.currentUser;
      _torboxConnected = true;
      if (torboxUser != null) {
        _applyTorboxUserInfo(torboxUser);
      } else {
        _torboxStatus = 'Connected';
        _torboxCaption = 'Loading account info...';
      }
    }

    if (premiumizeConnected) {
      final premiumizeUser = PremiumizeAccountService.currentUser;
      _premiumizeConnected = true;
      if (premiumizeUser != null) {
        _applyPremiumizeUserInfo(premiumizeUser);
      } else {
        _premiumizeStatus = 'Connected';
        _premiumizeCaption = 'Loading account info...';
      }
    }

    if (allDebridConnected) {
      final allDebridUser = AllDebridAccountService.currentUser;
      _allDebridConnected = true;
      if (allDebridUser != null) {
        _applyAllDebridUserInfo(allDebridUser);
      } else {
        _allDebridStatus = 'Connected';
        _allDebridCaption = 'Loading account info...';
      }
    }

    if (pikpakAuth) {
      _pikpakConnected = true;
      _pikpakStatus = 'Active';
      _pikpakCaption = 'Logged in';
    }

    if (webDavEnabled && webDavServers.isNotEmpty) {
      _webDavConnected = true;
      _webDavStatus = 'Active';
      final first = webDavServers.first;
      final host = Uri.tryParse(first.baseUrl)?.host;
      final label = (host != null && host.isNotEmpty) ? host : first.baseUrl;
      _webDavCaption = webDavServers.length == 1
          ? label
          : '$label (+${webDavServers.length - 1} more)';
    } else {
      _webDavConnected = false;
      _webDavStatus = 'Not connected';
      _webDavCaption = 'Tap to connect';
    }

    final traktExpired =
        traktExpiry != null &&
        DateTime.now().millisecondsSinceEpoch >= traktExpiry;
    if (traktConnected) {
      if (!traktExpired) {
        _traktConnected = true;
        _traktStatus = 'Active';
        _traktCaption = traktUsername != null
            ? 'Logged in as $traktUsername'
            : 'Logged in';
      } else {
        _traktStatus = 'Expired';
        _traktCaption = 'Tap to reconnect';
      }
    }

    // Simkl's PIN-issued tokens don't expire, so unlike Trakt there's no
    // "Expired" branch here — a stored token means connected.
    if (simklConnected) {
      _simklConnected = true;
      _simklStatus = 'Active';
      _simklCaption = simklUsername != null
          ? 'Logged in as $simklUsername'
          : 'Logged in';
    } else {
      _simklConnected = false;
      _simklStatus = 'Not connected';
      _simklCaption = 'Tap to connect';
    }

    // MDBList uses a plain API key (no expiry) — a stored key means connected.
    // Reset on the empty branch (like WebDAV above) so the card clears after a
    // logout, since this method re-runs when returning from the settings page.
    if (mdblistConnected) {
      _mdblistConnected = true;
      _mdblistStatus = 'Active';
      _mdblistCaption = mdblistUsername != null
          ? 'Logged in as $mdblistUsername'
          : 'Logged in';
    } else {
      _mdblistConnected = false;
      _mdblistStatus = 'Not connected';
      _mdblistCaption = 'Tap to connect';
    }

    if (indexerManagers.isNotEmpty) {
      _indexerManagersConfigured = true;
      _indexerManagersStatus = 'Active';
      _indexerManagersCaption =
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
    _iptvCredentialsPending = shouldApplyPendingCredentialOverride(
      pendingTypes: pendingCredentialTypes,
      providerTypes: const {
        ConnectionResourceType.iptvM3u,
        ConnectionResourceType.iptvXtream,
        ConnectionResourceType.xmltv,
      },
      ownCredentialPresent: configuredIptvPlaylists.isNotEmpty,
    );
    pending(const {ConnectionResourceType.realDebrid}, rdConnected, () {
      _realDebridConnected = true;
      _realDebridStatus = 'Attention';
      _realDebridCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.torbox}, torConnected, () {
      _torboxConnected = true;
      _torboxStatus = 'Attention';
      _torboxCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.premiumize}, premiumizeConnected, () {
      _premiumizeConnected = true;
      _premiumizeStatus = 'Attention';
      _premiumizeCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.allDebrid}, allDebridConnected, () {
      _allDebridConnected = true;
      _allDebridStatus = 'Attention';
      _allDebridCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.pikpak}, pikpakAuth, () {
      _pikpakConnected = true;
      _pikpakStatus = 'Attention';
      _pikpakCaption = pendingCaption;
    });
    pending(
      const {ConnectionResourceType.webDav},
      webDavEnabled && webDavServers.isNotEmpty,
      () {
        _webDavConnected = true;
        _webDavStatus = 'Attention';
        _webDavCaption = pendingCaption;
      },
    );
    pending(const {ConnectionResourceType.trakt}, traktConnected, () {
      _traktConnected = true;
      _traktStatus = 'Attention';
      _traktCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.simkl}, simklConnected, () {
      _simklConnected = true;
      _simklStatus = 'Attention';
      _simklCaption = pendingCaption;
    });
    pending(const {ConnectionResourceType.mdblist}, mdblistConnected, () {
      _mdblistConnected = true;
      _mdblistStatus = 'Attention';
      _mdblistCaption = pendingCaption;
    });
    pending(
      const {ConnectionResourceType.jackett, ConnectionResourceType.prowlarr},
      indexerManagers.isNotEmpty,
      () {
        _indexerManagersConfigured = true;
        _indexerManagersStatus = 'Attention';
        _indexerManagersCaption = pendingCaption;
      },
    );

    _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    _currentVersionName = packageInfo.version;
    _isAndroidTv = isAndroidTv;
    DiagnosticLog.instance.recordEvent(
      source: 'app',
      event: 'app_metadata',
      fields: <String, Object?>{
        'version': DiagnosticLabel(packageInfo.version),
        'build': DiagnosticLabel(packageInfo.buildNumber),
        'androidTv': isAndroidTv,
      },
    );
    _loading = false;
    _autoUpdateChecksEnabled = autoCheckEnabled;
    _tvKeyboardEnabled = tvKeyboardEnabled;
    _tvUiScalePercent = tvUiScalePercent;
    _tvRenderQuality = tvRenderQuality;
    _tvHomeStyle = tvHomeStyle;
    _tvSidebarStyle = tvSidebarStyle;
    _discoverLayout = discoverLayout;
    _iptvStyle = iptvStyle;
    _debrifyTvStyle = debrifyTvStyle;
    _playerGuideStyle = playerGuideStyle;
    _playLoaderStyle = playLoaderStyle;
    _tvPlayerControlsStyle = tvPlayerControlsStyle;
    _debrifyTvPlayerStyle = debrifyTvPlayerStyle;
    _playerDockStyle = playerDockStyle;
    _playerDockPalette = playerDockPalette;
    _playerDockSize = playerDockSize;
    _phoneNavStyle = phoneNavStyle;
    _desktopSidebarStyle = desktopSidebarStyle;
    _textBrightness = textBrightness;
    _launchAnimation = launchAnimation;
    _detailPageStyle = detailPageStyle;
    _detailTheme = detailTheme;
    _parentsGuideStyle = parentsGuideStyle;
    _tvHeroArtworkQuality = tvHeroArtworkQuality;
    _diagnosticExportVisible = diagnosticExportVisible;

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
        .where((resource) => resource.secretPending)
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
    _supportDonation = config.donation;
    _supportSettingsLabel = config.donation.settingsLabel;
    _supportSettingsSubtitle = config.donation.settingsSubtitle;
  }

  Future<void> _openSupportDonation() async {
    await showSupportDonationChooserDialog(
      context,
      donation: _supportDonation,
      title: _supportSettingsLabel,
      // Match the settings palette (the dialog is shown from the State's
      // context, which sits above the scoped theme in build()).
      theme: settingsPageTheme(context),
    );
  }

  void _applyRdUserInfo(dynamic user) {
    final expiry = _tryParseDate(user.expiration);
    final bool isPremium = user.isPremium;
    final bool active =
        isPremium && (expiry == null || expiry.isAfter(DateTime.now()));
    _realDebridStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _realDebridCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _realDebridCaption = 'Premium account';
    } else if (isPremium && expiry != null) {
      _realDebridCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _realDebridCaption = 'Premium not active';
    }
  }

  void _applyTorboxUserInfo(dynamic torboxUser) {
    final expiry = torboxUser.premiumExpiresAt;
    final bool active = torboxUser.hasActiveSubscription;
    _torboxStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _torboxCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _torboxCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _torboxCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _torboxCaption = 'Premium not active';
    }
  }

  void _applyPremiumizeUserInfo(dynamic premiumizeUser) {
    final expiry = premiumizeUser.premiumUntil;
    final bool active = premiumizeUser.hasActivePremium;
    _premiumizeStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _premiumizeCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _premiumizeCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _premiumizeCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _premiumizeCaption = 'Premium not active';
    }
  }

  void _applyAllDebridUserInfo(dynamic allDebridUser) {
    final expiry = allDebridUser.premiumUntil;
    final bool active = allDebridUser.hasActivePremium;
    _allDebridStatus = active ? 'Active' : 'Inactive';
    if (active && expiry != null) {
      _allDebridCaption = 'Expires ${_formatDate(expiry)}';
    } else if (active) {
      _allDebridCaption = 'Premium account';
    } else if (expiry != null && expiry.isBefore(DateTime.now())) {
      _allDebridCaption = 'Expired ${_formatDate(expiry)}';
    } else {
      _allDebridCaption = 'Premium not active';
    }
  }

  @override
  Widget build(BuildContext context) {
    // The whole tab renders under the scoped settings theme so inline
    // Material widgets (progress spinners, switches) match the subpages.
    // Dialogs shown from this State's context sit ABOVE this Theme, so they
    // go through showSettingsDialog instead.
    if (_loading) {
      return Theme(
        data: settingsPageTheme(context),
        child: const SettingsSkeleton(),
      );
    }

    return Theme(
      data: settingsPageTheme(context),
      child: Column(
        children: [
          if (_summaryLoadFailed || _summaryFailures.isNotEmpty)
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
            child: _isAndroidTv ? _buildTvLayout() : _buildLayout(context),
          ),
        ],
      ),
    );
  }

  // Connection cards in canonical order (matches the phone grid rows).
  String _summaryFailureStatus(String label) => 'Attention';

  String _summaryFailureCaption(String label) =>
      _summaryUnavailable.contains(label)
      ? 'Unavailable; retry or sign in'
      : 'Unable to load; open the item to retry';

  ConnectionInfo get _rdInfo => ConnectionInfo(
    title: 'Real Debrid',
    connected:
        !_summaryFailures.contains('Real Debrid') && _realDebridConnected,
    status: _summaryFailures.contains('Real Debrid')
        ? _summaryFailureStatus('Real Debrid')
        : _realDebridStatus,
    caption: _summaryFailures.contains('Real Debrid')
        ? _summaryFailureCaption('Real Debrid')
        : _realDebridCaption,
    onTap: _openRealDebridSettings,
  );
  ConnectionInfo get _torboxInfo => ConnectionInfo(
    title: 'Torbox',
    connected: !_summaryFailures.contains('Torbox') && _torboxConnected,
    status: _summaryFailures.contains('Torbox')
        ? _summaryFailureStatus('Torbox')
        : _torboxStatus,
    caption: _summaryFailures.contains('Torbox')
        ? _summaryFailureCaption('Torbox')
        : _torboxCaption,
    onTap: _openTorboxSettings,
  );
  ConnectionInfo get _premiumizeInfo => ConnectionInfo(
    title: 'Premiumize',
    connected: !_summaryFailures.contains('Premiumize') && _premiumizeConnected,
    status: _summaryFailures.contains('Premiumize')
        ? _summaryFailureStatus('Premiumize')
        : _premiumizeStatus,
    caption: _summaryFailures.contains('Premiumize')
        ? _summaryFailureCaption('Premiumize')
        : _premiumizeCaption,
    onTap: _openPremiumizeSettings,
  );
  ConnectionInfo get _allDebridInfo => ConnectionInfo(
    title: 'AllDebrid',
    connected: !_summaryFailures.contains('AllDebrid') && _allDebridConnected,
    status: _summaryFailures.contains('AllDebrid')
        ? _summaryFailureStatus('AllDebrid')
        : _allDebridStatus,
    caption: _summaryFailures.contains('AllDebrid')
        ? _summaryFailureCaption('AllDebrid')
        : _allDebridCaption,
    onTap: _openAllDebridSettings,
  );
  ConnectionInfo get _pikpakInfo => ConnectionInfo(
    title: 'PikPak',
    connected: !_summaryFailures.contains('PikPak') && _pikpakConnected,
    status: _summaryFailures.contains('PikPak')
        ? _summaryFailureStatus('PikPak')
        : _pikpakStatus,
    caption: _summaryFailures.contains('PikPak')
        ? _summaryFailureCaption('PikPak')
        : _pikpakCaption,
    onTap: _openPikPakSettings,
  );
  ConnectionInfo get _webDavInfo => ConnectionInfo(
    title: 'WebDAV',
    connected: !_summaryFailures.contains('WebDAV') && _webDavConnected,
    status: _summaryFailures.contains('WebDAV')
        ? _summaryFailureStatus('WebDAV')
        : _webDavStatus,
    caption: _summaryFailures.contains('WebDAV')
        ? _summaryFailureCaption('WebDAV')
        : _webDavCaption,
    onTap: _openWebDavSettings,
  );
  ConnectionInfo get _iptvInfo => ConnectionInfo(
    title: 'IPTV',
    connected: !_summaryFailures.contains('IPTV'),
    status: _summaryFailures.contains('IPTV')
        ? _summaryFailureStatus('IPTV')
        : _iptvCredentialsPending
        ? 'Attention'
        : 'Active',
    caption: _summaryFailures.contains('IPTV')
        ? _summaryFailureCaption('IPTV')
        : _iptvCredentialsPending
        ? 'credentials pending owner sign-in'
        : 'M3U playlist channels',
    onTap: _openIptvSettings,
  );
  ConnectionInfo get _traktInfo => ConnectionInfo(
    title: 'Trakt',
    connected: !_summaryFailures.contains('Trakt') && _traktConnected,
    status: _summaryFailures.contains('Trakt')
        ? _summaryFailureStatus('Trakt')
        : _traktStatus,
    caption: _summaryFailures.contains('Trakt')
        ? _summaryFailureCaption('Trakt')
        : _traktCaption,
    onTap: _openTraktSettings,
  );
  ConnectionInfo get _simklInfo => ConnectionInfo(
    title: 'Simkl',
    connected: !_summaryFailures.contains('Simkl') && _simklConnected,
    status: _summaryFailures.contains('Simkl')
        ? _summaryFailureStatus('Simkl')
        : _simklStatus,
    caption: _summaryFailures.contains('Simkl')
        ? _summaryFailureCaption('Simkl')
        : _simklCaption,
    onTap: _openSimklSettings,
  );
  ConnectionInfo get _mdblistInfo => ConnectionInfo(
    title: 'MDBList',
    connected: !_summaryFailures.contains('MDBList') && _mdblistConnected,
    status: _summaryFailures.contains('MDBList')
        ? _summaryFailureStatus('MDBList')
        : _mdblistStatus,
    caption: _summaryFailures.contains('MDBList')
        ? _summaryFailureCaption('MDBList')
        : _mdblistCaption,
    onTap: _openMdblistSettings,
  );
  ConnectionInfo get _trackingInfo => ConnectionInfo(
    title: 'Tracking',
    connected: true,
    status: 'Configured',
    caption: 'Scrobble, progress source & Home ticks',
    onTap: _openTrackingSettings,
  );
  ConnectionInfo get _indexerManagersInfo => ConnectionInfo(
    title: 'Jackett & Prowlarr',
    connected:
        !_summaryFailures.contains('Indexer managers') &&
        _indexerManagersConfigured,
    status: _summaryFailures.contains('Indexer managers')
        ? _summaryFailureStatus('Indexer managers')
        : _indexerManagersStatus,
    caption: _summaryFailures.contains('Indexer managers')
        ? _summaryFailureCaption('Indexer managers')
        : _indexerManagersCaption,
    onTap: _openIndexerManagersSettings,
  );

  Widget _buildTvLayout() {
    return SettingsTvLayout(
      connections: [
        _rdInfo,
        _torboxInfo,
        _premiumizeInfo,
        _allDebridInfo,
        _pikpakInfo,
        _webDavInfo,
        _iptvInfo,
        _indexerManagersInfo,
      ],
      // Watch history lives on its own rail category — Connections had grown
      // to ten cards covering five unrelated jobs.
      tracking: _trackingInfo,
      trackers: [
        _traktInfo,
        _simklInfo,
        // MDBList hidden for the alpha (unfinished) — see [kMdblistEnabled].
        if (kMdblistEnabled) _mdblistInfo,
      ],
      firstFocusNode: _firstCardFocusNode,
      onOpenSearch: _openSettingsSearch,
      onOpenHomePageSettings: _openHomePageSettings,
      onOpenExternalPlayerSettings: _openExternalPlayerSettings,
      onOpenRemoteControl: _openRemoteControl,
      showSwitchProfile:
          ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted,
      onSwitchProfile: _switchProfile,
      onAddProfile: _addProfile,
      onEditProfile: _editActiveProfile,
      onOpenTorrentSettings: _openTorrentSettings,
      onOpenFilterSettings: _openFilterSettings,
      onOpenProviderSettings: _openProviderSettings,
      onOpenQuickPlaySettings: _openQuickPlaySettings,
      onOpenDiscoverSettings: _openDiscoverSettings,
      onOpenDebrifyTvSettings: _openDebrifyTvSettings,
      onClearDownloads: _clearDownloadData,
      onClearPlayback: _clearPlaybackData,
      onOpenDownloadLocation: _downloadLocationSupported
          ? _openDownloadLocationSettings
          : null,
      downloadLocationSubtitle: _downloadLocationSubtitle,
      onCreateBackup: _createBackup,
      onRestoreBackup: _restoreBackup,
      onOpenSyncAndMigrate: _openSyncAndMigrate,
      onExportDiagnosticLogs: _diagnosticExportVisible
          ? _exportDiagnosticLogs
          : null,
      onDangerAction: _resetAppData,
      appVersion: _appVersion,
      onCheckForUpdates: _checkForAppUpdates,
      updateSubtitle: _updateSubtitle,
      checkingUpdates: _checkingUpdates,
      autoUpdateChecksEnabled: _autoUpdateChecksEnabled,
      onToggleAutoUpdateChecks: _toggleAutoUpdateChecks,
      tvKeyboardEnabled: _tvKeyboardEnabled,
      onToggleTvKeyboard: _toggleTvKeyboard,
      textBrightnessLabel: textBrightnessLabel(_textBrightness),
      onOpenTextBrightness: _openTextBrightnessPage,
      launchAnimationLabel: launchIdentLabel(_launchAnimation),
      onOpenLaunchAnimation: _openLaunchAnimationPage,
      tvUiScalePercent: _tvUiScalePercent,
      onOpenTvScreenSize: _openTvScreenSize,
      tvRenderQualityLabel: tvRenderQualityLabel(_tvRenderQuality),
      onOpenTvRenderQuality: _openTvRenderQuality,
      tvHeroArtworkQualityLabel: tvHeroArtworkQualityLabel(
        _tvHeroArtworkQuality,
      ),
      onOpenTvHeroArtworkQuality: _openTvHeroArtworkQuality,
      tvSidebarStyleLabel: tvSidebarStyleLabel(_tvSidebarStyle),
      onOpenTvSidebarStyle: _openTvSidebarStyle,
      discoverLayoutLabel: discoverLayoutLabel(_discoverLayout),
      onOpenDiscoverLayout: _openDiscoverLayout,
      tvHomeStyleLabel: tvHomeStyleLabel(_tvHomeStyle),
      onOpenTvHomeStyle: _openTvHomeStyle,
      profileAppearanceLabel: ProfileGateStyle.labelFor(
        ProfileGateStyle.cached,
      ),
      onOpenProfileAppearance: _openProfileAppearance,
      iptvStyleLabel: iptvStyleLabel(_iptvStyle),
      onOpenIptvStyle: _openIptvStylePage,
      debrifyTvStyleLabel: debrifyTvStyleLabel(_debrifyTvStyle),
      onOpenDebrifyTvStyle: _openDebrifyTvStylePage,
      playerGuideStyleLabel: playerGuideStyleLabel(_playerGuideStyle),
      playLoaderStyleLabel: playLoaderStyleLabel(_playLoaderStyle),
      onOpenPlayLoaderStyle: _openPlayLoaderStylePage,
      onOpenPlayerGuideStyle: _openPlayerGuideStylePage,
      tvPlayerControlsStyleLabel: tvPlayerControlsStyleLabel(
        _tvPlayerControlsStyle,
      ),
      onOpenTvPlayerControlsStyle: _openTvPlayerControlsStylePage,
      debrifyTvPlayerStyleLabel: debrifyTvPlayerStyleLabel(
        _debrifyTvPlayerStyle,
      ),
      onOpenDebrifyTvPlayerStyle: _openDebrifyTvPlayerStylePage,
      detailPageStyleLabel: detailPageStyleLabel(_detailPageStyle),
      onOpenDetailPageStyle: _openDetailPageStylePage,
      appThemeLabel: appThemeLabel(AppThemeController.instance.id),
      looksLabel: AppLooks.active()?.label ?? 'Custom',
      onOpenLooks: _openLooksPage,
      onOpenThemeTokens: _openThemeTokensPage,
      themeTokensLabel: _themeTokensLabel,
      onOpenThemeLab: _openThemeLab,
      onOpenAppTheme: _openAppThemePage,
      detailThemeLabel: detailThemeLabel(_detailTheme),
      onOpenDetailTheme: _openDetailThemePage,
      parentsGuideStyleLabel: parentsGuideStyleLabel(_parentsGuideStyle),
      onOpenParentsGuideStyle: _openParentsGuideStylePage,
      onOpenRecordings: _openRecordings,
      onOpenIptvSettings: _openIptvSettings,
      showSupportDonation: _supportDonation.hasProviders,
      supportDonationLabel: _supportSettingsLabel,
      supportDonationSubtitle: _supportSettingsSubtitle,
      onOpenSupportDonation: _openSupportDonation,
    );
  }

  Widget _buildLayout(BuildContext context) {
    return _SettingsLayout(
      connections: ConnectionsSummary(
        realDebrid: _rdInfo,
        torbox: _torboxInfo,
        premiumize: _premiumizeInfo,
        allDebrid: _allDebridInfo,
        pikpak: _pikpakInfo,
        webDav: _webDavInfo,
        iptv: _iptvInfo,
        trakt: _traktInfo,
        simkl: _simklInfo,
        tracking: _trackingInfo,
        // MDBList hidden for the alpha (unfinished) — see [kMdblistEnabled].
        mdblist: kMdblistEnabled ? _mdblistInfo : null,
        indexerManagers: _indexerManagersInfo,
        firstCardFocusNode: _firstCardFocusNode,
      ),
      onOpenSearch: _openSettingsSearch,
      onOpenTorrentSettings: _openTorrentSettings,
      onOpenFilterSettings: _openFilterSettings,
      onOpenProviderSettings: _openProviderSettings,
      onOpenQuickPlaySettings: _openQuickPlaySettings,
      onOpenDiscoverSettings: _openDiscoverSettings,
      onOpenDebrifyTvSettings: _openDebrifyTvSettings,
      onOpenPikPakSettings: _openPikPakSettings,
      onOpenHomePageSettings: _openHomePageSettings,
      onOpenExternalPlayerSettings: _openExternalPlayerSettings,
      onOpenRemoteControl: _openRemoteControl,
      showSwitchProfile:
          ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted,
      onSwitchProfile: _switchProfile,
      onAddProfile: _addProfile,
      onEditProfile: _editActiveProfile,
      onOpenNavigationSettings: _openNavigationSettings,
      isAndroidTv: _isAndroidTv,
      onClearDownloads: _clearDownloadData,
      onClearPlayback: _clearPlaybackData,
      onOpenDownloadLocation: _downloadLocationSupported
          ? _openDownloadLocationSettings
          : null,
      downloadLocationSubtitle: _downloadLocationSubtitle,
      onCreateBackup: _createBackup,
      onRestoreBackup: _restoreBackup,
      onOpenSyncAndMigrate: _openSyncAndMigrate,
      onExportDiagnosticLogs: _diagnosticExportVisible
          ? _exportDiagnosticLogs
          : null,
      onDangerAction: _resetAppData,
      appVersion: _appVersion,
      onCheckForUpdates: _checkForAppUpdates,
      updateSubtitle: _updateSubtitle,
      checkingUpdates: _checkingUpdates,
      autoUpdateChecksEnabled: _autoUpdateChecksEnabled,
      onToggleAutoUpdateChecks: _toggleAutoUpdateChecks,
      tvKeyboardEnabled: _tvKeyboardEnabled,
      onToggleTvKeyboard: _toggleTvKeyboard,
      showSupportDonation: _supportDonation.hasProviders,
      supportDonationLabel: _supportSettingsLabel,
      supportDonationSubtitle: _supportSettingsSubtitle,
      onOpenSupportDonation: _openSupportDonation,
      onOpenRecordings: _openRecordings,
      onOpenIptvSettings: _openIptvSettings,
      showIptvAppearance: _iptvAppearanceSearchable,
      textBrightnessLabel: textBrightnessLabel(_textBrightness),
      onOpenTextBrightness: _openTextBrightnessPage,
      launchAnimationLabel: launchIdentLabel(_launchAnimation),
      onOpenLaunchAnimation: _openLaunchAnimationPage,
      iptvStyleLabel: iptvStyleLabel(_iptvStyle),
      onOpenIptvStyle: _openIptvStylePage,
      debrifyTvStyleLabel: debrifyTvStyleLabel(_debrifyTvStyle),
      onOpenDebrifyTvStyle: _openDebrifyTvStylePage,
      playerGuideStyleLabel: playerGuideStyleLabel(_playerGuideStyle),
      playLoaderStyleLabel: playLoaderStyleLabel(_playLoaderStyle),
      onOpenPlayLoaderStyle: _openPlayLoaderStylePage,
      playerDockLabel: playerDockLabel(
        _playerDockStyle,
        _playerDockPalette,
        _playerDockSize,
      ),
      onOpenPlayerDock: _openPlayerDockPage,
      onOpenPlayerGuideStyle: _openPlayerGuideStylePage,
      detailPageStyleLabel: detailPageStyleLabel(_detailPageStyle),
      onOpenDetailPageStyle: _openDetailPageStylePage,
      appThemeLabel: appThemeLabel(AppThemeController.instance.id),
      onOpenLooks: _openLooksPage,
      onOpenThemeTokens: _openThemeTokensPage,
      themeTokensLabel: _themeTokensLabel,
      onOpenThemeLab: _openThemeLab,
      onOpenAppTheme: _openAppThemePage,
      detailThemeLabel: detailThemeLabel(_detailTheme),
      onOpenDetailTheme: _openDetailThemePage,
      parentsGuideStyleLabel: parentsGuideStyleLabel(_parentsGuideStyle),
      onOpenParentsGuideStyle: _openParentsGuideStylePage,
      phoneNavStyleLabel: _phoneNavStyle == 'floating'
          ? 'Floating button'
          : 'Classic bar',
      desktopSidebarStyleLabel: desktopSidebarStyleLabel(_desktopSidebarStyle),
      onOpenDesktopSidebarStyle: _openDesktopSidebarStyle,
      profileAppearanceLabel: ProfileGateStyle.labelFor(
        ProfileGateStyle.cached,
      ),
      onOpenProfileAppearance: _openProfileAppearance,
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
          _switchProfile,
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
          _addProfile,
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
          _editActiveProfile,
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
      conn(_rdInfo, const [
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
      conn(_torboxInfo, const [
        'debrid',
        'premium',
        'api key',
        'add api key',
        'logout',
        'login',
        'account',
      ]),
      conn(_premiumizeInfo, const [
        'debrid',
        'premium',
        'api key',
        'add api key',
        'logout',
        'login',
        'account',
      ]),
      conn(_allDebridInfo, const [
        'debrid',
        'ad',
        'premium',
        'api key',
        'add api key',
        'logout',
        'login',
        'account',
      ]),
      conn(_pikpakInfo, const [
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
      conn(_webDavInfo, const [
        'cloud',
        'nas',
        'server',
        'seedbox',
        'url',
        'username',
        'password',
        'app token',
      ]),
      conn(_iptvInfo, const [
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
        onTap: _openIptvSettings,
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
        onTap: _openIptvSettings,
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
        onTap: _openIptvSettings,
      ),
      conn(_indexerManagersInfo, const [
        'indexer',
        'torznab',
        'jackett',
        'prowlarr',
        'engines',
      ]),

      // Trackers — keep this block last in the Connections neighbourhood so
      // the two categories stay contiguous; see SettingsSearchPage.
      conn(_traktInfo, const [
        'scrobble',
        'sync',
        'watch history',
        'watchlist',
        'login',
        'activate',
        'device code',
        'logout',
      ], category: 'Trackers'),
      conn(_trackingInfo, const [
        'scrobble',
        'sync catalog',
        'watch progress',
        'continue watching source',
        'home ticks',
      ], category: 'Trackers'),
      conn(_simklInfo, const [
        'scrobble',
        'sync',
        'watch history',
        'login',
        'pin',
        'device code',
        'logout',
      ], category: 'Trackers'),
      if (kMdblistEnabled)
        conn(_mdblistInfo, const ['lists', 'ratings'], category: 'Trackers'),

      // General
      nav(
        SettingsRows.homePage,
        'Home & Display',
        _openHomePageSettings,
        keywords: const [
          'home page',
          'default view',
          'startup',
          'landing',
          'tab',
        ],
      ),
      nav(
        SettingsRows.collections,
        'Home & Display',
        _openCollectionsSettings,
        keywords: const [
          'collections',
          'collection',
          'nuvio',
          'xperience',
          'folders',
          'import json',
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
        _openTextBrightnessPage,
        subtitle: textBrightnessLabel(_textBrightness),
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
        _openLaunchAnimationPage,
        subtitle: launchIdentLabel(_launchAnimation),
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
      if (_isAndroidTv)
        nav(
          SettingsRows.tvScreenSize,
          'Appearance',
          _openTvScreenSize,
          subtitle: tvUiScaleLabel(_tvUiScalePercent),
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
      if (_isAndroidTv)
        nav(
          SettingsRows.tvRenderQuality,
          'Appearance',
          _openTvRenderQuality,
          subtitle: tvRenderQualityLabel(_tvRenderQuality),
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
          _openTvHeroArtworkQuality,
          subtitle: tvHeroArtworkQualityLabel(_tvHeroArtworkQuality),
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
        _openTvHomeStyle,
        subtitle: tvHomeStyleLabel(
          _isAndroidTv ? _tvHomeStyle : effectiveOffTvHomeStyle(_tvHomeStyle),
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
        _openProfileAppearance,
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
      // Android TV only — the stage layout is a TV-canvas design; phones and
      // desktop always browse Discover as a grid.
      if (_isAndroidTv)
        nav(
          SettingsRows.discoverLayout,
          'Appearance',
          _openDiscoverLayout,
          subtitle: discoverLayoutLabel(_discoverLayout),
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
      if (_isAndroidTv)
        nav(
          SettingsRows.tvSidebarStyle,
          'Appearance',
          _openTvSidebarStyle,
          subtitle: tvSidebarStyleLabel(_tvSidebarStyle),
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
      if (!_isAndroidTv && !PlatformUtil.isTelevision)
        nav(
          SettingsRows.desktopSidebarStyle,
          'Appearance',
          _openDesktopSidebarStyle,
          subtitle: desktopSidebarStyleLabel(_desktopSidebarStyle),
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
          _openIptvStylePage,
          subtitle: iptvStyleLabel(_iptvStyle),
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
        _openDebrifyTvStylePage,
        subtitle: debrifyTvStyleLabel(_debrifyTvStyle),
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
        _openPlayerGuideStylePage,
        subtitle: playerGuideStyleLabel(_playerGuideStyle),
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
        _openPlayLoaderStylePage,
        subtitle: playLoaderStyleLabel(_playLoaderStyle),
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
          _openTvPlayerControlsStylePage,
          subtitle: tvPlayerControlsStyleLabel(_tvPlayerControlsStyle),
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
          _openDebrifyTvPlayerStylePage,
          subtitle: debrifyTvPlayerStyleLabel(_debrifyTvPlayerStyle),
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
          _openPlayerDockPage,
          subtitle: playerDockLabel(
            _playerDockStyle,
            _playerDockPalette,
            _playerDockSize,
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
        _openThemeTokensPage,
        subtitle: _themeTokensLabel,
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
        _openLooksPage,
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
        _openParentsGuideStylePage,
        subtitle: parentsGuideStyleLabel(_parentsGuideStyle),
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
        _openDetailPageStylePage,
        subtitle: detailPageStyleLabel(_detailPageStyle),
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
          _openNavigationSettings,
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
        _openExternalPlayerSettings,
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
        _openRemoteControl,
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
        _openTorrentSettings,
        keywords: const ['engines', 'sorting', 'torrent', 'sources'],
      ),
      nav(
        SettingsRows.filterSettings,
        'Search',
        _openFilterSettings,
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
        _openProviderSettings,
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
        _openQuickPlaySettings,
        keywords: const ['instant', 'auto play', 'one tap'],
      ),
      nav(
        SettingsRows.discoverDefault,
        'Discover',
        _openDiscoverSettings,
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
        _openDebrifyTvSettings,
        keywords: const ['channels', 'limits', 'playback', 'android tv'],
      ),
      // One row, one entry: the recordings page owns the whole DVR — a second
      // "IPTV recording" entry pointed at the same page and only split the
      // keywords. The engine/battery/concurrency switches live in IPTV
      // settings instead, and are indexed as leaves there.
      nav(
        SettingsRows.recordings,
        'Live TV & DVR',
        _openRecordings,
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
        _openIptvSettings,
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
        onTap: _openStremioTvSettings,
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
        toggleValue: () => _tvKeyboardEnabled,
        onToggle: _toggleTvKeyboard,
      ),

      nav(
        SettingsRows.syncAndMigrate,
        'Sync and backup',
        _openSyncAndMigrate,
        keywords: const [
          'webdav',
          'cloud backup',
          'migration',
          'transfer',
          'save backup',
          'restore backup',
          'apple tv',
          'tvos',
          'encrypted',
        ],
      ),

      // Downloads
      if (_downloadLocationSupported)
        nav(
          SettingsRows.downloadLocation,
          'Data & Backup',
          _openDownloadLocationSettings,
          subtitle: _downloadLocationSubtitle,
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
        _clearDownloadData,
        keywords: const ['queue', 'history', 'clear', 'remove'],
      ),
      nav(
        SettingsRows.clearPlayback,
        'Data & Backup',
        _clearPlaybackData,
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
        _createBackup,
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
        _restoreBackup,
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
      if (_diagnosticExportVisible)
        nav(
          SettingsRows.exportDiagnosticLogs,
          'Data & Backup',
          _exportDiagnosticLogs,
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
        toggleValue: () => _autoUpdateChecksEnabled,
        onToggle: _toggleAutoUpdateChecks,
      ),
      nav(
        SettingsRows.checkUpdates,
        'About',
        _checkForAppUpdates,
        subtitle: _updateSubtitle,
        keywords: const ['version', 'upgrade', 'github', 'new build'],
      ),

      // Support
      if (_supportDonation.hasProviders)
        SettingsSearchEntry(
          icon: SettingsRows.supportDebrify.icon,
          title: _supportSettingsLabel,
          subtitle: _supportSettingsSubtitle,
          category: 'About',
          keywords: const ['donate', 'tip', 'contribute', 'fund'],
          onTap: _openSupportDonation,
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
        _resetAppData,
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
      'Torbox': _openTorboxSettings,
      'Premiumize': _openPremiumizeSettings,
      'Real Debrid': _openRealDebridSettings,
      'AllDebrid': _openAllDebridSettings,
      'PikPak': _openPikPakSettings,
      'WebDAV': _openWebDavSettings,
      'Indexer Managers': _openIndexerManagersSettings,
      'Engines': _openTorrentSettings,
      'Filters': _openFilterSettings,
      'Default Provider': _openProviderSettings,
      'Quick Play': _openQuickPlaySettings,
      'Home Screen': _openHomePageSettings,
      'Launch Animation': _openLaunchAnimationPage,
      'Advanced': _openThemeTokensPage,
      'Sidebar': _openSidebarCustomization,
      'Profile Picker': _openProfileAppearance,
      'Playback': _openExternalPlayerSettings,
      'Debrify TV': _openDebrifyTvSettings,
      'Stremio TV': _openStremioTvSettings,
      'IPTV Playlists': _openIptvSettings,
      'Recordings': _openRecordings,
      'Trakt': _openTraktSettings,
      'Tracking': _openTrackingSettings,
      'Simkl': _openSimklSettings,
      'MDBList': _openMdblistSettings,
      'Profiles': _switchProfile,
      'Remote': _openRemoteControl,
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

      // Player Settings
      leaf('Playback', 'Default Player', 'Which player plays videos', const [
        'default player',
        'debrify player',
        'external',
        'external player',
        'built-in',
        'system app chooser',
        'deovr',
      ]),
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
      ),
      leaf(
        'Playback',
        'Default Audio language',
        'Preferred audio language / track',
        const ['audio', 'language', 'track', 'dub', ...audioLanguageLabels],
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
      ),
      if (_isAndroid)
        leaf(
          'Playback',
          'Allow system audio effects',
          'Let equalizer apps process audio (Android)',
          const ['audio effects', 'equalizer', 'wavelet', 'dolby'],
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
        onTap: _openIptvAddSource,
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
        onTap: _openIptvChannelOrder,
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
      if (_recordingSearchable) ...[
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

  Future<void> _openTorrentSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.torrentSearch)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const TorrentSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openIndexerManagersSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.torrentSearch)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const IndexerManagersSettingsPage());
    if (!mounted) return;

    final configs = await StorageService.getIndexerManagerConfigs(
      forSettings: true,
    );
    if (!mounted) return;
    setState(() {
      _indexerManagersConfigured = configs.isNotEmpty;
      _indexerManagersStatus = configs.isNotEmpty ? 'Active' : 'Not configured';
      _indexerManagersCaption = configs.isNotEmpty
          ? '${configs.length} engine${configs.length == 1 ? '' : 's'} configured'
          : 'Connect Jackett or Prowlarr';
    });
  }

  Future<void> _openDebrifyTvSettings() async {
    await pushSettingsPage(context, const DebrifyTvSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  /// Stremio TV's channel settings. The row lives on the Stremio TV screen
  /// (not in Settings), but the page is self-contained — search deep-links
  /// into it so "random episodes"/"rotation" are findable from Settings.
  Future<void> _openStremioTvSettings() async {
    await pushSettingsPage(context, const StremioTvSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openPikPakSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const PikPakSettingsPage(),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  Future<void> _openWebDavSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const WebDavSettingsPage());
    if (!mounted) return;
    await _loadSummaries();
  }

  Future<void> _openTraktSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.trackersAndDiscovery)) {
      return;
    }
    if (!mounted) return;
    await pushSettingsPage(context, const TraktSettingsPage());
    if (!mounted) return;
    await _loadSummaries();
  }

  Future<void> _openTrackingSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.trackersAndDiscovery)) {
      return;
    }
    if (!mounted) return;
    await pushSettingsPage(context, const TrackingSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openSimklSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.trackersAndDiscovery)) {
      return;
    }
    if (!mounted) return;
    await pushSettingsPage(context, const SimklSettingsPage());
    if (!mounted) return;
    await _loadSummaries();
  }

  Future<void> _openMdblistSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.trackersAndDiscovery)) {
      return;
    }
    if (!mounted) return;
    await pushSettingsPage(context, const MdblistSettingsPage());
    if (!mounted) return;
    await _loadSummaries();
  }

  /// Phone/small-window chrome choice: classic bottom bar (default) vs the
  /// floating glass button. Applies live — MainPageBridge tells the shell.
  Future<void> _openNavigationSettings() async {
    final current = await StorageService.getPhoneNavStyle();
    if (!mounted) return;

    // The dialog RETURNS the choice; the write is awaited here before the
    // bridge fires. Popping first and writing unawaited (the old shape)
    // let an immediate pref re-read race the write.
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        Widget option({
          required IconData icon,
          required String title,
          required String subtitle,
          required String value,
        }) {
          final selected = current == value;
          return ListTile(
            leading: Icon(
              icon,
              color: selected ? const Color(0xFFC7BFFF) : null,
            ),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
            trailing: selected
                ? const Icon(Icons.check_rounded, color: Color(0xFFC7BFFF))
                : null,
            onTap: () => Navigator.of(dialogContext).pop(value),
          );
        }

        return AlertDialog(
          title: const Text('Navigation'),
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              option(
                icon: Icons.call_to_action_rounded,
                title: 'Classic bar',
                subtitle:
                    'Bottom tabs \u2014 Home, three slots you pick, More '
                    'holds the rest',
                value: 'classic',
              ),
              option(
                icon: Icons.blur_on_rounded,
                title: 'Floating button',
                subtitle: 'The glass button with the expanding menu',
                value: 'floating',
              ),
            ],
          ),
        );
      },
    );
    if (chosen == null || chosen == current || !mounted) return;
    await StorageService.setPhoneNavStyle(chosen);
    if (!mounted) return;
    setState(() => _phoneNavStyle = chosen);
    MainPageBridge.navPrefsChanged?.call();
  }

  Future<void> _openIptvSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.iptv)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const IptvSettingsPage());
    if (!mounted) return;
    // IPTV settings hosts its own Appearance/Player guide sections — keep
    // the Appearance row captions honest.
    await _reloadAppearanceSummaries();
  }

  Future<void> _openIptvChannelOrder() async {
    if (!await _ensureProfileFeature(ProfileFeature.iptv)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const IptvChannelOrderPage());
  }

  /// IPTV settings landing on the add-source form — what a search for "add
  /// playlist" is actually after. Without the flag the wide (TV/desktop)
  /// layout opens its source rail instead, and the form is another hop away.
  Future<void> _openIptvAddSource() async {
    if (!await _ensureProfileFeature(ProfileFeature.iptv)) return;
    if (!mounted) return;
    await pushSettingsPage(
      context,
      const IptvSettingsPage(openAddSource: true),
    );
    if (!mounted) return;
    // The two-pane reached from here still exposes the Appearance/Player
    // guide sections — keep the Appearance row captions honest.
    await _reloadAppearanceSummaries();
  }

  /// Live TV & DVR › Recordings — the same page IPTV settings and the
  /// recording dialogs open, promoted to a first-class settings row.
  Future<void> _openRecordings() async {
    if (!await _ensureProfileFeature(ProfileFeature.recordings)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const RecordingsPage());
  }

  Future<void> _openCollectionsSettings() async {
    await pushSettingsPage(context, const CollectionsSettingsPage());
  }

  Future<void> _openHomePageSettings() async {
    await pushSettingsPage(context, const HomePageSettingsPage());
    if (!mounted) return;
    // The Home Screen page hosts its own TV home layout row — keep the
    // Appearance row caption honest.
    await _reloadAppearanceSummaries();
  }

  Future<void> _openExternalPlayerSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.externalPlayers)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const ExternalPlayerSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openRemoteControl() async {
    if (!await _ensureProfileFeature(ProfileFeature.remoteControl)) return;
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RemoteRolePickerScreen()));
    if (!mounted) return;
    setState(() {});
  }

  /// Opens the Profiles hub (roster + switch + create). The bare
  /// switch-picker call moved onto the hub itself.
  Future<void> _switchProfile() async {
    await pushSettingsPage(context, const ProfilesSettingsPage());
    if (!mounted) return;
    final diagnosticExportVisible = await _activeProfileMayExportDiagnostics();
    if (!mounted) return;
    setState(() => _diagnosticExportVisible = diagnosticExportVisible);
  }

  /// The admin check the hub applies before its Create/Manage rows — the
  /// Profiles card's action rows share it, but answer with a spoken refusal
  /// instead of hiding: a card whose rows come and go with who is signed in
  /// reads as broken, not as policy.
  Future<bool> _mayManageProfiles() async {
    final registry = ProfileBootstrap.registry;
    final authorization = await ProfileAuthorizationContext.capture(registry);
    UserProfile? actor;
    try {
      actor = await authorization.validate(registry);
    } catch (_) {
      actor = null;
    }
    return actor != null &&
        actor.role == UserProfileRole.admin &&
        actor.allows(ProfileFeature.manageProfiles);
  }

  void _profilesDenied(String action) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Only an admin can $action profiles.')),
    );
  }

  /// The Profiles card's "Add a profile" row — the hub's create flow without
  /// the detour through the hub.
  Future<void> _addProfile() async {
    if (!await _mayManageProfiles()) {
      _profilesDenied('add');
      return;
    }
    if (!mounted) return;
    await ProfileSetupFlow.show(context);
    if (!mounted) return;
    setState(() {});
  }

  /// The Profiles card's "Edit this profile" row — straight into the ACTIVE
  /// profile's editor, matching the hub's active-card Edit button.
  Future<void> _editActiveProfile() async {
    final registry = ProfileBootstrap.registry;
    if (!await _mayManageProfiles()) {
      _profilesDenied('edit');
      return;
    }
    final profiles = await registry.listProfiles();
    final activeId = ProfileRuntime.capture().profileId;
    UserProfile? active;
    for (final profile in profiles) {
      if (profile.id == activeId) {
        active = profile;
        break;
      }
    }
    if (active == null) return;
    if (!mounted) return;
    await ProfileSetupFlow.show(context, profile: active);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openFilterSettings() async {
    await pushSettingsPage(context, const FilterSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openProviderSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    await pushSettingsPage(context, const ProviderSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openQuickPlaySettings() async {
    await pushSettingsPage(context, const QuickPlaySettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openDiscoverSettings() async {
    await pushSettingsPage(context, const DiscoverSettingsPage());
  }

  Future<void> _openRealDebridSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const RealDebridSettingsPage(),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  Future<void> _openTorboxSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const TorboxSettingsPage(),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  Future<void> _openPremiumizeSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const PremiumizeSettingsPage(),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  Future<void> _openAllDebridSettings() async {
    if (!await _ensureProfileFeature(ProfileFeature.cloud)) return;
    if (!mounted) return;
    final loggedOut = await pushSettingsPage<bool>(
      context,
      const AllDebridSettingsPage(),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  void _focusFirstCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _firstCardFocusNode.requestFocus();
      }
    });
  }

  /// Route checks are defense in depth; services still validate their own
  /// capabilities. Keeping this helper fail-closed also protects search/deep
  /// links that call an opener while a policy edit is propagating.
  Future<bool> _ensureProfileFeature(ProfileFeature feature) async {
    if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
      return true;
    }
    var allowed = false;
    try {
      final registry = ProfileBootstrap.registry;
      final authorization = await ProfileAuthorizationContext.capture(registry);
      final actor = await authorization.validate(registry);
      allowed = actor.allows(feature);
    } catch (_) {
      allowed = false;
    }
    if (!allowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This feature is disabled for this profile.'),
        ),
      );
    }
    return allowed;
  }

  Future<void> _createProfileBackup() =>
      ProfileBackupFlows(context).createProfileBackup();

  Future<void> _restoreProfileBackup() async {
    await ProfileBackupFlows(
      context,
      onRestored: () async {
        await _loadSummaries();
        MainPageBridge.notifyIntegrationChanged();
      },
    ).restoreProfileBackup();
  }

  Future<void> _openSyncAndMigrate() async {
    if (ProfileRuntime.mode != ProfileRuntimeMode.profileCommitted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sync and backup becomes available after Profiles setup.',
            ),
          ),
        );
      }
      return;
    }
    if (!await _ensureProfileFeature(ProfileFeature.backupRestore)) return;
    if (!mounted) return;
    await pushSettingsPage(
      context,
      SyncAndMigratePage(
        onRestored: () async {
          await _loadSummaries();
          MainPageBridge.notifyIntegrationChanged();
        },
      ),
    );
  }

  Future<void> _createBackup() async {
    if (ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted) {
      await _createProfileBackup();
      return;
    }
    final app = AppThemeScope.of(context);
    // Build the payload first so we can warn if it's empty.
    final Map<String, dynamic> payload;
    try {
      payload = await BackupRestoreService.buildBackup();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to build the backup')),
      );
      return;
    }

    final summary = BackupRestoreService.summarize(payload);
    if (summary.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to back up — no services are configured.'),
        ),
      );
      return;
    }

    // File-imported IPTV playlists are left out of the payload on purpose —
    // say so rather than let the user discover it after a restore.
    final iptvProviders = await IptvTransferPayload.countPlaylists();

    if (!mounted) return;
    var includeCredentials = true;
    var usePassphrase = false;
    final passphraseController = TextEditingController();
    final confirmController = TextEditingController();
    final passphraseFocus = FocusNode(debugLabel: 'backupPassphrase');
    final confirmFocus = FocusNode(debugLabel: 'backupPassphraseConfirmation');
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final passphraseOk =
              !usePassphrase ||
              (passphraseController.text.isNotEmpty &&
                  passphraseController.text == confirmController.text);
          return AlertDialog(
            title: const Text('Create backup'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('The backup will include:'),
                  const SizedBox(height: 8),
                  ..._backupSummaryLines(
                    summary,
                  ).map((line) => Text('• $line')),
                  if (iptvProviders.fileImported > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${iptvProviders.fileImported} IPTV playlist'
                        '${iptvProviders.fileImported == 1 ? '' : 's'} imported from '
                        'a file won\'t be included — re-import the file on the other '
                        'device. Starred channels from them still travel.',
                        style: TextStyle(
                          fontSize: 12,
                          color: app.fade(app.core.tx, 0x99 / 0xFF),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Include credentials'),
                    subtitle: const Text(
                      'Off: share your setup without your accounts. Skips '
                      'anything that embeds them: addons, Xtream providers, '
                      'indexers, starred channels and lists. M3U URLs are '
                      'kept — use a passphrase to protect those.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: includeCredentials,
                    onChanged: (v) =>
                        setDialogState(() => includeCredentials = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Encrypt with a passphrase'),
                    value: usePassphrase,
                    onChanged: (v) => setDialogState(() => usePassphrase = v),
                  ),
                  if (usePassphrase) ...[
                    TvTextField(
                      controller: passphraseController,
                      focusNode: passphraseFocus,
                      obscureText: true,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      keyboardSubmitLabel: 'Next',
                      decoration: const InputDecoration(
                        labelText: 'Passphrase',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (_) => confirmFocus.requestFocus(),
                    ),
                    const SizedBox(height: 8),
                    TvTextField(
                      controller: confirmController,
                      focusNode: confirmFocus,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      keyboardSubmitLabel: 'Save backup',
                      decoration: const InputDecoration(
                        labelText: 'Confirm passphrase',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (_) {
                        if (passphraseOk) Navigator.of(context).pop(true);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (usePassphrase)
                    Text(
                      'Encrypted with your passphrase — if you forget it, '
                      'this backup cannot be opened.',
                      style: TextStyle(
                        fontSize: 12,
                        color: app.fade(app.core.tx, 0x99 / 0xFF),
                      ),
                    )
                  else if (includeCredentials)
                    const Text(
                      'Credentials are stored in plain text. Keep this file '
                      'private and treat it like a password.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: passphraseOk
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: const Text('Save backup'),
              ),
            ],
          );
        },
      ),
    );

    final passphrase = usePassphrase ? passphraseController.text : null;
    passphraseController.dispose();
    confirmController.dispose();
    passphraseFocus.dispose();
    confirmFocus.dispose();
    if (confirmed != true) return;
    if (!mounted) return;

    // The pre-dialog payload was only for the summary — rebuild honoring the
    // include-credentials choice.
    Map<String, dynamic> exportMap = includeCredentials
        ? payload
        : await BackupRestoreService.buildBackup(includeCredentials: false);

    // The pre-dialog summary described the FULL payload — stripping
    // credentials can leave nothing behind (a device configured with only
    // accounts), and restore rejects an empty backup anyway.
    if (!includeCredentials &&
        BackupRestoreService.summarize(exportMap).isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nothing left to back up without credentials — everything on '
            'this device is account data.',
          ),
        ),
      );
      return;
    }

    if (passphrase != null && passphrase.isNotEmpty) {
      if (!mounted) return;
      // Captured BEFORE the await: the modal lives on the root navigator and
      // must be popped even if this screen unmounts while Argon2id runs —
      // a mounted-check first would strand an undismissable dialog.
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      // Argon2id takes seconds on TV hardware — show progress.
      showSettingsDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Encrypting backup…')),
              ],
            ),
          ),
        ),
      );
      try {
        exportMap = await BackupRestoreService.encryptBackup(
          exportMap,
          passphrase,
        );
      } catch (_) {
        rootNavigator.pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to encrypt the backup')),
        );
        return;
      }
      rootNavigator.pop();
      if (!mounted) return;
    }

    final jsonContent = const JsonEncoder.withIndent('  ').convert(exportMap);
    final bytes = Uint8List.fromList(utf8.encode(jsonContent));
    final ts = DateTime.now();
    final fileName =
        'debrify-backup-${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}-${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}.json';

    try {
      final savedPath = await ProfileBackupFlows(
        context,
      ).saveBackupFile(fileName: fileName, bytes: bytes);
      if (!mounted || savedPath == null) return;
      // On Android, savedPath may be a content:// URI from the Storage
      // Access Framework — show it raw so the user has at least a
      // breadcrumb of where the backup went.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup saved to $savedPath'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save the backup')),
      );
    }
  }

  Future<void> _exportDiagnosticLogs() async {
    if (_exportingDiagnostics) return;
    if (!await _activeProfileMayExportDiagnostics()) {
      if (!mounted) return;
      setState(() => _diagnosticExportVisible = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only an admin can export diagnostic logs.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _exportingDiagnostics = true);

    try {
      DiagnosticLog.instance.recordEvent(
        source: 'settings',
        event: 'diagnostic_export_requested',
      );
      final exported = await DiagnosticLog.instance.exportLastWindow();
      if (!mounted) return;

      if (kIsWeb) {
        final savedReference = await FilePicker.platform.saveFile(
          dialogTitle: 'Save diagnostic logs',
          fileName: exported.fileName,
          type: FileType.custom,
          allowedExtensions: const <String>['jsonl'],
          bytes: exported.bytes,
        );
        if (!mounted || savedReference == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${exported.entryCount} privacy-filtered diagnostic entries.',
            ),
          ),
        );
      } else {
        await ProfileBackupFlows(context).saveBackupFile(
          fileName: exported.fileName,
          bytes: exported.bytes,
          mimeType: 'application/x-ndjson',
          artifactLabel: 'diagnostic log',
        );
      }
      DiagnosticLog.instance.recordEvent(
        source: 'settings',
        event: 'diagnostic_export_saved',
        fields: <String, Object?>{'entries': exported.entryCount},
      );
    } catch (error, stackTrace) {
      DiagnosticLog.instance.recordError(
        source: 'settings',
        event: 'diagnostic_export_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export diagnostic logs.')),
      );
    } finally {
      if (mounted) setState(() => _exportingDiagnostics = false);
    }
  }

  /// Passphrase prompt loop for an encrypted backup envelope. Returns the
  /// decrypted inner payload, or null when the user cancels. A wrong
  /// passphrase re-shows the prompt with an inline error instead of aborting.
  Future<Map<String, dynamic>?> _promptAndDecryptBackup(
    Map<String, dynamic> envelope,
  ) async {
    String? errorText;
    while (true) {
      if (!mounted) return null;
      final controller = TextEditingController();
      final entered = await showSettingsDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Backup is encrypted'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (envelope['createdAt'] is String)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Created: ${envelope['createdAt']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                TvTextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  keyboardSubmitLabel: 'Unlock',
                  decoration: InputDecoration(
                    labelText: 'Passphrase',
                    errorText: errorText,
                  ),
                  onSubmitted: (value) => Navigator.of(context).pop(value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Unlock'),
              ),
            ],
          ),
        ),
      );
      controller.dispose();
      if (entered == null || entered.isEmpty) return null;
      if (!mounted) return null;

      // Captured BEFORE the await so the modal is popped even if this screen
      // unmounts while the KDF runs (see _createBackup's encrypt block).
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      showSettingsDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Unlocking backup…')),
              ],
            ),
          ),
        ),
      );
      try {
        final inner = await BackupRestoreService.decryptBackup(
          envelope,
          entered,
        );
        rootNavigator.pop();
        if (!mounted) return null;
        return inner;
      } on BackupPassphraseException {
        rootNavigator.pop();
        if (!mounted) return null;
        errorText = 'Wrong passphrase — try again';
      } on FormatException {
        rootNavigator.pop();
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The backup format is invalid')),
        );
        return null;
      }
    }
  }

  Future<void> _restoreBackup() async {
    if (ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted) {
      await _restoreProfileBackup();
      return;
    }
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final FilePickerResult? pick;
    try {
      // FileType.any instead of custom: Android's MIME mapping for `json` is
      // unreliable and throws PlatformException("Unsupported filter") on many
      // devices, leaving the backup unselectable. The contents are validated by
      // BackupRestoreService.parse below, so no extension filter is needed.
      pick = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose Debrify backup file',
        type: FileType.any,
        withData: false,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the file picker')),
      );
      return;
    }

    if (pick == null || pick.files.isEmpty) return;
    final file = pick.files.first;

    // FileType.any lets the user pick anything. Reject an implausibly large
    // file before opening it so a stray huge selection cannot be allocated.
    // Sized so the app always accepts what its own export can produce: a
    // passphrase-encrypted envelope base64-inflates the payload by ~4/3, so an
    // IPTV-heavy ~20 MiB backup arrives here at ~27 MiB.
    if (file.size > 40 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That file is too large to be a Debrify backup.'),
        ),
      );
      return;
    }

    final String content;
    try {
      if (file.path == null) {
        throw Exception('Could not read backup file contents');
      }
      final selected = File(file.path!);
      content = await PortableProfilePackage.readBoundedUtf8(
        selected.openRead(),
        maxBytes: 40 * 1024 * 1024,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to read the backup file')),
      );
      return;
    }

    Map<String, dynamic> payload;
    try {
      payload = BackupRestoreService.parse(content);
    } on FormatException catch (error) {
      if (!mounted) return;
      final looksLikeProfilePackage =
          content.contains('"format":"debrify-profile-package"') ||
          content.contains('"format": "debrify-profile-package"');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            looksLikeProfilePackage
                ? 'This is a profile backup. Enable profiles or update to a build that supports profile restore.'
                : error.message,
          ),
        ),
      );
      return;
    }

    if (BackupRestoreService.isEncrypted(payload)) {
      final inner = await _promptAndDecryptBackup(payload);
      if (inner == null) return; // Cancelled or unrecoverable.
      payload = inner;
    }

    final summary = BackupRestoreService.summarize(payload);
    if (summary.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup contains no data to restore.')),
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (summary.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Created: ${summary.createdAt}',
                  style: TextStyle(
                    fontSize: 12,
                    color: app.fade(app.core.tx, 0x99 / 0xFF),
                  ),
                ),
              ),
            const Text('This backup contains:'),
            const SizedBox(height: 8),
            ..._backupSummaryLines(summary).map((line) => Text('• $line')),
            const SizedBox(height: 12),
            const Text(
              'Saved credentials (Real-Debrid, Torbox, Premiumize, AllDebrid, PikPak, Trakt, Simkl) will '
              'be overwritten. Addons, search engines, WebDAV servers, '
              'indexer managers, and IPTV providers you already have are kept '
              'as-is. IPTV favorites and lists merge into what\'s here — '
              'nothing is removed.',
              style: TextStyle(fontSize: 12),
            ),
            if (summary.addonCount > 0 || summary.searchEngineCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Restoring addons and search engines needs a network '
                  'connection.',
                  style: TextStyle(
                    fontSize: 12,
                    color: app.fade(app.core.tx, 0x99 / 0xFF),
                  ),
                ),
              ),
            if (summary.webDavServerCount > 0 ||
                summary.indexerManagerCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'WebDAV and Jackett/Prowlarr URLs may be local-network '
                  'only — they won\'t work on a different network.',
                  style: TextStyle(
                    fontSize: 12,
                    color: app.fade(app.core.tx, 0x99 / 0xFF),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // Run the restore. Show a non-dismissible progress dialog while it runs
    // — search engines and addons require network and can take a while.
    showSettingsDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Restoring backup…')),
            ],
          ),
        ),
      ),
    );

    RestoreReport report;
    try {
      report = await BackupRestoreService.applyBackup(payload);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Restore failed')));
      return;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final msg = _formatRestoreReport(report);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: report.hasAnyFailure ? t.warning : null,
        duration: const Duration(seconds: 5),
      ),
    );

    // Drop any cached account info from a previous session so the cards
    // don't briefly show stale identity while Phase 2 of _loadSummaries
    // re-fetches it for the newly-restored keys.
    if (report.realDebrid) AccountService.clearUserInfo();
    if (report.torbox) TorboxAccountService.clearUserInfo();
    if (report.premiumize) PremiumizeAccountService.clearUserInfo();
    if (report.allDebrid) AllDebridAccountService.clearUserInfo();

    // Re-run the summary loader so the connection cards reflect the newly
    // restored services (and kick off background account refresh).
    await _loadSummaries();

    // Tell the rest of the app — navbar, home tabs, search surfaces — that
    // integrations changed so they rebuild against the restored services
    // (same hook the individual settings pages use after a credential edit).
    MainPageBridge.notifyIntegrationChanged();
  }

  List<String> _backupSummaryLines(BackupSummary s) {
    final lines = <String>[];
    if (s.hasRealDebrid) lines.add('Real-Debrid');
    if (s.hasTorbox) lines.add('Torbox');
    if (s.hasPremiumize) lines.add('Premiumize');
    if (s.hasAllDebrid) lines.add('AllDebrid');
    if (s.hasPikpak) lines.add('PikPak');
    if (s.hasTrakt) lines.add('Trakt');
    if (s.hasSimkl) lines.add('Simkl');
    if (s.hasMdblist) lines.add('MDBList');
    if (s.searchEngineCount > 0) {
      lines.add('Search engines (${s.searchEngineCount})');
    }
    if (s.addonCount > 0) lines.add('Stremio addons (${s.addonCount})');
    if (s.webDavServerCount > 0) {
      lines.add('WebDAV servers (${s.webDavServerCount})');
    }
    if (s.indexerManagerCount > 0) {
      lines.add('Jackett/Prowlarr (${s.indexerManagerCount})');
    }
    if (s.iptvPlaylistCount > 0) {
      lines.add('IPTV providers (${s.iptvPlaylistCount})');
    }
    if (s.iptvFavoriteCount > 0) {
      lines.add('IPTV favorites (${s.iptvFavoriteCount} channels)');
    }
    if (s.iptvListCount > 0) {
      lines.add(
        'IPTV lists (${s.iptvListCount}, '
        '${s.iptvListChannelCount} channels)',
      );
    }
    if (s.homeCollectionCount > 0) {
      lines.add('Collections (${s.homeCollectionCount})');
    }
    if (s.streamBadgeSourceCount > 0) {
      lines.add('Stream badge rulesets (${s.streamBadgeSourceCount})');
    }
    return lines;
  }

  String _formatRestoreReport(RestoreReport r) {
    final parts = <String>[];
    if (r.realDebrid) parts.add('Real-Debrid');
    if (r.torbox) parts.add('Torbox');
    if (r.premiumize) parts.add('Premiumize');
    if (r.allDebrid) parts.add('AllDebrid');
    if (r.pikpak) parts.add('PikPak');
    if (r.trakt) parts.add('Trakt');
    if (r.simkl) parts.add('Simkl');
    if (r.mdblist) parts.add('MDBList');
    if (r.searchEnginesImported > 0) {
      parts.add('${r.searchEnginesImported} new engine(s)');
    }
    if (r.addonsImported > 0) {
      parts.add('${r.addonsImported} new addon(s)');
    }
    if (r.webDavServersImported > 0) {
      parts.add('${r.webDavServersImported} WebDAV server(s)');
    }
    if (r.indexerManagersImported > 0) {
      parts.add('${r.indexerManagersImported} indexer manager(s)');
    }
    if (r.iptvPlaylistsImported > 0) {
      parts.add('${r.iptvPlaylistsImported} IPTV provider(s)');
    }
    if (r.iptvFavoritesImported > 0) {
      parts.add('${r.iptvFavoritesImported} favorite channel(s)');
    }
    if (r.iptvListsCreated > 0) {
      parts.add('${r.iptvListsCreated} IPTV list(s)');
    }
    if (r.iptvListChannelsImported > 0) {
      parts.add('${r.iptvListChannelsImported} list channel(s)');
    }
    if (r.homeCollectionsImported > 0) {
      parts.add('${r.homeCollectionsImported} collection(s)');
    }
    if (r.streamBadgeSourcesImported > 0) {
      parts.add('${r.streamBadgeSourcesImported} badge ruleset(s)');
    }

    if (parts.isEmpty && !r.hasAnyFailure) {
      return 'Nothing new to restore — everything was already present';
    }
    final base = parts.isEmpty
        ? 'Restore finished'
        : 'Restored: ${parts.join(', ')}';
    final notes = <String>[];
    if (r.searchEnginesAlreadyPresent > 0) {
      notes.add('${r.searchEnginesAlreadyPresent} engine(s) already present');
    }
    if (r.addonsAlreadyPresent > 0) {
      notes.add('${r.addonsAlreadyPresent} addon(s) already present');
    }
    if (r.webDavServersAlreadyPresent > 0) {
      notes.add(
        '${r.webDavServersAlreadyPresent} WebDAV server(s) already present',
      );
    }
    if (r.indexerManagersAlreadyPresent > 0) {
      notes.add(
        '${r.indexerManagersAlreadyPresent} indexer manager(s) already present',
      );
    }
    if (r.iptvPlaylistsAlreadyPresent > 0) {
      notes.add(
        '${r.iptvPlaylistsAlreadyPresent} IPTV provider(s) already present',
      );
    }
    if (r.iptvFavoritesAlreadyPresent > 0) {
      notes.add('${r.iptvFavoritesAlreadyPresent} favorite(s) already present');
    }
    if (r.iptvListsMerged > 0) {
      notes.add('${r.iptvListsMerged} existing list(s) topped up');
    }
    final withNotes = notes.isEmpty ? base : '$base (${notes.join(', ')})';

    if (!r.hasAnyFailure) return withNotes;
    final failed = <String>[];
    if (r.pikpakLoginFailed) {
      failed.add(
        'PikPak login (credentials saved — retry from PikPak settings)',
      );
    }
    if (r.searchEnginesFailed > 0) {
      failed.add('${r.searchEnginesFailed} engine(s)');
    }
    if (r.addonsFailed > 0) failed.add('${r.addonsFailed} addon(s)');
    if (r.webDavServersFailed > 0) {
      failed.add('${r.webDavServersFailed} WebDAV server(s)');
    }
    if (r.indexerManagersFailed > 0) {
      failed.add('${r.indexerManagersFailed} indexer manager(s)');
    }
    if (r.iptvPlaylistsFailed > 0) {
      failed.add('${r.iptvPlaylistsFailed} IPTV provider(s)');
    }
    if (r.iptvFavoritesFailed > 0) {
      failed.add('${r.iptvFavoritesFailed} favorite(s)');
    }
    if (r.iptvListsFailed > 0) {
      failed.add('${r.iptvListsFailed} IPTV list entr(ies)');
    }
    failed.addAll(r.errors);
    return '$withNotes — failed: ${failed.join(', ')}';
  }

  // Android uses SAF; Windows/Linux use a plain picked path. macOS is
  // deliberately excluded: the sandbox grants read-only user-selected access,
  // so a writable custom folder needs security-scoped bookmarks (own feature).
  bool get _downloadLocationSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows || Platform.isLinux);

  bool get _downloadLocationUsesSaf => !kIsWeb && Platform.isAndroid;

  String get _defaultDownloadLocationLabel {
    if (_downloadLocationUsesSaf || Platform.isWindows) {
      return 'Downloads/Debrify (default)';
    }
    // Linux: getDownloadsDirectory isn't used there — the app writes under
    // its documents dir (see DownloadService._appDownloadsSubdir fallback).
    return 'App folder (default)';
  }

  Future<void> _loadDownloadLocation() async {
    if (!_downloadLocationSupported) return;
    final String? name = _downloadLocationUsesSaf
        ? await StorageService.getDownloadTreeDisplayName()
        : await StorageService.getDownloadDirPath();
    if (!mounted) return;
    setState(() {
      _downloadLocationSubtitle = name == null
          ? _defaultDownloadLocationLabel
          : 'Custom: $name';
    });
  }

  Future<void> _openDownloadLocationSettings() async {
    final String? currentTree = _downloadLocationUsesSaf
        ? await StorageService.getDownloadTreeUri()
        : await StorageService.getDownloadDirPath();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppThemeScope.of(context).settings.sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: const Text('Download location'),
                subtitle: Text(_downloadLocationSubtitle),
              ),
              const Divider(height: 1),
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.drive_folder_upload_rounded),
                title: const Text('Choose folder…'),
                subtitle: Text(
                  _downloadLocationUsesSaf
                      ? 'Pick any folder, including an SD card. New downloads go there.'
                      : 'Pick any folder, including another drive. New downloads go there.',
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _chooseDownloadFolder();
                },
              ),
              if (currentTree != null)
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: const Text('Reset to default'),
                  subtitle: Text(
                    'Save to ${_defaultDownloadLocationLabel.replaceAll(' (default)', '')} again',
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _resetDownloadFolder();
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _chooseDownloadFolder() async {
    if (!_downloadLocationUsesSaf) {
      await _chooseDownloadFolderDesktop();
      return;
    }
    final res = await AndroidNativeDownloader.pickDownloadDirectory();
    if (res == null) return; // user backed out of the picker
    final newTree = (res['treeUri'] ?? '').toString();
    final name = (res['displayName'] ?? 'Custom folder').toString();
    if (newTree.isEmpty) return;
    final old = await StorageService.getDownloadTreeUri();
    if (old != null && old.isNotEmpty && old != newTree) {
      // Release the previous grant — persisted-permission slots are limited.
      await AndroidNativeDownloader.releaseDownloadDirectory(old);
    }
    await StorageService.setDownloadTreeUri(newTree, name);
    await _loadDownloadLocation();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('New downloads will be saved to "$name"')),
    );
  }

  /// Windows/Linux: a picked folder is a plain path — no grants to manage,
  /// but verify it's writable before persisting so the pref can't be born
  /// pointing at a read-only location.
  Future<void> _chooseDownloadFolderDesktop() async {
    String? dir;
    try {
      dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose download folder',
      );
    } catch (e) {
      // file_picker shells out to zenity/qarma/kdialog on Linux and throws
      // when none is installed — surface it instead of failing silently.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't open a folder picker on this system (a dialog tool like zenity may be missing).",
          ),
        ),
      );
      return;
    }
    if (dir == null || dir.trim().isEmpty) return; // user backed out
    // Normalize (also drops any trailing separator, so a drive-root pick
    // like "C:\" can't render doubled separators downstream).
    dir = path.normalize(dir.trim());
    // UNC network shares break background_downloader's task construction
    // (its Task constructor strips the leading backslash) — refuse rather
    // than accept a folder downloads can't actually reach.
    if (Platform.isWindows && dir.startsWith(r'\\')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Network shares aren\'t supported yet — map the share to a drive letter or pick a local folder.',
          ),
        ),
      );
      return;
    }
    bool writable = false;
    try {
      final probe = File(
        path.join(
          dir,
          '.debrify_write_probe_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
      await probe.writeAsString('probe', flush: true);
      // Write success alone proves writability; delete is best-effort (a
      // Windows AV/indexer lock on the fresh file must not fail the pick).
      try {
        await probe.delete();
      } catch (_) {}
      writable = true;
    } catch (_) {}
    if (!writable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("That folder isn't writable — pick another one."),
        ),
      );
      return;
    }
    await StorageService.setDownloadDirPath(dir);
    await _loadDownloadLocation();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('New downloads will be saved to "$dir"')),
    );
  }

  Future<void> _resetDownloadFolder() async {
    if (_downloadLocationUsesSaf) {
      final old = await StorageService.getDownloadTreeUri();
      if (old != null && old.isNotEmpty) {
        await AndroidNativeDownloader.releaseDownloadDirectory(old);
      }
      await StorageService.clearDownloadTreeUri();
    } else {
      await StorageService.clearDownloadDirPath();
    }
    await _loadDownloadLocation();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Downloads will be saved to ${_defaultDownloadLocationLabel.replaceAll(' (default)', '')}',
        ),
      ),
    );
  }

  Future<void> _clearDownloadData() async {
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear download data?'),
        content: const Text(
          'This removes queued entries and download history. Files already saved to disk stay untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DownloadService.instance.clearDownloadDatabase();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Download data cleared')));
    }
  }

  Future<void> _clearPlaybackData() async {
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear playback data?'),
        content: const Text(
          'This resets resume positions and cached playback preferences.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await StorageService.clearAllPlaybackData();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Playback data cleared')));
    }
  }

  Future<void> _resetAppData() async {
    final profileMode =
        ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted;
    ProfileAuthorizationContext? authorization;
    UserProfile? actor;
    if (profileMode) {
      authorization = await ProfileAuthorizationContext.capture(
        ProfileBootstrap.registry,
      );
      actor = await authorization.validate(ProfileBootstrap.registry);
    }
    final mayResetDevice =
        actor?.role == UserProfileRole.admin &&
        actor!.allows(ProfileFeature.manageProfiles) &&
        actor.allows(ProfileFeature.backupRestore);
    final action = await showSettingsDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(profileMode ? 'Reset this profile?' : 'Reset Debrify?'),
        content: Text(
          profileMode
              ? 'This clears this profile\'s settings, history, playlists, and private app data. The profile, PIN, shared connections, active jobs, downloads, and recordings remain untouched.'
              : 'This removes saved connections, playback history, download queue, and onboarding completion. Files already saved to disk remain untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (mayResetDevice)
            TextButton(
              onPressed: () => Navigator.of(context).pop('device'),
              child: const Text('Reset device…'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('profile'),
            child: Text(profileMode ? 'Reset profile' : 'Reset app'),
          ),
        ],
      ),
    );

    if (action == null) return;

    if (profileMode && action == 'device') {
      if (!await ProfileBackupFlows(
        context,
      ).reauthenticateSensitiveProfile(actor!)) {
        return;
      }
      final typed = TextEditingController();
      final confirmed = await showSettingsDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Reset this Debrify installation?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All profiles, connections, jobs, schedules, private data, remote pairings, and device keys will be removed. Downloaded and recorded files remain on disk. The app will close and start fresh next launch.',
                ),
                const SizedBox(height: 16),
                TvTextField(
                  controller: typed,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  keyboardSubmitLabel: 'Reset device',
                  decoration: const InputDecoration(
                    labelText: 'Type RESET to continue',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) {
                    if (typed.text == 'RESET') {
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: typed.text == 'RESET'
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: const Text('Reset device'),
              ),
            ],
          ),
        ),
      );
      typed
        ..clear()
        ..dispose();
      if (confirmed != true) return;
      await ProfileDeviceResetService.reset(
        registry: ProfileBootstrap.registry,
        authorization: authorization!,
      );
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        exit(0);
      }
      await SystemNavigator.pop();
      return;
    }

    if (profileMode && action == 'profile') {
      await ProfileResetService(
        registry: ProfileBootstrap.registry,
        lifecycleParticipants: <ProfileLifecycleParticipant>[
          ProfileAppLifecycleParticipant(),
        ],
      ).resetActiveProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile data reset. Connections and files were kept.'),
        ),
      );
      await _loadSummaries();
      return;
    }

    await StorageService.deleteApiKey();
    AccountService.clearUserInfo();
    await StorageService.deleteTorboxApiKey();
    TorboxAccountService.clearUserInfo();
    await StorageService.deletePremiumizeApiKey();
    await StorageService.deleteAllDebridApiKey();
    AllDebridAccountService.clearUserInfo();
    await StorageService.clearPikPakAuth();
    await StorageService.clearWebDav();
    await StorageService.clearTraktAuth();
    // Clears the token + username AND the in-memory library cache.
    await SimklService.instance.logout();
    // Clears the key + username AND the in-memory list/items cache.
    await MdblistService.instance.logout();
    await DownloadService.instance.clearDownloadDatabase();
    // Reset is a device-local wipe: none of these clears may record synced
    // deletions, or reconnecting sync later replays them circle-wide.
    await StorageService.clearAllPlaybackData(recordSyncDeletions: false);
    await StorageService.clearContinueWatching(recordSyncDeletions: false);
    await StorageService.clearPlaylist(recordSyncDeletions: false);
    await StorageService.clearAllPlaylistMetadata(recordSyncDeletions: false);
    await StorageService.clearMyWatchlist();
    await StorageService.clearTorrentSearchHistory();
    await StorageService.clearAllStartupSettings();
    await StorageService.clearAllHomePageSettings();
    await StorageService.clearAllIntegrationStates();
    await StorageService.clearDebrifyTvProviderAndLegacy();
    await StorageService.clearAllFilterSettings();
    await StorageService.clearAllTorrentEngineSettings();
    await StorageService.clearAllPostTorrentActions();
    await StorageService.clearAllDebrifyTvSettings();
    // A device-local reset must never mint circle-wide channel deletions:
    // rejoining a sync circle later means adopting its data, not erasing it.
    await DebrifyTvRepository.instance.clearAll(
      origin: WebDavSyncMutationOrigin.maintenance,
    );
    await StremioService.instance.clearAllAddons();
    await StorageService.setInitialSetupComplete(false);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('App data reset. You can reconnect services anytime.'),
      ),
    );

    await _loadSummaries();
  }

  Future<void> _checkForAppUpdates() async {
    if (_checkingUpdates) return;
    if (_currentVersionName.isEmpty) return;
    await StorageService.setIgnoredUpdateVersion(null);

    setState(() {
      _checkingUpdates = true;
      _updateSubtitle = 'Checking GitHub releases...';
    });

    try {
      final summary = await UpdateService.checkForUpdates(
        currentVersion: _currentVersionName,
      );
      if (!mounted) return;
      setState(() {
        _updateSubtitle = summary.updateAvailable
            ? 'Update available (${summary.release.versionLabel})'
            : 'You are on the latest build';
        _checkingUpdates = false;
      });
      await _showReleaseDetails(summary);
    } on UpdateException catch (err) {
      _showSnack(err.message);
      if (mounted) {
        setState(() {
          _updateSubtitle = 'Unable to reach GitHub releases';
          _checkingUpdates = false;
        });
      }
    } catch (_) {
      _showSnack('Could not check for updates. Please try again later.');
      if (mounted) {
        setState(() {
          _updateSubtitle = 'Unable to reach GitHub releases';
          _checkingUpdates = false;
        });
      }
    }
  }

  Future<void> _showReleaseDetails(UpdateSummary summary) async {
    final app = AppThemeScope.of(context);
    if (!mounted) return;
    final release = summary.release;
    final theme = Theme.of(context);
    final bool isAndroidDevice = !kIsWeb && Platform.isAndroid;
    final bool canInstallDirectly =
        summary.updateAvailable &&
        isAndroidDevice &&
        release.androidApkAsset != null;
    final String latestLabel = release.versionLabel.isNotEmpty
        ? release.versionLabel
        : 'Latest release';
    final String notes = release.body.trim().isNotEmpty
        ? release.body.trim()
        : 'Release notes will appear here once published.';
    final String? publishedLabel = release.publishedAt != null
        ? DateFormat.yMMMd().format(release.publishedAt!.toLocal())
        : null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final baseTheme = Theme.of(sheetContext);
        final textTheme = baseTheme.textTheme;
        final Color bodyColor = app.fade(app.core.tx, 0.85);
        final markdownStyle = MarkdownStyleSheet.fromTheme(baseTheme).copyWith(
          h1: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: app.core.tx,
          ),
          h2: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: app.core.tx,
          ),
          h3: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: app.core.tx,
          ),
          p: textTheme.bodyMedium?.copyWith(color: bodyColor, height: 1.45),
          strong: const TextStyle(fontWeight: FontWeight.w700),
          listBullet: textTheme.bodyMedium?.copyWith(color: bodyColor),
          blockquote: textTheme.bodyMedium?.copyWith(
            color: app.fade(app.core.tx, 0.7),
          ),
        );
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: app.fade(app.core.tx, 0.2),
                        borderRadius: app.shape.br(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    summary.updateAvailable
                        ? 'Update available'
                        : 'You are up to date',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Installed: $_appVersion',
                    style: textTheme.bodyMedium?.copyWith(
                      color: app.fade(app.core.tx, 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Latest: $latestLabel',
                    style: textTheme.bodyMedium?.copyWith(
                      color: app.fade(app.core.tx, 0.6),
                    ),
                  ),
                  if (publishedLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Published $publishedLabel',
                      style: textTheme.bodySmall?.copyWith(
                        color: app.fade(app.core.tx, 0.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Release notes',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: MarkdownBody(
                        data: notes,
                        selectable: true,
                        onTapLink: (text, href, title) {
                          if (href == null) return;
                          final uri = Uri.tryParse(href);
                          if (uri != null) {
                            launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                        styleSheet: markdownStyle,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (canInstallDirectly)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _startAndroidUpdateDownload(release);
                          },
                          icon: const Icon(Icons.system_update_alt_rounded),
                          label: const Text('Download & Install'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          _openReleasesPage(release.htmlUrl);
                        },
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Open Releases Page'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleAutoUpdateChecks(bool enabled) async {
    setState(() {
      _autoUpdateChecksEnabled = enabled;
    });
    await StorageService.setUpdateAutoCheckEnabled(enabled);
  }

  Future<void> _toggleTvKeyboard(bool enabled) async {
    setState(() {
      _tvKeyboardEnabled = enabled;
    });
    await StorageService.setTvKeyboardEnabled(enabled);
  }

  /// The page writes the pref itself (and says a restart is needed — the
  /// engine is built with the factor in MainActivity.onCreate); re-read it on
  /// the way back so the rail row's caption matches.
  Future<void> _openTvScreenSize() async {
    await pushSettingsPage(context, const TvScreenSizePage());
    if (!mounted) return;
    final percent = await StorageService.getTvUiScalePercent();
    if (!mounted) return;
    setState(() {
      _tvUiScalePercent = percent;
    });
  }

  /// Same contract as [_openTvScreenSize] — MainActivity reads the render
  /// pref in `onCreate` too, so the page owns the write and the restart
  /// notice; we only re-read for the row's caption.
  Future<void> _openTvRenderQuality() async {
    await pushSettingsPage(context, const TvRenderQualityPage());
    if (!mounted) return;
    final quality = await StorageService.getTvRenderQuality();
    if (!mounted) return;
    setState(() {
      _tvRenderQuality = quality;
    });
  }

  Future<void> _openTvHeroArtworkQuality() async {
    await pushSettingsPage(context, const TvHeroArtworkQualityPage());
    if (!mounted) return;
    final quality = await StorageService.getTvHeroArtworkQuality();
    if (!mounted) return;
    setState(() {
      _tvHeroArtworkQuality = quality;
    });
  }

  /// The page writes the pref and live-applies via MainPageBridge; re-read it
  /// on the way back so the rail row's caption matches.
  Future<void> _openTvHomeStyle() async {
    await pushSettingsPage(context, const TvHomeStylePage());
    if (!mounted) return;
    final style = await StorageService.getTvHomeStyle();
    if (!mounted) return;
    setState(() {
      _tvHomeStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the Discover layout picker.
  Future<void> _openDiscoverLayout() async {
    await pushSettingsPage(context, const DiscoverLayoutPage());
    if (!mounted) return;
    final layout = await StorageService.getDiscoverLayout();
    if (!mounted) return;
    setState(() {
      _discoverLayout = layout;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the sidebar chrome picker.
  Future<void> _openTvSidebarStyle() async {
    await pushSettingsPage(context, const TvSidebarStylePage());
    if (!mounted) return;
    final style = await StorageService.getTvSidebarStyle();
    if (!mounted) return;
    setState(() {
      _tvSidebarStyle = style;
    });
  }

  /// Same contract, for the desktop/tablet sidebar picker.
  Future<void> _openDesktopSidebarStyle() async {
    await pushSettingsPage(context, const DesktopSidebarStylePage());
    if (!mounted) return;
    final style = await StorageService.getDesktopSidebarStyle();
    if (!mounted) return;
    setState(() {
      _desktopSidebarStyle = style;
    });
  }

  Future<void> _openSidebarCustomization() async {
    await pushSettingsPage(context, const SidebarCustomizationPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openProfileAppearance() async {
    await pushSettingsPage(context, const ProfileAppearancePage());
    if (!mounted) return;
    await ProfileGateStyle.warm();
    if (mounted) setState(() {});
  }

  /// Same contract as [_openTvHomeStyle], for the IPTV page look picker.
  Future<void> _openIptvStylePage() async {
    await pushSettingsPage(context, const IptvStylePage());
    if (!mounted) return;
    final style = await StorageService.getIptvStyle();
    if (!mounted) return;
    setState(() {
      _iptvStyle = style;
    });
  }

  Future<void> _openDebrifyTvStylePage() async {
    await pushSettingsPage(context, const DebrifyTvStylePage());
    if (!mounted) return;
    final style = await StorageService.getDebrifyTvStyle();
    if (!mounted) return;
    setState(() {
      _debrifyTvStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the in-player guide picker.
  Future<void> _openPlayerGuideStylePage() async {
    await pushSettingsPage(context, const PlayerGuideStylePage());
    if (!mounted) return;
    final style = await StorageService.getIptvPlayerGuideStyle();
    if (!mounted) return;
    setState(() {
      _playerGuideStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the play loader look. Also
  /// re-warms the synchronous mirror the play path reads, so a change picked
  /// here applies to the very next play.
  Future<void> _openPlayLoaderStylePage() async {
    await pushSettingsPage(context, const PlayLoaderStylePage());
    if (!mounted) return;
    await PlayLoaderStyleController.warm();
    if (!mounted) return;
    setState(() {
      _playLoaderStyle = PlayLoaderStyleController.cached;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the native TV control skin.
  Future<void> _openTvPlayerControlsStylePage() async {
    await pushSettingsPage(context, const TvPlayerControlsStylePage());
    if (!mounted) return;
    final style = await StorageService.getTvPlayerControlsStyle();
    if (!mounted) return;
    setState(() {
      _tvPlayerControlsStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the Debrify TV playback screen.
  Future<void> _openDebrifyTvPlayerStylePage() async {
    await pushSettingsPage(context, const DebrifyTvPlayerStylePage());
    if (!mounted) return;
    final style = await StorageService.getDebrifyTvPlayerStyle();
    if (!mounted) return;
    setState(() {
      _debrifyTvPlayerStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the player control dock.
  Future<void> _openPlayerDockPage() async {
    await pushSettingsPage(context, const PlayerDockPage());
    if (!mounted) return;
    final style = await StorageService.getPlayerDockStyle();
    final palette = await StorageService.getPlayerDockPalette();
    final size = await StorageService.getPlayerDockSize();
    if (!mounted) return;
    setState(() {
      _playerDockStyle = style;
      _playerDockPalette = palette;
      _playerDockSize = size;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the details-page layout picker.
  Future<void> _openDetailPageStylePage() async {
    await pushSettingsPage(context, const DetailPageStylePage());
    if (!mounted) return;
    final style = await StorageService.getDetailPageStyle();
    if (!mounted) return;
    setState(() {
      _detailPageStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the details-page theme picker.
  Future<void> _openDetailThemePage() async {
    await pushSettingsPage(context, const DetailThemePage());
    if (!mounted) return;
    final theme = await StorageService.getDetailTheme();
    if (!mounted) return;
    setState(() {
      _detailTheme = theme;
    });
  }

  /// Appearance → Theme Lab. The setState on return covers the feedback
  /// toggles the lab hosts — their values are read from the synchronous
  /// mirrors, so one rebuild is the whole refresh.
  Future<void> _openThemeLab() async {
    await pushSettingsPage(context, const ThemeLabPage());
    if (!mounted) return;
    setState(() {});
  }

  /// Appearance → Looks. Re-reads nothing on return: the row's subtitle is
  /// COMPUTED from the live prefs (`AppLooks.active()`), so one setState is
  /// the whole refresh — there is no stored "current Look" that could drift.
  Future<void> _openLooksPage() async {
    await pushSettingsPage(context, const LooksPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openThemeTokensPage() async {
    await pushSettingsPage(context, const ThemeTokensPage());
    if (!mounted) return;
    setState(() {});
  }

  /// How many tokens have been taken over, or the invitation when none have.
  ///
  /// Computed from the live overrides rather than stored, for the same reason
  /// `AppLooks.active()` is: there is nothing to keep in sync and no way for a
  /// remembered answer to go stale.
  String get _themeTokensLabel {
    final n = AppThemeController.instance.overrides.count;
    if (n == 0) return 'Colour, shape, motion — one token at a time';
    return '$n ${n == 1 ? "token" : "tokens"} changed';
  }

  Future<void> _openAppThemePage() async {
    await pushSettingsPage(context, const AppThemePage());
    if (!mounted) return;
    final theme = await StorageService.getDetailTheme();
    if (!mounted) return;
    setState(() {
      _detailTheme = theme;
    });
  }

  Future<void> _openParentsGuideStylePage() async {
    await pushSettingsPage(context, const ParentsGuideStylePage());
    if (!mounted) return;
    final style = await StorageService.getParentsGuideStyle();
    if (!mounted) return;
    setState(() {
      _parentsGuideStyle = style;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the text brightness picker.
  Future<void> _openTextBrightnessPage() async {
    await pushSettingsPage(context, const TextBrightnessPage());
    if (!mounted) return;
    final value = await StorageService.getTextBrightness();
    if (!mounted) return;
    setState(() {
      _textBrightness = value;
    });
  }

  /// Same contract as [_openTvHomeStyle], for the launch ident picker.
  Future<void> _openLaunchAnimationPage() async {
    await pushSettingsPage(context, const LaunchAnimationPage());
    if (!mounted) return;
    final value = await StorageService.getLaunchAnimation();
    if (!mounted) return;
    setState(() {
      _launchAnimation = value;
    });
  }

  /// The Appearance rows quote live pref labels, but three of those prefs
  /// also have feature-local editors (the Home Screen page's layout row, the
  /// IPTV page's Appearance/Player guide sections). Re-read JUST those after
  /// any route that can reach them, so the captions never go stale. Never
  /// the full [_loadSummaries] — this is three pref reads, no network.
  Future<void> _reloadAppearanceSummaries() async {
    final tvHomeStyle = await StorageService.getTvHomeStyle();
    final iptvStyle = await StorageService.getIptvStyle();
    final playerGuideStyle = await StorageService.getIptvPlayerGuideStyle();
    final playLoaderStyle = await StorageService.getPlayLoaderStyle();
    final tvPlayerControlsStyle =
        await StorageService.getTvPlayerControlsStyle();
    final debrifyTvStyle = await StorageService.getDebrifyTvStyle();
    if (!mounted) return;
    setState(() {
      _tvHomeStyle = tvHomeStyle;
      _iptvStyle = iptvStyle;
      _playerGuideStyle = playerGuideStyle;
      _playLoaderStyle = playLoaderStyle;
      _tvPlayerControlsStyle = tvPlayerControlsStyle;
      _debrifyTvStyle = debrifyTvStyle;
    });
  }

  Future<void> _startAndroidUpdateDownload(AppRelease release) async {
    if (kIsWeb) {
      await _openReleasesPage(release.htmlUrl);
      return;
    }
    if (!Platform.isAndroid) {
      await _openReleasesPage(release.htmlUrl);
      return;
    }
    if (_updateDownloadTaskId != null) {
      _showSnack('An update download is already running.');
      return;
    }
    final asset = release.androidApkAsset;
    if (asset == null) {
      _showSnack('No Android APK is attached to this release yet.');
      await _openReleasesPage(release.htmlUrl);
      return;
    }
    final hasPermission = await _ensureInstallPermission();
    if (!hasPermission) return;

    if (mounted) {
      setState(() {
        _updateSubtitle = 'Downloading ${release.versionLabel}...';
      });
    }

    String? taskId;
    const mime = 'application/vnd.android.package-archive';
    try {
      taskId = await AndroidNativeDownloader.startUpdate(
        url: asset.downloadUrl.toString(),
        fileName: asset.name.isNotEmpty
            ? asset.name
            : 'Debrify-${release.versionLabel}.apk',
        subDir: 'Debrify/Updates',
        mimeType: mime,
      );
    } catch (_) {
      taskId = null;
    }

    if (taskId == null) {
      _showSnack(
        'Could not start the update download. Please try again later.',
      );
      if (mounted) {
        setState(() {
          _updateSubtitle = 'Download failed to start';
        });
      }
      return;
    }

    _updateDownloadTaskId = taskId;
    _updateDownloadSub?.cancel();
    _updateDownloadSub = AndroidNativeDownloader.events.listen((event) async {
      final String eventTaskId = (event['taskId'] ?? '').toString();
      if (eventTaskId != _updateDownloadTaskId) return;
      final type = event['type']?.toString();
      if (type == 'complete') {
        final contentUri = (event['contentUri'] ?? '').toString();
        final eventMime = (event['mimeType'] ?? '').toString().isNotEmpty
            ? (event['mimeType'] ?? '').toString()
            : mime;
        try {
          _showSnack('Update downloaded. Opening installer...');
          if (contentUri.isNotEmpty) {
            final ok = await AndroidNativeDownloader.openContentUri(
              contentUri,
              eventMime,
            );
            if (!ok) {
              _showSnack('Installer was opened from Downloads instead.');
            }
          }
        } catch (_) {
          _showSnack(
            'Could not launch the installer. Check your Downloads app.',
          );
        } finally {
          _clearUpdateDownloadListener();
          if (mounted) {
            setState(() {
              _updateSubtitle = 'Installer ready for ${release.versionLabel}';
            });
          }
        }
      } else if (type == 'error' || type == 'canceled') {
        _showSnack('Update download did not finish. Please try again.');
        _clearUpdateDownloadListener();
        if (mounted) {
          setState(() {
            _updateSubtitle = 'Download failed';
          });
        }
      }
    });

    _showSnack(
      'Downloading the update in the background. Check notifications for progress.',
    );
  }

  Future<bool> _ensureInstallPermission() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    final currentStatus = await Permission.requestInstallPackages.status;
    if (currentStatus.isGranted) return true;
    final result = await Permission.requestInstallPackages.request();
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied || result.isRestricted) {
      _showSnack('Allow Debrify to install apps from your settings.');
      unawaited(openAppSettings());
    } else {
      _showSnack('Permission required to install the downloaded update.');
    }
    return false;
  }

  Future<void> _openReleasesPage(Uri url) async {
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) {
      _showSnack('Unable to open the releases page right now.');
    }
  }

  void _clearUpdateDownloadListener() {
    _updateDownloadSub?.cancel();
    _updateDownloadSub = null;
    _updateDownloadTaskId = null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

const List<SettingsCategoryDefinition> _kAdaptiveSettingsCategories = [
  SettingsCategoryDefinition(
    icon: Icons.link_rounded,
    label: 'Connections',
    subtitle: 'Debrid, cloud, IPTV & more',
    eyebrow: 'Connections',
    title: 'Services, all in one place.',
    description:
        'See what is ready, what needs attention, and where playback will go '
        'before opening a provider.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.sync_rounded,
    label: 'Trackers',
    subtitle: 'Trakt & Simkl watch history',
    eyebrow: 'Trackers',
    title: 'Keep every watch in sync.',
    description:
        'Choose how tracking works, then connect each watch-history service '
        'without digging through account screens.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.home_rounded,
    label: 'Home & Display',
    subtitle: 'Rows, artwork & navigation',
    eyebrow: 'Home & Display',
    title: 'Shape the room you come home to.',
    description:
        'Arrange the home screen and choose the navigation that fits this '
        'device.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.auto_awesome_rounded,
    label: 'Appearance',
    subtitle: 'Look, text, motion & layouts',
    eyebrow: 'Appearance',
    title: 'Make the interface feel like yours.',
    description:
        'A Look sets the room. Individual controls below let you adjust only '
        'what matters.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.play_circle_outline_rounded,
    label: 'Playback',
    subtitle: 'Player, subtitles & audio',
    eyebrow: 'Playback',
    title: 'Playback without surprises.',
    description:
        'Choose how videos start, what plays them, and the behavior shared by '
        'movies and episodes.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.search_rounded,
    label: 'Search',
    subtitle: 'Engines, filters & providers',
    eyebrow: 'Search',
    title: 'Find the right source faster.',
    description:
        'Search engines, default filters, and provider routing form one clear '
        'pipeline.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.explore_rounded,
    label: 'Discover',
    subtitle: 'Source & poster cards',
    eyebrow: 'Discover',
    title: 'Open where you want to browse.',
    description:
        'Remember the last source you used or choose one source to show every '
        'time Discover opens.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.live_tv_rounded,
    label: 'Live TV & DVR',
    subtitle: 'Channels, guide & recordings',
    eyebrow: 'Live TV & DVR',
    title: 'Live television, organized.',
    description:
        'Manage channel sources, recordings, and the guide from one focused '
        'area.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.devices_rounded,
    label: 'Devices',
    subtitle: 'Remote & setup transfer',
    eyebrow: 'Devices',
    title: 'Let your devices work together.',
    description:
        'Control another screen or move this setup without re-entering every '
        'service.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.switch_account_rounded,
    label: 'Profiles',
    subtitle: 'Who can use this device',
    eyebrow: 'Profiles',
    title: 'One device, many viewers.',
    description:
        'Switch between people, add someone new, and shape what each '
        'profile can reach.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.sync_alt_rounded,
    label: 'Sync and backup',
    subtitle: 'Sync across devices and save backups',
    eyebrow: 'Sync and backup',
    title: 'Keep your devices in sync.',
    description:
        'Connect your WebDAV account to sync profiles, settings and watch '
        'progress, or save a separate backup.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.storage_rounded,
    label: 'Data & Backup',
    subtitle: 'Downloads, backup & restore',
    eyebrow: 'Data & Backup',
    title: 'Your data, under your control.',
    description:
        'Downloads, playback state, and portable backups are separated into '
        'clear actions.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.info_outline_rounded,
    label: 'About',
    subtitle: 'Updates, version & community',
    eyebrow: 'About',
    title: 'Debrify, up to date.',
    description:
        'Version, release checks, and the places where the community meets.',
  ),
  SettingsCategoryDefinition(
    icon: Icons.warning_amber_rounded,
    label: 'Danger Zone',
    subtitle: 'Reset Debrify',
    eyebrow: 'Danger Zone',
    title: 'Start over, deliberately.',
    description:
        'Destructive actions stay isolated and explain exactly what they '
        'remove.',
    destructive: true,
  ),
];

class _SettingsLayout extends StatelessWidget {
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
  final Future<void> Function() onOpenExternalPlayerSettings;
  final VoidCallback onOpenRemoteControl;
  final bool showSwitchProfile;
  final Future<void> Function() onSwitchProfile;
  final Future<void> Function() onAddProfile;
  final Future<void> Function() onEditProfile;
  final Future<void> Function() onOpenNavigationSettings;
  final bool isAndroidTv;
  final Future<void> Function() onClearDownloads;
  final Future<void> Function() onClearPlayback;
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

  const _SettingsLayout({
    required this.connections,
    required this.onOpenSearch,
    required this.onOpenTorrentSettings,
    required this.onOpenFilterSettings,
    required this.onOpenProviderSettings,
    required this.onOpenQuickPlaySettings,
    required this.onOpenDiscoverSettings,
    required this.onOpenDebrifyTvSettings,
    required this.onOpenPikPakSettings,
    required this.onOpenHomePageSettings,
    required this.onOpenExternalPlayerSettings,
    required this.onOpenRemoteControl,
    required this.showSwitchProfile,
    required this.onSwitchProfile,
    required this.onAddProfile,
    required this.onEditProfile,
    required this.onOpenNavigationSettings,
    required this.isAndroidTv,
    required this.onClearDownloads,
    required this.onClearPlayback,
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

  List<ConnectionInfo> get _providerConnections => [
    connections.realDebrid,
    connections.torbox,
    connections.premiumize,
    connections.allDebrid,
    connections.pikpak,
    connections.webDav,
    connections.indexerManagers,
    connections.iptv,
  ];

  List<ConnectionInfo> get _trackerServices => [
    connections.trakt,
    connections.simkl,
    if (connections.mdblist != null) connections.mdblist!,
  ];

  Widget _buildSpotlight(BuildContext context) {
    final attention = _providerConnections.where(
      settingsConnectionNeedsAttention,
    );
    final attentionCount = attention.length;
    final readyCount = _providerConnections
        .where(settingsConnectionIsReady)
        .length;
    final firstAttention = attention.isEmpty ? null : attention.first;
    final summaryTone = attentionCount == 0
        ? SettingsSummaryTone.good
        : SettingsSummaryTone.attention;
    final summaryTitle = attentionCount > 0
        ? '$attentionCount connection${attentionCount == 1 ? '' : 's'} need attention.'
        : readyCount > 0
        ? 'Everything connected looks ready.'
        : 'Connect a playback service.';
    final summarySubtitle = attentionCount > 0
        ? '${firstAttention!.title} reports ${firstAttention.status.toLowerCase()}. '
              'Review it before your next playback.'
        : readyCount > 0
        ? '$readyCount services are configured on this device.'
        : 'Add a debrid, cloud, or IPTV service to get started.';
    final summaryTarget = firstAttention ?? _providerConnections.first;
    return SettingsSpotlightShell(
      categories: _kAdaptiveSettingsCategories,
      onOpenSearch: onOpenSearch,
      compactSummary: SettingsSpotlightSummaryCard(
        eyebrow: attentionCount > 0 ? 'Connection check' : 'Service health',
        title: summaryTitle,
        subtitle: summarySubtitle,
        actionLabel: attentionCount > 0
            ? 'Review ${summaryTarget.title}'
            : readyCount > 0
            ? 'Manage connections'
            : 'Connect a service',
        tone: summaryTone,
        onTap: () => unawaited(summaryTarget.onTap()),
      ),
      categoryBuilder: _buildSpotlightCategory,
    );
  }

  Widget _buildConnectionGrid(
    BuildContext context,
    List<ConnectionInfo> items, {
    bool singleFullWidth = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns =
            constraints.maxWidth >= 680 &&
            !(singleFullWidth && items.length == 1);
        final width = twoColumns
            ? (constraints.maxWidth - 10) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final info in items)
              SizedBox(
                width: width,
                child: ConnectionCard(info: info, isLeftColumn: false),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSpotlightCategory(BuildContext context, int category) {
    final t = AppThemeScope.of(context).settings;
    switch (category) {
      case 0:
        return _buildConnectionGrid(context, _providerConnections);
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SettingsSectionLabel('Tracking'),
            _buildConnectionGrid(context, [
              connections.tracking,
            ], singleFullWidth: true),
            const SizedBox(height: 22),
            const SettingsSectionLabel('Tracker services'),
            _buildConnectionGrid(context, _trackerServices),
          ],
        );
      case 2:
        return SettingsSection(
          title: '',
          children: [
            SettingsTile.spec(
              SettingsRows.homePage,
              onTap: onOpenHomePageSettings,
            ),
            SettingsTile.spec(
              SettingsRows.navigationStyle,
              subtitle: phoneNavStyleLabel,
              onTap: onOpenNavigationSettings,
            ),
            SettingsTile.spec(
              SettingsRows.desktopSidebarStyle,
              subtitle: desktopSidebarStyleLabel,
              onTap: onOpenDesktopSidebarStyle,
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsLookHero(
              label: AppLooks.active()?.label ?? 'Custom',
              subtitle: 'Full-bleed art, borderless focus, and ambient detail.',
              onTap: onOpenLooks,
            ),
            const SizedBox(height: 18),
            SettingsSection(
              title: 'Presets',
              blurb:
                  'One pick sets the theme, layouts, and launch animation '
                  'together.',
              children: [
                SettingsTile.spec(
                  SettingsRows.themeTokens,
                  subtitle: themeTokensLabel,
                  onTap: onOpenThemeTokens,
                ),
              ],
            ),
            const SizedBox(height: 18),
            SettingsSection(
              title: 'Theme',
              blurb: 'Colour, focus, and motion. Applies everywhere.',
              children: [
                SettingsTile.spec(
                  SettingsRows.textBrightness,
                  subtitle: textBrightnessLabel,
                  onTap: onOpenTextBrightness,
                ),
                SettingsTile.spec(
                  SettingsRows.launchAnimation,
                  subtitle: launchAnimationLabel,
                  onTap: onOpenLaunchAnimation,
                ),
              ],
            ),
            const SizedBox(height: 18),
            SettingsSection(
              title: 'Screen layouts',
              blurb: 'Where things sit. Each screen is chosen separately.',
              children: [
                SettingsTile.spec(
                  SettingsRows.detailPageStyle,
                  subtitle: detailPageStyleLabel,
                  onTap: onOpenDetailPageStyle,
                ),
                if (showIptvAppearance)
                  SettingsTile.spec(
                    SettingsRows.iptvAppearance,
                    subtitle: iptvStyleLabel,
                    onTap: onOpenIptvStyle,
                  ),
                SettingsTile.spec(
                  SettingsRows.debrifyTvAppearance,
                  subtitle: debrifyTvStyleLabel,
                  onTap: onOpenDebrifyTvStyle,
                ),
                SettingsTile.spec(
                  SettingsRows.playerGuideStyle,
                  subtitle: playerGuideStyleLabel,
                  onTap: onOpenPlayerGuideStyle,
                ),
                SettingsTile.spec(
                  SettingsRows.playLoaderStyle,
                  subtitle: playLoaderStyleLabel,
                  onTap: onOpenPlayLoaderStyle,
                ),
                if (!PlatformUtil.isTelevision)
                  SettingsTile.spec(
                    SettingsRows.playerDock,
                    subtitle: playerDockLabel,
                    onTap: onOpenPlayerDock,
                  ),
                SettingsTile.spec(
                  SettingsRows.parentsGuideStyle,
                  subtitle: parentsGuideStyleLabel,
                  onTap: onOpenParentsGuideStyle,
                ),
                SettingsTile.spec(
                  SettingsRows.profileAppearance,
                  subtitle: profileAppearanceLabel,
                  onTap: onOpenProfileAppearance,
                ),
              ],
            ),
          ],
        );
      case 4:
        return SettingsSection(
          title: '',
          children: [
            SettingsTile.spec(
              SettingsRows.player,
              onTap: onOpenExternalPlayerSettings,
            ),
          ],
        );
      case 5:
        return SettingsSection(
          title: '',
          children: [
            SettingsTile.spec(
              SettingsRows.searchSettings,
              onTap: onOpenTorrentSettings,
            ),
            SettingsTile.spec(
              SettingsRows.filterSettings,
              onTap: onOpenFilterSettings,
            ),
            SettingsTile.spec(
              SettingsRows.providerSettings,
              onTap: onOpenProviderSettings,
            ),
            SettingsTile.spec(
              SettingsRows.quickPlay,
              onTap: onOpenQuickPlaySettings,
            ),
          ],
        );
      case 6:
        return SettingsSection(
          title: '',
          children: [
            SettingsTile.spec(
              SettingsRows.discoverDefault,
              onTap: onOpenDiscoverSettings,
            ),
          ],
        );
      case 7:
        return SettingsSection(
          title: '',
          children: [
            SettingsTile.spec(
              SettingsRows.debrifyTv,
              onTap: onOpenDebrifyTvSettings,
            ),
            SettingsTile.spec(SettingsRows.recordings, onTap: onOpenRecordings),
            SettingsTile.spec(
              SettingsRows.iptvPlaylists,
              onTap: onOpenIptvSettings,
            ),
          ],
        );
      case 8:
        return SettingsSection(
          title: '',
          children: [
            SettingsTile.spec(
              SettingsRows.remote,
              onTap: () async => onOpenRemoteControl(),
            ),
          ],
        );
      case 9:
        // Profiles' own card (it used to be a tenant row under Devices). A
        // legacy-mode install keeps the card but says why it's empty rather
        // than presenting actions that would fail.
        return SettingsSection(
          title: '',
          children: [
            if (showSwitchProfile) ...[
              SettingsTile.spec(
                SettingsRows.switchProfile,
                onTap: onSwitchProfile,
              ),
              SettingsTile.spec(SettingsRows.addProfile, onTap: onAddProfile),
              SettingsTile.spec(SettingsRows.editProfile, onTap: onEditProfile),
            ] else
              SettingsTile.spec(
                SettingsRowContent(
                  icon: Icons.info_outline_rounded,
                  title: 'Profiles unavailable',
                  // First line only: the captured reason can carry a stack
                  // frame on its second line, and the row is one-line copy.
                  subtitle: ProfileBootstrap.legacyReasonSummary
                      .split('\n')
                      .first,
                ),
                onTap: () => showLegacyModeInfoDialog(context),
              ),
          ],
        );
      case 10:
        return SettingsSection(
          title: '',
          children: [
            SettingsTile.spec(
              SettingsRows.syncAndMigrate,
              onTap: onOpenSyncAndMigrate,
              trailing: const WebDavSyncPendingBadge(),
            ),
          ],
        );
      case 11:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onOpenDownloadLocation != null) ...[
              SettingsSection(
                title: 'Downloads',
                children: [
                  SettingsTile.spec(
                    SettingsRows.downloadLocation,
                    subtitle: downloadLocationSubtitle,
                    onTap: onOpenDownloadLocation!,
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
            SettingsSection(
              title: 'Maintenance',
              children: [
                SettingsTile.spec(
                  SettingsRows.clearDownloads,
                  onTap: onClearDownloads,
                ),
                SettingsTile.spec(
                  SettingsRows.clearPlayback,
                  onTap: onClearPlayback,
                ),
              ],
            ),
            const SizedBox(height: 18),
            SettingsSection(
              title: 'Backup & Restore',
              children: [
                SettingsTile.spec(
                  SettingsRows.createBackup,
                  onTap: onCreateBackup,
                ),
                SettingsTile.spec(
                  SettingsRows.restoreBackup,
                  onTap: onRestoreBackup,
                ),
              ],
            ),
            if (onExportDiagnosticLogs != null) ...[
              const SizedBox(height: 18),
              SettingsSection(
                title: 'Diagnostics',
                children: [
                  SettingsTile.spec(
                    SettingsRows.exportDiagnosticLogs,
                    onTap: onExportDiagnosticLogs!,
                  ),
                ],
              ),
            ],
          ],
        );
      case 12:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSection(
              title: 'Updates',
              children: [
                SettingsToggleTile.spec(
                  SettingsRows.autoUpdate,
                  value: autoUpdateChecksEnabled,
                  onChanged: onToggleAutoUpdateChecks,
                ),
                SettingsTile.spec(
                  SettingsRows.checkUpdates,
                  subtitle: updateSubtitle,
                  onTap: onCheckForUpdates,
                  tag: 'New',
                  trailing: checkingUpdates
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : null,
                ),
                SettingsInfoTile.spec(SettingsRows.version, value: appVersion),
              ],
            ),
            const SizedBox(height: 18),
            SettingsSection(
              title: 'Community & Support',
              children: [
                if (showSupportDonation)
                  SettingsTile(
                    icon: SettingsRows.supportDebrify.icon,
                    title: supportDonationLabel,
                    subtitle: supportDonationSubtitle,
                    onTap: onOpenSupportDonation,
                  ),
                SettingsTile.spec(
                  SettingsRows.reddit,
                  onTap: () => launchSettingsUrl(SettingsRows.reddit.url!),
                ),
                SettingsTile.spec(
                  SettingsRows.discord,
                  onTap: () => launchSettingsUrl(SettingsRows.discord.url!),
                ),
                SettingsTile.spec(
                  SettingsRows.github,
                  onTap: () => launchSettingsUrl(SettingsRows.github.url!),
                ),
              ],
            ),
          ],
        );
      case 13:
        return SettingsSection(
          title: '',
          accentColor: t.danger,
          children: [
            SettingsTile.spec(
              SettingsRows.resetDebrify,
              onTap: onDangerAction,
              destructive: true,
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    if (app.id == 'spotlight') return _buildSpotlight(context);
    final t = app.settings;
    return SettingsBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsHeader(),
                const SizedBox(height: 18),
                _SettingsSearchBar(onTap: onOpenSearch),
                const SizedBox(height: 24),
                // Connections section with cards
                connections,
                const SizedBox(height: 24),
                // ONE information architecture, shared verbatim with the TV
                // rail (_kCategories in settings_tv_layout.dart) and the
                // search index — organized by what the user is changing,
                // never by platform. Platform-only rows hide where they don't
                // apply; the section names never differ between surfaces.
                SettingsSection(
                  title: 'Home & Display',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.homePage,
                      onTap: onOpenHomePageSettings,
                    ),
                    if (isAndroidTv)
                      SettingsToggleTile.spec(
                        SettingsRows.tvKeyboard,
                        value: tvKeyboardEnabled,
                        onChanged: onToggleTvKeyboard,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                // Every look/layout pref, one tap from the root. The TV-only
                // pickers live in the TV layout's Appearance category — this
                // layout never renders on Android TV.
                SettingsSection(
                  title: 'Presets',
                  blurb:
                      'One pick that sets the theme, layouts and launch '
                      'animation together.',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.looks,
                      subtitle: AppLooks.active()?.label ?? 'Custom',
                      onTap: onOpenLooks,
                    ),
                    SettingsTile.spec(
                      SettingsRows.themeTokens,
                      subtitle: themeTokensLabel,
                      onTap: onOpenThemeTokens,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Theme',
                  blurb:
                      'Colour, focus and motion. Applies everywhere in the '
                      'app.',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.textBrightness,
                      subtitle: textBrightnessLabel,
                      onTap: onOpenTextBrightness,
                    ),
                    SettingsTile.spec(
                      SettingsRows.launchAnimation,
                      subtitle: launchAnimationLabel,
                      onTap: onOpenLaunchAnimation,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Screen layouts',
                  blurb: 'Where things sit. Each screen is chosen separately.',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.detailPageStyle,
                      subtitle: detailPageStyleLabel,
                      onTap: onOpenDetailPageStyle,
                    ),
                    if (showIptvAppearance)
                      SettingsTile.spec(
                        SettingsRows.iptvAppearance,
                        subtitle: iptvStyleLabel,
                        onTap: onOpenIptvStyle,
                      ),
                    SettingsTile.spec(
                      SettingsRows.debrifyTvAppearance,
                      subtitle: debrifyTvStyleLabel,
                      onTap: onOpenDebrifyTvStyle,
                    ),
                    SettingsTile.spec(
                      SettingsRows.playerGuideStyle,
                      subtitle: playerGuideStyleLabel,
                      onTap: onOpenPlayerGuideStyle,
                    ),
                    SettingsTile.spec(
                      SettingsRows.playLoaderStyle,
                      subtitle: playLoaderStyleLabel,
                      onTap: onOpenPlayLoaderStyle,
                    ),
                    // Televisions build TvControls, not Controls, so this
                    // pref has no consumer there. SettingsTvLayout omits the
                    // row entirely; this gate covers Apple TV, which shares
                    // the TV layout via AndroidNativeDownloader.isTelevision.
                    if (!PlatformUtil.isTelevision)
                      SettingsTile.spec(
                        SettingsRows.playerDock,
                        subtitle: playerDockLabel,
                        onTap: onOpenPlayerDock,
                      ),
                    SettingsTile.spec(
                      SettingsRows.parentsGuideStyle,
                      subtitle: parentsGuideStyleLabel,
                      onTap: onOpenParentsGuideStyle,
                    ),
                    SettingsTile.spec(
                      SettingsRows.profileAppearance,
                      subtitle: profileAppearanceLabel,
                      onTap: onOpenProfileAppearance,
                    ),
                    // Phone/small-window chrome — TVs navigate by sidebar
                    // and never read the style.
                    SettingsTile.spec(
                      SettingsRows.navigationStyle,
                      subtitle: phoneNavStyleLabel,
                      onTap: onOpenNavigationSettings,
                    ),
                    // Wide-window chrome: the desktop/tablet rail's picker
                    // (rail or pill). Phones never reach the wide layout but
                    // an iPad rotates in and out of it, so the row is not
                    // width-gated.
                    SettingsTile.spec(
                      SettingsRows.desktopSidebarStyle,
                      subtitle: desktopSidebarStyleLabel,
                      onTap: onOpenDesktopSidebarStyle,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Playback',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.player,
                      onTap: onOpenExternalPlayerSettings,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Search',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.searchSettings,
                      onTap: onOpenTorrentSettings,
                    ),
                    SettingsTile.spec(
                      SettingsRows.filterSettings,
                      onTap: onOpenFilterSettings,
                    ),
                    SettingsTile.spec(
                      SettingsRows.providerSettings,
                      onTap: onOpenProviderSettings,
                    ),
                    SettingsTile.spec(
                      SettingsRows.quickPlay,
                      onTap: onOpenQuickPlaySettings,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Discover',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.discoverDefault,
                      onTap: onOpenDiscoverSettings,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Live TV & DVR',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.debrifyTv,
                      onTap: onOpenDebrifyTvSettings,
                    ),
                    SettingsTile.spec(
                      SettingsRows.recordings,
                      onTap: onOpenRecordings,
                    ),
                    SettingsTile.spec(
                      SettingsRows.iptvPlaylists,
                      onTap: onOpenIptvSettings,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Devices',
                  children: [
                    // Remote is listed on every platform. It used to be hidden
                    // off TV and desktop on the grounds that "mobile keeps its
                    // entry in the floating menu" — but that menu is gated on
                    // width (isDesktopWide, >= 600 px), not on platform, so a
                    // tablet or a phone in landscape lost both entry points at
                    // once and could only reach Remote through settings search.
                    SettingsTile.spec(
                      SettingsRows.remote,
                      onTap: () async => onOpenRemoteControl(),
                    ),
                  ],
                ),
                // Profiles' own card (it used to be a tenant row under
                // Devices). The list layout simply hides it in legacy mode —
                // no index coupling to preserve here, unlike the category
                // switches.
                if (showSwitchProfile) ...[
                  const SizedBox(height: 24),
                  SettingsSection(
                    title: 'Profiles',
                    children: [
                      SettingsTile.spec(
                        SettingsRows.switchProfile,
                        onTap: onSwitchProfile,
                      ),
                      SettingsTile.spec(
                        SettingsRows.addProfile,
                        onTap: onAddProfile,
                      ),
                      SettingsTile.spec(
                        SettingsRows.editProfile,
                        onTap: onEditProfile,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Sync and backup',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.syncAndMigrate,
                      onTap: onOpenSyncAndMigrate,
                      trailing: const WebDavSyncPendingBadge(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Data & Backup',
                  children: [
                    if (onOpenDownloadLocation != null)
                      SettingsTile.spec(
                        SettingsRows.downloadLocation,
                        subtitle: downloadLocationSubtitle,
                        onTap: onOpenDownloadLocation!,
                      ),
                    SettingsTile.spec(
                      SettingsRows.clearDownloads,
                      onTap: onClearDownloads,
                    ),
                    SettingsTile.spec(
                      SettingsRows.clearPlayback,
                      onTap: onClearPlayback,
                    ),
                    SettingsTile.spec(
                      SettingsRows.createBackup,
                      onTap: onCreateBackup,
                    ),
                    SettingsTile.spec(
                      SettingsRows.restoreBackup,
                      onTap: onRestoreBackup,
                    ),
                    if (onExportDiagnosticLogs != null)
                      SettingsTile.spec(
                        SettingsRows.exportDiagnosticLogs,
                        onTap: onExportDiagnosticLogs!,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                // About section
                SettingsSection(
                  title: 'About',
                  children: [
                    SettingsToggleTile.spec(
                      SettingsRows.autoUpdate,
                      value: autoUpdateChecksEnabled,
                      onChanged: onToggleAutoUpdateChecks,
                    ),
                    SettingsTile.spec(
                      SettingsRows.checkUpdates,
                      subtitle: updateSubtitle,
                      onTap: onCheckForUpdates,
                      tag: 'New',
                      trailing: checkingUpdates
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : null,
                    ),
                    if (showSupportDonation)
                      SettingsTile(
                        icon: SettingsRows.supportDebrify.icon,
                        title: supportDonationLabel,
                        subtitle: supportDonationSubtitle,
                        onTap: onOpenSupportDonation,
                      ),
                    SettingsTile.spec(
                      SettingsRows.reddit,
                      onTap: () => launchSettingsUrl(SettingsRows.reddit.url!),
                    ),
                    SettingsTile.spec(
                      SettingsRows.discord,
                      onTap: () => launchSettingsUrl(SettingsRows.discord.url!),
                    ),
                    SettingsTile.spec(
                      SettingsRows.github,
                      onTap: () => launchSettingsUrl(SettingsRows.github.url!),
                    ),
                    SettingsInfoTile.spec(
                      SettingsRows.version,
                      value: appVersion,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Danger Zone LAST — destructive actions live at the end of
                // the page, isolated in their own red section on purpose.
                SettingsSection(
                  title: 'Danger Zone',
                  accentColor: t.danger.withValues(alpha: 0.85),
                  children: [
                    SettingsTile.spec(
                      SettingsRows.resetDebrify,
                      onTap: onDangerAction,
                      destructive: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable search affordance on the phone/desktop settings root. Looks like a
/// search field but opens the dedicated [SettingsSearchPage] (which owns the
/// live field) so the root layout stays a cheap StatelessWidget.
class _SettingsSearchBar extends StatefulWidget {
  final VoidCallback onTap;
  const _SettingsSearchBar({required this.onTap});

  @override
  State<_SettingsSearchBar> createState() => _SettingsSearchBarState();
}

class _SettingsSearchBarState extends State<_SettingsSearchBar> {
  final FocusNode _node = FocusNode(debugLabel: 'settingsSearchBar');
  bool _hovered = false;

  /// Live, never cached — see the note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  bool get _focused => _node.hasFocus;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final bool lit = _focused || _hovered;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        focusNode: _node,
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        onFocusChange: (_) => setState(() {}),
        onHover: (h) => setState(() => _hovered = h),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: lit ? t.panel2 : t.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? t.accent : t.line,
              width: _focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 20,
                color: lit ? t.accent2 : t.dim,
              ),
              const SizedBox(width: 12),
              Text(
                'Search settings',
                style: TextStyle(fontSize: 13.5, color: t.dim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
