import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/profiles/profile_avatar.dart';
import '../../models/profiles/user_profile.dart';
import '../../utils/app_storage.dart';
import 'profile_avatar_storage.dart';
import 'profile_cleanup_ledger.dart';
import 'profile_data_generation.dart';
import 'profile_registry.dart';
import 'profile_scope.dart';

/// Serializes avatar publication and records its filesystem intent durably.
///
/// The registry and avatar directory cannot share a database transaction. The
/// in-process queue prevents two writers from interleaving their update/prune
/// pairs, while the ledger lets bootstrap reconcile a process death at any
/// point between writing a candidate and pruning the old file.
class ProfileAvatarMutation {
  ProfileAvatarMutation._();

  static final Map<String, Future<void>> _profileTails =
      <String, Future<void>>{};
  static Future<void> _ledgerTail = Future<void>.value();

  static const String _ledgerName = 'profile-avatar-mutations-v1.json';

  static Future<T> runExclusive<T>(
    String profileId,
    Future<T> Function() operation,
  ) async {
    if (!ProfileScope.isValidProfileId(profileId)) {
      throw ArgumentError.value(profileId, 'profileId', 'Unsafe profile ID');
    }
    final previous = _profileTails[profileId] ?? Future<void>.value();
    final release = Completer<void>();
    _profileTails[profileId] = release.future;
    try {
      try {
        await previous;
      } catch (_) {
        // A failed predecessor must not poison the per-profile queue.
      }
      return await operation();
    } finally {
      release.complete();
      if (identical(_profileTails[profileId], release.future)) {
        _profileTails.remove(profileId);
      }
    }
  }

  /// Acquires several profile queues in stable order, avoiding graph-restore
  /// deadlocks while keeping every newly published profile protected until its
  /// avatar files have been finalized.
  static Future<T> runExclusiveMany<T>(
    Iterable<String> profileIds,
    Future<T> Function() operation,
  ) {
    final ids = profileIds.toSet().toList()..sort();
    Future<T> acquire(int index) => index == ids.length
        ? operation()
        : runExclusive(ids[index], () => acquire(index + 1));
    return acquire(0);
  }

  /// Records the key that the current operation intends to make authoritative.
  /// This must complete before candidate bytes touch the live avatar directory.
  static Future<void> begin(String profileId, String avatarKey) =>
      _withLedgerLock(() async {
        if (!ProfileScope.isValidProfileId(profileId) ||
            ProfileAvatar.tryParse(avatarKey) == null) {
          throw ArgumentError('Invalid avatar mutation intent');
        }
        final state = await _readLedger();
        state.entries[profileId] = avatarKey;
        await _writeLedger(state);
      });

  static Future<void> complete(String profileId) => _withLedgerLock(() async {
    final state = await _readLedger();
    if (state.entries.remove(profileId) != null) await _writeLedger(state);
  });

  /// Reconciles mutations interrupted by process death.
  ///
  /// An active profile's registry key is authoritative: if it matches the
  /// intent, finish its prune; otherwise discard the abandoned candidate and
  /// normalize storage around the newer key. A staging profile carrying an
  /// editor mutation was never published, so roll back its complete private
  /// tree through the same durable cleanup path used by creation failures.
  static Future<void> recover(ProfileRegistry registry) async {
    final snapshot = await _withLedgerLock(_readLedger);
    for (final entry in snapshot.entries.entries) {
      final profileId = entry.key;
      final intendedKey = entry.value;
      await runExclusive(profileId, () async {
        final profile = await registry.getProfile(profileId);
        if (profile?.lifecycle == UserProfileLifecycle.staging) {
          await ProfileCleanupLedger.scheduleProfile(profileId);
          await registry.deleteProfile(profileId);
          await ProfileDataGenerationManager.deleteAllProfileData(profileId);
          await ProfileCleanupLedger.completeProfile(profileId);
          await complete(profileId);
          return;
        }

        final intended = ProfileAvatar.tryParse(intendedKey);
        if (profile == null) {
          await ProfileAvatarStorage.deleteAll(profileId);
          await complete(profileId);
          return;
        }

        final current = ProfileAvatar.tryParse(profile.avatarKey);
        if (profile.avatarKey != intendedKey && intended != null) {
          await ProfileAvatarStorage.deleteCandidate(
            profileId,
            intended,
            preserve: current,
          );
        }
        if (current?.kind == ProfileAvatarKind.image) {
          await ProfileAvatarStorage.pruneExcept(profileId, current!);
        } else {
          await ProfileAvatarStorage.deleteAll(profileId);
        }
        await ProfileAvatarStorage.cleanupTemporary(profileId);
        await _deleteRestoreStaging(profileId);
        await complete(profileId);
      });
    }
  }

