import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;

/// Where the ladder for the CURRENT media generation ended up.
enum TvosRemedyState {
  /// Nothing detected, nothing touched.
  none,

  /// Rung 1 settled: VideoToolbox re-decoding to 8-bit NV12 surfaces.
  nv12,

  /// Rung 2 settled: software decode (either forced by rung 2, or mpv's own
  /// fallback observed after the rung-1 cycle).
  software,

  /// Both rungs applied and the decoder still reports a high-bit surface.
  /// Nothing further to try from Dart; diagnosed for the report.
  gaveUp,
}

enum _Phase { idle, applying, terminal }

/// The Apple TV blue-screen remedy — see PLAYER_TVOS_10BIT_PLAN.md.
///
/// The tvOS video path renders mpv through the OpenGL render API into an
/// OpenGL ES context, whose VideoToolbox interop (`ios-gl`) maps decoded
/// CVPixelBuffers with 8-bit GL_LUMINANCE textures. A high-bit surface
/// (P010 family — 10/12/16-bit biplanar) viewed through that mapping is
/// garbage that reads as a solid blue field. This class watches what the
/// decoder actually produced and, only when it produced one of those
/// formats, walks a two-rung ladder:
///
///  1. `hwdec-image-format=nv12` + a `hwdec` no→auto cycle — VideoToolbox
///     itself converts to 8-bit during decode, hardware decoding retained;
///  2. `hwdec=no` — software decode, correct but heavy.
///
/// Concurrency contract (carried from four review rounds — do not relax):
///  - `videoParams` stream events may only START the ladder from idle, and
///    never while a media boundary is in flight ([boundaryPending]) —
///    events from the outgoing file would otherwise be relabelled as the
///    new generation's.
///  - Escalation is decided exclusively by direct property polling; the
///    cycle's own transitional events are ignored. A poll terminates EARLY
///    only on two consecutive reads of that rung's TARGET; a bad value is
///    final only at the deadline (rung 1's target: any format the interop
///    can map; rung 2's target: no hw surface at all).
///  - Every property access runs through a serial queue with a generation
///    guard inside the queued op. The media-boundary restore runs as a
///    queued op too, so it drains behind any in-flight ladder write, reads
///    the touched-flags AFTER that write, and completes before the caller's
///    awaited `onNewMedia` resolves — which the screen awaits before
///    `open()`. Touched flags are set at ISSUE time (before the write), so
///    a boundary can never observe an in-flight write as untouched.
///    Poll SLEEPS stay outside the queue.
class TvosDecodeRemedy {
  TvosDecodeRemedy({
    required Future<String> Function(String property) getProperty,
    required Future<void> Function(String property, String value) setProperty,
    void Function()? onStateChanged,
    Duration pollInterval = const Duration(milliseconds: 250),
    int pollAttempts = 12,
    bool pinNv12FromStart = false,
  })  : _get = getProperty,
        _set = setProperty,
        _onStateChanged = onStateChanged,
        _pollInterval = pollInterval,
        _pollAttempts = pollAttempts,
        _keepNv12ForSession = pinNv12FromStart;

  final Future<String> Function(String property) _get;
  final Future<void> Function(String property, String value) _set;
  final void Function()? _onStateChanged;
  final Duration _pollInterval;
  final int _pollAttempts;

  /// The complete high-bit biplanar family VideoToolbox can emit (FFmpeg
  /// pixfmt.h). High-bit 4:2:2/4:4:4 triggering is intentional: it takes
  /// the same broken 8-bit GLES mapping as P010.
  static const Set<String> highBitBiplanar = {
    'p010', 'p012', 'p016',
    'p210', 'p212', 'p216',
    'p410', 'p412', 'p416',
  };

  static bool triggers(String? hwPixelformat) =>
      hwPixelformat != null && highBitBiplanar.contains(hwPixelformat);

  /// Ownership token: bumped synchronously by [onNewMedia]. Checked inside
  /// every queued op and after every await in the ladder flow.
  int _generation = -1;

  /// The generation whose boundary restore has been REQUESTED but has not
  /// yet RUN. While it matches [_generation], [evaluate] is gated: an event
  /// arriving in that window belongs to the outgoing file, whatever
  /// generation number the caller stamps on it.
  int _boundaryPendingFor = -1;

  _Phase _phase = _Phase.idle;

  /// The ladder outcome for the current generation, for diagnostics.
  TvosRemedyState state = TvosRemedyState.none;

  /// True while a ladder is being applied — the diagnostic's
  /// `remedy_outcome=pending`.
  bool get applying => _phase == _Phase.applying;

  /// What triggered the ladder (e.g. 'p010') — preserved even after the
  /// decoder reconfigures, so the diagnostic line shows the whole journey.
  String? detectedHwPixelformat;

