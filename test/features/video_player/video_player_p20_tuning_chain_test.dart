import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_network_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/player_actions.dart';

const _lavf = 'stream-lavf-o';
const _liveLavf =
    'reconnect=1,reconnect_streamed=1,'
    'reconnect_on_network_error=1,'
    'reconnect_on_http_error=5xx,'
    'reconnect_delay_max=5';
const _tuningKeys = {
  'network-timeout',
  'demuxer-max-bytes',
  'demuxer-readahead-secs',
  'cache-secs',
};

/// Parks the first native operation that [match] accepts, once.
class _Park {
  _Park(this.match);
  final bool Function(String name, Object? value) match;
  final gate = Completer<void>();
  bool armed = false;
  bool entered = false;
  bool held(String name, Object? value) => armed && match(name, value);
  void release() {
    if (!gate.isCompleted) gate.complete();
  }
}

/// One ordered record of tuning reads/writes and opens, plus an optional park.
void Function(FakePlayer) _record(
  List<String> seq,
  _Park park, {
  Map<String, String> stock = const {},
}) => (p) {
  final native = p.platform! as FakeNativePlayer;
  native.properties.addAll(stock);
  p.beforeOperation = (name, value) {
    if (name == 'open') seq.add('open');
  };
  native.heldOperation = park.held;
  native.beforeOperation = (name, value) async {
    if (name == 'getProperty') seq.add('get:$value');
    if (name == 'setProperty') {
      final (key, v) = value as (String, String);
      seq.add('set:$key=$v');
    }
    if (park.held(name, value)) {
      park.armed = false;
      park.entered = true;
      seq.add('parked');
      await park.gate.future;
    }
  };
};

List<String> _tuning(List<String> seq) => [
  for (final e in seq)
    if (e == 'open' ||
        e == 'parked' ||
        _tuningKeys.any((k) => e == 'get:$k' || e.startsWith('set:$k=')))
      e,
];

IptvChannel _channel(int id, {bool live = true}) => IptvChannel(
  name: 'P20 chain $id',
  url: 'https://chain.test/$id.ts',
  contentType: live ? 'live' : 'vod',
  group: 'News',
  channelNumber: id,
);

Future<(EngineDriver, List<String>, _Park)> _start(
  WidgetTester t,
  List<IptvChannel> channels,
  bool Function(String, Object?) park, {
  Map<String, String> stock = const {},
  String patience = 'extended',
  String buffer = 'standard',
}) async {
  final seq = <String>[];
  final parked = _Park(park);
  final d = EngineDriver(
    t,
    configurePlayer: _record(seq, parked, stock: stock),
  );
  await d.initialize();
  await d.f.finish<void>(
    t,
    PlayerNetworkStorage.setNetworkConnectPatience(patience),
  );
  await d.f.finish<void>(t, PlayerNetworkStorage.setNetworkBufferSize(buffer));
  await d.mount(
    screen: VideoPlayerScreen(
      videoUrl: channels.first.url,
      title: channels.first.name,
      iptvChannels: channels,
      iptvStartIndex: 0,
      iptvSourceId: 'p20-chain',
    ),
  );
  return (d, seq, parked);
}

/// Starts a guide pick through the IPTV sheet's own callback, unsettled.
Future<void> _pick(
  EngineDriver d,
  List<IptvChannel> channels,
  int index,
) async {
  final open = playerControls(d.t).onShowIptvChannels;
  expect(open, isNotNull, reason: 'The player exposes its IPTV guide');
  open!();
  await d.f.advance(d.t, const Duration(milliseconds: 350));
  final sheet = d.t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
  d.observe(() => sheet.onChannelSelected(channels, index));
  await d.f.advance(d.t, const Duration(milliseconds: 50));
}

bool _readTimeout(String name, Object? value) =>
    name == 'getProperty' && value == 'network-timeout';

