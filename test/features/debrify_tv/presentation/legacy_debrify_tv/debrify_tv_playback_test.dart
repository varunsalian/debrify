import 'dart:async';

import 'package:debrify/screens/debrify_tv/dialogs/cached_loading_dialog.dart';
import 'package:debrify/screens/debrify_tv/dialogs/channel_creation_dialog.dart';
import 'package:debrify/screens/debrify_tv/widgets/random_start_slider.dart';
import 'package:debrify/screens/debrify_tv/widgets/switch_row.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/debrify_tv_fixture.dart';
import '../../../../support/debrify_tv_handoff.dart';

Map<String, Object?> options(
  DebrifyTvFixture f, {
  required bool quick,
  bool random = false,
}) => {
  'videoUrl': 'https://streams.test/Original.720p.mkv',
  'title': 'Original.720p.mkv',
  'startFromRandom': random,
  'randomStartMaxPercent': 23,
  'hideSeekbar': false,
  'showChannelName': false,
  'channelName': quick ? null : 'Original channel 1',
  'channelNumber': quick ? null : 1,
  'showVideoTitle': false,
  'hideOptions': false,
  'requestMagicNext': isNotNull,
  'requestNextChannel': isNotNull,
};

void main() {
  for (final flow in [
    ('real_debrid', 'P5', false),
    ('alldebrid', 'P6', false),
    ('torbox', 'P7', false),
    ('premiumize', 'P10', false),
    ('real_debrid', 'P1', true),
    ('torbox', 'P3', true),
    ('premiumize', 'P11', true),
    ('alldebrid', 'P12', true),
    ('pikpak', 'P4', true),
    ('pikpak', 'P8', false),
  ]) {
    testWidgets(
      'C3 O ${flow.$2} complete arguments defaults and provider requests',
      (t) async {
        await debrifyTvCase(t, (f) async {
          await t.runAsync(() => f.provider(flow.$1));
          await f.mount(t);
          final ready = Completer<void>();
          var held = false;
          f.onRequest = (request) async {
            if (!held) {
              held = true;
              await ready.future;
            }
            return f.providerResponse(request);
          };
          if (flow.$3) {
            await f.quick(t);
          } else {
            await f.watch(t);
          }
          await f.until(
            t,
            () =>
                find.byType(CachedLoadingDialog).evaluate().isNotEmpty ||
                find.byType(ChannelCreationDialog).evaluate().isNotEmpty,
          );
          ready.complete();
          await f.until(t, () => f.observer.players.isNotEmpty);
          final expected = options(f, quick: flow.$3);
          if (!flow.$3 || flow.$2 == 'P1') {
            expected['requestChannelById'] = isNotNull;
            expected['channelDirectory'] = [
              {
                'id': 'original-1',
                'name': 'Original channel 1',
                'channelNumber': 1,
                'isCurrent': !flow.$3,
              },
              {
                'id': 'original-2',
                'name': 'Original channel 2',
                'channelNumber': 2,
                'isCurrent': false,
              },
            ];
          }
          expectDebrifyTvPlayer(f.observer.players.single, flow.$2, expected);
          final ids = f.requests.map(f.requestIdentity).toList();
          if (flow.$1 == 'real_debrid') {
            expect(
              ids,
              containsAllInOrder([
                'POST /rest/1.0/torrents/addMagnet',
                'GET /rest/1.0/torrents/info/original-1',
                'POST /rest/1.0/torrents/selectFiles/original-1',
                'GET /rest/1.0/torrents/info/original-1',
                'POST /rest/1.0/unrestrict/link',
              ]),
            );
          } else if (flow.$1 == 'torbox') {
            expect(
              ids,
              containsAllInOrder([
                'GET /v1/api/torrents/checkcached',
                'POST /v1/api/torrents/createtorrent',
                'GET /v1/api/torrents/mylist',
                'GET /v1/api/torrents/requestdl',
              ]),
            );
          } else if (flow.$1 == 'premiumize') {
            expect(
              ids,
              containsAllInOrder([
                'POST /api/cache/check',
                'POST /api/transfer/directdl',
              ]),
            );
          } else if (flow.$1 == 'alldebrid') {
            expect(
              ids,
              containsAllInOrder([
                'POST /v4/magnet/upload',
                'POST /v4/magnet/files',
                'POST /v4/link/unlock',
              ]),
            );
          }
          if (flow.$1 == 'pikpak') {
            expect(
              ids,
              containsAllInOrder([
                'GET /drive/v1/files/original-folder',
                'POST /drive/v1/files',
                'GET /drive/v1/tasks/original-task',
                'GET /drive/v1/files/original-video',
              ]),
            );
          }
          expect(
            f.observer.events,
            containsAllInOrder(['dialog', 'player', 'player removed']),
          );
          expect(
            f.observer.activeDialogsAtPlayer.single,
            0,
            reason: '${flow.$2} closes progress before push',
          );
          expect(f.probes.where((p) => p == 'hide overlay'), hasLength(1));
          final before = f.requests.length;
          await f.settle(t, frames: 30);
          expect(
            f.requests.length,
            before,
            reason: '${flow.$2} stops prefetch after intercepted exit',
          );
          if (flow.$3) {
            expect(
              f.requests.any((r) => r.url.host == 'debrify-tv-original.test'),
              isTrue,
            );
          }
        });
      },
    );
  }

  testWidgets('C3 C10 O P5 live channel option differs from quick scope', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      await f.mount(t);
      await f.settings(t);
      final switchRow = t.widget<SwitchRow>(find.byType(SwitchRow).first);
      switchRow.onChanged(true);
      await f.settle(t);
      expect(t.widget<SwitchRow>(find.byType(SwitchRow).first).value, isTrue);
      expect(
        await t.runAsync(DebrifyTvStorage.getDebrifyTvStartRandom),
        isTrue,
      );
      expect(
        t.widget<RandomStartSlider>(find.byType(RandomStartSlider)).value,
        23,
      );
      await f.tap(t, find.text('Done'));
      await f.watch(t);
      await f.until(t, () => f.observer.players.isNotEmpty);
      expect(
        f.observer.players.single.startFromRandom,
        isTrue,
        reason: 'P5 passes the channel startFromRandom',
      );
    });
  });

  testWidgets(
    'C3 O P3 stacked live settings make channel and quick options differ',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.style = 'spotlight';
        await t.runAsync(() => f.provider('torbox'));
        final held = Completer<http.Response>();
        var holding = false;
        f.onRequest = (r) async {
          if (r.url.path.endsWith('/checkcached') && !holding) {
            holding = true;
            return held.future;
          }
          return f.providerResponse(r);
        };
        await f.mount(t);
        await f.quick(t);
        await f.until(t, () => holding);
        await f.settings(t);
        t.widget<SwitchRow>(find.byType(SwitchRow).first).onChanged(true);
        await f.settle(t);
        await f.tap(t, find.text('Done'));
        held.complete(
          f.jsonResponse({
            'success': true,
            'data': [
              {'hash': 'a' * 40},
            ],
          }),
        );
        await f.until(t, () => f.observer.players.isNotEmpty);
        expect(
          f.observer.players.single.startFromRandom,
          isTrue,
          reason: 'P3 passes the channel startFromRandom',
        );
      });
    },
  );

  testWidgets('C3 O cached RD late launch after Cancel remains characterized', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.heldUnrestrict = Completer<http.Response>();
      await f.mount(t);
      await f.watch(t);
      await f.until(t, () => f.holdUsed);
      expect(find.text('Cancel'), findsOneWidget);
      await f.tap(t, find.text('Cancel'));
      expect(f.observer.players, isEmpty);
      f.heldUnrestrict!.complete(f.streamResponse());
      await f.until(t, () => f.observer.players.isNotEmpty);
      expect(
        f.observer.events,
        containsAllInOrder(['dialog', 'pop', 'player']),
      );
      expect(
        f.observer.players.single.videoUrl,
        'https://streams.test/Original.720p.mkv',
        reason: 'Found-not-fixed cached RD late launch after cancel',
      );
    });
  });

  for (final provider in ['torbox', 'premiumize', 'alldebrid', 'real_debrid']) {
    testWidgets('C3 O held quick $provider resolve honours Cancel', (t) async {
      await debrifyTvCase(t, (f) async {
        await t.runAsync(() => f.provider(provider));
        final held = Completer<http.Response>();
        http.Request? waiting;
        final path = switch (provider) {
          'torbox' => '/createtorrent',
          'premiumize' => '/transfer/directdl',
          'alldebrid' => '/magnet/upload',
          _ => '/unrestrict/link',
        };
        f.onRequest = (r) async {
          if (r.url.path.endsWith(path) && waiting == null) {
            waiting = r;
            return held.future;
          }
          return f.providerResponse(r);
        };
        await f.mount(t);
        await f.quick(t);
        await f.until(t, () => waiting != null);
        await f.tap(t, find.text('Cancel'));
        held.complete(await f.providerResponse(waiting!));
        await f.settle(t, frames: 120);
        expect(
          f.observer.players,
          isEmpty,
          reason: 'held quick $provider does not push after cancel',
        );
      });
    });
  }

  testWidgets('C3 O native TV false result falls back with two overlay hides', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.television = true;
      await f.mount(t);
      await f.watch(t);
      await f.until(t, () => f.observer.players.isNotEmpty);
      expect(
        f.nativeCalls,
        isEmpty,
        reason: 'non-Android bridge returns false before invocation',
      );
      expect(f.probes.where((p) => p == 'hide overlay'), hasLength(2));
      expect(f.observer.players, hasLength(1));
    });
  });

  for (final provider in ['real_debrid', 'premiumize']) {
    testWidgets(
      'C3 O $provider channel switch waits five seconds and preserves original result',
      (t) async {
        await debrifyTvCase(t, (f) async {
          await t.runAsync(() => f.provider(provider));
          await f.mount(t);
          await f.watch(t);
          await f.until(t, () => f.observer.players.isNotEmpty);
          Map<String, dynamic>? value;
          var done = false;
          final pending = f.observer.players.single.requestNextChannel!().then((
            v,
          ) {
            value = v;
            done = true;
          });
          await f.settle(t, frames: 4);
          await t.pump(const Duration(seconds: 4));
          expect(
            done,
            isFalse,
            reason:
                'channel switch cannot complete before the five second cooldown',
          );
          await t.pump(const Duration(seconds: 1));
          await f.until(t, () => done);
          await pending;
          if (provider == 'premiumize') {
            expect(
              value,
              isNull,
              reason:
                  'Found-not-fixed Premiumize switch has no resolver branch',
            );
          } else {
            expect(value!.keys.toSet(), {
              'channelId',
              'firstUrl',
              'firstTitle',
              'channelName',
              'channelNumber',
            });
            expect(
              value!['firstUrl'],
              'https://streams.test/Original.720p.mkv',
            );
            expect(value!['firstTitle'], 'Original.720p.mkv');
            expect(value!['channelName'], 'Original channel 2');
            expect(value!['channelNumber'], 2);
            expect(value!['channelId'], 'original-2');
          }
        });
      },
    );
  }
}
