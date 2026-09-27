import 'package:debrify/features/home/presentation/home_hero_preview_policy.dart';
import 'package:flutter_test/flutter_test.dart';

bool admit(
  HomeHeroPreviewPolicy policy,
  String id, {
  bool spotlight = false,
  bool enabled = true,
}) => policy.admitSchedule(
  id,
  fromSpotlight: spotlight,
  renderableAndEnabled: () => enabled,
);

void main() {
  test(
    'playback before first dwell suppresses the visible hero, not a missing schedule',
    () {
      final policy = HomeHeroPreviewPolicy();
      policy.suppressForPlayback(() => 'visible');
      expect(admit(policy, 'visible', spotlight: true), isFalse);
      expect(admit(policy, 'next', spotlight: true), isTrue);
    },
  );

  test(
    'visible hero replaces an older scheduled baseline at playback launch',
    () {
      final policy = HomeHeroPreviewPolicy();
      expect(admit(policy, 'a'), isTrue);
      policy.suppressForPlayback(() => 'b');
      expect(admit(policy, 'b', spotlight: true), isFalse);
      expect(admit(policy, 'a', spotlight: true), isTrue);
    },
  );

  test(
    'missing visible hero preserves admission baseline even before an attempt',
    () {
      final policy = HomeHeroPreviewPolicy();
      expect(admit(policy, 'a'), isTrue);
      // The caller can decline for layout/favourite reasons after admission.
      expect(policy.hasAttempted('a'), isFalse);
      policy.suppressForPlayback(() => null);
      expect(admit(policy, 'a', spotlight: true), isFalse);
      expect(admit(policy, 'b'), isFalse);
    },
  );

  test(
    'new hero/reseed lifts suppression without resetting attempt tracking',
    () {
      final policy = HomeHeroPreviewPolicy();
      policy.recordAttempt('a');
      policy.suppressForPlayback(() => 'a');
      policy.allowNewHero();
      expect(admit(policy, 'a'), isTrue);
      expect(policy.hasAttempted('a'), isTrue);
    },
  );

  test(
    'focus and leaving the top reset attempts independently of suppression',
    () {
      final policy = HomeHeroPreviewPolicy();
      policy.recordAttempt('a');
      policy.focus('a');
      expect(policy.hasAttempted('a'), isTrue);
      policy.focus('b');
      expect(policy.hasAttempted('a'), isFalse);
      policy.recordAttempt('b');
      policy.suppressForPlayback(() => 'b');
      policy.resetAttempt();
      expect(policy.hasAttempted('b'), isFalse);
      expect(admit(policy, 'b', spotlight: true), isFalse);
    },
  );

  test(
    'Spotlight lift precedes settings check but disabled admission does not record id',
    () {
      final policy = HomeHeroPreviewPolicy();
      expect(admit(policy, 'a'), isTrue);
      policy.suppressForPlayback(() => null);
      expect(admit(policy, 'b', enabled: false), isFalse);
      expect(admit(policy, 'a', spotlight: true), isFalse);
      expect(admit(policy, 'b', spotlight: true, enabled: false), isFalse);
      expect(admit(policy, 'a'), isTrue);
      policy.suppressForPlayback(() => null);
      expect(admit(policy, 'a', spotlight: true), isFalse);
    },
  );

  test(
    'launch sets suppression before snapshot and view instances are independent',
    () {
      final first = HomeHeroPreviewPolicy();
      final second = HomeHeroPreviewPolicy();
      first.suppressForPlayback(() {
        expect(admit(first, 'a'), isFalse);
        return 'a';
      });
      var reads = 0;
      expect(
        first.admitSchedule(
          'a',
          fromSpotlight: false,
          renderableAndEnabled: () {
            reads++;
            return true;
          },
        ),
        isFalse,
      );
      expect(reads, 1);
      expect(admit(second, 'a'), isTrue);
      second.recordAttempt('a');
      expect(first.hasAttempted('a'), isFalse);
    },
  );
}
