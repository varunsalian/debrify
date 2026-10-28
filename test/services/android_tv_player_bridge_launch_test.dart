import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const player = MethodChannel('com.debrify.app/android_tv_player');
  const recovery = MethodChannel('debrify/tv_playback_recovery');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({
      // Non-standard presets make the launch read every tuning value.
      'network_connect_patience': 'patient',
      'network_buffer_size': 'large',
    });
    AndroidTvPlayerBridge.debugLaunchOnAndroid = true;
  });
  tearDown(() {
    AndroidTvPlayerBridge.debugLaunchOnAndroid = null;
    messenger.setMockMethodCallHandler(player, null);
    messenger.setMockMethodCallHandler(recovery, null);
    ProfileRuntime.debugReset();
  });

  test(
    'a launch retired at any step is never logged as a tuning failure',
    () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = original);
      var launches = 0;
      messenger.setMockMethodCallHandler(recovery, (call) async => 7);
      messenger.setMockMethodCallHandler(player, (call) async {
        if (call.method == 'launchTorrentPlayback') launches++;
        return true;
      });
      // Retire the launch at each successive guard check until it reaches the
      // native call, covering every await of the launch preparation.
      for (var stopAt = 1; stopAt < 40 && launches == 0; stopAt++) {
        var checks = 0;
        final launched = await AndroidTvPlayerBridge.launchTorrentPlayback(
          payload: const {'title': 'Fixture'},
          canContinue: () => ++checks < stopAt,
        );
        if (launches == 0) expect(launched, isFalse, reason: 'stop at $stopAt');
      }
      expect(launches, 1, reason: 'the unretired launch still reaches native');
      expect(
        logs.where((line) => line.contains('network tuning read failed')),
        isEmpty,
      );
    },
  );
}
