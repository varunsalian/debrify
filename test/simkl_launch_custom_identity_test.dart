// A user's diagnostics (0.10.0-beta.1, Windows): with Simkl connected, every
// source picked for a catalog's own (custom) show threw
// `ArgumentError` from `MediaIdentity.apiIds` inside the launch-time Simkl
// refresh, and the player never opened. A tracker refresh must fail closed
// and never hold the player handoff.

import 'package:debrify/features/player_launch/presentation/legacy_launch/tracker_progress_seeding.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/services/episode_tracker_snapshot_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final custom = CustomSeriesIdentity('aiometadata', 'mal:21').id;
  final requests = <Uri>[];

  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'simkl-launch-custom');
    SimklService.instance.resetProfileScope();
    await SimklStorage.setSimklAccessToken('synthetic');
    requests.clear();
    EpisodeTrackerSnapshotService.debugResetRefreshState();
  });
  tearDown(() {
    SimklService.instance.resetProfileScope();
    SecretVault.debugReset();
    ProfileRuntime.debugReset();
  });

  Future<T> offline<T>(Future<T> Function() body) => http.runWithClient(
    body,
    () => MockClient((request) async {
      requests.add(request.url);
      return http.Response('[]', 200);
    }),
  );

  test('a custom show never reaches Simkl and never fails', () async {
    final watched = await offline(
      () => SimklService.instance.fetchWatchedShowEpisodesOrNull(custom),
    );

    expect(watched, isNull);
    expect(requests.where((u) => u.path == '/sync/watched'), isEmpty);
  });

  test('the launch-time Simkl refresh skips a custom show', () async {
    expect(
      await offline(() => EpisodeTrackerSnapshotService.refreshSimkl(custom)),
      isNull,
    );
    expect(requests, isEmpty);
  });

  test('the launch seed completes for a custom show', () async {
    await expectLater(
      offline(() => TrackerProgressSeeding.seedSimklEpisodeProgress(custom)),
      completes,
    );
    expect(requests, isEmpty);
  });
}
