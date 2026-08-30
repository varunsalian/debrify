import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The tvOS recovery envelope excludes cache-shaped preferences by name, and
/// the built-in My Watchlist (`my_watchlist_v1`) matched the `watchlist`
/// pattern — so every tvOS launch, which rebuilds scoped preferences from the
/// envelope, wiped the user's saved shelf. These pin the exemption, and pin
/// that a full envelope SKIPS the watchlist instead of throwing: checkpoints
/// run inside preference writes, so a thrown bound would fail every
/// subsequent save.
void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late String adminId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp('recov-prefs-');
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
      policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
    );
    adminId = admin.id;
  });

  tearDown(() async {
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  String scoped(String logicalKey) => 'p.$adminId.g.1.$logicalKey';

  Future<Map<String, Object?>> exportedPreferences() async =>
      Map<String, Object?>.from(
        (jsonDecode(await registry.exportRecoverySnapshot())
                as Map<String, dynamic>)['preferences']
            as Map,
      );

  test('My Watchlist is recoverable; tracker caches stay excluded', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(scoped('my_watchlist_v1'), '[{"key":"movie:tt1"}]');
    await prefs.setString(scoped('trakt_watchlist_cache'), '{}');
    await prefs.setString(scoped('resume_positions'), '{}');
    await prefs.setInt(scoped('theme_index'), 3);

    final exported = await exportedPreferences();
    expect(exported[scoped('my_watchlist_v1')], '[{"key":"movie:tt1"}]');
    expect(exported[scoped('theme_index')], 3);
    expect(exported.containsKey(scoped('trakt_watchlist_cache')), isFalse);
    expect(exported.containsKey(scoped('resume_positions')), isFalse);
  });

  test('the watchlist survives the launch-time envelope import', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(scoped('my_watchlist_v1'), '[{"key":"movie:tt1"}]');
    await prefs.setString(scoped('resume_positions'), '{}');

    await registry.importRecoverySnapshot(
      await registry.exportRecoverySnapshot(),
    );

    expect(prefs.getString(scoped('my_watchlist_v1')), '[{"key":"movie:tt1"}]');
    expect(
      prefs.containsKey(scoped('resume_positions')),
      isFalse,
      reason: 'non-recoverable keys are rebuilt away, as before',
    );
  });

  test('a watchlist the export dropped survives the import; stale-generation '
      'copies still clear', () async {
    final prefs = await SharedPreferences.getInstance();
    final oversized = 'w' * 70000; // over the 64KiB per-value envelope cap
    await prefs.setString(scoped('my_watchlist_v1'), oversized);
    await prefs.setString('p.$adminId.g.99.my_watchlist_v1', 'stale');

    await registry.importRecoverySnapshot(
      await registry.exportRecoverySnapshot(),
    );

    expect(
      prefs.getString(scoped('my_watchlist_v1')),
      oversized,
      reason: 'an export skip must never become an import deletion',
    );
    expect(prefs.containsKey('p.$adminId.g.99.my_watchlist_v1'), isFalse);
  });

  test('a full envelope skips My Watchlist instead of throwing', () async {
    final prefs = await SharedPreferences.getInstance();
    // Eight ~65KB values land just under the 512KiB bound on their own,
    // so adding the watchlist would cross it.
    for (var i = 0; i < 8; i++) {
      await prefs.setString(scoped('note_$i'), 'x' * 65000);
    }
    await prefs.setString(scoped('my_watchlist_v1'), 'w' * 30000);

    final exported = await exportedPreferences();
    expect(exported.containsKey(scoped('my_watchlist_v1')), isFalse);
    for (var i = 0; i < 8; i++) {
      expect(exported.containsKey(scoped('note_$i')), isTrue);
    }
  });
}
