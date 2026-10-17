import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/stremio_service.dart';

import 'support/iptv_storage_driver.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/trakt_transport.dart';

void main() {
  testWidgets(
    'P15 rebase an older ladder cannot unmute a newer pending candidate probe',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      TraktTestTransport.instance.attach(f);
      SecretVault.debugReset(deviceIdOverride: 'p15-stale-ladder-fixture');
      await t.runAsync(SecretVault.warmUp);
      final service = StremioService.instance;
      service.invalidateCache();
      service.debugManifestFetcher = (url) async => StremioAddon.fromManifest({
        'id': Uri.parse(url).host,
        'name': Uri.parse(url).host,
        'version': '1.0.0',
        'resources': ['stream'],
        'types': ['tv'],
        'catalogs': [],
      }, url);
      Future<IptvChannel> addon(String name, int index) async {
        final installed = await t.runAsync(
          () => service.addAddon('https://p15-$name.test/manifest.json'),
        );
        return iptvChannel(
          index,
          url: StremioIptvService.buildChannelKey(installed!.id, name),
        );
      }

      final olderChannel = await addon('older-ladder', 1);
      final newerChannel = await addon('newer-ladder', 2);
      service.debugManifestFetcher = null;
      f.network.handler = (request) => request.url.path.contains('/stream/tv/')
          ? Response(
              jsonEncode({
                'streams': [
                  {'url': 'https://${request.url.host}/candidate.ts'},
                ],
              }),
              200,
            )
          : Response('{}', 404);
      final held = IptvAwaitDelivery('tryOpenLiveStream', (v) => v is bool);
      final failures = <Object>[];
      Future<void>? older;
      Future<void>? newer;
      var newerDone = false;
      const error = 'HTTP 403 stale-ladder-isolation';
      try {
        final channels = [iptvChannel(0), olderChannel, newerChannel];
        await f.mount(
          t,
          VideoPlayerScreen(
            videoUrl: channels.first.url,
            title: channels.first.name,
            iptvChannels: channels,
          ),
        );
        playerControls(t).onShowIptvChannels!();
        await f.advance(t, const Duration(milliseconds: 350));
        final guide = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        f.player.onOpen = () {};
        older = held.run(
          () => guide
              .onChannelSelected(channels, 1)
              .then<void>((_) {}, onError: (Object e) => failures.add(e)),
        );
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        await f.actions.settle(t);
        f.player.emit<int?>('width', 1280);
        await f.until(t, () => held.pending.isNotEmpty);
        newer = guide
            .onChannelSelected(channels, 2)
            .then<void>(
              (_) => newerDone = true,
              onError: (Object e) => failures.add(e),
            );
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 3,
        );
        await f.actions.settle(t);
        expect(newerDone, false);
        held.release();
        await f.finish(t, older!);
        await f.actions.settle(t);
        expect(newerDone, false);
        f.player.emit('error', error);
        await f.finish(t, newer!);
        await f.actions.settle(t);
        expect(find.textContaining(error), findsNothing);
        expect(failures, isEmpty);
      } finally {
        held.release();
        f.player.emit<int?>('width', 1280);
        if (older != null) await f.finish(t, older);
        if (newer != null) await f.finish(t, newer);
        await f.close(t);
        TraktTestTransport.instance.recorder = null;
        service.debugManifestFetcher = null;
      }
    },
  );
}
