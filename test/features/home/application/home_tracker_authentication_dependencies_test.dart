import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/features/home/models/home_tracker_authentication.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset(deviceIdOverride: 'tracker-auth-fixture');
    SharedPreferences.setMockInitialValues({
      'trakt_access_token': 'fixture-trakt',
      'trakt_token_expiry': DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch,
      'simkl_access_token': 'fixture-simkl',
      'mdblist_api_key': 'fixture-mdblist',
    });
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });
  HomeTrackerAuthReader reader(HomeTracker tracker) {
    final container = ProviderContainer.test();
    final key = (
      view: HomeCatalogSession(
        owner: ProfileSessionMemory.captureOwner(),
        viewIdentity: Object(),
      ),
      tracker: tracker,
    );
    container.listen(homeTrackerAuthReaderProvider(key), (_, _) {});
    return container.read(homeTrackerAuthReaderProvider(key));
  }

  for (final tracker in HomeTracker.values) {
    test('$tracker uses its existing service authentication policy', () async {
      final read = reader(tracker);
      expect(await read(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      final key = switch (tracker) {
        HomeTracker.trakt => 'trakt_access_token',
        HomeTracker.simkl => 'simkl_access_token',
        HomeTracker.mdblist => 'mdblist_api_key',
      };
      await prefs.remove(key);
      expect(await read(), isFalse);
    });
  }
  test(
    'expired Trakt token without refresh token remains unauthenticated',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('trakt_token_expiry', 1);
      expect(await reader(HomeTracker.trakt)(), isFalse);
    },
  );
  test(
    'retired owner cannot start credential reads or legacy sealing',
    () async {
      final read = reader(HomeTracker.simkl);
      ProfileSessionMemory.clearAll();
      expect(await read(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('simkl_access_token'), 'fixture-simkl');
    },
  );
}
