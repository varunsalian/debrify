import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/theme_core_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `AppThemeController.warm()` is called twice in this app's life: once before
/// `runApp`, and again on every profile switch. Only the second caller has
/// listeners, and it is the one that matters — the root `MaterialApp` and
/// `AppThemeScope` are built ABOVE `ProfileGate`, so the gate's own setState
/// can never re-read them. A silent warm left the incoming profile wearing the
/// outgoing profile's theme until the user re-picked one or restarted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProfileScope scopeFor(String id, int epoch) =>
      ProfileScope(profileId: id, dataGeneration: 1, sessionEpoch: epoch);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'p.alpha.g.1.app_theme': 'signal',
      'p.beta.g.1.app_theme': AppThemes.legacyId,
    });
    ProfileRuntime.debugReset();
    ThemeCoreResolver.debugReset();
  });

  tearDown(ProfileRuntime.debugReset);

  test('warm publishes the newly active profile theme to listeners', () async {
    ProfileRuntime.initializeCommitted(scopeFor('alpha', 1));
    await AppThemeController.warm();
    expect(AppThemeController.instance.id, 'signal');

    var notifications = 0;
    void listener() => notifications++;
    AppThemeController.instance.addListener(listener);
    addTearDown(() => AppThemeController.instance.removeListener(listener));

    // What a profile switch does: publish the new scope, then re-warm.
    ProfileRuntime.publish(scopeFor('beta', 2));
    await AppThemeController.warm();

    expect(
      AppThemeController.instance.id,
      AppThemes.legacyId,
      reason: 'warm must read the newly published scope',
    );
    expect(
      notifications,
      greaterThan(0),
      reason: 'a silent warm strands the root MaterialApp on the old theme',
    );
  });

  test('warm keeps the derived pair in step with the id it published', () async {
    ProfileRuntime.initializeCommitted(scopeFor('beta', 1));
    await AppThemeController.warm();
    final legacyData = AppThemeController.instance.themeData;

    ProfileRuntime.publish(scopeFor('alpha', 2));
    await AppThemeController.warm();

    expect(AppThemeController.instance.id, 'signal');
    expect(
      identical(AppThemeController.instance.themeData, legacyData),
      isFalse,
      reason: 'the notified rebuild reads themeData — it must be recomputed',
    );
  });
}
