import 'package:debrify/services/storage/launch_ident_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    await LaunchIdentStorage.getLaunchAnimation();
    LookApplier.debugResetGenerations();
  });
  test(
    'deleting B preserves A and deleting A uses built-in fallback',
    () async {
      await LaunchIdentStorage.setLaunchAnimation('horizon');
      await LaunchIdentStorage.setImportedLaunchAnimation(a);
      await LaunchIdentStorage.clearImportedLaunchAnimationIf(b);
      expect(LaunchIdentStorage.importedLaunchAnimationCached, a);
      await LaunchIdentStorage.clearImportedLaunchAnimationIf(a);
      expect(LaunchIdentStorage.importedLaunchAnimationCached, isNull);
      expect(await LaunchIdentStorage.getLaunchAnimation(), 'horizon');
    },
  );
  test('choosing same built-in fallback disables imported override', () async {
    await LaunchIdentStorage.setLaunchAnimation('trace');
    await LaunchIdentStorage.setImportedLaunchAnimation(a);
    await LaunchIdentStorage.setLaunchAnimation('trace');
    expect(LaunchIdentStorage.importedLaunchAnimationCached, isNull);
    await LaunchIdentStorage.getLaunchAnimation();
    expect(LaunchIdentStorage.importedLaunchAnimationCached, isNull);
  });
  test('newer imported choice wins over queued built-in write', () async {
    final old = LaunchIdentStorage.setLaunchAnimation('horizon');
    final newer = LaunchIdentStorage.setImportedLaunchAnimation(a);
    await Future.wait([old, newer]);
    await LaunchIdentStorage.getLaunchAnimation();
    expect(LaunchIdentStorage.importedLaunchAnimationCached, a);
  });
  test(
    'a new selection survives concurrent deletion of the old selection',
    () async {
      await LaunchIdentStorage.setImportedLaunchAnimation(a);
      await Future.wait([
        LaunchIdentStorage.clearImportedLaunchAnimationIf(a),
        LaunchIdentStorage.setImportedLaunchAnimation(b),
      ]);
      await LaunchIdentStorage.getLaunchAnimation();
      expect(LaunchIdentStorage.importedLaunchAnimationCached, b);
    },
  );
  test('imported override never enters portable or sanitized preferences', () {
    expect(
      ProfilePreferencePortability.allowsKey(
        LaunchIdentStorage.importedLaunchAnimationKey,
      ),
      isFalse,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        LaunchIdentStorage.importedLaunchAnimationKey,
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
      first.preferenceKey(LaunchIdentStorage.importedLaunchAnimationKey),
      a,
    );
    ProfileRuntime.initializeCommitted(first);
    await LaunchIdentStorage.getLaunchAnimation();
    expect(LaunchIdentStorage.importedLaunchAnimationCached, a);
    ProfileRuntime.publish(second);
    await LaunchIdentStorage.getLaunchAnimation();
    expect(LaunchIdentStorage.importedLaunchAnimationCached, isNull);
  });
}
