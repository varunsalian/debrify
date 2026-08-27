import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/resume_write_guard.dart';

void main() {
  group('ResumeWriteGuard', () {
    final t0 = DateTime(2026, 8, 27, 9, 58, 45);

    test('permits every write when no resume was requested', () {
      final guard = ResumeWriteGuard();
      expect(guard.allowsPersist(0, now: t0), isTrue);
      expect(guard.allowsPersist(661786, now: t0), isTrue);
      expect(guard.pendingTargetMs, isNull);
    });

    test('blocks the near-zero write that follows an unlanded resume seek', () {
      // The observed failure: resume to 11:01 was requested, mpv restarted the
      // stream at 0, and the exit save filed 2169ms over the good bookmark.
      final guard = ResumeWriteGuard()..arm(661786, now: t0);
      expect(
        guard.allowsPersist(2169, now: t0.add(const Duration(seconds: 5))),
        isFalse,
      );
      expect(guard.pendingTargetMs, 661786);
    });

    test('releases once playback reaches the target', () {
      final guard = ResumeWriteGuard()..arm(661786, now: t0);
      expect(
        guard.allowsPersist(661800, now: t0.add(const Duration(seconds: 3))),
        isTrue,
      );
      expect(guard.pendingTargetMs, isNull);
      // And stays released for the shallow positions that follow.
      expect(
        guard.allowsPersist(10, now: t0.add(const Duration(minutes: 9))),
        isTrue,
      );
    });

    test('treats a keyframe-rounded landing as landed', () {
      final guard = ResumeWriteGuard(toleranceMs: 10000)..arm(661786, now: t0);
      expect(
        guard.allowsPersist(655000, now: t0.add(const Duration(seconds: 3))),
        isTrue,
      );
    });

    test('releases once the user takes over the position', () {
      final guard = ResumeWriteGuard()..arm(661786, now: t0);
      guard.noteUserSeek();
      expect(
        guard.allowsPersist(2169, now: t0.add(const Duration(seconds: 5))),
        isTrue,
      );
    });

    test('releases after the settle window so real viewing is never lost', () {
      // Resume failed, the user shrugged and watched from the start. Their
      // progress must be saved rather than blocked forever.
      final guard = ResumeWriteGuard()..arm(661786, now: t0);
      expect(
        guard.allowsPersist(15000, now: t0.add(const Duration(seconds: 29))),
        isFalse,
      );
      expect(
        guard.allowsPersist(31000, now: t0.add(const Duration(seconds: 31))),
        isTrue,
      );
      expect(guard.pendingTargetMs, isNull);
    });

    test('a fresh start (no resume) arms nothing', () {
      final guard = ResumeWriteGuard()..arm(0, now: t0);
      expect(guard.pendingTargetMs, isNull);
      expect(guard.allowsPersist(500, now: t0), isTrue);
    });

    test('re-arming for the next item replaces the previous target', () {
      final guard = ResumeWriteGuard()..arm(661786, now: t0);
      guard.arm(120000, now: t0);
      expect(guard.pendingTargetMs, 120000);
      expect(guard.allowsPersist(115000, now: t0), isTrue);
    });

    test('clear releases an in-flight guard', () {
      final guard = ResumeWriteGuard()..arm(661786, now: t0);
      guard.clear();
      expect(guard.allowsPersist(2169, now: t0), isTrue);
    });

    group('heldTargetIfBlocked (pure query)', () {
      test('returns the target for a blocked position without releasing', () {
        final guard = ResumeWriteGuard()..arm(661786, now: t0);
        expect(
          guard.heldTargetIfBlocked(
            2169,
            now: t0.add(const Duration(seconds: 5)),
          ),
          661786,
        );
        // Querying must not consume the protection.
        expect(guard.pendingTargetMs, 661786);
        expect(
          guard.allowsPersist(2169, now: t0.add(const Duration(seconds: 5))),
          isFalse,
        );
      });

      test('returns null when unarmed, landed, or settled', () {
        final unarmed = ResumeWriteGuard();
        expect(unarmed.heldTargetIfBlocked(2169, now: t0), isNull);

        final landed = ResumeWriteGuard()..arm(661786, now: t0);
        expect(landed.heldTargetIfBlocked(661800, now: t0), isNull);
        // Unlike allowsPersist, the guard is untouched by the query.
        expect(landed.pendingTargetMs, 661786);

        final settled = ResumeWriteGuard()..arm(661786, now: t0);
        expect(
          settled.heldTargetIfBlocked(
            2169,
            now: t0.add(const Duration(seconds: 31)),
          ),
          isNull,
        );
      });
    });
  });
}
