import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// TEMPORARY instrumentation, round 2: sidebar open/close jank + residual
/// Home lag. Grep tag: `DBRF-PERF`. REMOVE this file and its call sites when
/// the hunt is over.
///
/// Works on a RELEASE Android build (`adb logcat -s flutter`). Lines are
/// phrased to pass PrivacyLog's redactor untouched — no braces, no URLs, no
/// `error:`/`failed:` shapes. tvOS release carries these to no console;
/// Android TV is the target.
///
/// Captures:
///  - every janky frame (>=33ms) with the BUILD vs RASTER split, image-cache
///    pressure, and how long after the last key it landed (and which key);
///  - burst summaries so an episode reads as one line;
///  - marks from call sites: sidebar expand/collapse status transitions
///    (with the nav style, so a style-specific cost shows itself) and
///    Spotlight board mount/update/dispose.
abstract final class HomePerf {
  static bool _installed = false;

  /// On once installed — the sidebar lives on every TV tab, so frames are
  /// interesting whenever the shell is up. (Round 1 gated this to the
  /// Spotlight board's lifetime; the navbar complaint spans tabs.)
  static bool active = false;

  static Stopwatch? _sinceKey;
  static String _keyLabel = '';

  static bool _inBurst = false;
  static int _burstFrames = 0;
  static int _burstWorst = 0;
  static int _quiet = 0;
  static final Stopwatch _burstClock = Stopwatch();

  static void install() {
    if (_installed) return;
    _installed = true;
    active = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // Observe-only: always returns false so no key is ever consumed.
    HardwareKeyboard.instance.addHandler(_onKey);
    mark('installed');
  }

  static void mark(String what) => debugPrint('DBRF-PERF $what');

  static bool _onKey(KeyEvent e) {
    if (active && e is KeyDownEvent) {
      _sinceKey = Stopwatch()..start();
      final k = e.logicalKey;
      _keyLabel = k.keyLabel.isEmpty ? (k.debugName ?? 'unnamed') : k.keyLabel;
    }
    return false;
  }

  static void _onTimings(List<FrameTiming> timings) {
    if (!active) return;
    for (final t in timings) {
      final build = t.buildDuration.inMilliseconds;
      final raster = t.rasterDuration.inMilliseconds;
      final total = t.totalSpan.inMilliseconds;
      if (total >= 33) {
        final cache = PaintingBinding.instance.imageCache;
        final key = _sinceKey == null
            ? ''
            : ' sinceKey=${_sinceKey!.elapsedMilliseconds}ms key=$_keyLabel';
        mark(
          'frame total=${total}ms build=${build}ms raster=${raster}ms '
          'imgCache=${cache.currentSizeBytes >> 20}MB '
          'imgs=${cache.currentSize} live=${cache.liveImageCount}$key',
        );
        if (!_inBurst) {
          _inBurst = true;
          _burstFrames = 0;
          _burstWorst = 0;
          _burstClock
            ..reset()
            ..start();
        }
        _burstFrames++;
        if (total > _burstWorst) _burstWorst = total;
        _quiet = 0;
      } else if (_inBurst && ++_quiet >= 30) {
        // ~half a second of clean frames closes the burst.
        _inBurst = false;
        mark(
          'burst frames=$_burstFrames worst=${_burstWorst}ms '
          'span=${_burstClock.elapsedMilliseconds}ms',
        );
      }
    }
    // One measurement per keypress: whatever frames this batch carried,
    // the NEXT slow frame should not be blamed on an old key.
    if (_sinceKey != null && _sinceKey!.elapsedMilliseconds > 2000) {
      _sinceKey = null;
    }
  }
}
