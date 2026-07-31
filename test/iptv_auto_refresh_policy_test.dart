import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/widgets/iptv/iptv_results_view.dart';

/// Policy for when a stored IPTV catalog is allowed to refresh itself.
///
/// Refreshing means downloading the provider's whole response, decoding it and
/// ingesting a fresh generation — the heaviest thing the page does, and at 50k
/// channels heavy enough to be what the weakest boxes die on. These cases pin
/// when the page may choose to do that on its own, and when it may not.
void main() {
  const fresh = Duration(minutes: 5);
  const stale = Duration(hours: 2);

  bool allowed(
    Duration age, {
    int channelCount = 5000,
    bool userRequested = false,
    bool interrupted = false,
  }) => IptvResultsViewState.shouldAutoRevalidate(
    channelCount: channelCount,
    ageMs: age.inMilliseconds,
    userRequested: userRequested,
    interrupted: interrupted,
  );

  test('a fresh catalog is never refreshed', () {
    expect(allowed(fresh), isFalse);
    expect(allowed(fresh, userRequested: true), isFalse);
  });

  test('an ordinary stale catalog refreshes itself', () {
    expect(allowed(stale), isTrue);
  });

  test('a large catalog never refreshes itself, however stale', () {
    expect(
      allowed(stale, channelCount: 20000),
      isFalse,
      reason: 'at this size the refresh is the operation that kills weak '
          'devices — the page must not choose it unprompted',
    );
    expect(allowed(const Duration(days: 30), channelCount: 50000), isFalse);
    expect(allowed(stale, channelCount: 19999), isTrue);
  });

  test('an interrupted refresh is not retried on its own', () {
    expect(allowed(stale, interrupted: true), isFalse);
  });

  test('a user-requested load overrides both guards', () {
    // Settings → the playlist → Refresh, and the error screen's Retry. The
    // guards exist to stop the page deciding to do something expensive, never
    // to refuse someone who asked for fresh data.
    expect(allowed(stale, channelCount: 50000, userRequested: true), isTrue);
    expect(allowed(stale, interrupted: true, userRequested: true), isTrue);
    expect(
      allowed(
        stale,
        channelCount: 50000,
        interrupted: true,
        userRequested: true,
      ),
      isTrue,
    );
  });
}
