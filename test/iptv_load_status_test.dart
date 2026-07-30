import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/iptv_load_phase.dart';
import 'package:debrify/widgets/iptv/iptv_results_view.dart';

/// What the blocking-load screen is allowed to claim.
///
/// The point of this screen is that a user waiting several seconds on a 50k
/// panel can tell the app apart from a hung one. That only works if every
/// number on it is real — a fabricated or misleading one is worse than the
/// bare spinner it replaced.
void main() {
  group('byte label', () {
    test('a measurable transfer shows received against total', () {
      expect(
        IptvResultsViewState.loadBytesLabel(12 * 1024 * 1024, 50 * 1024 * 1024),
        '12.0 MB / 50.0 MB',
      );
    });

    test('a landed payload of unknown total shows its size alone', () {
      // The Xtream fetch buffers, so its size is only known after it lands —
      // still worth saying, since it explains the pause that follows.
      expect(IptvResultsViewState.loadBytesLabel(42 * 1024 * 1024, null),
          '42.0 MB');
    });

    test('nothing is claimed before there is anything to claim', () {
      expect(IptvResultsViewState.loadBytesLabel(null, null), isNull);
      expect(
        IptvResultsViewState.loadBytesLabel(0, null),
        isNull,
        reason: 'a buffered fetch that has not landed must not imply progress '
            'it cannot measure',
      );
    });

    test('a known total is shown even at zero received', () {
      // A streamed download DOES know where it is going, so the denominator
      // is honest from the first byte.
      expect(
        IptvResultsViewState.loadBytesLabel(0, 50 * 1024 * 1024),
        '0 B / 50.0 MB',
      );
    });

    test('small payloads do not read as 0.0 MB', () {
      expect(IptvResultsViewState.loadBytesLabel(4096, null), '4 KB');
      expect(IptvResultsViewState.loadBytesLabel(512, null), '512 B');
    });
  });

  group('elapsed clock', () {
    test('formats as m:ss', () {
      expect(IptvResultsViewState.formatLoadElapsed(Duration.zero), '0:00');
      expect(
        IptvResultsViewState.formatLoadElapsed(const Duration(seconds: 7)),
        '0:07',
      );
      expect(
        IptvResultsViewState.formatLoadElapsed(
          const Duration(minutes: 2, seconds: 5),
        ),
        '2:05',
      );
      expect(
        IptvResultsViewState.formatLoadElapsed(const Duration(minutes: 75)),
        '75:00',
      );
    });
  });

  group('phase vocabulary', () {
    test('every phase the services emit has a step position', () {
      // The page derives "Step N of M" by looking the label up in this list.
      // A service emitting a label that is not here loses its step counter
      // silently, so the two must not drift.
      for (final phase in [
        IptvLoadPhases.contacting,
        IptvLoadPhases.downloading,
        IptvLoadPhases.processing,
        IptvLoadPhases.preparing,
      ]) {
        expect(
          IptvLoadPhases.ordered,
          contains(phase),
          reason: '$phase has no step position',
        );
      }
    });

    test('the order is the order a load actually runs in', () {
      expect(IptvLoadPhases.ordered, [
        IptvLoadPhases.contacting,
        IptvLoadPhases.downloading,
        IptvLoadPhases.processing,
        IptvLoadPhases.preparing,
      ]);
      expect(
        IptvLoadPhases.ordered.toSet().length,
        IptvLoadPhases.ordered.length,
        reason: 'a duplicate label would make the step counter jump backwards',
      );
    });
  });

  group('status chip priority', () {
    // Three background jobs overlap: the guide download starts when the list
    // is presented, maintenance two seconds later, a refresh after that. One
    // chip, so without a rank the last writer wins and it flickers between
    // unrelated messages.
    // Derived from the enum itself, so a reorder cannot leave this test
    // passing against ranks the code no longer uses.
    final none = IptvResultsViewState.chipRankNone;
    final guide = IptvResultsViewState.chipRankGuide;
    final maintenance = IptvResultsViewState.chipRankMaintenance;
    final refresh = IptvResultsViewState.chipRankRefresh;

    test('anything may speak into silence', () {
      expect(IptvResultsViewState.chipClaimAllowed(none, guide), isTrue);
      expect(IptvResultsViewState.chipClaimAllowed(none, maintenance), isTrue);
      expect(IptvResultsViewState.chipClaimAllowed(none, refresh), isTrue);
    });

    test('news about the list outranks news about the guide', () {
      expect(
        IptvResultsViewState.chipClaimAllowed(guide, maintenance),
        isTrue,
      );
      expect(IptvResultsViewState.chipClaimAllowed(guide, refresh), isTrue);
      expect(
        IptvResultsViewState.chipClaimAllowed(maintenance, guide),
        isFalse,
        reason: 'a slow guide download must not stomp the numbering message',
      );
      expect(
        IptvResultsViewState.chipClaimAllowed(refresh, guide),
        isFalse,
      );
      expect(
        IptvResultsViewState.chipClaimAllowed(refresh, maintenance),
        isFalse,
      );
    });

    test('a stage may update its own message', () {
      // The guide re-announces itself every megabyte; it must not be blocked
      // by its own previous claim.
      expect(IptvResultsViewState.chipClaimAllowed(guide, guide), isTrue);
      expect(
        IptvResultsViewState.chipClaimAllowed(refresh, refresh),
        isTrue,
      );
    });

    test('the ranks are ordered as the enum declares them', () {
      expect([none, guide, maintenance, refresh], [0, 1, 2, 3]);
    });
  });
}
