import 'package:debrify/features/discover/application/discover_layout_controller.dart';
import 'package:debrify/features/discover/models/discover_layout_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfileSessionMemory.clearAll();
    SharedPreferences.setMockInitialValues({'discover_layout': 'grid'});
    StorageService.discoverLayoutCached = 'stage';
  });
  tearDown(() {
    ProfileRuntime.debugReset();
    StorageService.discoverLayoutCached = 'stage';
  });
  DiscoverLayoutSession session() =>
      (owner: ProfileSessionMemory.captureOwner(), viewIdentity: Object());
  DiscoverLayoutController controller(ProviderContainer container) {
    final key = session();
    container.listen(discoverLayoutProvider(key), (_, _) {});
    return container.read(discoverLayoutProvider(key).notifier);
  }

  Future<void> load(DiscoverLayoutController operation) =>
      operation.load(isCurrent: () => true, onChanged: () {});

  test(
    'same-session re-entry stays warm; views retain independent accepted state',
    () async {
      final firstContainer = ProviderContainer.test();
      final first = controller(firstContainer);
      expect(first.current, 'stage');
      await load(first);
      expect(first.current, 'grid');
      expect(StorageService.discoverLayoutCached, 'grid');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('discover_layout', 'stage');
      final second = controller(ProviderContainer.test());
      expect(second.current, 'grid');
      await load(second);
      expect(second.current, 'stage');
      expect(first.current, 'grid');
      firstContainer.dispose();
      expect(controller(ProviderContainer.test()).current, 'stage');
    },
  );

  test(
    'profile preferences normalize reads without rewriting the saved value',
    () async {
      final scope = ProfileScope(
        profileId: 'layout',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.promoteLegacyToCommitted(scope);
      SharedPreferences.setMockInitialValues({
        scope.preferenceKey('discover_layout'): 'grid',
        'discover_layout': 'stage',
      });
      final operation = controller(ProviderContainer.test());
      await load(operation);
      expect(operation.current, 'grid');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(scope.preferenceKey('discover_layout'), 'unknown');
      await load(operation);
      expect(operation.current, 'stage');
      expect(
        prefs.getString(scope.preferenceKey('discover_layout')),
        'unknown',
      );
    },
  );

  test(
    'handoff clears the first-frame mirror without reading storage',
    () async {
      final first = controller(ProviderContainer.test());
      await load(first);
      expect(controller(ProviderContainer.test()).current, 'grid');
      ProfileSessionMemory.clearAll();
      expect(controller(ProviderContainer.test()).current, 'stage');
      expect(StorageService.discoverLayoutCached, 'grid');
    },
  );

  test(
    'profile change during the real read cannot overwrite either layout cache',
    () async {
      final firstScope = ProfileScope(
        profileId: 'old',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final nextScope = ProfileScope(
        profileId: 'next',
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      ProfileRuntime.promoteLegacyToCommitted(firstScope);
      SharedPreferences.setMockInitialValues({
        firstScope.preferenceKey('discover_layout'): 'grid',
        nextScope.preferenceKey('discover_layout'): 'stage',
      });
      final operation = controller(ProviderContainer.test());
      final pending = load(operation);
      ProfileRuntime.publish(nextScope);
      await pending;
      expect(operation.current, 'stage');
      expect(StorageService.discoverLayoutCached, 'stage');
      expect(controller(ProviderContainer.test()).current, 'stage');
    },
  );

  test(
    'storage getter retains its return contract but guards shared cache publication',
    () async {
      var current = true;
      final pending = StorageService.getDiscoverLayout(
        canContinue: () => current,
      );
      current = false;
      expect(await pending, 'grid');
      expect(StorageService.discoverLayoutCached, 'stage');
      expect(await StorageService.getDiscoverLayout(), 'grid');
      expect(StorageService.discoverLayoutCached, 'grid');
    },
  );
}
