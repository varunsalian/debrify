import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';

/// The tvOS decode remedy's per-file restore (`hwdec-image-format=nv12`,
/// written by `onNewMedia` before every open), held once on request.
class _Restore {
  final gate = Completer<void>();
  bool armed = false;
  bool entered = false;
  bool matches(String name, Object? value) =>
      name == 'setProperty' && value == ('hwdec-image-format', 'nv12');
  void release() {
    if (!gate.isCompleted) gate.complete();
  }
}

void Function(FakePlayer) _record(List<String> seq, _Restore restore) => (p) {
  final native = p.platform! as FakeNativePlayer;
  p.beforeOperation = (name, value) {
    if (name == 'open') {
      seq.add('open:${((value as (mk.Playable, bool)).$1 as mk.Media).uri}');
    }
  };
  native.heldOperation = (name, value) =>
      restore.armed && restore.matches(name, value);
  native.beforeOperation = (name, value) async {
    if (restore.matches(name, value)) seq.add('nv12');
    if (name == 'setProperty' &&
        (value as (String, String)).$1 == 'sub-visibility') {
      seq.add('sub-visibility');
    }
    if (restore.armed && restore.matches(name, value)) {
      restore.armed = false;
      restore.entered = true;
      seq.add('parked');
      await restore.gate.future;
    }
  };
};

IptvChannel _channel(int id) => IptvChannel(
  name: 'P20 remedy $id',
  url: 'https://remedy.test/$id.mp4',
  contentType: 'vod',
  group: 'Films',
  channelNumber: id,
);

Future<(EngineDriver, List<String>, _Restore)> _start(
  WidgetTester t,
  List<IptvChannel> channels,
) async {
  final seq = <String>[];
  final restore = _Restore();
  final d = EngineDriver(t, tvos: true, configurePlayer: _record(seq, restore));
  await d.initialize();
  await d.mount(
    screen: VideoPlayerScreen(
      videoUrl: channels.first.url,
      title: channels.first.name,
      iptvChannels: channels,
      iptvStartIndex: 0,
      iptvSourceId: 'p20-remedy',
    ),
  );
  expect(seq, contains('nv12'), reason: 'the launch ran the tvOS restore');
  return (d, seq, restore);
}

/// A guide pick through the TV bar's IPTV entry and the sheet's callback.
Future<void> _pick(EngineDriver d, List<IptvChannel> channels, int i) async {
  final open = d.t.widget<TvControls>(find.byType(TvControls));
  expect(open.onShowIptvChannels, isNotNull);
  open.onShowIptvChannels!();
  await d.f.advance(d.t, const Duration(milliseconds: 350));
  final sheet = d.t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
  d.observe(() => sheet.onChannelSelected(channels, i));
  await d.f.advance(d.t, const Duration(milliseconds: 50));
}

void main() {
  testWidgets(
    'P20 tvOS a new open waits for the remedy restore before resetting subtitles and opening',
    (t) async {
      final channels = [_channel(1), _channel(2)];
      final (d, seq, restore) = await _start(t, channels);
      try {
        seq.clear();
        restore.armed = true;
        await _pick(d, channels, 1);
        await d.f.until(t, () => restore.entered);
        await d.f.advance(t, const Duration(milliseconds: 500));
        expect(seq, ['nv12', 'parked']);
        restore.release();
        await d.f.actions.settle(t);
        expect(seq, [
          'nv12',
          'parked',
          'sub-visibility',
          'open:${channels[1].url}',
        ]);
      } finally {
        restore.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 tvOS an open superseded during its remedy restore stops there; only the newer open continues',
    (t) async {
      final channels = [_channel(1), _channel(2), _channel(3)];
      final (d, seq, restore) = await _start(t, channels);
      try {
        seq.clear();
        restore.armed = true;
        await _pick(d, channels, 1);
        await d.f.until(t, () => restore.entered);
        await _pick(d, channels, 2);
        await d.f.advance(t, const Duration(milliseconds: 500));
        expect(seq, ['nv12', 'parked']);
        restore.release();
        await d.f.actions.settle(t);
        expect(seq, [
          'nv12',
          'parked',
          'nv12',
          'sub-visibility',
          'open:${channels[2].url}',
        ]);
      } finally {
        restore.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 tvOS a live channel zap also restores the remedy before resetting subtitles and opening',
    (t) async {
      IptvChannel live(int id) => IptvChannel(
        name: 'P20 remedy live $id',
        url: 'https://remedy.test/live$id.ts',
        contentType: 'live',
        group: 'News',
        channelNumber: id,
      );
      final channels = [live(1), live(2)];
      final (d, seq, restore) = await _start(t, channels);
      try {
        seq.clear();
        await _pick(d, channels, 1);
        await d.f.actions.settle(t);
        expect(seq, ['nv12', 'sub-visibility', 'open:${channels[1].url}']);
      } finally {
        restore.release();
        await d.close();
      }
    },
  );
}
