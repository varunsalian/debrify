import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'dart:async';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/iptv_storage_driver.dart';
import 'support/local_completion_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode, iptvAudioTracks;

void main() {
  for (final operation in [
    'browse',
    'candidate',
    'catchup',
    'banner',
    'audio',
  ]) {
    for (final retired in ['profile', 'ABA', 'dispose']) {
      testWidgets(
        'P15 held $operation read across $retired pins outgoing result acceptance',
        (t) async {
          final d = IptvWorkflowDriver(t);
          await d.initialize();
          final a = ProfileRuntime.capture();
          final http = Completer<Response>();
          final browse = Completer<Map<String, dynamic>?>();
          final audio = CompletionDelivery(
            'applyIptvAudioPreference',
            (v) => v == 'fra',
          );
          final live = operation == 'candidate'
              ? await d.installAddon('read-$retired')
              : iptvChannel(
                  1,
                  url:
                      'https://p15-read-$operation-$retired.test/live/u/p/123.ts',
                );
          d.response = (r) =>
              operation == 'candidate' && r.url.path.contains('/stream/tv/') ||
                  operation == 'catchup' &&
                      r.url.path.contains('/timeshift/') ||
                  operation == 'banner' && r.url.path == '/player_api.php'
              ? http.future
              : iptvPanelReply(r);
          var hold = false;
          final basic = iptvChannel(0);
          d.provider = (r) => hold ? browse.future : iptvPage([basic]);
          try {
            Future<void>? pending;
            if (operation == 'audio') {
              await d.f.finish(
                t,
                IptvAudioStorage.setIptvSeriesAudioLanguage(
                  'provider::series',
                  'fra',
                ),
              );
              await d.mount([iptvEpisode(1), iptvEpisode(2)]);
              iptvAudioTracks(d);
              await d.settle();
              final sheet = await d.guide();
              pending = d.observe(
                () => audio.run(
                  () => sheet.onChannelSelected([
                    iptvEpisode(1),
                    iptvEpisode(2),
                  ], 1),
                ),
              );
              await d.f.until(t, () => audio.pending.isNotEmpty);
            } else if (operation == 'banner') {
              await d.mount([live]);
              await d.f.until(
                t,
                () => d.f.network.requests.any(
                  (r) => r.url.path == '/player_api.php',
                ),
              );
            } else {
              await d.mount([basic, live], paged: operation == 'browse');
              final sheet = await d.guide();
              if (operation == 'browse') {
                hold = true;
                pending = d.observe(
                  () => sheet.onChannelSelected([basic, live], 1),
                );
                await d.f.finish(t, pending!);
                await d.f.until(t, () => d.browse.length > 1);
              }
              if (operation == 'candidate') {
                d.probeMode();
                pending = d.observe(
                  () => sheet.onChannelSelected([basic, live], 1),
                );
                await d.f.until(
                  t,
                  () => d.f.network.requests.any(
                    (r) => r.url.path.contains('/stream/tv/'),
                  ),
                );
              }
              if (operation == 'catchup') {
                pending = d.observe(
                  () => sheet.onPlayProgramme!(live, iptvProgramme()),
                );
                await d.f.until(
                  t,
                  () => d.f.network.requests.any(
                    (r) => r.url.path.contains('/timeshift/'),
                  ),
                );
              }
            }
            if (retired == 'dispose') {
              await d.retire();
            } else {
              await iptvHandoff(d, a, retired == 'ABA' ? 'ABA' : 'B');
            }
            final before = d.opened.length;
            if (operation == 'browse') {
              browse.complete(
                iptvPage([live, iptvChannel(8)], category: 'Sports'),
              );
              await d.settle();
              if (retired != 'dispose') {
                final after = await d.guide();
                expect(after.channels.length, 2);
                expect(after.channels.last.url, 'https://p15.test/8.ts');
              } else {
                expect(d.opened.length, before);
              }
            }
            if (operation == 'candidate') {
              http.complete(
                Response(
                  '{"streams":[{"url":"https://p15-read-probe.test/accepted.ts"}]}',
                  200,
                ),
              );
              await d.settle();
              if (retired != 'dispose') {
                await d.f.until(t, () => d.opened.length == before + 1);
                await d.probeEvent('width');
              }
              await d.f.finish(t, pending!);
              expect(d.opened.length, before + (retired == 'dispose' ? 0 : 1));
            }
            if (operation == 'catchup') {
              http.complete(Response('', 200));
              await d.f.finish(t, pending!);
              expect(d.opened.length, before + (retired == 'dispose' ? 0 : 1));
            }
            if (operation == 'catchup' && retired == 'dispose') {
              expect(
                await d.f.finish(t, IptvHistoryStorage.getIptvWatchHistory()),
                isEmpty,
              );
            }
            if (operation == 'banner') {
              http.complete(
                iptvPanelReply(
                  Request(
                    'GET',
                    Uri.parse('https://p15-epg.test/player_api.php'),
                  ),
                  title: 'Held profile guide',
                ),
              );
              await d.settle();
              if (retired != 'dispose') {
                expect(d.banners.first.epg?.now?.title, 'Held profile guide');
              }
            }
            if (operation == 'audio') {
              final calls = d.calls('audio').length;
              audio.release();
              await d.f.finish(t, pending!);
              await d.settle();
              if (retired == 'dispose') {
                expect(d.calls('audio').length, calls);
              } else {
                expect(d.player.state.track.audio.id, '2');
              }
            }
            expect(d.errors, isEmpty);
          } finally {
            audio.release();
            if (!http.isCompleted) {
              http.complete(Response('{}', 404));
            }
            if (!browse.isCompleted) {
              browse.complete(null);
            }
            await d.close();
          }
        },
      );
    }
  }
}