  /// The value the settling poll last verified by DIRECT read — unlike the
  /// screen's stream-captured params, this cannot be stale-P010 after a
  /// confirmed settle.
  String? verifiedHwPixelformat;

  /// When set, every media boundary pre-applies `hwdec-image-format=nv12`
  /// BEFORE the file's decoder exists — no cycle, no flash, free for 8-bit
  /// files (their format is already NV12).
  ///
  /// Armed two ways: from construction (`pinNv12FromStart` — the standard
  /// player behavior: pre-0.33 mpv shipped this exact default on Apple
  /// platforms), and by a rung-1 settle (the session hint, which mattered
  /// when the pin was reactive-only and is kept as belt-and-braces).
  /// The LADDER stays underneath either way: if VideoToolbox rejects NV12
  /// for some exotic stream, detection still fires and rung 2 lands on
  /// software decode. The software rung is never sticky.
  bool _keepNv12ForSession;

  /// Which properties this class has written — or is in the middle of
  /// writing: set at issue time, read only inside queued ops (i.e. after
  /// the write in question has drained).
  bool _touchedFormat = false;
  bool _touchedHwdec = false;

  bool _disposed = false;

  /// Serial queue for property access and boundary restores.
  Future<void> _queue = Future<void>.value();

  /// Enqueue one op. It runs only if the generation it was created under is
  /// still current; otherwise it's a silent no-op. Errors are swallowed: a
  /// property backend failure must never break playback, only the remedy.
  ///
  /// The result is TAGGED: `ran` distinguishes a genuine value (including a
  /// genuinely-absent property) from a skipped or failed op — a failed READ
  /// must never be mistaken for "no hardware surface".
  Future<(bool ran, T? value)> _op<T>(
    int generation,
    Future<T> Function() body,
  ) {
    final completer = Completer<(bool, T?)>();
    _queue = _queue.then((_) async {
      if (_disposed || generation != _generation) {
        completer.complete((false, null));
        return;
      }
      try {
        completer.complete((true, await body()));
      } catch (_) {
        completer.complete((false, null));
      }
    });
    return completer.future;
  }

  /// media_kit's getProperty returns '' for absent properties; "no hw
  /// surface" is only expressible as null.
  static String? _normalize(String? raw) {
    if (raw == null) return null;
    final v = raw.trim();
    if (v.isEmpty || v == 'null' || v == 'no') return null;
    return v;
  }

  void _setState(TvosRemedyState next) {
    if (state == next) return;
    state = next;
    _onStateChanged?.call();
  }

  /// Media boundary. MUST be awaited before the next `open()`.
  ///
  /// The generation bump and the evaluate-gate are synchronous; the restore
  /// itself is a queued op, so it observes touched-flags only after every
  /// in-flight ladder write has drained, and the returned future resolves
  /// only once the restore writes have actually landed.
  Future<void> onNewMedia(int generation) async {
    // Session-hint promotion happens here, synchronously: `state` is only
    // ever terminal (settled/gaveUp) or none at a boundary — the applying
    // phase cannot be current because evaluate is gated the moment the
    // previous boundary began and ladder steps abort on generation change.
    if (state == TvosRemedyState.nv12) _keepNv12ForSession = true;
    _generation = generation;
    _boundaryPendingFor = generation;
    _phase = _Phase.idle;
    state = TvosRemedyState.none;
    detectedHwPixelformat = null;
    verifiedHwPixelformat = null;

    await _op(generation, () async {
      try {
        if (_touchedHwdec) {
          await _set('hwdec', 'auto');
          // Cleared only AFTER the write lands: a failed restore keeps the
          // flag, and the next boundary retries it.
          _touchedHwdec = false;
        }
        if (_keepNv12ForSession) {
          // Pre-apply (idempotent when already set). Decoder not created
          // yet → no cycle, no flash, free for 8-bit files.
          _touchedFormat = true;
          await _set('hwdec-image-format', 'nv12');
        } else if (_touchedFormat) {
          await _set('hwdec-image-format', 'no');
          _touchedFormat = false;
        }
      } finally {
        // A throw above is swallowed by _op — but the gate must lift
        // regardless, or every later evaluate for this media is dead.
        if (generation == _generation) _boundaryPendingFor = -1;
      }
    });
    // A superseding boundary re-gates for ITS generation; nothing to do
    // here if this op was skipped.
  }

