import 'package:debrify/features/home/presentation/home_stage_deferred_advance.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final origin = FocusNode();
  final other = FocusNode();
  FocusNode? primary;
  bool active = true;
  DateTime time = DateTime(2026);
  bool waiting = false;
  final inspected = <String>[];
  late final owner = HomeStageDeferredAdvance(
    stageActive: () => active,
    maxAge: const Duration(seconds: 3),
    primaryFocus: () => primary,
    now: () => time,
  );

  _Fixture() {
    primary = origin;
    addTearDown(() {
      origin.dispose();
      other.dispose();
    });
  }

  HomeStageAdvanceMove? take() => owner.take(
    waitingForMore: (key) {
      inspected.add(key);
      return waiting;
    },
  );
}

void main() {
  test(
    'partial arrivals retain intent until a destination can be resolved',
    () {
      final f = _Fixture();
      f.owner.defer('rail-a', fillsLower: true);
      f.waiting = true;
      expect(f.take(), isNull);
      expect(f.take(), isNull);
      f.waiting = false;
      final move = f.take()!;
      expect(move.railKey, 'rail-a');
      expect(move.origin, same(f.origin));
      expect(move.fillsLower, isTrue);
      expect(f.take(), isNull);
      expect(f.inspected, ['rail-a', 'rail-a', 'rail-a']);
    },
  );

  test(
    'expired, inactive or moved focus is consumed even during partial arrival',
    () {
      for (final waiting in [false, true]) {
        for (final invalidate in <void Function(_Fixture)>[
          (f) => f.active = false,
          (f) => f.primary = f.other,
          (f) => f.primary = null,
          (f) =>
              f.time = f.time.add(const Duration(seconds: 3, microseconds: 1)),
        ]) {
          final f = _Fixture();
          f.owner.defer('a');
          f.waiting = waiting;
          invalidate(f);
          expect(f.take(), isNull);
          f.active = true;
          f.primary = f.origin;
          f.time = DateTime(2026);
          f.waiting = false;
          expect(f.take(), isNull);
          expect(f.inspected, ['a']);
        }
      }
    },
  );

  test(
    'inclusive age limit and backward clock retain the original age policy',
    () {
      for (final elapsed in [
        const Duration(seconds: 3),
        const Duration(seconds: -1),
      ]) {
        final f = _Fixture();
        f.owner.defer('a');
        f.time = f.time.add(elapsed);
        expect(f.take()!.railKey, 'a');
      }
    },
  );

  test('new intent replaces old; missing focus does not overwrite it', () {
    final f = _Fixture();
    f.owner.defer('old', fillsLower: true);
    f.owner.defer('new');
    f.primary = null;
    f.owner.defer('ignored', fillsLower: true);
    f.primary = f.origin;
    final move = f.take()!;
    expect(move.railKey, 'new');
    expect(move.fillsLower, isFalse);
  });

  test(
    'board reseed, route/layout reset and independent owners do not replay',
    () {
      for (final boardReseed in [true, false]) {
        final a = _Fixture();
        final b = _Fixture();
        a.owner.defer('a', fillsLower: true);
        b.owner.defer('b');
        if (boardReseed) {
          a.owner.invalidateForBoardReseed();
        } else {
          a.owner.reset();
        }
        expect(a.take(), isNull);
        expect(a.inspected, isEmpty);
        expect(b.take()!.railKey, 'b');
        a.owner.defer('fresh');
        expect(a.take()!.fillsLower, isFalse);
      }
    },
  );

  test(
    'readiness runs before validation and consumption runs before dispatch',
    () {
      final f = _Fixture();
      f.owner.defer('a');
      final move = f.owner.take(
        waitingForMore: (_) {
          f.primary = f.other;
          return false;
        },
      );
      expect(move, isNull);
      f.primary = f.origin;
      expect(f.take(), isNull);
      expect(f.inspected, isEmpty);
    },
  );
}
