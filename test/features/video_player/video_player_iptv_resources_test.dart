import 'package:flutter/services.dart';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'support/iptv_workflow_driver.dart';
import 'support/local_completion_driver.dart';

void main() {
  testWidgets(
    'P15 disposal cancels banner hide ticker and last-live settle at their original sites',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final a = [iptvChannel(0), iptvChannel(1)];
      try {
        await d.mount(a);
        await d.advance(const Duration(seconds: 6));
        await d.zap(1);
        final hide = d.timed
            .where((v) => v.$1 == const Duration(milliseconds: 4500))
            .map((v) => v.$2)
            .toList();
        final ticks = d.periodic
            .where((v) => v.$1 == const Duration(seconds: 1))
            .map((v) => v.$2)
            .toList();
        final last = d.timed
            .where((v) => v.$1 == const Duration(seconds: 1))
            .map((v) => v.$2)
            .toList();
        expect(hide.any((v) => v.isActive), true);
        expect(ticks.any((v) => v.isActive), true);
        expect(last.any((v) => v.isActive), true);
        await d.retire();
        expect(hide.every((v) => !v.isActive), true);
        expect(ticks.every((v) => !v.isActive), true);
        expect(last.every((v) => !v.isActive), true);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 direct retune held at recording stop is stranded by a real zap',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final a = [iptvChannel(0), iptvChannel(1)];
      final held = CompletionDelivery('performIptvLiveRetune', (v) => v == null)
        ..armed = false;
      try {
        await held.run(() => d.mount(a));
        held.armed = true;
        d.player.emit('error', 'connection lost');
        await d.f.until(t, () => held.pending.isNotEmpty);
        expect(d.opened.length, 1);
        await d.pick(a, 1);
        expect(d.playingUrl, a[1].url);
        held.release();
        await d.settle();
        expect(d.opened.length, 2);
        expect(d.playingUrl, a[1].url);
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close();
      }
    },
  );
  testWidgets(
    'P15 composite channel directory guide cancels the floating IPTV banner timer',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      final live = iptvChannel(0);
      try {
        await d.observe(
          () => d.f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: live.url,
              title: live.name,
              iptvChannels: [live],
              channelDirectory: [
                {'id': 'c', 'name': 'Composite', 'channelNumber': 1},
              ],
              requestChannelById: (id) async => null,
            ),
          ),
        );
        await d.f.until(
          t,
          () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
        );
        final hide = d.timed
            .lastWhere((v) => v.$1 == const Duration(milliseconds: 4500))
            .$2;
        expect(hide.isActive, true);
        await d.f.key(t, LogicalKeyboardKey.keyG);
        expect(find.byType(ChannelGuide), findsOneWidget);
        expect(hide.isActive, false);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
