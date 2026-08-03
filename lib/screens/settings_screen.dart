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
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/webdav_item.dart';
import '../services/main_page_bridge.dart';
import '../utils/platform_util.dart';

import '../services/analytics_service.dart';
import '../services/account_service.dart';
import '../services/backup_restore_service.dart';
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
import '../services/update_service.dart';
import '../widgets/support_donation_chooser_dialog.dart';
import 'settings/debrify_tv_settings_page.dart';
import 'settings/settings_tv_layout.dart';
import 'settings/settings_search.dart';
import 'settings/tv_screen_size_page.dart';
import 'settings/widgets/settings_widgets.dart';
import 'settings/pikpak_settings_page.dart';
import 'settings/real_debrid_settings_page.dart';
import 'settings/reddit_settings_page.dart';
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
import '../widgets/remote/remote_role_picker_screen.dart';

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
      PackageInfo.fromPlatform(),
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
  ConnectionInfo get _redditInfo => ConnectionInfo(
    title: 'Reddit',
    connected: true,
    status: 'Active',
    caption: 'Browse video subreddits',
    onTap: _openRedditSettings,
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
        // Reddit source is retired — card hidden, settings code kept.
        // _redditInfo,
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
      tvUiScalePercent: _tvUiScalePercent,
      onOpenTvScreenSize: _openTvScreenSize,
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
        reddit: _redditInfo,
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
  /// Only top-level destinations are indexed today; [SettingsSearchEntry.keywords]
  /// carry the in-page concepts (sd card, 4k, epg, scrobble…) so a search still
  /// lands on the owning page. Per-leaf deep-links are a future extension —
  /// add entries here.
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
        category: 'Connections',
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
        category: 'Connections',
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
      if (_recordingSearchable)
        SettingsSearchEntry(
          icon: Icons.fiber_manual_record_rounded,
          title: 'IPTV recording',
          subtitle:
              'Recording engine, scheduled recordings and your recordings '
              'library',
          category: 'Connections',
          keywords: const [
            'record',
            'recording',
            'recordings',
            'dvr',
            'capture',
            'schedule',
            'scheduled',
            'timer',
            'rec',
            'iptv',
            'live tv',
            'engine',
            'library',
            'simultaneous',
            'parallel',
            'connections',
            'battery',
            'doze',
            'notifications',
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
        'General',
        _openHomePageSettings,
        keywords: const ['default view', 'startup', 'landing', 'tab'],
      ),
      nav(
        SettingsRows.player,
        'General',
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
        ],
      ),
      nav(
        SettingsRows.remote,
        'General',
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
      if (!PlatformUtil.isAndroidTvCached)
        nav(
          SettingsRows.navigationStyle,
          'General',
          _openNavigationSettings,
          keywords: const [
            'navigation',
            'nav',
            'bottom bar',
            'tabs',
            'floating',
            'classic',
            'menu',
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

      // TV Mode
      nav(
        SettingsRows.debrifyTv,
        'TV Mode',
        _openDebrifyTvSettings,
        keywords: const ['channels', 'limits', 'playback', 'android tv'],
      ),
      SettingsSearchEntry(
        icon: SettingsRows.tvKeyboard.icon,
        title: SettingsRows.tvKeyboard.title,
        subtitle: SettingsRows.tvKeyboard.subtitle,
        category: 'TV Mode',
        keywords: const [
          'on-screen keyboard',
          'remote',
          'text input',
          'ime',
          'typing',
        ],
        toggleValue: () => _tvKeyboardEnabled,
        onToggle: _toggleTvKeyboard,
      ),
      // Android TV only — the size factor is applied natively in MainActivity,
      // so the row would be inert anywhere else.
      if (_isAndroidTv)
        nav(
          SettingsRows.tvScreenSize,
          'TV Mode',
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
          ],
        ),

      // Downloads
      if (_downloadLocationSupported)
        nav(
          SettingsRows.downloadLocation,
          'Downloads',
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
        'Maintenance',
        _clearDownloadData,
        keywords: const ['queue', 'history', 'clear', 'remove'],
      ),
      nav(
        SettingsRows.clearPlayback,
        'Maintenance',
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
        'Backup & Restore',
        _createBackup,
        keywords: const ['export', 'save', 'addons'],
      ),
      nav(
        SettingsRows.restoreBackup,
        'Backup & Restore',
        _restoreBackup,
        keywords: const ['import', 'load'],
      ),

      // Updates
      SettingsSearchEntry(
        icon: SettingsRows.autoUpdate.icon,
        title: SettingsRows.autoUpdate.title,
        subtitle: SettingsRows.autoUpdate.subtitle,
        category: 'Updates',
        keywords: const ['notify', 'releases', 'startup'],
        toggleValue: () => _autoUpdateChecksEnabled,
        onToggle: _toggleAutoUpdateChecks,
      ),
      nav(
        SettingsRows.checkUpdates,
        'Updates',
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
          category: 'Support',
          keywords: const ['donate', 'tip', 'contribute', 'fund'],
          onTap: _openSupportDonation,
        ),
      nav(
        SettingsRows.reddit,
        'Support',
        () => launchSettingsUrl(SettingsRows.reddit.url!),
        keywords: const ['community', 'subreddit'],
      ),
      nav(
        SettingsRows.discord,
        'Support',
        () => launchSettingsUrl(SettingsRows.discord.url!),
        keywords: const ['community', 'chat', 'help'],
      ),
      nav(
        SettingsRows.github,
        'Support',
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
      'Search Settings': Icons.search_rounded,
      'Filter Settings': Icons.filter_list_rounded,
      'Provider Settings': Icons.cloud_sync_rounded,
      'Quick Play': Icons.bolt_rounded,
      'Home Page': Icons.home_rounded,
      'Player Settings': Icons.open_in_new_rounded,
      'Debrify TV': Icons.live_tv_rounded,
    };
    final pageOpeners = <String, Future<void> Function()>{
      'Torbox': _openTorboxSettings,
      'Premiumize': _openPremiumizeSettings,
      'Real Debrid': _openRealDebridSettings,
      'AllDebrid': _openAllDebridSettings,
      'PikPak': _openPikPakSettings,
      'Search Settings': _openTorrentSettings,
      'Filter Settings': _openFilterSettings,
      'Provider Settings': _openProviderSettings,
      'Quick Play': _openQuickPlaySettings,
      'Home Page': _openHomePageSettings,
      'Player Settings': _openExternalPlayerSettings,
      'Debrify TV': _openDebrifyTvSettings,
    };

    SettingsSearchEntry leaf(
      String page,
      String title,
      String subtitle,
      List<String> keywords,
    ) => SettingsSearchEntry(
      icon: pageIcons[page]!,
      title: title,
      subtitle: subtitle,
      category: page,
      keywords: keywords,
      onTap: pageOpeners[page]!,
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
        'AllDebrid',
        'Post-Torrent Action',
        'What happens after adding a torrent to AllDebrid',
        const ['after adding', 'post torrent', 'play', 'download'],
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

      // Search / Filter / Provider
      leaf(
        'Filter Settings',
        'Quality filter',
        'Default resolution filter for results',
        const ['quality', 'resolution', '4k', '2160p', '1080p', '720p', '480p'],
      ),
      leaf(
        'Filter Settings',
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
        'Filter Settings',
        'Language filter',
        'Default audio-language filter',
        const ['language', 'audio', 'english', 'hindi', 'multi-audio'],
      ),
      leaf(
        'Filter Settings',
        'Size filter',
        'Default file/pack size filter',
        const ['size', 'gb', 'mb', 'file size'],
      ),
      leaf(
        'Filter Settings',
        'Apply filters to Quick Play',
        'Quick Play prefers filtered sources',
        const ['quick play', 'apply filters', 'honor', 'sources'],
      ),
      leaf(
        'Provider Settings',
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
      leaf('Home Page', 'Home Rows', 'Choose which rows appear on Home', const [
        'home rows',
        'rows',
        'catalogs',
        'customize',
      ]),
      leaf(
        'Home Page',
        'Continue Watching',
        'Show recently watched on Home',
        const ['continue watching', 'recently watched', 'history'],
      ),
      leaf(
        'Home Page',
        'Hide Provider Cards',
        'Hide debrid status cards on Home',
        const ['hide', 'provider cards', 'debrid', 'status'],
      ),
      leaf(
        'Home Page',
        'Home trailer & sound',
        'Ambient trailer playback and volume',
        const ['trailer', 'spotlight', 'hero', 'sound', 'volume', 'autoplay'],
      ),

      // Player Settings
      leaf(
        'Player Settings',
        'Default Player',
        'Which player plays videos',
        const ['default player', 'debrify player', 'external', 'deovr'],
      ),
      leaf(
        'Player Settings',
        'Default Subtitle language',
        'Preferred subtitle language',
        const ['subtitle', 'subtitles', 'language', 'captions'],
      ),
      leaf(
        'Player Settings',
        'Default Audio language',
        'Preferred audio language / track',
        const ['audio', 'language', 'track', 'dub'],
      ),
      leaf(
        'Player Settings',
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
        'Player Settings',
        'Default Aspect Ratio',
        'Default video aspect / zoom',
        const ['aspect', 'ratio', 'zoom', 'fit', 'fill'],
      ),
      leaf(
        'Player Settings',
        'Allow system audio effects',
        'Let equalizer apps process audio (Android)',
        const ['audio effects', 'equalizer', 'wavelet', 'dolby'],
      ),
      leaf(
        'Player Settings',
        'Preferred external player',
        'Choose the external player app',
        const ['external', 'vlc', 'mpv', 'mx player', 'custom command'],
      ),

      // Debrify TV
      leaf(
        'Debrify TV',
        'Channel result limits',
        'Per-engine channel size & result caps',
        const ['limits', 'result limit', 'channel max', 'engines', 'nsfw'],
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

  Future<void> _openRedditSettings() async {
    await pushSettingsPage(context, const RedditSettingsPage());
    if (!mounted) return;
    setState(() {});
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
    Future<void> choose(String style) async {
      await StorageService.setPhoneNavStyle(style);
      MainPageBridge.navPrefsChanged?.call();
    }

    await showDialog<void>(
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
            onTap: () {
              Navigator.of(dialogContext).pop();
              unawaited(choose(value));
            },
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
  }

  Future<void> _openIptvSettings() async {
    await pushSettingsPage(context, const IptvSettingsPage());
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openHomePageSettings() async {
    await pushSettingsPage(context, const HomePageSettingsPage());
    if (!mounted) return;
    setState(() {});
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
        final dir = await getApplicationDocumentsDirectory();
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
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
            const Text('This backup contains:'),
            const SizedBox(height: 8),
            ..._backupSummaryLines(summary).map((line) => Text('• $line')),
            const SizedBox(height: 12),
            const Text(
              'Saved credentials (Real-Debrid, Torbox, Premiumize, AllDebrid, PikPak, Trakt, Simkl) will '
              'be overwritten. Addons, search engines, WebDAV servers, and '
              'indexer managers you already have are kept as-is.',
              style: TextStyle(fontSize: 12),
            ),
            if (summary.addonCount > 0 || summary.searchEngineCount > 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Restoring addons and search engines needs a network '
                  'connection.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
            if (summary.webDavServerCount > 0 ||
                summary.indexerManagerCount > 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'WebDAV and Jackett/Prowlarr URLs may be local-network '
                  'only — they won\'t work on a different network.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
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
        backgroundColor: report.hasAnyFailure ? kSettingsAmber : null,
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
      backgroundColor: const Color(0xFF0B1220),
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
        final Color bodyColor = Colors.white.withValues(alpha: 0.85);
        final markdownStyle = MarkdownStyleSheet.fromTheme(baseTheme).copyWith(
          h1: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          h2: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          h3: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          p: textTheme.bodyMedium?.copyWith(color: bodyColor, height: 1.45),
          strong: const TextStyle(fontWeight: FontWeight.w700),
          listBullet: textTheme.bodyMedium?.copyWith(color: bodyColor),
          blockquote: textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.7),
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
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
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
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Latest: $latestLabel',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  if (publishedLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Published $publishedLabel',
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.5),
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
  });

  @override
  Widget build(BuildContext context) {
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
                // General section
                SettingsSection(
                  title: 'General',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.homePage,
                      onTap: onOpenHomePageSettings,
                    ),
                    SettingsTile.spec(
                      SettingsRows.player,
                      onTap: onOpenExternalPlayerSettings,
                    ),
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
                    // Phone/small-window chrome only — TVs navigate by
                    // sidebar and never read the style.
                    if (!isAndroidTv)
                      SettingsTile.spec(
                        SettingsRows.navigationStyle,
                        onTap: onOpenNavigationSettings,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                // Search section
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
                // TV Mode section
                SettingsSection(
                  title: 'TV Mode',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.debrifyTv,
                      onTap: onOpenDebrifyTvSettings,
                    ),
                    SettingsToggleTile.spec(
                      SettingsRows.tvKeyboard,
                      value: tvKeyboardEnabled,
                      onChanged: onToggleTvKeyboard,
                    ),
                  ],
                ),
                if (onOpenDownloadLocation != null) ...[
                  const SizedBox(height: 24),
                  // Downloads section
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
                ],
                const SizedBox(height: 24),
                // Maintenance section
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
                const SizedBox(height: 24),
                // Backup & Restore section
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
                const SizedBox(height: 24),
                // Danger Zone section
                SettingsSection(
                  title: 'Danger Zone',
                  accentColor: kSettingsRed.withValues(alpha: 0.85),
                  children: [
                    SettingsTile.spec(
                      SettingsRows.resetDebrify,
                      onTap: onDangerAction,
                      destructive: true,
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
            color: lit ? kSettingsPanel2 : kSettingsPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused ? kSettingsAccent : kSettingsLine,
              width: _focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 20,
                color: lit ? kSettingsAccent2 : kSettingsDim,
              ),
              const SizedBox(width: 12),
              Text(
                'Search settings',
                style: TextStyle(fontSize: 13.5, color: kSettingsDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
