import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mdblist_capability_reads.dart';
import 'support/player_actions.dart';
import 'support/secondary_policy_reads.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  TraktTestTransport.install();
  for (final variant in ['late-close', 'early-close', 'late-release']) {
    final lateCapability = variant != 'early-close';
    testWidgets(
      'MDBList ${lateCapability ? 'late capability' : 'live seek and duration edge'} during manual validation keeps its original checkpoint at $variant',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final reads = MdblistCapabilityReads();
        final opening = Completer<void>();
        final oldPrint = debugPrint;
        final logs = <String>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        final a = source('Original', 'https://player.test/md-validation-a.mp4');
        final b = source('Incoming', 'https://player.test/md-validation-b.mp4');
        try {
          final screen = VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'MDBList validation fixture',
            contentImdbId: 'tt5100000',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            mdblistScrobble: true,
            stremioSources: [a, b],
            resolveStremioSource: (s) async => s.directUrl,
          );
          if (lateCapability) {
            await d.observe(() => reads.run(() => f.mount(t, screen)));
            await f.until(t, () => reads.pending.isNotEmpty);
            expect(d.forTracker('mdblist'), isEmpty);
            expect(d.heartbeats, isEmpty);
          } else {
            await d.mount(screen);
            await d.waitCheckpoint('mdblist', 1);
            d.expectCheckpoint('mdblist', 0, 'pause', 0.01);
            await d.position(300000);
          }
          f.player.delays['open'] = opening;
          playerControls(t).onShowStremioSources!();
          await f.advance(t, const Duration(milliseconds: 300));
          d.observe(
            () => t
                .widget<SourceSheet>(find.byType(SourceSheet))
                .onSourceSelected(1, b.directUrl!),
          );
          await f.until(
            t,
            () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
          );
          f.player.emit('playing', true);
          if (lateCapability) {
            f.player.emit('position', const Duration(milliseconds: 300000));
            await d.drain();
            reads.release();
            await d.drain();
            if (variant == 'late-close') {
              f.player.emit('duration', Duration.zero);
              await d.drain();
              f.player.emit('duration', const Duration(minutes: 20));
              await d.drain();
            }
            expect(d.forTracker('mdblist'), isEmpty);
            expect(d.heartbeats, isEmpty);
          } else {
            f.player.emit('position', const Duration(milliseconds: 959000));
            f.player.emit('duration', Duration.zero);
            await d.drain();
            f.player.emit('duration', const Duration(minutes: 20));
            await d.drain();
            await f.key(t, LogicalKeyboardKey.mediaFastForward);
            await d.drain();
            expect(d.seeks.last, const Duration(milliseconds: 969000));
            expect(d.forTracker('mdblist'), hasLength(1));
          }
          if (variant == 'late-release') {
            opening.complete();
            f.player.delays.remove('open');
            await d.drain();
            await d.waitCheckpoint('mdblist', 1);
            d.expectCheckpoint('mdblist', 0, 'pause', 0.01);
            expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
            await d.retired();
            expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
            return;
          }
          await d.retired();
          final count = lateCapability ? 1 : 2;
          await d.waitCheckpoint('mdblist', count);
          d.expectCheckpoint('mdblist', count - 1, 'pause', 25);
          expect(
            logs.where((line) => line.startsWith('[MDBListDiag] player stop ')),
            isEmpty,
            reason:
                'The gated stop returns before its diagnostic; close still runs',
          );
          expect(d.heartbeats.where((timer) => timer.isActive), isEmpty);
          opening.complete();
          f.player.delays.remove('open');
          await d.drain();
          expect(d.forTracker('mdblist'), hasLength(count));
        } finally {
          reads.release();
          if (!opening.isCompleted) opening.complete();
          f.player.delays.remove('open');
          debugPrint = oldPrint;
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'MDBList capability finishing paused allocates without starting until the real playing edge',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final reads = MdblistCapabilityReads();
      try {
        await d.observe(
          () => reads.run(() => f.mount(t, secondaryScreen(simkl: false))),
        );
        await f.until(t, () => reads.pending.isNotEmpty);
        await d.playing(false);
        reads.release();
        await d.drain();
        expect(d.forTracker('mdblist'), isEmpty);
        expect(d.heartbeats, isEmpty);
        await d.playing(true);
        await d.waitCheckpoint('mdblist', 1);
        d.expectCheckpoint('mdblist', 0, 'pause', 0.01);
        expect(d.heartbeats.where((timer) => timer.isActive), hasLength(1));
      } finally {
        reads.release();
        await d.close();
      }
    },
  );

  testWidgets(
    'MDBList disposal after successful player setup but before policy delivery returns before capability diagnostics',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final reads = MdblistPolicyReads();
      final oldPrint = debugPrint;
      final logs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await d.observe(
          () => reads.run(() => f.mount(t, secondaryScreen(simkl: false))),
        );
        await f.until(t, () => reads.pending.isNotEmpty);
        expect(f.player.readyDelivered, isTrue);
        expect(f.player.state.duration, const Duration(minutes: 20));
        expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(1));
        expect(d.forTracker('mdblist'), isEmpty);
        await d.retired();
        reads.release();
        await d.drain();
        expect(
          logs,
          isNot(
            contains('[MDBListDiag] player init abandoned: player unmounted'),
          ),
        );
        expect(d.forTracker('mdblist'), isEmpty);
        expect(d.heartbeats, isEmpty);
      } finally {
        reads.release();
        debugPrint = oldPrint;
        await d.close();
      }
    },
  );
}
