import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/local_completion_driver.dart';
import 'support/subtitle_apply_driver.dart';
import 'support/vp_fixture_actions.dart';
import 'video_player_skip_races_test.dart' show incomingProfile;
import 'video_player_subtitle_apply_boundaries_test.dart'
    show crossBoundary, boundaryScreen;

const preferenceKey = 'video_subtitle_apply_original';

class ApplyWrites extends CompletionWrites {
  ApplyWrites(super.values);
  bool armed = false;
  bool fail = false;
  final pending = <({String key, Object value, Completer<void> gate})>[];
  static Future<ApplyWrites> install() async {
    final store = ApplyWrites(
      await SharedPreferencesStorePlatform.instance.getAll(),
    );
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (armed && key.endsWith('playback_state_v1')) {
      final gate = Completer<void>();
      pending.add((key: key, value: value, gate: gate));
      final task = VpFixtureActions.current!.begin(
        'subtitle physical preference write',
        held: true,
      );
      try {
        await gate.future;
      } finally {
        task.complete();
      }
      if (fail) throw StateError('subtitle preference write rejected');
    }
    return super.setValue(type, key, value);
  }

  void release(int index) => pending[index].gate.complete();
  void releaseAll() {
    armed = false;
    for (final item in pending) {
      if (!item.gate.isCompleted) item.gate.complete();
    }
  }

  Future<Map<String, dynamic>> map(ProfileScope scope) async {
    final raw = await physical(scope, 'playback_state_v1');
    return raw == null ? {} : jsonDecode(raw as String) as Map<String, dynamic>;
  }
}

