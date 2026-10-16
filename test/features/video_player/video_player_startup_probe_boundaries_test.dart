import 'dart:async';

import 'package:debrify/models/torrent.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/startup_driver.dart';

void main() {
  testWidgets(
    'P16 VOD subscribes before setup, ignores pre-arm errors, retains evidence and accepts before open acknowledgement',
    (t) async {
      final d = StartupDriver(t, native: true);
      await d.initialize();
      final a = startupSource('armed');
      d.prearm = Completer<void>();
      final ack = d.openGates[a.directUrl!] = Completer<void>();
      try {
        await d.begin(d.screen(sources: [a]));
        await d.f.until(t, () => d.prearmEntered);
        expect(d.probeSubscriptions.map((s) => s.channel), [
          'error',
          'width',
          'position',
          'duration',
          'buffer',
        ]);
        expect(d.opens, isEmpty);
        d.player.emit('error', 'old source error before authorization');
        d.player.emit<int?>('width', 1280);
        d.player.emit('position', const Duration(milliseconds: 80));
        await d.tick();
        expect(d.event('candidate_result'), isEmpty);
        expect(d.commits, isEmpty);
        d.prearm!.complete();
        await d.openEntered();
        expect(ack.isCompleted, isFalse);
        expect(
          d.event('candidate_result'),
          isEmpty,
          reason: 'Arming itself does not re-evaluate retained samples',
        );
        d.player.emit('duration', Duration.zero);
        await d.result();
        expect(
          d.event('candidate_result').singleOrNull,
          contains('ok=true reason=decoded_video'),
        );
        expect(d.commits, isEmpty);
        expect(d.activeProbes, hasLength(5));
        await d.tick(const Duration(seconds: 13));
        expect(
          d.commits,
          isEmpty,
          reason: 'Probe timeout does not bound the open await',
        );
        expect(d.activeProbes, hasLength(5));
        ack.complete();
        await d.committed();
        expect(d.activeProbes, isEmpty);
        expect(
          d.trace.indexOf('pre-arm'),
          greaterThan(d.trace.indexOf('subscribe:vod:buffer')),
        );
        expect(
          d.trace.indexOf('native-open:${a.directUrl}'),
          greaterThan(d.trace.indexOf('setup-complete')),
        );
        expect(
          d.trace.indexOf('caller-commit:armed'),
          greaterThan(d.trace.indexOf('open-ack:${a.directUrl}')),
        );
        d.frame();
        await d.settle();
      } finally {
        await d.close();
      }
    },
  );

  for (final route in ['duration', 'width', 'position']) {
    testWidgets(
      'P16 debrid accepts $route while setup is held but keeps the open await and subscriptions',
      (t) async {
        final d = StartupDriver(t, native: true);
        await d.initialize();
        final a = startupSource('unarmed-$route', type: StreamType.torrent);
        d.prearm = Completer<void>();
        final ack = d.openGates[a.directUrl!] = Completer<void>();
        try {
          await d.begin(d.screen(sources: [a]));
          await d.f.until(t, () => d.prearmEntered);
          expect(d.probeSubscriptions.map((s) => s.channel), [
            'error',
            'duration',
            'width',
            'position',
            'buffer',
          ]);
          d.player.emit('duration', Duration.zero);
          d.player.emit<int?>('width', 0);
          d.player.emit('position', Duration.zero);
          await d.tick();
          expect(d.event('candidate_result'), isEmpty);
          if (route == 'duration') {
            d.player.emit('duration', const Duration(milliseconds: 1));
          } else if (route == 'width') {
            d.player.state = d.player.state.copyWith(
              position: const Duration(milliseconds: 1),
            );
            d.player.emit<int?>('width', 1);
          } else {
            d.player.state = d.player.state.copyWith(width: 1);
            d.player.emit('position', const Duration(milliseconds: 1));
          }
          await d.result();
          expect(
            d.event('candidate_result').singleOrNull,
            contains(
              route == 'duration'
                  ? 'ok=true reason=duration_known'
                  : 'ok=true reason=decoded_video',
            ),
          );
          expect(d.opens, isEmpty);
          expect(d.commits, isEmpty);
          d.prearm!.complete();
          await d.openEntered();
          expect(d.activeProbes, hasLength(5));
          expect(d.commits, isEmpty);
          ack.complete();
          await d.committed();
          expect(d.commits, [a]);
          expect(d.activeProbes, isEmpty);
          d.frame();
          await d.settle();
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final kind in [
    'width first',
    'position first',
    'null width',
    'negative clock',
  ]) {
    testWidgets('P16 VOD requires decoded width and positive clock: $kind', (
      t,
    ) async {
      final d = StartupDriver(t);
      await d.initialize();
      final a = startupSource('decode');
      try {
        await d.begin(d.screen(sources: [a]));
        await d.openEntered();
        if (kind == 'width first') {
          d.player.emit<int?>('width', 1280);
        } else if (kind == 'position first') {
          d.player.emit('position', const Duration(milliseconds: 80));
        } else if (kind == 'null width') {
          d.player.emit<int?>('width', null);
          d.player.emit('position', const Duration(milliseconds: 80));
        } else {
          d.player.emit<int?>('width', 1280);
          d.player.emit('position', const Duration(milliseconds: -1));
        }
        await d.tick();
        expect(d.commits, isEmpty);
        expect(d.event('candidate_result'), isEmpty);
        d.frame();
        await d.committed();
        expect(
          d.event('candidate_result').singleOrNull,
          contains('ok=true reason=decoded_video'),
        );
        expect(d.activeProbes, isEmpty);
      } finally {
        await d.close();
      }
    });
  }

  for (final debrid in [false, true]) {
    testWidgets(
      'P16 ${debrid ? 'debrid' : 'VOD'} acknowledgement that never completes keeps the continuation pending through disposal',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        final a = startupSource(
          'never-ack',
          type: debrid ? StreamType.torrent : StreamType.directUrl,
        );
        final ack = d.openGates[a.directUrl!] = Completer<void>();
        try {
          await d.begin(d.screen(sources: [a]));
          await d.openEntered();
          d.frame();
          await d.result();
          await d.tick(const Duration(seconds: 13));
          expect(d.commits, isEmpty);
          expect(d.activeProbes, hasLength(5));
          expect(ack.isCompleted, isFalse);
          await t.pumpWidget(const SizedBox.shrink());
          await d.f.until(t, () => d.player.disposed.isCompleted);
          expect(
            d.activeProbes,
            hasLength(5),
            reason:
                'The original has no cancellation of the pending open Future',
          );
          ack.complete();
          await d.f.until(t, () => d.activeProbes.isEmpty);
          expect(
            d.commits,
            isEmpty,
            reason: 'The ladder returns before committing after disposal',
          );
          expect(d.event('commit'), isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final debrid in [false, true]) {
    testWidgets(
      'P16 ${debrid ? 'debrid' : 'VOD'} open throw is redacted, stopped and unsubscribed',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        final a = startupSource(
          'secret-token',
          type: debrid ? StreamType.torrent : StreamType.directUrl,
        );
        d.openFailures[a.directUrl!] = StateError(
          'signed secret URL ${a.directUrl}',
        );
        try {
          await d.begin(d.screen(sources: [a]));
          await d.result();
          await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'stop'));
          expect(
            d.event('open_exception').singleOrNull,
            contains('exception=StateError'),
          );
          expect(
            d.event('open_exception').singleOrNull,
            isNot(contains(a.directUrl!)),
          );
          expect(
            d.event('open_exception').singleOrNull,
            isNot(contains('signed secret')),
          );
          expect(
            d.event('candidate_result').singleOrNull,
            contains('ok=false reason=open_exception'),
          );
          expect(d.activeProbes, isEmpty);
          expect(d.commits, isEmpty);
          d.player.emit('error', 'late error after cancellation');
          d.frame();
          await d.tick();
          expect(d.event('candidate_result'), hasLength(1));
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P16 width alone completes previously sampled duration and position before open acknowledgement',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      final a = startupSource('width-last');
      final ack = d.openGates[a.directUrl!] = Completer<void>();
      try {
        await d.begin(d.screen(sources: [a]));
        await d.openEntered();
        d.player.emit('duration', const Duration(minutes: 20));
        d.player.emit('position', const Duration(milliseconds: 80));
        await d.tick();
        expect(d.event('candidate_result'), isEmpty);
        expect(d.commits, isEmpty);
        d.player.state = d.player.state.copyWith(width: 1280);
        d.player.emit<int?>('width', 1280);
        await d.result();
        expect(
          d.event('candidate_result').singleOrNull,
          contains('ok=true reason=decoded_video'),
        );
        expect(ack.isCompleted, isFalse);
        expect(d.commits, isEmpty);
        ack.complete();
        await d.committed();
        expect(d.commits, [a]);
        d.frame();
      } finally {
        ack.completeIfPending();
        await d.close();
      }
    },
  );
}
