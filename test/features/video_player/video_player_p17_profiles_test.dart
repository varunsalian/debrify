import 'dart:async';
import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/source_binding_committer.dart';
import 'package:debrify/features/sources/presentation/legacy_playback/source_player_launch.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved preference transport; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/local_completion_driver.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final boundary in ['candidate', 'fetch', 'production resolver']) {
    for (final crossing in [
      'none',
      'A to B',
      'A to B to A',
      'delete A',
      'dispose',
    ]) {
      testWidgets(
        'P17 $boundary across $crossing inspects captured binding and resume stores',
        (t) async {
          final d = TvEpisodeDriver(t);
          await d.initialize();
          SecretVault.debugReset(deviceIdOverride: 'p17-ownership');
          WebDavSyncTombstoneRecorder.debugInstall(sink: (_, _) {});
          final oldStore = SharedPreferencesStorePlatform.instance;
          final gate = Completer<void>();
          var entered = false;
          final delivery = CompletionDelivery(
            'SourcePlaylistResolver._resolve',
            (v) => v == null,
          );
          delivery.armed = false;
          SourceBindingCommitter? committer;
          try {
            final a = ProfileRuntime.capture();
            final b = await completionIncomingProfile(t, d.f);
            await d.f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(
                'https://player.test/a.mp4',
                {'positionMs': 222},
              ),
            );
            await completionActivate(t, d.f, a);
            final origin = ProfileRuntime.capture();
            final bindings = AutomaticSourceBindings.capture();
            committer = SourcePlayerLaunch.validatedLaunchCommitter(
              'debrid',
              const PlaybackMeta(
                imdbId: 'tt1700000',
                contentType: 'series',
                season: 1,
                episode: 1,
              ),
              sourceBindings: bindings,
            );
            final resolver = SourcePlayerLaunch.resolverFor(
              'debrid',
              committer,
            );
            final candidate = Torrent(
              rowid: 0,
              infohash: '',
              name: 'Show.S01E02',
              sizeBytes: 0,
              createdUnix: 0,
              seeders: 0,
              leechers: 0,
              completed: 0,
              scrapedDate: 0,
              streamType: StreamType.directUrl,
              directUrl: 'https://player.test/incoming.mp4',
              stremioAddonId: 'p17-addon',
              stremioAddonKey: 'p17-config',
              stremioStreamKey: 'p17-stream',
              stremioStreamIndex: 0,
              stremioVideoId: 'tt1700000:1:2',
            );
            Future<void> hold(String site) async {
              if (site == boundary && !entered) {
                entered = true;
                await gate.future;
              }
            }

            await d.mount(
              screen: VideoPlayerScreen(
                videoUrl: 'https://player.test/a.mp4',
                title: 'Show.S01E01.mkv',
                contentType: 'series',
                contentSeason: 1,
                contentEpisode: 1,
                contentImdbId: 'tt1700000',
                seriesSourceFetcher: SeriesSourceFetcher(
                  season: 1,
                  episode: 1,
                  searchEpisodes: (s, e) async {
                    await hold('fetch');
                    return [candidate];
                  },
                  searchPacks: (s, e) async => [],
                  validateCandidate: (s) async {
                    await hold('candidate');
                    return true;
                  },
                ),
                resolveSourceToPlaylist: resolver,
                onStremioSourceCommitted: committer.call,
              ),
            );
            await d.f.finish(
              t,
              VideoResumeStorage.upsertVideoResume(
                'https://player.test/a.mp4',
                {'positionMs': 111},
              ),
            );
            final store = (await t.runAsync(CompletionWrites.install))!;
            final beforeA = await store.physical(
              origin,
              'series_source_tt1700000',
            );
            final beforeB = await store.physical(b, 'series_source_tt1700000');
            final browser = await d.browser();
            delivery.armed = boundary == 'production resolver';
            final task =
                d.observe<dynamic>(
                      () => delivery.run(() => browser.onEpisodeSelected(1, 2)),
                    )
                    as Future<dynamic>;
            await d.f.until(
              t,
              () => boundary == 'production resolver'
                  ? delivery.pending.isNotEmpty
                  : entered,
            );
            if (crossing != 'none') {
              await completionActivate(t, d.f, b);
            }
            if (crossing == 'A to B to A') {
              await completionActivate(t, d.f, origin);
            }
            if (crossing == 'delete A') {
              final actor = await d.f.finish(
                t,
                ProfileAuthorizationContext.capture(d.f.registry!),
              );
              await d.f.finish(
                t,
                d.f.registry!.deleteProfileWithDisposition(
                  id: origin.profileId,
                  deleteOwnedResources: true,
                  detachPublicArtifacts: true,
                  actingProfileId: actor.profileId,
                  actingAuthorizationRevision: actor.authorizationRevision,
                  actingSessionEpoch: actor.sessionEpoch,
                ),
              );
            }
            if (crossing == 'dispose') {
              await t.pumpWidget(const SizedBox.shrink());
              await d.f.until(t, () => d.player.disposed.isCompleted);
            }
            delivery.release();
            gate.complete();
            await d.f.finish(t, task);
            await d.f.actions.settle(t);
            expect(await store.physical(b, 'series_source_tt1700000'), beforeB);
            expect(
              (await t.runAsync(
                () => completionPhysicalResume(
                  d.f,
                  b,
                  'https://player.test/a.mp4',
                ),
              ))?['position_ms'],
              crossing == 'dispose' ? 80 : 222,
            );
            if (crossing == 'none') {
              expect(d.opens.last.uri, candidate.directUrl);
              await d.f.until(
                t,
                () => store.writes.any(
                  (v) => v.$1.endsWith('series_source_tt1700000'),
                ),
              );
              expect(
                await store.physical(origin, 'series_source_tt1700000'),
                isNot(beforeA),
              );
            } else {
              expect(d.opens, hasLength(1));
              expect(
                await store.physical(origin, 'series_source_tt1700000'),
                beforeA,
              );
              expect(bindings.isCurrent, isFalse);
            }
            if (crossing != 'delete A') {
              expect(
                (await t.runAsync(
                  () => completionPhysicalResume(
                    d.f,
                    origin,
                    'https://player.test/a.mp4',
                  ),
                ))?['position_ms'],
                crossing == 'none' ? 80 : 111,
              );
            }
            expect(d.errors, isEmpty);
          } finally {
            delivery.release();
            if (!gate.isCompleted) {
              gate.complete();
            }
            committer?.close();
            await d.close();
            SharedPreferencesStorePlatform.instance = oldStore;
            SecretVault.debugReset();
            WebDavSyncTombstoneRecorder.debugReset();
          }
        },
      );
    }
  }
}