void main() {
  for (final failure in [false, true]) {
    for (final event in ['same content', 'reset', 'profile', 'dispose']) {
      testWidgets(
        'subtitle rollback waits for ${failure ? 'failed' : 'successful'} optimistic persistence across $event',
        (t) async {
          final d = SubtitleApplyDriver(t);
          await d.initialize();
          final store = await t.runAsync(ApplyWrites.install);
          final outgoing = ProfileRuntime.capture();
          try {
            await d.mount(screen: boundaryScreen);
            final panel = await d.menu();
            await d.f.finish(
              t,
              PlaybackStateStore.savePlaybackStateMap({
                'unrelated': {'owner': 'A'},
              }),
            );
            store!.armed = true;
            store.fail = failure;
            var completed = false;
            final selected = d.observe(
              () => panel.onEmbeddedSubtitleSelected('2', '1'),
            );
            selected.then((_) => completed = true);
            await d.f.until(t, () => store.pending.length == 1);
            expect(completed, isFalse);
            expect(d.player.state.track.subtitle.id, '2');
            expect((await store.map(outgoing))[preferenceKey], isNull);
            d.fail();
            await d.f.until(t, () => d.player.state.track.subtitle.id == '1');
            await d.f.actions.settle(t);
            expect(d.logs.where((v) => v.contains('user notified')), isEmpty);
            expect(completed, isFalse);
            store.armed = false;
            if (event != 'same content') await crossBoundary(d, event);
            final incoming = ProfileRuntime.capture();
            if (event == 'profile') {
              store.armed = false;
              await d.f.finish(
                t,
                PlaybackStateStore.savePlaybackStateMap({
                  'unrelated': {'owner': 'B'},
                }),
              );
            }
            expect(store.pending, hasLength(1));
            store.armed = false;
            store.release(0);
            expect(await d.f.finish(t, selected), isTrue);
            await d.f.actions.settle(t);
            final a = await store.map(outgoing);
            final b = await store.map(incoming);
            expect(a['unrelated'], {'owner': 'A'});
            expect(b['unrelated'], {'owner': event == 'profile' ? 'B' : 'A'});
            expect(
              (b[preferenceKey] as Map)['trackPreferences']['subtitleTrackId'],
              '1',
            );
            if (event == 'profile') {
              expect(
                a[preferenceKey] == null
                    ? null
                    : (a[preferenceKey]
                          as Map)['trackPreferences']['subtitleTrackId'],
                failure ? null : '2',
              );
            }
            expect(
              d.logs.where((v) => v.contains('user notified')),
              hasLength(event == 'dispose' ? 0 : 1),
            );
            expect(d.errors, isEmpty);
          } finally {
            store!.releaseAll();
            await d.close();
          }
        },
      );
    }
  }
  for (final newerFirst in [false, true]) {
    testWidgets(
      'subtitle rollback awaits the newest matching completer when writes finish ${newerFirst ? 'newest first' : 'oldest first'}',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        final store = await t.runAsync(ApplyWrites.install);
        final scope = ProfileRuntime.capture();
        try {
          await d.mount();
          final panel = await d.menu();
          await d.f.finish(
            t,
            PlaybackStateStore.savePlaybackStateMap({
              'unrelated': {'owner': 'A'},
            }),
          );
          store!.armed = true;
          final first = d.observe(
            () => panel.onEmbeddedSubtitleSelected('2', '1'),
          );
          await d.f.until(t, () => store.pending.length == 1);
          final second = d.observe(() => panel.onAudioSelected('2', '2'));
          await d.f.until(t, () => store.pending.length == 2);
          d.fail();
          await d.f.until(t, () => d.player.state.track.subtitle.id == '1');
          expect(d.logs.where((v) => v.contains('user notified')), isEmpty);
          store.armed = false;
          store.release(newerFirst ? 1 : 0);
          if (newerFirst) {
            await d.f.finish(t, second);
            await d.f.until(
              t,
              () => d.logs.any((v) => v.contains('user notified')),
            );
            expect(store.pending[0].gate.isCompleted, isFalse);
            expect(
              (await store.map(scope))[preferenceKey]['trackPreferences'],
              containsPair('subtitleTrackId', '1'),
            );
          } else {
            expect(await d.f.finish(t, first), isTrue);
            await d.f.actions.settle(t);
            expect(d.logs.where((v) => v.contains('user notified')), isEmpty);
            expect(store.pending[1].gate.isCompleted, isFalse);
          }
          store.release(newerFirst ? 0 : 1);
          expect(await d.f.finish(t, first), isTrue);
          await d.f.finish(t, second);
          await d.f.actions.settle(t);
          final physical = await store.map(scope);
          expect(physical['unrelated'], {'owner': 'A'});
          expect(
            physical[preferenceKey]['trackPreferences']['subtitleTrackId'],
            newerFirst ? '2' : '1',
          );
          expect(
            physical[preferenceKey]['trackPreferences']['audioTrackId'],
            newerFirst ? '1' : '2',
          );
          expect(
            d.logs.where((v) => v.contains('user notified')),
            hasLength(1),
          );
          expect(d.errors, isEmpty);
        } finally {
          store!.releaseAll();
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'subtitle delayed preference map is written into the incoming profile as-is',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final store = await t.runAsync(ApplyWrites.install);
      final oldScope = ProfileRuntime.capture();
      final held = CompletionDelivery(
        'saveVideoTrackPreferences',
        (v) => v is Map,
      );
      try {
        await d.mount();
        final panel = await d.menu();
        await d.f.finish(
          t,
          PlaybackStateStore.savePlaybackStateMap({
            'unrelatedA': {'owner': 'A'},
          }),
        );
        final selected = held.run(
          () => d.observe(() => panel.onEmbeddedSubtitleSelected('2', '1')),
        );
        await d.f.until(t, () => held.pending.isNotEmpty);
        expect(held.pending, hasLength(1));
        expect(d.player.state.track.subtitle.id, '2');
        await incomingProfile(t, d.f);
        final newScope = ProfileRuntime.capture();
        await d.f.finish(
          t,
          PlaybackStateStore.savePlaybackStateMap({
            'unrelatedB': {'owner': 'B'},
          }),
        );
        expect((await store!.map(oldScope))[preferenceKey], isNull);
        expect((await store.map(newScope))['unrelatedB'], {'owner': 'B'});
        held.release();
        expect(await d.f.finish(t, selected), isTrue);
        final a = await store.map(oldScope);
        final b = await store.map(newScope);
        expect(a['unrelatedA'], {'owner': 'A'});
        expect(a[preferenceKey], isNull);
        expect(b['unrelatedA'], {'owner': 'A'});
        expect(b.containsKey('unrelatedB'), isFalse);
        expect(b[preferenceKey]['trackPreferences']['subtitleTrackId'], '2');
        d.fail();
        await d.rollback('1');
        expect(
          (await store.map(
            newScope,
          ))[preferenceKey]['trackPreferences']['subtitleTrackId'],
          '1',
        );
        expect((await store.map(oldScope))[preferenceKey], isNull);
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close();
      }
    },
  );
  testWidgets(
    'subtitle admitted rollback clears the active attempt before a later audio preference write',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final gate = Completer<void>();
      var entered = false;
      try {
        await d.mount();
        final panel = await d.menu();
        expect(await d.select('2', panel: panel), isTrue);
        d.native.beforeOperation = (name, value) async {
          if (!entered &&
              name == 'setProperty' &&
              value == ('sub-visibility', 'no')) {
            entered = true;
            await gate.future;
          }
        };
        d.native.heldOperation = (name, value) =>
            name == 'setProperty' &&
            value == ('sub-visibility', 'no') &&
            !gate.isCompleted;
        d.fail();
        await d.f.until(t, () => entered);
        expect(d.player.state.track.subtitle.id, '2');
        await d.f.finish(t, d.observe(() => panel.onAudioSelected('2', '2')));
        expect((await d.saved())?['audioTrackId'], '2');
        expect((await d.saved())?['subtitleTrackId'], '2');
        expect(d.logs.where((v) => v.contains('user notified')), isEmpty);
        gate.complete();
        await d.rollback('1');
        expect((await d.saved())?['audioTrackId'], '1');
        expect((await d.saved())?['subtitleTrackId'], '1');
        expect(d.player.state.track.audio.id, '2');
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        d.native.beforeOperation = null;
        d.native.heldOperation = null;
        await d.close();
      }
    },
  );
}
