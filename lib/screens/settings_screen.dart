import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/main_page_bridge.dart';

import '../services/account_service.dart';
import '../services/download_service.dart';
import '../services/storage_service.dart';
import '../services/torbox_account_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/stremio_service.dart';
import '../services/android_native_downloader.dart';
import '../services/update_service.dart';
import '../widgets/shimmer.dart';
import 'settings/debrify_tv_settings_page.dart';
import 'settings/pikpak_settings_page.dart';
import 'settings/real_debrid_settings_page.dart';
import 'settings/reddit_settings_page.dart';
import 'settings/iptv_settings_page.dart';
import 'settings/home_page_settings_page.dart';
import 'settings/startup_settings_page.dart';
import 'settings/torbox_settings_page.dart';
import 'settings/torrent_settings_page.dart';
import 'settings/filter_settings_page.dart';
import 'settings/provider_settings_page.dart';
import 'settings/quick_play_settings_page.dart';
import 'settings/external_player_settings_page.dart';
import 'settings/stremio_tv_settings_page.dart';
import 'settings/trakt_settings_page.dart';
import '../widgets/remote/remote_control_screen.dart';

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

  // TV content focus handler (stored for proper unregistration)
  VoidCallback? _tvContentFocusHandler;

  bool _realDebridConnected = false;
  String _realDebridStatus = 'Not connected';
  String _realDebridCaption = 'Tap to connect';

  bool _torboxConnected = false;
  String _torboxStatus = 'Not connected';
  String _torboxCaption = 'Tap to connect';

  bool _pikpakConnected = false;
  String _pikpakStatus = 'Not connected';
  String _pikpakCaption = 'Tap to connect';

  bool _traktConnected = false;
  String _traktStatus = 'Not connected';
  String _traktCaption = 'Tap to connect';

  String _appVersion = '';
  String _currentVersionName = '';
  bool _checkingUpdates = false;
  String _updateSubtitle = 'Check for new builds from GitHub releases';
  StreamSubscription<Map<String, dynamic>>? _updateDownloadSub;
  String? _updateDownloadTaskId;

  @override
  void initState() {
    super.initState();
    _loadSummaries();

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
      StorageService.getTraktAccessToken(),
      StorageService.getTraktTokenExpiry(),
      StorageService.getTraktUsername(),
      PackageInfo.fromPlatform(),
      AndroidNativeDownloader.isTelevision(),
    ]);

    if (!mounted) return;

    final rdKey = results[0] as String?;
    final torboxKey = results[1] as String?;
    final pikpakAuth = results[2] as bool;
    final traktToken = results[3] as String?;
    final traktExpiry = results[4] as int?;
    final traktUsername = results[5] as String?;
    final packageInfo = results[6] as PackageInfo;
    final isAndroidTv = results[7] as bool;

    // Set initial state from cached data
    final rdConnected = rdKey != null && rdKey.isNotEmpty;
    final torConnected = torboxKey != null && torboxKey.isNotEmpty;

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

    if (pikpakAuth) {
      _pikpakConnected = true;
      _pikpakStatus = 'Active';
      _pikpakCaption = 'Logged in';
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

    _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
    _currentVersionName = packageInfo.version;
    _isAndroidTv = isAndroidTv;
    _loading = false;

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _SettingsSkeleton();
    }

    return _SettingsLayout(
      connections: _ConnectionsSummary(
        realDebrid: _ConnectionInfo(
          title: 'Real Debrid',
          connected: _realDebridConnected,
          status: _realDebridStatus,
          caption: _realDebridCaption,
          icon: Icons.cloud_download_rounded,
          onTap: _openRealDebridSettings,
        ),
        torbox: _ConnectionInfo(
          title: 'Torbox',
          connected: _torboxConnected,
          status: _torboxStatus,
          caption: _torboxCaption,
          icon: Icons.flash_on_rounded,
          onTap: _openTorboxSettings,
        ),
        pikpak: _ConnectionInfo(
          title: 'PikPak',
          connected: _pikpakConnected,
          status: _pikpakStatus,
          caption: _pikpakCaption,
          icon: Icons.cloud_circle_rounded,
          onTap: _openPikPakSettings,
        ),
        reddit: _ConnectionInfo(
          title: 'Reddit',
          connected: true,
          status: 'Active',
          caption: 'Browse video subreddits',
          icon: Icons.reddit,
          onTap: _openRedditSettings,
        ),
        iptv: _ConnectionInfo(
          title: 'IPTV',
          connected: true,
          status: 'Active',
          caption: 'M3U playlist channels',
          icon: Icons.live_tv,
          onTap: _openIptvSettings,
        ),
        trakt: _ConnectionInfo(
          title: 'Trakt',
          connected: _traktConnected,
          status: _traktStatus,
          caption: _traktCaption,
          icon: Icons.movie_filter_rounded,
          onTap: _openTraktSettings,
        ),
        firstCardFocusNode: _firstCardFocusNode,
      ),
      onOpenTorrentSettings: _openTorrentSettings,
      onOpenFilterSettings: _openFilterSettings,
      onOpenProviderSettings: _openProviderSettings,
      onOpenQuickPlaySettings: _openQuickPlaySettings,
      onOpenDebrifyTvSettings: _openDebrifyTvSettings,
      onOpenStremioTvSettings: _openStremioTvSettings,
      onOpenPikPakSettings: _openPikPakSettings,
      onOpenHomePageSettings: _openHomePageSettings,
      onOpenStartupSettings: _openStartupSettings,
      onOpenExternalPlayerSettings: _openExternalPlayerSettings,
      onOpenRemoteControl: _openRemoteControl,
      isAndroidTv: _isAndroidTv,
      onClearDownloads: _clearDownloadData,
      onClearPlayback: _clearPlaybackData,
      onDangerAction: _resetAppData,
      appVersion: _appVersion,
      onCheckForUpdates: _checkForAppUpdates,
      updateSubtitle: _updateSubtitle,
      checkingUpdates: _checkingUpdates,
    );
  }

  Future<void> _openTorrentSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TorrentSettingsPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openDebrifyTvSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DebrifyTvSettingsPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openStremioTvSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StremioTvSettingsPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openPikPakSettings() async {
    final loggedOut = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const PikPakSettingsPage()));
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  Future<void> _openRedditSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RedditSettingsPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openTraktSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TraktSettingsPage()));
    if (!mounted) return;
    await _loadSummaries();
  }

  Future<void> _openIptvSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const IptvSettingsPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openHomePageSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HomePageSettingsPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openStartupSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StartupSettingsPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openExternalPlayerSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ExternalPlayerSettingsPage()),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openRemoteControl() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RemoteControlScreen()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openFilterSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FilterSettingsPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openProviderSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ProviderSettingsPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openQuickPlaySettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QuickPlaySettingsPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openRealDebridSettings() async {
    final loggedOut = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RealDebridSettingsPage()),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  Future<void> _openTorboxSettings() async {
    final loggedOut = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const TorboxSettingsPage()));
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

  Future<void> _clearDownloadData() async {
    final confirmed = await showDialog<bool>(
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
    final confirmed = await showDialog<bool>(
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
    final confirmed = await showDialog<bool>(
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
    await StorageService.clearPikPakAuth();
    await StorageService.clearTraktAuth();
    await DownloadService.instance.clearDownloadDatabase();
    await StorageService.clearAllPlaybackData();
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
  final _ConnectionsSummary connections;
  final Future<void> Function() onOpenTorrentSettings;
  final Future<void> Function() onOpenFilterSettings;
  final Future<void> Function() onOpenProviderSettings;
  final Future<void> Function() onOpenQuickPlaySettings;
  final Future<void> Function() onOpenDebrifyTvSettings;
  final Future<void> Function() onOpenStremioTvSettings;
  final Future<void> Function() onOpenPikPakSettings;
  final Future<void> Function() onOpenHomePageSettings;
  final Future<void> Function() onOpenStartupSettings;
  final Future<void> Function() onOpenExternalPlayerSettings;
  final VoidCallback onOpenRemoteControl;
  final bool isAndroidTv;
  final Future<void> Function() onClearDownloads;
  final Future<void> Function() onClearPlayback;
  final Future<void> Function() onDangerAction;
  final String appVersion;
  final Future<void> Function() onCheckForUpdates;
  final String updateSubtitle;
  final bool checkingUpdates;

  const _SettingsLayout({
    required this.connections,
    required this.onOpenTorrentSettings,
    required this.onOpenFilterSettings,
    required this.onOpenProviderSettings,
    required this.onOpenQuickPlaySettings,
    required this.onOpenDebrifyTvSettings,
    required this.onOpenStremioTvSettings,
    required this.onOpenPikPakSettings,
    required this.onOpenHomePageSettings,
    required this.onOpenStartupSettings,
    required this.onOpenExternalPlayerSettings,
    required this.onOpenRemoteControl,
    required this.isAndroidTv,
    required this.onClearDownloads,
    required this.onClearPlayback,
    required this.onDangerAction,
    required this.appVersion,
    required this.onCheckForUpdates,
    required this.updateSubtitle,
    required this.checkingUpdates,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsHeader(theme: theme),
          const SizedBox(height: 24),
          // Connections section with cards
          connections,
          const SizedBox(height: 24),
          // General section
          _SettingsSection(
            title: 'General',
            children: [
              _SettingsTile(
                icon: Icons.home_rounded,
                title: 'Home Page',
                subtitle: 'Default view when app opens',
                onTap: onOpenHomePageSettings,
                iconColor: const Color(0xFF6366F1),
              ),
              _SettingsTile(
                icon: Icons.open_in_new_rounded,
                title: 'Player Settings',
                subtitle: 'Configure preferred video player',
                onTap: onOpenExternalPlayerSettings,
                iconColor: const Color(0xFF8B5CF6),
              ),
              _SettingsTile(
                icon: Icons.rocket_launch_rounded,
                title: 'Startup',
                subtitle: 'Decide what happens on app launch',
                onTap: onOpenStartupSettings,
                iconColor: const Color(0xFFF59E0B),
              ),
              // Remote Control: Hide on mobile (in floating menu) and TV (receiver)
              // Only show on desktop platforms
              if (!kIsWeb &&
                  (Platform.isWindows || Platform.isMacOS || Platform.isLinux))
                _SettingsTile(
                  icon: Icons.phonelink_rounded,
                  title: 'Remote Control',
                  subtitle: 'Control Debrify TV from your phone',
                  onTap: () async => onOpenRemoteControl(),
                  iconColor: const Color(0xFF06B6D4),
                ),
            ],
          ),
          const SizedBox(height: 24),
          // Search section
          _SettingsSection(
            title: 'Search',
            children: [
              _SettingsTile(
                icon: Icons.search_rounded,
                title: 'Search Settings',
                subtitle: 'Engines, filters, and sorting',
                onTap: onOpenTorrentSettings,
                iconColor: const Color(0xFF3B82F6),
              ),
              _SettingsTile(
                icon: Icons.filter_list_rounded,
                title: 'Filter Settings',
                subtitle: 'Default quality, source, and language filters',
                onTap: onOpenFilterSettings,
                iconColor: const Color(0xFF10B981),
              ),
              _SettingsTile(
                icon: Icons.cloud_sync_rounded,
                title: 'Provider Settings',
                subtitle: 'Default provider for adding torrents',
                onTap: onOpenProviderSettings,
                iconColor: const Color(0xFF8B5CF6),
              ),
              _SettingsTile(
                icon: Icons.bolt_rounded,
                title: 'Quick Play Settings',
                subtitle: 'Configure quick play for torrent search',
                onTap: onOpenQuickPlaySettings,
                iconColor: const Color(0xFFF59E0B),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // TV Mode section
          _SettingsSection(
            title: 'TV Mode',
            children: [
              _SettingsTile(
                icon: Icons.live_tv_rounded,
                title: 'Debrify TV Settings',
                subtitle: 'Limits, channels, and playback configuration',
                onTap: onOpenDebrifyTvSettings,
                iconColor: const Color(0xFFE11D48),
              ),
              _SettingsTile(
                icon: Icons.smart_display_rounded,
                title: 'Stremio TV Settings',
                subtitle: 'Rotation interval and channel preferences',
                onTap: onOpenStremioTvSettings,
                iconColor: const Color(0xFF06B6D4),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Maintenance section
          _SettingsSection(
            title: 'Maintenance',
            children: [
              _SettingsTile(
                icon: Icons.download_rounded,
                title: 'Clear Download Data',
                subtitle: 'Remove queue history and in-progress entries',
                onTap: onClearDownloads,
                iconColor: const Color(0xFFF59E0B),
              ),
              _SettingsTile(
                icon: Icons.play_circle_rounded,
                title: 'Clear Playback Data',
                subtitle: 'Reset resume points and playback sessions',
                onTap: onClearPlayback,
                iconColor: const Color(0xFF8B5CF6),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Danger Zone section
          _SettingsSection(
            title: 'Danger Zone',
            accentColor: theme.colorScheme.error,
            children: [
              _SettingsTile(
                icon: Icons.warning_rounded,
                title: 'Reset Debrify',
                subtitle: 'Remove connections, preferences, and caches',
                onTap: onDangerAction,
                iconColor: const Color(0xFFEF4444),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // About section
          _SettingsSection(
            title: 'About',
            children: [
              _SettingsTile(
                icon: Icons.system_update_rounded,
                title: 'Check for Updates',
                subtitle: updateSubtitle,
                onTap: onCheckForUpdates,
                iconColor: const Color(0xFF22C55E),
                tag: 'New',
                trailing: checkingUpdates
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : null,
              ),
              _SettingsTile(
                icon: Icons.forum_rounded,
                title: 'Reddit Community',
                subtitle: 'r/debrify - Questions, tips, and discussion',
                onTap: () =>
                    launchUrl(Uri.parse('https://www.reddit.com/r/debrify/')),
                iconColor: const Color(0xFFFF4500),
              ),
              _SettingsTile(
                icon: Icons.chat_rounded,
                title: 'Discord',
                subtitle: 'Join for help, updates, and discussion',
                onTap: () =>
                    launchUrl(Uri.parse('https://discord.gg/xuAc4Q2c9G')),
                iconColor: const Color(0xFF5865F2),
              ),
              _SettingsTile(
                icon: Icons.code_rounded,
                title: 'GitHub',
                subtitle: 'Source code and contributions',
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/varunsalian/debrify'),
                ),
                iconColor: const Color(0xFF10B981),
              ),
              _InfoTile(
                icon: Icons.info_outline_rounded,
                title: 'Version',
                value: appVersion,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  final ThemeData theme;
  const _SettingsHeader({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3730A3), Color(0xFF1E1B4B)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.settings_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Settings',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage connections and clean up your library.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionsSummary extends StatefulWidget {
  final _ConnectionInfo realDebrid;
  final _ConnectionInfo torbox;
  final _ConnectionInfo pikpak;
  final _ConnectionInfo reddit;
  final _ConnectionInfo iptv;
  final _ConnectionInfo trakt;
  final FocusNode? firstCardFocusNode;

  const _ConnectionsSummary({
    required this.realDebrid,
    required this.torbox,
    required this.pikpak,
    required this.reddit,
    required this.iptv,
    required this.trakt,
    this.firstCardFocusNode,
  });

  @override
  State<_ConnectionsSummary> createState() => _ConnectionsSummaryState();
}

class _ConnectionsSummaryState extends State<_ConnectionsSummary> {
  // Focus nodes for grid navigation
  // Layout: [realDebrid, torbox]
  //         [pikpak,     reddit]
  //         [iptv]
  late final FocusNode _torboxFocusNode;
  late final FocusNode _pikpakFocusNode;
  late final FocusNode _redditFocusNode;
  late final FocusNode _iptvFocusNode;
  late final FocusNode _traktFocusNode;

  @override
  void initState() {
    super.initState();
    _torboxFocusNode = FocusNode(debugLabel: 'settings-torbox');
    _pikpakFocusNode = FocusNode(debugLabel: 'settings-pikpak');
    _redditFocusNode = FocusNode(debugLabel: 'settings-reddit');
    _iptvFocusNode = FocusNode(debugLabel: 'settings-iptv');
    _traktFocusNode = FocusNode(debugLabel: 'settings-trakt');
  }

  @override
  void dispose() {
    _torboxFocusNode.dispose();
    _pikpakFocusNode.dispose();
    _redditFocusNode.dispose();
    _iptvFocusNode.dispose();
    _traktFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connections',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final bool wide = constraints.maxWidth > 520;
            final double itemWidth = wide
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            // Grid layout (wide):
            // [RD]      [Torbox]
            // [PikPak]  [Reddit]
            // [IPTV]    [Trakt]
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Row 1: Real Debrid (left), Torbox (right)
                SizedBox(
                  width: itemWidth,
                  child: _ConnectionCard(
                    info: widget.realDebrid,
                    focusNode: widget.firstCardFocusNode,
                    isLeftColumn: true,
                    rightNeighbor: wide ? _torboxFocusNode : null,
                    downNeighbor: _pikpakFocusNode,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _ConnectionCard(
                    info: widget.torbox,
                    focusNode: _torboxFocusNode,
                    isLeftColumn: !wide,
                    leftNeighbor: wide ? widget.firstCardFocusNode : null,
                    downNeighbor: wide ? _redditFocusNode : _pikpakFocusNode,
                  ),
                ),
                // Row 2: PikPak (left), Reddit (right)
                SizedBox(
                  width: itemWidth,
                  child: _ConnectionCard(
                    info: widget.pikpak,
                    focusNode: _pikpakFocusNode,
                    isLeftColumn: true,
                    rightNeighbor: wide ? _redditFocusNode : null,
                    upNeighbor: widget.firstCardFocusNode,
                    downNeighbor: _iptvFocusNode,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _ConnectionCard(
                    info: widget.reddit,
                    focusNode: _redditFocusNode,
                    isLeftColumn: !wide,
                    leftNeighbor: wide ? _pikpakFocusNode : null,
                    upNeighbor: wide ? _torboxFocusNode : _pikpakFocusNode,
                    downNeighbor: wide ? _traktFocusNode : _iptvFocusNode,
                  ),
                ),
                // Row 3: IPTV (left), Trakt (right)
                SizedBox(
                  width: itemWidth,
                  child: _ConnectionCard(
                    info: widget.iptv,
                    focusNode: _iptvFocusNode,
                    isLeftColumn: true,
                    rightNeighbor: wide ? _traktFocusNode : null,
                    upNeighbor: _pikpakFocusNode,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _ConnectionCard(
                    info: widget.trakt,
                    focusNode: _traktFocusNode,
                    isLeftColumn: !wide,
                    leftNeighbor: wide ? _iptvFocusNode : null,
                    upNeighbor: wide ? _redditFocusNode : _iptvFocusNode,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ConnectionInfo {
  final String title;
  final bool connected;
  final String status;
  final String caption;
  final IconData icon;
  final Future<void> Function() onTap;

  const _ConnectionInfo({
    required this.title,
    required this.connected,
    required this.status,
    required this.caption,
    required this.icon,
    required this.onTap,
  });
}

class _ConnectionCard extends StatelessWidget {
  final _ConnectionInfo info;
  final FocusNode? focusNode;
  final bool isLeftColumn;
  final FocusNode? leftNeighbor;
  final FocusNode? rightNeighbor;
  final FocusNode? upNeighbor;
  final FocusNode? downNeighbor;

  const _ConnectionCard({
    required this.info,
    this.focusNode,
    this.isLeftColumn = true,
    this.leftNeighbor,
    this.rightNeighbor,
    this.upNeighbor,
    this.downNeighbor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String statusLower = info.status.toLowerCase();
    final bool active = info.connected && statusLower == 'active';
    final Color indicatorColor = info.connected
        ? (active ? Colors.green : Colors.red)
        : theme.colorScheme.outline;

    // Helper to focus and scroll into view
    void focusAndScroll(FocusNode target) {
      target.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (target.context != null) {
          Scrollable.ensureVisible(
            target.context!,
            alignment: 0.3,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
    }

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (leftNeighbor != null) {
            focusAndScroll(leftNeighbor!);
            return KeyEventResult.handled;
          } else if (isLeftColumn && MainPageBridge.focusTvSidebar != null) {
            // Left column with no left neighbor: open sidebar
            MainPageBridge.focusTvSidebar!();
            return KeyEventResult.handled;
          }
        } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (rightNeighbor != null) {
            focusAndScroll(rightNeighbor!);
            return KeyEventResult.handled;
          }
        } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (upNeighbor != null) {
            focusAndScroll(upNeighbor!);
            return KeyEventResult.handled;
          }
        } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (downNeighbor != null) {
            focusAndScroll(downNeighbor!);
            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            focusNode: focusNode,
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              await info.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: info.connected && active
                            ? [const Color(0xFF059669), const Color(0xFF10B981)]
                            : [
                                const Color(0xFF6366F1),
                                const Color(0xFF8B5CF6),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (info.connected && active
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF6366F1))
                                  .withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(info.icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                info.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              height: 8,
                              width: 8,
                              decoration: BoxDecoration(
                                color: indicatorColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: indicatorColor.withValues(
                                      alpha: 0.5,
                                    ),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          info.status,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: info.connected
                                ? (active
                                      ? const Color(0xFF34D399)
                                      : Colors.red)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          info.caption,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Color? accentColor;

  const _SettingsSection({
    required this.title,
    required this.children,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: accentColor ?? Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  if (i != 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 56,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final String? tag;
  final Color iconColor;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tag,
    this.iconColor = const Color(0xFF6366F1),
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        await onTap();
      },
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiary.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tag!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.tertiary,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF818CF8), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSkeleton extends StatelessWidget {
  const _SettingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _SkeletonHeader(),
          SizedBox(height: 24),
          _SkeletonSection(),
          SizedBox(height: 24),
          _SkeletonSection(),
          SizedBox(height: 24),
          _SkeletonSection(),
        ],
      ),
    );
  }
}

class _SkeletonHeader extends StatelessWidget {
  const _SkeletonHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3730A3), Color(0xFF1E1B4B)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Shimmer(width: 140, height: 20),
          SizedBox(height: 10),
          Shimmer(width: 220, height: 14),
        ],
      ),
    );
  }
}

class _SkeletonSection extends StatelessWidget {
  const _SkeletonSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Shimmer(width: 160, height: 16),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: const [
              _SkeletonTile(),
              Divider(height: 1),
              _SkeletonTile(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: const [
          Shimmer(
            width: 40,
            height: 40,
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
          SizedBox(width: 12),
          Expanded(child: Shimmer(height: 14)),
        ],
      ),
    );
  }
}
