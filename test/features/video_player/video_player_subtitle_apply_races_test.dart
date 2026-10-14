import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/vp_fixture_actions.dart';
import 'support/subtitle_apply_driver.dart';

class ApplyTurn {
  bool armed = true;
  final pending = <void Function()>[];
  T run<T>(T Function() action) => runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if (armed &&
            duration == const Duration(milliseconds: 50) &&
            StackTrace.current.toString().contains(
              'setSubtitleTrackWithDiagnostics',
            )) {
          armed = false;
          return parent.createTimer(
            zone,
            duration,
            () => pending.add(
              VpFixtureActions.heldCallback(
                'subtitle apply 50ms turn',
                callback,
              ),
            ),
          );
        }
        return parent.createTimer(zone, duration, callback);
      },
    ),
  );
  void release() {
    armed = false;
    final callbacks = List<void Function()>.of(pending);
    pending.clear();
    for (final callback in callbacks) {
      callback();
    }
  }
}

void main() {
  testWidgets(
    'subtitle old decoder log rolls the current accepted B attempt back as-is',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        await d.mount();
        final panel = await d.menu();
        expect(await d.select('2', panel: panel), isTrue);
        expect(await d.select('3', panel: panel), isTrue);
        d.player.calls.clear();
        d.fail(reason: 'decoder error originally belonging to A');
        await d.rollback('2');
        expect(
          d.player.calls
              .where((v) => v.$1 == 'subtitle')
              .map((v) => (v.$2 as mk.SubtitleTrack).id),
          ['2'],
        );
        expect((await d.saved())?['subtitleTrackId'], '2');
        expect(
          d.logs.where((v) => v.contains('user notified')).single,
          contains('originally belonging to A'),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'subtitle delayed A apply exception is rejected after B becomes current',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final gate = Completer<void>();
      var entered = false;
      try {
        await d.mount();
        final panel = await d.menu();
        d.player.beforeOperation = (name, value) async {
          if (name == 'subtitle' && (value as mk.SubtitleTrack).id == '2') {
            entered = true;
            await gate.future;
            throw StateError('late A exception');
          }
        };
        d.player.heldOperation = (name, value) =>
            name == 'subtitle' &&
            (value as mk.SubtitleTrack).id == '2' &&
            !gate.isCompleted;
        final a = d.observe(() => panel.onEmbeddedSubtitleSelected('2', '1'));
        await d.f.until(t, () => entered);
        expect(await d.select('3', panel: panel), isTrue);
        expect(d.player.state.track.subtitle.id, '3');
        expect((await d.saved())?['subtitleTrackId'], '3');
        gate.complete();
        expect(await d.f.finish(t, a), isFalse);
        expect(d.player.state.track.subtitle.id, '3');
        expect((await d.saved())?['subtitleTrackId'], '3');
        expect(d.logs.where((v) => v.contains('user notified')), isEmpty);
        expect(
          d.player.calls
              .where((v) => v.$1 == 'subtitle')
              .map((v) => (v.$2 as mk.SubtitleTrack).id),
          containsAllInOrder(['2', '3']),
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        d.player.beforeOperation = null;
        d.player.heldOperation = null;
        await d.close();
      }
    },
  );
  testWidgets(
    'subtitle admitted A rollback continues over B without a generation recheck',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final gate = Completer<void>();
      var entered = false;
      try {
        await d.mount();
        final panel = await d.menu();
        expect(await d.select('2', panel: panel), isTrue);
        d.player.beforeOperation = (name, value) async {
          if (name == 'subtitle' && (value as mk.SubtitleTrack).id == '1') {
            entered = true;
            await gate.future;
          }
        };
        d.player.heldOperation = (name, value) =>
            name == 'subtitle' &&
            (value as mk.SubtitleTrack).id == '1' &&
            !gate.isCompleted;
        d.fail();
        await d.f.until(t, () => entered);
        expect(d.player.state.track.subtitle.id, '2');
        expect(await d.select('3', panel: panel), isTrue);
        expect(d.player.state.track.subtitle.id, '3');
        expect((await d.saved())?['subtitleTrackId'], '3');
        gate.complete();
        await d.rollback('1');
        expect(d.player.state.track.subtitle.id, '1');
        expect((await d.saved())?['subtitleTrackId'], '1');
        expect(d.logs.where((v) => v.contains('user notified')), hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        d.player.beforeOperation = null;
        d.player.heldOperation = null;
        await d.close();
      }
    },
  );
  testWidgets(
    'subtitle repeated decoder corrections reconcile the unified menu and reopened selection',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        await d.mount();
        var panel = await d.menu();
        for (var i = 0; i < 2; i++) {
          final label = panel.embeddedSubtitles
              .firstWhere((v) => v.id == '2')
              .label;
          await t.ensureVisible(d.row(label));
          await d.observe(() => t.tap(d.row(label)));
          await d.f.until(t, () => d.player.state.track.subtitle.id == '2');
          expect(
            d.logs.where((v) => v.contains('user notified')),
            hasLength(i),
          );
          await d.f.advance(t, const Duration(milliseconds: 100));
          await d.f.actions.settle(t);
          d.expectSelected(panel, '2');
          d.fail();
          await d.f.until(
            t,
            () =>
                d.logs.where((v) => v.contains('user notified')).length ==
                i + 1,
          );
          await d.f.advance(t);
          d.expectSelected(panel, '1');
          expect(d.player.state.track.subtitle.id, '1');
          expect((await d.saved())?['subtitleTrackId'], '1');
          panel.onClose();
          await d.f.advance(t);
          panel = await d.menu();
          d.expectSelected(panel, '1');
        }
        expect(
          find.text(
            'Couldn’t apply subtitles. Try another embedded or online track.',
          ),
          findsOneWidget,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'subtitle checking-turn decoder correction clears optimistic menu while apply remains pending',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final held = ApplyTurn();
      try {
        await d.mount();
        final panel = await d.menu();
        final label = panel.embeddedSubtitles
            .firstWhere((v) => v.id == '2')
            .label;
        await t.ensureVisible(d.row(label));
        await held.run(() => d.observe(() => t.tap(d.row(label))));
        await d.f.until(t, () => held.pending.isNotEmpty);
        expect(held.pending, hasLength(1));
        expect(d.player.state.track.subtitle.id, '2');
        expect(await d.saved(), isNull);
        expect(
          find.descendant(
            of: d.row(label),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        d.fail();
        await d.f.until(
          t,
          () => d.logs.any((v) => v.contains('user notified')),
        );
        await d.f.advance(t);
        expect(held.pending, hasLength(1));
        expect(d.player.state.track.subtitle.id, '1');
        expect(await d.saved(), isNull);
        d.expectSelected(panel, '1');
        expect(
          find.descendant(
            of: d.row(label),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );
        held.release();
        await d.f.actions.settle(t);
        expect(await d.saved(), isNull);
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close();
      }
    },
  );
  testWidgets(
    'subtitle A decoder rollback followed by the same A apply exception is handled once at the unchanged generation',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final gate = Completer<void>();
      var entered = false;
      try {
        await d.mount();
        final panel = await d.menu();
        d.player.calls.clear();
        d.player.beforeOperation = (name, value) async {
          if (name == 'subtitle' && (value as mk.SubtitleTrack).id == '2') {
            entered = true;
            await gate.future;
            throw StateError('same A exception');
          }
        };
        d.player.heldOperation = (name, value) =>
            name == 'subtitle' &&
            (value as mk.SubtitleTrack).id == '2' &&
            !gate.isCompleted;
        final a = d.observe(() => panel.onEmbeddedSubtitleSelected('2', '1'));
        await d.f.until(t, () => entered);
        expect(d.player.state.track.subtitle.id, '1');
        d.fail(reason: 'A decoder failure');
        await d.rollback('1');
        expect(gate.isCompleted, isFalse);
        expect(d.logs.where((v) => v.contains('user notified')), hasLength(1));
        gate.complete();
        expect(await d.f.finish(t, a), isFalse);
        expect(
          d.player.calls
              .where((v) => v.$1 == 'subtitle')
              .map((v) => (v.$2 as mk.SubtitleTrack).id),
          ['2', '1'],
        );
        expect(d.logs.where((v) => v.contains('user notified')), hasLength(1));
        expect(
          d.logs.where(
            (v) => v.contains('set FAILED') && v.contains('same A exception'),
          ),
          hasLength(1),
        );
        expect(await d.saved(), isNull);
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        d.player.beforeOperation = null;
        d.player.heldOperation = null;
        await d.close();
      }
    },
  );
}
