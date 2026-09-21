import 'package:debrify/services/player_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('healthy state rechecks do not reset settling or block refresh', (
    tester,
  ) async {
    final owner = Object();
    PlayerVisibility.opened(owner);
    PlayerVisibility.playbackState(owner, ready: true);
    await tester.pump(const Duration(seconds: 20));
    // A nonfatal mpv error rechecks the unchanged playing/non-buffering state.
    PlayerVisibility.playbackState(owner, ready: true);
    await tester.pump(const Duration(seconds: 10));
    expect(PlayerVisibility.refreshAllowed.value, isTrue);
    PlayerVisibility.playbackState(owner, ready: true);
    expect(PlayerVisibility.refreshAllowed.value, isTrue);
    PlayerVisibility.closed(owner);
  });

  testWidgets(
    'refresh waits for stable playback, resets on buffering and pause',
    (tester) async {
      final owner = Object();
      PlayerVisibility.opened(owner);
      expect(PlayerVisibility.refreshAllowed.value, isFalse);
      PlayerVisibility.playbackState(owner, ready: true);
      await tester.pump(const Duration(seconds: 29));
      expect(PlayerVisibility.refreshAllowed.value, isFalse);
      PlayerVisibility.playbackState(owner, ready: false);
      await tester.pump(const Duration(seconds: 2));
      expect(PlayerVisibility.refreshAllowed.value, isFalse);
      PlayerVisibility.playbackState(owner, ready: true);
      await tester.pump(const Duration(seconds: 30));
      expect(PlayerVisibility.refreshAllowed.value, isTrue);
      expect(PlayerVisibility.visible.value, isTrue);
      PlayerVisibility.playbackState(owner, ready: false);
      expect(PlayerVisibility.refreshAllowed.value, isFalse);
      PlayerVisibility.closed(owner);
      expect(PlayerVisibility.refreshAllowed.value, isTrue);
    },
  );

  testWidgets('handoffs and retired owner events cannot permit early work', (
    tester,
  ) async {
    final first = Object();
    final second = Object();
    PlayerVisibility.opened(first, native: true);
    PlayerVisibility.playbackState(first, ready: true);
    await tester.pump(const Duration(seconds: 30));
    PlayerVisibility.opened(second);
    expect(PlayerVisibility.refreshAllowed.value, isFalse);
    PlayerVisibility.closed(first);
    PlayerVisibility.playbackState(first, ready: true);
    await tester.pump(const Duration(seconds: 30));
    expect(PlayerVisibility.refreshAllowed.value, isFalse);
    expect(PlayerVisibility.nativeVisible, isFalse);
    PlayerVisibility.closed(second);
    expect(PlayerVisibility.visible.value, isFalse);
    expect(PlayerVisibility.refreshAllowed.value, isTrue);
  });
}
