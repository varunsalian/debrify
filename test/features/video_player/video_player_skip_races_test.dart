import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/skip_segment_driver.dart';
import 'support/video_player_environment.dart';

Future<void> incomingProfile(WidgetTester t, VideoPlayerEnvironment f) async {
  final scope = ProfileRuntime.capture();
  final actor = await f.finish(t, f.registry!.getProfile(scope.profileId));
  final profile = await f.finish(
    t,
    f.registry!.createProfile(
      name: 'Incoming skip profile',
      role: UserProfileRole.admin,
      actingProfileId: scope.profileId,
      actingAuthorizationRevision: actor!.authorizationRevision,
      actingSessionEpoch: scope.sessionEpoch,
    ),
  );
  await f.finish(t, f.registry!.setActiveProfile(profile.id));
  ProfileRuntime.publish(
    ProfileScope(
      profileId: profile.id,
      dataGeneration: 1,
      sessionEpoch: ProfileRuntime.nextEpoch,
    ),
  );
  ProfilePolicyGuard.updateActiveProfile(profile);
  // Mirror the existing handoff's cache invalidation before the incoming route.
  SubtitleSettingsService.instance.resetProfileScope();
  SubtitleFontService.instance.resetProfileScope();
}

void main() {
  testWidgets('skip cache returns episode-duration key without another fetch', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    final d = SkipSegmentDriver(t, f);
    try {
      await d.configure(hold: true);
      await f.mount(t, skipScreen());
      await d.release(0);
      await d.tick();
      d.expectButton(true);
      await d.duration(const Duration(seconds: 1000));
      expect(d.requests, hasLength(2));
      d.expectButton(false);
      await d.release(1, reply: skipReply(start: 40, end: 60));
      await d.tick(45);
      d.expectButton(true);
      await d.duration(const Duration(seconds: 1200));
      d.expectButton(false);
      await d.tick();
      d.expectButton(true);
      expect(d.requests, hasLength(2));
    } finally {
      d.releaseAll();
      await f.close(t);
    }
  });

  testWidgets(
    'skip stale generation caches result without publishing wrong duration',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        await d.duration(const Duration(seconds: 1000));
        await d.tick();
        await d.release(0);
        d.expectButton(false);
        for (var tick = 0; tick < 3; tick++) {
          await d.tick();
        }
        expect(d.requests, hasLength(2));
        await d.release(1, reply: skipReply(start: 40, end: 60));
        d.expectButton(false);
        await d.tick(45);
        d.expectButton(true);
        await d.duration(const Duration(seconds: 1200));
        await d.tick();
        d.expectButton(true);
        expect(d.requests, hasLength(2));
      } finally {
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  for (final error in [false, true]) {
    testWidgets(
      'skip held A-B-A old ${error ? 'error' : 'success'} caches and clears same-key loading before generation rejection',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final d = SkipSegmentDriver(t, f);
        final logs = <String>[];
        final oldPrint = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) logs.add(message);
        };
        try {
          await d.configure(hold: true);
          await f.mount(t, skipScreen());
          await d.duration(const Duration(seconds: 1000));
          await d.duration(const Duration(seconds: 1200));
          expect(d.requests, hasLength(3));
          expect(d.requests[0].url, d.requests[2].url);
          await d.tick();
          await d.release(0, error: error ? StateError('held old A') : null);
          d.expectButton(false);
          await d.tick();
          d.expectButton(!error);
          expect(
            d.requests,
            hasLength(3),
            reason:
                'old completion populates cache and clears newer same-key loading',
          );
          if (error) {
            expect(
              logs,
              contains(
                'SkipSegments: SkipDB fetch failed: Bad state: held old A',
              ),
            );
          }
          await d.release(2, reply: skipReply(start: 40, end: 60));
          d.expectButton(false);
          await d.tick(45);
          d.expectButton(true);
          await d.release(1);
          d.expectButton(true);
          expect(d.requests, hasLength(3));
        } finally {
          debugPrint = oldPrint;
          d.releaseAll();
          await f.close(t);
        }
      },
    );
  }

  testWidgets(
    'skip failed fetch caches empty and logs once without retrying ticks',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      final logs = <String>[];
      final oldPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        await d.release(0, error: StateError('skip offline'));
        for (var i = 0; i < 3; i++) {
          await d.tick();
        }
        d.expectButton(false);
        expect(d.requests, hasLength(1));
        expect(
          logs.where(
            (s) =>
                s ==
                'SkipSegments: SkipDB fetch failed: Bad state: skip offline',
          ),
          hasLength(1),
        );
        await d.duration(const Duration(seconds: 1000));
        await d.release(1);
        await d.tick();
        d.expectButton(true);
        await d.duration(const Duration(seconds: 1200));
        d.expectButton(false);
        expect(d.requests, hasLength(2));
      } finally {
        debugPrint = oldPrint;
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  for (final error in [false, true]) {
    testWidgets(
      'skip current cached A stays visible when held B completes with ${error ? 'error' : 'success'} in the same generation',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final d = SkipSegmentDriver(t, f);
        try {
          await d.configure(hold: true);
          await f.mount(t, skipScreen());
          await d.release(0);
          await d.tick();
          d.expectButton(true);
          await d.duration(const Duration(seconds: 1000));
          d.expectButton(false);
          await d.duration(const Duration(seconds: 1200));
          d.expectButton(true);
          await d.release(
            1,
            reply: skipReply(start: 40, end: 60),
            error: error ? StateError('held B') : null,
          );
          d.expectButton(true);
          expect(d.requests, hasLength(2));
          await d.tick();
          d.expectButton(true);
        } finally {
          d.releaseAll();
          await f.close(t);
        }
      },
    );
  }

  testWidgets(
    'skip failed changed-key fetch clears previously loaded segments',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        await d.release(0);
        await d.tick();
        d.expectButton(true);
        await d.duration(const Duration(seconds: 1000));
        d.expectButton(false);
        await d.release(1, error: StateError('new key offline'));
        d.expectButton(false);
        await d.tick();
        d.expectButton(false);
        expect(d.requests, hasLength(2));
      } finally {
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip provider closes on disposal and late success cannot publish',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        final before = f.network.closedClients.length;
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        expect(f.network.closedClients.length, before + 1);
        await d.release(0);
        d.expectButton(false);
        expect(t.takeException(), isNull);
      } finally {
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip close-aborted fetch logs once without publishing or uncaught errors',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      final logs = <String>[];
      final oldPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        f.network.abortOnClose = true;
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        await f.advance(t);
        expect(
          logs.where(
            (s) =>
                s.startsWith('SkipSegments: SkipDB fetch failed:') &&
                s.contains('fixture client closed'),
          ),
          hasLength(1),
        );
        await d.release(0);
        d.expectButton(false);
        expect(t.takeException(), isNull);
      } finally {
        debugPrint = oldPrint;
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip outgoing mounted route publishes held result after profile changes as-is',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        await d.tick();
        await incomingProfile(t, f);
        await d.release(0);
        d.expectButton(true);
        expect(d.requests, hasLength(1));
      } finally {
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip outgoing disposed route rejects held result after profile changes',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        final closed = f.network.closedClients.length;
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        expect(f.network.closedClients.length, closed + 1);
        await incomingProfile(t, f);
        await d.release(0);
        d.expectButton(false);
        expect(t.takeException(), isNull);
      } finally {
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip incoming route reads incoming disabled settings and provider independently',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        await incomingProfile(t, f);
        await d.configure(enabled: false, provider: 'introdb');
        await f.mount(t, skipScreen());
        await d.tick();
        expect(d.requests, hasLength(1));
        expect(
          f.network.requests.where((r) => r.url.host == 'api.introdb.app'),
          isEmpty,
        );
        d.expectButton(false);
        await d.release(0);
        d.expectButton(false);
      } finally {
        d.releaseAll();
        await f.close(t);
      }
    },
  );
  testWidgets(
    'skip incoming enabled profile selects IntroDB without another SkipDB request',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure();
        await f.mount(t, skipScreen());
        await d.tick();
        expect(d.requests, hasLength(1));
        d.expectButton(true);
        final outgoingRequests = d.requests.length;

        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        await incomingProfile(t, f);
        await d.configure(enabled: true, provider: 'introdb');
        await f.mount(t, skipScreen());
        await d.tick();

        final incomingRequests = f.network.requests
            .where((r) => r.url.host == 'api.introdb.app')
            .toList();
        expect(incomingRequests, hasLength(1));
        expect(incomingRequests.single.url.queryParameters, {
          'imdb_id': 'tt4100000',
          'season': '2',
          'episode': '3',
        });
        expect(d.requests, hasLength(outgoingRequests));
        d.expectButton(false);
      } finally {
        await f.close(t);
      }
    },
  );
  for (final error in [false, true]) {
    testWidgets(
      'skip held A-B-A late old ${error ? 'error' : 'success'} preserves newer UI but poisons cache as-is',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final d = SkipSegmentDriver(t, f);
        try {
          await d.configure(hold: true);
          await f.mount(t, skipScreen());
          await d.duration(const Duration(seconds: 1000));
          await d.duration(const Duration(seconds: 1200));
          await d.tick(45);
          await d.release(2, reply: skipReply(start: 40, end: 60));
          d.expectButton(true);
          await d.release(0, error: error ? StateError('late old A') : null);
          d.expectButton(true);
          await d.tick(45);
          d.expectButton(true);
          await d.release(1);
          await d.duration(const Duration(seconds: 1000));
          await d.tick();
          d.expectButton(true);
          await d.duration(const Duration(seconds: 1200));
          d.expectButton(!error);
          expect(d.requests, hasLength(3));
        } finally {
          d.releaseAll();
          await f.close(t);
        }
      },
    );
  }

  testWidgets(
    'skip held A-B-A current error remains displayed after late old success until cache return',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        await d.duration(const Duration(seconds: 1000));
        await d.duration(const Duration(seconds: 1200));
        await d.tick();
        await d.release(2, error: StateError('current A offline'));
        d.expectButton(false);
        await d.release(0);
        await d.tick();
        d.expectButton(false);
        await d.release(1);
        await d.duration(const Duration(seconds: 1000));
        d.expectButton(true);
        await d.duration(const Duration(seconds: 1200));
        d.expectButton(true);
        expect(d.requests, hasLength(3));
      } finally {
        d.releaseAll();
        await f.close(t);
      }
    },
  );
}