void main() {
  testWidgets(
    'P20 a newer open waits for a parked older tuning capture before it captures, writes or opens',
    (t) async {
      final channels = [
        _channel(1),
        _channel(2, live: false),
        _channel(3, live: false),
      ];
      final (d, seq, park) = await _start(
        t,
        channels,
        _readTimeout,
        stock: {'network-timeout': '60'},
      );
      try {
        seq.clear();
        park.armed = true;
        await _pick(d, channels, 1);
        await d.f.until(t, () => park.entered);
        await _pick(d, channels, 2);
        await d.f.advance(t, const Duration(milliseconds: 300));
        expect(
          _tuning(seq),
          ['get:network-timeout', 'parked'],
          reason: 'the newer apply is queued behind the parked capture',
        );
        park.release();
        await d.f.actions.settle(t);
        expect(_tuning(seq), [
          'get:network-timeout',
          'parked',
          'get:network-timeout',
          'set:network-timeout=90',
          'open',
        ]);
      } finally {
        park.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a queued tuning apply superseded before it runs reads and writes nothing',
    (t) async {
      final channels = [
        _channel(1),
        _channel(2, live: false),
        _channel(3, live: false),
        _channel(4, live: false),
      ];
      final (d, seq, park) = await _start(
        t,
        channels,
        _readTimeout,
        stock: {'network-timeout': '60'},
      );
      try {
        seq.clear();
        park.armed = true;
        await _pick(d, channels, 1);
        await d.f.until(t, () => park.entered);
        await _pick(d, channels, 2);
        await _pick(d, channels, 3);
        await d.f.advance(t, const Duration(milliseconds: 300));
        park.release();
        await d.f.actions.settle(t);
        // Channel 2's capture was superseded and channel 3's queued apply
        // never ran: only channel 4 reads, writes and opens.
        expect(_tuning(seq), [
          'get:network-timeout',
          'parked',
          'get:network-timeout',
          'set:network-timeout=90',
          'open',
        ]);
        expect(
          d.player.calls
              .where((c) => c.$1 == 'open')
              .map((c) => ((c.$2 as (mk.Playable, bool)).$1 as mk.Media).uri)
              .last,
          channels[3].url,
        );
      } finally {
        park.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a tuning restore superseded mid-write stops at the next property and the live open restores stock',
    (t) async {
      final channels = [
        _channel(1, live: false),
        _channel(2, live: false),
        _channel(3),
      ];
      final (d, seq, park) = await _start(
        t,
        channels,
        (name, value) =>
            name == 'setProperty' && value == ('demuxer-max-bytes', '256MiB'),
        stock: {
          'demuxer-max-bytes': '150MiB',
          'demuxer-readahead-secs': '1',
          'cache-secs': '10',
        },
        patience: 'standard',
        buffer: 'large',
      );
      try {
        seq.clear();
        park.armed = true;
        await _pick(d, channels, 1);
        await d.f.until(t, () => park.entered);
        await _pick(d, channels, 2);
        await d.f.advance(t, const Duration(milliseconds: 300));
        park.release();
        await d.f.actions.settle(t);
        expect(_tuning(seq), [
          'set:demuxer-max-bytes=256MiB',
          'parked',
          'set:demuxer-max-bytes=150MiB',
          'set:demuxer-readahead-secs=1',
          'set:cache-secs=10',
          'open',
        ]);
        final native = d.player.platform! as FakeNativePlayer;
        expect(native.properties['demuxer-readahead-secs'], '1');
        expect(native.properties['cache-secs'], '10');
      } finally {
        park.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 an open superseded during its stream-lavf-o write applies no VOD tuning after the newer live open',
    (t) async {
      final channels = [
        _channel(1, live: false),
        _channel(2, live: false),
        _channel(3),
      ];
      final (d, seq, park) = await _start(
        t,
        channels,
        (name, value) =>
            name == 'setProperty' && (value as (String, String)).$1 == _lavf,
        stock: {'network-timeout': '60'},
      );
      try {
        seq.clear();
        park.armed = true;
        await _pick(d, channels, 1);
        await d.f.until(t, () => park.entered);
        await _pick(d, channels, 2);
        await d.f.advance(t, const Duration(milliseconds: 300));
        expect(seq, contains('set:$_lavf=$_liveLavf'));
        park.release();
        await d.f.actions.settle(t);
        expect(_tuning(seq), ['parked', 'set:network-timeout=60', 'open']);
        final native = d.player.platform! as FakeNativePlayer;
        expect(native.properties['network-timeout'], '60');
      } finally {
        park.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 presets are read once per screen: a change after the first open does not reach the next open',
    (t) async {
      final channels = [_channel(1, live: false), _channel(2, live: false)];
      final (d, seq, park) = await _start(
        t,
        channels,
        (name, value) => false,
        stock: {'network-timeout': '60'},
        patience: 'standard',
      );
      try {
        await d.f.finish<void>(
          t,
          PlayerNetworkStorage.setNetworkConnectPatience('extended'),
        );
        seq.clear();
        await _pick(d, channels, 1);
        await d.f.actions.settle(t);
        expect(seq, contains('set:$_lavf='));
        expect(_tuning(seq), ['open']);
      } finally {
        park.release();
        await d.close();
      }
    },
  );
}
