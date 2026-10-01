import 'dart:async';
import 'package:debrify/features/home/application/home_pikpak_only_controller.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const keys = [
    'pikpak_email',
    'real_debrid_api_key',
    'torbox_api_key',
    'premiumize_api_key',
    'alldebrid_api_key',
  ];
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfilePreferences.debugResetMutationTracking();
    SecretVault.debugReset(deviceIdOverride: 'home-availability-fixture');
    SharedPreferences.setMockInitialValues({
      'pikpak_enabled': true,
      for (final key in keys) key: 'fixture-value',
    });
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    SecretVault.debugReset();
  });
  HomePikpakOnlyController mount() {
    final container = ProviderContainer.test();
    final key = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container.listen(homePikpakOnlyProvider(key), (_, _) {});
    return container.read(homePikpakOnlyProvider(key).notifier);
  }

  test(
    'default adapter reads and migrates every original key without exposing credentials in state',
    () async {
      final controller = mount();
      await controller.load(
        isCurrent: () => true,
        onChanged: () => fail('false state is unchanged'),
      );
      expect(controller.current, isFalse);
      final prefs = await SharedPreferences.getInstance();
      for (final key in keys) {
        expect(prefs.getString(key), startsWith(SecretVault.prefix));
      }
    },
  );
  test(
    'retirement while legacy migration waits prevents credential writes and repaint',
    () async {
      final controller = mount();
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
      var finished = false;
      final pending = controller
          .load(isCurrent: () => true, onChanged: () => fail('retired repaint'))
          .whenComplete(() => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      ProfileSessionMemory.clearAll();
      release.complete();
      await snapshot;
      await pending;
      final prefs = await SharedPreferences.getInstance();
      for (final key in keys) {
        expect(prefs.getString(key), 'fixture-value');
      }
      expect(controller.current, isFalse);
    },
  );
}
