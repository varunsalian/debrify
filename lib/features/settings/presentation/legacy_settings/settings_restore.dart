import 'dart:io' show File;
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/account_service.dart';
import 'package:debrify/services/alldebrid_account_service.dart';
import 'package:debrify/services/backup_restore_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/premiumize_account_service.dart';
import 'package:debrify/services/profiles/portable_profile_package.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/torbox_account_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../application/settings_backup_formatting.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsRestore {
  SettingsRestore(this._deps);
  final ({
    Future<void> Function() loadSummaries,
    Future<void> Function() restoreProfileBackup,
    BuildContext Function() context,
    bool Function() mounted,
  })
  _deps;

  /// Passphrase prompt loop for an encrypted backup envelope. Returns the
  /// decrypted inner payload, or null when the user cancels. A wrong
  /// passphrase re-shows the prompt with an inline error instead of aborting.
  Future<Map<String, dynamic>?> promptAndDecryptBackup(
    Map<String, dynamic> envelope,
  ) async {
    String? errorText;
    while (true) {
      if (!_deps.mounted()) return null;
      final controller = TextEditingController();
      final context = _deps.context();
      final entered = await showSettingsDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Backup is encrypted'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (envelope['createdAt'] is String)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Created: ${envelope['createdAt']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                TvTextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  keyboardSubmitLabel: 'Unlock',
                  decoration: InputDecoration(
                    labelText: 'Passphrase',
                    errorText: errorText,
                  ),
                  onSubmitted: (value) => Navigator.of(context).pop(value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Unlock'),
              ),
            ],
          ),
        ),
      );
      controller.dispose();
      if (entered == null || entered.isEmpty) return null;
      if (!context.mounted) return null;

      // Captured BEFORE the await so the modal is popped even if this screen
      // unmounts while the KDF runs (see _createBackup's encrypt block).
      final rootNavigator = Navigator.of(context, rootNavigator: true);
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
                Expanded(child: Text('Unlocking backup…')),
              ],
            ),
          ),
        ),
      );
      try {
        final inner = await BackupRestoreService.decryptBackup(
          envelope,
          entered,
        );
        rootNavigator.pop();
        if (!context.mounted) return null;
        return inner;
      } on BackupPassphraseException {
        rootNavigator.pop();
        if (!context.mounted) return null;
        errorText = 'Wrong passphrase — try again';
      } on FormatException {
        rootNavigator.pop();
        if (!context.mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The backup format is invalid')),
        );
        return null;
      }
    }
  }

  Future<void> restoreBackup() async {
    if (ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted) {
      await _deps.restoreProfileBackup();
      return;
    }
    final context = _deps.context();
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final FilePickerResult? pick;
    try {
      // FileType.any instead of custom: Android's MIME mapping for `json` is
      // unreliable and throws PlatformException("Unsupported filter") on many
      // devices, leaving the backup unselectable. The contents are validated by
      // BackupRestoreService.parse below, so no extension filter is needed.
      pick = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose Debrify backup file',
        type: FileType.any,
        withData: false,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the file picker')),
      );
      return;
    }

    if (pick == null || pick.files.isEmpty) return;
    final file = pick.files.first;

    // FileType.any lets the user pick anything. Reject an implausibly large
    // file before opening it so a stray huge selection cannot be allocated.
    // Sized so the app always accepts what its own export can produce: a
    // passphrase-encrypted envelope base64-inflates the payload by ~4/3, so an
    // IPTV-heavy ~20 MiB backup arrives here at ~27 MiB.
    if (file.size > 40 * 1024 * 1024) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That file is too large to be a Debrify backup.'),
        ),
      );
      return;
    }

    final String content;
    try {
      if (file.path == null) {
        throw Exception('Could not read backup file contents');
      }
      final selected = File(file.path!);
      content = await PortableProfilePackage.readBoundedUtf8(
        selected.openRead(),
        maxBytes: 40 * 1024 * 1024,
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to read the backup file')),
      );
      return;
    }

    Map<String, dynamic> payload;
    try {
      payload = BackupRestoreService.parse(content);
    } on FormatException catch (error) {
      if (!context.mounted) return;
      final looksLikeProfilePackage =
          content.contains('"format":"debrify-profile-package"') ||
          content.contains('"format": "debrify-profile-package"');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            looksLikeProfilePackage
                ? 'This is a profile backup. Enable profiles or update to a build that supports profile restore.'
                : error.message,
          ),
        ),
      );
      return;
    }

    if (BackupRestoreService.isEncrypted(payload)) {
      final inner = await promptAndDecryptBackup(payload);
      if (inner == null) return; // Cancelled or unrecoverable.
      payload = inner;
    }

    final summary = BackupRestoreService.summarize(payload);
    if (summary.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup contains no data to restore.')),
      );
      return;
    }

    if (!context.mounted) return;
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
                  style: TextStyle(
                    fontSize: 12,
                    color: app.fade(app.core.tx, 0x99 / 0xFF),
                  ),
                ),
              ),
            const Text('This backup contains:'),
            const SizedBox(height: 8),
            ...backupSummaryLines(summary).map((line) => Text('• $line')),
            const SizedBox(height: 12),
            const Text(
              'Saved credentials (Real-Debrid, Torbox, Premiumize, AllDebrid, PikPak, Trakt, Simkl) will '
              'be overwritten. Addons, search engines, WebDAV servers, '
              'indexer managers, and IPTV providers you already have are kept '
              'as-is. IPTV favorites and lists merge into what\'s here — '
              'nothing is removed.',
              style: TextStyle(fontSize: 12),
            ),
            if (summary.addonCount > 0 || summary.searchEngineCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Restoring addons and search engines needs a network '
                  'connection.',
                  style: TextStyle(
                    fontSize: 12,
                    color: app.fade(app.core.tx, 0x99 / 0xFF),
                  ),
                ),
              ),
            if (summary.webDavServerCount > 0 ||
                summary.indexerManagerCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'WebDAV and Jackett/Prowlarr URLs may be local-network '
                  'only — they won\'t work on a different network.',
                  style: TextStyle(
                    fontSize: 12,
                    color: app.fade(app.core.tx, 0x99 / 0xFF),
                  ),
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
    if (!context.mounted) return;

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
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Restore failed')));
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final msg = formatRestoreReport(report);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: report.hasAnyFailure ? t.warning : null,
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
    await _deps.loadSummaries();

    // Tell the rest of the app — navbar, home tabs, search surfaces — that
    // integrations changed so they rebuild against the restored services
    // (same hook the individual settings pages use after a credential edit).
    MainPageBridge.notifyIntegrationChanged();
  }
}
