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

  test('user data is durable by default; only named caches drop', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(scoped('my_watchlist_v1'), '[{"key":"movie:tt1"}]');
    await prefs.setString(scoped('debrify_tv_favorite_channels_v1'), '["ch1"]');
    await prefs.setString(scoped('playback_state_v1'), '{}');
    await prefs.setBool(scoped('home_continue_watching_enabled'), false);
    await prefs.setInt(scoped('theme_index'), 3);
    await prefs.setString(scoped('trakt_watchlist_cache'), '{}');
    await prefs.setString(scoped('tvmaze_series_mappings'), '{}');
    await prefs.setString(scoped('epg_guides'), '{}');
    await prefs.setString(scoped('trakt_continue_watching_shows'), '[]');

    final exported = await exportedPreferences();
    expect(exported[scoped('my_watchlist_v1')], '[{"key":"movie:tt1"}]');
    expect(exported[scoped('debrify_tv_favorite_channels_v1')], '["ch1"]');
    expect(exported[scoped('playback_state_v1')], '{}');
    expect(exported[scoped('home_continue_watching_enabled')], false);
    expect(exported[scoped('theme_index')], 3);
    expect(exported.containsKey(scoped('trakt_watchlist_cache')), isFalse);
    expect(exported.containsKey(scoped('tvmaze_series_mappings')), isFalse);
    expect(exported.containsKey(scoped('epg_guides')), isFalse);
    expect(
      exported.containsKey(scoped('trakt_continue_watching_shows')),
      isFalse,
    );
  });

  test('the launch-time import rebuilds without deleting live keys', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(scoped('my_watchlist_v1'), '[{"key":"movie:tt1"}]');
    await prefs.setString(scoped('epg_guides'), '{}');

    await registry.importRecoverySnapshot(
      await registry.exportRecoverySnapshot(),
    );

    expect(prefs.getString(scoped('my_watchlist_v1')), '[{"key":"movie:tt1"}]');
    expect(
      prefs.getString(scoped('epg_guides')),
      '{}',
      reason: 'a live cache is dropped from the envelope, not purged locally',
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

  test('a full envelope drops only the largest values, never throws', () async {
    final prefs = await SharedPreferences.getInstance();
    // Eight ~65KB values plus the watchlist exceed the 512KiB bound. Packing
    // is smallest-first, so the small user data always fits and only the
    // biggest note falls out.
    for (var i = 0; i < 8; i++) {
      await prefs.setString(scoped('note_$i'), 'x' * 65000);
    }
    await prefs.setString(scoped('my_watchlist_v1'), 'w' * 30000);
    await prefs.setInt(scoped('theme_index'), 3);

    final exported = await exportedPreferences();
    expect(exported.containsKey(scoped('my_watchlist_v1')), isTrue);
    expect(exported[scoped('theme_index')], 3);
    final notesKept = List.generate(
      8,
      (i) => exported.containsKey(scoped('note_$i')),
    ).where((kept) => kept).length;
    expect(notesKept, 7, reason: 'exactly the largest overflow is skipped');
  });

  test('device-owned WebDAV sync state never enters tvOS recovery', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webdav_sync_state_v1', 'sealed-device-state');
    await prefs.setString(scoped('theme_index'), '3');

    final encoded = await registry.exportRecoverySnapshot();
    final exported = await exportedPreferences();

    expect(exported, isNot(contains('webdav_sync_state_v1')));
    expect(encoded, isNot(contains('sealed-device-state')));
  });
}
