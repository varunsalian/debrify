import 'package:debrify/features/sources/data/stored_source_settings_repository.dart';
import 'package:debrify/features/sources/models/sources_session.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
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

  StoredSourceSettingsRepository repository() => StoredSourceSettingsRepository(
    SourcesSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
      selection: const AdvancedSearchSelection(
        imdbId: 'tt-settings',
        title: 'Fixture',
        isSeries: true,
      ),
    ),
  );

  test(
    'missing appearance preferences retain shipped true defaults without writing',
    () async {
      expect(await repository().loadAppearance(), (text: true, logos: true));
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    },
  );

  test('reads both original appearance keys independently', () async {
    SharedPreferences.setMockInitialValues({
      'sources_use_addon_text': false,
      'sources_show_addon_logos': true,
    });
    expect(await repository().loadAppearance(), (text: false, logos: true));
  });

  test(
    'profile appearance uses captured scope; retired repository rejects further reads',
    () async {
      final first = ProfileScope(
        profileId: 'first',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final next = ProfileScope(
        profileId: 'next',
        dataGeneration: 1,
        sessionEpoch: 2,
      );
      SharedPreferences.setMockInitialValues({
        first.preferenceKey('sources_use_addon_text'): false,
        first.preferenceKey('sources_show_addon_logos'): true,
        next.preferenceKey('sources_use_addon_text'): true,
        next.preferenceKey('sources_show_addon_logos'): false,
      });
      ProfileRuntime.initializeCommitted(first);
      final original = repository();
      expect(await original.loadAppearance(), (text: false, logos: true));
      ProfileRuntime.publish(next);
      expect(original.isCurrent, isFalse);
      expect(await original.loadAppearance(), (text: false, logos: false));
      expect((await original.loadPriority()).providers, isEmpty);
      expect(await repository().loadAppearance(), (text: true, logos: false));
    },
  );
}
