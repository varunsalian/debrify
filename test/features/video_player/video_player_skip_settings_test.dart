import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved interface; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/skip_segment_driver.dart';
import 'support/skip_settings_reads.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'skip unloaded settings start no request and disposed settings completion creates no provider',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      final oldStore = SharedPreferencesStorePlatform.instance;
      SkipSettingsReads? reads;
      try {
        await d.configure();
        reads = await t.runAsync(SkipSettingsReads.install);
        await t.pumpWidget(MaterialApp(home: skipScreen()));
        await f.until(t, () => reads!.entered);
        expect(d.requests, isEmpty);
        expect(f.network.pendingByClient, isEmpty);
        expect(f.creationOrder, contains('media-kit-init'));
        await t.pumpWidget(const SizedBox.shrink());
        reads!.release.complete();
        for (var i = 0; i < 20; i++) {
          await f.advance(t, const Duration(milliseconds: 100));
        }
        expect(d.requests, isEmpty);
        expect(
          f.network.pendingByClient,
          isEmpty,
          reason: 'disposed async settings load must not construct a provider',
        );
      } finally {
        if (reads != null && !reads.release.isCompleted) {
          reads.release.complete();
        }
        await f.close(t);
        SharedPreferencesStorePlatform.instance = oldStore;
      }
    },
  );

  testWidgets(
    'skip configured single-provider choice reaches IntroDB rather than auto or SkipDB',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(provider: 'introdb');
        await f.mount(t, skipScreen());
        expect(d.requests, isEmpty);
        final requests = f.network.requests
            .where((r) => r.url.host == 'api.introdb.app')
            .toList();
        expect(requests, hasLength(1));
        expect(requests.single.url.queryParameters, {
          'imdb_id': 'tt4100000',
          'season': '2',
          'episode': '3',
        });
        await d.tick();
        d.expectButton(false);
        expect(
          f.network.requests.where((r) => r.url.host == 'api.introdb.app'),
          hasLength(1),
        );
      } finally {
        await f.close(t);
      }
    },
  );
}
