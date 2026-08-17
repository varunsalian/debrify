import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scope = ProfileScope(
    profileId: 'profile-a',
    dataGeneration: 3,
    sessionEpoch: 7,
  );

  setUp(() {
    ProfileRuntime.debugReset();
    StorageService.debugResetTvTrailerUnderlaySession();
  });

  tearDown(() {
    StorageService.debugResetTvTrailerUnderlaySession();
    ProfileRuntime.debugReset();
  });

  void installCommittedPreferences(Map<String, Object> values) {
    SharedPreferences.setMockInitialValues(values);
    ProfileRuntime.initializeCommitted(scope);
  }

  test('native underlay decision overrides a stale scoped snapshot', () async {
    installCommittedPreferences(<String, Object>{
      DevicePreferences.tvTrailerUnderlayEffectiveKey: false,
      scope.preferenceKey(DevicePreferences.tvTrailerUnderlayEffectiveKey):
          true,
      scope.preferenceKey('tv_trailer_underlay_enabled'): true,
    });

    expect(await StorageService.getTvTrailerUnderlayEnabledAtLaunch(), isFalse);
  });

  test(
    'missing native underlay decision falls back to the profile toggle',
    () async {
      installCommittedPreferences(<String, Object>{
        scope.preferenceKey(DevicePreferences.tvTrailerUnderlayEffectiveKey):
            true,
        scope.preferenceKey('tv_trailer_underlay_enabled'): false,
      });

      expect(
        await StorageService.getTvTrailerUnderlayEnabledAtLaunch(),
        isFalse,
      );
    },
  );

  test('low-resolution status reads only the native launch snapshot', () async {
    installCommittedPreferences(<String, Object>{
      DevicePreferences.tvLowResRenderActiveKey: true,
      scope.preferenceKey(DevicePreferences.tvLowResRenderActiveKey): false,
    });

    expect(await StorageService.getTvLowResRenderActive(), isTrue);

    SharedPreferences.setMockInitialValues(<String, Object>{
      scope.preferenceKey(DevicePreferences.tvLowResRenderActiveKey): true,
    });
    expect(await StorageService.getTvLowResRenderActive(), isNull);
  });
}
