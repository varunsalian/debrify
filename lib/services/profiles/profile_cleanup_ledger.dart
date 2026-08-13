import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../utils/app_storage.dart';
import 'profile_data_generation.dart';
import 'profile_registry.dart';

/// Durable, idempotent cleanup authority kept outside the profile registry.
/// Registry rows may disappear before filesystem cleanup, so profile IDs live
/// here until every private path and preference prefix has been removed.
class ProfileCleanupLedger {
  ProfileCleanupLedger._();

  static const String _name = 'profile-cleanup-ledger-v1.json';

  static Future<void> scheduleProfile(String profileId) async {
    final pending = await _read();
    pending.add(profileId);
    await _write(pending);
  }

  static Future<void> completeProfile(String profileId) async {
    final pending = await _read();
    pending.remove(profileId);
    await _write(pending);
  }

  static Future<void> resume(ProfileRegistry? registry) async {
    final pending = await _read();
    for (final profileId in pending.toList(growable: false)) {
      // A crash after scheduling but before graph deletion leaves the profile
      // live. Cancel that preparation; cleanup is valid only after the graph is
      // gone.
      if (registry != null && await registry.getProfile(profileId) != null) {
        pending.remove(profileId);
        await _write(pending);
        continue;
      }
      await ProfileDataGenerationManager.deleteAllProfileData(profileId);
      pending.remove(profileId);
      await _write(pending);
    }
  }

  static Future<File> _file() async =>
      File(p.join((await AppStorage.support()).path, _name));

  static Future<Set<String>> _read() async {
    final target = await _file();
    final records = <Map<String, dynamic>>[];
    var any = false;
    for (final file in <File>[target, File('${target.path}.next')]) {
      if (!await file.exists()) continue;
      any = true;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic> &&
            decoded['version'] == 1 &&
            decoded['sequence'] is int &&
            decoded['profiles'] is List &&
            (decoded['profiles'] as List).every((item) => item is String)) {
          records.add(decoded);
        }
      } catch (_) {
        // The other independently flushed slot remains authoritative.
      }
    }
    if (records.isEmpty) {
      if (!any) return <String>{};
      throw const FormatException('Profile cleanup ledger is corrupt');
    }
    records.sort(
      (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int),
    );
    return (records.last['profiles'] as List).cast<String>().toSet();
  }

  static Future<void> _write(Set<String> profiles) async {
    final target = await _file();
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
    final nextSequence =
        sequences.values.fold<int>(0, (a, b) => a > b ? a : b) + 1;
    final slot = slots.firstWhere(
      (candidate) => !sequences.containsKey(candidate),
      orElse: () =>
          sequences[slots[0]]! <= sequences[slots[1]]! ? slots[0] : slots[1],
    );
    await slot.writeAsString(
      jsonEncode(<String, Object?>{
        'version': 1,
        'sequence': nextSequence,
        'profiles': profiles.toList()..sort(),
      }),
      flush: true,
    );
  }
}
