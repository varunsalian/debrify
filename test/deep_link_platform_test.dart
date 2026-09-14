import 'package:debrify/services/deep_link_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const links = MethodChannel('com.llfbandit.app_links/messages');
  const linkEvents = MethodChannel('com.llfbandit.app_links/events');
  const shares = MethodChannel('flutter_sharing_intent');
  const shareEvents = MethodChannel('flutter_sharing_intent/events-sharing');
  late List<String> calls;

  setUp(() {
    calls = [];
    for (final channel in [links, linkEvents, shares, shareEvents]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add('${channel.name}:${call.method}');
        return null;
      });
    }
  });
  tearDown(() async {
    DeepLinkService().dispose();
    await Future<void>.delayed(Duration.zero);
    debugDefaultTargetPlatformOverride = null;
    for (final channel in [links, linkEvents, shares, shareEvents]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    test(
      '$platform keeps deep links without invoking mobile sharing',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        await DeepLinkService().initialize();
        await Future<void>.delayed(Duration.zero);
        expect(calls, contains('${linkEvents.name}:listen'));
        expect(
          calls.where((x) => x.startsWith('flutter_sharing_intent')),
          isEmpty,
        );
      },
    );
  }
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform retains sharing and cancels its subscription', () async {
      debugDefaultTargetPlatformOverride = platform;
      await DeepLinkService().initialize();
      await Future<void>.delayed(Duration.zero);
      expect(calls, contains('${shares.name}:getInitialSharing'));
      expect(calls, contains('${shareEvents.name}:listen'));
      DeepLinkService().dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls, contains('${shareEvents.name}:cancel'));
    });
  }
  test('desktop launch preflight skips mobile sharing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await DeepLinkService.preflightLaunchIntent();
    expect(calls, contains('${links.name}:getInitialLink'));
    expect(calls.where((x) => x.startsWith('flutter_sharing_intent')), isEmpty);
  });
}
