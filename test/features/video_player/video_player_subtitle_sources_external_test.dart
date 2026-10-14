import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';
import 'support/subtitle_apply_driver.dart';
import 'video_player_subtitle_apply_boundaries_test.dart'
    show boundaryScreen, crossBoundary;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

const oldAddonTracks = [
  ...applyTracks,
  mk.SubtitleTrack(
    '8',
    'Old addon A',
    'eng',
    external: true,
    externalFilename: '/fixture/stremio_sub_old_a.srt',
  ),
  mk.SubtitleTrack(
    '9',
    'Old addon B',
    'eng',
    external: true,
    externalFilename: '/fixture/stremio_sub_old_b.srt',
  ),
  mk.SubtitleTrack(
    '10',
    'Local sidecar',
    'eng',
    external: true,
    externalFilename: '/fixture/local.srt',
  ),
];
List<List<String>> removals(FakeNativePlayer native) => [
  for (final c in native.calls)
    if (c.$1 == 'command' && (c.$2 as List<String>).first == 'sub-remove')
      c.$2 as List<String>,
];

void main() {
  for (final variant in [
    'success',
    'apply failure',
    'remove failure',
    'nonnative',
  ]) {
    testWidgets(
      'subtitle external replacement $variant loads before retiring only captured addon ids',
      (t) async {
        final d = SubtitleApplyDriver(t, native: variant != 'nonnative');
        await d.initialize();
        try {
          await d.mount();
          d.publish(tracks: oldAddonTracks);
          final panel = await d.menu();
          final order = <String>[];
          d.player.beforeOperation = (name, value) {
            if (name == 'subtitle') {
              order.add('apply:${(value as mk.SubtitleTrack).uri}');
            }
          };
          if (variant != 'nonnative') {
            d.native.beforeOperation = (name, value) {
              if (name == 'command' &&
                  (value as List<String>).first == 'sub-remove') {
                order.add('remove:${value[1]}');
                if (variant == 'remove failure' && value[1] == '8') {
                  throw StateError('remove refused');
                }
              }
            };
          }
          if (variant == 'apply failure') {
            d.player.failures['subtitle'] = StateError('load refused');
          }
          final id = 'replacement-${variant.replaceAll(' ', '-')}';
          final applied = await d.addon(id, panel: panel);
          expect(order, isNotEmpty);
          expect(order.first, 'apply:true');
          expect(applied, variant != 'apply failure');
          if (variant == 'apply failure') {
            expect(order.where((s) => s.startsWith('remove:')), isEmpty);
            expect(d.player.state.track.subtitle.id, '1');
            expect(
              d.logs.where(
                (s) => s.startsWith(
                  '[SubtitleDiag] set FAILED source=addon-external requestedId=<external> error=Bad state: load refused',
                ),
              ),
              hasLength(1),
            );
          } else {
            expect(d.player.state.track.subtitle.uri, isTrue);
            expect(
              order,
              variant == 'nonnative'
                  ? ['apply:true']
                  : ['apply:true', 'remove:8', 'remove:9'],
            );
            expect((await d.saved())?['subtitleTrackId'], 'stremio:$id');
          }
          if (variant == 'remove failure') {
            expect(
              d.logs.where(
                (s) =>
                    s ==
                    'VideoPlayer: Failed to unload external subtitle 8: Bad state: remove refused',
              ),
              hasLength(1),
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
        expect(
          d.logs.where((s) => s.contains('Failed to delete temp subtitle')),
          isEmpty,
        );
      },
    );
  }
  for (final event in ['reset', 'dispose']) {
    testWidgets(
      'subtitle external cleanup held across $event never removes a reused subsequent ordinal',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        final gate = Completer<void>();
        var entered = false;
        try {
          await d.mount(screen: boundaryScreen);
          d.publish(tracks: oldAddonTracks);
          final panel = await d.menu();
          d.native.heldOperation = (name, value) =>
              name == 'command' &&
              (value as List<String>).first == 'sub-remove' &&
              !gate.isCompleted;
          d.native.beforeOperation = (name, value) async {
            if (name == 'command' &&
                (value as List<String>).first == 'sub-remove' &&
                !entered) {
              entered = true;
              await gate.future;
            }
          };
          final pending = d.startAddon('held-removal-$event', panel);
          var completed = false;
          pending.then((_) => completed = true);
          await d.f.until(t, () => entered);
          expect(completed, isFalse);
          expect(removals(d.native), [
            ['sub-remove', '8'],
          ]);
          await crossBoundary(d, event);
          if (event == 'reset') {
            d.publish(tracks: oldAddonTracks);
          }
          expect(completed, isFalse);
          gate.complete();
          expect(await d.f.finish(t, pending), isFalse);
          expect(removals(d.native), [
            ['sub-remove', '8'],
          ]);
          expect(
            d.logs.where(
              (s) =>
                  s ==
                  'VideoPlayer: Content changed during addon subtitle cleanup; stopping before track 9',
            ),
            hasLength(1),
          );
          expect(d.errors, isEmpty);
        } finally {
          if (!gate.isCompleted) {
            gate.complete();
          }
          await removeFixture(d);
        }
      },
    );
  }
}
