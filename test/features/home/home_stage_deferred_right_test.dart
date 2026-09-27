import 'package:debrify/features/home/presentation/home_stage_deferred_right.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fixture {
  final origin = FocusNode();
  final target = FocusNode();
  FocusNode? primary;
  String? rail = 'a';
  bool active = true;
  DateTime time = DateTime(2026);
  final frames = <FocusNode? Function()>[];
  final resolved = <(String, int)>[];
  late final owner = HomeStageDeferredRight(
    currentRail: () => rail,
    stageActive: () => active,
    scheduleFocus: frames.add,
    maxAge: const Duration(seconds: 3),
    primaryFocus: () => primary,
    now: () => time,
  );

  _Fixture() {
    primary = origin;
    addTearDown(() {
      origin.dispose();
      target.dispose();
    });
  }

  void complete() => owner.complete((key, column) {
    resolved.add((key, column));
    return target;
  });
}

void main() {
  test('page completion consumes once and resolves current nodes in frame', () {
    final f = _Fixture();
    f.owner.defer('a', 99);
    f.complete();
    f.complete();
    expect(f.frames, hasLength(1));
    expect(f.resolved, isEmpty);
    expect(f.frames.single(), same(f.target));
    expect(f.resolved, [('a', 100)]);
  });

  test('rail, stage, focus and expiry rejection consume the pending move', () {
    for (final reject in <void Function(_Fixture)>[
      (f) => f.rail = 'b',
      (f) => f.active = false,
      (f) => f.primary = f.target,
      (f) => f.primary = null,
      (f) => f.time = f.time.add(const Duration(seconds: 3, microseconds: 1)),
    ]) {
      final f = _Fixture();
      f.owner.defer('a', 3);
      reject(f);
      f.complete();
      expect(f.frames, isEmpty);
      f.rail = 'a';
      f.active = true;
      f.primary = f.origin;
      f.time = DateTime(2026);
      f.complete();
      expect(f.frames, isEmpty);
    }
  });

  test('exact age limit accepts, with focus checked again inside frame', () {
    final f = _Fixture();
    f.owner.defer('a', 3);
    f.time = f.time.add(const Duration(seconds: 3));
    f.complete();
    expect(f.frames, hasLength(1));
    f.primary = f.target;
    expect(f.frames.single(), isNull);
    expect(f.resolved, isEmpty);
  });

  test('new move replaces old; no primary focus preserves pending move', () {
    final f = _Fixture();
    f.owner.defer('old', 1);
    f.owner.defer('a', 4);
    f.primary = null;
    f.owner.defer('ignored', 20);
    f.primary = f.origin;
    f.complete();
    expect(f.frames.single(), same(f.target));
    expect(f.resolved, [('a', 5)]);
  });

  test('reset retires pending move and owners remain independent', () {
    final a = _Fixture();
    final b = _Fixture();
    a.owner.defer('a', 1);
    b.owner.defer('a', 9);
    a.owner.reset();
    a.complete();
    b.complete();
    expect(a.frames, isEmpty);
    expect(b.frames.single(), same(b.target));
    expect(b.resolved, [('a', 10)]);
  });

  test('missing next node is consumed without a second completion attempt', () {
    final f = _Fixture();
    f.owner.defer('a', 3);
    f.owner.complete((_, _) => null);
    expect(f.frames.single(), isNull);
    f.complete();
    expect(f.frames, hasLength(1));
    expect(f.resolved, isEmpty);
  });
}
