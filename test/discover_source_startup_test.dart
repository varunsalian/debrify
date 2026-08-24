import 'package:debrify/screens/search_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('late Discover hydration cannot replace an explicit source choice', () {
    expect(
      discoverLandingLoadIsCurrent(
        capturedRevision: 0,
        currentRevision: 1,
        hasPendingHandoff: false,
      ),
      isFalse,
    );
  });

  test('Search handoff takes priority over the configured landing source', () {
    expect(
      discoverLandingLoadIsCurrent(
        capturedRevision: 0,
        currentRevision: 0,
        hasPendingHandoff: true,
      ),
      isFalse,
    );
  });

  test('unchanged Discover startup hydration may apply', () {
    expect(
      discoverLandingLoadIsCurrent(
        capturedRevision: 0,
        currentRevision: 0,
        hasPendingHandoff: false,
      ),
      isTrue,
    );
  });
}
