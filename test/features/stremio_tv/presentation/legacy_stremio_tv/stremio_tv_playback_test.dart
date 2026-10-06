import 'dart:async';

import 'package:debrify/features/home/presentation/home_hero_shell_bridge.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/stremio_tv_fixture.dart';
import '../../../../support/stremio_tv_handoff.dart';

Finder get loader => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_PlContent',
);

void main() {
  testWidgets('C3 (R/O) P2 full fields defaults order and snapshot resolver', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      await t.runAsync(() async {
        await f.provider('torbox');
        await StremioTvStorage.setStremioTvDebridProvider('realdebrid');
      });
      await f.mount(t);
      final held = Completer<http.Response>();
      f.heldUnrestrict = held;
      final overlayDismissedAtPush = <bool>[];
      f.observer.onPlayer = (_) =>
          overlayDismissedAtPush.add(f.observer.events.last == 'pop');
      f.tuner(t).onPlay(f.channel(t));
      await f.until(t, () => f.holdUsed);
      expect(loader, findsOneWidget);
      held.complete(f.unrestricted());
      await f.until(t, () => f.observer.players.isNotEmpty);
      final p = f.observer.players.single;
      expect(overlayDismissedAtPush, [true]);
      expectStremioTvPlayer(p, 'P2', {
        'videoUrl': 'https://video.test/original.mp4',
        'title': f.meta(1).name,
        'startAtPercent': null,
        'contentImdbId': f.meta(1).effectiveImdbId,
        'contentTitle': f.meta(1).name,
        'contentType': 'movie',
        'contentSeason': null,
        'contentEpisode': null,
        'stremioSources': hasLength(2),
        'stremioCurrentSourceIndex': 0,
        'resolveStremioSource': isNotNull,
        'stremioTvChannels': [
          for (final channel in f.tuner(t).allChannels)
            containsPair('id', channel.id),
        ],
        'stremioTvCurrentChannelId': f.channelId(1),
        'stremioTvGuideDataProvider': isNotNull,
        'stremioTvChannelSwitchProvider': isNotNull,
        'stremioTvNextProvider': isNotNull,
      });
      await f.settle(t);
      await t.runAsync(() => f.provider('torbox'));
      await f.chooseProvider(t, 'TorBox');
      f.requests.clear();
      expect(
        await t.runAsync(
          () => p.resolveStremioSource!(p.stremioSources!.first),
        ),
        'https://video.test/original.mp4',
      );
      expect(f.requests.any((r) => r.url.host.contains('real-debrid')), isTrue);
      expect(f.requests.any((r) => r.url.host.contains('torbox')), isFalse);
    });
  });

  testWidgets('C3 (O) guide lazy load next map switch and failed-slot cursor', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      f.count = 20;
      f.addonCatalogs = [
        {'id': 'unloaded', 'type': 'movie', 'name': 'Unloaded'},
      ];
      await t.runAsync(() async {
        for (var i = 1; i <= f.count; i++) {
          await StremioTvStorage.setStremioTvChannelFavorited(
            f.channelId(i),
            true,
          );
        }
      });
      await f.mount(t);
      await f.play(t);
      final p = f.observer.players.single;
      final unloaded = f.tuner(t).allChannels.singleWhere((c) => !c.isLocal);
      // The lazy guide itself must make the catalog request.
      expect(
        unloaded.items,
        isEmpty,
        reason: 'guide begins with a genuinely unloaded offscreen addon',
      );
      f.requests.clear();
      final guide = await t.runAsync(
        () => p.stremioTvGuideDataProvider!([f.channelId(1), unloaded.id]),
      );
      expect(guide!.keys, containsAll([f.channelId(1), unloaded.id]));
      expect(
        f.requests.any((r) => r.url.path.contains('/catalog/movie/unloaded')),
        isTrue,
      );
      final first = await t.runAsync(
        () => p.stremioTvNextProvider!(f.channelId(1)),
      );
      expect(first!.keys.toSet(), {
        'channelId',
        'url',
        'title',
        'contentType',
        'contentImdbId',
        'startAtPercent',
        'stremioSources',
        'stremioCurrentSourceIndex',
        'sourceResolver',
        'nowPlaying',
        'nextUp',
      });
      final switched = await t.runAsync(
        () => p.stremioTvChannelSwitchProvider!(f.channelId(2)),
      );
      expect(switched!['channelId'], f.channelId(2));
      expect(switched['title'], f.meta(2).name);
      f.rdFails = true;
      expect(
        await t.runAsync(() => p.stremioTvNextProvider!(f.channelId(1))),
        isNull,
      );
      expect(
        f.logs.any((m) => m.contains('slot offset 2 unavailable')),
        isTrue,
      );
      f.rdFails = false;
      final following = await t.runAsync(
        () => p.stremioTvNextProvider!(f.channelId(1)),
      );
      final end1 = (first['nowPlaying'] as Map)['slotEndMs'] as int;
      final end3 = (following!['nowPlaying'] as Map)['slotEndMs'] as int;
      expect(end3 - end1, const Duration(minutes: 180).inMilliseconds);
      // Retune through P2 in the same base slot; Next restarts at offset one.
      await f.play(t);
      final restarted = await t.runAsync(
        () => f.observer.players.last.stremioTvNextProvider!(f.channelId(1)),
      );
      expect((restarted!['nowPlaying'] as Map)['slotEndMs'], end1);
    });
  });

  testWidgets(
    'C2/C3 (O) Home stash startup launch clears flag then unknown falls back',
    (t) async {
      await stremioTvCase(t, (f) async {
        HomeHeroShellBridge.playSavedStremioChannel(f.channelId(2));
        await f.mount(t);
        await f.until(t, () => f.observer.players.isNotEmpty);
        expect(
          f.observer.players.single.stremioTvCurrentChannelId,
          f.channelId(2),
        );
        await f.settle(t);
        await MainPageBridge.watchStremioTvChannel!('unknown-id');
        await f.settle(t, frames: 40);
        expect(f.observer.players, hasLength(2));
        expect(
          f.observer.players.last.stremioTvCurrentChannelId,
          f.channelId(1),
        );
        expect(
          f.logs.any((m) => m.contains('Startup channel not found')),
          isFalse,
        );
      });
    },
  );

  testWidgets(
    'C2 (O) unknown pending startup id fails before a stream request',
    (t) async {
      await stremioTvCase(t, (f) async {
        HomeHeroShellBridge.playSavedStremioChannel('unknown-id');
        await f.mount(t);
        expect(f.probes, contains('hide overlay'));
        expect(
          f.logs.any((m) => m.contains('Startup channel not found')),
          isTrue,
        );
        expect(f.requests.any((r) => r.url.path.contains('/stream/')), isFalse);
        expect(f.observer.players, isEmpty);
      });
    },
  );

  testWidgets('C3 (R/O) held RD Cancel releases without a player push', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      f.heldUnrestrict = Completer<http.Response>();
      HomeHeroShellBridge.playSavedStremioChannel(f.channelId(1));
      await f.mount(t);
      await f.until(t, () => f.holdUsed);
      await f.tap(t, find.text('Cancel'));
      expect(f.probes, contains('hide overlay'));
      expect(f.logs.any((m) => m.contains('Playback canceled')), isTrue);
      f.heldUnrestrict!.complete(f.unrestricted());
      await f.settle(t, frames: 30);
      expect(loader, findsNothing);
      expect(f.observer.players, isEmpty);
    });
  });

  testWidgets('C3 (O) superseding play rejects the older held response', (
    t,
  ) async {
    await stremioTvCase(t, (f) async {
      f.heldUnrestrict = Completer<http.Response>();
      HomeHeroShellBridge.playSavedStremioChannel(f.channelId(1));
      await f.mount(t);
      await f.until(t, () => f.holdUsed);
      f.tuner(t).onPlay(f.channel(t, 2));
      await f.until(t, () => f.observer.players.isNotEmpty);
      f.heldUnrestrict!.complete(f.unrestricted());
      await f.settle(t, frames: 30);
      expect(f.observer.players, hasLength(1));
      expect(
        f.observer.players.single.stremioTvCurrentChannelId,
        f.channelId(2),
      );
    });
  });
}
