// Settings (classic layout) › Data & Backup: one section holding the
// download folder, maintenance, backup and diagnostics rows.
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'settings_layout.dart';

class SettingsClassicDataSection extends StatelessWidget {
  const SettingsClassicDataSection({super.key, required this.layout});

  final SettingsLayout layout;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Data & Backup',
      children: [
        if (layout.onOpenDownloadLocation != null)
          SettingsTile.spec(
            SettingsRows.downloadLocation,
            subtitle: layout.downloadLocationSubtitle,
            onTap: layout.onOpenDownloadLocation!,
          ),
        SettingsTile.spec(
          SettingsRows.clearDownloads,
          onTap: layout.onClearDownloads,
        ),
        SettingsTile.spec(
          SettingsRows.clearPlayback,
          onTap: layout.onClearPlayback,
        ),
        if (layout.onOpenStorageUsage case final open?)
          SettingsTile.spec(SettingsRows.storageUsage, onTap: open),
        SettingsTile.spec(
          SettingsRows.createBackup,
          onTap: layout.onCreateBackup,
        ),
        SettingsTile.spec(
          SettingsRows.restoreBackup,
          onTap: layout.onRestoreBackup,
        ),
        if (layout.onExportDiagnosticLogs != null)
          SettingsTile.spec(
            SettingsRows.exportDiagnosticLogs,
            onTap: layout.onExportDiagnosticLogs!,
          ),
      ],
    );
  }
}
