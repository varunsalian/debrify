import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_preference_portability.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/theme/app_looks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    await StorageService.getLaunchAnimation();
    LookApplier.debugResetGenerations();
  });
  test(
    'deleting B preserves A and deleting A uses built-in fallback',
    () async {
      await StorageService.setLaunchAnimation('horizon');
      await StorageService.setImportedLaunchAnimation(a);
      await StorageService.clearImportedLaunchAnimationIf(b);
      expect(StorageService.importedLaunchAnimationCached, a);
      await StorageService.clearImportedLaunchAnimationIf(a);
      expect(StorageService.importedLaunchAnimationCached, isNull);
      expect(await StorageService.getLaunchAnimation(), 'horizon');
    },
  );
  test('choosing same built-in fallback disables imported override', () async {
    await StorageService.setLaunchAnimation('trace');
    await StorageService.setImportedLaunchAnimation(a);
    await StorageService.setLaunchAnimation('trace');
    expect(StorageService.importedLaunchAnimationCached, isNull);
    await StorageService.getLaunchAnimation();
    expect(StorageService.importedLaunchAnimationCached, isNull);
  });
  test('newer imported choice wins over queued built-in write', () async {
    final old = StorageService.setLaunchAnimation('horizon');
    final newer = StorageService.setImportedLaunchAnimation(a);
    await Future.wait([old, newer]);
    await StorageService.getLaunchAnimation();
    expect(StorageService.importedLaunchAnimationCached, a);
  });
  test(
    'a new selection survives concurrent deletion of the old selection',
    () async {
      await StorageService.setImportedLaunchAnimation(a);
      await Future.wait([
        StorageService.clearImportedLaunchAnimationIf(a),
        StorageService.setImportedLaunchAnimation(b),
      ]);
      await StorageService.getLaunchAnimation();
      expect(StorageService.importedLaunchAnimationCached, b);
    },
  );
  test('imported override never enters portable or sanitized preferences', () {
    expect(
      ProfilePreferencePortability.allowsKey(
        StorageService.importedLaunchAnimationKey,
      ),
      isFalse,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        StorageService.importedLaunchAnimationKey,
        a,
      ),
      isFalse,
    );
  });
  test('warming after a profile switch replaces the cached override', () async {
    final prefs = await SharedPreferences.getInstance();
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
    await prefs.setString(
      first.preferenceKey(StorageService.importedLaunchAnimationKey),
      a,
    );
    ProfileRuntime.initializeCommitted(first);
    await StorageService.getLaunchAnimation();
    expect(StorageService.importedLaunchAnimationCached, a);
    ProfileRuntime.publish(second);
    await StorageService.getLaunchAnimation();
    expect(StorageService.importedLaunchAnimationCached, isNull);
  });
}
