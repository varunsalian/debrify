import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'package:debrify/services/tvos_decode_remedy.dart';

/// A scriptable mpv property backend. Records every access in order and
/// serves `video-params/hw-pixelformat` reads from a queue so tests can
/// replay exactly the transition sequences the review demanded (stale
/// reads, mid-cycle values, never-settling decoders).
class _FakeProps {
  final List<String> log = [];
  final Map<String, String> values = {};
  final List<String> hwPixelformatReads = [];
  String hwPixelformatFallback = '';

  /// Properties whose writes the fake mpv "rejects": logged, not stored —
  /// exactly what a real rejected option looks like through media_kit's
  /// error-discarding setProperty.
  final Set<String> rejectSets = {};

  Future<String> get(String property) async {
    log.add('get:$property');
    if (throwGets.contains(property)) throw StateError('get failed');
    if (property == 'video-params/hw-pixelformat') {
      if (hwPixelformatReads.isNotEmpty) {
        return hwPixelformatReads.removeAt(0);
      }
      return hwPixelformatFallback;
    }
    return values[property] ?? '';
  }

  /// When non-null, every set() suspends until this completer resolves —
  /// the in-flight-write window the boundary fence must survive.
  Completer<void>? setGate;

  /// Properties whose reads throw (a dead property backend).
  final Set<String> throwGets = {};

  /// Properties whose writes throw.
  final Set<String> throwSets = {};

  Future<void> set(String property, String value) async {
    final gate = setGate;
    if (gate != null) await gate.future;
    log.add('set:$property=$value');
    if (throwSets.contains(property)) throw StateError('set failed');
    if (!rejectSets.contains(property)) values[property] = value;
  }
}

mk.VideoParams _params(String? hw) => mk.VideoParams(
      pixelformat: hw == null ? 'yuv420p10le' : 'videotoolbox',
      hwPixelformat: hw,
      w: 3840,
      h: 2160,
      dw: 3840,
      dh: 2160,
    );

TvosDecodeRemedy _remedy(
  _FakeProps props, {
  void Function()? onStateChanged,
  int pollAttempts = 12,
  bool pinNv12FromStart = false,
}) =>
    TvosDecodeRemedy(
      getProperty: props.get,
      setProperty: props.set,
      onStateChanged: onStateChanged,
      pollInterval: Duration.zero,
      pollAttempts: pollAttempts,
      pinNv12FromStart: pinNv12FromStart,
    );

