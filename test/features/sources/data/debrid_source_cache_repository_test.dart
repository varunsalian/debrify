import 'package:debrify/features/sources/data/debrid_source_cache_repository.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'source-cache-test');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset();
  });

  DebridSourceCacheRepository repository() =>
      DebridSourceCacheRepository(owner: ProfileSessionMemory.captureOwner());

  for (final provider in ['torbox', 'premiumize']) {
    for (final missing in ['preference', 'integration', 'key', 'none']) {
      test(
        '$provider requires preference, integration and a nonempty key: missing=$missing',
        () async {
          SharedPreferences.setMockInitialValues({
            '${provider}_check_cache_before_search': missing != 'preference',
            '${provider}_integration_enabled': missing != 'integration',
            '${provider}_api_key': missing == 'key' ? '' : 'test-key',
          });
          final config = await repository().open();
          expect(
            provider == 'torbox'
                ? config.torboxEnabled
                : config.premiumizeEnabled,
            missing == 'none',
          );
        },
      );
    }
  }

  test(
    'credentials are captured per configuration and delegated using original protocols',
    () async {
      final tbCalls = <(String, List<String>)>[];
      final pmCalls = <(String, List<String>)>[];
      final repo = DebridSourceCacheRepository(
        owner: ProfileSessionMemory.captureOwner(),
        torboxCheck: ({required apiKey, required infoHashes}) async {
          tbCalls.add((apiKey, List.of(infoHashes)));
          return {'a'};
        },
        premiumizeCheck: (key, hashes) async {
          pmCalls.add((key, List.of(hashes)));
          return [true, false];
        },
      );
      await TorboxStorage.saveTorboxApiKey('first-tb');
      await PremiumizeStorage.savePremiumizeApiKey('first-pm');
      await TorboxStorage.setTorboxCacheCheckEnabled(true);
      await PremiumizeStorage.setPremiumizeCacheCheckEnabled(true);
      final first = await repo.open();
      await TorboxStorage.saveTorboxApiKey('next-tb');
      await PremiumizeStorage.savePremiumizeApiKey('next-pm');
      final next = await repo.open();
      expect(tbCalls, isEmpty);
      expect(pmCalls, isEmpty);
      expect(await first.torbox(['a', 'b']), {'a'});
      expect(await first.premiumize(['a', 'b']), [true, false]);
      await next.torbox(['c']);
      await next.premiumize(['c']);
      expect(tbCalls.map((call) => call.$1), ['first-tb', 'next-tb']);
      expect(tbCalls.map((call) => call.$2), [
        ['a', 'b'],
        ['c'],
      ]);
      expect(pmCalls.map((call) => call.$1), ['first-pm', 'next-pm']);
      expect(pmCalls.map((call) => call.$2), [
        ['a', 'b'],
        ['c'],
      ]);
    },
  );

  test(
    'retired sessions cannot dispatch either provider or reload credentials',
    () async {
      var calls = 0;
      final repo = DebridSourceCacheRepository(
        owner: ProfileSessionMemory.captureOwner(),
        torboxCheck: ({required apiKey, required infoHashes}) async {
          calls++;
          return {};
        },
        premiumizeCheck: (key, hashes) async {
          calls++;
          return [];
        },
      );
      await TorboxStorage.saveTorboxApiKey('test-key');
      await PremiumizeStorage.savePremiumizeApiKey('test-key');
      final config = await repo.open();
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'next', dataGeneration: 1, sessionEpoch: 2),
      );
      expect(() => config.torbox(['a']), throwsStateError);
      expect(() => config.premiumize(['a']), throwsStateError);
      await expectLater(repo.open(), throwsStateError);
      expect(calls, 0);
    },
  );
}
