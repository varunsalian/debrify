import 'dart:async';

import 'package:debrify/services/player_display_controls.dart';
import 'package:debrify/services/profiles/tvos_profile_recovery_store.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player.dart';
import 'subtitle_apply_driver.dart';
import 'tv_episode_driver.dart' show P17ObservedErrors;

/// Phase 19 engine driver: the real screen on the shared fixture, plus the
/// tvOS release-log and display-match channels the engine reaches on tvOS.
///
/// `tvos` sets the PlatformUtil override BEFORE the screen mounts, so every
/// tvOS branch (defaults, audio list, remedy, display match, release log) is
/// taken by the original code. Diagnostics are observed where they land:
/// desktop `print` (zone capture), tvOS `debrify/tvlog` `log`.
class EngineDriver extends SubtitleApplyDriver {
  EngineDriver(
    super.t, {
    this.tvos = false,
    this.routeChannels = 0,
    super.native,
    super.configurePlayer,
  });
  final _observedErrors = P17ObservedErrors();
  @override
  List<Object> get errors => _observedErrors;
  @override
  T observe<T>(T Function() body) => runZoned(
    () => super.observe(body),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        logs.add(line);
        parent.print(zone, line);
      },
    ),
  );
  final bool tvos;
  final int routeChannels;
  final tvlog = <MethodCall>[];
  final displayMatch = <MethodCall>[];
  Object? displayMatchApplyFailure;
  Map<String, Object?> displayMatchStatus = const {'matchingEnabled': true};

  Future<void> Function()? oldCheckpoint;

  static final _wakeDrainMarker = Object();

  static const _tvlog = MethodChannel('debrify/tvlog');
  static const _match = MethodChannel('debrify/tvos_display_match');

  @override
  Future<void> initialize() async {
    await super.initialize();
    PlatformUtil.debugSetTvOS(tvos);
    // tvOS preference writes checkpoint the durable recovery envelope; the
    // host fixture has no native envelope, so the checkpoint is a no-op.
    oldCheckpoint = TvOsProfileRecoveryStore.checkpointCallback;
    if (tvos) TvOsProfileRecoveryStore.checkpointCallback = () async {};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_tvlog, (call) async {
      tvlog.add(call);
      if (call.method == 'outputChannelCount') return routeChannels;
      return null;
    });
    messenger.setMockMethodCallHandler(_match, (call) async {
      displayMatch.add(call);
      if (call.method == 'apply') {
        final failure = displayMatchApplyFailure;
        if (failure != null) throw failure;
        return displayMatchStatus;
      }
      return null;
    });
  }

  /// Every release-path decoder diagnostic, in emission order.
  List<String> get decoderLines => tvos
      ? [
          for (final call in tvlog)
            if (call.method == 'log') call.arguments as String,
        ]
      : [
          for (final line in logs)
            if (line.startsWith('DEBRIFY_PLAYER_DECODER ')) line,
        ];

  List<(String, String)> propertyWrites([FakePlayer? of]) => [
    for (final c in ((of ?? player).platform! as FakeNativePlayer).calls)
      if (c.$1 == 'setProperty') c.$2 as (String, String),
  ];

  List<String> propertyReads([FakePlayer? of]) => [
    for (final c in ((of ?? player).platform! as FakeNativePlayer).calls)
      if (c.$1 == 'getProperty') c.$2 as String,
  ];

  @override
  Future<void> close() async {
    try {
      await super.close();
      // Leave the shared wakelock queue's cursor in the isolate's real zone
      // (PipLifecycleDriver.flushWake): a FakeAsync cursor from this case
      // would stall later suites in the same isolate.
      late Future<void> pending;
      await t.runAsync(() async {
        pending = PlayerDisplayControls.instance.setWakelockOwner(
          _wakeDrainMarker,
          false,
        );
      });
      await f.finish<void>(t, pending);
    } finally {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_tvlog, null);
      messenger.setMockMethodCallHandler(_match, null);
      PlatformUtil.debugSetTvOS(false);
      TvOsProfileRecoveryStore.checkpointCallback = oldCheckpoint;
    }
  }
}
