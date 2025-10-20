import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/account_service.dart';
import '../services/download_service.dart';
import '../services/torbox_account_service.dart';
import 'settings/real_debrid_settings_page.dart';
import 'settings/torbox_settings_page.dart';

import 'settings/torrent_settings_page.dart';
import '../widgets/shimmer.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = true;
  String? _apiKeySummary;
  String? _torboxSummary;

  @override
  void initState() {
    super.initState();
    _loadSummaries();
  }

  Future<void> _loadSummaries() async {
    final rdKey = await StorageService.getApiKey();
    String rdSummary = 'Not connected';
    if (rdKey != null && rdKey.isNotEmpty) {
      await AccountService.refreshUserInfo();
      final user = AccountService.currentUser;
      rdSummary = user != null ? user.premiumStatusText : 'Connected';
    }

    final torboxKey = await StorageService.getTorboxApiKey();
    String torboxSummary = 'Not connected';
    if (torboxKey != null && torboxKey.isNotEmpty) {
      await TorboxAccountService.refreshUserInfo();
      final torboxUser = TorboxAccountService.currentUser;
      torboxSummary = torboxUser != null
          ? torboxUser.subscriptionStatus
          : 'Connected';
    }

    setState(() {
      _apiKeySummary = rdSummary;
      _torboxSummary = torboxSummary;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Shimmer(width: 120, height: 18),
                  SizedBox(height: 8),
                  Shimmer(width: 220, height: 14),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: const [
                    Shimmer(
                      width: 36,
                      height: 36,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: Shimmer(height: 16)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: const [
                    Shimmer(
                      width: 36,
                      height: 36,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: Shimmer(height: 16)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.settings,
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
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Configure your app preferences',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Torrent Settings
          _SectionTile(
            icon: Icons.search_rounded,
            title: 'Torrent Settings',
            subtitle: 'Search engine defaults',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TorrentSettingsPage()),
              );
              setState(() {});
            },
          ),

          const SizedBox(height: 12),
          _SectionTile(
            icon: Icons.storage_rounded,
            title: 'Clear Download Data',
            subtitle:
                'Remove queued/running history and pending download queue',
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear download data?'),
                  content: const Text(
                    'This will delete all local download records and pending queue entries.\n'
                    'It will not delete files already saved to disk. This is useful for starting fresh during testing.',
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Download data cleared')),
                );
                setState(() {});
              }
            },
          ),

          const SizedBox(height: 12),
          _SectionTile(
            icon: Icons.cleaning_services_rounded,
            title: 'Clear Playback Data',
            subtitle:
                'Remove watched history, resume points, and track choices',
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear playback data?'),
                  content: const Text(
                    'This will delete all saved playback history across movies and series, '
                    'including resume positions, finished markers, and audio/subtitle selections. '
                    'This cannot be undone.',
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Playback data cleared')),
                );
                setState(() {});
              }
            },
          ),

          const SizedBox(height: 12),
          // Real Debrid
          _SectionTile(
            icon: Icons.cloud_download_rounded,
            title: 'Real Debrid Settings',
            subtitle: _apiKeySummary ?? 'Not connected',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RealDebridSettingsPage(),
                ),
              );
              await _loadSummaries();
              setState(() {});
            },
          ),

          const SizedBox(height: 12),
          _SectionTile(
            icon: Icons.flash_on_rounded,
            title: 'Torbox Settings',
            subtitle: _torboxSummary ?? 'Not connected',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TorboxSettingsPage()),
              );
              await _loadSummaries();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        focusColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
