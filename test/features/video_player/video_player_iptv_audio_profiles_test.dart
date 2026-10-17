import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Existing resolved transport; no dependency change.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/iptv_storage_driver.dart';
import 'support/local_completion_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode, iptvAudioTracks;

void main() {
  for (final boundary in ['pre-capture', 'post-capture', 'transport']) {
    for (final handoff in ['B', 'ABA', 'delete']) {
      for (final disposed in [false, true]) {
        testWidgets(
          'P15 audio write $boundary handoff=$handoff disposed=$disposed pins both physical profiles',
          (t) async {
            final d = IptvWorkflowDriver(t);
            await d.initialize();
            final previous = SharedPreferencesStorePlatform.instance;
            final store = (await t.runAsync(IptvPreferenceWrites.install))!;
            final held = CompletionDelivery(
              boundary == 'pre-capture'
                  ? 'ProfilePreferences.instance'
                  : 'setIptvSeriesAudioLanguage',
              (v) => boundary == 'pre-capture'
                  ? v is SharedPreferences
                  : v is ProfilePreferences,
            );
            held.armed = boundary != 'transport';
            try {
              await d.mount([iptvEpisode(1)]);
              iptvAudioTracks(d);
              await d.settle();
              final a = ProfileRuntime.capture();
              final m = await openPlayerMenu(t, d.f);
              if (boundary == 'transport') {
                store.heldKey = 'iptv_series_audio_lang';
              }
              final action = d.observe(
                () => held.run(() => m.onAudioSelected('2', '1')),
              );
              await d.f.until(
                t,
                () => boundary == 'transport'
                    ? store.entered
                    : held.pending.isNotEmpty,
              );
              expect(await store.physical(a, 'iptv_series_audio_lang'), isNull);
              if (disposed) {
                await d.retire();
              }
              final transfer = await iptvHandoff(d, a, handoff);
              final incoming = transfer.current;
              held.release();
              store.release();
              await d.f.finish(t, action);
              await d.settle();
              final rawA = await store.physical(a, 'iptv_series_audio_lang');
              final rawB = await store.physical(
                incoming,
                'iptv_series_audio_lang',
              );
              if (handoff == 'ABA') {
                expect(
                  await store.physical(
                    transfer.intermediate,
                    'iptv_series_audio_lang',
                  ),
                  isNull,
                );
              }
              final aWritten =
                  boundary == 'transport' ||
                  boundary == 'pre-capture' && handoff == 'ABA';
              final bWritten = boundary == 'pre-capture';
              expect(
                rawA == null ? null : jsonDecode(rawA as String),
                aWritten ? {'provider::series': 'fra'} : isNull,
              );
              expect(
                rawB == null ? null : jsonDecode(rawB as String),
                bWritten || boundary == 'transport' && handoff == 'ABA'
                    ? {'provider::series': 'fra'}
                    : isNull,
              );
              if (boundary == 'post-capture') {
                expect(
                  d.errors.any(
                    (e) => e.toString().contains('stale ProfilePreferences'),
                  ),
                  true,
                );
              } else {
                expect(d.errors, isEmpty);
              }
            } finally {
              held.release();
              store.release();
              await d.close();
              SharedPreferencesStorePlatform.instance = previous;
              SharedPreferences.resetStatic();
            }
          },
        );
      }
    }
  }
}
