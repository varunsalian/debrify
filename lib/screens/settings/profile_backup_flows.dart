import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../models/webdav_item.dart';
import '../../services/backup_restore_service.dart';
import '../../services/download_service.dart';
import '../../services/profiles/connection_resource_service.dart';
import '../../services/profiles/device_key_provider.dart';
import '../../services/profiles/legacy_backup_adapter.dart';
import '../../services/profiles/local_backup/local_backup_archive.dart';
import '../../services/profiles/local_backup/local_backup_zip.dart'
    show LocalBackupZip;
import '../../services/profiles/portable_profile_package.dart';
import '../../services/profiles/profile_app_lifecycle_participant.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/profile_database_snapshot.dart';
import '../../services/profiles/profile_lifecycle.dart';
import '../../services/profiles/profile_lock_controller.dart';
import '../../services/profiles/profile_package_service.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_restore_coordinator.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/webdav_backup_transport.dart';
import '../../services/webdav_protocol_client.dart';
import '../../services/webdav_service.dart';
import '../../utils/platform_util.dart';
import '../../utils/tvos_device.dart';
import '../../widgets/tv_text_field.dart';
import '../webdav/webdav_files_screen.dart';
import 'widgets/settings_widgets.dart';

/// Successful profile restore metadata needed by onboarding completion.
class ProfileBackupRestoreResult {
  const ProfileBackupRestoreResult.singleProfile({
    required this.authorizingProfileId,
  }) : graphReport = null;

  const ProfileBackupRestoreResult.deviceGraph({
    required this.authorizingProfileId,
    required this.graphReport,
  });

  final String authorizingProfileId;
  final ProfileGraphRestoreReport? graphReport;
}

const int _lowMemoryTvosRestoreLimit = 32 * 1024 * 1024;

enum _ProfileBackupSource { localFile, webDav }

/// The profile backup/restore user flows, extracted from the settings screen
/// so the Profiles hub can offer them at its first level. The original local
/// file behavior stays intact, while WebDAV supplies a second transport;
/// [onRestored] replaces the screen-specific refresh the settings page used to
/// run inline.
class ProfileBackupFlows {
  const ProfileBackupFlows(
    this.context, {
    this.onRestored,
    this.completingOnboarding = false,
  });

  final BuildContext context;
  final Future<void> Function()? onRestored;
  final bool completingOnboarding;

