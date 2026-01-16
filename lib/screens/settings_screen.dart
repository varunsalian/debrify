import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/main_page_bridge.dart';

import '../services/account_service.dart';
import '../services/download_service.dart';
import '../services/storage_service.dart';
import '../services/torbox_account_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/debrify_tv_repository.dart';
import '../services/stremio_service.dart';
import '../widgets/shimmer.dart';
import 'settings/debrify_tv_settings_page.dart';
import 'settings/pikpak_settings_page.dart';
import 'settings/real_debrid_settings_page.dart';
import 'settings/startup_settings_page.dart';
import 'settings/torbox_settings_page.dart';
import 'settings/torrent_settings_page.dart';
import 'settings/filter_settings_page.dart';
import 'settings/engine_import_page.dart';
import 'settings/stremio_addons_page.dart';
import 'settings/provider_settings_page.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;

  // Focus node for the first connection card (Real-Debrid) for TV navigation
  final FocusNode _firstCardFocusNode = FocusNode(debugLabel: 'firstCardFocus');

  bool _realDebridConnected = false;
  String _realDebridStatus = 'Not connected';
  String _realDebridCaption = 'Tap to connect';

  bool _torboxConnected = false;
  String _torboxStatus = 'Not connected';
  String _torboxCaption = 'Tap to connect';

  bool _pikpakConnected = false;
  String _pikpakStatus = 'Not connected';
  String _pikpakCaption = 'Tap to connect';

  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadSummaries();

    // Register TV sidebar focus handler (tab index 7 = Settings)
    MainPageBridge.registerTvContentFocusHandler(7, () {
      _firstCardFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    MainPageBridge.unregisterTvContentFocusHandler(7);
    _firstCardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSummaries() async {
    setState(() {
      _loading = true;
    });

    bool rdConnected = false;
    String rdStatus = 'Not connected';
    String rdCaption = 'Tap to connect';

    final rdKey = await StorageService.getApiKey();
    if (rdKey != null && rdKey.isNotEmpty) {
      rdConnected = true;
      await AccountService.refreshUserInfo();
      final user = AccountService.currentUser;
      if (user != null) {
        final expiry = _tryParseDate(user.expiration);
        final bool isPremium = user.isPremium;
        final bool active =
            isPremium && (expiry == null || expiry.isAfter(DateTime.now()));
        rdStatus = active ? 'Active' : 'Inactive';
        if (active && expiry != null) {
          rdCaption = 'Expires ${_formatDate(expiry)}';
        } else if (active) {
          rdCaption = 'Premium account';
        } else if (isPremium && expiry != null) {
          rdCaption = 'Expired ${_formatDate(expiry)}';
        } else {
          rdCaption = 'Premium not active';
        }
      } else {
        rdStatus = 'Inactive';
        rdCaption = 'Tap to view account';
      }
    }

    bool torConnected = false;
    String torStatus = 'Not connected';
    String torCaption = 'Tap to connect';

    final torboxKey = await StorageService.getTorboxApiKey();
    if (torboxKey != null && torboxKey.isNotEmpty) {
      torConnected = true;
      await TorboxAccountService.refreshUserInfo();
      final torboxUser = TorboxAccountService.currentUser;
      if (torboxUser != null) {
        final expiry = torboxUser.premiumExpiresAt;
        final bool active = torboxUser.hasActiveSubscription;
        torStatus = active ? 'Active' : 'Inactive';
        if (active && expiry != null) {
          torCaption = 'Expires ${_formatDate(expiry)}';
        } else if (active) {
          torCaption = 'Premium account';
        } else if (expiry != null && expiry.isBefore(DateTime.now())) {
          torCaption = 'Expired ${_formatDate(expiry)}';
        } else {
          torCaption = 'Premium not active';
        }
      } else {
        torStatus = 'Inactive';
        torCaption = 'Plan status unavailable';
      }
    }

    bool pikpakConnected = false;
    String pikpakStatus = 'Not connected';
    String pikpakCaption = 'Tap to connect';

    final pikpakAuth = await PikPakApiService.instance.isAuthenticated();
    if (pikpakAuth) {
      pikpakConnected = true;
      pikpakStatus = 'Active';
      pikpakCaption = 'Logged in';
    }

    // Load app version
    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';

    if (!mounted) return;

    setState(() {
      _realDebridConnected = rdConnected;
      _realDebridStatus = rdStatus;
      _realDebridCaption = rdCaption;
      _torboxConnected = torConnected;
      _torboxStatus = torStatus;
      _torboxCaption = torCaption;
      _pikpakConnected = pikpakConnected;
      _pikpakStatus = pikpakStatus;
      _pikpakCaption = pikpakCaption;
      _appVersion = appVersion;
      _loading = false;
    });
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
        firstCardFocusNode: _firstCardFocusNode,
      ),
      onOpenTorrentSettings: _openTorrentSettings,
      onOpenFilterSettings: _openFilterSettings,
      onOpenProviderSettings: _openProviderSettings,
      onOpenDebrifyTvSettings: _openDebrifyTvSettings,
      onOpenPikPakSettings: _openPikPakSettings,
      onOpenStartupSettings: _openStartupSettings,
      onOpenEngineImportSettings: _openEngineImportSettings,
      onOpenStremioAddonsSettings: _openStremioAddonsSettings,
      onClearDownloads: _clearDownloadData,
      onClearPlayback: _clearPlaybackData,
      onDangerAction: _resetAppData,
      appVersion: _appVersion,
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

  Future<void> _openPikPakSettings() async {
    final loggedOut = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PikPakSettingsPage()),
    );
    if (!mounted) return;
    await _loadSummaries();
    if (loggedOut == true) {
      _focusFirstCard();
    }
  }

  Future<void> _openStartupSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StartupSettingsPage()));
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

  Future<void> _openEngineImportSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const EngineImportPage()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openStremioAddonsSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StremioAddonsPage()));
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
    final loggedOut = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TorboxSettingsPage()),
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
    await DownloadService.instance.clearDownloadDatabase();
    await StorageService.clearAllPlaybackData();
    await StorageService.clearPlaylist();
    await StorageService.clearAllPlaylistMetadata();
    await StorageService.clearTorrentSearchHistory();
    await StorageService.clearAllStartupSettings();
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
  final Future<void> Function() onOpenDebrifyTvSettings;
  final Future<void> Function() onOpenPikPakSettings;
  final Future<void> Function() onOpenStartupSettings;
  final Future<void> Function() onOpenEngineImportSettings;
  final Future<void> Function() onOpenStremioAddonsSettings;
  final Future<void> Function() onClearDownloads;
  final Future<void> Function() onClearPlayback;
  final Future<void> Function() onDangerAction;
  final String appVersion;

  const _SettingsLayout({
    required this.connections,
    required this.onOpenTorrentSettings,
    required this.onOpenFilterSettings,
    required this.onOpenProviderSettings,
    required this.onOpenDebrifyTvSettings,
    required this.onOpenPikPakSettings,
    required this.onOpenStartupSettings,
    required this.onOpenEngineImportSettings,
    required this.onOpenStremioAddonsSettings,
    required this.onClearDownloads,
    required this.onClearPlayback,
    required this.onDangerAction,
    required this.appVersion,
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
          // Search section
          _SettingsSection(
            title: 'Search',
            children: [
              _SettingsTile(
                icon: Icons.search_rounded,
                title: 'Search Settings',
                subtitle: 'Engines, filters, and sorting',
                onTap: onOpenTorrentSettings,
              ),
              _SettingsTile(
                icon: Icons.filter_list_rounded,
                title: 'Filter Settings',
                subtitle: 'Default quality, source, and language filters',
                onTap: onOpenFilterSettings,
              ),
              _SettingsTile(
                icon: Icons.cloud_sync_rounded,
                title: 'Provider Settings',
                subtitle: 'Default provider for adding torrents',
                onTap: onOpenProviderSettings,
              ),
              _SettingsTile(
                icon: Icons.extension_rounded,
                title: 'Import Engines',
                subtitle: 'Import and manage torrent search engines',
                onTap: onOpenEngineImportSettings,
              ),
              _SettingsTile(
                icon: Icons.stream_rounded,
                title: 'Stremio Addons',
                subtitle: 'Connect Stremio addons for more sources',
                onTap: onOpenStremioAddonsSettings,
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
              ),
            ],
          ),
          const SizedBox(height: 24),
          // General section
          _SettingsSection(
            title: 'General',
            children: [
              _SettingsTile(
                icon: Icons.rocket_launch_rounded,
                title: 'Startup',
                subtitle: 'Decide what happens on app launch',
                onTap: onOpenStartupSettings,
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
              ),
              _SettingsTile(
                icon: Icons.play_circle_rounded,
                title: 'Clear Playback Data',
                subtitle: 'Reset resume points and playback sessions',
                onTap: onClearPlayback,
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
              ),
            ],
          ),
          const SizedBox(height: 24),
          // About section
          _SettingsSection(
            title: 'About',
            children: [
              _SettingsTile(
                icon: Icons.forum_rounded,
                title: 'Reddit Community',
                subtitle: 'r/debrify - Questions, tips, and discussion',
                onTap: () => launchUrl(Uri.parse('https://www.reddit.com/r/debrify/')),
              ),
              _SettingsTile(
                icon: Icons.chat_rounded,
                title: 'Discord',
                subtitle: 'Join for help, updates, and discussion',
                onTap: () => launchUrl(Uri.parse('https://discord.gg/nay3FVtAp')),
              ),
              _SettingsTile(
                icon: Icons.code_rounded,
                title: 'GitHub',
                subtitle: 'Source code and contributions',
                onTap: () => launchUrl(Uri.parse('https://github.com/varunsalian/debrify')),
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
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.settings, color: Colors.white, size: 24),
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
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage connections and clean up your library.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.7,
                    ),
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

class _ConnectionsSummary extends StatelessWidget {
  final _ConnectionInfo realDebrid;
  final _ConnectionInfo torbox;
  final _ConnectionInfo pikpak;
  final FocusNode? firstCardFocusNode;

  const _ConnectionsSummary({
    required this.realDebrid,
    required this.torbox,
    required this.pikpak,
    this.firstCardFocusNode,
  });

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
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _ConnectionCard(
                    info: realDebrid,
                    focusNode: firstCardFocusNode,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _ConnectionCard(info: torbox),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _ConnectionCard(info: pikpak),
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
  const _ConnectionCard({required this.info, this.focusNode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String statusLower = info.status.toLowerCase();
    final bool active = info.connected && statusLower == 'active';
    final Color indicatorColor = info.connected
        ? (active ? Colors.green : Colors.red)
        : theme.colorScheme.outline;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            MainPageBridge.focusTvSidebar != null) {
          MainPageBridge.focusTvSidebar!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
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
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(info.icon, color: theme.colorScheme.primary),
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
                            ? (active ? Colors.green : Colors.red)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.caption,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded),
            ],
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
              letterSpacing: 0.2,
              color: accentColor ?? theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i != 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.35,
                    ),
                  ),
                children[i],
              ],
            ],
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

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tag,
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
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
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
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
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
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
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
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
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
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
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
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
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
