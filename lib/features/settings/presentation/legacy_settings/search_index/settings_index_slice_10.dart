import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'settings_index_builder.dart';

extension SettingsIndexSlice10 on SettingsIndexBuilder {
  List<SettingsSearchEntry> indexSlice10() {
    return [
      // Downloads
      if (deps.downloadLocationSupported())
        nav(
          SettingsRows.downloadLocation,
          'Data & Backup',
          deps.openDownloadLocationSettings,
          subtitle: summaries.downloadLocationSubtitle,
          keywords: const [
            'sd card',
            'folder',
            'external storage',
            'saf',
            'location',
            'path',
            'directory',
            'sd',
            'choose folder',
            'reset to default',
            'another drive',
          ],
        ),

      // Maintenance
      nav(
        SettingsRows.clearDownloads,
        'Data & Backup',
        deps.clearDownloadData,
        keywords: const ['queue', 'history', 'clear', 'remove'],
      ),
      nav(
        SettingsRows.clearPlayback,
        'Data & Backup',
        deps.clearPlaybackData,
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
        deps.createBackup,
        keywords: const [
          'export',
          'save',
          'addons',
          'search engines',
          'all profiles',
          'shared connections',
          'encrypted',
          'password',
          'passphrase',
          'minimum 8 characters',
          'recovery code',
        ],
      ),
      nav(
        SettingsRows.restoreBackup,
        'Data & Backup',
        deps.restoreBackup,
        keywords: const [
          'import',
          'load',
          'encrypted',
          'password',
          'passphrase',
          'unlock backup',
          'admin pin',
          'confirm admin pin',
          'profiles',
          'connections',
        ],
      ),
      if (summaries.diagnosticExportVisible)
        nav(
          SettingsRows.exportDiagnosticLogs,
          'Data & Backup',
          deps.exportDiagnosticLogs,
          keywords: const [
            'logs',
            'diagnostics',
            'debug',
            'crash',
            'support',
            'android tv',
            'last two hours',
          ],
        ),
    ];
  }
}
