import 'package:debrify/services/stremio_tv_service.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/stremio_tv_fixture.dart';

Future<void> shuffle(WidgetTester t, StremioTvFixture f) async {
  await f.menu(t);
  await f.tap(t, find.widgetWithText(MenuItemButton, 'Shuffle (Mix 1)'));
}

String inlineTitle(Map<String, dynamic> channel) =>
    (channel['nowPlaying'] as Map)['title'] as String;

void main() {
  for (final path in [
    'fresh launch metadata',
    'guide provider',
    'equal-offset Next and switch',
  ]) {
    testWidgets(
      'C9 (O) mix salt changes $path with different-item precondition',
      (t) async {
        await stremioTvCase(t, (f) async {
          f.itemCount = 2;
          await f.mount(t);
          final channel = f.channel(t);
          final service = StremioTvService.instance;
          final original = service.getSchedule(
            channel,
            count: 3,
            rotationMinutes: 90,
            salt: 0,
          );
          final shuffled = service.getSchedule(
            channel,
            count: 3,
            rotationMinutes: 90,
            salt: 1,
          );
          expect(
            original.map((s) => s.slotEnd),
            shuffled.map((s) => s.slotEnd),
          );
          for (var offset = 0; offset < 3; offset++) {
            expect(
              original[offset].item.id,
              isNot(shuffled[offset].item.id),
              reason: 'two-item salt precondition at compared offset $offset',
            );
          }
          await f.play(t);
          final player = f.observer.players.single;
          Object? before;
          int? end;
          if (path == 'fresh launch metadata') {
            before = inlineTitle(
              player.stremioTvChannels!.singleWhere(
                (c) => c['id'] == channel.id,
              ),
            );
          } else if (path == 'guide provider') {
            final guide = await t.runAsync(
              () => player.stremioTvGuideDataProvider!([channel.id]),
            );
            before = inlineTitle(guide![channel.id] as Map<String, dynamic>);
          } else {
            final next = await t.runAsync(
              () => player.stremioTvNextProvider!(channel.id),
            );
            before = next!['contentImdbId'];
            end = (next['nowPlaying'] as Map)['slotEndMs'] as int;
            expect(end, original[1].slotEnd.millisecondsSinceEpoch);
          }
          await shuffle(t, f);
          if (path == 'fresh launch metadata') {
            await f.play(t);
            final after = inlineTitle(
              f.observer.players.last.stremioTvChannels!.singleWhere(
                (c) => c['id'] == channel.id,
              ),
            );
            expect(after, isNot(before));
            expect(after, shuffled[0].item.name);
          } else if (path == 'guide provider') {
            final guide = await t.runAsync(
              () => player.stremioTvGuideDataProvider!([channel.id]),
            );
            final after = inlineTitle(
              guide![channel.id] as Map<String, dynamic>,
            );
            expect(after, isNot(before));
            expect(after, shuffled[0].item.name);
          } else {
            // Channel switch resets this channel's cursor to offset zero.
            final switched = await t.runAsync(
              () => player.stremioTvChannelSwitchProvider!(channel.id),
            );
            expect(
              switched!['contentImdbId'],
              shuffled[0].item.effectiveImdbId,
            );
            final next = await t.runAsync(
              () => player.stremioTvNextProvider!(channel.id),
            );
            expect(
              (next!['nowPlaying'] as Map)['slotEndMs'],
              end,
              reason: 'the compared Next results must use the same guide slot',
            );
            expect(next['contentImdbId'], isNot(before));
            expect(next['contentImdbId'], shuffled[1].item.effectiveImdbId);
          }
        });
      },
    );
  }

  testWidgets(
    'C9 (R/O) rotation max-start hide-now-playing and refresh reach consumers',
    (t) async {
      await stremioTvCase(t, (f) async {
        await t.runAsync(() async {
          await StremioTvStorage.setStremioTvRotationMinutes(120);
          await StremioTvStorage.setStremioTvSeriesRotationMinutes(60);
          await StremioTvStorage.setStremioTvMaxStartPercent(10);
          await StremioTvStorage.setStremioTvHideNowPlaying(true);
          await StremioTvStorage.setStremioTvAutoRefresh(true);
        });
        await f.mount(t);
        expect(f.tuner(t).hideNowPlaying, isTrue);
        expect(f.tuner(t).autoRefresh, isTrue);
        expect(f.tuner(t).rotationFor(f.channel(t)), 120);
        await f.play(t);
        final player = f.observer.players.single;
        expect(player.startAtPercent, inInclusiveRange(0.0, 0.1));
        final first = await t.runAsync(
          () => player.stremioTvNextProvider!(f.channelId(1)),
        );
        final second = await t.runAsync(
          () => player.stremioTvNextProvider!(f.channelId(1)),
        );
        expect(
          ((second!['nowPlaying'] as Map)['slotEndMs'] as int) -
              ((first!['nowPlaying'] as Map)['slotEndMs'] as int),
          const Duration(minutes: 120).inMilliseconds,
        );
      });
    },
  );
}
