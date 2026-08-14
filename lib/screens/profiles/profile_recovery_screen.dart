import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/backup_restore_service.dart';
import '../../services/profiles/device_key_provider.dart';
import '../../services/profiles/legacy_backup_adapter.dart';
import '../../services/profiles/portable_profile_package.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/profile_device_reset_service.dart';
import '../../services/profiles/profile_restore_coordinator.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../utils/platform_util.dart';
import '../../widgets/tv_text_field.dart';

/// Privacy-safe startup surface used when a one-way committed installation can
/// no longer mount its registry. It deliberately initializes none of the
/// normal app services or legacy stores before the user chooses a recovery.
class ProfileRecoveryScreen extends StatefulWidget {
  final Future<void> Function() onRecovered;
  final Future<void> Function() onResetComplete;
  final bool forceTvSafeInput;

  const ProfileRecoveryScreen({
    super.key,
    required this.onRecovered,
    required this.onResetComplete,
    this.forceTvSafeInput = false,
  });

  @override
  State<ProfileRecoveryScreen> createState() => _ProfileRecoveryScreenState();
}

class _ProfileRecoveryScreenState extends State<ProfileRecoveryScreen> {
  bool _busy = false;
  String? _status;

  Future<String?> _promptSecret(String title, String message) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            TvTextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              forceTvKeyboard: widget.forceTvSafeInput,
              textInputAction: TextInputAction.done,
              keyboardSubmitLabel: 'Continue',
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
              decoration: const InputDecoration(labelText: 'Passphrase'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value?.trim().isEmpty == true ? null : value;
  }

  Future<String?> _linuxVaultPassphrase() async {
    if (!Platform.isLinux || DeviceKeyProvider.isUnlocked) return null;
    return _promptSecret(
      'Unlock device vault',
      await DeviceKeyProvider.linuxHasWrappedKey()
          ? 'Enter the existing device-vault passphrase. This is separate from the backup passphrase.'
          : 'Create a device-vault passphrase for the recovered profiles. This is separate from the backup passphrase.',
    );
  }

  Future<void> _run(Future<String> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final message = await operation();
      if (mounted) setState(() => _status = message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Recovery did not complete. No legacy or quarantined profile data was exposed.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    await _run(() async {
      final pick = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose a Debrify backup',
        type: FileType.any,
        withData: false,
      );
      if (pick == null || pick.files.isEmpty) return 'Restore cancelled.';
      final selected = pick.files.single;
      if (selected.size > PortableProfilePackage.maxEnvelopeBytes ||
          selected.path == null) {
        throw const FormatException('Backup is not locally readable');
      }
      final source = await PortableProfilePackage.readBoundedUtf8(
        File(selected.path!).openRead(),
      );
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Backup must be an object');
      }

      final PortableProfilePackage package;
      if (decoded['format'] == 'debrify-profile-package') {
        if (decoded['encrypted'] == true) {
          if (!mounted) return 'Restore cancelled.';
          final passphrase = await _promptSecret(
            'Backup passphrase',
            'Enter the passphrase used when this backup was created.',
          );
          if (passphrase == null) return 'Restore cancelled.';
          package = await PortableProfilePackage.decrypt(decoded, passphrase);
        } else {
          package = await PortableProfilePackage.decodeMap(decoded);
        }
      } else {
        var legacy = BackupRestoreService.parse(source);
        if (BackupRestoreService.isEncrypted(legacy)) {
          if (!mounted) return 'Restore cancelled.';
          final passphrase = await _promptSecret(
            'Backup passphrase',
            'Enter the passphrase used by the older Debrify backup.',
          );
          if (passphrase == null) return 'Restore cancelled.';
          legacy = await BackupRestoreService.decryptBackup(legacy, passphrase);
        }
        package = LegacyBackupAdapter.adapt(legacy);
      }

      final linuxPassphrase = await _linuxVaultPassphrase();
      if (Platform.isLinux &&
          !DeviceKeyProvider.isUnlocked &&
          linuxPassphrase == null) {
        return 'Restore cancelled.';
      }
      final registry = await ProfileBootstrap.initializeRecoveryAuthority(
        linuxVaultPassphrase: linuxPassphrase,
      );
      final authorization = await ProfileAuthorizationContext.capture(registry);
      final coordinator = ProfileRestoreCoordinator(
        registry: registry,
        cipher: DeviceKeyProvider.cipher,
      );
      if (package.mode == 'deviceGraph') {
        await coordinator.restoreDeviceGraph(
          package: package,
          authorization: authorization,
        );
      } else {
        await coordinator.restore(
          package: package,
          destinationProfileId: ProfileRuntime.capture().profileId,
          authorization: authorization,
          replacePreferences: true,
        );
      }
      await widget.onRecovered();
      return 'Backup restored.';
    });
  }

  Future<void> _continueWithRecoveryAdmin() async {
    await _run(() async {
      final linuxPassphrase = await _linuxVaultPassphrase();
      if (Platform.isLinux &&
          !DeviceKeyProvider.isUnlocked &&
          linuxPassphrase == null) {
        return 'Recovery cancelled.';
      }
      await ProfileBootstrap.initializeRecoveryAuthority(
        linuxVaultPassphrase: linuxPassphrase,
      );
      await widget.onRecovered();
      return 'Recovery Admin created.';
    });
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Erase private app data?'),
        content: const Text(
          'This removes profiles, credentials, settings, jobs, and private app data. Completed media files are retained. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Erase private data'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      final linuxPassphrase = await _linuxVaultPassphrase();
      if (Platform.isLinux &&
          !DeviceKeyProvider.isUnlocked &&
          linuxPassphrase == null) {
        return 'Reset cancelled.';
      }
      final registry = await ProfileBootstrap.initializeRecoveryAuthority(
        linuxVaultPassphrase: linuxPassphrase,
      );
      final authorization = await ProfileAuthorizationContext.capture(registry);
      await ProfileDeviceResetService.reset(
        registry: registry,
        authorization: authorization,
      );
      await widget.onResetComplete();
      return 'Private app data erased.';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.health_and_safety_outlined, size: 56),
                const SizedBox(height: 20),
                Text(
                  'Profile recovery required',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Debrify could not safely open the committed profile registry. Legacy data will not be mounted. A damaged registry is moved aside when you begin recovery, so it remains available for diagnostics.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                if (!PlatformUtil.isTvOS)
                  FilledButton.icon(
                    onPressed: _busy ? null : _restoreBackup,
                    autofocus: widget.forceTvSafeInput,
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore a backup'),
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _continueWithRecoveryAdmin,
                  autofocus: widget.forceTvSafeInput && PlatformUtil.isTvOS,
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: Text(
                    PlatformUtil.isTvOS
                        ? 'Start Recovery Admin for Remote restore'
                        : 'Continue with a new Recovery Admin',
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _busy ? null : _reset,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Erase private app data'),
                ),
                if (_busy) ...[
                  const SizedBox(height: 20),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Text(_status!, textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
