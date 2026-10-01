import 'dart:async';
import 'package:debrify/features/home/data/home_display_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/home_preferences.dart';

HomeDisplayPreferencesRepository displayRepository({
  Future<bool> Function()? focus,
  bool enabled = true,
}) => HomeDisplayPreferencesRepository(
  readFocusDetails: focus ?? () async => enabled,
  readAnimationsEnabled: () async => enabled,
  readAnimationStyle: () async => 'moonlit_ocean',
  readOrientation: () async => HomeCardOrientation.portrait,
  readHideTitles: () async => enabled,
  readHideAddonNames: () async => enabled,
  readHideCollectionNames: () async => enabled,
);

void main() {
  test(
    'three sequential reads precede the parallel card preference barrier',
    () async {
      final calls = <String>[];
      final focus = Completer<bool>();
      final animation = Completer<bool>();
      final style = Completer<String>();
      final cards = Completer<HomeCardOrientation>();
      final repo = HomeDisplayPreferencesRepository(
        readFocusDetails: () {
          calls.add('focus');
          return focus.future;
        },
        readAnimationsEnabled: () {
          calls.add('animation');
          return animation.future;
        },
        readAnimationStyle: () {
          calls.add('style');
          return style.future;
        },
        readOrientation: () {
          calls.add('orientation');
          return cards.future;
        },
        readHideTitles: () async {
          calls.add('titles');
          return true;
        },
        readHideAddonNames: () async {
          calls.add('addons');
          return false;
        },
        readHideCollectionNames: () async {
          calls.add('collections');
          return true;
        },
      );
      final pending = repo.read(isCurrent: () => true);
      expect(calls, ['focus']);
      focus.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['focus', 'animation']);
      animation.complete(false);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['focus', 'animation', 'style']);
      style.complete('moonlit_ocean');
      await Future<void>.delayed(Duration.zero);
      expect(calls, [
        'focus',
        'animation',
        'style',
        'orientation',
        'titles',
        'addons',
        'collections',
      ]);
      cards.complete(HomeCardOrientation.portrait);
      final result = (await pending)!;
      expect(result, (
        orientation: HomeCardOrientation.portrait,
        hideTitlesAndRatings: true,
        hideCatalogAddonNames: false,
        hideCollectionNames: true,
        spotlightFocusDetails: true,
        animationsEnabled: false,
        animationStyle: 'moonlit_ocean',
      ));
    },
  );

  for (final stopAfter in [0, 1, 2, 3, 7]) {
    test(
      'retirement after $stopAfter reads prevents later sequential work',
      () async {
        var reads = 0;
        Future<bool> flag() async {
          reads++;
          return true;
        }

        final repo = HomeDisplayPreferencesRepository(
          readFocusDetails: flag,
          readAnimationsEnabled: flag,
          readAnimationStyle: () async {
            reads++;
            return 'moonlit_ocean';
          },
          readOrientation: () async {
            reads++;
            return HomeCardOrientation.portrait;
          },
          readHideTitles: flag,
          readHideAddonNames: flag,
          readHideCollectionNames: flag,
        );
        expect(await repo.read(isCurrent: () => reads < stopAfter), isNull);
        expect(reads, stopAfter);
      },
    );
  }

  test(
    'read failure propagates and does not trigger another preference read',
    () async {
      final error = StateError('storage');
      final repo = displayRepository(focus: () => Future.error(error));
      await expectLater(repo.read(isCurrent: () => true), throwsA(same(error)));
    },
  );
}
