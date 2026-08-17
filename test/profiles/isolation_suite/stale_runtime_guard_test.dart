import 'dart:io';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/theme_core_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Source-level guards for the isolation failures that survive a profile
/// switch **without an app relaunch**.
///
/// Data-at-rest isolation is covered elsewhere (see `profile_source_guard_test`
/// and the per-feature isolation tests). The failures guarded here are
/// different in kind: the bytes on disk are correctly partitioned, but a
/// process-global mirror still holds profile A's value, so profile B sees A's
/// data on screen until the app is killed. Every one of these has happened at
/// least once in this codebase.
///
/// Two shapes are used here, on purpose.
///
/// The first two are *source* guards: they parse `lib/` and prove the set of
/// resettable caches is completely covered. A behavioural test can only assert
/// about caches someone remembered to exercise, so only source parsing catches
/// the cache nobody thought about — which is the one that leaks.
///
/// The third is *behavioural*, because the source-guard version of it was
/// written first and silently passed while the bug it guards was reintroduced.
/// See the note above that group. Where a guard can be fooled by a comment,
/// drive the real thing instead.
///
/// Every assertion here has been mutation-tested: the bug it describes was
/// reintroduced and the guard confirmed to fail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storageSource = File(
    'lib/services/storage_service.dart',
  ).readAsStringSync();
  final participantSource = File(
    'lib/services/profiles/profile_app_lifecycle_participant.dart',
  ).readAsStringSync();

  test('every synchronous mirror is cleared on profile switch', () {
    // StorageService exposes `<name>Cached` statics that the UI reads
    // synchronously, precisely so a rebuild does not have to await a disk
    // read. That speed is why they are the sharpest stale-UI edge in the app:
    // a mirror left holding profile A's value is displayed to profile B
    // immediately, with no relaunch and no error anywhere.
    final declared = RegExp(
      r'^\s+static\s+[A-Za-z0-9<>?,\s]+\s+(_?[a-zA-Z0-9]+Cached)\b',
      multiLine: true,
    ).allMatches(storageSource).map((m) => m.group(1)!).toSet();

    expect(
      declared,
      isNotEmpty,
      reason: 'the mirror naming convention changed; update this guard',
    );

    final body = _bodyOf(storageSource, 'static void resetProfileCaches()');
    final unreset = declared.where((name) => !body.contains(name)).toList()
      ..sort();

    expect(
      unreset,
      isEmpty,
      reason:
          'These StorageService mirrors survive a profile switch, so the '
          'incoming profile sees the previous profile\'s value until the app '
          'is killed. Reset each in resetProfileCaches().',
    );
  });

  test('every profile-scoped cache is wired into the switch', () {
    // A service that grew a reset method but was never called from the
    // lifecycle participant is a cache that never resets. The method existing
    // is not the point — being *invoked on switch* is.
    // Each reason below was verified against the source on 2026-08-15, not
    // assumed from the file name. Two of them were wrong on the first pass —
    // an allowlist whose reasons are decorative is how a real leak gets
    // exempted, so re-verify rather than trust an entry when you add one.
    const deviceGlobalCaches = <String, String>{
      // Keyed purely on content identifiers — '<title>_<season>_<episode>',
      // 'imdb_<id>', title+year — and holding public API responses. An
      // episode's air date does not depend on who is watching, so keeping
      // these warm across a switch is a deliberate performance choice.
      //
      // The residual, accepted: a cache HIT is faster than a miss, so profile
      // B could in principle infer that somebody looked a title up. That is a
      // timing side channel, not data exposure. If any of these ever starts
      // keying on a user or storing a personalised response, wire it in.
      'lib/services/episode_info_service.dart': 'keyed on title/season/episode',
      'lib/services/movie_metadata_service.dart': 'keyed on title+year',
      'lib/services/tvmaze_service.dart': 'keyed on show name/imdb id',
      // Host capability, not user data.
      'lib/utils/platform_util.dart': 'device capability probe',
      // LocalEngineStorage is the only one of the three the lifecycle touches
      // directly (EngineProfileLifecycle calls resetProfileScope on it).
      'lib/services/engine/local_engine_storage.dart':
          'reset by EngineProfileLifecycle',
      // Cleared by EngineRegistry._loadScope on every scope load, NOT by the
      // lifecycle participant — so it resets on switch, just by another route.
      'lib/services/engine/config_loader.dart': 'cleared by EngineRegistry',
      // Holds the remote engine MARKETPLACE catalog: one public list, same for
      // every profile. clearCache() has no caller in lib/ at all; it exists for
      // manual refresh. Nothing here is per-user, so there is nothing to reset.
      'lib/services/engine/remote_engine_manager.dart':
          'public marketplace catalog',
    };

    final resetShaped = RegExp(
      r'(static\s+)?(void|Future<void>)\s+'
      r'(resetProfileScope|resetProfileCaches|clearCache|invalidateCache|'
      r'clearUserInfo|clearProfileSessionState)\s*\(',
    );

    final unwired = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.endsWith('profile_app_lifecycle_participant.dart')) continue;
      final source = entity.readAsStringSync();
      if (!resetShaped.hasMatch(source)) continue;
      if (deviceGlobalCaches.containsKey(path)) continue;

      // The participant imports by relative path; match on the file's own
      // basename so a rename cannot silently drop the wiring.
      final basename = path.split('/').last;
      if (!participantSource.contains(basename)) unwired.add(path);
    }
    unwired.sort();

    expect(
      unwired,
      isEmpty,
      reason:
          'These hold a resettable cache but are never reset on profile '
          'switch, so profile B keeps serving profile A\'s data. Either wire '
          'them into ProfileAppLifecycleParticipant, or add them to '
          'deviceGlobalCaches above with the reason they are safe.',
    );
  });

  test('every controller read above ProfileGate is listened to', () {
    // ProfileGate wraps its child in KeyedSubtree(key: ValueKey(sessionEpoch)),
    // so a switch destroys and rebuilds everything BELOW it — widget State
    // cannot carry profile A's data across. That structural defence is why
    // stale UI is not a general risk in this app.
    //
    // It also draws the boundary exactly: whatever is built ABOVE the gate is
    // never rekeyed and therefore never rebuilt by a switch. Anything up there
    // reading a controller's value must subscribe to it, or the incoming
    // profile keeps the outgoing profile's value until the app is killed.
    // That is precisely what happened with the theme.
    // Scoped to _DebrifyAppState, NOT to all of main.dart. That file also
    // holds MainScreen, which is ~3000 lines living *below* the gate and is
    // rekeyed like everything else — scanning the whole file conflates the two
    // sides of the boundary this guard exists to police.
    final appState = _bodyOf(
      File('lib/main.dart').readAsStringSync(),
      'class _DebrifyAppState extends State<DebrifyApp>',
    );
    expect(
      appState,
      isNotEmpty,
      reason: 'the root app State was renamed; update this guard',
    );

    // Value reads only. The `(?!\s*\()` excludes method calls: telling a
    // controller something creates no staleness, whereas reading a value does.
    final read = RegExp(r'(\w+Controller)\.(?:instance\.\w+(?!\s*\()|notifier\b)')
        .allMatches(appState)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      read,
      isNotEmpty,
      reason: 'no controller reads found; the pattern changed',
    );

    final unlistened = read
        .where(
          (controller) => !RegExp(
            '$controller' r'(\.instance|\.notifier)?\.addListener',
          ).hasMatch(appState),
        )
        .toList()
      ..sort();

    expect(
      unlistened,
      isEmpty,
      reason:
          'These are read above ProfileGate but never subscribed to. The gate '
          'rekeys only its child, so nothing up here rebuilds on a profile '
          'switch and the incoming profile inherits the previous value.',
    );
  });

  // The theme bug, generalised, and asserted by BEHAVIOUR rather than by
  // reading the source.
  //
  // The first version of this guard string-matched the warm() body for a
  // silent-recompute call. It passed while the bug was reintroduced, because
  // `indexOf('warm()')` matched a mention of warm() in a comment 60 lines above
  // the method and extracted the wrong brace block. A guard that cannot fail
  // is worse than no guard, so both controllers are now driven for real: a
  // listener is attached, the scope is switched, warm() runs, and the
  // notification is what gets asserted.
  //
  // Why notification and not just the value: the root MaterialApp and
  // AppThemeScope are built ABOVE ProfileGate, so the gate's setState can never
  // re-read them. A warm that updates the value silently is indistinguishable,
  // on screen, from a warm that never ran.
  group('warming a shared controller publishes to its listeners', () {
    ProfileScope scopeFor(String id, int epoch) =>
        ProfileScope(profileId: id, dataGeneration: 1, sessionEpoch: epoch);

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'p.alpha.g.1.app_theme': 'signal',
        'p.beta.g.1.app_theme': AppThemes.legacyId,
        'p.alpha.g.1.text_brightness': TextBrightness.bright.name,
        'p.beta.g.1.text_brightness': TextBrightness.dim.name,
      });
      ProfileRuntime.debugReset();
      ThemeCoreResolver.debugReset();
    });

    tearDown(ProfileRuntime.debugReset);

    test('AppThemeController', () async {
      ProfileRuntime.initializeCommitted(scopeFor('alpha', 1));
      await AppThemeController.warm();

      var notifications = 0;
      void listener() => notifications++;
      AppThemeController.instance.addListener(listener);
      addTearDown(() => AppThemeController.instance.removeListener(listener));

      ProfileRuntime.publish(scopeFor('beta', 2));
      await AppThemeController.warm();

      expect(AppThemeController.instance.id, AppThemes.legacyId);
      expect(
        notifications,
        greaterThan(0),
        reason: 'a silent warm strands the root MaterialApp on the old theme',
      );
    });

    test('TextBrightnessController', () async {
      ProfileRuntime.initializeCommitted(scopeFor('alpha', 1));
      await TextBrightnessController.warm();

      var notifications = 0;
      void listener() => notifications++;
      TextBrightnessController.notifier.addListener(listener);
      addTearDown(
        () => TextBrightnessController.notifier.removeListener(listener),
      );

      ProfileRuntime.publish(scopeFor('beta', 2));
      await TextBrightnessController.warm();

      expect(TextBrightnessController.notifier.value, TextBrightness.dim);
      expect(
        notifications,
        greaterThan(0),
        reason: 'text brightness is read above the gate, same as the theme',
      );
    });
  });
}

/// Returns the brace-balanced body following [signature], or `''` if absent.
///
/// Brace matching rather than a line count: these bodies grow, and a guard
/// that reads a fixed number of lines silently stops covering the tail.
String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start < 0) return '';
  final open = source.indexOf('{', start);
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  return '';
}
