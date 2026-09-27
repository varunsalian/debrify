import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../fixtures/iptv_lists_fixture.dart';

void main() {
  test(
    'stored list/channel order wins over opt-in order; favourites/empty rows excluded',
    () async {
      final calls = <String>[];
      final r = repository(
        extras: () async {
          calls.add('extras');
          return [
            (id: 'iptvlist:a', title: 'old A'),
            (id: 'iptvlist:b', title: 'old B'),
            (id: 'iptvlist:empty', title: ''),
            (id: 'iptvlist:favorites', title: ''),
            (id: 'traktlist:watchlist', title: ''),
            (id: 'iptvlist:a', title: 'duplicate'),
          ];
        },
        lists: () async {
          calls.add('lists');
          return [
            meta('b', title: 'New B'),
            meta('empty'),
            meta('ignored'),
            meta('a'),
            (id: 'favorites', title: '', isFavorites: true),
          ];
        },
        channels: (id) async {
          calls.add(id);
          return id == 'empty'
              ? {}
              : {
                  'second': {'name': 'Two'},
                  'first': {'name': 'One'},
                };
        },
      );
      final result = (await r.read(isCurrent: () => true))!;
      expect(calls, ['extras', 'lists', 'b', 'empty', 'a']);
      expect(result.hasWantedLists, isTrue);
      expect(result.rows.map((r) => r.listId), ['b', 'a']);
      expect(result.rows.first.title, 'New B');
      expect(result.rows.first.channels.map((c) => c.url), ['second', 'first']);
      expect(result.rows.clear, throwsUnsupportedError);
      expect(result.rows.first.channels.clear, throwsUnsupportedError);
    },
  );

  test(
    'live/VOD/series fields, numeric conversion, empty normalization and copied headers survive',
    () async {
      final headers = <String, dynamic>{'User-Agent': 'UA', 'X': 3};
      final map = <String, Map<String, dynamic>>{
        'vod': {
          'name': '',
          'logoUrl': '',
          'group': '',
          'channelNumber': 7.8,
          'duration': 123.9,
          'contentType': 'vod',
          'playlistId': 'provider',
          'httpHeaders': headers,
        },
        'xtream-series://series': {
          'name': 'Series',
          'duration': 0,
          'contentType': 'series',
        },
        'live': {
          'name': ' spaced ',
          'logoUrl': ' logo ',
          'group': ' group ',
          'playlistId': '',
        },
      };
      final result = (await repository(
        channels: (_) async => map,
      ).read(isCurrent: () => true))!;
      final channels = result.rows.single.channels;
      final vod = channels.first;
      expect(vod.name, 'Unknown Channel');
      expect(vod.logoUrl, isNull);
      expect(vod.group, isNull);
      expect(vod.channelNumber, 7);
      expect(vod.duration, 123);
      expect(vod.contentType, 'vod');
      expect(vod.isLive, isFalse);
      expect(vod.attributes, {'list_playlist_id': 'provider'});
      expect(vod.httpHeaders, {'User-Agent': 'UA', 'X': '3'});
      expect(channels[1].url, 'xtream-series://series');
      expect(channels[1].contentType, 'series');
      expect(channels[1].isLive, isFalse);
      expect(channels.last.name, ' spaced ');
      expect(channels.last.logoUrl, ' logo ');
      expect(channels.last.group, ' group ');
      expect(channels.last.duration, -1);
      expect(channels.last.isLive, isTrue);
      expect(channels.last.attributes, isEmpty);
      headers.clear();
      map.clear();
      expect(vod.httpHeaders.length, 2);
      expect(vod.httpHeaders.clear, throwsUnsupportedError);
      expect(vod.attributes.clear, throwsUnsupportedError);
    },
  );

  test(
    'no enabled custom lists avoids list/channel reads and differs from unmatched opt-ins',
    () async {
      var enabled = false;
      var listReads = 0;
      final r = repository(
        extras: () async => [
          (id: enabled ? 'iptvlist:missing' : 'iptvlist:favorites', title: ''),
        ],
        lists: () async {
          listReads++;
          return [meta('a')];
        },
        channels: (_) async => throw StateError('unexpected read'),
      );
      expect((await r.read(isCurrent: () => true))!.hasWantedLists, isFalse);
      expect(listReads, 0);
      enabled = true;
      final result = (await r.read(isCurrent: () => true))!;
      expect(result.hasWantedLists, isTrue);
      expect(result.rows, isEmpty);
      expect(listReads, 1);
    },
  );

  for (final stage in ['before', 'extras', 'lists', 'a', 'b']) {
    test(
      'retirement at $stage stops later reads and discards incomplete snapshots',
      () async {
        var current = stage != 'before';
        final calls = <String>[];
        void mark(String name) {
          calls.add(name);
          if (name == stage) current = false;
        }

        final r = repository(
          extras: () async {
            mark('extras');
            return [
              (id: 'iptvlist:a', title: ''),
              (id: 'iptvlist:b', title: ''),
            ];
          },
          lists: () async {
            mark('lists');
            return [meta('a'), meta('b')];
          },
          channels: (id) async {
            mark(id);
            return saved(id);
          },
        );
        expect(await r.read(isCurrent: () => current), isNull);
        final steps = ['extras', 'lists', 'a', 'b'];
        expect(
          calls,
          steps.take(stage == 'before' ? 0 : steps.indexOf(stage) + 1),
        );
      },
    );
  }

  test(
    'reads each selected list sequentially and propagates a later failure',
    () async {
      final pending = Completer<SavedChannels>();
      final entered = Completer<void>();
      final calls = <String>[];
      final r = repository(
        extras: () async => [
          (id: 'iptvlist:a', title: ''),
          (id: 'iptvlist:b', title: ''),
        ],
        lists: () async => [meta('a'), meta('b')],
        channels: (id) {
          calls.add(id);
          if (id == 'a') {
            entered.complete();
            return pending.future;
          }
          throw StateError('later list');
        },
      );
      final read = r.read(isCurrent: () => true);
      await entered.future;
      expect(calls, ['a']);
      final assertion = expectLater(read, throwsStateError);
      pending.complete(saved('One'));
      await assertion;
      expect(calls, ['a', 'b']);
    },
  );
}
