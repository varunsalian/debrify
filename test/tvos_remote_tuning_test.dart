import 'package:debrify/services/tvos_remote_tuning.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tvos/flutter_tvos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const buttonChannel = MethodChannel('flutter/tv_remote', JSONMethodCodec());
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(buttonChannel, null);
    TvRemoteController.instance.debugReset();
    TvRemoteController.debugForceTvosForTesting = false;
    PlatformUtil.debugSetTvOS(null);
  });

  test('Siri Remote tuning stays deliberately calmer than engine defaults', () {
    final config = TvosRemoteTuning.config;

    expect(config.shortSwipeThreshold, 0.45);
    expect(config.fastSwipeThreshold, 0.70);
    expect(config.dpadDeadZone, 0.72);
    expect(config.continuousSwipeMoveThreshold, 6);
    expect(config.keyRepeatInitialDelay, const Duration(milliseconds: 500));
    expect(config.keyRepeatInterval, const Duration(milliseconds: 140));
  });

  test(
    'install sends the complete tuning contract to the tvOS engine',
    () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(buttonChannel, (call) async {
        received = call;
        return null;
      });
      PlatformUtil.debugSetTvOS(true);
      TvRemoteController.debugForceTvosForTesting = true;

      TvosRemoteTuning.install();
      await Future<void>.delayed(Duration.zero);

      expect(received?.method, 'configure');
      expect(received?.arguments, <String, Object>{
        'shortSwipeThreshold': 0.45,
        'fastSwipeThreshold': 0.70,
        'dpadDeadZone': 0.72,
        'continuousSwipeMoveThreshold': 6,
        'keyRepeatInitialDelayMs': 500,
        'keyRepeatIntervalMs': 140,
      });
    },
  );

  test('install does not touch the remote channel off tvOS', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(buttonChannel, (_) async {
      calls++;
      return null;
    });
    PlatformUtil.debugSetTvOS(false);
    TvRemoteController.debugForceTvosForTesting = true;

    TvosRemoteTuning.install();
    await Future<void>.delayed(Duration.zero);

    expect(calls, 0);
  });
}
