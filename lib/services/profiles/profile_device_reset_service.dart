import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/profiles/profile_policy.dart';
import '../../utils/app_storage.dart';
import '../android_native_downloader.dart';
import '../desktop_recording_service.dart';
import '../desktop_schedule_service.dart';
import '../download_service.dart';
import '../live_recording_service.dart';
import '../remote_control/remote_control_state.dart';
import '../remote_control/remote_pairing_store.dart';
import '../tvos_top_shelf_service.dart';
import 'device_key_provider.dart';
import 'profile_authorization.dart';
import 'profile_database_snapshot.dart';
import 'profile_registry.dart';
import 'profile_remote_lease.dart';
import 'profile_runtime.dart';
import 'pending_external_action_store.dart';
import 'native_profile_projection.dart';
import 'tvos_profile_recovery_store.dart';

/// Ordered, restart-safe factory reset for profile mode. Public downloads and
/// recordings are deliberately not filesystem targets.
class ProfileDeviceResetService {
  ProfileDeviceResetService._();

  static const int _journalVersion = 1;
  static const String _journalName = 'profile-device-reset-journal-v1.json';

  static Future<bool> journalExists() async {
    final base = await _journalPath();
    return await File(base).exists() || await File('$base.next').exists();
  }

  /// Handles the boundary where a prior reset already deleted profiles.db.
  /// Returns true when the caller must terminate and relaunch fresh.
  static Future<bool> resumeWithoutRegistryIfNeeded() async {
    final journal = await _readJournal();
    if (journal == null) {
      return false;
    }
    final registryExists = await ProfileRegistry.defaultRegistryExists();
    final stage = journal['stage']! as String;
    if (registryExists &&
        const <String>{'prepared', 'workDrained'}.contains(stage)) {
      return false;
    }
    if (stage == 'prepared') {
      if (!ProfileRuntime.isInMaintenance) ProfileRuntime.enterMaintenance();
      ProfileRemoteLease.instance.revoke();
      await _drainDeviceWork();
      await _writeJournal('workDrained');
    }
    await _finishPrivateCleanup();
    await _deleteJournal();
    return true;
  }

  static Future<void> reset({
    required ProfileRegistry registry,
    required ProfileAuthorizationContext authorization,
  }) async {
    final actor = await authorization.validate(registry);
    if (actor.role != UserProfileRole.admin ||
        !actor.allows(ProfileFeature.manageProfiles) ||
        !actor.allows(ProfileFeature.backupRestore)) {
      throw StateError('Device reset requires an Admin');
    }
    await _writeJournal('prepared');
    await _resumeWithRegistry(registry);
  }

  static Future<void> resumeWithRegistry(ProfileRegistry registry) async {
    if (await _readJournal() == null) return;
    await _resumeWithRegistry(registry);
  }

  static Future<void> _resumeWithRegistry(ProfileRegistry registry) async {
    if (!ProfileRuntime.isInMaintenance) ProfileRuntime.enterMaintenance();
    ProfileRemoteLease.instance.revoke();
    await _drainDeviceWork();
    await _writeJournal('workDrained');
    await _clearProfileFilesAndPreferences();
    await _writeJournal('privateDataCleared');
    await TvosTopShelfService.instance.clear();
    await PendingExternalActionStore.clear();
    await TvOsProfileRecoveryStore.clear();
    await RemotePairingStore.resetDeviceIdentity();
    await NativeProfileProjection.clearDeviceAuthorities();
    await DeviceKeyProvider.destroy();
    await _writeJournal('deviceAuthoritiesCleared');
    await registry.close();
    await _deleteRegistryFiles();
    await _writeJournal('registryDeleted');
    await _deleteJournal();
  }

