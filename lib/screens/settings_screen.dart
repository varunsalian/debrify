import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/app_version_info.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../utils/app_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/webdav_item.dart';
import '../services/main_page_bridge.dart';
import '../utils/platform_util.dart';

import '../services/analytics_service.dart';
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
import 'settings/debrify_tv_settings_page.dart';
import 'settings/settings_tv_layout.dart';
import 'settings/settings_search.dart';
import 'settings/discover_layout_page.dart';
import 'settings/iptv_style_page.dart';
import 'settings/text_brightness_page.dart';
import 'settings/launch_animation_page.dart';
import '../widgets/launch/launch_ident.dart';
import 'settings/detail_page_style_page.dart';
import 'settings/app_theme_page.dart';
import 'settings/looks_page.dart';
import 'settings/detail_theme_page.dart';
import '../theme/app_theme_controller.dart';
import 'settings/parents_guide_style_page.dart';
import 'settings/player_guide_style_page.dart';
import 'settings/tv_home_style_page.dart';
import 'settings/tv_render_quality_page.dart';
import 'settings/tv_hero_artwork_quality_page.dart';
import 'settings/tv_screen_size_page.dart';
import 'settings/recordings_page.dart';
import 'settings/tv_sidebar_style_page.dart';
import 'settings/widgets/settings_widgets.dart';
import 'settings/pikpak_settings_page.dart';
import 'settings/real_debrid_settings_page.dart';
import 'settings/iptv_settings_page.dart';
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
import 'settings/trakt_settings_page.dart';
import 'settings/simkl_settings_page.dart';
import 'settings/mdblist_settings_page.dart';
import 'settings/webdav_settings_page.dart';
import 'settings/stremio_tv_settings_page.dart';
import '../widgets/remote/remote_role_picker_screen.dart';
import '../theme/app_looks.dart';
import '../theme/app_theme_scope.dart';
import '../models/tv_hero_artwork_quality.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
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
  bool _tvKeyboardEnabled = true;
  int _tvUiScalePercent = StorageService.kTvUiScaleDefault;
  TvRenderQuality _tvRenderQuality = TvRenderQuality.auto;
  TvHeroArtworkQuality _tvHeroArtworkQuality =
      TvHeroArtworkQuality.automatic;
  String _tvHomeStyle = 'canvas';
  String _discoverLayout = 'stage';
  String _tvSidebarStyle = 'ghost';
  String _iptvStyle = 'command';
  String _playerGuideStyle = 'classic';
  String _detailPageStyle = 'classic';
  String _detailTheme = 'signal';
  String _parentsGuideStyle = 'compass';
  String _phoneNavStyle = 'classic';
  String _textBrightness = 'bright';
  String _launchAnimation = 'horizon';
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
    // Phase 1: Load cached/local state instantly (no network)
    final results = await Future.wait([
      StorageService.getApiKey(),
      StorageService.getTorboxApiKey(),
      PikPakApiService.instance.isAuthenticated(),
      StorageService.getWebDavEnabled(),
      StorageService.getWebDavServers(),
      StorageService.getTraktAccessToken(),
      StorageService.getTraktTokenExpiry(),
      StorageService.getTraktUsername(),
      AppVersionInfo.get(),
      AndroidNativeDownloader.isTelevision(),
      StorageService.getUpdateAutoCheckEnabled(),
      StorageService.getIndexerManagerConfigs(),
      StorageService.getPremiumizeApiKey(),
      StorageService.getAllDebridApiKey(),
      StorageService.getSimklAccessToken(),
      StorageService.getSimklUsername(),
      StorageService.getMdblistApiKey(),
      StorageService.getMdblistUsername(),
      StorageService.getTvKeyboardEnabled(),
      StorageService.getTvUiScalePercent(),
      StorageService.getTvHomeStyle(),
      StorageService.getTvSidebarStyle(),
      StorageService.getDiscoverLayout(),
      StorageService.getIptvStyle(),
      StorageService.getIptvPlayerGuideStyle(),
      StorageService.getPhoneNavStyle(),
      StorageService.getTextBrightness(),
      StorageService.getLaunchAnimation(),
      StorageService.getDetailPageStyle(),
      StorageService.getTvRenderQuality(),
      StorageService.getDetailTheme(),
      StorageService.getParentsGuideStyle(),
      StorageService.getTvHeroArtworkQuality(),
    ]);

    if (!mounted) return;

    final rdKey = results[0] as String?;
    final torboxKey = results[1] as String?;
    final pikpakAuth = results[2] as bool;
    final webDavEnabled = results[3] as bool;
    final webDavServers = results[4] as List<WebDavConfig>;
    final traktToken = results[5] as String?;
    final traktExpiry = results[6] as int?;
    final traktUsername = results[7] as String?;
    final packageInfo = results[8] as PackageInfo;
    final isAndroidTv = results[9] as bool;
    final autoCheckEnabled = results[10] as bool;
    final indexerManagers = results[11] as List;
    final premiumizeKey = results[12] as String?;
    final allDebridKey = results[13] as String?;
    final simklToken = results[14] as String?;
    final simklUsername = results[15] as String?;
    final mdblistKey = results[16] as String?;
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

    // Set initial state from cached data
    final rdConnected = rdKey != null && rdKey.isNotEmpty;
    final torConnected = torboxKey != null && torboxKey.isNotEmpty;
    final premiumizeConnected =
        premiumizeKey != null && premiumizeKey.isNotEmpty;
    final allDebridConnected = allDebridKey != null && allDebridKey.isNotEmpty;

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

    if (traktToken != null && traktToken.isNotEmpty) {
      final traktExpired =
          traktExpiry != null &&
          DateTime.now().millisecondsSinceEpoch >= traktExpiry;
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
    if (simklToken != null && simklToken.isNotEmpty) {
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
    if (mdblistKey != null && mdblistKey.isNotEmpty) {
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

    _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    _currentVersionName = packageInfo.version;
    _isAndroidTv = isAndroidTv;
    _loading = false;
    _autoUpdateChecksEnabled = autoCheckEnabled;
    _tvKeyboardEnabled = tvKeyboardEnabled;
    _tvUiScalePercent = tvUiScalePercent;
    _tvRenderQuality = tvRenderQuality;
    _tvHomeStyle = tvHomeStyle;
    _tvSidebarStyle = tvSidebarStyle;
    _discoverLayout = discoverLayout;
    _iptvStyle = iptvStyle;
    _playerGuideStyle = playerGuideStyle;
    _phoneNavStyle = phoneNavStyle;
    _textBrightness = textBrightness;
    _launchAnimation = launchAnimation;
    _detailPageStyle = detailPageStyle;
    _detailTheme = detailTheme;
    _parentsGuideStyle = parentsGuideStyle;
    _tvHeroArtworkQuality = tvHeroArtworkQuality;

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
      child: _isAndroidTv ? _buildTvLayout() : _buildLayout(context),
    );
  }

  // Connection cards in canonical order (matches the phone grid rows).
  ConnectionInfo get _rdInfo => ConnectionInfo(
    title: 'Real Debrid',
    connected: _realDebridConnected,
    status: _realDebridStatus,
    caption: _realDebridCaption,
    onTap: _openRealDebridSettings,
  );
  ConnectionInfo get _torboxInfo => ConnectionInfo(
    title: 'Torbox',
    connected: _torboxConnected,
    status: _torboxStatus,
    caption: _torboxCaption,
    onTap: _openTorboxSettings,
  );
  ConnectionInfo get _premiumizeInfo => ConnectionInfo(
    title: 'Premiumize',
    connected: _premiumizeConnected,
    status: _premiumizeStatus,
    caption: _premiumizeCaption,
    onTap: _openPremiumizeSettings,
  );
  ConnectionInfo get _allDebridInfo => ConnectionInfo(
    title: 'AllDebrid',
    connected: _allDebridConnected,
    status: _allDebridStatus,
    caption: _allDebridCaption,
    onTap: _openAllDebridSettings,
  );
  ConnectionInfo get _pikpakInfo => ConnectionInfo(
    title: 'PikPak',
    connected: _pikpakConnected,
    status: _pikpakStatus,
    caption: _pikpakCaption,
    onTap: _openPikPakSettings,
  );
  ConnectionInfo get _webDavInfo => ConnectionInfo(
    title: 'WebDAV',
    connected: _webDavConnected,
    status: _webDavStatus,
    caption: _webDavCaption,
    onTap: _openWebDavSettings,
  );
  ConnectionInfo get _iptvInfo => ConnectionInfo(
    title: 'IPTV',
    connected: true,
    status: 'Active',
    caption: 'M3U playlist channels',
    onTap: _openIptvSettings,
  );
  ConnectionInfo get _traktInfo => ConnectionInfo(
    title: 'Trakt',
    connected: _traktConnected,
    status: _traktStatus,
    caption: _traktCaption,
    onTap: _openTraktSettings,
  );
  ConnectionInfo get _simklInfo => ConnectionInfo(
    title: 'Simkl',
    connected: _simklConnected,
    status: _simklStatus,
    caption: _simklCaption,
    onTap: _openSimklSettings,
  );
  ConnectionInfo get _mdblistInfo => ConnectionInfo(
    title: 'MDBList',
    connected: _mdblistConnected,
    status: _mdblistStatus,
    caption: _mdblistCaption,
    onTap: _openMdblistSettings,
  );
  ConnectionInfo get _indexerManagersInfo => ConnectionInfo(
    title: 'Jackett & Prowlarr',
    connected: _indexerManagersConfigured,
    status: _indexerManagersStatus,
    caption: _indexerManagersCaption,
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
      onOpenTorrentSettings: _openTorrentSettings,
      onOpenFilterSettings: _openFilterSettings,
      onOpenProviderSettings: _openProviderSettings,
      onOpenQuickPlaySettings: _openQuickPlaySettings,
      onOpenDebrifyTvSettings: _openDebrifyTvSettings,
      onClearDownloads: _clearDownloadData,
      onClearPlayback: _clearPlaybackData,
      onOpenDownloadLocation: _downloadLocationSupported
          ? _openDownloadLocationSettings
          : null,
      downloadLocationSubtitle: _downloadLocationSubtitle,
      onCreateBackup: _createBackup,
      onRestoreBackup: _restoreBackup,
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
      iptvStyleLabel: iptvStyleLabel(_iptvStyle),
      onOpenIptvStyle: _openIptvStylePage,
      playerGuideStyleLabel: playerGuideStyleLabel(_playerGuideStyle),
      onOpenPlayerGuideStyle: _openPlayerGuideStylePage,
      detailPageStyleLabel: detailPageStyleLabel(_detailPageStyle),
      onOpenDetailPageStyle: _openDetailPageStylePage,
      appThemeLabel: appThemeLabel(AppThemeController.instance.id),
      looksLabel: AppLooks.active()?.label ?? 'Custom',
      onOpenLooks: _openLooksPage,
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
      onOpenDebrifyTvSettings: _openDebrifyTvSettings,
      onOpenPikPakSettings: _openPikPakSettings,
      onOpenHomePageSettings: _openHomePageSettings,
      onOpenExternalPlayerSettings: _openExternalPlayerSettings,
      onOpenRemoteControl: _openRemoteControl,
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
      playerGuideStyleLabel: playerGuideStyleLabel(_playerGuideStyle),
      onOpenPlayerGuideStyle: _openPlayerGuideStylePage,
      detailPageStyleLabel: detailPageStyleLabel(_detailPageStyle),
      onOpenDetailPageStyle: _openDetailPageStylePage,
      appThemeLabel: appThemeLabel(AppThemeController.instance.id),
      onOpenLooks: _openLooksPage,
      onOpenAppTheme: _openAppThemePage,
      detailThemeLabel: detailThemeLabel(_detailTheme),
      onOpenDetailTheme: _openDetailThemePage,
      parentsGuideStyleLabel: parentsGuideStyleLabel(_parentsGuideStyle),
      onOpenParentsGuideStyle: _openParentsGuideStylePage,
      phoneNavStyleLabel: _phoneNavStyle == 'floating'
          ? 'Floating button'
          : 'Classic bar',
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
      keywords: keywords,
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

    return [
      // Connections
      conn(_rdInfo, const ['debrid', 'real-debrid', 'rd', 'premium']),
      conn(_torboxInfo, const ['debrid', 'premium']),
      conn(_premiumizeInfo, const ['debrid', 'premium']),
      conn(_allDebridInfo, const ['debrid', 'ad', 'premium']),
      conn(_pikpakInfo, const ['cloud', 'storage']),
      conn(_webDavInfo, const ['cloud', 'nas', 'server']),
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
      ], category: 'Trackers'),
      conn(_simklInfo, const [
        'scrobble',
        'sync',
        'watch history',
      ], category: 'Trackers'),
      if (kMdblistEnabled)
        conn(_mdblistInfo, const ['lists', 'ratings'], category: 'Trackers'),

      // General
      nav(
        SettingsRows.homePage,
        'Home & Display',
        _openHomePageSettings,
        keywords: const ['default view', 'startup', 'landing', 'tab'],
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
        keywords: const [
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
        ],
      ),
      // Ungated — every platform plays the splash. Lands on the picker.
      nav(
        SettingsRows.launchAnimation,
        'Appearance',
        _openLaunchAnimationPage,
        subtitle: launchIdentLabel(_launchAnimation),
        keywords: const [
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
          keywords: const [
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
          keywords: const [
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
          keywords: const [
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
          ],
        ),
      // Android TV only — the layout branch only exists on the TV home board.
      if (_isAndroidTv)
        nav(
          SettingsRows.tvHomeStyle,
          'Appearance',
          _openTvHomeStyle,
          subtitle: tvHomeStyleLabel(_tvHomeStyle),
          keywords: const [
            'home',
            'layout',
            'home screen',
            'canvas',
            'shelf',
            'classic',
            'rows',
            'redesign',
            'view',
            'display',
            'home & display',
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
          keywords: const [
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
          ],
        ),
      // Android TV only — the rail is TV chrome.
      if (_isAndroidTv)
        nav(
          SettingsRows.tvSidebarStyle,
          'Appearance',
          _openTvSidebarStyle,
          subtitle: tvSidebarStyleLabel(_tvSidebarStyle),
          keywords: const [
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
          keywords: const [
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
        keywords: const [
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
        ],
      ),
      // App-wide theme (experimental) — the token layer's picker.
      nav(
        SettingsRows.appTheme,
        'Appearance',
        _openAppThemePage,
        subtitle: appThemeLabel(AppThemeController.instance.id),
        keywords: const [
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
          'broadsheet',
          'experimental',
        ],
      ),
      // Ungated: the theme applies wherever an alternate layout draws.
      nav(
        SettingsRows.detailTheme,
        'Appearance',
        _openDetailThemePage,
        subtitle: detailThemeLabel(_detailTheme),
        keywords: const [
          'details',
          'detail',
          'theme',
          'colour',
          'color',
          'palette',
          'look',
          'style',
          'skin',
          'dark',
          'light',
          'noir',
          'broadsheet',
          'phosphor',
          'aurora',
          'concrete',
          'velvet',
          'blueprint',
          'broadcast',
          'sepia',
          'obsidian',
          'halo',
          'prestige',
          'deep field',
          'graphite',
          'vault',
          'spectrum',
          'verdant',
          'frost',
          'cinemascope',
          'gold',
        ],
      ),
      nav(
        SettingsRows.parentsGuideStyle,
        'Appearance',
        _openParentsGuideStylePage,
        subtitle: parentsGuideStyleLabel(_parentsGuideStyle),
        keywords: const [
          'parents',
          'parental',
          'guide',
          'advisory',
          'content rating',
          'severity',
          'compass',
          'classic',
          'family',
        ],
      ),
      // Ungated: the details page opens on every platform.
      nav(
        SettingsRows.detailPageStyle,
        'Appearance',
        _openDetailPageStylePage,
        subtitle: detailPageStyleLabel(_detailPageStyle),
        keywords: const [
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
        keywords: const [
          'external player',
          'vlc',
          'mpv',
          'mx player',
          'video player',
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
        ],
      ),
      nav(
        SettingsRows.providerSettings,
        'Search',
        _openProviderSettings,
        keywords: const ['default provider', 'add torrent', 'debrid'],
      ),
      nav(
        SettingsRows.quickPlay,
        'Search',
        _openQuickPlaySettings,
        keywords: const ['instant', 'auto play', 'one tap'],
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
        ],
        onTap: () async => MainPageBridge.switchTab?.call(
          7, // 7 = Addons (see main.dart _pages)
        ),
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
        keywords: const ['export', 'save', 'addons'],
      ),
      nav(
        SettingsRows.restoreBackup,
        'Data & Backup',
        _restoreBackup,
        keywords: const ['import', 'load'],
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
      'Engines': Icons.search_rounded,
      'Filters': Icons.filter_list_rounded,
      'Default Provider': Icons.cloud_sync_rounded,
      'Quick Play': Icons.bolt_rounded,
      'Home Screen': Icons.home_rounded,
      'Playback': Icons.open_in_new_rounded,
      'Debrify TV': Icons.live_tv_rounded,
      'Stremio TV': Icons.smart_display_rounded,
      'IPTV Playlists': Icons.playlist_play_rounded,
      'Recordings': Icons.fiber_dvr_rounded,
      'Trakt': Icons.sync_rounded,
      'Simkl': Icons.sync_rounded,
      'MDBList': Icons.list_alt_rounded,
      'Remote': Icons.phonelink_rounded,
    };
    final pageOpeners = <String, Future<void> Function()>{
      'Torbox': _openTorboxSettings,
      'Premiumize': _openPremiumizeSettings,
      'Real Debrid': _openRealDebridSettings,
      'AllDebrid': _openAllDebridSettings,
      'PikPak': _openPikPakSettings,
      'Engines': _openTorrentSettings,
      'Filters': _openFilterSettings,
      'Default Provider': _openProviderSettings,
      'Quick Play': _openQuickPlaySettings,
      'Home Screen': _openHomePageSettings,
      'Playback': _openExternalPlayerSettings,
      'Debrify TV': _openDebrifyTvSettings,
      'Stremio TV': _openStremioTvSettings,
      'IPTV Playlists': _openIptvSettings,
      'Recordings': _openRecordings,
      'Trakt': _openTraktSettings,
      'Simkl': _openSimklSettings,
      'MDBList': _openMdblistSettings,
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
        const ['after adding', 'post torrent', 'play', 'download', 'open'],
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
        const ['after adding', 'post torrent', 'play', 'download', 'open'],
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
        const ['after adding', 'post torrent', 'play', 'download', 'open'],
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
        const ['after adding', 'post torrent', 'play', 'download'],
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
        const ['after adding', 'post torrent', 'play', 'download', 'open'],
      ),
      leaf(
        'PikPak',
        'Restrict Access to Folder',
        'Limit PikPak access to a single folder',
        const ['restrict', 'folder', 'access', 'security'],
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
          'brrip',
          'hdrip',
          'cam',
          'dvdrip',
        ],
      ),
      leaf(
        'Filters',
        'Language filter',
        'Default audio-language filter',
        const ['language', 'audio', 'english', 'hindi', 'multi-audio'],
      ),
      leaf('Filters', 'Size filter', 'Default file/pack size filter', const [
        'size',
        'gb',
        'mb',
        'file size',
      ]),
      leaf(
        'Filters',
        'Apply filters to Quick Play',
        'Quick Play prefers filtered sources',
        const ['quick play', 'apply filters', 'honor', 'sources'],
      ),
      leaf(
        'Default Provider',
        'Default Torrent Provider',
        'Which service torrents are added to',
        const ['default provider', 'ask every time', 'torbox', 'real-debrid'],
      ),

      // Quick Play
      leaf(
        'Quick Play',
        'Quick Play Timeout',
        'Max wait for search before playback',
        const ['timeout', 'wait', 'seconds'],
      ),
      leaf(
        'Quick Play',
        'Sources Timeout',
        'Max wait per Stremio addon',
        const ['sources', 'timeout', 'stremio', 'addon', 'seconds'],
      ),
      leaf(
        'Quick Play',
        'Prefer and pin series packs',
        'Search packs first and pin the source',
        const ['series', 'packs', 'pin', 'season pack', 'auto-pin'],
      ),
      leaf(
        'Quick Play',
        'Cache Fallback',
        'What to do when a torrent is not cached',
        const [
          'cache',
          'not cached',
          'fallback',
          'try multiple',
          'retry',
          'max torrents',
        ],
      ),

      // Home Page
      leaf(
        'Home Screen',
        'Home Rows',
        'Choose which rows appear on Home',
        const ['home rows', 'rows', 'catalogs', 'customize'],
      ),
      leaf(
        'Home Screen',
        'Continue Watching',
        'Show recently watched on Home',
        const ['continue watching', 'recently watched', 'history'],
      ),
      leaf(
        'Home Screen',
        'Hide Provider Cards',
        'Hide debrid status cards on Home',
        const ['hide', 'provider cards', 'debrid', 'status'],
      ),
      leaf(
        'Home Screen',
        'Home trailer & sound',
        'Ambient trailer playback and volume',
        const ['trailer', 'spotlight', 'hero', 'sound', 'volume', 'autoplay'],
      ),
      // Not on TV: TV has separate Home and Search tabs, so the page hides the
      // selector there (home_page_settings_page's !isAndroidTvCached block).
      if (!_isAndroidTv)
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
      // Exactly ONE ambient-trailer surface is offered per platform (see
      // home_page_settings_page): the Home spotlight on TV, the detail-page
      // backdrop everywhere else. Index each where its row actually exists.
      if (!_isAndroidTv)
        leaf(
          'Home Screen',
          'Trailer on Detail Page',
          'Play a trailer behind the movie/series detail page',
          const ['trailer', 'detail page', 'preview', 'backdrop', 'autoplay'],
        ),
      if (_isAndroidTv)
        leaf(
          'Home Screen',
          'Trailer on Home Spotlight',
          'Play a trailer in the Home and Discover hero',
          const ['trailer', 'spotlight', 'hero', 'ambient', 'autoplay'],
        ),
      // TV only: the native hardware-plane renderer for those trailers.
      if (_isAndroidTv)
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

      // Player Settings
      leaf('Playback', 'Default Player', 'Which player plays videos', const [
        'default player',
        'debrify player',
        'external',
        'deovr',
      ]),
      leaf(
        'Playback',
        'Default Subtitle language',
        'Preferred subtitle language',
        const ['subtitle', 'subtitles', 'language', 'captions'],
      ),
      leaf(
        'Playback',
        'Default Audio language',
        'Preferred audio language / track',
        const ['audio', 'language', 'track', 'dub'],
      ),
      leaf(
        'Playback',
        'Subtitle Appearance',
        'Subtitle size, style, color, background & font',
        const [
          'subtitle',
          'size',
          'style',
          'color',
          'background',
          'font',
          'bold',
          'outline',
          'captions',
        ],
      ),
      leaf(
        'Playback',
        'Default Aspect Ratio',
        'Default video aspect / zoom',
        const ['aspect', 'ratio', 'zoom', 'fit', 'fill'],
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
        'Allow system audio effects',
        'Let equalizer apps process audio (Android)',
        const ['audio effects', 'equalizer', 'wavelet', 'dolby'],
      ),
      if (_isAndroid && !PlatformUtil.isAndroidTvCached)
        leaf(
          'Playback',
          'Video renderer',
          'Choose the Android phone/tablet video output path',
          const [
            'renderer',
            'mediacodec',
            'direct surface',
            'battery',
            'performance',
            'hardware decoding',
          ],
        ),
      if (_isAndroid && PlatformUtil.isAndroidTvCached)
        leaf(
          'Playback',
          'Auto-sync addon subtitles',
          'Align downloaded subtitles to the audio automatically',
          const ['subtitle', 'sync', 'auto', 'align', 'timing', 'offset'],
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
      leaf(
        'Playback',
        'Preferred external player',
        'Choose the external player app',
        const ['external', 'vlc', 'mpv', 'mx player', 'custom command'],
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
          ],
        ),
      leaf(
        'Playback',
        'Import Custom Font',
        'Add your own TTF/OTF font for subtitles',
        const ['font', 'ttf', 'otf', 'import font', 'custom font', 'subtitle'],
      ),
      // Android only: the page disables the DeoVR mode off Android and builds
      // its format controls under `Platform.isAndroid`.
      if (_isAndroid)
        leaf(
          'Playback',
          'VR / DeoVR format',
          'Screen type, stereo mode and format detection for DeoVR',
          const [
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
          ],
        ),

      // Debrify TV
      leaf(
        'Debrify TV',
        'Channel result limits',
        'Per-engine channel size & result caps',
        const ['limits', 'result limit', 'channel max', 'engines', 'nsfw'],
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
        'How often the channel changes (movies and series)',
        const ['rotation', 'interval', 'minutes', 'change', 'shuffle'],
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
        const ['debrid', 'provider', 'real-debrid', 'torbox', 'pikpak'],
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
        ],
        onTap: _openIptvAddSource,
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
        ],
      ),
      leaf(
        'IPTV Playlists',
        'Default playlist',
        'Which source loads when you open IPTV',
        const ['default', 'playlist', 'source', 'opens', 'preferred'],
      ),
      leaf(
        'IPTV Playlists',
        'Refresh playlist',
        'Re-fetch channels and rebuild the catalog',
        const [
          'refresh',
          'reload',
          'update',
          'rebuild',
          'catalog',
          're-fetch',
          'missing channels',
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

      // Trackers — the pages behind the connection cards.
      leaf(
        'Trakt',
        'Sync Catalog Items',
        'Sync your Trakt lists and watch history into catalogs',
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
        'Simkl',
        'Sync Catalog Items',
        'Sync your Simkl lists and watch history into catalogs',
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
      if (kMdblistEnabled)
        leaf(
          'MDBList',
          'MDBList API Key',
          'Connect MDBList and browse your lists',
          const ['api key', 'lists', 'liked', 'supporter', 'usage'],
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
        ],
      ),
    ];
  }

  Future<void> _openTorrentSettings() async {
    await pushSettingsPage(context, const TorrentSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openIndexerManagersSettings() async {
    await pushSettingsPage(context, const IndexerManagersSettingsPage());
    if (!mounted) return;

    final configs = await StorageService.getIndexerManagerConfigs();
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
    await pushSettingsPage(context, const WebDavSettingsPage());
    if (!mounted) return;
    await _loadSummaries();
  }

  Future<void> _openTraktSettings() async {
    await pushSettingsPage(context, const TraktSettingsPage());
    if (!mounted) return;
    await _loadSummaries();
  }

  Future<void> _openSimklSettings() async {
    await pushSettingsPage(context, const SimklSettingsPage());
    if (!mounted) return;
    await _loadSummaries();
  }

  Future<void> _openMdblistSettings() async {
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
    await pushSettingsPage(context, const IptvSettingsPage());
    if (!mounted) return;
    // IPTV settings hosts its own Appearance/Player guide sections — keep
    // the Appearance row captions honest.
    await _reloadAppearanceSummaries();
  }

  /// IPTV settings landing on the add-source form — what a search for "add
  /// playlist" is actually after. Without the flag the wide (TV/desktop)
  /// layout opens its source rail instead, and the form is another hop away.
  Future<void> _openIptvAddSource() async {
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
    await pushSettingsPage(context, const RecordingsPage());
  }

  Future<void> _openHomePageSettings() async {
    await pushSettingsPage(context, const HomePageSettingsPage());
    if (!mounted) return;
    // The Home Screen page hosts its own TV home layout row — keep the
    // Appearance row caption honest.
    await _reloadAppearanceSummaries();
  }

  Future<void> _openExternalPlayerSettings() async {
    await pushSettingsPage(context, const ExternalPlayerSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openRemoteControl() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RemoteRolePickerScreen()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openFilterSettings() async {
    await pushSettingsPage(context, const FilterSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openProviderSettings() async {
    await pushSettingsPage(context, const ProviderSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openQuickPlaySettings() async {
    await pushSettingsPage(context, const QuickPlaySettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openRealDebridSettings() async {
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

  Future<void> _createBackup() async {
    final app = AppThemeScope.of(context);
    // Build the payload first so we can warn if it's empty.
    final Map<String, dynamic> payload;
    try {
      payload = await BackupRestoreService.buildBackup();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to build backup: $e')));
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
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The backup will include:'),
            const SizedBox(height: 8),
            ..._backupSummaryLines(summary).map((line) => Text('• $line')),
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
            const SizedBox(height: 12),
            const Text(
              'Credentials are stored in plain text. Keep this file private '
              'and treat it like a password.',
              style: TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
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
            child: const Text('Save backup'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final jsonContent = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = Uint8List.fromList(utf8.encode(jsonContent));
    final ts = DateTime.now();
    final fileName =
        'debrify-backup-${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}-${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}.json';

    try {
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Debrify backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );

      if (savedPath == null) {
        // User cancelled.
        return;
      }

      // On some platforms, saveFile returns the chosen path but does not
      // write the bytes itself — write defensively if the file is missing
      // or empty.
      try {
        final file = File(savedPath);
        if (!await file.exists() || (await file.length()) == 0) {
          await file.writeAsBytes(bytes, flush: true);
        }
      } catch (_) {
        // saveFile already handled writing on this platform.
      }

      if (!mounted) return;
      // On Android, savedPath may be a content:// URI from the Storage
      // Access Framework — show it raw so the user has at least a
      // breadcrumb of where the backup went.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup saved to $savedPath'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      // Fallback: write to the app's documents directory so the user is
      // never left without a copy when saveFile is unavailable (some TV
      // platforms lack a system save dialog).
      try {
        final dir = await AppStorage.documents();
        final fallbackPath = '${dir.path}/$fileName';
        await File(fallbackPath).writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup saved to $fallbackPath'),
            duration: const Duration(seconds: 5),
          ),
        );
      } catch (e2) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save backup: $e2')));
      }
    }
  }

  Future<void> _restoreBackup() async {
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
        withData: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open file picker: $e')));
      return;
    }

    if (pick == null || pick.files.isEmpty) return;
    final file = pick.files.first;

    // FileType.any lets the user pick anything and withData buffers it into RAM;
    // reject an implausibly large pick before reading so a stray huge file can't OOM.
    if (file.size > 20 * 1024 * 1024) {
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
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        throw Exception('Could not read backup file contents');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to read backup file: $e')));
      return;
    }

    final Map<String, dynamic> payload;
    try {
      payload = BackupRestoreService.parse(content);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invalid backup: ${e.message}')));
      return;
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
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
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
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Debrify?'),
        content: const Text(
          'This removes saved connections, playback history, download queue, and onboarding completion. Files already saved to disk remain untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset app'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

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
    await StorageService.clearAllPlaybackData();
    await StorageService.clearContinueWatching();
    await StorageService.clearPlaylist();
    await StorageService.clearAllPlaylistMetadata();
    await StorageService.clearTorrentSearchHistory();
    await StorageService.clearAllStartupSettings();
    await StorageService.clearAllHomePageSettings();
    await StorageService.clearAllIntegrationStates();
    await StorageService.clearDebrifyTvProviderAndLegacy();
    await StorageService.clearAllFilterSettings();
    await StorageService.clearAllTorrentEngineSettings();
    await StorageService.clearAllPostTorrentActions();
    await StorageService.clearAllDebrifyTvSettings();
    await DebrifyTvRepository.instance.clearAll();
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
    await pushSettingsPage(
      context,
      const TvHeroArtworkQualityPage(),
    );
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

  /// App-wide theme picker. Also refreshes the Details Theme subtitle: picking
  /// a real app theme write-through-mirrors it into `detail_theme`.
  /// Appearance → Looks. Re-reads nothing on return: the row's subtitle is
  /// COMPUTED from the live prefs (`AppLooks.active()`), so one setState is
  /// the whole refresh — there is no stored "current Look" that could drift.
  Future<void> _openLooksPage() async {
    await pushSettingsPage(context, const LooksPage());
    if (!mounted) return;
    setState(() {});
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
    if (!mounted) return;
    setState(() {
      _tvHomeStyle = tvHomeStyle;
      _iptvStyle = iptvStyle;
      _playerGuideStyle = playerGuideStyle;
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

class _SettingsLayout extends StatelessWidget {
  final ConnectionsSummary connections;
  final VoidCallback onOpenSearch;
  final Future<void> Function() onOpenTorrentSettings;
  final Future<void> Function() onOpenFilterSettings;
  final Future<void> Function() onOpenProviderSettings;
  final Future<void> Function() onOpenQuickPlaySettings;
  final Future<void> Function() onOpenDebrifyTvSettings;
  final Future<void> Function() onOpenPikPakSettings;
  final Future<void> Function() onOpenHomePageSettings;
  final Future<void> Function() onOpenExternalPlayerSettings;
  final VoidCallback onOpenRemoteControl;
  final Future<void> Function() onOpenNavigationSettings;
  final bool isAndroidTv;
  final Future<void> Function() onClearDownloads;
  final Future<void> Function() onClearPlayback;
  // Android-only custom download folder (SAF); null hides the row.
  final Future<void> Function()? onOpenDownloadLocation;
  final String downloadLocationSubtitle;
  final Future<void> Function() onCreateBackup;
  final Future<void> Function() onRestoreBackup;
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
  final String textBrightnessLabel;
  final Future<void> Function() onOpenTextBrightness;
  final String launchAnimationLabel;
  final Future<void> Function() onOpenLaunchAnimation;
  final String iptvStyleLabel;
  final Future<void> Function() onOpenIptvStyle;
  final String playerGuideStyleLabel;
  final Future<void> Function() onOpenPlayerGuideStyle;
  final String detailPageStyleLabel;
  final Future<void> Function() onOpenDetailPageStyle;
  final String appThemeLabel;
  final Future<void> Function() onOpenLooks;
  final Future<void> Function() onOpenAppTheme;
  final String detailThemeLabel;
  final Future<void> Function() onOpenDetailTheme;
  final String parentsGuideStyleLabel;
  final Future<void> Function() onOpenParentsGuideStyle;
  final String phoneNavStyleLabel;

  const _SettingsLayout({
    required this.connections,
    required this.onOpenSearch,
    required this.onOpenTorrentSettings,
    required this.onOpenFilterSettings,
    required this.onOpenProviderSettings,
    required this.onOpenQuickPlaySettings,
    required this.onOpenDebrifyTvSettings,
    required this.onOpenPikPakSettings,
    required this.onOpenHomePageSettings,
    required this.onOpenExternalPlayerSettings,
    required this.onOpenRemoteControl,
    required this.onOpenNavigationSettings,
    required this.isAndroidTv,
    required this.onClearDownloads,
    required this.onClearPlayback,
    this.onOpenDownloadLocation,
    this.downloadLocationSubtitle = '',
    required this.onCreateBackup,
    required this.onRestoreBackup,
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
    required this.textBrightnessLabel,
    required this.onOpenTextBrightness,
    required this.launchAnimationLabel,
    required this.onOpenLaunchAnimation,
    required this.iptvStyleLabel,
    required this.onOpenIptvStyle,
    required this.playerGuideStyleLabel,
    required this.onOpenPlayerGuideStyle,
    required this.detailPageStyleLabel,
    required this.onOpenDetailPageStyle,
    required this.appThemeLabel,
    required this.onOpenLooks,
    required this.onOpenAppTheme,
    required this.detailThemeLabel,
    required this.onOpenDetailTheme,
    required this.parentsGuideStyleLabel,
    required this.onOpenParentsGuideStyle,
    required this.phoneNavStyleLabel,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
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
                  title: 'Appearance',
                  children: [
                    // Looks FIRST: it is the entry point every picker below is
                    // an alternative to. Nobody assembles a coherent look out
                    // of fourteen dropdowns, so the one-pick answer goes at
                    // the top and the dropdowns stay for people who want them.
                    SettingsTile.spec(
                      SettingsRows.looks,
                      subtitle: AppLooks.active()?.label ?? 'Custom',
                      onTap: onOpenLooks,
                    ),
                    // App-wide next, then the feature looks.
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
                    if (showIptvAppearance)
                      SettingsTile.spec(
                        SettingsRows.iptvAppearance,
                        subtitle: iptvStyleLabel,
                        onTap: onOpenIptvStyle,
                      ),
                    SettingsTile.spec(
                      SettingsRows.playerGuideStyle,
                      subtitle: playerGuideStyleLabel,
                      onTap: onOpenPlayerGuideStyle,
                    ),
                    SettingsTile.spec(
                      SettingsRows.detailPageStyle,
                      subtitle: detailPageStyleLabel,
                      onTap: onOpenDetailPageStyle,
                    ),
                    SettingsTile.spec(
                      SettingsRows.appTheme,
                      subtitle: appThemeLabel,
                      onTap: onOpenAppTheme,
                    ),
                    SettingsTile.spec(
                      SettingsRows.detailTheme,
                      subtitle: detailThemeLabel,
                      onTap: onOpenDetailTheme,
                    ),
                    SettingsTile.spec(
                      SettingsRows.parentsGuideStyle,
                      subtitle: parentsGuideStyleLabel,
                      onTap: onOpenParentsGuideStyle,
                    ),
                    // Phone/small-window chrome — TVs navigate by sidebar
                    // and never read the style.
                    SettingsTile.spec(
                      SettingsRows.navigationStyle,
                      subtitle: phoneNavStyleLabel,
                      onTap: onOpenNavigationSettings,
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
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final bool lit = _focused || _hovered;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
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
