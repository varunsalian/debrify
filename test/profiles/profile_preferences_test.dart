import 'dart:async';

import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/services/storage/discover_storage.dart';
import 'package:debrify/services/storage/home_appearance_storage.dart';
import 'package:debrify/services/storage/home_page_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_save_feedback.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_scheduler.dart';

import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'legacy': 'kept',
      'p.one.g.1.theme': 'blue',
      'p.two.g.1.theme': 'red',
    });
    ProfileRuntime.debugReset();
    ProfilePreferences.debugResetMutationTracking();
    ProfilePreferences.webDavSyncLocalChangeSink = null;
  });

  tearDown(() {
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    ProfileRuntime.debugReset();
  });

  test(
    'committed reads and clear are restricted to captured generation',
    () async {
      final scope = ProfileScope(
        profileId: 'one',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      final prefs = await ProfilePreferences.instance();

      expect(prefs.getString('theme'), 'blue');
      expect(prefs.getKeys(), <String>{'theme'});
      await prefs.setString('language', 'en');
      await prefs.clear();

      final raw = await SharedPreferences.getInstance();
      expect(raw.getString('legacy'), 'kept');
      expect(raw.getString('p.two.g.1.theme'), 'red');
      expect(raw.containsKey('p.one.g.1.theme'), isFalse);
      expect(raw.containsKey('p.one.g.1.language'), isFalse);
    },
  );

  test(
    'Midnight rain persists and validates as a portable animation choice',
    () async {
      ProfileRuntime.initializeLegacy();
      await HomeAppearanceStorage.setHomeAnimationStyle('moonlit_ocean');
      expect(
        await HomeAppearanceStorage.getHomeAnimationStyle(),
        'moonlit_ocean',
      );
      expect(
        SanitizedProfilePreferences.allowsEntry(
          'home_animation_style',
          'moonlit_ocean',
        ),
        isTrue,
      );
      await HomeAppearanceStorage.setHomeAnimationStyle('midnight_rain');
      expect(
        await HomeAppearanceStorage.getHomeAnimationStyle(),
        'midnight_rain',
      );
      expect(
        SanitizedProfilePreferences.allowsEntry(
          'home_animation_style',
          'midnight_rain',
        ),
        isTrue,
      );
      await expectLater(
        HomeAppearanceStorage.setHomeAnimationStyle('unknown'),
        throwsArgumentError,
      );
      expect(
        await HomeAppearanceStorage.getHomeAnimationStyle(),
        'midnight_rain',
      );
      final prefs = await ProfilePreferences.instance();
      await prefs.setString('home_animation_style', 'future-style');
      expect(
        await HomeAppearanceStorage.getHomeAnimationStyle(),
        'snowy_mountain',
      );
    },
  );

  test('Home animations default off, persist per profile and reset', () async {
    ProfileRuntime.initializeLegacy();
    expect(await HomeAppearanceStorage.getHomeAnimationsEnabled(), isFalse);
    expect(
      await HomeAppearanceStorage.getHomeAnimationStyle(),
      'snowy_mountain',
    );
    await HomeAppearanceStorage.setHomeAnimationsEnabled(true);
    await HomeAppearanceStorage.setHomeAnimationStyle('snowy_mountain');
    expect(await HomeAppearanceStorage.getHomeAnimationsEnabled(), isTrue);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
    );
    expect(await HomeAppearanceStorage.getHomeAnimationsEnabled(), isFalse);
    await HomeAppearanceStorage.setHomeAnimationsEnabled(true);
    await HomePageStorage.clearAllHomePageSettings();
    expect(await HomeAppearanceStorage.getHomeAnimationsEnabled(), isFalse);
    expect(
      await HomeAppearanceStorage.getHomeAnimationStyle(),
      'snowy_mountain',
    );
    expect(
      (await SharedPreferences.getInstance()).getBool(
        'home_animations_enabled',
      ),
      isTrue,
    );
  });

  test('legacy mode is byte-compatible with existing keys', () async {
    ProfileRuntime.initializeLegacy();
    final prefs = await ProfilePreferences.instance();

    expect(prefs.getString('legacy'), 'kept');
    await prefs.setBool('enabled', true);
    expect((await SharedPreferences.getInstance()).getBool('enabled'), isTrue);
  });

  test('captured and sync-apply writes emit no local-change signals', () async {
    final scope = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    final notifications = <String>[];
    ProfilePreferences.webDavSyncLocalChangeSink = (_, key) {
      notifications.add(key);
    };

    for (final access in const <CapturedProfilePreferenceAccess>[
      CapturedProfilePreferenceAccess.migration,
      CapturedProfilePreferenceAccess.profileCreation,
      CapturedProfilePreferenceAccess.restore,
      CapturedProfilePreferenceAccess.connectionGrant,
      CapturedProfilePreferenceAccess.syncApply,
    ]) {
      final captured = await ProfilePreferences.forCapturedScope(scope, access);
      expect(
        await captured.setString('captured_${access.name}', 'value'),
        isTrue,
      );
    }
    final sync = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.syncApply,
    );
    expect(
      await sync.applySyncBatch(<String, Object>{
        for (var index = 0; index < 10; index++) 'remote_$index': index,
      }, authorizationBarrier: () {}),
      isTrue,
    );

    expect(notifications, isEmpty);
  });

  test('a successful ordinary portable write emits one local change', () async {
    final scope = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    final notifications = <(String, String)>[];
    ProfilePreferences.webDavSyncLocalChangeSink = (profileId, key) {
      notifications.add((profileId, key));
    };
    final prefs = await ProfilePreferences.instance();

    expect(await prefs.setString('language', 'en'), isTrue);

    expect(notifications, <(String, String)>[('one', 'language')]);
  });

  test(
    'unchanged scalar and list saves emit no new sync notification',
    () async {
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
      );
      var signals = 0;
      ProfilePreferences.webDavSyncLocalChangeSink = (_, _) => signals++;
      final prefs = await ProfilePreferences.instance();
      await prefs.setString('discover_last_source', 'cw');
      await prefs.setString('discover_last_source', 'cw');
      await prefs.setStringList('tracking_scrobble_targets', ['local']);
      await prefs.setStringList('tracking_scrobble_targets', ['local']);
      expect(signals, 2);
      await prefs.setStringList('tracking_scrobble_targets', [
        'local',
        'simkl',
      ]);
      expect(signals, 3);
    },
  );

  for (final selection in [
    ('subtitle_selected_font_id', 'custom_test_font', 'default'),
    ('external_player_preferred', 'custom_app', 'vlc'),
  ]) {
    test(
      'atomic ${selection.$1} uses its computed value for sync eligibility',
      () async {
        ProfileRuntime.initializeCommitted(
          ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
        );
        final prefs = await ProfilePreferences.instance();
        final signals = <String>[];
        ProfilePreferences.webDavSyncLocalChangeSink = (_, key) =>
            signals.add(key);
        final (key, local, portable) = selection;
        expect(await prefs.mutateStringAtomically(key, (_) => local), true);
        expect(prefs.getString(key), local);
        expect(signals, isEmpty);
        expect(await prefs.mutateStringAtomically(key, (_) => portable), true);
        expect(signals, [key]);
        expect(await prefs.mutateStringAtomically(key, (_) => portable), true);
        expect(signals, [key]); // Unchanged writes remain silent.
        expect(await prefs.mutateStringAtomically(key, (_) => local), true);
        expect(signals, [key]);
        expect(await prefs.remove(key), true);
        expect(
          signals,
          key == 'subtitle_selected_font_id' ? [key] : [key, key],
        );
      },
    );
  }

  for (final selection in <(String, String, String)>[
    ('subtitle_selected_font_id', 'custom_test_font', 'default'),
    ('external_player_preferred', 'custom', 'vlc'),
    ('external_player_preferred', 'custom_app', 'vlc'),
    ('external_player_preferred', 'custom_command', 'vlc'),
    ('ios_external_player_preferred', 'custom_scheme', 'vlc'),
    ('linux_external_player_preferred', 'custom_command', 'vlc'),
    ('windows_external_player_preferred', 'custom_command', 'vlc'),
  ]) {
    test(
      'local-only ${selection.$1}=${selection.$2} emits no save receipt',
      () async {
        ProfileRuntime.initializeCommitted(
          ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
        );
        final feedback = WebDavSyncSaveFeedback()..setEnabled(true);
        addTearDown(feedback.dispose);
        var sequence = 0;
        ProfilePreferences.webDavSyncLocalChangeSink = (_, key) {
          if (WebDavSyncScheduler.admitsLocalChangeKey(key)) {
            feedback.saved(++sequence);
          }
        };
        final prefs = await ProfilePreferences.instance();
        final (key, custom, builtin) = selection;

        expect(await prefs.setString(key, custom), isTrue);
        expect(prefs.getString(key), custom);
        expect(feedback.revision, 0);
        expect(feedback.phase, WebDavSavePhase.inactive);

        expect(await prefs.setString(key, builtin), isTrue);
        expect(feedback.revision, 1);
        feedback.finished(1, published: true);
        expect(feedback.phase, WebDavSavePhase.synced);

        expect(await prefs.setString(key, custom), isTrue);
        expect(feedback.revision, 1);
        expect(feedback.hasPending, isFalse);
        expect(await prefs.remove(key), isTrue);
        if (key == 'subtitle_selected_font_id') {
          expect(feedback.revision, 1);
          expect(feedback.hasPending, isFalse);
        } else {
          expect(feedback.revision, 2);
          expect(feedback.hasPending, isTrue);
        }
      },
    );
  }

  test('a throwing local-change sink cannot fail its write', () async {
    final scope = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    ProfilePreferences.webDavSyncLocalChangeSink = (_, _) {
      throw StateError('scheduler failed');
    };
    final prefs = await ProfilePreferences.instance();

    expect(await prefs.setString('language', 'fr'), isTrue);
    expect(prefs.getString('language'), 'fr');
  });

  test('Home card orientation is isolated per profile', () async {
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
    );

    // Landscape is the unset default; an explicit portrait choice is the
    // per-profile state that must not leak.
    expect(
      await HomePageStorage.getHomeCardOrientation(),
      HomeCardOrientation.landscape,
    );
    await HomePageStorage.setHomeCardOrientation(HomeCardOrientation.portrait);

    ProfileRuntime.publish(
      ProfileScope(profileId: 'two', dataGeneration: 1, sessionEpoch: 2),
    );
    expect(
      await HomePageStorage.getHomeCardOrientation(),
      HomeCardOrientation.landscape,
    );

    ProfileRuntime.publish(
      ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 3),
    );
    expect(
      await HomePageStorage.getHomeCardOrientation(),
      HomeCardOrientation.portrait,
    );
  });

  test(
    'Discover defaults remember the last source and stay profile-local',
    () async {
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
      );

      expect(
        await DiscoverStorage.getDiscoverDefaultSource(),
        DiscoverStorage.discoverDefaultRememberLast,
      );
      expect(await DiscoverStorage.getDiscoverLastSource(), 'cw');
      await DiscoverStorage.setDiscoverDefaultSource('a:catalog-addon');
      await DiscoverStorage.setDiscoverLastSource('simkl');

      ProfileRuntime.publish(
        ProfileScope(profileId: 'two', dataGeneration: 1, sessionEpoch: 2),
      );
      expect(
        await DiscoverStorage.getDiscoverDefaultSource(),
        DiscoverStorage.discoverDefaultRememberLast,
      );
      expect(await DiscoverStorage.getDiscoverLastSource(), 'cw');

      ProfileRuntime.publish(
        ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 3),
      );
      expect(
        await DiscoverStorage.getDiscoverDefaultSource(),
        'a:catalog-addon',
      );
      expect(await DiscoverStorage.getDiscoverLastSource(), 'simkl');
    },
  );

  test(
    'Discover preference backup validation accepts only known source shapes',
    () {
      for (final key in ['discover_default_source', 'discover_last_source']) {
        expect(SanitizedProfilePreferences.allowsEntry(key, 'tmdb'), isTrue);
      }
      expect(
        SanitizedProfilePreferences.allowsEntry(
          'discover_default_source',
          'remember',
        ),
        isTrue,
      );
      expect(
        SanitizedProfilePreferences.allowsEntry(
          'discover_default_source',
          'a:catalog-addon',
        ),
        isTrue,
      );
      expect(
        SanitizedProfilePreferences.allowsEntry(
          'discover_last_source',
          'trakt',
        ),
        isTrue,
      );
      expect(
        SanitizedProfilePreferences.allowsEntry('discover_last_source', 'a:'),
        isFalse,
      );
      expect(
        SanitizedProfilePreferences.allowsEntry(
          'discover_default_source',
          'unknown',
        ),
        isFalse,
      );
    },
  );

  test('Discover poster settings transfer as reviewed preferences', () {
    for (final key in const [
      'discover_show_type_tags',
      'discover_show_ratings',
    ]) {
      expect(ProfileCreationService.copyablePreferenceKeys, contains(key));
      expect(SanitizedProfilePreferences.allowsEntry(key, true), isTrue);
      expect(SanitizedProfilePreferences.allowsEntry(key, 'yes'), isFalse);
    }
  });

  test('Home card orientation transfers as a reviewed preference', () {
    expect(
      ProfileCreationService.copyablePreferenceKeys,
      contains('home_card_orientation'),
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_card_orientation',
        'landscape',
      ),
      isTrue,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_card_orientation',
        'square',
      ),
      isFalse,
    );
  });

  test('Home card hold action transfers as a reviewed preference', () {
    expect(
      ProfileCreationService.copyablePreferenceKeys,
      contains('home_cw_hold_to_quick_play'),
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_cw_hold_to_quick_play',
        true,
      ),
      isTrue,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_cw_hold_to_quick_play',
        'yes',
      ),
      isFalse,
    );
  });

  test('Home card text visibility transfers as a reviewed preference', () {
    expect(
      ProfileCreationService.copyablePreferenceKeys,
      contains('home_hide_card_titles_and_ratings'),
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_hide_card_titles_and_ratings',
        true,
      ),
      isTrue,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_hide_card_titles_and_ratings',
        'yes',
      ),
      isFalse,
    );
  });

  test('Home catalog add-on visibility transfers as a reviewed preference', () {
    expect(
      ProfileCreationService.copyablePreferenceKeys,
      contains('home_hide_catalog_addon_names'),
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_hide_catalog_addon_names',
        true,
      ),
      isTrue,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_hide_catalog_addon_names',
        'yes',
      ),
      isFalse,
    );
  });

  test(
    'Home collection-name visibility transfers as a reviewed preference',
    () {
      expect(
        ProfileCreationService.copyablePreferenceKeys,
        contains('home_hide_collection_names'),
      );
      expect(
        SanitizedProfilePreferences.allowsEntry(
          'home_hide_collection_names',
          true,
        ),
        isTrue,
      );
      expect(
        SanitizedProfilePreferences.allowsEntry(
          'home_hide_collection_names',
          'yes',
        ),
        isFalse,
      );
    },
  );

  test('device preference allowlist rejects arbitrary state', () async {
    final prefs = await DevicePreferences.instance();
    expect(() => prefs.setString('profile_theme', 'dark'), throwsArgumentError);
  });

  test(
    'current-session wrapper fails when another profile is published',
    () async {
      final first = ProfileScope(
        profileId: 'one',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(first);
      final current = await ProfilePreferences.instance();
      ProfileRuntime.publish(
        ProfileScope(profileId: 'two', dataGeneration: 1, sessionEpoch: 2),
      );

      expect(() => current.getString('theme'), throwsA(isA<StateError>()));

      final captured = await ProfilePreferences.forCapturedScope(
        first,
        CapturedProfilePreferenceAccess.profileCreation,
      );
      expect(captured.getString('theme'), 'blue');
      expect(await captured.setString('background_result', 'done'), isTrue);
    },
  );

  group('tvOS preference budget', () {
    String filler(int bytes) => 'x' * bytes;

    setUp(() => ProfilePreferenceBudget.debugEnforcedOverride = true);
    tearDown(ProfilePreferenceBudget.debugReset);

    ProfileScope scopeOne() =>
        ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1);

    test('refuses an oversized ordinary write without throwing', () async {
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      // Must return false rather than throw: no ordinary caller inspects the
      // result, so a throw would surface in code that has never handled one.
      expect(
        await prefs.setString(
          'bulk',
          filler(ProfilePreferenceBudget.limitBytes),
        ),
        isFalse,
      );
      expect(prefs.getString('bulk'), isNull);
    });

    test('still admits ordinary writes that fit', () async {
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      expect(await prefs.setString('language', 'en'), isTrue);
      expect(prefs.getString('language'), 'en');
    });

    test('refuses an oversized string list write', () async {
      // Scoring a list flat instead of summing its elements would let an
      // arbitrarily large list straight through the guard.
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      expect(
        await prefs.setStringList('bulk', <String>[
          filler(ProfilePreferenceBudget.limitBytes ~/ 2),
          filler(ProfilePreferenceBudget.limitBytes ~/ 2),
        ]),
        isFalse,
      );
      expect(prefs.getStringList('bulk'), isNull);
    });

    test('measures the whole database, not just the captured scope', () async {
      // The platform limit is database-wide, so another profile's keys count.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'p.two.g.1.bulk': filler(ProfilePreferenceBudget.limitBytes - 4096),
      });
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      expect(await prefs.setString('bulk', filler(8192)), isFalse);
    });

    test('removal is never gated', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'p.one.g.1.bulk': filler(ProfilePreferenceBudget.limitBytes * 2),
      });
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      expect(await prefs.remove('bulk'), isTrue);
      expect(prefs.getString('bulk'), isNull);
    });

    test('captured-scope writes are exempt', () async {
      // Migration, restore and profile creation all treat a false result as
      // fatal and throw; during bootstrap that would stop the app from
      // starting. They are bounded by their own preflight/envelope caps.
      ProfileRuntime.initializeCommitted(scopeOne());
      final captured = await ProfilePreferences.forCapturedScope(
        scopeOne(),
        CapturedProfilePreferenceAccess.migration,
      );

      expect(
        await captured.setString(
          'bulk',
          filler(ProfilePreferenceBudget.limitBytes),
        ),
        isTrue,
      );
    });

    test('sync batch refuses unsafe growth before its first write', () async {
      ProfileRuntime.initializeCommitted(scopeOne());
      final sync = await ProfilePreferences.forCapturedScope(
        scopeOne(),
        CapturedProfilePreferenceAccess.syncApply,
      );

      expect(
        await sync.applySyncBatch(<String, Object>{
          'bulk': filler(ProfilePreferenceBudget.limitBytes),
          'language': 'fr',
        }, authorizationBarrier: () {}),
        isFalse,
      );
      final raw = await SharedPreferences.getInstance();
      expect(raw.getString('p.one.g.1.bulk'), isNull);
      expect(raw.getString('p.one.g.1.language'), isNull);
      expect(raw.getString('p.one.g.1.theme'), 'blue');
    });

    test(
      'sync batch rechecks headroom immediately before each write',
      () async {
        ProfileRuntime.initializeCommitted(scopeOne());
        final sync = await ProfilePreferences.forCapturedScope(
          scopeOne(),
          CapturedProfilePreferenceAccess.syncApply,
        );
        final raw = await SharedPreferences.getInstance();
        var barriers = 0;

        final wrote = await sync.applySyncBatch(
          const <String, Object>{'language': 'fr'},
          authorizationBarrier: () {
            barriers++;
            if (barriers == 2) {
              unawaited(
                raw.setString(
                  'another_writer_bulk',
                  filler(ProfilePreferenceBudget.emergencyLimitBytes),
                ),
              );
            }
          },
        );

        expect(wrote, isFalse);
        expect(raw.getString('p.one.g.1.language'), isNull);
      },
    );

    test('off tvOS every write behaves exactly as before', () async {
      ProfilePreferenceBudget.debugEnforcedOverride = false;
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      expect(
        await prefs.setString(
          'bulk',
          filler(ProfilePreferenceBudget.limitBytes * 2),
        ),
        isTrue,
      );
    });
  });

  test('native projection captured access cannot write', () async {
    final scope = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    final projection = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.nativeProjectionReadOnly,
    );

    expect(projection.getString('theme'), 'blue');
    await expectLater(
      projection.setString('theme', 'red'),
      throwsA(isA<StateError>()),
    );
  });

  test('sync batch refreshes only keys whose stored value changed', () async {
    final scope = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    final sync = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.syncApply,
    );
    Set<String>? refreshed;

    expect(
      await sync.applySyncBatch(
        const <String, Object>{'theme': 'blue', 'language': 'en'},
        authorizationBarrier: () {},
        afterApply: (appliedScope, changedKeys) async {
          expect(appliedScope, scope);
          refreshed = changedKeys;
        },
      ),
      isTrue,
    );

    expect(refreshed, <String>{'language'});
  });

  test(
    'sync batch refuses a target captured before a newer local write',
    () async {
      final scope = ProfileScope(
        profileId: 'one',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      late ProfilePreferenceMutationToken token;
      await ProfilePreferences.captureMutationSnapshot((captured) async {
        token = captured;
      });
      final ordinary = await ProfilePreferences.instance();
      await ordinary.setString('theme', 'new-local-value');
      final sync = await ProfilePreferences.forCapturedScope(
        scope,
        CapturedProfilePreferenceAccess.syncApply,
      );
      var journaled = false;

      await expectLater(
        sync.applySyncBatch(
          const <String, Object>{'theme': 'stale-sync-value'},
          authorizationBarrier: () {},
          expectedMutationToken: token,
          beforeWrite: () async => journaled = true,
        ),
        throwsA(isA<ProfilePreferenceMutationConflict>()),
      );

      expect(journaled, isFalse);
      expect(ordinary.getString('theme'), 'new-local-value');
    },
  );

  test(
    'async string preparation releases the barrier and retries a racing sync',
    () async {
      final scope = ProfileScope(
        profileId: 'one',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      final prefs = await ProfilePreferences.instance();
      final sync = await ProfilePreferences.forCapturedScope(
        scope,
        CapturedProfilePreferenceAccess.syncApply,
      );
      final preparing = Completer<void>();
      final resume = Completer<void>();
      final seen = <String?>[];
      final mutation = prefs.mutateStringAsyncAtomically('theme', (
        current,
      ) async {
        seen.add(current);
        if (seen.length == 1) {
          preparing.complete();
          await resume.future;
        }
        return '$current-edited';
      });
      await preparing.future;
      try {
        await ProfilePreferences.captureMutationSnapshot(
          (_) async {},
        ).timeout(const Duration(seconds: 1));
        expect(
          await sync
              .applySyncBatch({'theme': 'remote'}, authorizationBarrier: () {})
              .timeout(const Duration(seconds: 1)),
          true,
        );
      } finally {
        resume.complete();
      }
      expect(await mutation, true);
      expect(seen, ['blue', 'remote']);
      expect(prefs.getString('theme'), 'remote-edited');
    },
  );

  test('snapshot rejects atomic list mutation without deadlocking', () async {
    final scope = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    final prefs = await ProfilePreferences.instance();

    await ProfilePreferences.captureMutationSnapshot((_) async {
      expect(
        () => prefs.mutateStringListAtomically(
          'favorites',
          (_) => const <String>['one'],
        ),
        throwsStateError,
      );
    }).timeout(const Duration(seconds: 1));
  });

  test('sync batch skips cache publication for an unchanged target', () async {
    final scope = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    final sync = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.syncApply,
    );
    var refreshed = false;

    expect(
      await sync.applySyncBatch(
        const <String, Object>{'theme': 'blue'},
        authorizationBarrier: () {},
        afterApply: (_, _) async => refreshed = true,
      ),
      isTrue,
    );

    expect(refreshed, isFalse);
  });

  test(
    'pending replay republishes caches after values already landed',
    () async {
      final scope = ProfileScope(
        profileId: 'one',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      final sync = await ProfilePreferences.forCapturedScope(
        scope,
        CapturedProfilePreferenceAccess.syncApply,
      );
      Set<String>? refreshed;

      expect(
        await sync.applySyncBatch(
          const <String, Object>{'theme': 'blue'},
          authorizationBarrier: () {},
          replayCommittedTarget: true,
          afterApply: (_, changedKeys) async => refreshed = changedKeys,
        ),
        isTrue,
      );

      expect(refreshed, <String>{'theme'});
    },
  );

  test(
    'sync batch does not treat equal int and double values as unchanged',
    () async {
      final scope = ProfileScope(
        profileId: 'one',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      final raw = await SharedPreferences.getInstance();
      await raw.setInt(scope.preferenceKey('scale'), 1);
      final sync = await ProfilePreferences.forCapturedScope(
        scope,
        CapturedProfilePreferenceAccess.syncApply,
      );
      Set<String>? refreshed;

      expect(
        await sync.applySyncBatch(
          const <String, Object>{'scale': 1.0},
          authorizationBarrier: () {},
          afterApply: (_, changedKeys) async => refreshed = changedKeys,
        ),
        isTrue,
      );

      expect(raw.getDouble(scope.preferenceKey('scale')), 1.0);
      expect(refreshed, <String>{'scale'});
    },
  );

  test('sync batch stops after its authorization barrier is revoked', () async {
    final scope = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    final sync = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.syncApply,
    );
    var barriers = 0;
    void barrier() {
      barriers++;
      if (barriers == 3) {
        ProfileRuntime.publish(
          ProfileScope(profileId: 'two', dataGeneration: 1, sessionEpoch: 2),
        );
      }
      if (ProfileRuntime.scope.value != scope) {
        throw StateError('profile switched');
      }
    }

    await expectLater(
      sync.applySyncBatch(const <String, Object>{
        'theme': 'green',
        'language': 'en',
      }, authorizationBarrier: barrier),
      throwsStateError,
    );
    final raw = await SharedPreferences.getInstance();
    expect(raw.getString('p.one.g.1.theme'), 'green');
    expect(raw.getString('p.one.g.1.language'), isNull);
  });

  test('sync batch rejects non-finite doubles before writing', () async {
    final scope = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    final sync = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.syncApply,
    );

    await expectLater(
      sync.applySyncBatch(<String, Object>{
        'bad': double.nan,
      }, authorizationBarrier: () {}),
      throwsArgumentError,
    );
    expect(
      (await SharedPreferences.getInstance()).containsKey('p.one.g.1.bad'),
      isFalse,
    );
  });

  test(
    'a nested ordinary write cannot deadlock against a snapshot barrier',
    () async {
      // Outer writer registers, then a WebDAV snapshot raises the exclusive
      // barrier and waits for active writers to drain, then the outer writer
      // reaches its nested write. Without re-entrancy the nested write waits
      // on the barrier while the barrier waits on the outer writer.
      final before = await ProfilePreferences.captureMutationToken();
      final outerRegistered = Completer<void>();
      final reachNested = Completer<void>();
      var nestedRan = false;
      final outer = ProfilePreferences.synchronizeExternalMutation(() async {
        outerRegistered.complete();
        await reachNested.future;
        await ProfilePreferences.synchronizeExternalMutation(() async {
          nestedRan = true;
        }, marksMutation: true);
      }, marksMutation: false);
      await outerRegistered.future;
      var snapshotRan = false;
      final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
        snapshotRan = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(snapshotRan, isFalse, reason: 'the barrier waits for the writer');
      reachNested.complete();
      await outer.timeout(const Duration(seconds: 2));
      await snapshot.timeout(const Duration(seconds: 2));
      expect(nestedRan, isTrue);
      expect(snapshotRan, isTrue);
      // The nested write still counts as a mutation for snapshot tokens.
      final after = await ProfilePreferences.captureMutationToken();
      expect(
        () => ProfilePreferences.runIfMutationSnapshotCurrent(
          before,
          () async {},
        ),
        throwsA(isA<ProfilePreferenceMutationConflict>()),
      );
      await ProfilePreferences.runIfMutationSnapshotCurrent(after, () async {});
    },
  );

  test('work inheriting a finished writer\'s zone registers normally', () async {
    late Zone writerZone;
    await ProfilePreferences.synchronizeExternalMutation(() async {
      writerZone = Zone.current;
    }, marksMutation: false);
    // A timer or unawaited future started inside the finished writer still runs
    // in its zone; it must hold the snapshot barrier off like any writer.
    final gate = Completer<void>();
    final late = writerZone.run(
      () => ProfilePreferences.synchronizeExternalMutation(
        () => gate.future,
        marksMutation: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    var snapshotRan = false;
    final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
      snapshotRan = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(snapshotRan, isFalse);
    gate.complete();
    await late;
    await snapshot.timeout(const Duration(seconds: 2));
    expect(snapshotRan, isTrue);
  });

  test(
    'a nested write that outlives its writer still holds the barrier off',
    () async {
      final gate = Completer<void>();
      late Future<void> nested;
      await ProfilePreferences.synchronizeExternalMutation(() async {
        // Started inside the open writer but not awaited by it.
        nested = ProfilePreferences.synchronizeExternalMutation(
          () => gate.future,
          marksMutation: true,
        );
      }, marksMutation: false);
      var snapshotRan = false;
      final snapshot = ProfilePreferences.captureMutationSnapshot((_) async {
        snapshotRan = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(snapshotRan, isFalse, reason: 'the nested write is still running');
      gate.complete();
      await nested;
      await snapshot.timeout(const Duration(seconds: 2));
      expect(snapshotRan, isTrue);
    },
  );
}