  static Future<void> _drainDeviceWork() async {
    final journal = await _readJournal();
    final drains = journal?['drains'] is Map
        ? Map<String, dynamic>.from(journal!['drains'] as Map)
        : <String, dynamic>{};

    Future<void> drain(String name, Future<void> Function() operation) async {
      if (drains[name] == true) return;
      await operation();
      drains[name] = true;
      // Persist every confirmed stop independently. A later failure retries
      // only unfinished subsystems and can never be mistaken for a full drain.
      await _writeJournal('prepared', <String, Object?>{'drains': drains});
    }

    await drain('remote', () => RemoteControlState().stop());
    await drain('desktopRecordings', DesktopRecordingService.instance.stopAll);
    await drain(
      'desktopSchedules',
      DesktopScheduleService.instance.clearForDeviceReset,
    );
    if (Platform.isAndroid) {
      await drain('androidRecordings', () async {
        final recordings = await LiveRecordingService.query(
          adminAggregate: true,
          failClosed: true,
        );
        for (final recording in recordings) {
          if (recording.isRecording) {
            if (!await LiveRecordingService.stop(recording.taskId)) {
              throw StateError(
                'Could not stop Android recording ${recording.taskId}',
              );
            }
          }
        }
        var settled = recordings;
        for (
          var attempt = 0;
          attempt < 40 && settled.any((item) => item.isRecording);
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 125));
          settled = await LiveRecordingService.query(
            adminAggregate: true,
            failClosed: true,
          );
        }
        if (settled.any((item) => item.isRecording)) {
          throw StateError('Android recordings did not stop during reset');
        }
        for (final recording in settled) {
          if (!await LiveRecordingService.forget(recording.taskId)) {
            throw StateError(
              'Could not remove Android recording ${recording.taskId}',
            );
          }
        }
        if ((await LiveRecordingService.query(
          adminAggregate: true,
          failClosed: true,
        )).isNotEmpty) {
          throw StateError('Android recording state survived reset');
        }
      });
      await drain('androidSchedules', () async {
        final schedules = await LiveRecordingService.listSchedules(
          adminAggregate: true,
          failClosed: true,
        );
        for (final schedule in schedules) {
          if (!await LiveRecordingService.cancelSchedule(schedule.id)) {
            throw StateError(
              'Could not cancel Android schedule ${schedule.id}',
            );
          }
        }
        if ((await LiveRecordingService.listSchedules(
          adminAggregate: true,
          failClosed: true,
        )).isNotEmpty) {
          throw StateError('Android recording schedules survived reset');
        }
      });
    }
    await drain('downloads', DownloadService.instance.clearDeviceStateForReset);
    if (Platform.isAndroid) {
      // URI grants are storage authority for active native/plugin writers.
      // Releasing them before the writers are durably drained can strand a
      // partial file or make an otherwise retryable reset irrecoverable.
      await drain('androidDownloadDirectories', () async {
        if (!await AndroidNativeDownloader.releaseAllDownloadDirectories()) {
          throw StateError('Could not release every Android download folder');
        }
      });
    }
  }

  static Future<void> _clearProfileFilesAndPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.clear()) {
      throw StateError('Could not clear application preferences');
    }
    final roots = <Directory>[
      await AppStorage.documents(),
      await AppStorage.support(),
      await AppStorage.cache(),
    ];
    final seen = <String>{};
    for (final root in roots) {
      final profiles = Directory(p.join(root.absolute.path, 'profiles'));
      if (seen.add(profiles.path) && await profiles.exists()) {
        await profiles.delete(recursive: true);
      }
    }
    final support = await AppStorage.support();
    await _deleteExactFile(p.join(support.path, 'downloads_db_v1.json'));
    final documents = await AppStorage.documents();
    for (final name in ProfileDatabaseSnapshot.databaseNames) {
      await _deleteSqliteFamily(p.join(documents.path, name));
    }
    final legacyEngines = Directory(p.join(documents.path, 'engines'));
    if (await legacyEngines.exists()) {
      await legacyEngines.delete(recursive: true);
    }
  }

  static Future<void> _finishPrivateCleanup() async {
    await _clearProfileFilesAndPreferences();
    await TvosTopShelfService.instance.clear();
    await PendingExternalActionStore.clear();
    await TvOsProfileRecoveryStore.clear();
    await RemotePairingStore.resetDeviceIdentity();
    await NativeProfileProjection.clearDeviceAuthorities();
    await DeviceKeyProvider.destroy();
    await _deleteRegistryFiles();
  }

  static Future<void> _deleteRegistryFiles() async =>
      _deleteSqliteFamily(await ProfileRegistry.defaultPath());

  static Future<void> _deleteSqliteFamily(String databasePath) async {
    for (final suffix in const <String>['', '-wal', '-shm', '-journal']) {
      await _deleteExactFile('$databasePath$suffix');
    }
  }

  static Future<void> _deleteExactFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  static Future<String> _journalPath() async =>
      p.join((await AppStorage.support()).path, _journalName);

  static Future<Map<String, dynamic>?> _readJournal() async {
    final base = await _journalPath();
    final valid = <Map<String, dynamic>>[];
    var any = false;
    for (final path in <String>[base, '$base.next']) {
      final file = File(path);
      if (!await file.exists()) continue;
      any = true;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic> &&
            decoded['version'] == _journalVersion &&
            decoded['stage'] is String &&
            decoded['updatedAtMs'] is int &&
            (decoded['sequence'] == null || decoded['sequence'] is int)) {
          valid.add(decoded);
        }
      } catch (_) {
        // The other slot remains authoritative after an interrupted write.
      }
    }
    if (valid.isEmpty) {
      if (!any) return null;
      throw const FormatException('Device reset journal is corrupt');
    }
    valid.sort((a, b) {
      final bySequence = ((a['sequence'] as int?) ?? 0).compareTo(
        (b['sequence'] as int?) ?? 0,
      );
      if (bySequence != 0) return bySequence;
      return (a['updatedAtMs'] as int).compareTo(b['updatedAtMs'] as int);
    });
    return valid.last;
  }

  static Future<void> _writeJournal(
    String stage, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    final base = await _journalPath();
    final first = File(base);
    final second = File('$base.next');
    final previous = await _readJournal();
    final nextSequence = ((previous?['sequence'] as int?) ?? 0) + 1;
    final target = !await first.exists()
        ? first
        : !await second.exists()
        ? second
        : (await first.lastModified()).isBefore(await second.lastModified())
        ? first
        : second;
    await target.parent.create(recursive: true);
    await target.writeAsString(
      jsonEncode(<String, Object?>{
        'version': _journalVersion,
        'stage': stage,
        'sequence': nextSequence,
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        'publicMediaRetained': true,
        ...payload,
      }),
      flush: true,
    );
  }

  static Future<void> _deleteJournal() async {
    final base = await _journalPath();
    await _deleteExactFile(base);
    await _deleteExactFile('$base.next');
  }
}
