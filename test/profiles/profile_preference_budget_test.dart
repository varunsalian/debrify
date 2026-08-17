import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A value whose measured footprint is at least [bytes].
String _filler(int bytes) => 'x' * bytes;

void main() {
  tearDown(ProfilePreferenceBudget.debugReset);

  group('measurement', () {
    test('counts key bytes, value bytes, and per-entry overhead', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{'ab': 'cde'});
      final prefs = await SharedPreferences.getInstance();

      expect(
        ProfilePreferenceBudget.measure(prefs),
        ProfilePreferenceBudget.perEntryOverheadBytes + 2 + 3,
      );
    });

    test('sums string list elements rather than scoring the list flat', () {
      final small = ProfilePreferenceBudget.entryFootprint('k', <String>['a']);
      final large = ProfilePreferenceBudget.entryFootprint('k', <String>[
        _filler(4096),
      ]);

      expect(large - small, greaterThan(4000));
    });

    test('scores a dynamic list the same as a typed one', () {
      // The in-memory cache hands back List<dynamic>; matching on List<String>
      // would silently score a large list as a couple of bytes.
      final dynamicList = <dynamic>[_filler(2048)];
      final typedList = <String>[_filler(2048)];

      expect(
        ProfilePreferenceBudget.entryFootprint('k', dynamicList),
        ProfilePreferenceBudget.entryFootprint('k', typedList),
      );
    });

    test('counts multi-byte characters by their UTF-8 width', () {
      final ascii = ProfilePreferenceBudget.entryFootprint('k', 'aaa');
      final cjk = ProfilePreferenceBudget.entryFootprint('k', '世界人');
      final emoji = ProfilePreferenceBudget.entryFootprint('k', '😀');

      expect(cjk - ascii, 6); // three 3-byte runes vs three 1-byte
      expect(emoji - ProfilePreferenceBudget.entryFootprint('k', ''), 4);
    });
  });

  group('admission', () {
    test('is disabled off tvOS regardless of size', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      ProfilePreferenceBudget.debugEnforcedOverride = false;

      expect(
        ProfilePreferenceBudget.admits(
          prefs,
          'k',
          _filler(ProfilePreferenceBudget.limitBytes * 2),
        ),
        isTrue,
      );
    });

    test('admits a write that stays within the limit', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      ProfilePreferenceBudget.debugEnforcedOverride = true;

      expect(ProfilePreferenceBudget.admits(prefs, 'k', 'small'), isTrue);
    });

    test('refuses a write that would cross the limit', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      ProfilePreferenceBudget.debugEnforcedOverride = true;

      expect(
        ProfilePreferenceBudget.admits(
          prefs,
          'k',
          _filler(ProfilePreferenceBudget.limitBytes + 1),
        ),
        isFalse,
      );
    });

    test('admits a shrinking write while already over budget', () async {
      final oversized = _filler(ProfilePreferenceBudget.limitBytes * 2);
      SharedPreferences.setMockInitialValues(<String, Object>{'k': oversized});
      final prefs = await SharedPreferences.getInstance();
      ProfilePreferenceBudget.debugEnforcedOverride = true;

      // Without this an over-budget install could never shrink itself back.
      expect(ProfilePreferenceBudget.admits(prefs, 'k', 'tiny'), isTrue);
      expect(ProfilePreferenceBudget.admits(prefs, 'k', oversized), isTrue);
    });

    test('refuses further growth once over budget', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'k': _filler(ProfilePreferenceBudget.limitBytes * 2),
      });
      final prefs = await SharedPreferences.getInstance();
      ProfilePreferenceBudget.debugEnforcedOverride = true;

      expect(ProfilePreferenceBudget.admits(prefs, 'other', 'more'), isFalse);
    });

    test('accounts for the value a write replaces', () async {
      // Occupy most of the budget, then overwrite it with something equally
      // large: the net delta is zero, so it must be admitted.
      final value = _filler(ProfilePreferenceBudget.limitBytes - 1024);
      SharedPreferences.setMockInitialValues(<String, Object>{'k': value});
      final prefs = await SharedPreferences.getInstance();
      ProfilePreferenceBudget.debugEnforcedOverride = true;

      expect(ProfilePreferenceBudget.admits(prefs, 'k', value), isTrue);
      // Growing well past the remaining headroom is refused.
      expect(
        ProfilePreferenceBudget.admits(
          prefs,
          'k',
          value + _filler(ProfilePreferenceBudget.smallWriteBytes * 4),
        ),
        isFalse,
      );
    });
  });

  group('small-write reserve', () {
    setUp(() => ProfilePreferenceBudget.debugEnforcedOverride = true);

    test('keeps admitting small writes above the limit', () async {
      // Settings and sealed credentials must keep saving once the bulk stores
      // have saturated the budget: SecretVault.setString returns Future<void>
      // and drops the result, so a refusal there is invisible to the user.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'bulk': _filler(ProfilePreferenceBudget.limitBytes),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        ProfilePreferenceBudget.admits(prefs, 'api_key', _filler(512)),
        isTrue,
      );
    });

    test('still refuses bulk growth above the limit', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'bulk': _filler(ProfilePreferenceBudget.limitBytes),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        ProfilePreferenceBudget.admits(
          prefs,
          'more',
          _filler(ProfilePreferenceBudget.smallWriteBytes * 2),
        ),
        isFalse,
      );
    });

    test('refuses even small writes at the emergency ceiling', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'bulk': _filler(ProfilePreferenceBudget.emergencyLimitBytes),
      });
      final prefs = await SharedPreferences.getInstance();

      expect(ProfilePreferenceBudget.admits(prefs, 'api_key', 'x'), isFalse);
    });

    test('the emergency ceiling stays well below the platform limit', () {
      // tvOS terminates the process at 1 MiB; nothing may approach it.
      expect(
        ProfilePreferenceBudget.emergencyLimitBytes,
        lessThanOrEqualTo(512 * 1024),
      );
      expect(
        ProfilePreferenceBudget.migrationLimitBytes,
        lessThan(ProfilePreferenceBudget.limitBytes),
      );
    });
  });
}
