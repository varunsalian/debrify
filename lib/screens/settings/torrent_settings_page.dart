import 'package:flutter/material.dart';
import 'indexer_managers_settings_page.dart';
import 'widgets/dynamic_settings_builder.dart';

class TorrentSettingsPage extends StatefulWidget {
  const TorrentSettingsPage({super.key});

  @override
  State<TorrentSettingsPage> createState() => _TorrentSettingsPageState();
}

class _TorrentSettingsPageState extends State<TorrentSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Torrent Settings'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(context),

            const SizedBox(height: 24),

            _buildIndexerManagersCard(context),

            const SizedBox(height: 16),

            // Use DynamicSettingsBuilder instead of hardcoded settings
            DynamicSettingsBuilder(
              onSettingsChanged: () {
                // Optionally refresh state if needed
                setState(() {});
              },
            ),

            const SizedBox(height: 16),

            // Info message
            _buildInfoMessage(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
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
              Icons.search_rounded,
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
                  'Search Engine Defaults',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure which search engines are enabled by default',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexerManagersCard(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.manage_search_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('Indexer Managers'),
        subtitle: const Text('Add Jackett or Prowlarr search sources'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const IndexerManagersSettingsPage(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoMessage(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Theme.of(context).colorScheme.secondary,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'These settings only affect the default state. You can still toggle engines on/off in the search page.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
