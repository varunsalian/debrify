import 'dart:io';

import 'package:debrify/services/profiles/profile_appearance_preferences.dart';
import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/tv_motion_profile.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_scheduler.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/tv_motion_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MotionProbe extends StatelessWidget {
  const _MotionProbe();

  @override
  Widget build(BuildContext context) => Text(
    '${AppMotion.of(context).scrollTempo(true, const Duration(milliseconds: 220)).inMilliseconds}',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = TvMotionController.preferenceKey;
  ProfileScope scope(String id, int epoch) =>
      ProfileScope(profileId: id, dataGeneration: 1, sessionEpoch: epoch);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    TvMotionController.resetProfileScope();
  });
  tearDown(() {
    TvMotionController.resetProfileScope();
    ProfileRuntime.debugReset();
  });

  test(
    'unset and unknown values keep Snappy without writing a default',
    () async {
      await TvMotionController.warm();
      expect(TvMotionController.current, TvMotionProfile.snappy);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      await prefs.setString(key, 'future-profile');
      await TvMotionController.warm();
      expect(TvMotionController.current, TvMotionProfile.snappy);
      expect(prefs.getString(key), 'future-profile');
    },
  );

  test(
    'selection writes only the captured profile and notifies immediately',
    () async {
      ProfileRuntime.initializeCommitted(scope('alpha', 1));
      final selected = TvMotionController.select(TvMotionProfile.smooth);
      expect(TvMotionController.current, TvMotionProfile.smooth);
      ProfileRuntime.publish(scope('beta', 2));
      await TvMotionController.warm();
      await selected;
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'p.alpha.g.1.$key'});
      expect(prefs.getString('p.alpha.g.1.$key'), 'smooth');
      expect(TvMotionController.current, TvMotionProfile.snappy);
    },
  );

  test('an older warm cannot overwrite a later selection', () async {
    final warm = TvMotionController.warm();
    final selected = TvMotionController.select(TvMotionProfile.smooth);
    await Future.wait([warm, selected]);
    expect(TvMotionController.current, TvMotionProfile.smooth);
  });

  test(
    'profile rollback restores its choice and failed reads fall back safely',
    () async {
      SharedPreferences.setMockInitialValues({
        'p.alpha.g.1.$key': 'smooth',
        'p.beta.g.1.$key': 42,
      });
      ProfileRuntime.initializeCommitted(scope('alpha', 1));
      await TvMotionController.warm();
      expect(TvMotionController.current, TvMotionProfile.smooth);
      TvMotionController.resetProfileScope();
      ProfileRuntime.publish(scope('beta', 2));
      await TvMotionController.warm();
      expect(TvMotionController.current, TvMotionProfile.snappy);
      ProfileRuntime.publish(scope('alpha', 3));
      await TvMotionController.warm();
      expect(TvMotionController.current, TvMotionProfile.smooth);
    },
  );

  test('rapid selections persist the last input', () async {
    final first = TvMotionController.select(TvMotionProfile.smooth);
    final last = TvMotionController.select(TvMotionProfile.snappy);
    await Future.wait([first, last]);
    expect(TvMotionController.current, TvMotionProfile.snappy);
    expect((await SharedPreferences.getInstance()).getString(key), 'snappy');
  });

  test(
    'motion stays local to automatic sync, but is valid in explicit copies',
    () {
      expect(ProfileAppearancePreferences.keys, contains(key));
      expect(WebDavSyncScheduler.admitsLocalChangeKey(key), isFalse);
      expect(ProfileCreationService.copyablePreferenceKeys, contains(key));
      for (final profile in TvMotionProfile.values) {
        expect(
          SanitizedProfilePreferences.allowsEntry(key, profile.value),
          isTrue,
        );
      }
      expect(
        SanitizedProfilePreferences.allowsEntry(key, 'future-profile'),
        isFalse,
      );
      expect(SanitizedProfilePreferences.allowsEntry(key, true), isFalse);
    },
  );

  test('resolver preserves platform baselines and reduced motion', () {
    const pointer = Duration(milliseconds: 220);
    for (final profile in TvMotionProfile.values) {
      final motion = AppMotion(
        MotionTokens.legacy,
        reduced: false,
        profile: profile,
      );
      expect(motion.scrollTempo(false, pointer), pointer);
      expect(
        motion.scrollTempo(true, pointer),
        profile == TvMotionProfile.smooth
            ? const Duration(milliseconds: 260)
            : Duration.zero,
      );
      // Upstream tvOS already glides; the opt-in must not change its default.
      expect(
        motion.scrollTempo(true, pointer, tvSnappy: pointer),
        profile == TvMotionProfile.smooth
            ? const Duration(milliseconds: 260)
            : pointer,
      );
      final reduced = AppMotion(
        MotionTokens.legacy,
        reduced: true,
        profile: profile,
      );
      expect(reduced.scrollTempo(true, pointer), Duration.zero);
      expect(reduced.scrollTempo(false, pointer), Duration.zero);
    }
  });

  test('theme tempo does not change the shipped scroll defaults', () {
    const pointer = Duration(milliseconds: 220);
    final tokens = MotionTokens.legacy.copyWith(scale: 1.3);
    final snappy = AppMotion(tokens, reduced: false);
    final smooth = AppMotion(
      tokens,
      reduced: false,
      profile: TvMotionProfile.smooth,
    );
    expect(snappy.scrollTempo(true, pointer), Duration.zero);
    expect(snappy.scrollTempo(true, pointer, tvSnappy: pointer), pointer);
    expect(snappy.scrollTempo(false, pointer), pointer);
    expect(smooth.scrollTempo(false, pointer), pointer);
    expect(
      smooth.scrollTempo(true, pointer),
      const Duration(milliseconds: 260),
    );
  });

  testWidgets(
    'root refreshes the same mounted consumer on selection and profile warm',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'p.alpha.g.1.$key': 'smooth',
        'p.beta.g.1.$key': 'snappy',
      });
      ProfileRuntime.initializeCommitted(scope('alpha', 1));
      await TvMotionController.warm();
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => TvMotionRoot(child: child!),
          home: const Scaffold(body: _MotionProbe()),
        ),
      );
      final element = tester.element(find.byType(_MotionProbe));
      expect(find.text('260'), findsOneWidget);

      ProfileRuntime.publish(scope('beta', 2));
      await TvMotionController.warm();
      await tester.pump();
      expect(find.text('0'), findsOneWidget);
      expect(tester.element(find.byType(_MotionProbe)), same(element));
      await TvMotionController.select(TvMotionProfile.smooth);
      await tester.pump();
      expect(find.text('260'), findsOneWidget);
      expect(tester.element(find.byType(_MotionProbe)), same(element));

      await tester.pumpWidget(const SizedBox.shrink());
      TvMotionController.resetProfileScope();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  test('production root and profile lifecycle wire the motion policy', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains("'tv-motion-warm', TvMotionController.warm"));
    final root = main.substring(
      main.indexOf('class _DebrifyAppState'),
      main.indexOf('class MainPage'),
    );
    expect(root, contains('child: TvMotionRoot('));
    final participant = File(
      'lib/services/profiles/profile_app_lifecycle_participant.dart',
    ).readAsStringSync();
    expect(participant, contains('TvMotionController.resetProfileScope();'));
    expect(participant, contains('await TvMotionController.warm();'));
  });
}
