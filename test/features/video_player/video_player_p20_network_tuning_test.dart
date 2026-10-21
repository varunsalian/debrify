import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/player_network_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/player_actions.dart';

const _lavf = 'stream-lavf-o';
const _extendedLavf =
    'reconnect=1,reconnect_on_network_error=1,'
    'reconnect_on_http_error=5xx,reconnect_delay_max=10';
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

const _a = PlaylistEntry(url: 'https://tuning.test/a.mp4', title: 'Tuning A');
const _b = PlaylistEntry(url: 'https://tuning.test/b.mp4', title: 'Tuning B');
const _playlist = VideoPlayerScreen(
  videoUrl: 'https://tuning.test/a.mp4',
  title: 'Tuning playlist',
  disableAutoResume: true,
  startIndex: 0,
  playlist: [_a, _b],
);

/// One ordered record of native property reads/writes and player opens.
void Function(FakePlayer) _record(
  List<String> seq, {
  Map<String, String> stock = const {},
}) => (p) {
  final native = p.platform! as FakeNativePlayer;
  native.properties.addAll(stock);
  p.beforeOperation = (name, value) {
    if (name == 'open') seq.add('open');
  };
  native.beforeOperation = (name, value) {
    if (name == 'getProperty') seq.add('get:$value');
    if (name == 'setProperty') {
      final (key, v) = value as (String, String);
      seq.add('set:$key=$v');
    }
  };
};

/// Only the entries that name a tuning key or the lavf slot.
List<String> _tuning(List<String> seq) => [
  for (final e in seq)
    if (e == 'open' ||
        _tuningKeys.any((k) => e == 'get:$k' || e.startsWith('set:$k=')) ||
        e.startsWith('set:$_lavf='))
      e,
];

Future<void> _prefs(
  EngineDriver d, {
  String patience = 'standard',
  String buffer = 'standard',
}) async {
  await d.f.finish<void>(
    d.t,
    PlayerNetworkStorage.setNetworkConnectPatience(patience),
  );
  await d.f.finish<void>(
    d.t,
    PlayerNetworkStorage.setNetworkBufferSize(buffer),
  );
}

Future<void> _next(EngineDriver d) async {
  final dynamic callback = playerControls(d.t).onNext!;
  await d.f.finish<dynamic>(
    d.t,
    d.observe<dynamic>(() => callback()) as Future<dynamic>,
  );
  await d.f.advance(d.t, const Duration(milliseconds: 300));
  await d.f.actions.settle(d.t);
}

IptvChannel _channel(int id, {bool live = true}) => IptvChannel(
  name: 'P20 channel $id',
  url: 'https://tuning.test/$id.ts',
  contentType: live ? 'live' : 'vod',
  group: 'News',
  channelNumber: id,
);

Future<(EngineDriver, List<String>)> _iptvStart(
  WidgetTester t,
  List<IptvChannel> channels, {
  Map<String, String> stock = const {},
  String patience = 'extended',
}) async {
  final seq = <String>[];
  final d = EngineDriver(t, configurePlayer: _record(seq, stock: stock));
  await d.initialize();
  await _prefs(d, patience: patience);
  await d.mount(
    screen: VideoPlayerScreen(
      videoUrl: channels.first.url,
      title: channels.first.name,
      iptvChannels: channels,
      iptvStartIndex: 0,
      iptvSourceId: 'p20-tuning',
    ),
  );
  return (d, seq);
}

/// Starts a guide pick through the IPTV sheet's own callback.
Future<void> _pick(
  EngineDriver d,
  List<IptvChannel> channels,
  int index, {
  bool settle = true,
}) async {
  final open = playerControls(d.t).onShowIptvChannels;
  expect(open, isNotNull, reason: 'The player exposes its IPTV guide');
  open!();
  await d.f.advance(d.t, const Duration(milliseconds: 350));
  final sheet = d.t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
  d.observe(() => sheet.onChannelSelected(channels, index));
  if (settle) await d.f.actions.settle(d.t);
}

