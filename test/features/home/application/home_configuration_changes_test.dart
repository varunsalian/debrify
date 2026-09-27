import 'package:debrify/features/home/application/home_configuration_changes.dart';
import 'package:debrify/features/home/models/home_catalog_preferences.dart';
import 'package:debrify/models/home_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

HomeCatalogPreferences prefs({
  Set<String> disabled = const {},
  List<HomeExtraRow> extras = const [],
  List<String> order = const [],
  HomeHeroSource hero = (
    mode: HomeHeroSourceMode.random,
    ids: const <String>[],
  ),
}) => HomeCatalogPreferences(
  disabled: disabled,
  extras: extras,
  rowOrder: order,
  heroSource: hero,
);

void main() {
  test('equal sets and cross-family interleaving do not trigger a reload', () {
    final changes = homeConfigurationChanges(
      previous: prefs(
        disabled: {'a', 'b'},
        extras: [
          (id: 'traktlist:a', title: 'A'),
          (id: 'iptvlist:b', title: 'B'),
        ],
      ),
      next: prefs(
        disabled: {'b', 'a'},
        extras: [
          (id: 'iptvlist:b', title: 'B'),
          (id: 'traktlist:a', title: 'A'),
        ],
      ),
      previousHideWatched: false,
      hideWatched: false,
      previousCollectionsSignature: 'same',
      collectionsSignature: 'same',
      isHome: true,
    );
    expect(changes, (
      changed: false,
      reloadBoard: false,
      reloadHero: false,
      reloadIptv: false,
    ));
  });

  test('title and order changes reload only their own extra-row family', () {
    for (final iptv in [false, true]) {
      final prefix = iptv ? 'iptvlist:' : 'unrecognized:';
      final before = [
        (id: '${prefix}a', title: 'A'),
        (id: '${prefix}b', title: 'B'),
      ];
      for (final after in [
        before.reversed.toList(),
        [(id: '${prefix}a', title: 'Renamed'), before.last],
      ]) {
        final changes = homeConfigurationChanges(
          previous: prefs(extras: before),
          next: prefs(extras: after),
          previousHideWatched: false,
          hideWatched: false,
          previousCollectionsSignature: '',
          collectionsSignature: '',
          isHome: true,
        );
        expect(changes.changed, isTrue);
        expect(changes.reloadBoard, !iptv);
        expect(changes.reloadIptv, iptv);
        expect(changes.reloadHero, isFalse);
      }
    }
  });

  test(
    'hero and row order are committed in all variants but reload only Home',
    () {
      for (final home in [true, false]) {
        for (final heroOnly in [true, false]) {
          final changes = homeConfigurationChanges(
            previous: prefs(),
            next: heroOnly
                ? prefs(hero: (mode: HomeHeroSourceMode.custom, ids: ['a']))
                : prefs(order: ['a']),
            previousHideWatched: false,
            hideWatched: false,
            previousCollectionsSignature: '',
            collectionsSignature: '',
            isHome: home,
          );
          expect(changes.changed, isTrue);
          expect(changes.reloadBoard, home && !heroOnly);
          expect(changes.reloadHero, home && heroOnly);
          expect(changes.reloadIptv, isFalse);
        }
      }
    },
  );

  test(
    'disabled, watched and collection changes reload the board in every variant',
    () {
      for (final home in [true, false]) {
        for (final field in ['disabled', 'watched', 'collections']) {
          final changes = homeConfigurationChanges(
            previous: prefs(),
            next: prefs(disabled: field == 'disabled' ? {'a'} : {}),
            previousHideWatched: false,
            hideWatched: field == 'watched',
            previousCollectionsSignature: '',
            collectionsSignature: field == 'collections' ? 'new' : '',
            isHome: home,
          );
          expect(changes, (
            changed: true,
            reloadBoard: true,
            reloadHero: false,
            reloadIptv: false,
          ));
        }
      }
    },
  );

  test(
    'board reload takes precedence over hero while IPTV still reloads independently',
    () {
      final changes = homeConfigurationChanges(
        previous: prefs(),
        next: prefs(
          disabled: {'a'},
          extras: [(id: 'iptvlist:b', title: 'B')],
          hero: (mode: HomeHeroSourceMode.auto, ids: []),
        ),
        previousHideWatched: false,
        hideWatched: false,
        previousCollectionsSignature: '',
        collectionsSignature: '',
        isHome: true,
      );
      expect(changes, (
        changed: true,
        reloadBoard: true,
        reloadHero: false,
        reloadIptv: true,
      ));
    },
  );

  test(
    'hero ID order and duplicate saved row IDs retain their existing significance',
    () {
      for (final hero in [true, false]) {
        final changes = homeConfigurationChanges(
          previous: prefs(
            order: ['a'],
            hero: (mode: HomeHeroSourceMode.custom, ids: ['a', 'b']),
          ),
          next: prefs(
            order: hero ? ['a'] : ['a', 'a'],
            hero: (
              mode: HomeHeroSourceMode.custom,
              ids: hero ? ['b', 'a'] : ['a', 'b'],
            ),
          ),
          previousHideWatched: false,
          hideWatched: false,
          previousCollectionsSignature: '',
          collectionsSignature: '',
          isHome: true,
        );
        expect(changes.changed, isTrue);
        expect(changes.reloadBoard, !hero);
        expect(changes.reloadHero, hero);
      }
    },
  );
}
