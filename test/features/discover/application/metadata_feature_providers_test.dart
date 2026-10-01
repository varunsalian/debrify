import 'dart:convert';
import 'package:debrify/features/discover/application/discover_providers.dart';
import 'package:debrify/features/discover/models/metadata_feature_policy.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
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
  MetadataFeatureReader reader() {
    final container = ProviderContainer.test();
    final key = (
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container.listen(metadataFeatureReaderProvider(key), (_, _) {});
    return container.read(metadataFeatureReaderProvider(key));
  }

  test(
    'default reader preserves service decoding and sees changed settings',
    () async {
      final read = reader();
      final initial = await read();
      expect(initial.features, contains(MetadataFeature.discovery));
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        MetadataPreferencesService.key,
        jsonEncode(
          MetadataPreferences(features: {}, language: 'hi-IN').toJson(),
        ),
      );
      final disabled = await read();
      expect(disabled.features, isEmpty);
      expect(disabled.language, 'hi-IN');
      await preferences.setString(MetadataPreferencesService.key, '{invalid');
      expect((await read()).features, contains(MetadataFeature.discovery));
    },
  );
  test('retired reader rejects before resolving an incoming profile', () async {
    final read = reader();
    ProfileSessionMemory.clearAll();
    await expectLater(read(), throwsStateError);
  });
}