void main() {
  test('detection: the nine-format family triggers, good formats never do',
      () {
    for (final bad in [
      'p010', 'p012', 'p016',
      'p210', 'p212', 'p216',
      'p410', 'p412', 'p416',
    ]) {
      expect(TvosDecodeRemedy.triggers(bad), isTrue, reason: bad);
    }
    expect(TvosDecodeRemedy.triggers('nv12'), isFalse);
    expect(TvosDecodeRemedy.triggers('uyvy422'), isFalse);
    expect(TvosDecodeRemedy.triggers(null), isFalse);
  });

  test('rung 1: format set → read-back → no → auto, settles nv12', () async {
    final props = _FakeProps();
    // After the cycle: one stale p010 read, then stable nv12.
    props.hwPixelformatReads.addAll(['p010', 'nv12', 'nv12']);
    props.values['hwdec-current'] = 'videotoolbox';
    final r = _remedy(props);
    await r.onNewMedia(1);
    await r.evaluate(_params('p010'), 1);

    expect(r.state, TvosRemedyState.nv12);
    expect(r.detectedHwPixelformat, 'p010');
    final sets = props.log.where((e) => e.startsWith('set:')).toList();
    expect(sets, [
      'set:hwdec-image-format=nv12',
      'set:hwdec=no',
      'set:hwdec=auto',
    ]);
    // Read-back happened between the format set and the cycle.
    final rbIndex = props.log.indexOf('get:hwdec-image-format');
    expect(rbIndex, greaterThan(props.log.indexOf('set:hwdec-image-format=nv12')));
    expect(rbIndex, lessThan(props.log.indexOf('set:hwdec=no')));
  });

  test('read-back mismatch skips the cycle and escalates to software',
      () async {
    final props = _FakeProps();
    props.rejectSets.add('hwdec-image-format');
    props.values['hwdec-image-format'] = 'no';
    final r = _remedy(props);
    await r.onNewMedia(1);

    // Rung-2 poll: software decode reached.
    props.hwPixelformatReads.addAll(['', '']);
    await r.evaluate(_params('p010'), 1);

    expect(props.log.contains('set:hwdec=auto'), isFalse,
        reason: 'a rejected option means the cycle is pointless');
    expect(props.log.contains('set:hwdec=no'), isTrue,
        reason: 'rung 2 forces software');
    expect(r.state, TvosRemedyState.software);
  });

  test('stale bad reads never end the poll early — good must be consecutive',
      () async {
    final props = _FakeProps();
    // Two stale p010s (would have satisfied a naive two-matching-reads
    // protocol), one good, one bad again, then stable good.
    props.hwPixelformatReads.addAll(['p010', 'p010', 'nv12', 'p010', 'nv12', 'nv12']);
    props.values['hwdec-current'] = 'videotoolbox';
    final r = _remedy(props);
    await r.onNewMedia(1);
    await r.evaluate(_params('p010'), 1);

    expect(r.state, TvosRemedyState.nv12,
        reason: 'the poll must survive stale and flapping reads');
  });

  test('rung 1 dead at deadline → rung 2 → settles software', () async {
    final props = _FakeProps();
    props.hwPixelformatReads.addAll(List.filled(12, 'p010')); // rung-1 poll
    props.hwPixelformatReads.addAll(['', '']); // rung-2 poll: sw decode
    final r = _remedy(props);
    await r.onNewMedia(1);
    await r.evaluate(_params('p010'), 1);

    expect(r.state, TvosRemedyState.software);
    final hwdecSets =
        props.log.where((e) => e.startsWith('set:hwdec=')).toList();
    expect(hwdecSets, ['set:hwdec=no', 'set:hwdec=auto', 'set:hwdec=no']);
  });

  test('both rungs dead → gaveUp, and states were announced', () async {
    final props = _FakeProps();
    props.hwPixelformatFallback = 'p010'; // never settles
    var announced = 0;
    final r = _remedy(props, onStateChanged: () => announced++, pollAttempts: 3);
    await r.onNewMedia(1);
    await r.evaluate(_params('p010'), 1);

    expect(r.state, TvosRemedyState.gaveUp);
    expect(announced, 1);
  });

  test('events in a non-idle phase are ignored (no double ladder)', () async {
    final props = _FakeProps();
    props.hwPixelformatReads.addAll(['nv12', 'nv12']);
    props.values['hwdec-current'] = 'videotoolbox';
    final r = _remedy(props);
    await r.onNewMedia(1);
    final first = r.evaluate(_params('p010'), 1);
    // A stale-P010 event lands while rung 1 is in flight.
    await r.evaluate(_params('p010'), 1);
    await first;

    final formatSets = props.log
        .where((e) => e == 'set:hwdec-image-format=nv12')
        .length;
    expect(formatSets, 1, reason: 'one ladder, not two');
    expect(r.state, TvosRemedyState.nv12);
  });

  test('good formats are a full no-op', () async {
    final props = _FakeProps();
    final r = _remedy(props);
    await r.onNewMedia(1);
    await r.evaluate(_params('nv12'), 1);
    await r.evaluate(_params(null), 1);
    expect(props.log.where((e) => e.startsWith('set:')), isEmpty);
    expect(r.state, TvosRemedyState.none);
  });

  test('generation change mid-ladder aborts without writes for the old gen',
      () async {
    final props = _FakeProps();
    props.hwPixelformatFallback = 'p010';
    final r = _remedy(props, pollAttempts: 50);
    await r.onNewMedia(1);
    final flight = r.evaluate(_params('p010'), 1);
    // Let rung 1 reach its verification poll deterministically.
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    // Boundary arrives while the rung-1 poll spins.
    await r.onNewMedia(2);
    await flight;

    expect(r.state, TvosRemedyState.none, reason: 'new generation is clean');
    // The boundary's restore is the LAST write — nothing from the stale
    // flow may land after it.
    final lastRestore = props.log.lastIndexOf('set:hwdec-image-format=no');
    expect(lastRestore, isNot(-1));
    expect(
      props.log.sublist(lastRestore + 1).where((e) => e.startsWith('set:')),
      isEmpty,
    );
  });

  test('onNewMedia restores what was touched — remediated → 8-bit case',
      () async {
    final props = _FakeProps();
    props.hwPixelformatReads.addAll(List.filled(12, 'p010'));
    props.hwPixelformatReads.addAll(['', '']);
    final r = _remedy(props);
    await r.onNewMedia(1);
    await r.evaluate(_params('p010'), 1); // ends software
    expect(r.state, TvosRemedyState.software);

    props.log.clear();
    await r.onNewMedia(2);
    expect(props.log, contains('set:hwdec=auto'),
        reason: 'software never leaks into the next file');
    expect(r.state, TvosRemedyState.none);
  });

  test('session hint: rung-1 settle keeps nv12 for the next media, no cycle',
      () async {
    final props = _FakeProps();
    props.hwPixelformatReads.addAll(['nv12', 'nv12']);
    props.values['hwdec-current'] = 'videotoolbox';
    final r = _remedy(props);
    await r.onNewMedia(1);
    await r.evaluate(_params('p010'), 1);
    expect(r.state, TvosRemedyState.nv12);

    props.log.clear();
    await r.onNewMedia(2);
    expect(props.log, contains('set:hwdec-image-format=nv12'),
        reason: 'pre-applied before the decoder exists');
    expect(props.log, contains('set:hwdec=auto'),
        reason: 'the cycle touched hwdec; it goes back to auto');
    // The next file decodes straight to nv12: no ladder, no cycle.
    props.log.clear();
    await r.evaluate(_params('nv12'), 2);
    expect(props.log.where((e) => e.startsWith('set:')), isEmpty);
  });

  test('rung 2 target is strictly software — stale nv12 cannot confirm it',
      () async {
    final props = _FakeProps();
    props.hwPixelformatReads.addAll(List.filled(12, 'p010')); // rung-1 poll
    // Rung-2 poll: two stale nv12 reads (must NOT settle), then p010 to the
    // deadline — the honest verdict is gaveUp.
    props.hwPixelformatReads.addAll(['nv12', 'nv12']);
    props.hwPixelformatFallback = 'p010';
    final r = _remedy(props);
    await r.onNewMedia(1);
    await r.evaluate(_params('p010'), 1);

    expect(r.state, TvosRemedyState.gaveUp,
        reason: 'nv12 after hwdec=no is a stale read, not software decode');
  });

  test('an in-flight write is fenced: the boundary restore lands after it '
      'and before onNewMedia resolves', () async {
    final props = _FakeProps();
    final r = _remedy(props);
    await r.onNewMedia(1);

    // Suspend the very first ladder write mid-flight.
    props.setGate = Completer<void>();
    final flight = r.evaluate(_params('p010'), 1);
    await Future<void>.delayed(Duration.zero);

    // Boundary arrives while set(hwdec-image-format) is suspended.
    final boundary = r.onNewMedia(2);
    props.setGate!.complete();
    props.setGate = null;
    await boundary;
    await flight;

    // The stale write drained FIRST, and the boundary saw it as touched —
    // its restore is ordered after and puts the format back.
    final formatWrites = props.log
        .where((e) => e.startsWith('set:hwdec-image-format'))
        .toList();
    expect(formatWrites, [
      'set:hwdec-image-format=nv12',
      'set:hwdec-image-format=no',
    ]);
  });

  test('events during a pending boundary are ignored even with the new '
      'generation number', () async {
    final props = _FakeProps();
    final r = _remedy(props);
    await r.onNewMedia(1);

    // Gate the queue so the boundary restore for gen 2 cannot run yet.
    props.setGate = Completer<void>();
    // Force a queued write so the boundary op sits behind it: start a
    // ladder on gen 1 whose first write suspends.
    final flight = r.evaluate(_params('p010'), 1);
    await Future<void>.delayed(Duration.zero);
    final boundary = r.onNewMedia(2);

    // The outgoing file's stale P010 event arrives relabelled as gen 2.
    await r.evaluate(_params('p010'), 2);

    props.setGate!.complete();
    props.setGate = null;
    await boundary;
    await flight;

    expect(r.state, TvosRemedyState.none,
        reason: 'the relabelled event must not have started a ladder');
    // Exactly one nv12 write (gen 1's, drained) — no second ladder.
    expect(
      props.log.where((e) => e == 'set:hwdec-image-format=nv12').length,
      1,
    );
  });

  test('failed poll reads are no evidence — rung 2 cannot confirm on them',
      () async {
    final props = _FakeProps();
    props.hwPixelformatReads.addAll(List.filled(12, 'p010')); // rung-1 poll
    // Rung-2 poll: the property backend dies. '' would normalize to null
    // (the software target); a THROW must not.
    props.throwGets.add('video-params/hw-pixelformat');
    final r = _remedy(props);
    await r.onNewMedia(1);
    await r.evaluate(_params('p010'), 1);

    expect(r.state, TvosRemedyState.gaveUp,
        reason: 'no read succeeded — "confirmed software" would be a lie');
  });

  test('a failing boundary write neither wedges the gate nor drops the flag',
      () async {
    final props = _FakeProps();
    props.hwPixelformatReads.addAll(List.filled(12, 'p010'));
    props.hwPixelformatReads.addAll(['', '']);
    final r = _remedy(props);
    await r.onNewMedia(1);
    await r.evaluate(_params('p010'), 1); // settles software (hwdec touched)
    expect(r.state, TvosRemedyState.software);

    // The restore write fails at the next boundary.
    props.throwSets.add('hwdec');
    props.log.clear();
    await r.onNewMedia(2);

    // Gate lifted: evaluation works for the new media.
    props.hwPixelformatReads.addAll(['nv12', 'nv12']);
    props.values['hwdec-current'] = 'videotoolbox';
    props.throwSets.clear();
    await r.evaluate(_params('p010'), 2);
    expect(r.state, TvosRemedyState.nv12,
        reason: 'a failed restore must not permanently gate evaluate');

    // And the failed restore was retried at the following boundary.
    props.log.clear();
    await r.onNewMedia(3);
    expect(props.log, contains('set:hwdec=auto'));
  });

  test('a write skipped by the generation guard leaves no touched flag — '
      'the boundary does not restore what was never written', () async {
    final props = _FakeProps();
    final r = _remedy(props);
    await r.onNewMedia(1);
    // The ladder enqueues its first write; the boundary bumps the
    // generation before the queue runs it, so the write is SKIPPED.
    final flight = r.evaluate(_params('p010'), 1);
    await r.onNewMedia(2);
    await flight;

    expect(props.log.where((e) => e.startsWith('set:')), isEmpty,
        reason: 'no write ran, so there is nothing to restore');
  });

  test('pinNv12FromStart: the pin lands before the FIRST open, no ladder, '
      'and the ladder still backstops a rejected pin', () async {
    final props = _FakeProps();
    final r = _remedy(props, pinNv12FromStart: true);
    await r.onNewMedia(1);

    expect(props.log, contains('set:hwdec-image-format=nv12'),
        reason: 'the pin is pre-applied before the first decoder exists');
    expect(props.log.where((e) => e.startsWith('set:hwdec=')), isEmpty,
        reason: 'no cycle — the decoder was never created yet');

    // The pinned decoder produces nv12: nothing further ever happens.
    props.log.clear();
    await r.evaluate(_params('nv12'), 1);
    expect(props.log.where((e) => e.startsWith('set:')), isEmpty);
    expect(r.state, TvosRemedyState.none);

    // A stream the pin could not help (still high-bit) drives the ladder
    // as before — the backstop is intact.
    props.hwPixelformatReads.addAll(List.filled(12, 'p010'));
    props.hwPixelformatReads.addAll(['', '']);
    await r.evaluate(_params('p010'), 1);
    expect(r.state, TvosRemedyState.software);
  });

  test('no hint without a settle: a clean session restores format to no',
      () async {
    final props = _FakeProps();
    props.hwPixelformatReads.addAll(List.filled(12, 'p010'));
    props.hwPixelformatReads.addAll(List.filled(12, 'p010'));
    final r = _remedy(props, pollAttempts: 3);
    props.hwPixelformatReads.clear();
    props.hwPixelformatFallback = 'p010';
    await r.onNewMedia(1);
    await r.evaluate(_params('p010'), 1); // gaveUp
    expect(r.state, TvosRemedyState.gaveUp);

    props.log.clear();
    await r.onNewMedia(2);
    expect(props.log, contains('set:hwdec-image-format=no'),
        reason: 'a failed remedy must not pin formats for later files');
  });
}
