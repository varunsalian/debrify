import 'package:debrify/features/search/data/debrid_keyword_cache_repository.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'keyword-cache-test');
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SecretVault.debugReset();
  });

  DebridKeywordCacheRepository repository() =>
      DebridKeywordCacheRepository(owner: ProfileSessionMemory.captureOwner());

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

  for (final provider in ['real_debrid', 'premiumize', 'alldebrid', 'pikpak']) {
    test(
      '$provider usable integration prevents TorBox-only filtering',
      () async {
        SharedPreferences.setMockInitialValues({
          if (provider == 'pikpak') ...{
            'pikpak_enabled': true,
            'pikpak_email': 'fixture@example.invalid',
          } else ...{
            '${provider}_integration_enabled': true,
            '${provider}_api_key': 'test-key',
          },
        });
        final config = await repository().open();
        expect(config.otherProviderActive, isTrue);
        expect(config.premiumizeEnabled, isFalse); // cache preference is off
        expect(config.torboxEnabled, isFalse);
      },
    );
  }

  test(
    'credentials are captured per search and delegated using original protocols',
    () async {
      final tbCalls = <(String, List<String>)>[];
      final pmCalls = <(String, List<String>)>[];
      final repo = DebridKeywordCacheRepository(
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
      await StorageService.saveTorboxApiKey('first-tb');
      await StorageService.savePremiumizeApiKey('first-pm');
      await StorageService.setTorboxCacheCheckEnabled(true);
      await StorageService.setPremiumizeCacheCheckEnabled(true);
      final first = await repo.open();
      await StorageService.saveTorboxApiKey('next-tb');
      await StorageService.savePremiumizeApiKey('next-pm');
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
      final repo = DebridKeywordCacheRepository(
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
      await StorageService.saveTorboxApiKey('test-key');
      await StorageService.savePremiumizeApiKey('test-key');
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
