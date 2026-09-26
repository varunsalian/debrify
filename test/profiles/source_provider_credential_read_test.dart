import 'dart:async';

import 'package:debrify/services/profiles/profile_preferences.dart';
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
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfilePreferences.debugResetMutationTracking();
    SecretVault.debugReset(deviceIdOverride: 'source-reader-fixture');
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });

  final readers = <String, Future<String?> Function(bool Function())>{
    'real_debrid_api_key': (active) =>
        StorageService.getApiKey(canContinue: active),
    'torbox_api_key': (active) =>
        StorageService.getTorboxApiKey(canContinue: active),
    'premiumize_api_key': (active) =>
        StorageService.getPremiumizeApiKey(canContinue: active),
    'alldebrid_api_key': (active) =>
        StorageService.getAllDebridApiKey(canContinue: active),
    'pikpak_email': (active) =>
        StorageService.getPikPakEmail(canContinue: active),
  };
  for (final entry in readers.entries) {
    test('${entry.key} migrates only for a current read', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(entry.key, 'fixture-value');
      expect(await entry.value(() => false), isNull);
      expect(prefs.getString(entry.key), 'fixture-value');
      expect(await entry.value(() => true), 'fixture-value');
      expect(prefs.getString(entry.key), startsWith(SecretVault.prefix));
      expect(
        await SecretVault.open(prefs.getString(entry.key)!),
        'fixture-value',
      );
    });
  }

  test(
    'PikPak availability guards its legacy email read and retains enablement',
    () async {
      SharedPreferences.setMockInitialValues({
        'pikpak_enabled': true,
        'pikpak_email': 'fixture-email',
      });
      expect(
        await StorageService.getPikPakEnabled(canContinue: () => false),
        isFalse,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pikpak_email'), 'fixture-email');
      expect(
        await StorageService.getPikPakEnabled(canContinue: () => true),
        isTrue,
      );
      expect(prefs.getString('pikpak_email'), startsWith(SecretVault.prefix));
    },
  );

  for (final retirement in ['view', 'clear', 'switch', 'replacement', 'none']) {
    test(
      'blocked scalar migration respects $retirement before writing',
      () async {
        const key =
            'fixture-credential'; // No committed resource routing for this key.
        final first = ProfileScope(
          profileId: 'first',
          dataGeneration: 1,
          sessionEpoch: 1,
        );
        final second = ProfileScope(
          profileId: 'second',
          dataGeneration: 1,
          sessionEpoch: 2,
        );
        ProfileRuntime.initializeCommitted(first);
        final owner = ProfileSessionMemory.captureOwner();
        final prefs = await ProfilePreferences.instance();
        final raw = await SharedPreferences.getInstance();
        await raw.setString(first.preferenceKey(key), 'original');
        await raw.setString(second.preferenceKey(key), 'incoming');
        final replacement = await SecretVault.seal('replacement');
        final entered = Completer<void>();
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        var active = true;
        var finished = false;
        final reading = SecretVault.getString(
          prefs,
          key,
          canContinue: () =>
              active && owner == ProfileSessionMemory.captureOwner(),
        ).whenComplete(() => finished = true);
        await Future<void>.delayed(Duration.zero);
        expect(finished, isFalse);
        if (retirement == 'view') active = false;
        if (retirement == 'clear') ProfileSessionMemory.clearAll();
        if (retirement == 'switch') ProfileRuntime.publish(second);
        if (retirement == 'replacement') {
          await raw.setString(first.preferenceKey(key), replacement);
        }
        release.complete();
        await snapshot;
        final current = retirement == 'none' || retirement == 'replacement';
        expect(await reading, current ? 'original' : null);
        final stored = raw.getString(first.preferenceKey(key));
        if (retirement == 'none') {
          expect(stored, startsWith(SecretVault.prefix));
          expect(await SecretVault.open(stored!), 'original');
        } else {
          expect(
            stored,
            retirement == 'replacement' ? replacement : 'original',
          );
        }
        expect(raw.getString(second.preferenceKey(key)), 'incoming');
      },
    );
  }
}
