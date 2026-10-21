import 'dart:math' as math;

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/utils/aspect_mode_utils.dart';
import 'package:debrify/screens/video_player/widgets/dock_style.dart';
import 'package:debrify/screens/video_player/widgets/iptv_zap_banner.dart';
import 'package:debrify/screens/video_player/widgets/player_guide_style.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/player_actions.dart';

/// Ordered sid / sub-visibility / video-zoom writes and the player open.
void Function(FakePlayer) _record(
  List<String> seq, {
  Set<String> rejected = const {},
}) => (p) {
  p.beforeOperation = (name, value) {
    if (name == 'open') seq.add('open');
  };
  (p.platform! as FakeNativePlayer).beforeOperation = (name, value) {
    if (name != 'setProperty') return;
    final (key, v) = value as (String, String);
    seq.add('set:$key=$v');
    if (rejected.contains(key)) throw StateError('$key rejected');
  };
};

/// The [keys] writes up to and including the first open.
List<String> _only(List<String> seq, Set<String> keys) => [
  for (final e in seq.take(seq.indexOf('open') + 1))
    if (e == 'open' || keys.any((k) => e.startsWith('set:$k='))) e,
];

const _subtitle = {'sid', 'sub-visibility'};

String _zoom(AspectMode mode) =>
    (math.log(AspectModeUtils.getScaleForMode(mode)) / math.ln2)
        .toStringAsFixed(6);

Future<List<String>> _mountWith(
  WidgetTester t, {
  bool forced = false,
  bool foreign = false,
  int? aspect,
  Set<String> rejected = const {},
  void Function(EngineDriver)? inspect,
}) async {
  final seq = <String>[];
  final d = EngineDriver(t, configurePlayer: _record(seq, rejected: rejected));
  await d.initialize();
  try {
    await d.f.finish<void>(
      t,
      SubtitleSettingsStorage.setSubtitleForcedOnly(forced),
    );
    await d.f.finish<void>(
      t,
      SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(foreign),
    );
    if (aspect != null) {
      await d.f.finish<void>(
        t,
        PlayerSettingsStorage.setPlayerDefaultAspectIndex(aspect),
      );
    }
    await d.mount();
    inspect?.call(d);
    expect(d.errors, isEmpty);
    return seq;
  } finally {
    await d.close();
  }
}

