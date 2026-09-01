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
import '../../services/profiles/portable_profile_package.dart';
import '../../services/profiles/profile_app_lifecycle_participant.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/profile_database_snapshot.dart';
import '../../services/profiles/profile_lifecycle.dart';
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

enum _ProfileBackupDestination { localFile, webDav }

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
      await _createProfileBackupUnchecked(
        destination: _ProfileBackupDestination.localFile,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_profileBackupError(error, creating: true))),
      );
    }
  }

  Future<void> createWebDavProfileBackup() async {
    try {
      await _createProfileBackupUnchecked(
        destination: _ProfileBackupDestination.webDav,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_profileBackupError(error, creating: true))),
      );
    }
  }

  Future<void> _createProfileBackupUnchecked({
    required _ProfileBackupDestination destination,
  }) async {
    if (destination == _ProfileBackupDestination.localFile &&
        PlatformUtil.isTvOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Apple TV profile backups use the authenticated Remote transfer flow.',
          ),
        ),
      );
      return;
    }
    if (destination == _ProfileBackupDestination.webDav &&
        PlatformUtil.isTvOS &&
        TvosDevice.isLowMemoryCached) {
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

    final WebDavPickerResult? webDavTarget;
    final ProfileAsyncAuthorization? migrateAuthorization;
    if (destination == _ProfileBackupDestination.webDav) {
      webDavTarget = await Navigator.of(context).push<WebDavPickerResult>(
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
      migrateAuthorization = await _captureWebDavAuthorization(
        webDavTarget.config,
      );
    } else {
      webDavTarget = null;
      migrateAuthorization = null;
    }
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
    if (destination == _ProfileBackupDestination.localFile) {
      final stamp = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final saved = await saveBackupFile(
        fileName: allProfiles
            ? 'debrify-profiles-$stamp.json'
            : 'debrify-profile-$stamp.json',
        bytes: encodedBytes!,
      );
      if (saved == null) return;
      destinationLabel = 'saved';
    } else {
      final target = webDavTarget!;
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
    return saved.reference;
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
      if (file.size > PortableProfilePackage.maxEnvelopeBytes) {
        throw const FormatException('Backup exceeds the supported size limit');
      }
      final path = file.path;
      if (path == null) {
        throw const FormatException('Selected backup is not locally readable');
      }
      return _restoreProfileBackupFromPath(path);
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

    final registry = ProfileBootstrap.registry;
    final profile = await registry.getProfile(
      ProfileRuntime.capture().profileId,
    );
    if (profile == null || !context.mounted) return null;
    final graphRestore = package.mode == 'deviceGraph';
    final legacyDatabasesMissing =
        package.omissions['libraryDatabasesOmitted'] == true ||
        package.omissions['libraryDatabasesTooLarge'] != null;
    final debrifyTvOmission = DebrifyTvBackupOmission.fromOmissions(
      package.omissions,
    );
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
      if (package.omissions.containsKey('rebuildableDatabaseCachesOmitted'))
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
              ? 'Import ${package.profiles.length} profiles?'
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