  static Future<T> _withLedgerLock<T>(Future<T> Function() operation) async {
    final previous = _ledgerTail;
    final release = Completer<void>();
    _ledgerTail = release.future;
    try {
      try {
        await previous;
      } catch (_) {
        // A failed ledger operation must not permanently block recovery.
      }
      return await operation();
    } finally {
      release.complete();
    }
  }

  /// Avatar restore attachments are intentionally excluded from generation
  /// manifests. A crash after publication can therefore leave their staging
  /// copy inside the now-visible generation unless the avatar intent recovery
  /// removes it explicitly.
  static Future<void> _deleteRestoreStaging(String profileId) async {
    final documents = await AppStorage.documents();
    final generations = Directory(
      p.join(documents.path, 'profiles', profileId, 'g'),
    );
    if (!await generations.exists()) return;
    await for (final generation in generations.list(followLinks: false)) {
      if (generation is! Directory) continue;
      final staging = Directory(
        p.join(generation.path, 'documents', '.avatar-restore'),
      );
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  static Future<File> _ledgerFile() async =>
      File('${(await AppStorage.support()).path}/$_ledgerName');

  static Future<_AvatarMutationLedgerState> _readLedger() async {
    final target = await _ledgerFile();
    // A slot is installed by rename only after its temporary sibling has been
    // flushed. A crash before that rename leaves no authoritative mutation, so
    // the abandoned temporary file is always safe to discard.
    for (final temporary in <File>[
      File('${target.path}.write.tmp'),
      File('${target.path}.next.write.tmp'),
    ]) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // An official slot, when present, remains the only authority.
      }
    }
    final candidates = <_AvatarMutationLedgerState>[];
    var any = false;
    for (final file in <File>[target, File('${target.path}.next')]) {
      if (!await file.exists()) continue;
      any = true;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map<String, dynamic> ||
            decoded['version'] != 1 ||
            decoded['sequence'] is! int ||
            decoded['profiles'] is! Map) {
          continue;
        }
        final entries = <String, String>{};
        var valid = true;
        for (final entry in (decoded['profiles'] as Map).entries) {
          if (entry.key is! String ||
              entry.value is! String ||
              !ProfileScope.isValidProfileId(entry.key as String) ||
              ProfileAvatar.tryParse(entry.value as String) == null) {
            valid = false;
            break;
          }
          entries[entry.key as String] = entry.value as String;
        }
        if (valid) {
          candidates.add(
            _AvatarMutationLedgerState(
              sequence: decoded['sequence'] as int,
              entries: entries,
            ),
          );
        }
      } catch (_) {
        // The independently flushed sibling slot may still be authoritative.
      }
    }
    if (candidates.isEmpty) {
      if (!any) return _AvatarMutationLedgerState(sequence: 0, entries: {});
      throw const FormatException('Avatar mutation ledger is corrupt');
    }
    candidates.sort((a, b) => a.sequence.compareTo(b.sequence));
    return candidates.last;
  }

  static Future<void> _writeLedger(_AvatarMutationLedgerState current) async {
    final target = await _ledgerFile();
    await target.parent.create(recursive: true);
    final slots = <File>[target, File('${target.path}.next')];
    final sequences = <File, int>{};
    for (final slot in slots) {
      if (!await slot.exists()) continue;
      try {
        final decoded = jsonDecode(await slot.readAsString());
        if (decoded is Map && decoded['sequence'] is int) {
          sequences[slot] = decoded['sequence'] as int;
        }
      } catch (_) {
        sequences[slot] = -1;
      }
    }
    final slot = slots.firstWhere(
      (candidate) => !sequences.containsKey(candidate),
      orElse: () =>
          sequences[slots[0]]! <= sequences[slots[1]]! ? slots[0] : slots[1],
    );
    final temporary = File('${slot.path}.write.tmp');
    if (await temporary.exists()) await temporary.delete();
    try {
      await temporary.writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'sequence': current.sequence + 1,
          'profiles': current.entries,
        }),
        flush: true,
      );
      // On platforms where rename cannot replace an existing file, deleting
      // this slot is still safe: every replacement happens only after another
      // independently valid slot exists. The first-ever slot starts absent.
      if (await slot.exists()) await slot.delete();
      await temporary.rename(slot.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

class _AvatarMutationLedgerState {
  final int sequence;
  final Map<String, String> entries;

  const _AvatarMutationLedgerState({
    required this.sequence,
    required this.entries,
  });
}