void main() {
  testWidgets(
    'P20 forced-only alone is a subtitle policy: sid is cleared before sub-visibility, both before the open',
    (t) async {
      final seq = await _mountWith(t, forced: true);
      expect(_only(seq, _subtitle), [
        'set:sid=no',
        'set:sub-visibility=no',
        'open',
      ]);
    },
  );

  testWidgets(
    'P20 only-foreign-audio alone is a subtitle policy that clears sid before the open',
    (t) async {
      final seq = await _mountWith(t, foreign: true);
      expect(_only(seq, _subtitle), [
        'set:sid=no',
        'set:sub-visibility=no',
        'open',
      ]);
    },
  );

  testWidgets(
    'P20 without a subtitle policy only sub-visibility is reset before the open',
    (t) async {
      final seq = await _mountWith(t);
      expect(_only(seq, _subtitle), ['set:sub-visibility=no', 'open']);
    },
  );

  testWidgets(
    'P20 a rejected subtitle reset is logged and the open still runs',
    (t) async {
      final logs = <String>[];
      final seq = await _mountWith(
        t,
        forced: true,
        rejected: {'sid'},
        inspect: (d) => logs.addAll(d.logs),
      );
      expect(_only(seq, _subtitle), ['set:sid=no', 'open']);
      expect(
        logs.where(
          (l) => l.startsWith('Player: subtitle visibility reset failed'),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'P20 the stored default aspect reaches video-zoom; out-of-range indexes clamp to the ends',
    (t) async {
      for (final (index, mode) in [
        (1, AspectMode.cover),
        (99, AspectMode.cinemaZoom),
        (-4, AspectMode.contain),
      ]) {
        final seq = await _mountWith(t, aspect: index);
        expect(
          _only(seq, {'video-zoom'}).first,
          'set:video-zoom=${_zoom(mode)}',
          reason: 'index $index',
        );
      }
    },
  );

  testWidgets('P20 the auto-sync preference is loaded before startup', (
    t,
  ) async {
    for (final enabled in [true, false]) {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.f.finish<void>(
          t,
          SubtitleSettingsStorage.setSubtitleAutoSyncEnabled(enabled),
        );
        await d.mount();
        expect(
          d.logs.where((l) => l.startsWith('SubtitleAutoSync: pref loaded')),
          ['SubtitleAutoSync: pref loaded, enabled=$enabled'],
        );
      } finally {
        await d.close();
      }
    }
  });

  testWidgets(
    'P20 the in-player guide style reaches the launch zap banner with its tokens',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.f.finish<void>(
          t,
          IptvAppearanceStorage.setIptvPlayerGuideStyle('glass'),
        );
        final channel = IptvChannel(
          name: 'P20 guide style',
          url: 'https://defaults.test/live.ts',
          contentType: 'live',
          group: 'News',
        );
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: channel.url,
            title: channel.name,
            iptvChannels: [channel],
            iptvStartIndex: 0,
          ),
        );
        final banners = t
            .widgetList<IptvZapBanner>(find.byType(IptvZapBanner))
            .toList();
        expect(banners, isNotEmpty);
        expect(banners.map((b) => b.style).toSet(), {PlayerGuideStyle.glass});
        expect(banners.map((b) => b.tokens).toSet(), {PlayerGuideTokens.glass});
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P20 the stored dock style reaches the controls after startup', (
    t,
  ) async {
    final d = EngineDriver(t);
    await d.initialize();
    try {
      await d.f.finish<void>(
        t,
        PlayerAppearanceStorage.setPlayerDockStyle('cinema'),
      );
      await d.mount();
      expect(playerControls(t).dockStyle, PlayerDockStyle.cinema);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P20 tvOS display-match clear failure is swallowed and playback still opens',
    (t) async {
      final d = EngineDriver(t, tvos: true);
      await d.initialize();
      const match = MethodChannel('debrify/tvos_display_match');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(match, (call) async {
            d.displayMatch.add(call);
            if (call.method == 'clear') {
              throw PlatformException(code: 'clear', message: 'refused');
            }
            return d.displayMatchStatus;
          });
      try {
        await d.mount();
        expect(d.displayMatch.map((c) => c.method).take(1), ['clear']);
        expect(
          d.logs.where((l) => l.startsWith('DisplayMatch: tvOS clear failed')),
          hasLength(1),
        );
        expect(d.player.calls.where((c) => c.$1 == 'open'), hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final failure in [true, false]) {
    testWidgets(
      'P20 tvOS a ${failure ? 'failed' : 'missing'} route channel count is treated as unknown and leaves channels alone',
      (t) async {
        final seq = <String>[];
        final d = EngineDriver(
          t,
          tvos: true,
          configurePlayer: (p) {
            (p.platform! as FakeNativePlayer).beforeOperation = (name, value) {
              if (name != 'setProperty') return;
              final (key, v) = value as (String, String);
              if (key == 'audio-channels') seq.add('set:$key=$v');
            };
          },
        );
        await d.initialize();
        const tvlog = MethodChannel('debrify/tvlog');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(tvlog, (call) async {
              d.tvlog.add(call);
              if (call.method == 'outputChannelCount') {
                if (failure) throw PlatformException(code: 'route');
                return null;
              }
              return null;
            });
        try {
          await d.mount();
          expect(
            d.tvlog.where((c) => c.method == 'outputChannelCount'),
            hasLength(1),
          );
          expect(seq, isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P20 tvOS a two-channel route caps the output to stereo before the open',
    (t) async {
      final seq = <String>[];
      final d = EngineDriver(
        t,
        tvos: true,
        routeChannels: 2,
        configurePlayer: (p) {
          p.beforeOperation = (name, value) {
            if (name == 'open') seq.add('open');
          };
          (p.platform! as FakeNativePlayer).beforeOperation = (name, value) {
            if (name != 'setProperty') return;
            final (key, v) = value as (String, String);
            if (key == 'audio-channels') seq.add('set:$key=$v');
          };
        },
      );
      await d.initialize();
      try {
        await d.mount();
        expect(seq, ['set:audio-channels=stereo', 'open']);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 the stored default aspect reaches the video fit; negative indexes clamp to contain',
    (t) async {
      for (final (index, fit) in [
        (1, BoxFit.cover),
        (3, BoxFit.fitHeight),
        (-4, BoxFit.contain),
      ]) {
        final d = EngineDriver(t);
        await d.initialize();
        try {
          await d.f.finish<void>(
            t,
            PlayerSettingsStorage.setPlayerDefaultAspectIndex(index),
          );
          await d.mount();
          expect(
            t.widget<mkv.Video>(find.byType(mkv.Video)).fit,
            fit,
            reason: 'index $index',
          );
        } finally {
          await d.close();
        }
      }
    },
  );
}
