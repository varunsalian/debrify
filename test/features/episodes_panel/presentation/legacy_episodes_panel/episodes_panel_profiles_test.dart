import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../support/episodes_panel_fixture.dart';
import '../../../../support/profile_fixture.dart';
import 'episodes_panel_watched_test.dart' show actWatched;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  testWidgets(
    'A with tokens and B without write disjoint profile-local completions',
    (t) async {
      await episodesPanelCase(t, 'profile-local', 370, (f) async {
        final profiles = ProfileFixture();
        await t.runAsync(profiles.open);
        try {
          final a = ProfileRuntime.capture();
          final bId = await t.runAsync(
            () async => (await profiles.registry.createProfile(
              name: 'B',
              role: UserProfileRole.member,
              actingProfileId: a.profileId,
              actingAuthorizationRevision: (await profiles.registry.getProfile(
                a.profileId,
              ))!.authorizationRevision,
              actingSessionEpoch: a.sessionEpoch,
            )).id,
          );
          final b = ProfileScope(
            profileId: bId!,
            dataGeneration: 1,
            sessionEpoch: 2,
          );
          await t.runAsync(() async {
            await f.authenticate({TrackingSource.trakt});
            await TrackingSourceStorage.setTrackingScrobbleTargets({
              TrackingSource.trakt,
            });
          });
          f.progressLoader = () async => {};
          await f.mount(t);
          f.requests.clear();
          await actWatched(t, f, true);
          expect(
            f.requests.where(
              (r) => r.url.host == 'api.trakt.tv' && r.method == 'POST',
            ),
            hasLength(1),
          );
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump();
          await t.runAsync(() async {
            await profiles.registry.setActiveProfile(b.profileId);
            ProfileRuntime.publish(b);
            await TrackingSourceStorage.setTrackingScrobbleTargets({
              TrackingSource.trakt,
            });
            expect(await TraktStorage.hasTraktCredential(), isFalse);
            expect(
              await EpisodeProgressStorage.isEpisodeFinished(
                seriesTitle: f.show.name,
                season: 1,
                episode: 1,
                imdbId: f.id,
              ),
              isFalse,
            );
          });
          await f.mount(t);
          f.requests.clear();
          await actWatched(t, f, true);
          expect(f.requests, isEmpty);
          expect(find.text('Marked as Watched on this device'), findsOneWidget);
          await t.runAsync(() async {
            expect(
              await EpisodeProgressStorage.isEpisodeFinished(
                seriesTitle: f.show.name,
                season: 1,
                episode: 1,
                imdbId: f.id,
              ),
              isTrue,
            );
          });
          ScaffoldMessenger.of(
            t.element(find.text('Marked as Watched on this device')),
          ).clearSnackBars();
          await t.pump(const Duration(milliseconds: 400));
          await actWatched(t, f, false);
          await t.runAsync(() async {
            expect(
              await EpisodeProgressStorage.isEpisodeFinished(
                seriesTitle: f.show.name,
                season: 1,
                episode: 1,
                imdbId: f.id,
              ),
              isFalse,
            );
            await ProfileRuntime.withCapturedScope(a, () async {
              expect(
                await EpisodeProgressStorage.isEpisodeFinished(
                  seriesTitle: f.show.name,
                  season: 1,
                  episode: 1,
                  imdbId: f.id,
                ),
                isTrue,
              );
            });
          });
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump();
          await t.runAsync(profiles.close);
        }
      });
    },
  );
  testWidgets(
    'same-session scope republish presents metadata without resolving cached auth',
    (t) async {
      await episodesPanelCase(t, 'scope-auth', 371, (f) async {
        final profiles = ProfileFixture();
        await t.runAsync(profiles.open);
        try {
          await t.runAsync(() async {
            await f.authenticate({TrackingSource.trakt});
            await MetadataPreferencesService.save(
              MetadataPreferences(
                providers: {MetadataCategory.episodeArtwork: 'tvmaze'},
              ),
            );
          });
          f.progressLoader = () async => {};
          await f.mount(t);
          final firstEpisodes = f.view.episodes;
          final generation = f.view.generation;
          final state = f.key.currentState;
          await t.runAsync(TraktStorage.clearTraktAuth);
          final scope = ProfileRuntime.capture();
          ProfileRuntime.scope.value = null;
          ProfileRuntime.scope.value = null;
          ProfileRuntime.publish(scope);
          await f.until(t, () => !identical(f.view.episodes, firstEpisodes));
          expect(f.key.currentState, same(state));
          expect(f.view.generation, generation);
          f.requests.clear();
          await f.sheet(t);
          expect(find.text('Rate on Trakt'), findsOneWidget);
          expect(f.requests, isEmpty);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump();
          await t.runAsync(profiles.close);
        }
      });
    },
  );
}
