import 'dart:async';
import 'package:debrify/core/metadata/metadata_presentation_cache.dart';
import 'package:debrify/features/home/application/home_card_metadata_dependencies.dart';
import 'package:debrify/features/home/application/home_card_metadata_controller.dart';
import 'package:debrify/features/home/models/home_card_metadata.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/metadata_presentation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/card_metadata_fixture.dart';

void main() {
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(ProfileRuntime.debugReset);

  test(
    'build is read-free and repository recomputation retains accepted state',
    () async {
      final h = CardMetadataHarness();
      addTearDown(h.dispose);
      expect(h.data.preferenceReads, 0);
      expect(h.state.artworkPending(MetadataCategory.posters), isTrue);
      await h.load();
      expect(h.state.presented, same(approvedCard));
      expect(h.state.resolvedOnce, isTrue);
      expect(h.data.cache.peek(cardSource)?.value.item, same(approvedCard));
      h.container.invalidate(
        homeCardMetadataRepositoryProvider(h.session.epoch),
      );
      await h.container.pump();
      expect(h.state.presented, same(approvedCard));
      expect(h.data.preferenceReads, 1);
      expect(h.data.requests, hasLength(1));
    },
  );

  test(
    'late preferences from an older request cannot start a provider call',
    () async {
      final h = CardMetadataHarness();
      addTearDown(h.dispose);
      final oldPreferences = Completer<MetadataPreferences>();
      h.data.preferences = () => oldPreferences.future;
      final old = h.load();
      h.data.preferences = () async => MetadataPreferences(language: 'fr-FR');
      await h.load();
      oldPreferences.complete(MetadataPreferences(language: 'de-DE'));
      await old;
      expect(h.state.preferences!.language, 'fr-FR');
      expect(h.data.requests, hasLength(1));
      expect(h.data.diagnostics, hasLength(1));
    },
  );

  for (final retirement in ['view', 'profile', 'repository']) {
    test(
      'late presentation cannot publish or populate cache after $retirement retirement',
      () async {
        final h = CardMetadataHarness();
        addTearDown(h.dispose);
        final pending = Completer<MetadataPresentation>();
        h.data.respond = (_) => pending.future;
        final loading = h.load();
        await Future<void>.delayed(Duration.zero);
        expect(h.data.requests, hasLength(1));
        if (retirement == 'view') h.controller.retire();
        if (retirement == 'profile') {
          ProfileRuntime.promoteLegacyToCommitted(
            ProfileScope(
              profileId: 'incoming',
              dataGeneration: 1,
              sessionEpoch: 1,
            ),
          );
        }
        if (retirement == 'repository') {
          h.container.invalidate(
            homeCardMetadataRepositoryProvider(h.session.epoch),
          );
          await h.container.pump();
        }
        expect(h.data.requests.single.relevant(), isFalse);
        pending.complete(const MetadataPresentation(approvedCard));
        await loading;
        expect(h.state.resolvedOnce, isFalse);
        expect(h.data.cache.peek(cardSource), isNull);
        expect(h.data.diagnostics, isEmpty);
      },
    );
  }

  test(
    'two mounted cards keep independent request ownership for the same source',
    () async {
      final h = CardMetadataHarness();
      addTearDown(h.dispose);
      final other = HomeCardMetadataSession(
        epoch: h.session.epoch,
        viewIdentity: Object(),
        generation: 0,
        initial: h.session.initial,
      );
      final subscription = h.container.listen(
        homeCardMetadataProvider(other),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final first = Completer<MetadataPresentation>();
      final second = Completer<MetadataPresentation>();
      h.data.respond = (_) =>
          h.data.requests.length == 1 ? first.future : second.future;
      final old = h.load();
      final fresh = h.container
          .read(homeCardMetadataProvider(other).notifier)
          .load(isCurrent: () => true);
      await Future<void>.delayed(Duration.zero);
      h.controller.retire();
      second.complete(const MetadataPresentation(approvedCard));
      await fresh;
      first.complete(const MetadataPresentation(cardSource));
      await old;
      expect(subscription.read().presented, same(approvedCard));
      expect(h.state.resolvedOnce, isFalse);
      expect(h.data.cache.peek(cardSource)?.value.item, same(approvedCard));
      expect(h.data.diagnostics, hasLength(1));
    },
  );

  test('retired profile is rejected before preference access', () async {
    final h = CardMetadataHarness();
    addTearDown(h.dispose);
    ProfileRuntime.promoteLegacyToCommitted(
      ProfileScope(profileId: 'incoming', dataGeneration: 1, sessionEpoch: 1),
    );
    await h.load();
    expect(h.data.preferenceReads, 0);
    expect(h.data.requests, isEmpty);
  });

  for (final failure in ['preferences', 'presentation']) {
    test('$failure errors retain usable artwork without automatic retry', () {
      fakeAsync((time) {
        final h = CardMetadataHarness(
          initial: HomeCardMetadataState(
            original: cardSource,
            presentation: approvedCard,
            preferences: MetadataPreferences(),
            resolvedOnce: true,
          ),
        );
        if (failure == 'preferences') {
          h.data.preferences = () async => throw StateError('preferences');
        } else {
          h.data.respond = (_) async => throw StateError('presentation');
        }
        unawaited(h.load());
        time.flushMicrotasks();
        time.elapse(const Duration(seconds: 20));
        expect(h.state.presented, same(approvedCard));
        expect(h.data.preferenceReads, 1);
        expect(h.data.requests, hasLength(failure == 'preferences' ? 0 : 1));
        expect(h.data.diagnostics, isEmpty);
        h.dispose();
      });
    });
  }

  test(
    'retryable results use 2s/4s retries and merge only already-approved fields',
    () {
      fakeAsync((time) {
        final h = CardMetadataHarness();
        h.data.respond = (_) async => MetadataPresentation(
          h.data.requests.length == 1
              ? approvedCard
              : const StremioMeta(
                  id: 'card',
                  type: 'movie',
                  name: 'Translated',
                ),
          retryable: true,
        );
        unawaited(h.load());
        time.flushMicrotasks();
        expect(h.data.requests, hasLength(1));
        time.elapse(const Duration(milliseconds: 1999));
        expect(h.data.requests, hasLength(1));
        time.elapse(const Duration(milliseconds: 1));
        expect(h.data.requests, hasLength(2));
        expect(h.state.presented.poster, 'approved-art');
        expect(h.state.presented.background, isNull);
        time.elapse(const Duration(milliseconds: 3999));
        expect(h.data.requests, hasLength(2));
        time.elapse(const Duration(milliseconds: 1));
        expect(h.data.requests, hasLength(3));
        time.elapse(const Duration(seconds: 20));
        expect(h.data.requests, hasLength(3));
        expect(h.data.diagnostics.map((d) => d.attempt), [0, 1, 2]);
        expect(h.data.cache.peek(cardSource), isNull);
        h.dispose();
      });
    },
  );

  for (final disposed in [false, true]) {
    test(
      '${disposed ? 'disposal' : 'retirement'} cancels a scheduled retry',
      () {
        fakeAsync((time) {
          final h = CardMetadataHarness();
          h.data.respond = (_) async =>
              const MetadataPresentation(approvedCard, retryable: true);
          unawaited(h.load());
          time.flushMicrotasks();
          expect(h.data.requests, hasLength(1));
          if (disposed) {
            h.dispose();
          } else {
            h.controller.retire();
          }
          time.elapse(const Duration(seconds: 10));
          expect(h.data.requests, hasLength(1));
          expect(h.data.requests.single.relevant(), isFalse);
          if (!disposed) h.dispose();
        });
      },
    );
  }

  for (final expired in [false, true]) {
    test(
      '${expired ? 'expired' : 'fresh'} shared cache preserves provider eligibility',
      () async {
        final cache = MetadataPresentationCache(
          now: () => expired ? DateTime.utc(2000) : DateTime.now(),
        );
        final h = CardMetadataHarness(data: CardMetadataFake(cache: cache));
        addTearDown(h.dispose);
        final prefs = await h.data.preferences();
        cache.prepare(
          scope: h.session.epoch.owner.scope,
          revision: 0,
          preferences: prefs,
        );
        cache.store(cardSource, const MetadataPresentation(approvedCard));
        await h.load();
        expect(h.state.presented, same(approvedCard));
        expect(h.data.requests, hasLength(expired ? 1 : 0));
        expect(h.data.diagnostics.single.cacheHit, !expired);
      },
    );
  }
}
