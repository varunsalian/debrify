import 'package:debrify/services/pip_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.debrify.app/pip');
  final calls = <MethodCall>[];
  setUp(() {
    PipService.resetForTesting();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'isSupported' || call.method == 'enterPip'
              ? true
              : null;
        });
  });
  tearDown(() {
    PipService.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<dynamic> event(String method, Object args) async {
    dynamic result;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (response) {
            result = const StandardMethodCodec().decodeEnvelope(response!);
          },
        );
    return result;
  }

  test('Android retains its aspect and action protocol', () async {
    PipService.debugPlatform = TargetPlatform.android;
    expect(await PipService.resolveSupport(), isTrue);
    final owner = Object();
    final actions = <String>[];
    PipService.attach(owner, onMode: (_) {}, onAction: actions.add);
    expect(
      await PipService.enterPip(aspectWidth: 1920, aspectHeight: 1080),
      isTrue,
    );
    expect(calls.last.arguments, {'aspectWidth': 1920, 'aspectHeight': 1080});
    await event('onPipAction', 'next');
    expect(actions, ['next']);
    PipService.detach(owner);
    await Future<void>.delayed(Duration.zero);
    expect(calls.where((c) => c.method == 'detach'), isEmpty);
  });

  test('iOS sends player identity and timeline', () async {
    PipService.debugPlatform = TargetPlatform.iOS;
    expect(await PipService.resolveSupport(), isTrue);
    PipService.attach(Object(), onMode: (_) {}, onAction: (_) {});
    await PipService.enterPip(playerHandle: 123);
    expect(calls.last.arguments['playerHandle'], '123');
    await PipService.updatePlaybackState(
      isPlaying: true,
      hasNext: false,
      positionMs: 12000,
      durationMs: 60000,
    );
    expect(calls.last.arguments['positionMs'], 12000);
    expect(calls.last.arguments['durationMs'], 60000);
  });

  test('late iOS callbacks cannot control a newer player', () async {
    PipService.debugPlatform = TargetPlatform.iOS;
    await PipService.resolveSupport();
    final first = Object();
    final second = Object();
    final actions = <String>[];
    PipService.attach(first, onMode: (_) {}, onAction: (_) {});
    await PipService.enterPip(playerHandle: 1);
    PipService.attach(second, onMode: (_) {}, onAction: actions.add);
    await PipService.enterPip(playerHandle: 2);
    await event('onPipAction', {'playerHandle': '1', 'value': 'pause'});
    expect(actions, isEmpty);
    await event('onPipAction', {'playerHandle': '2', 'value': 'play'});
    expect(actions, ['play']);
    PipService.detach(first);
    expect(PipService.isOwner(second), isTrue);
    PipService.detach(second);
    await event('onPipAction', {'playerHandle': '2', 'value': 'pause'});
    expect(actions, ['play']);
  });

  test('unsupported platforms never call the native channel', () async {
    PipService.debugPlatform = TargetPlatform.linux;
    expect(await PipService.resolveSupport(), isFalse);
    expect(await PipService.enterPip(), isFalse);
    expect(calls, isEmpty);
  });

  test('iOS restoration acknowledges the current owner only', () async {
    PipService.debugPlatform = TargetPlatform.iOS;
    await PipService.resolveSupport();
    var restores = 0;
    final owner = Object();
    PipService.attach(
      owner,
      onMode: (_) {},
      onAction: (_) {},
      onRestore: () async {
        restores++;
        return true;
      },
    );
    await PipService.enterPip(playerHandle: 123);
    expect(
      await event('onPipRestore', {'playerHandle': '123', 'value': true}),
      isTrue,
    );
    expect(
      await event('onPipRestore', {'playerHandle': 'old', 'value': true}),
      isNull,
    );
    expect(restores, 1);
    PipService.detach(owner);
    await event('onPipRestore', {'playerHandle': '123', 'value': true});
    expect(restores, 1);
  });
}
