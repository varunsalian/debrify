import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/iptv_last_channel_storage.dart';
import 'package:debrify/services/secret_vault.dart';
// Existing resolved transport; no dependency change.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/iptv_storage_driver.dart';
import 'support/local_completion_driver.dart';

void main() {
  for (final boundary in [
    'settle',
    'playlist-lookup',
    'post-capture',
    'transport',
  ]) {
    for (final handoff in ['B', 'ABA', 'delete']) {
      for (final disposed in [false, true]) {
        testWidgets(
          'P15 last-channel $boundary handoff=$handoff disposed=$disposed pins physical ownership',
          (t) async {
            final d = IptvWorkflowDriver(t);
            await d.initialize();
            final previous = SharedPreferencesStorePlatform.instance;
            final store = (await t.runAsync(IptvPreferenceWrites.install))!;
            final held = CompletionDelivery(
              'setIptvLastLiveChannel',
              (v) => boundary == 'playlist-lookup'
                  ? v is List<IptvPlaylist>
                  : v is ProfilePreferences,
            )..armed = false;
            final live = iptvChannel(
              0,
              attributes: {'source_playlist_id': 'origin'},
            );
            try {
              await held.run(() => d.mount([live]));
              await d.f.until(
                t,
                () => store.saved.any(
                  (k) => k.endsWith('iptv_last_live_channel'),
                ),
              );
              await d.f.finish(
                t,
                IptvLastChannelStorage.clearIptvLastLiveChannel(),
              );
              final a = ProfileRuntime.capture();
              store.saved.clear();
              held.armed =
                  boundary == 'playlist-lookup' || boundary == 'post-capture';
              if (boundary == 'transport') {
                store.heldKey = 'iptv_last_live_channel';
              }
              d.observe(() => held.run(() => d.player.emit('playing', true)));
              await d.f.advance(t);
              if (boundary != 'settle') {
                await d.advance(const Duration(seconds: 1));
                await d.f.until(
                  t,
                  () => boundary == 'transport'
                      ? store.entered
                      : held.pending.isNotEmpty,
                );
              }
              if (disposed) {
                await d.retire();
              }
              final transfer = await iptvHandoff(d, a, handoff);
              final incoming = transfer.current;
              held.release();
              store.release();
              await d.advance(const Duration(seconds: 2));
              await d.settle();
              if (boundary == 'post-capture') {
                await d.f.until(
                  t,
                  () => d.errors.any(
                    (e) => e.toString().contains('stale ProfilePreferences'),
                  ),
                );
              } else if (!(boundary == 'settle' && disposed)) {
                await d.f.until(
                  t,
                  () => store.saved.any(
                    (k) => k.endsWith('iptv_last_live_channel'),
                  ),
                );
              }
              final rawA = await store.physical(a, 'iptv_last_live_channel');
              final rawB = await store.physical(
                incoming,
                'iptv_last_live_channel',
              );
              if (handoff == 'ABA') {
                expect(
                  await store.physical(
                    transfer.intermediate,
                    'iptv_last_live_channel',
                  ),
                  isNull,
                );
              }
              final write =
                  boundary != 'post-capture' &&
                  !(boundary == 'settle' && disposed);
              expect(
                rawA != null,
                write && (boundary == 'transport' || handoff == 'ABA'),
              );
              expect(
                rawB != null,
                write && (boundary != 'transport' || handoff == 'ABA'),
              );
              if (write && handoff != 'delete') {
                final owner = boundary == 'transport' ? a : incoming;
                final prefs = await d.f.finish(
                  t,
                  ProfilePreferences.forCapturedScope(
                    owner,
                    CapturedProfilePreferenceAccess.diagnosticsReadOnly,
                  ),
                );
                final raw = await d.f.finish(
                  t,
                  SecretVault.getString(prefs, 'iptv_last_live_channel'),
                );
                expect((jsonDecode(raw!) as Map)['url'], live.url);
                expect((jsonDecode(raw) as Map)['playlistId'], 'origin');
              }
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
            }
          },
        );
      }
    }
  }
}
