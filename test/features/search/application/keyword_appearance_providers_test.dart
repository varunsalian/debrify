import 'package:debrify/features/search/application/keyword_appearance_controller.dart';
import 'package:debrify/features/search/models/search_session.dart';
import 'package:debrify/models/source_appearance.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
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

  SearchSession session() => SearchSession(
    owner: ProfileSessionMemory.captureOwner(),
    viewIdentity: Object(),
  );
  Future<void> load(ProviderContainer container, SearchSession key) => container
      .read(keywordAppearanceProvider(key).notifier)
      .load(isCurrent: () => true, onAccepted: () {});

  test(
    'default keyword adapter preserves stored true defaults and performs no writes',
    () async {
      final container = ProviderContainer.test();
      final key = session();
      final state = container.listen(keywordAppearanceProvider(key), (_, _) {});
      expect(state.read(), initialSourceAppearance);
      await load(container, key);
      expect(state.read(), (text: true, logos: true));
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test(
    'handoff clears accepted appearance and the new view reads its own keys',
    () async {
      final first = ProfileScope(
        profileId: 'appearance-first',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final next = ProfileScope(
        profileId: 'appearance-next',
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      SharedPreferences.setMockInitialValues({
        first.preferenceKey('sources_use_addon_text'): true,
        first.preferenceKey('sources_show_addon_logos'): false,
        next.preferenceKey('sources_use_addon_text'): false,
        next.preferenceKey('sources_show_addon_logos'): true,
      });
      ProfileRuntime.initializeCommitted(first);
      final container = ProviderContainer.test();
      final old = session();
      final oldState = container.listen(
        keywordAppearanceProvider(old),
        (_, _) {},
      );
      await load(container, old);
      expect(oldState.read(), (text: true, logos: false));
      ProfileRuntime.publish(next);
      await container.pump();
      expect(oldState.read(), initialSourceAppearance);
      await load(container, old);
      expect(oldState.read(), initialSourceAppearance);
      final fresh = session();
      final freshState = container.listen(
        keywordAppearanceProvider(fresh),
        (_, _) {},
      );
      await load(container, fresh);
      expect(freshState.read(), (text: false, logos: true));
    },
  );
}
