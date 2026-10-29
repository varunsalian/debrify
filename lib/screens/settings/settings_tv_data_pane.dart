// Settings (TV) › Data & Backup: the pane's rows.
//
// Focus nodes are claimed from the pane pool in row order, so the optional
// rows (download location, storage usage, diagnostics) never shift the
// indices of the rows after them and Up/Down wiring stays contiguous.
import 'package:flutter/material.dart';

import 'widgets/settings_widgets.dart';

List<Widget> settingsTvDataBackupRows({
  required List<FocusNode> nodes,
  required Future<void> Function()? onOpenDownloadLocation,
  required String downloadLocationSubtitle,
  required Future<void> Function() onClearDownloads,
  required Future<void> Function() onClearPlayback,
  required Future<void> Function()? onOpenStorageUsage,
  required Future<void> Function() onCreateBackup,
  required Future<void> Function() onRestoreBackup,
  required Future<void> Function()? onExportDiagnosticLogs,
}) {
  var paneIdx = 0;
  FocusNode nextNode() => nodes[paneIdx++];
  return [
    if (onOpenDownloadLocation != null) ...[
      const SettingsSectionLabel('Downloads'),
      SettingsSection(
        title: '',
        children: [
          SettingsTile.spec(
            SettingsRows.downloadLocation,
            subtitle: downloadLocationSubtitle,
            onTap: onOpenDownloadLocation,
            focusNode: nextNode(),
          ),
        ],
      ),
      const SizedBox(height: 18),
    ],
    const SettingsSectionLabel('Maintenance'),
    SettingsSection(
      title: '',
      children: [
        SettingsTile.spec(
          SettingsRows.clearDownloads,
          onTap: onClearDownloads,
          focusNode: nextNode(),
        ),
        SettingsTile.spec(
          SettingsRows.clearPlayback,
          onTap: onClearPlayback,
          focusNode: nextNode(),
        ),
        if (onOpenStorageUsage case final open?)
          SettingsTile.spec(
            SettingsRows.storageUsage,
            onTap: open,
            focusNode: nextNode(),
          ),
      ],
    ),
    const SizedBox(height: 18),
    const SettingsSectionLabel('Backup & Restore'),
    SettingsSection(
      title: '',
      children: [
        SettingsTile.spec(
          SettingsRows.createBackup,
          onTap: onCreateBackup,
          focusNode: nextNode(),
        ),
        SettingsTile.spec(
          SettingsRows.restoreBackup,
          onTap: onRestoreBackup,
          focusNode: nextNode(),
        ),
      ],
    ),
    if (onExportDiagnosticLogs != null) ...[
      const SizedBox(height: 18),
      const SettingsSectionLabel('Diagnostics'),
      SettingsSection(
        title: '',
        children: [
          SettingsTile.spec(
            SettingsRows.exportDiagnosticLogs,
            onTap: onExportDiagnosticLogs,
            focusNode: nextNode(),
          ),
        ],
      ),
    ],
  ];
}
