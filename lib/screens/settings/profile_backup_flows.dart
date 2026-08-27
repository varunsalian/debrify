import 'dart:async';
import 'dart:typed_data';
import 'dart:io' show Directory, File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'
    show getExternalStorageDirectory;

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/backup_restore_service.dart';
import '../../services/profiles/connection_resource_service.dart';
import '../../services/profiles/device_key_provider.dart';
import '../../services/profiles/legacy_backup_adapter.dart';
import '../../services/profiles/portable_profile_package.dart';
import '../../services/profiles/profile_app_lifecycle_participant.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/profile_lifecycle.dart';
import '../../services/profiles/profile_package_service.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_restore_coordinator.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../utils/app_storage.dart';
import '../../utils/platform_util.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';
import '../../app/wiring.dart';

/// The profile backup/restore user flows, extracted from the settings screen
/// so the Profiles hub can offer them at its first level. Behavior is
/// identical to the settings-screen originals; [onRestored] replaces the
/// screen-specific refresh the settings page used to run inline.
class ProfileBackupFlows {
  const ProfileBackupFlows(this.context, {this.onRestored});

  final BuildContext context;
  final Future<void> Function()? onRestored;

  Future<void> createProfileBackup() async {
    try {
      await _createProfileBackupUnchecked();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_profileBackupError(error, creating: true))),
      );
    }
  }

  Future<void> _createProfileBackupUnchecked() async {
    if (PlatformUtil.isTvOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Apple TV profile backups use the authenticated Remote transfer flow.',
          ),
        ),
      );
      return;
    }
    final registry = ProfileBootstrap.registry;
    final authorization = await ProfileAuthorizationContext.capture(registry);
    final actor = await authorization.validate(registry);
    if (!actor.allows(ProfileFeature.backupRestore)) {
      throw StateError('This profile is not allowed to create backups');
    }
    final canExportAll =
        actor.role == UserProfileRole.admin &&
        actor.allows(ProfileFeature.manageProfiles);
    final passphrase = TextEditingController();
    var allProfiles = false;
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(allProfiles ? 'Back up all profiles' : 'Back up profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Creates an encrypted profile package. Downloads, recordings, '
                'active jobs, device paths, and remote pairings are not '
                'included.',
              ),
              const SizedBox(height: 12),
              if (canExportAll)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All profiles and shared connections'),
                  subtitle: const Text(
                    'Admin-only graph backup. Imported profile and resource IDs are remapped on restore.',
                  ),
                  value: allProfiles,
                  onChanged: (value) =>
                      setDialogState(() => allProfiles = value),
                ),
              TvTextField(
                  controller: passphrase,
                  obscureText: true,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  keyboardSubmitLabel: 'Create backup',
                  decoration: const InputDecoration(
                    labelText: 'Backup passphrase (minimum 8 characters)',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (_) {
                    if (passphrase.text.length >= 8) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: passphrase.text.length >= 8
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('Create backup'),
            ),
          ],
        ),
      ),
    );
    final password = passphrase.text;
    passphrase
      ..clear()
      ..dispose();
    if (confirmed != true) return;
    if (allProfiles && !await reauthenticateSensitiveProfile(actor)) return;

    final resourceService = ConnectionResourceService(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
    );
    final service = ProfilePackageService(
      registry: registry,
      resources: resourceService,
    );
    var packageOmissions = const <String, dynamic>{};
    final bytes = await _profileBackupProgress<Uint8List>(
      'Packaging profile data…',
      (setStage) async {
        final package = allProfiles
            ? await service.exportAllProfiles(
                context: authorization,
                includeSecrets: true,
              )
            : await service.exportProfile(
                context: authorization,
                scope: ProfileRuntime.capture(),
                includeSecrets: true,
                sanitized: false,
              );
        packageOmissions = package.omissions;
        setStage('Encrypting backup — this can take a minute…');
        return PortableProfilePackage.encodeEncryptedBytes(package, password);
      },
    );
    final stamp = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final saved = await saveBackupFile(
      dialogTitle: 'Save Debrify profile backup',
      fileName: allProfiles
          ? 'debrify-profiles-$stamp.json'
          : 'debrify-profile-$stamp.json',
      bytes: bytes,
    );
    if (!context.mounted || saved == null) return;
    final skippedDatabases = packageOmissions['libraryDatabasesTooLarge'];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skippedDatabases is String
              ? '${allProfiles ? 'All-profile backup' : 'Profile backup'} saved. '
                    'Too large to include: $skippedDatabases'
              : allProfiles
              ? 'All-profile backup saved'
              : 'Profile backup saved',
        ),
        duration: skippedDatabases is String
            ? const Duration(seconds: 8)
            : const Duration(seconds: 4),
      ),
    );
  }

  /// Saves backup bytes to a user-chosen location — or the best local one.
  ///
  /// Android TV builds ship no ACTION_CREATE_DOCUMENT handler, so the system
  /// save dialog behind [FilePicker.saveFile] just raises an OS toast
  /// ("you don't have an app to do this") and nothing is written. On TV —
  /// or anywhere the dialog errors — the bytes are written to the most
  /// retrievable writable folder instead (public Download, then the app's
  /// browsable external dir, then app documents) and the full path is shown
  /// in a dialog the user can act on.
  ///
  /// Returns the saved path, or null when the user cancelled the system
  /// dialog. Throws [StateError] when no location could be written.
  Future<String?> saveBackupFile({
    required String dialogTitle,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (!PlatformUtil.isAndroidTvCached) {
      try {
        final savedPath = await FilePicker.platform.saveFile(
          dialogTitle: dialogTitle,
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const <String>['json'],
          bytes: bytes,
        );
        if (savedPath == null) return null;
        // On desktop platforms saveFile returns the chosen path without
        // writing the bytes itself — write defensively if the file is
        // missing or empty.
        try {
          final file = File(savedPath);
          if (!await file.exists() || (await file.length()) == 0) {
            await file.writeAsBytes(bytes, flush: true);
          }
        } catch (_) {
          // saveFile already handled writing on this platform.
        }
        return savedPath;
      } catch (_) {
        // No usable system dialog here either — fall through to local write.
      }
    }

    final candidates = <Directory>[
      // Public Download first: reachable by every file manager. The write
      // simply fails without storage permission or under scoped storage,
      // and the ladder moves on.
      if (Platform.isAndroid) Directory('/storage/emulated/0/Download'),
      if (Platform.isAndroid)
        ...await getExternalStorageDirectory().then(
          (dir) => [if (dir != null) dir],
          onError: (_) => const <Directory>[],
        ),
      await AppStorage.documents(),
    ];
    String? savedPath;
    for (final dir in candidates) {
      try {
        if (!await dir.exists()) continue;
        var file = File('${dir.path}/$fileName');
        if (await file.exists()) {
          // The system dialog would have warned before overwriting; a plain
          // write won't, so a second same-day backup gets a time suffix.
          final now = DateTime.now();
          final suffix = [
            now.hour,
            now.minute,
            now.second,
          ].map((part) => part.toString().padLeft(2, '0')).join();
          file = File(
            '${dir.path}/${fileName.replaceFirst('.json', '-$suffix.json')}',
          );
        }
        await file.writeAsBytes(bytes, flush: true);
        if (await file.length() == bytes.length) {
          savedPath = file.path;
          break;
        }
      } catch (_) {
        // Not writable — try the next candidate.
      }
    }
    if (savedPath == null) {
      throw StateError('Could not save the backup on this device');
    }
    if (context.mounted) {
      await showSettingsDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Backup saved on this device'),
          content: Text(
            'The system save dialog is not available here, so the backup '
            'was written to:\n\n$savedPath\n\nCopy it off with a file '
            'manager, USB, or over the network.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    return savedPath;
  }

  /// Modal stage indicator for backup/restore work. The crypto and
  /// whole-envelope parse stages run in a worker isolate so the spinner
  /// animates through them (packaging still reads databases on this isolate);
  /// [setStage] swaps the label between phases without re-opening the dialog.
  /// The dialog dismisses itself through its own context, so it cannot leak
  /// on the root navigator if this State unmounts mid-run.
  Future<T> _profileBackupProgress<T>(
    String initialStage,
    Future<T> Function(void Function(String) setStage) run,
  ) async {
    final stage = ValueNotifier<String>(initialStage);
    final done = ValueNotifier<bool>(false);
    unawaited(
      showSettingsDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BackupProgressDialog(stage: stage, done: done),
      ),
    );
    try {
      return await run((value) => stage.value = value);
    } finally {
      done.value = true;
    }
  }

  Future<void> restoreProfileBackup() async {
    try {
      await _restoreProfileBackupUnchecked();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_profileBackupError(error, creating: false))),
      );
    }
  }

  String _profileBackupError(Object error, {required bool creating}) {
    if (error is FormatException) {
      return error.message;
    }
    if (error is StateError) return error.message;
    return creating
        ? 'Could not create the profile backup'
        : 'Profile restore failed; existing data is unchanged';
  }

  Future<void> _restoreProfileBackupUnchecked() async {
    if (PlatformUtil.isTvOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Apple TV restores profile packages through authenticated Remote transfer.',
          ),
        ),
      );
      return;
    }
    final pick = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a Debrify backup',
      type: FileType.any,
      withData: false,
    );
    if (pick == null || pick.files.isEmpty) return;
    final file = pick.files.single;
    if (file.size > PortableProfilePackage.maxEnvelopeBytes) {
      throw const FormatException('Backup exceeds the supported size limit');
    }
    final path = file.path;
    if (path == null) {
      throw const FormatException('Selected backup is not locally readable');
    }
    final probe = await _profileBackupProgress(
      'Reading backup…',
      (_) => PortableProfilePackage.probeFile(path),
    );

    PortableProfilePackage package;
    if (probe.isProfilePackage) {
      if (probe.encrypted) {
        final unlocked = await _promptAndDecryptProfilePackage(path);
        if (unlocked == null) return;
        package = unlocked;
      } else {
        package = await _profileBackupProgress(
          'Checking backup…',
          (_) => PortableProfilePackage.decodeFile(path),
        );
      }
    } else {
      var legacy = BackupRestoreService.parse(probe.legacySource!);
      if (BackupRestoreService.isEncrypted(legacy)) {
        final unlocked = await _promptAndDecryptBackup(legacy);
        if (unlocked == null) return;
        legacy = unlocked;
      }
      package = LegacyBackupAdapter.adapt(legacy);
    }

    final registry = ProfileBootstrap.registry;
    final profile = await registry.getProfile(
      ProfileRuntime.capture().profileId,
    );
    if (profile == null || !context.mounted) return;
    final graphRestore = package.mode == 'deviceGraph';
    final authorization = await ProfileAuthorizationContext.capture(registry);
    final actor = await authorization.validate(registry);
    if (graphRestore &&
        (actor.role != UserProfileRole.admin ||
            !actor.allows(ProfileFeature.manageProfiles))) {
      throw StateError('Only an Admin can restore an all-profile backup');
    }
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          graphRestore
              ? 'Import ${package.profiles.length} profiles?'
              : 'Restore profile backup?',
        ),
        content: Text(
          graphRestore
              ? 'The profiles and their shared connection graph are staged under new IDs, then made visible together. Your current Admin remains the recovery profile. Existing profiles are not overwritten. Profiles keep their PINs when the backup carries them. Media, jobs, paths, and remote pairings are not restored.'
              : 'Destination: ${profile.name}\n\nA complete shadow generation will be verified first. Existing data remains visible if staging fails. Imported accounts become new resources; downloads, recordings, jobs, PINs, paths, and pairings are not restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              graphRestore ? 'Import profiles' : 'Restore to ${profile.name}',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (graphRestore && !await reauthenticateSensitiveProfile(actor)) return;

    final coordinator = ProfileRestoreCoordinator(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
      lifecycleParticipants: <ProfileLifecycleParticipant>[
        ProfileAppLifecycleParticipant(pikpak: AppServices.pikpak),
      ],
    );
    if (graphRestore) {
      final report = await _profileBackupProgress(
        'Importing profiles — this can take a few minutes…',
        (_) => coordinator.restoreDeviceGraph(
          package: package,
          authorization: authorization,
        ),
      );
      if (!context.mounted) return;
      await onRestored?.call();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${report.profilesImported} profiles, '
            '${report.resourcesImported} connections and '
            '${report.grantsImported} grants.'
            '${report.pinResetsRequired == 0 ? '' : ' ${report.pinResetsRequired} profile(s) require a new PIN.'}',
          ),
          duration: const Duration(seconds: 7),
        ),
      );
      return;
    }
    final report = await _profileBackupProgress(
      'Restoring — verifying and staging data, this can take a few minutes…',
      (_) => coordinator.restore(
        package: package,
        destinationProfileId: profile.id,
        authorization: authorization,
      ),
    );
    if (!context.mounted) return;
    await onRestored?.call();
    final omitted = report.omissions.entries
        .where((entry) => entry.value != null && entry.value != 0)
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Restored generation ${report.publishedGeneration}: '
          '${report.preferencesApplied} settings and '
          '${report.resourcesImported} connections. '
          '${omitted.isEmpty ? '' : 'Skipped: $omitted. '}'
          'Media/jobs were not restored.',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<PortableProfilePackage?> _promptAndDecryptProfilePackage(
    String path,
  ) async {
    String? errorText;
    while (true) {
      final password = await _promptProfileBackupPassphrase(
        errorText: errorText,
      );
      if (password == null) return null;
      try {
        return await _profileBackupProgress(
          'Unlocking backup…',
          (_) => PortableProfilePackage.decryptFile(path, password),
        );
      } on FormatException catch (error) {
        if (error.message == 'Wrong passphrase or tampered backup') {
          errorText = 'Wrong passphrase or damaged backup — try again';
          continue;
        }
        rethrow;
      }
    }
  }

  Future<String?> _promptProfileBackupPassphrase({String? errorText}) async {
    final controller = TextEditingController();
    final result = await showSettingsDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlock backup'),
        content: TvTextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          textInputAction: TextInputAction.done,
          keyboardSubmitLabel: 'Unlock',
          decoration: InputDecoration(
            labelText: 'Passphrase',
            errorText: errorText,
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    controller
      ..clear()
      ..dispose();
    return result?.isEmpty == true ? null : result;
  }

  Future<bool> reauthenticateSensitiveProfile(UserProfile profile) async {
    if (!profile.hasPin) return true;
    final controller = TextEditingController();
    final pin = await showSettingsDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm Admin PIN'),
        content: TvTextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          keyboardSubmitLabel: 'Confirm',
          decoration: const InputDecoration(labelText: 'PIN'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    controller
      ..clear()
      ..dispose();
    if (pin == null) return false;
    final result = await ProfilePinService(
      registry: ProfileBootstrap.registry,
    ).verify(profile.id, pin);
    if (result.result == ProfilePinResult.verified) return true;
    if (context.mounted) {
      final message = switch (result.result) {
        ProfilePinResult.locked => 'PIN is temporarily locked',
        ProfilePinResult.resetRequired => 'This PIN requires an Admin reset',
        ProfilePinResult.notConfigured => 'PIN is not configured',
        _ => 'PIN confirmation failed',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    return false;
  }

  /// Passphrase prompt loop for an encrypted backup envelope. Returns the
  /// decrypted inner payload, or null when the user cancels. A wrong
  /// passphrase re-shows the prompt with an inline error instead of aborting.
  Future<Map<String, dynamic>?> _promptAndDecryptBackup(
    Map<String, dynamic> envelope,
  ) async {
    String? errorText;
    while (true) {
      if (!context.mounted) return null;
      final controller = TextEditingController();
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
}

/// Busy dialog for [_profileBackupProgress]: undismissable while work runs,
/// and closed through its OWN context when `done` fires — the caller's State
/// may unmount mid-run, and an orphaned `canPop: false` modal on the root
/// navigator would wedge the whole app.
class _BackupProgressDialog extends StatefulWidget {
  const _BackupProgressDialog({required this.stage, required this.done});

  final ValueNotifier<String> stage;
  final ValueNotifier<bool> done;

  @override
  State<_BackupProgressDialog> createState() => _BackupProgressDialogState();
}

class _BackupProgressDialogState extends State<_BackupProgressDialog> {
  @override
  void initState() {
    super.initState();
    widget.done.addListener(_maybeClose);
    if (widget.done.value) {
      // The work finished before this route's first build (a fast probe):
      // the listener never fires, so close on the next frame instead.
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeClose());
    }
  }

  @override
  void dispose() {
    widget.done.removeListener(_maybeClose);
    super.dispose();
  }

  void _maybeClose() {
    if (widget.done.value && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: widget.stage,
                builder: (_, value, _) => Text(value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
