import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved transport; application dependencies are unchanged.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';
import 'support/vp_fixture_actions.dart';

void main() {
  const initial = 'https://player.test/a.mp4';
  for (final mode in ['Debrify', 'Stremio']) {
    for (final boundary in ['pause', 'provider']) {
      for (final crossing in [
        'none',
        'A to B',
        'A to B to A',
        'delete A',
        'dispose in B',
      ]) {
        testWidgets(
          'P17 facade $mode $boundary across $crossing observes invocation scope and physical resume rows',
          (t) async {
            final d = TvEpisodeDriver(t);
            await d.initialize();
            final oldStore = SharedPreferencesStorePlatform.instance;
            final pause = Completer<void>();
            final provider = Completer<Map<String, dynamic>?>();
            var pauseEntered = false;
            ProfileScope? invoked;
            VpFixtureTask<dynamic>? task;
            const payload = {'url': 'https://player.test/b.mp4', 'title': 'B'};
            Future<Map<String, dynamic>?> request() {
              invoked = ProfileRuntime.capture();
              return boundary == 'provider'
                  ? provider.future
                  : Future.value(payload);
            }

            try {
              final first = ProfileRuntime.capture();
              final b = await completionIncomingProfile(t, d.f);
              await d.f.finish(
                t,
                VideoResumeStorage.upsertVideoResume(initial, {
                  'positionMs': 222,
                }),
              );
              await completionActivate(t, d.f, first);
              final a = ProfileRuntime.capture();
              await d.mount(
                screen: VideoPlayerScreen(
                  videoUrl: initial,
                  title: 'A',
                  requestNextChannel: mode == 'Debrify' ? request : null,
                  stremioTvCurrentChannelId: mode == 'Stremio' ? 'a' : null,
                  stremioTvNextProvider: mode == 'Stremio'
                      ? (id) => request()
                      : null,
                ),
              );
              await d.f.finish(
                t,
                VideoResumeStorage.upsertVideoResume(initial, {
                  'positionMs': 111,
                }),
              );
              final store = (await t.runAsync(CompletionWrites.install))!;
              d.player.beforeOperation = (name, value) async {
                if (boundary == 'pause' && name == 'pause' && !pauseEntered) {
                  pauseEntered = true;
                  await pause.future;
                }
              };
              d.player.heldOperation = (name, value) =>
                  boundary == 'pause' && name == 'pause' && !pause.isCompleted;
              final dynamic action = mode == 'Debrify'
                  ? playerControls(t).onNextChannel!
                  : playerControls(t).onNext!;
              task = d.f.actions.start<dynamic>(
                'held TV profile action',
                () => d.observe<dynamic>(() => action()),
                held: true,
              );
              await d.f.until(
                t,
                () => boundary == 'pause' ? pauseEntered : invoked != null,
              );
              if (crossing != 'none') {
                await completionActivate(t, d.f, b);
              }
              if (crossing == 'A to B to A') {
                await completionActivate(t, d.f, a);
              }
              if (crossing == 'delete A') {
                final actor = await d.f.finish(
                  t,
                  ProfileAuthorizationContext.capture(d.f.registry!),
                );
                await d.f.finish(
                  t,
                  d.f.registry!.deleteProfileWithDisposition(
                    id: a.profileId,
                    deleteOwnedResources: true,
                    detachPublicArtifacts: true,
                    actingProfileId: actor.profileId,
                    actingAuthorizationRevision: actor.authorizationRevision,
                    actingSessionEpoch: actor.sessionEpoch,
                  ),
                );
              }
              final afterCross = ProfileRuntime.capture();
              if (crossing == 'dispose in B') {
                await t.pumpWidget(const SizedBox.shrink());
                await d.f.until(t, () => d.player.disposed.isCompleted);
              }
              pause.complete();
              provider.complete(payload);
              await d.f.finish(t, task.future);
              expect(
                invoked!.profileId,
                boundary == 'provider' ? a.profileId : afterCross.profileId,
              );
              expect(
                invoked!.sessionEpoch,
                boundary == 'provider'
                    ? a.sessionEpoch
                    : afterCross.sessionEpoch,
              );
              if (crossing == 'dispose in B') {
                expect(d.opens, hasLength(1));
              } else {
                expect(
                  d.player.state.playlist.medias.single.uri,
                  payload['url'],
                );
                d.player.state = d.player.state.copyWith(
                  position: const Duration(seconds: 90),
                );
                d.player.emit('position', d.player.state.position);
                await d.f.advance(t);
                await d.f.advance(t, const Duration(seconds: 6));
              }
              await d.f.actions.settle(t);
              final ar = crossing == 'delete A'
                  ? null
                  : await t.runAsync(
                      () => completionPhysicalResume(d.f, a, initial),
                    );
              final br = await t.runAsync(
                () => completionPhysicalResume(d.f, b, initial),
              );
              final activeA = afterCross.profileId == a.profileId;
              if (crossing != 'delete A') {
                expect(ar?['position_ms'], activeA ? 90000 : 111);
              }
              expect(
                br?['position_ms'],
                crossing == 'dispose in B'
                    ? 80
                    : activeA
                    ? 222
                    : 90000,
              );
              expect(
                await store.physical(a, 'series_source_tt1700000'),
                isNull,
              );
              expect(
                await store.physical(b, 'series_source_tt1700000'),
                isNull,
              );
              if (crossing == 'delete A') {
                expect(
                  await d.f.finish(t, d.f.registry!.getProfile(a.profileId)),
                  isNull,
                );
              }
              expect(d.errors, isEmpty);
            } finally {
              if (!pause.isCompleted) {
                pause.complete();
              }
              if (!provider.isCompleted) {
                provider.complete(payload);
              }
              if (task != null && !task.isCompleted) {
                await d.f.finish(t, task.future);
              }
              await d.close();
              SharedPreferencesStorePlatform.instance = oldStore;
            }
          },
        );
      }
    }
  }
}