  Future<void> createProfileBackup() async {
    try {
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
      await _createLocalArchiveBackup();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_profileBackupError(error, creating: true))),
      );
    }
  }

  Future<void> createWebDavProfileBackup() async {
    try {
      await _createWebDavProfileBackupUnchecked();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_profileBackupError(error, creating: true))),
      );
    }
  }

  /// WebDAV manual backup: the passphrase-encrypted JSON package on its
  /// existing format and path. Local files use [_createLocalArchiveBackup].
  Future<void> _createWebDavProfileBackupUnchecked() async {
    if (PlatformUtil.isTvOS && TvosDevice.isLowMemoryCached) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup packaging is deferred on this low-memory Apple TV. Use '
            'Remote transfer or create the backup on another enrolled device.',
          ),
          duration: Duration(seconds: 7),
        ),
      );
      return;
    }

    final webDavTarget = await Navigator.of(context).push<WebDavPickerResult>(
      MaterialPageRoute(
        builder: (_) => const WebDavFilesScreen(
          isPushedRoute: true,
          pickerMode: WebDavPickerMode.selectFolder,
          dataSource: WebDavFilesDataSource(
            feature: ProfileFeature.backupRestore,
          ),
        ),
      ),
    );
    if (webDavTarget == null || !context.mounted) return;
    final migrateAuthorization = await _captureWebDavAuthorization(
      webDavTarget.config,
    );
    final registry = ProfileBootstrap.registry;
    final authorization = await ProfileAuthorizationContext.capture(registry);
    final actor = await _runIfCurrent(
      migrateAuthorization,
      () => authorization.validate(registry),
    );
    if (!actor.allows(ProfileFeature.backupRestore)) {
      throw StateError('This profile is not allowed to create backups');
    }
    final canExportAll =
        actor.role == UserProfileRole.admin &&
        actor.allows(ProfileFeature.manageProfiles);
    if (!context.mounted) return;
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
    Future<PortableProfilePackage> export({required bool compact}) =>
        _runIfCurrent(
          migrateAuthorization,
          () => allProfiles
              ? service.exportAllProfiles(
                  context: authorization,
                  includeSecrets: true,
                  compactDatabaseSnapshots: compact,
                )
              : service.exportProfile(
                  context: authorization,
                  scope: ProfileRuntime.capture(),
                  includeSecrets: true,
                  sanitized: false,
                  compactDatabaseSnapshots: compact,
                ),
        );

    PortableProfilePackage? package;
    Uint8List? encodedBytes;
    var compactRetryRequired = false;
    await _profileBackupProgress<void>('Packaging profile data…', (
      setStage,
    ) async {
      package = await export(compact: false);
      // An automatic raw-database compaction can already have produced an
      // omitted package. Size it here, but obtain consent before saving it.
      setStage('Encrypting backup — this can take a minute…');
      try {
        encodedBytes = await PortableProfilePackage.encodeEncryptedBytes(
          package!,
          password,
        );
      } catch (error) {
        if (!PortableProfilePackage.isExportTooLarge(error)) rethrow;
        compactRetryRequired = true;
      }
    });
    if (compactRetryRequired) {
      package = await _profileBackupProgress<PortableProfilePackage>(
        'Compacting the backup…',
        (setStage) async {
          final compacted = await export(compact: true);
          setStage('Encrypting compacted backup — this can take a minute…');
          encodedBytes = await PortableProfilePackage.encodeEncryptedBytes(
            compacted,
            password,
          );
          return compacted;
        },
      );
    }
    final debrifyTvOmission = DebrifyTvBackupOmission.fromOmissions(
      package!.omissions,
    );
    if (debrifyTvOmission?.isEmpty == false) {
      final continueWithoutChannels = await _confirmDebrifyTvOmission(
        debrifyTvOmission!,
        allProfiles: allProfiles,
      );
      if (!continueWithoutChannels) return;
    }
    encodedBytes ??= await _profileBackupProgress<Uint8List>(
      'Encrypting backup — this can take a minute…',
      (_) => PortableProfilePackage.encodeEncryptedBytes(package!, password),
    );
    final databaseCachesCompacted = package!.omissions.containsKey(
      'rebuildableDatabaseCachesOmitted',
    );
    // Nothing below needs the plaintext export graph. Clear the captured
    // reference explicitly before any local-file or WebDAV I/O so a large
    // database snapshot can be collected on memory-constrained tvOS devices.
    package = null;
    late final String destinationLabel;
    final target = webDavTarget;
    final stagingDirectory = await _createPrivateStagingDirectory('upload');
    try {
      final stagedFile = File(
        p.join(stagingDirectory.path, 'profile-backup.json'),
      );
      await stagedFile.writeAsBytes(encodedBytes!, flush: true);
      // The transport reads from disk. Drop the encrypted envelope reference
      // before the network transfer as well.
      encodedBytes = null;
      final uploaded = await _profileBackupProgress(
        'Uploading and verifying backup…',
        (_) => _runIfCurrentAsOutbound(
          migrateAuthorization,
          () => WebDavBackupTransport().uploadVerified(
            config: target.config,
            directoryPath: target.path,
            stagedFile: stagedFile,
            scratchDirectory: stagingDirectory,
            fileNamePrefix: allProfiles
                ? 'debrify-profiles'
                : 'debrify-profile',
            beforeSend: ProfileAsyncAuthorization.currentOutboundBarrier,
          ),
        ),
      );
      destinationLabel =
          'uploaded to ${target.config.name}/${uploaded.remotePath}';
    } finally {
      await _deletePrivateStagingDirectory(stagingDirectory);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${allProfiles ? 'All-profile backup' : 'Profile backup'} '
          '$destinationLabel'
          '${debrifyTvOmission?.isEmpty == false
              ? '. Debrify TV was excluded as confirmed; restore it from a channel ZIP or Remote.'
              : databaseCachesCompacted
              ? '. Rebuildable catalog/EPG caches were compacted.'
              : ''}',
        ),
        duration: debrifyTvOmission?.isEmpty == false || databaseCachesCompacted
            ? const Duration(seconds: 7)
            : const Duration(seconds: 4),
      ),
    );
  }

  /// Manual local backups use the streamed `.debrify` archive: databases and
  /// imported playlists travel as files, never as base64 inside JSON, so a
  /// large library does not need to fit in memory. Unencrypted by design;
  /// the dialog says so and names what the file contains.
  Future<void> _createLocalArchiveBackup() async {
    final registry = ProfileBootstrap.registry;
    final authorization = await ProfileAuthorizationContext.capture(registry);
    final actor = await authorization.validate(registry);
    if (!actor.allows(ProfileFeature.backupRestore)) {
      throw StateError('This profile is not allowed to create backups');
    }
    final canExportAll =
        actor.role == UserProfileRole.admin &&
        actor.allows(ProfileFeature.manageProfiles);
    if (!context.mounted) return;
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
                'Creates a Debrify backup file (.debrify). It is not '
                'encrypted and contains your account credentials and '
                'connection passwords, so keep it private.\n\n'
                'Included: settings, connections, Debrify TV channels with '
                'their saved hashes, IPTV playlists, favorites, lists, '
                'history, and ordering. Provider channel lists and TV guides '
                'are rebuilt after restore, which may need network access. '
                'Downloads, recordings, active jobs, device paths, and remote '
                'pairings are not included.\n\n'
                'Older Debrify versions cannot read this file.',
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Create backup'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    if (allProfiles && !await reauthenticateSensitiveProfile(actor)) return;

    final exporter = LocalBackupExporter(
      service: ProfilePackageService(
        registry: registry,
        resources: ConnectionResourceService(
          registry: registry,
          cipher: DeviceKeyProvider.cipher,
        ),
      ),
    );
    await LocalBackupOperationGuard.run(() async {
      final staging = await LocalBackupScratch.create('export');
      final cancellation = LocalBackupCancellation();
      try {
        final result = await _profileBackupProgress<LocalBackupExportResult>(
          'Preparing backup…',
          (setStage) => exporter.export(
            context: authorization,
            staging: staging,
            allProfiles: allProfiles,
            scope: allProfiles ? null : ProfileRuntime.capture(),
            onStage: setStage,
            onBytes: _byteStageReporter(setStage),
            cancellation: cancellation,
          ),
          cancellation: cancellation,
        );
        final saved = await _profileBackupProgress<GeneratedFileSaveResult>(
          'Saving backup…',
          (_) => DownloadService.instance.saveGeneratedFileFromPath(
            fileName: result.fileName,
            source: result.archive,
            mimeType: LocalBackupManifest.mimeType,
          ),
        );
        if (!context.mounted) return;
        await _showGeneratedFileSaved(saved, artifactLabel: 'backup');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${allProfiles ? 'All-profile backup' : 'Profile backup'} saved'
              '${result.cachesPruned ? '. Provider channel lists and TV guides will refresh after a restore.' : '.'}',
            ),
            duration: Duration(seconds: result.cachesPruned ? 7 : 4),
          ),
        );
      } on LocalBackupCancelledException {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup cancelled; nothing was saved.')),
        );
      } finally {
        await LocalBackupScratch.delete(staging);
      }
    });
  }

  /// Turns per-chunk byte callbacks into a stage label that only changes
  /// when the displayed megabyte count changes, so the dialog is not rebuilt
  /// hundreds of times per second on slow storage.
  void Function(String, int, int) _byteStageReporter(
    void Function(String) setStage,
  ) {
    String? lastLabel;
    return (name, done, total) {
      final label =
          '${_stageVerbFor(name)} ${p.basename(name)}: '
          '${_megabytes(done)} of ${_megabytes(total)}';
      if (label == lastLabel) return;
      lastLabel = label;
      setStage(label);
    };
  }

  static String _stageVerbFor(String entryName) =>
      entryName.startsWith('databases/')
      ? 'Library'
      : entryName.startsWith('attachments/')
      ? 'Playlist'
      : 'File';

  static String _megabytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).ceil()} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';
  }

  Future<ProfileAsyncAuthorization?> _captureWebDavAuthorization(
    WebDavConfig config,
  ) async {
    if (ProfileRuntime.isProfileCommitted &&
        (config.connectionResourceId == null ||
            config.connectionResourceRevision == null)) {
      throw StateError('The selected WebDAV connection is no longer valid');
    }
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.backupRestore,
      resourceId: config.connectionResourceId,
      resourceAuthorizationRevision: config.connectionResourceRevision,
    );
    if (ProfileRuntime.isProfileCommitted && authorization == null) {
      throw StateError('Profile backup authorization is unavailable');
    }
    return authorization;
  }

  Future<T> _runIfCurrent<T>(
    ProfileAsyncAuthorization? authorization,
    Future<T> Function() body,
  ) => authorization == null ? body() : authorization.runIfCurrent(body);

  Future<T> _runIfCurrentAsOutbound<T>(
    ProfileAsyncAuthorization? authorization,
    Future<T> Function() body,
  ) => authorization == null
      ? body()
      : authorization.runIfCurrentAsOutbound(body);

  Future<Directory> _createPrivateStagingDirectory(String purpose) async {
    final root = await getTemporaryDirectory();
    await root.create(recursive: true);
    return root.createTemp('debrify-migrate-$purpose-');
  }

  Future<void> _deletePrivateStagingDirectory(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<bool> _confirmDebrifyTvOmission(
    DebrifyTvBackupOmission omission, {
    required bool allProfiles,
  }) async {
    if (!context.mounted) return false;
    return await showSettingsDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Continue without Debrify TV?'),
            content: Text(
              'This backup had to be compacted to fit. Debrify TV will not '
              'be included: ${omission.contentsLabel} will be left out. No '
              'empty channels will be created when it is restored.\n\n'
              'Before continuing, you can cancel and open Debrify TV → '
              'Export to save the channels and their playable pools as a '
              'ZIP. After restoring, use Debrify TV → Import → From storage. '
              'Remote → Debrify TV Channels remains available for direct '
              'device transfer.'
              '${allProfiles && omission.profilesAffected > 1 ? ' Repeat the ZIP export/import or Remote transfer for each affected profile.' : ''}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel and export ZIP'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continue without Debrify TV'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Saves portable bytes through the same destination policy as downloads.
  /// Generated artifacts never enter the download queue or history, but they
  /// honor Downloads/Debrify, desktop custom folders, and Android SAF.
  /// Returns a filesystem path or Android content URI.
  Future<String?> saveBackupFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = 'application/json',
    String artifactLabel = 'backup',
  }) async {
    final saved = await DownloadService.instance.saveGeneratedFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
    if (context.mounted) {
      await _showGeneratedFileSaved(saved, artifactLabel: artifactLabel);
    }
    return saved.reference;
  }

  Future<void> _showGeneratedFileSaved(
    GeneratedFileSaveResult saved, {
    required String artifactLabel,
  }) async {
    final titleLabel = artifactLabel.isEmpty
        ? 'File'
        : '${artifactLabel[0].toUpperCase()}${artifactLabel.substring(1)}';
    await showSettingsDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$titleLabel saved'),
        content: Text(
          'The $artifactLabel was saved by Debrify’s download service:\n\n'
          '${saved.displayLocation}\n\nYou can move or copy it with a file '
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

  /// Modal stage indicator for backup/restore work. The crypto and
  /// whole-envelope parse stages run in a worker isolate so the spinner
  /// animates through them (packaging still reads databases on this isolate);
  /// [setStage] swaps the label between phases without re-opening the dialog.
  /// The dialog dismisses itself through its own context, so it cannot leak
  /// on the root navigator if this State unmounts mid-run.
  Future<T> _profileBackupProgress<T>(
    String initialStage,
    Future<T> Function(void Function(String) setStage) run, {
    LocalBackupCancellation? cancellation,
  }) async {
    final stage = ValueNotifier<String>(initialStage);
    final done = ValueNotifier<bool>(false);
    unawaited(
      showSettingsDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BackupProgressDialog(
          stage: stage,
          done: done,
          onCancel: cancellation == null
              ? null
              : () {
                  cancellation.cancel();
                  stage.value = 'Cancelling…';
                },
        ),
      ),
    );
    try {
      return await run((value) => stage.value = value);
    } finally {
      done.value = true;
    }
  }

  Future<ProfileBackupRestoreResult?> restoreProfileBackup() async {
    try {
      return await _restoreProfileBackupUnchecked(
        source: _ProfileBackupSource.localFile,
      );
    } catch (error) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_profileBackupError(error, creating: false))),
      );
      return null;
    }
  }

  Future<ProfileBackupRestoreResult?> restoreWebDavProfileBackup() async {
    try {
      return await _restoreProfileBackupUnchecked(
        source: _ProfileBackupSource.webDav,
      );
    } catch (error) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_profileBackupError(error, creating: false))),
      );
      return null;
    }
  }

  String _profileBackupError(Object error, {required bool creating}) {
    if (error is LocalBackupStorageException) return error.message;
    if (error is FormatException) {
      return error.message;
    }
    if (error is StateError) return error.message;
    if (error is WebDavException ||
        error is WebDavBackupVerificationException) {
      return error.toString();
    }
    return creating
        ? 'Could not create the profile backup'
        : 'Profile restore failed; existing data is unchanged';
  }

  Future<ProfileBackupRestoreResult?> _restoreProfileBackupUnchecked({
    required _ProfileBackupSource source,
  }) async {
    if (source == _ProfileBackupSource.localFile && PlatformUtil.isTvOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Apple TV restores profile packages through authenticated Remote transfer.',
          ),
        ),
      );
      return null;
    }

    if (source == _ProfileBackupSource.localFile) {
      final pick = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose a Debrify backup',
        type: FileType.any,
        withData: false,
      );
      if (pick == null || pick.files.isEmpty) return null;
      final file = pick.files.single;
      final path = file.path;
      if (path == null) {
        throw const FormatException('Selected backup is not locally readable');
      }
      try {
        // Route by header, not extension: a `.debrify` archive starts with
        // the ZIP magic, legacy backups are JSON objects.
        if (await LocalBackupZip.looksLikeArchive(File(path))) {
          return await _restoreLocalArchive(path);
        }
        if (file.size > PortableProfilePackage.maxEnvelopeBytes) {
          throw const FormatException(
            'Backup exceeds the supported size limit',
          );
        }
        return await _restoreProfileBackupFromPath(path);
      } finally {
        // On Android/iOS the picker copies a content:// pick into the app
        // cache; a multi-GB archive would otherwise sit there until the user
        // clears app data. Only that copy is removed: the plugin's own
        // clearTemporaryFiles wipes the whole temp directory on iOS.
        await _deletePickerCopy(path);
      }
    }

    final target = await Navigator.of(context).push<WebDavPickerResult>(
      MaterialPageRoute(
        builder: (_) => const WebDavFilesScreen(
          isPushedRoute: true,
          pickerMode: WebDavPickerMode.selectBackup,
          dataSource: WebDavFilesDataSource(
            feature: ProfileFeature.backupRestore,
          ),
        ),
      ),
    );
    if (target == null || !context.mounted) return null;
    final migrateAuthorization = await _captureWebDavAuthorization(
      target.config,
    );
    final maxBytes = PlatformUtil.isTvOS && TvosDevice.isLowMemoryCached
        ? _lowMemoryTvosRestoreLimit
        : PortableProfilePackage.maxEnvelopeBytes;
    if ((target.item?.sizeBytes ?? 0) > maxBytes) {
      throw const FormatException(
        'This backup is too large to restore safely on this Apple TV',
      );
    }
    final stagingDirectory = await _createPrivateStagingDirectory('restore');
    try {
      final stagedFile = File(
        p.join(stagingDirectory.path, 'profile-backup.json'),
      );
      await _profileBackupProgress(
        'Downloading backup…',
        (_) => _runIfCurrentAsOutbound(
          migrateAuthorization,
          () => WebDavService.downloadToFile(
            config: target.config,
            path: target.path,
            destination: stagedFile,
            maxBytes: maxBytes,
            feature: ProfileFeature.backupRestore,
            beforeSend: ProfileAsyncAuthorization.currentOutboundBarrier,
          ),
        ),
      );
      return await _restoreProfileBackupFromPath(
        stagedFile.path,
        migrateAuthorization: migrateAuthorization,
      );
    } finally {
      await _deletePrivateStagingDirectory(stagingDirectory);
    }
  }

  Future<ProfileBackupRestoreResult?> _restoreProfileBackupFromPath(
    String path, {
    ProfileAsyncAuthorization? migrateAuthorization,
  }) async {
    final probe = await _profileBackupProgress(
      'Reading backup…',
      (_) => PortableProfilePackage.probeFile(path),
    );

    PortableProfilePackage package;
    if (probe.isProfilePackage) {
      if (probe.encrypted) {
        final unlocked = await _promptAndDecryptProfilePackage(path);
        if (unlocked == null) return null;
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
        if (unlocked == null) return null;
        legacy = unlocked;
      }
      package = LegacyBackupAdapter.adapt(legacy);
    }
    return _confirmAndRestorePackage(
      package,
      migrateAuthorization: migrateAuthorization,
    );
  }

  Future<void> _deletePickerCopy(String path) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final temp = (await getTemporaryDirectory()).path;
      final normalized = p.normalize(path);
      final inPickerCache =
          p.isWithin(temp, normalized) ||
          normalized.contains('${p.separator}file_picker${p.separator}');
      if (!inPickerCache) return;
      final file = File(normalized);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort; the OS reclaims cache eventually.
    }
  }

  /// Reads only the archive directory and manifest, obtains confirmation and
  /// authorization, and only then extracts into private staging. A cancelled
  /// or unauthorized restore never pays for a multi-gigabyte extraction.
  Future<ProfileBackupRestoreResult?> _restoreLocalArchive(String path) {
    return LocalBackupOperationGuard.run(() async {
      final inspection = await _profileBackupProgress<LocalBackupInspection>(
        'Reading backup…',
        (_) => LocalBackupRestorer.inspect(File(path)),
      );
      if (!context.mounted) return null;
      final summary = _archiveSummary(inspection.manifest);
      final confirmation = await _confirmRestore(
        mode: summary.mode,
        profileCount: summary.profileCount,
        omissions: summary.omissions,
      );
      if (confirmation == null) return null;

      final staging = await LocalBackupScratch.create('restore');
      final cancellation = LocalBackupCancellation();
      LocalBackupRestoreStage? stage;
      // Authorization and PIN re-auth were captured before a possibly long
      // unpack; keep the inactivity lock from firing while the busy dialog
      // is up, exactly as playback does.
      ProfileLockController.instance.setPlaybackActive(true);
      try {
        stage = await _profileBackupProgress<LocalBackupRestoreStage>(
          'Unpacking backup…',
          (setStage) => LocalBackupRestorer.stage(
            archive: File(path),
            staging: staging,
            inspection: inspection,
            onStage: setStage,
            onBytes: _byteStageReporter(setStage),
            cancellation: cancellation,
          ),
          cancellation: cancellation,
        );
        if (!context.mounted) return null;
        return await _performRestore(
          stage.package,
          confirmation,
          databaseFileResolver: stage.resolveDatabase,
        );
      } on LocalBackupCancelledException {
        return null;
      } finally {
        ProfileLockController.instance.setPlaybackActive(false);
        if (stage != null) {
          await stage.dispose();
        } else {
          await LocalBackupScratch.delete(staging);
        }
      }
    });
  }

  /// Minimal, type-checked view of an archive's embedded package before the
  /// full decoder runs. Enough for the confirmation dialog, nothing more.
  static ({String mode, int profileCount, Map<String, dynamic> omissions})
  _archiveSummary(LocalBackupManifest manifest) {
    final package = manifest.package;
    final mode = package['mode'];
    final profiles = package['profiles'];
    final omissions = package['omissions'];
    if (mode is! String ||
        profiles is! List ||
        profiles.isEmpty ||
        profiles.length > PortableProfilePackage.maxProfiles ||
        (omissions != null && omissions is! Map)) {
      throw const FormatException('Backup manifest is invalid');
    }
    return (
      mode: mode,
      profileCount: profiles.length,
      omissions: omissions == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(omissions as Map),
    );
  }

  Future<ProfileBackupRestoreResult?> _confirmAndRestorePackage(
    PortableProfilePackage package, {
    ProfileAsyncAuthorization? migrateAuthorization,
    ProfileDatabaseFileResolver? databaseFileResolver,
  }) async {
    final confirmation = await _confirmRestore(
      mode: package.mode,
      profileCount: package.profiles.length,
      omissions: package.omissions,
    );
    if (confirmation == null) return null;
    return _performRestore(
      package,
      confirmation,
      migrateAuthorization: migrateAuthorization,
      databaseFileResolver: databaseFileResolver,
    );
  }

  /// Authorization check, notices, confirm dialog and sensitive re-auth.
  /// Returns null when the user backs out.
  Future<_RestoreConfirmation?> _confirmRestore({
    required String mode,
    required int profileCount,
    required Map<String, dynamic> omissions,
  }) async {
    final registry = ProfileBootstrap.registry;
    final profile = await registry.getProfile(
      ProfileRuntime.capture().profileId,
    );
    if (profile == null || !context.mounted) return null;
    final graphRestore = mode == 'deviceGraph';
    final legacyDatabasesMissing =
        omissions['libraryDatabasesOmitted'] == true ||
        omissions['libraryDatabasesTooLarge'] != null;
    final debrifyTvOmission = DebrifyTvBackupOmission.fromOmissions(omissions);
    final databaseNotices = <String>[
      if (legacyDatabasesMissing)
        'Warning: this older backup omitted one or more library databases; '
            'those playlists/history rows cannot be recovered from it.',
      if (debrifyTvOmission?.isEmpty == false)
        'Debrify TV was excluded when this backup was compacted '
            '(${debrifyTvOmission!.contentsLabel}). No empty Debrify TV '
            'channels will be created. Import a previously exported channel '
            'ZIP from Debrify TV → Import → From storage, or transfer them '
            'from the source using Remote → Debrify TV Channels.',
      if (omissions.containsKey('rebuildableDatabaseCachesOmitted'))
        'Rebuildable IPTV catalog and EPG caches were compacted; playlists, '
            'favorites, history, numbering, and settings are included.',
    ];
    final databaseNotice = databaseNotices.join('\n\n');
    final authorization = await ProfileAuthorizationContext.capture(registry);
    final actor = await authorization.validate(registry);
    if (graphRestore &&
        (actor.role != UserProfileRole.admin ||
            !actor.allows(ProfileFeature.manageProfiles))) {
      throw StateError('Only an Admin can restore an all-profile backup');
    }
    final graphAuthorityNotice =
        completingOnboarding && actor.id == ProfileBootstrap.freshAdminId
        ? 'Debrify then switches to a usable imported Admin and removes the '
              'temporary setup Admin if it is untouched. If no imported '
              'Admin can take over, the setup Admin remains for recovery.'
        : 'Your current Admin remains the recovery profile.';
    if (!context.mounted) return null;
    final confirmed = await showSettingsDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          graphRestore
              ? 'Import $profileCount profiles?'
              : 'Restore profile backup?',
        ),
        content: Text(
          graphRestore
              ? 'The profiles and their shared connection graph are staged under new IDs, then made visible together. $graphAuthorityNotice Existing profiles are not overwritten. Profiles keep their PINs when the backup carries them. Media, jobs, paths, and remote pairings are not restored.${databaseNotice.isEmpty ? '' : '\n\n$databaseNotice'}'
              : 'Destination: ${profile.name}\n\nA complete shadow generation will be verified first. Existing data remains visible if staging fails. Imported accounts become new resources. The destination name, role, policy, PIN, and enabled state stay unchanged; downloads, recordings, jobs, paths, and pairings are not restored.${databaseNotice.isEmpty ? '' : '\n\n$databaseNotice'}',
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
    if (confirmed != true) return null;
    if (graphRestore && !await reauthenticateSensitiveProfile(actor)) {
      return null;
    }
    return _RestoreConfirmation(
      actor: actor,
      profile: profile,
      authorization: authorization,
      graphRestore: graphRestore,
      databaseNotice: databaseNotice,
    );
  }

  Future<ProfileBackupRestoreResult?> _performRestore(
    PortableProfilePackage package,
    _RestoreConfirmation confirmation, {
    ProfileAsyncAuthorization? migrateAuthorization,
    ProfileDatabaseFileResolver? databaseFileResolver,
  }) async {
    final registry = ProfileBootstrap.registry;
    final actor = confirmation.actor;
    final profile = confirmation.profile;
    final authorization = confirmation.authorization;
    final graphRestore = confirmation.graphRestore;
    final databaseNotice = confirmation.databaseNotice;
    final coordinator = ProfileRestoreCoordinator(
      registry: registry,
      cipher: DeviceKeyProvider.cipher,
      lifecycleParticipants: <ProfileLifecycleParticipant>[
        ProfileAppLifecycleParticipant(),
      ],
    );
    if (graphRestore) {
      final report = await _profileBackupProgress(
        'Importing profiles — this can take a few minutes…',
        (_) => _runIfCurrent(
          migrateAuthorization,
          () => coordinator.restoreDeviceGraph(
            package: package,
            authorization: authorization,
            databaseFileResolver: databaseFileResolver,
          ),
        ),
      );
      final result = ProfileBackupRestoreResult.deviceGraph(
        authorizingProfileId: actor.id,
        graphReport: report,
      );
      if (!context.mounted) return result;
      await onRestored?.call();
      if (!context.mounted) return result;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${report.profilesImported} profiles, '
            '${report.resourcesImported} connections and '
            '${report.grantsImported} grants.'
            '${report.pinResetsRequired == 0 ? '' : ' ${report.pinResetsRequired} profile(s) require a new PIN.'}'
            '${databaseNotice.isEmpty ? '' : ' $databaseNotice'}',
          ),
          duration: const Duration(seconds: 7),
        ),
      );
      return result;
    }
    final report = await _profileBackupProgress(
      'Restoring — verifying and staging data, this can take a few minutes…',
      (_) => _runIfCurrent(
        migrateAuthorization,
        () => coordinator.restore(
          package: package,
          destinationProfileId: profile.id,
          authorization: authorization,
          completeOnboarding: completingOnboarding,
          databaseFileResolver: databaseFileResolver,
        ),
      ),
    );
    final result = ProfileBackupRestoreResult.singleProfile(
      authorizingProfileId: actor.id,
    );
    if (!context.mounted) return result;
    await onRestored?.call();
    if (context.mounted) {
      final omitted = PortableProfilePackage.userVisibleOmissions(
        report.omissions,
      ).entries.map((entry) => '${entry.key}: ${entry.value}').join(', ');
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
    return result;
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

class _RestoreConfirmation {
  const _RestoreConfirmation({
    required this.actor,
    required this.profile,
    required this.authorization,
    required this.graphRestore,
    required this.databaseNotice,
  });

  final UserProfile actor;
  final UserProfile profile;
  final ProfileAuthorizationContext authorization;
  final bool graphRestore;
  final String databaseNotice;
}

/// Busy dialog for [_profileBackupProgress]: undismissable while work runs,
/// and closed through its OWN context when `done` fires — the caller's State
/// may unmount mid-run, and an orphaned `canPop: false` modal on the root
/// navigator would wedge the whole app.
class _BackupProgressDialog extends StatefulWidget {
  const _BackupProgressDialog({
    required this.stage,
    required this.done,
    this.onCancel,
  });

  final ValueNotifier<String> stage;
  final ValueNotifier<bool> done;
  final VoidCallback? onCancel;

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
    if (!widget.done.value || !mounted) return;
    // Remove THIS route, not whatever is on top: a fast stage can finish
    // before the first frame, and the caller may already have pushed its
    // confirm dialog above us by the time the post-frame callback runs.
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  bool _cancelRequested = false;

  @override
  Widget build(BuildContext context) {
    final onCancel = widget.onCancel;
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
        actions: onCancel == null
            ? null
            : [
                TextButton(
                  autofocus: true,
                  onPressed: _cancelRequested
                      ? null
                      : () {
                          setState(() => _cancelRequested = true);
                          onCancel();
                        },
                  child: const Text('Cancel'),
                ),
              ],
      ),
    );
  }
}
