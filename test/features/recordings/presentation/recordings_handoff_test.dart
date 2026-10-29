import 'dart:io';

import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/debrify_tv_handoff.dart';
import '../../../support/recordings_fixture.dart';

void main() {
  testWidgets(
    'library play observes supplied fields and every observable launch default',
    (t) async {
      await recordingsCase(t, (f) async {
        final file = await t.runAsync(
          () => f.file('Original_Title_20240301_120000.ts'),
        );
        await f.mount(t);
        await f.tap(t, find.text('Original Title'));
        await f.until(t, () => f.observer.players.isNotEmpty);
        expect(f.observer.players, hasLength(1));
        // The supplied URI, title and visible title; every other observable
        // field keeps its constructor default.
        expectDebrifyTvPlayer(f.observer.players.single, 'recordings play', {
          'videoUrl': file!.path,
          'title': 'Original Title',
          'showVideoTitle': true,
        });
        MainPageBridge.notifyContentPlaybackStopped();
      });
    },
  );

  testWidgets(
    'desktop allows preferred external player and drains return lifecycle',
    (t) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final calls = <MethodCall>[];
      final previousExternal = MainPageBridge.onExternalPlayerLaunched;
      final previousOverlay = MainPageBridge.hideAutoLaunchOverlay;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      try {
        await recordingsCase(t, (f) async {
          final file = await t.runAsync(() => f.file('External.ts'));
          await ExternalPlayerStorage.setPreferredExternalPlayer('infuse');
          await ExternalPlayerStorage.setDefaultPlayerMode('external');
          await f.mount(t);
          await f.tap(t, find.text('External'));
          await f.until(t, () => calls.isNotEmpty);
          expect(
            f.observer.players,
            isEmpty,
            reason: 'desktop external default reaches transport',
          );
          expect(calls, hasLength(1));
          final args = calls.single.arguments as Map;
          expect(
            Uri.parse(args['url'] as String).queryParameters['url'],
            file!.path,
            reason: 'desktop allows external player with unchanged entry URI',
          );
          expect(args['useSafariVC'], false);
          expect(args['useWebView'], false);
          await t.pumpWidget(const SizedBox());
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await t.pump(const Duration(seconds: 30));
          MainPageBridge.notifyContentPlaybackStopped();
        });
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        MainPageBridge.onExternalPlayerLaunched = previousExternal;
        MainPageBridge.hideAutoLaunchOverlay = previousOverlay;
      }
    },
    skip: !Platform.isMacOS,
  );
}
