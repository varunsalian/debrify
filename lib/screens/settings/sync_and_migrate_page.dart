import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import 'profile_backup_flows.dart';
import 'widgets/settings_widgets.dart';

/// The manual migration half of Sync and Migrate.
///
/// Continuous Sync Circle enrollment intentionally arrives in later
/// milestones. These actions are explicit, encrypted backup transfers and do
/// not imply background synchronization.
class SyncAndMigratePage extends StatefulWidget {
  const SyncAndMigratePage({super.key, this.onRestored});

  final Future<void> Function()? onRestored;

  @override
  State<SyncAndMigratePage> createState() => _SyncAndMigratePageState();
}

class _SyncAndMigratePageState extends State<SyncAndMigratePage> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('sync_and_migrate');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Sync and Migrate',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SettingsSectionLabel('Migrate'),
                const SizedBox(height: 8),
                SettingsSection(
                  title: '',
                  children: [
                    SettingsTile.spec(
                      SettingsRows.createWebDavBackup,
                      onTap: () => ProfileBackupFlows(
                        context,
                      ).createWebDavProfileBackup(),
                    ),
                    SettingsTile.spec(
                      SettingsRows.restoreWebDavBackup,
                      onTap: () => ProfileBackupFlows(
                        context,
                        onRestored: widget.onRestored,
                      ).restoreWebDavProfileBackup(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Backups are encrypted with the passphrase you choose. '
                  'This is a manual transfer; continuous Sync Circle support '
                  'is not enabled by these actions.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