  /// Called from the screen's `videoParams` listener. Starts the ladder —
  /// and does nothing else, in any other phase, or while a boundary is in
  /// flight (stale events from the outgoing file arrive relabelled with the
  /// new generation during that window).
  Future<void> evaluate(mk.VideoParams params, int generation) async {
    if (_disposed || generation != _generation) return;
    if (_boundaryPendingFor == _generation) return;
    if (_phase != _Phase.idle) return;
    final hw = _normalize(params.hwPixelformat);
    if (!triggers(hw)) return;

    _phase = _Phase.applying;
    detectedHwPixelformat = hw;
    await _rung1(generation);
  }

  /// Rung 1's poll target: anything the GLES interop can actually map —
  /// including "no hw surface", which means mpv fell back to software on
  /// its own after the cycle.
  static bool _mappable(String? v) => !triggers(v);

  /// Rung 2's poll target: strictly no hardware surface. A stale `nv12`
  /// read after `hwdec=no` must NOT be reported as confirmed software.
  static bool _software(String? v) => v == null;

  /// The touched flag is set INSIDE the queued body, immediately before the
  /// write: a write skipped by the generation guard stays untouched (no
  /// spurious restore), while a genuinely in-flight write is already marked
  /// when a boundary drains behind it.
  Future<(bool, void)> _write(int generation, String property, String value) {
    return _op(generation, () async {
      if (property == 'hwdec') {
        _touchedHwdec = true;
      } else if (property == 'hwdec-image-format') {
        _touchedFormat = true;
      }
      await _set(property, value);
    });
  }

  Future<void> _rung1(int generation) async {
    await _write(generation, 'hwdec-image-format', 'nv12');
    if (_stale(generation)) return;

    // media_kit's setProperty discards mpv's error code — the read-back is
    // the only truth. A mismatch (or a failed read) means the option can't
    // be trusted: skip the pointless cycle and escalate.
    final readBack = await _op(generation, () => _get('hwdec-image-format'));
    if (_stale(generation)) return;
    if (!readBack.$1 || _normalize(readBack.$2) != 'nv12') {
      await _rung2(generation);
      return;
    }

    // Re-initialise the decoder in place so the new surface format takes
    // effect for the CURRENT file. No app-level player rebuild.
    await _write(generation, 'hwdec', 'no');
    if (_stale(generation)) return;
    await _write(generation, 'hwdec', 'auto');
    if (_stale(generation)) return;

    final settled = await _poll(generation, _mappable);
    if (_stale(generation)) return;
    if (settled == _PollResult.good) {
      _phase = _Phase.terminal;
      // Distinguish "hardware nv12" from "mpv fell back to software on its
      // own" for the diagnosis. A failed read defaults to the honest
      // hardware claim — the poll already verified a mappable surface.
      final current = await _op(generation, () => _get('hwdec-current'));
      if (_stale(generation)) return;
      _setState(current.$1 && _normalize(current.$2) == null
          ? TvosRemedyState.software
          : TvosRemedyState.nv12);
      return;
    }
    await _rung2(generation);
  }

  Future<void> _rung2(int generation) async {
    await _write(generation, 'hwdec', 'no');
    if (_stale(generation)) return;

    final settled = await _poll(generation, _software);
    if (_stale(generation)) return;
    _phase = _Phase.terminal;
    _setState(settled == _PollResult.good
        ? TvosRemedyState.software
        : TvosRemedyState.gaveUp);
  }

  /// Poll `video-params/hw-pixelformat` until the rung's TARGET reads twice
  /// in a row. Non-target reads never end the poll early — a decoder
  /// mid-cycle serves stale surfaces for several reads — they are only
  /// final at the deadline.
  Future<_PollResult> _poll(
    int generation,
    bool Function(String?) isTarget,
  ) async {
    var consecutiveTarget = 0;
    String? last;
    var anyRead = false;
    for (var attempt = 0; attempt < _pollAttempts; attempt++) {
      // Sleep OUTSIDE the queue — a media boundary must never wait behind
      // this loop.
      await Future<void>.delayed(_pollInterval);
      if (_stale(generation)) return _PollResult.aborted;
      final read = await _op(
        generation,
        () => _get('video-params/hw-pixelformat'),
      );
      if (_stale(generation)) return _PollResult.aborted;
      if (!read.$1) {
        // A failed read is NOT "no hardware surface" — it is no evidence at
        // all, and it breaks any streak.
        consecutiveTarget = 0;
        continue;
      }
      anyRead = true;
      last = _normalize(read.$2);
      if (isTarget(last)) {
        consecutiveTarget++;
        if (consecutiveTarget >= 2) {
          verifiedHwPixelformat = last;
          return _PollResult.good;
        }
      } else {
        consecutiveTarget = 0;
      }
    }
    if (anyRead) verifiedHwPixelformat = last;
    return _PollResult.bad;
  }

  bool _stale(int generation) => _disposed || generation != _generation;

  void dispose() {
    _disposed = true;
  }
}

enum _PollResult { good, bad, aborted }
