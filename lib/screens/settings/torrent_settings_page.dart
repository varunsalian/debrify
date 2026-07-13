import 'package:flutter/material.dart';
import 'indexer_managers_settings_page.dart';
import 'widgets/dynamic_settings_builder.dart';
import 'widgets/settings_widgets.dart';

class TorrentSettingsPage extends StatefulWidget {
  const TorrentSettingsPage({super.key});

  @override
  State<TorrentSettingsPage> createState() => _TorrentSettingsPageState();
}

class _TorrentSettingsPageState extends State<TorrentSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Torrent Settings',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.search_rounded,
                  title: 'Search Engine Defaults',
                  subtitle:
                      'Configure which search engines are enabled by default',
                ),

                const SizedBox(height: 24),

                SettingsSection(
                  title: '',
                  children: [
                    SettingsTile(
                      icon: Icons.manage_search_rounded,
                      title: 'Indexer Managers',
                      subtitle: 'Add Jackett or Prowlarr search sources',
                      onTap: () async {
                        await pushSettingsPage(
                          context,
                          const IndexerManagersSettingsPage(),
                        );
                      },
                    ),
                  ],
                ),

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
                const SettingsInfoBanner(
                  text:
                      'These settings only affect the default state. You can still toggle engines on/off in the search page.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
