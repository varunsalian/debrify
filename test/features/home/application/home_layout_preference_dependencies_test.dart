import 'dart:async';
import 'package:debrify/features/home/application/home_layout_preference_dependencies.dart';
import 'package:debrify/features/home/data/home_layout_preferences.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
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
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfileRuntime.debugReset);
  HomeCatalogSession session() => HomeCatalogSession(
    owner: ProfileSessionMemory.captureOwner(),
    viewIdentity: Object(),
  );

  for (final retire in ['profile', 'dispose', 'recompute']) {
    test(
      '$retire rejects pending layout; a replacement operation remains usable',
      () async {
        final response = Completer<String>();
        var reads = 0;
        final container = ProviderContainer.test(
          overrides: [
            homeLayoutPreferencesProvider.overrideWithValue(
              HomeLayoutPreferences(
                readCached: () => 'classic',
                readSaved: () {
                  reads++;
                  return response.future;
                },
              ),
            ),
          ],
        );
        final key = session();
        final subscription = container.listen(
          homeLayoutPreferenceProvider(key),
          (_, _) {},
        );
        final operation = subscription.read();
        expect(operation.initialStyle, 'classic');
        expect(reads, 0);
        final pending = operation.load(
          isCurrent: () => true,
          currentStyle: () => 'classic',
          transition: (_) => fail('retired transition'),
        );
        switch (retire) {
          case 'profile':
            ProfileSessionMemory.clearAll();
          case 'dispose':
            container.dispose();
          case 'recompute':
            container.invalidate(homeLayoutPreferenceProvider(key));
            subscription.read();
        }
        response.complete('spotlight');
        await pending;
        if (retire == 'recompute') {
          final transitions = <String>[];
          await subscription.read().load(
            isCurrent: () => true,
            currentStyle: () => 'classic',
            transition: transitions.add,
          );
          expect(transitions, ['spotlight']);
          expect(subscription.read(), isNot(same(operation)));
        }
        expect(reads, retire == 'recompute' ? 2 : 1);
      },
    );
  }
  test(
    'each view captures the current cache; reads preserve normalization and profile keys',
    () async {
      final scope = ProfileScope(
        profileId: 'layout',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      SharedPreferences.setMockInitialValues({
        scope.preferenceKey('tv_home_style'): 'spotlight',
        'tv_home_style': 'mosaic',
      });
      StorageService.tvHomeStyleCached = 'classic';
      final container = ProviderContainer.test();
      final first = container
          .listen(homeLayoutPreferenceProvider(session()), (_, _) {})
          .read();
      expect(first.initialStyle, 'classic');
      final transitions = <String>[];
      await first.load(
        isCurrent: () => true,
        currentStyle: () => 'classic',
        transition: transitions.add,
      );
      expect(transitions, ['spotlight']);
      expect(StorageService.tvHomeStyleCached, 'spotlight');
      final second = container
          .listen(homeLayoutPreferenceProvider(session()), (_, _) {})
          .read();
      expect(second.initialStyle, 'spotlight');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(scope.preferenceKey('tv_home_style'), 'invalid');
      await second.load(
        isCurrent: () => true,
        currentStyle: () => 'spotlight',
        transition: transitions.add,
      );
      expect(transitions, ['spotlight', 'canvas']);
      expect(prefs.getString(scope.preferenceKey('tv_home_style')), 'invalid');
      expect(first.initialStyle, 'classic');
    },
  );
}
