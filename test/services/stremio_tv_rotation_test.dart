import 'dart:convert';
import 'dart:io';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_now_playing.dart';
import 'package:debrify/screens/stremio_tv/stremio_tv_service.dart';
import 'package:debrify/services/stremio_tv_rotation.dart';
import 'package:flutter_test/flutter_test.dart';

List<StremioMeta> items() => List.generate(
  11,
  (i) => StremioMeta(id: 'item$i', name: 'Item $i', type: 'movie'),
);
Map<String, Object> describe(StremioTvNowPlaying playing) => {
  'item': playing.item.id,
  'index': playing.itemIndex,
  'start': playing.slotStart.millisecondsSinceEpoch,
  'end': playing.slotEnd.millisecondsSinceEpoch,
};

void main() {
  test('matches 54 frozen original-service selections and schedules', () {
    final feed = items();
    // Captured from the original service at 3b5930b4 before extraction.
    // Keep these independent expected results; do not regenerate from this policy.
    final vectors =
        jsonDecode(
              File(
                'test/services/fixtures/stremio_rotation_baseline.json',
              ).readAsStringSync(),
            )
            as List;
    expect(vectors, hasLength(54));
    for (final raw in vectors) {
      final vector = raw as Map<String, dynamic>;
      final now = DateTime.fromMillisecondsSinceEpoch(
        vector['now'] as int,
        isUtc: true,
      );
      final selected = stremioTvPlayingAt(
        channelId: vector['id'] as String,
        items: feed,
        now: now,
        rotationMinutes: vector['rotation'] as int,
        salt: vector['salt'] as int,
        slotOffset: vector['offset'] as int,
      )!;
      expect(describe(selected), {
        for (final key in ['item', 'index', 'start', 'end']) key: vector[key],
      }, reason: '$vector');
      expect(selected.item, same(feed[selected.itemIndex]));
      expect(selected.slotStart.isUtc, isFalse);
      expect(selected.slotEnd.isUtc, isFalse);
      final schedule = stremioTvSchedule(
        channelId: vector['id'] as String,
        items: feed,
        now: now,
        rotationMinutes: vector['rotation'] as int,
        salt: vector['salt'] as int,
        count: 4,
      );
      expect(
        schedule.map(describe).toList(),
        vector['schedule'],
        reason: '$vector',
      );
    }
  });

  test(
    'slot end is exclusive and the next slot begins at that exact instant',
    () {
      final feed = items();
      StremioTvNowPlaying at(DateTime now) => stremioTvPlayingAt(
        channelId: 'channel',
        items: feed,
        now: now,
        rotationMinutes: 45,
      )!;
      final initial = at(DateTime.utc(2026, 9, 27, 10));
      final last = at(
        initial.slotEnd.subtract(const Duration(milliseconds: 1)),
      );
      expect(describe(last), describe(initial));
      final next = at(initial.slotEnd);
      expect(next.slotStart, initial.slotEnd);
      expect(
        next.slotEnd.difference(next.slotStart),
        const Duration(minutes: 45),
      );
      expect(initial.slotStart.isAfter(DateTime.utc(2026, 9, 27, 10)), isFalse);
    },
  );

  test('empty feeds bypass duration math and schedules remain mutable', () {
    final now = DateTime.utc(2026);
    expect(
      stremioTvPlayingAt(
        channelId: '',
        items: [],
        now: now,
        rotationMinutes: 0,
      ),
      isNull,
    );
    final empty = stremioTvSchedule(
      channelId: '',
      items: [],
      now: now,
      rotationMinutes: 0,
    );
    expect(empty, isEmpty);
    expect(() => empty.clear(), returnsNormally);
    for (final count in [0, -1]) {
      expect(
        stremioTvSchedule(
          channelId: 'a',
          items: items(),
          now: now,
          count: count,
        ),
        isEmpty,
      );
    }
  });

  test(
    'schedule offset entries agree and keep the borrowed item descriptors',
    () {
      final feed = items();
      final now = DateTime.utc(2026, 4, 1);
      final schedule = stremioTvSchedule(
        channelId: 'a',
        items: feed,
        now: now,
        count: 8,
        salt: 17,
      );
      for (var i = 0; i < schedule.length; i++) {
        final selected = stremioTvPlayingAt(
          channelId: 'a',
          items: feed,
          now: now,
          slotOffset: i,
          salt: 17,
        )!;
        expect(describe(schedule[i]), describe(selected));
        expect(schedule[i].item, same(feed[schedule[i].itemIndex]));
      }
      schedule.clear();
      expect(feed, hasLength(11));
    },
  );

  test('daily paging retains its stable 31-bit hash', () {
    expect(stremioTvStableHash(''), 5381);
    expect(stremioTvStableHash('a'), 177670);
    expect(stremioTvStableHash('abc'), 193485963);
    expect(stremioTvStableHash('世界🚀' * 100), inInclusiveRange(0, 0x7fffffff));
  });

  test('legacy facade still forwards offset, duration and salt', () {
    final feed = items();
    final channel = StremioTvChannel(
      id: 'facade',
      displayName: 'Channel',
      addon: StremioAddon(id: 'a', name: 'A', manifestUrl: '', baseUrl: ''),
      catalog: StremioAddonCatalog(id: 'c', name: 'C', type: 'movie'),
      channelNumber: 1,
      items: feed,
    );
    final before = DateTime.now();
    final actual = StremioTvService.instance.getPlayingAtSlotOffset(
      channel,
      slotOffset: 2,
      rotationMinutes: 45,
      salt: 17,
    )!;
    final after = DateTime.now();
    final candidates = [
      for (final now in [before, after])
        describe(
          stremioTvPlayingAt(
            channelId: channel.id,
            items: feed,
            now: now,
            slotOffset: 2,
            rotationMinutes: 45,
            salt: 17,
          )!,
        ),
    ];
    expect(
      describe(actual),
      anyOf(equals(candidates.first), equals(candidates.last)),
    );
    final beforeSchedule = DateTime.now();
    final schedule = StremioTvService.instance.getSchedule(
      channel,
      count: 3,
      rotationMinutes: 45,
      salt: 17,
    );
    final afterSchedule = DateTime.now();
    List<Map<String, Object>> expectedSchedule(DateTime now) =>
        stremioTvSchedule(
          channelId: channel.id,
          items: feed,
          now: now,
          count: 3,
          rotationMinutes: 45,
          salt: 17,
        ).map(describe).toList();
    expect(
      schedule.map(describe).toList(),
      anyOf(
        equals(expectedSchedule(beforeSchedule)),
        equals(expectedSchedule(afterSchedule)),
      ),
    );
    channel.items = [];
    expect(
      StremioTvService.instance.getNowPlaying(channel, rotationMinutes: 0),
      isNull,
    );
    expect(
      StremioTvService.instance.getSchedule(channel, rotationMinutes: 0),
      isEmpty,
    );
  });
}
