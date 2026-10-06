import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/playback_resume_policy.dart';
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
        final fields = debrifyTvPlayerFields(f.observer.players.single);
        expect(
          fields['videoUrl'],
          file!.path,
          reason: 'recordings handoff uses entry URI',
        );
        expect(
          fields['title'],
          'Original Title',
          reason: 'recordings handoff uses display title',
        );
        expect(
          fields['showVideoTitle'],
          true,
          reason: 'recordings handoff shows video title',
        );
        final ledger =
            jsonDecode(
                  File(
                    'dev/tool/recordings_handoff_ledger.json',
                  ).readAsStringSync(),
                )
                as Map;
        for (final item in (ledger['parameters'] as List).cast<Map>()) {
          if (item['classification'] != 'observable' ||
              item['supplied'] == true) {
            continue;
          }
          final name = item['name'] as String;
          final Object? expected = switch (item['default']) {
            null => null,
            'false' => false,
            'true' => true,
            '40' => 40,
            'PlaybackResumePolicy.sourceSpecific' =>
              PlaybackResumePolicy.sourceSpecific,
            _ => throw StateError('Unclassified launch default: $name'),
          };
          expect(
            fields,
            contains(name),
            reason: 'typed observer covers ledger field $name',
          );
          expect(
            fields[name],
            expected,
            reason: 'recordings retains observable default $name',
          );
        }
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