void main() {
  testWidgets(
    'P20 Standard tuning writes only an empty stream-lavf-o before the open',
    (t) async {
      final seq = <String>[];
      final d = EngineDriver(t, configurePlayer: _record(seq));
      await d.initialize();
      try {
        await d.mount();
        expect(_tuning(seq), ['set:$_lavf=', 'open']);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 Extended patience captures the stock timeout, then applies 90 s after the VOD reconnect options',
    (t) async {
      final seq = <String>[];
      final d = EngineDriver(
        t,
        configurePlayer: _record(seq, stock: {'network-timeout': '60'}),
      );
      await d.initialize();
      try {
        await _prefs(d, patience: 'extended');
        await d.mount();
        expect(_tuning(seq), [
          'set:$_lavf=$_extendedLavf',
          'get:network-timeout',
          'set:network-timeout=90',
          'open',
        ]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 Large buffer captures and applies all three cache properties in order',
    (t) async {
      final seq = <String>[];
      final d = EngineDriver(
        t,
        configurePlayer: _record(
          seq,
          stock: {
            'demuxer-max-bytes': '150MiB',
            'demuxer-readahead-secs': '1',
            'cache-secs': '10',
          },
        ),
      );
      await d.initialize();
      try {
        await _prefs(d, buffer: 'large');
        await d.mount();
        expect(_tuning(seq), [
          'set:$_lavf=',
          'get:demuxer-max-bytes',
          'get:demuxer-readahead-secs',
          'get:cache-secs',
          'set:demuxer-max-bytes=256MiB',
          'set:demuxer-readahead-secs=120',
          'set:cache-secs=120',
          'open',
        ]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 an unreadable stock value skips tuning for that open and the next open captures again',
    (t) async {
      final seq = <String>[];
      final d = EngineDriver(t, configurePlayer: _record(seq));
      await d.initialize();
      try {
        await _prefs(d, patience: 'patient');
        await d.mount(screen: _playlist);
        expect(_tuning(seq).where((e) => !e.startsWith('set:$_lavf')), [
          'get:network-timeout',
          'open',
        ]);
        expect(
          d.logs,
          contains(
            'Player: network tuning skipped — network-timeout unreadable',
          ),
        );
        (d.player.platform! as FakeNativePlayer).properties['network-timeout'] =
            '45';
        seq.clear();
        await _next(d);
        expect(_tuning(seq).where((e) => !e.startsWith('set:$_lavf')), [
          'get:network-timeout',
          'set:network-timeout=180',
          'open',
        ]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a later VOD open reuses the captured defaults without reading them again',
    (t) async {
      final seq = <String>[];
      final d = EngineDriver(
        t,
        configurePlayer: _record(seq, stock: {'network-timeout': '60'}),
      );
      await d.initialize();
      try {
        await _prefs(d, patience: 'extended');
        await d.mount(screen: _playlist);
        seq.clear();
        await _next(d);
        expect(_tuning(seq), [
          'set:$_lavf=$_extendedLavf',
          'set:network-timeout=90',
          'open',
        ]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a profile storage failure while loading presets degrades to Standard and still opens',
    (t) async {
      final seq = <String>[];
      final d = EngineDriver(
        t,
        configurePlayer: _record(seq, stock: {'network-timeout': '60'}),
      );
      await d.initialize();
      try {
        // A non-string value under the preset key makes the typed read throw.
        await d.f.finish<void>(
          t,
          ProfilePreferences.instance().then(
            (p) => p.setInt('network_connect_patience', 7),
          ),
        );
        await d.mount();
        expect(_tuning(seq), ['set:$_lavf=', 'open']);
        expect(
          d.logs.where(
            (l) => l.startsWith('Player: network tuning load failed'),
          ),
          hasLength(1),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a failed stream-lavf-o write is logged and tuning and the open still run',
    (t) async {
      final seq = <String>[];
      final d = EngineDriver(
        t,
        configurePlayer: (p) {
          _record(seq, stock: {'network-timeout': '60'})(p);
          final native = p.platform! as FakeNativePlayer;
          final record = native.beforeOperation!;
          native.beforeOperation = (name, value) {
            record(name, value);
            if (name == 'setProperty' &&
                (value as (String, String)).$1 == _lavf) {
              throw StateError('lavf rejected');
            }
          };
        },
      );
      await d.initialize();
      try {
        await _prefs(d, patience: 'extended');
        await d.mount();
        expect(_tuning(seq), [
          'set:$_lavf=$_extendedLavf',
          'get:network-timeout',
          'set:network-timeout=90',
          'open',
        ]);
        expect(
          d.logs.where((l) => l.startsWith('Player: stream-lavf-o set failed')),
          hasLength(1),
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P20 a failed tuning write is logged and the open still runs', (
    t,
  ) async {
    final seq = <String>[];
    final d = EngineDriver(
      t,
      configurePlayer: (p) {
        _record(seq, stock: {'network-timeout': '60'})(p);
        final native = p.platform! as FakeNativePlayer;
        final record = native.beforeOperation!;
        native.beforeOperation = (name, value) {
          record(name, value);
          if (name == 'setProperty' &&
              (value as (String, String)).$1 == 'network-timeout') {
            throw StateError('timeout rejected');
          }
        };
      },
    );
    await d.initialize();
    try {
      await _prefs(d, patience: 'extended');
      await d.mount();
      expect(_tuning(seq).last, 'open');
      expect(
        d.logs.where(
          (l) => l.startsWith('Player: network tuning apply failed'),
        ),
        hasLength(1),
      );
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P20 a live launch before any tuning writes the live reconnect options and no tuning property',
    (t) async {
      final channels = [_channel(1), _channel(2)];
      final (d, seq) = await _iptvStart(
        t,
        channels,
        stock: {'network-timeout': '60'},
      );
      try {
        expect(_tuning(seq), ['set:$_lavf=$_liveLavf', 'open']);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a live open after a tuned VOD open restores the captured stock value',
    (t) async {
      final channels = [_channel(1, live: false), _channel(2)];
      final (d, seq) = await _iptvStart(
        t,
        channels,
        stock: {'network-timeout': '60'},
      );
      try {
        expect(_tuning(seq), [
          'set:$_lavf=$_extendedLavf',
          'get:network-timeout',
          'set:network-timeout=90',
          'open',
        ]);
        seq.clear();
        await _pick(d, channels, 1);
        expect(_tuning(seq), [
          'set:$_lavf=$_liveLavf',
          'set:network-timeout=60',
          'open',
        ]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a superseded capture stores nothing and the newer open captures and applies once',
    (t) async {
      final channels = [
        _channel(1),
        _channel(2, live: false),
        _channel(3, live: false),
      ];
      final (d, seq) = await _iptvStart(
        t,
        channels,
        stock: {'network-timeout': '60'},
      );
      final native = d.player.platform! as FakeNativePlayer;
      final read = Completer<void>();
      try {
        seq.clear();
        native.delays['getProperty'] = read;
        await _pick(d, channels, 1, settle: false);
        await d.f.until(t, () => seq.contains('get:network-timeout'));
        await _pick(d, channels, 2, settle: false);
        await d.f.advance(t, const Duration(milliseconds: 50));
        read.complete();
        await d.f.actions.settle(t);
        expect(
          _tuning(seq).where((e) => !e.startsWith('set:$_lavf')).toList(),
          [
            'get:network-timeout',
            'get:network-timeout',
            'set:network-timeout=90',
            'open',
          ],
        );
      } finally {
        if (!read.isCompleted) read.complete();
        await d.close();
      }
    },
  );
}
