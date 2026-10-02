import 'dart:convert' show JsonEncoder, utf8;
import 'package:debrify/screens/settings/profile_backup_flows.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/backup_restore_service.dart';
import 'package:debrify/services/iptv_transfer_payload.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../application/settings_backup_formatting.dart';

/// One Settings State owns this section; dependencies and summaries are borrowed.
class SettingsBackup {
  SettingsBackup(this._deps);
  final ({
    Future<void> Function() createProfileBackup,
    BuildContext Function() context,
    bool Function() mounted,
  })
  _deps;

  Future<void> createBackup() async {
    if (ProfileRuntime.mode == ProfileRuntimeMode.profileCommitted) {
      await _deps.createProfileBackup();
      return;
    }
    final context = _deps.context();
    final app = AppThemeScope.of(context);
    // Build the payload first so we can warn if it's empty.
    final Map<String, dynamic> payload;
    try {
      payload = await BackupRestoreService.buildBackup();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to build the backup')),
      );
      return;
    }

    final summary = BackupRestoreService.summarize(payload);
    if (summary.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to back up — no services are configured.'),
        ),
      );
      return;
    }

    // File-imported IPTV playlists are left out of the payload on purpose —
    // say so rather than let the user discover it after a restore.
    final iptvProviders = await IptvTransferPayload.countPlaylists();

    if (!context.mounted) return;
    var includeCredentials = true;
    var usePassphrase = false;
    final passphraseController = TextEditingController();
    final confirmController = TextEditingController();
    final passphraseFocus = FocusNode(debugLabel: 'backupPassphrase');
    final confirmFocus = FocusNode(debugLabel: 'backupPassphraseConfirmation');
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final passphraseOk =
              !usePassphrase ||
              (passphraseController.text.isNotEmpty &&
                  passphraseController.text == confirmController.text);
          return AlertDialog(
            title: const Text('Create backup'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('The backup will include:'),
                  const SizedBox(height: 8),
                  ...backupSummaryLines(summary).map((line) => Text('• $line')),
                  if (iptvProviders.fileImported > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${iptvProviders.fileImported} IPTV playlist'
                        '${iptvProviders.fileImported == 1 ? '' : 's'} imported from '
                        'a file won\'t be included — re-import the file on the other '
                        'device. Starred channels from them still travel.',
                        style: TextStyle(
                          fontSize: 12,
                          color: app.fade(app.core.tx, 0x99 / 0xFF),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Include credentials'),
                    subtitle: const Text(
                      'Off: share your setup without your accounts. Skips '
                      'anything that embeds them: addons, Xtream providers, '
                      'indexers, starred channels and lists. M3U URLs are '
                      'kept — use a passphrase to protect those.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: includeCredentials,
                    onChanged: (v) =>
                        setDialogState(() => includeCredentials = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Encrypt with a passphrase'),
                    value: usePassphrase,
                    onChanged: (v) => setDialogState(() => usePassphrase = v),
                  ),
                  if (usePassphrase) ...[
                    TvTextField(
                      controller: passphraseController,
                      focusNode: passphraseFocus,
                      obscureText: true,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      keyboardSubmitLabel: 'Next',
                      decoration: const InputDecoration(
                        labelText: 'Passphrase',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (_) => confirmFocus.requestFocus(),
                    ),
                    const SizedBox(height: 8),
                    TvTextField(
                      controller: confirmController,
                      focusNode: confirmFocus,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      keyboardSubmitLabel: 'Save backup',
                      decoration: const InputDecoration(
                        labelText: 'Confirm passphrase',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (_) {
                        if (passphraseOk) Navigator.of(context).pop(true);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (usePassphrase)
                    Text(
                      'Encrypted with your passphrase — if you forget it, '
                      'this backup cannot be opened.',
                      style: TextStyle(
                        fontSize: 12,
                        color: app.fade(app.core.tx, 0x99 / 0xFF),
                      ),
                    )
                  else if (includeCredentials)
                    const Text(
                      'Credentials are stored in plain text. Keep this file '
                      'private and treat it like a password.',
                      style: TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: passphraseOk
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: const Text('Save backup'),
              ),
            ],
          );
        },
      ),
    );

    final passphrase = usePassphrase ? passphraseController.text : null;
    passphraseController.dispose();
    confirmController.dispose();
    passphraseFocus.dispose();
    confirmFocus.dispose();
    if (confirmed != true) return;
    if (!context.mounted) return;

    // The pre-dialog payload was only for the summary — rebuild honoring the
    // include-credentials choice.
    Map<String, dynamic> exportMap = includeCredentials
        ? payload
        : await BackupRestoreService.buildBackup(includeCredentials: false);

    // The pre-dialog summary described the FULL payload — stripping
    // credentials can leave nothing behind (a device configured with only
    // accounts), and restore rejects an empty backup anyway.
    if (!includeCredentials &&
        BackupRestoreService.summarize(exportMap).isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nothing left to back up without credentials — everything on '
            'this device is account data.',
          ),
        ),
      );
      return;
    }

    if (passphrase != null && passphrase.isNotEmpty) {
      if (!context.mounted) return;
      // Captured BEFORE the await: the modal lives on the root navigator and
      // must be popped even if this screen unmounts while Argon2id runs —
      // a mounted-check first would strand an undismissable dialog.
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      // Argon2id takes seconds on TV hardware — show progress.
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
                Expanded(child: Text('Encrypting backup…')),
              ],
            ),
          ),
        ),
      );
      try {
        exportMap = await BackupRestoreService.encryptBackup(
          exportMap,
          passphrase,
        );
      } catch (_) {
        rootNavigator.pop();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to encrypt the backup')),
        );
        return;
      }
      rootNavigator.pop();
      if (!context.mounted) return;
    }

    final jsonContent = const JsonEncoder.withIndent('  ').convert(exportMap);
    final bytes = Uint8List.fromList(utf8.encode(jsonContent));
    final ts = DateTime.now();
    final fileName =
        'debrify-backup-${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}-${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}.json';

    try {
      final savedPath = await ProfileBackupFlows(
        context,
      ).saveBackupFile(fileName: fileName, bytes: bytes);
      if (!context.mounted || savedPath == null) return;
      // On Android, savedPath may be a content:// URI from the Storage
      // Access Framework — show it raw so the user has at least a
      // breadcrumb of where the backup went.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup saved to $savedPath'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save the backup')),
      );
    }
  }
}
