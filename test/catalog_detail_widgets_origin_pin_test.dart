import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';

/// Origin pin for the presentational widgets that live in the tail of
/// `catalog_item_detail_screen.dart` — the backdrop, the reveal, the meta
/// badges/chips, the cast avatars, the "More Like This" cards, the synopsis
/// and its Read-more toggle, the action row and its primary buttons, the
/// Trakt / Simkl / MDBList quick actions, and the glass card + back button.
///
/// Every assertion drives the real [CatalogItemDetailScreen]: the widgets are
/// private today, so the screen is the only door to them. Written before the
/// extraction so it pins the origin, and it must keep passing verbatim once
/// they move under `lib/widgets/detail/`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The one network call this screen makes that the pin cares about is
  // `ImdbEnrichmentService.fetch` (a POST to graphql.imdb.com) — it feeds the
  // certificate, the Metacritic badge and the Cast rail. Everything else
  // (parents guide, artwork, posters) is answered 404 so the widgets take
  // their fallback paths deterministically.
  String imdbBody({
    String? certificate,
    int? metascore,
    List<String> stars = const [],
    List<String> genres = const [],
    String? plot,
  }) => json.encode({
    'data': {
      'title': {
        if (plot != null)
          'plot': {
            'plotText': {'plainText': plot},
          },
        if (certificate != null)
          'certificate': {'rating': certificate},
        if (metascore != null)
          'metacritic': {
            'metascore': {'score': metascore},
          },
        'titleGenres': {
          'genres': [
            for (final g in genres)
              {
                'genre': {'text': g},
              },
          ],
        },
        'principalCredits': [
          {
            'category': {'text': 'Stars'},
            'credits': [
              for (final n in stars)
                {
                  'name': {
                    'nameText': {'text': n},
                  },
                  'characters': [
                    {'name': 'As $n'},
                  ],
                },
            ],
          },
        ],
      },
    },
  });

  void canImdb(String body) => HttpOverrides.global = _CannedImdb(body);

  setUp(() => HttpOverrides.global = _CannedImdb(imdbBody()));
  tearDown(() => HttpOverrides.global = null);

  TraktMenuOption trakt(
    TraktItemMenuAction action,
    String caption, {
    bool isTrakt = false,
  }) => TraktMenuOption(
    action: action,
    icon: Icons.bookmark_add_outlined,
    color: Colors.amber,
    label: caption,
    caption: caption,
    isTrakt: isTrakt,
  );

  SimklMenuOption simkl(SimklItemMenuAction action, String caption) =>
      SimklMenuOption(
        action: action,
        icon: Icons.play_circle_outline,
        color: Colors.cyan,
        label: caption,
        caption: caption,
      );

  MdblistMenuOption mdblist(MdblistItemMenuAction action, String caption) =>
      MdblistMenuOption(
        action: action,
        icon: Icons.list_alt_rounded,
        color: Colors.green,
        label: 'MDBList $caption',
        caption: caption,
      );

  /// Pumps the real screen. `size` decides the layout: the cinematic
  /// bottom-left sheet needs width >= 900 AND width > height, anything else
  /// falls to the single-scroll phone column.
  Future<void> pumpDetail(
    WidgetTester tester,
    CatalogItemDetailScreen screen, {
    Size size = const Size(1400, 900),
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: screen,
      ),
    );
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  StremioMeta movie({
    String id = 'tt0000001',
    String name = 'Pin Movie',
    String? background,
    String? description,
    List<String>? genres,
    String type = 'movie',
  }) => StremioMeta(
    id: id,
    imdbId: id,
    type: type,
    name: name,
    background: background,
    description: description,
    genres: genres,
  );

  CatalogItemDetailScreen screenFor(
    StremioMeta item, {
    VoidCallback? onPlay,
    VoidCallback? onBrowse,
    bool isTelevision = false,
    bool showQuickPlay = true,
    List<TraktMenuOption> traktMenuOptions = const [],
    void Function(TraktItemMenuAction)? onTraktAction,
    List<SimklMenuOption> simklMenuOptions = const [],
    void Function(SimklItemMenuAction)? onSimklAction,
    List<MdblistMenuOption> mdblistMenuOptions = const [],
    void Function(MdblistItemMenuAction)? onMdblistAction,
    Future<List<StremioMeta>> Function()? recommendationsLoader,
    void Function(StremioMeta)? onRecommendationTap,
    Future<({bool started, int? season, int? episode})> Function()?
    resumeInfoLoader,
  }) => CatalogItemDetailScreen(
    // A key per item id so a second `pumpWidget` inside one test builds a
    // fresh State instead of updating the previous screen in place.
    key: ValueKey(item.id),
    item: item,
    isTelevision: isTelevision,
    showQuickPlay: showQuickPlay,
    onPlay: onPlay ?? () {},
    onBrowse: onBrowse ?? () {},
    traktMenuOptions: traktMenuOptions,
    onTraktAction: onTraktAction,
    simklMenuOptions: simklMenuOptions,
    onSimklAction: onSimklAction,
    mdblistMenuOptions: mdblistMenuOptions,
    onMdblistAction: onMdblistAction,
    recommendationsLoader: recommendationsLoader,
    onRecommendationTap: onRecommendationTap,
    resumeInfoLoader: resumeInfoLoader,
  );

  /// The one `Image.network` on the page is the backdrop — every other image
  /// goes through `CachedNetworkImage`, whose provider is not a [NetworkImage].
  Finder backdropImage() => find.byWidgetPredicate(
    (w) => w is Image && w.image is NetworkImage,
    description: 'backdrop Image.network',
  );

  /// The vertical scrim: the only top→bottom [LinearGradient] painted with
  /// the backdrop's five-stop black ramp.
  BoxDecoration scrimWith(WidgetTester tester, Alignment begin) {
    final decorations = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .where((d) {
          final g = d.gradient;
          return g is LinearGradient && g.begin == begin;
        })
        .toList();
    expect(decorations, hasLength(1));
    return decorations.single;
  }

  /// Focuses the widget that owns [inner] — these cells build their own
  /// [FocusNode] internally, so the node is only reachable from below.
  Future<void> focusOn(WidgetTester tester, Finder inner) async {
    Focus.of(tester.element(inner)).requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  T ancestorOf<T extends Widget>(WidgetTester tester, Finder of) =>
      tester.widget<T>(find.ancestor(of: of, matching: find.byType(T)).first);

  // ── _Backdrop ─────────────────────────────────────────────────────────────

  testWidgets('the backdrop paints the wide scrim ramp and a left side scrim', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(movie(background: 'https://art.example/wide.jpg')),
    );

    final img = tester.widget<Image>(backdropImage());
    expect((img.image as NetworkImage).url, 'https://art.example/wide.jpg');
    expect(img.fit, BoxFit.cover);
    expect(img.alignment, Alignment.topCenter);
    // Phone/desktop keeps the Ken-Burns fade-in wrapper.
    expect(img.frameBuilder, isNotNull);

    final vertical = scrimWith(tester, Alignment.topCenter);
    final ramp = vertical.gradient! as LinearGradient;
    expect(ramp.end, Alignment.bottomCenter);
    expect(ramp.colors, const [
      Color(0x33000000),
      Color(0x66000000),
      Color(0xCC050507),
      Color(0xF5050507),
      Color(0xFF050507),
    ]);
    expect(ramp.stops, const [0.0, 0.30, 0.58, 0.82, 1.0]);

    // Wide only: the left-hand scrim under the content sheet.
    final side = scrimWith(tester, Alignment.centerLeft);
    final sideRamp = side.gradient! as LinearGradient;
    expect(sideRamp.colors, const [
      Color(0xEE050507),
      Color(0x99050507),
      Color(0x33000000),
      Color(0x00000000),
    ]);
    expect(sideRamp.stops, const [0.0, 0.32, 0.60, 1.0]);

    // Base wash + corner vignette.
    expect(
      find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0x44000000),
      ),
      findsOneWidget,
    );
    final vignette = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.gradient is RadialGradient)
        .toList();
    expect(vignette, hasLength(1));
    expect(
      (vignette.single.gradient! as RadialGradient).stops,
      const [0.0, 0.55, 1.0],
    );
  });

  testWidgets('the narrow backdrop uses the phone ramp and no side scrim', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(movie(background: 'https://art.example/tall.jpg')),
      size: const Size(420, 900),
    );

    final ramp = scrimWith(tester, Alignment.topCenter).gradient!
        as LinearGradient;
    expect(ramp.stops, const [0.0, 0.32, 0.62, 0.86, 1.0]);
    expect(
      tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) {
            final g = d.gradient;
            return g is LinearGradient && g.begin == Alignment.centerLeft;
          }),
      isEmpty,
    );
  });

  testWidgets('TV drops the Ken-Burns wrapper for a static image', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(
        movie(background: 'https://art.example/tv.jpg'),
        isTelevision: true,
      ),
    );
    expect(tester.widget<Image>(backdropImage()).frameBuilder, isNull);
  });

  // ── _GlassIconButton (back) ───────────────────────────────────────────────

  testWidgets('the back button is a 42px glass circle that pops the route', (
    tester,
  ) async {
    await pumpDetail(tester, screenFor(movie()));

    final icon = find.byIcon(Icons.arrow_back_rounded);
    expect(icon, findsOneWidget);
    expect(tester.widget<Icon>(icon).color, Colors.white);
    expect(tester.widget<Icon>(icon).size, 22);

    final box = ancestorOf<Container>(tester, icon);
    expect(box.constraints?.maxWidth, 42);
    expect(box.constraints?.maxHeight, 42);
    final deco = box.decoration! as BoxDecoration;
    expect(deco.shape, BoxShape.circle);
    expect(deco.color, Colors.black.withValues(alpha: 0.55));
    expect(deco.border!.top.width, 0.5);

    expect(find.byType(CatalogItemDetailScreen), findsOneWidget);
    await tester.tap(icon);
    await tester.pumpAndSettle();
    expect(find.byType(CatalogItemDetailScreen), findsNothing);
  });

  // ── _Reveal ───────────────────────────────────────────────────────────────

  testWidgets('sections fade and lift in, then settle at full opacity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: screenFor(movie()),
      ),
    );
    await tester.pump();

    final eyebrow = find.text('MOVIE');
    Opacity opacityOf() => ancestorOf<Opacity>(tester, eyebrow);
    expect(opacityOf().opacity, 0.0);
    final lift = ancestorOf<Transform>(tester, eyebrow);
    // dy defaults to 26 and the reveal starts fully displaced.
    expect(lift.transform.getTranslation().y, closeTo(26, 0.001));

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(opacityOf().opacity, 1.0);
    expect(
      ancestorOf<Transform>(tester, eyebrow).transform.getTranslation().y,
      closeTo(0, 0.001),
    );
  });

  // ── _CertBadge / _MetacriticBadge / _GenreChip ────────────────────────────

  testWidgets('the certificate badge renders IMDb\'s rating in a dark pill', (
    tester,
  ) async {
    canImdb(imdbBody(certificate: 'PG-13'));
    await pumpDetail(tester, screenFor(movie(id: 'tt1000001')));

    final label = find.text('PG-13');
    expect(label, findsOneWidget);
    final style = tester.widget<Text>(label).style!;
    expect(style.color, Colors.white.withValues(alpha: 0.85));
    expect(style.fontSize, 11);
    expect(style.fontWeight, FontWeight.w700);
    expect(style.letterSpacing, 0.3);

    final deco = ancestorOf<Container>(tester, label).decoration! as BoxDecoration;
    expect(deco.color, Colors.black.withValues(alpha: 0.30));
    expect(deco.borderRadius, BorderRadius.circular(4));
    expect(deco.border!.top.color, Colors.white.withValues(alpha: 0.50));
  });

  testWidgets('the Metacritic badge colours by band', (tester) async {
    // 61+ green, 40..60 yellow, below 40 red. Distinct ids because
    // ImdbEnrichmentService memoises per imdb id for the process.
    const bands = <int, Color>{
      88: Color(0xFF66CC33),
      61: Color(0xFF66CC33),
      55: Color(0xFFFFCC33),
      12: Color(0xFFFF0000),
    };
    var n = 0;
    for (final entry in bands.entries) {
      n++;
      canImdb(imdbBody(metascore: entry.key));
      await pumpDetail(tester, screenFor(movie(id: 'tt200000$n')));
      final label = find.text('${entry.key}');
      expect(label, findsOneWidget, reason: 'score ${entry.key}');
      final text = tester.widget<Text>(label).style!;
      expect(text.color, Colors.white);
      expect(text.fontWeight, FontWeight.w900);
      final deco =
          ancestorOf<Container>(tester, label).decoration! as BoxDecoration;
      expect(deco.color, entry.value, reason: 'score ${entry.key}');
      expect(deco.borderRadius, BorderRadius.circular(3));
    }
  });

  testWidgets('genre chips are capped at five and wear the pill outline', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(
        movie(
          id: 'tt3000001',
          genres: const [
            'Action',
            'Drama',
            'Sci-Fi',
            'Thriller',
            'Comedy',
            'Horror',
            'Western',
          ],
        ),
      ),
    );

    for (final g in ['Action', 'Drama', 'Sci-Fi', 'Thriller', 'Comedy']) {
      expect(find.text(g), findsOneWidget);
    }
    expect(find.text('Horror'), findsNothing);
    expect(find.text('Western'), findsNothing);

    final chip = find.text('Action');
    final style = tester.widget<Text>(chip).style!;
    expect(style.color, Colors.white.withValues(alpha: 0.88));
    expect(style.fontSize, 11);
    expect(style.fontWeight, FontWeight.w600);
    final deco = ancestorOf<Container>(tester, chip).decoration! as BoxDecoration;
    expect(deco.color, Colors.black.withValues(alpha: 0.35));
    expect(deco.borderRadius, BorderRadius.circular(999));
    expect(deco.border!.top.width, 0.5);
  });

  // ── _CastAvatar ───────────────────────────────────────────────────────────

  testWidgets('cast avatars show the surname, the character and an initial', (
    tester,
  ) async {
    canImdb(imdbBody(stars: const ['Ada Lovelace', 'Rex']));
    await pumpDetail(tester, screenFor(movie(id: 'tt4000001')));

    // Surname only, with the character line underneath.
    expect(find.text('Lovelace'), findsOneWidget);
    expect(find.text('As Ada Lovelace'), findsOneWidget);
    expect(find.text('Rex'), findsOneWidget);
    expect(find.text('As Rex'), findsOneWidget);

    final surname = tester.widget<Text>(find.text('Lovelace')).style!;
    expect(surname.color, Colors.white.withValues(alpha: 0.80));
    expect(surname.fontSize, 10);
    final character = tester.widget<Text>(find.text('As Ada Lovelace')).style!;
    expect(character.color, Colors.white.withValues(alpha: 0.38));
    expect(character.fontSize, 9);

    // No headshot in the payload, so the circle falls back to the initial.
    expect(find.text('A'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
    final initial = tester.widget<Text>(find.text('A')).style!;
    expect(initial.fontSize, 20);
    expect(initial.color, Colors.white.withValues(alpha: 0.4));

    // 1400x900 is not "tight", so the avatar is the 68px size.
    final avatar = ancestorOf<Container>(tester, find.text('A'));
    expect(avatar.constraints?.maxWidth, 68);
    expect((avatar.decoration! as BoxDecoration).shape, BoxShape.circle);
  });

  // ── _Description / _ReadMoreToggle ────────────────────────────────────────

  final longPlot = List.filled(90, 'Sentences about the plot.').join(' ');

  testWidgets('a long synopsis offers Read more and expands in place', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(movie(id: 'tt5000001', description: longPlot)),
    );

    final body = find.text(longPlot);
    expect(body, findsOneWidget);
    final collapsed = tester.widget<Text>(body);
    expect(collapsed.maxLines, 4);
    expect(collapsed.overflow, TextOverflow.fade);
    expect(collapsed.style!.fontSize, 17); // wide, not dense
    expect(collapsed.style!.height, 1.5);
    expect(collapsed.style!.color, Colors.white.withValues(alpha: 0.82));

    expect(find.text('Read more'), findsOneWidget);
    await tester.tap(find.text('Read more'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Show less'), findsOneWidget);
    final expanded = tester.widget<Text>(find.text(longPlot));
    expect(expanded.maxLines, isNull);
    expect(expanded.overflow, TextOverflow.visible);
  });

  testWidgets('the Read more toggle goes gold on focus and answers Enter', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(movie(id: 'tt5000002', description: longPlot)),
    );

    final toggle = find.text('Read more');
    final resting = tester.widget<Text>(toggle).style!;
    expect(resting.color, Colors.white.withValues(alpha: 0.95));
    expect(resting.decoration, isNull);
    expect(resting.fontWeight, FontWeight.w700);

    await focusOn(tester, toggle);

    final gold = DetailThemes.signal.focus;
    final focused = tester.widget<Text>(find.text('Read more')).style!;
    expect(focused.color, gold);
    expect(focused.decoration, TextDecoration.underline);
    expect(focused.decorationColor, gold);
    expect(
      ancestorOf<AnimatedScale>(tester, find.text('Read more')).scale,
      1.04,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Show less'), findsOneWidget);
  });

  // ── _ActionRow / _PrimaryButton ───────────────────────────────────────────

  testWidgets('a movie shows a red filled Play beside an outlined Sources', (
    tester,
  ) async {
    var plays = 0;
    var browses = 0;
    await pumpDetail(
      tester,
      screenFor(
        movie(id: 'tt6000001'),
        onPlay: () => plays++,
        onBrowse: () => browses++,
      ),
    );

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.layers_rounded), findsOneWidget);

    // Legacy keeps the shipped Netflix red with white ink.
    final play = ancestorOf<AnimatedContainer>(tester, find.text('Play'));
    final playDeco = play.decoration! as BoxDecoration;
    expect(playDeco.color, const Color(0xFFE50914));
    expect(playDeco.borderRadius, BorderRadius.circular(10));
    expect(playDeco.border!.top.color, Colors.transparent);
    expect(playDeco.border!.top.width, 0.0);
    expect(play.constraints?.maxHeight, 54);
    expect(tester.widget<Text>(find.text('Play')).style!.color, Colors.white);
    expect(tester.widget<Text>(find.text('Play')).style!.fontSize, 16);

    // Sources is the glass/outlined variant.
    final browse = ancestorOf<AnimatedContainer>(tester, find.text('Sources'));
    final browseDeco = browse.decoration! as BoxDecoration;
    expect(browseDeco.color, Colors.white.withValues(alpha: 0.06));
    expect(browseDeco.border!.top.color, Colors.white.withValues(alpha: 0.18));
    expect(browseDeco.border!.top.width, 1.2);

    await tester.tap(find.text('Play'));
    await tester.tap(find.text('Sources'));
    await tester.pump();
    expect(plays, 1);
    expect(browses, 1);
  });

  testWidgets('a series labels Browse "Episodes" with the list icon', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(movie(id: 'tt6000002', type: 'series', name: 'Pin Series')),
    );
    expect(find.text('Episodes'), findsOneWidget);
    expect(find.byIcon(Icons.list_alt_rounded), findsOneWidget);
    expect(find.text('Sources'), findsNothing);
  });

  testWidgets('showQuickPlay off drops Play and fills Browse instead', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(movie(id: 'tt6000003'), showQuickPlay: false),
    );
    expect(find.text('Play'), findsNothing);
    final browse = ancestorOf<AnimatedContainer>(tester, find.text('Sources'));
    expect((browse.decoration! as BoxDecoration).color, Colors.white);
    expect(tester.widget<Text>(find.text('Sources')).style!.color, Colors.black);
  });

  testWidgets('the watchlist button reflects and toggles its state', (
    tester,
  ) async {
    await pumpDetail(tester, screenFor(movie(id: 'tt6000004')));
    expect(find.text('My Watchlist'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
    final resting = ancestorOf<AnimatedContainer>(
      tester,
      find.text('My Watchlist'),
    );
    expect(
      (resting.decoration! as BoxDecoration).border!.top.color,
      Colors.white.withValues(alpha: 0.18),
    );

    // Tapping flips label, icon and the tinted resting border. The screen
    // updates optimistically, so this is the state the first frame after the
    // tap shows.
    await tester.tap(find.text('My Watchlist'));
    await tester.pump();
    expect(find.text('My Watchlist'), findsNothing);
    expect(find.text('In My Watchlist'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);
    final saved = ancestorOf<AnimatedContainer>(
      tester,
      find.text('In My Watchlist'),
    );
    expect(
      (saved.decoration! as BoxDecoration).border!.top.color,
      isNot(Colors.white.withValues(alpha: 0.18)),
    );
  });

  testWidgets('an unresolved resume lookup shows a spinner, not a label', (
    tester,
  ) async {
    final pending = Completer<({bool started, int? season, int? episode})>();
    try {
      await pumpDetail(
        tester,
        screenFor(
          movie(id: 'tt6000005'),
          resumeInfoLoader: () => pending.future,
        ),
      );

      expect(find.text('Play'), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      final spinner = find.byType(CircularProgressIndicator);
      expect(spinner, findsOneWidget);
      expect(tester.widget<CircularProgressIndicator>(spinner).strokeWidth, 2);
      expect(
        tester.widget<CircularProgressIndicator>(spinner).color,
        Colors.white,
      );
      // Non-compact: the indicator is 18px inside a 64px reserved box.
      expect(ancestorOf<SizedBox>(tester, spinner).width, 18);

      pending.complete((started: false, season: null, episode: null));
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Play'), findsOneWidget);
    } finally {
      // The screen holds this future for the life of the State. If an
      // assertion above throws, the completion below never runs, so release
      // it here: this is cleanup only, and the primary failure still
      // propagates out of the `finally`.
      if (!pending.isCompleted) {
        pending.complete((started: false, season: null, episode: null));
        // Drain the loader's continuation before teardown. Guarded so a
        // failure here cannot mask the assertion that actually failed.
        try {
          await tester.pump();
        } catch (_) {
          // Cleanup only.
        }
      }
    }
  });

  testWidgets('a resolved resume relabels Play with the season/episode tag', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(
        movie(id: 'tt6000006', type: 'series'),
        resumeInfoLoader: () async => (started: true, season: 3, episode: 4),
      ),
    );
    expect(find.text('Resume · S3E4'), findsOneWidget);
  });

  testWidgets('focus rings the primary button in gold and scales it', (
    tester,
  ) async {
    await pumpDetail(tester, screenFor(movie(id: 'tt6000007')));

    final playFocus = tester.widget<Focus>(
      find.byWidgetPredicate(
        (w) => w is Focus && w.focusNode?.debugLabel == 'detail-play',
      ),
    );
    playFocus.focusNode!.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final gold = DetailThemes.signal.focus;
    final play = ancestorOf<AnimatedContainer>(tester, find.text('Play'));
    final deco = play.decoration! as BoxDecoration;
    expect(deco.border!.top.color, gold);
    expect(deco.border!.top.width, 2.5);
    // Focused fill lerps 12% toward white.
    expect(deco.color, Color.lerp(const Color(0xFFE50914), Colors.white, 0.12));
    expect(deco.boxShadow!.single.blurRadius, 30);
    expect(deco.boxShadow!.single.spreadRadius, 2);
    expect(ancestorOf<AnimatedScale>(tester, find.text('Play')).scale, 1.035);
  });

  testWidgets('a narrow layout stacks the action row and goes compact', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(movie(id: 'tt6000008')),
      size: const Size(420, 900),
    );
    final play = ancestorOf<AnimatedContainer>(tester, find.text('Play'));
    expect(play.constraints?.maxHeight, 48);
    expect(tester.widget<Text>(find.text('Play')).style!.fontSize, 14);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded)).size,
      20,
    );
    // Stacked: Play sits above Sources rather than beside it.
    expect(
      tester.getTopLeft(find.text('Play')).dy,
      lessThan(tester.getTopLeft(find.text('Sources')).dy),
    );
  });

  // ── _QuickActions / _QuickAction ──────────────────────────────────────────

  testWidgets('Trakt quick actions wrap on wide with a TRAKT badge', (
    tester,
  ) async {
    TraktItemMenuAction? picked;
    await pumpDetail(
      tester,
      screenFor(
        movie(id: 'tt7000001'),
        traktMenuOptions: [
          trakt(TraktItemMenuAction.addToWatchlist, 'Watchlist', isTrakt: true),
          trakt(TraktItemMenuAction.markWatched, 'Watched'),
        ],
        onTraktAction: (a) => picked = a,
      ),
    );

    final header = find.text('QUICK ACTIONS');
    expect(header, findsOneWidget);
    final headerStyle = tester.widget<Text>(header).style!;
    expect(headerStyle.color, Colors.white.withValues(alpha: 0.5));
    expect(headerStyle.fontSize, 10);
    expect(headerStyle.fontWeight, FontWeight.w800);
    expect(headerStyle.letterSpacing, 2.2);

    expect(find.text('Watchlist'), findsOneWidget);
    expect(find.text('Watched'), findsOneWidget);
    // Only the isTrakt option carries the badge.
    expect(find.text('TRAKT'), findsOneWidget);
    final badge = ancestorOf<Container>(tester, find.text('TRAKT'));
    expect(
      (badge.decoration! as BoxDecoration).color,
      const Color(0xFFED1C24),
    );

    // Wide keeps the free wrap and the fixed 80px cell.
    final cell = ancestorOf<SizedBox>(tester, find.text('Watchlist'));
    expect(cell.width, 80);

    await tester.tap(find.text('Watched'));
    await tester.pump();
    expect(picked, TraktItemMenuAction.markWatched);
  });

  testWidgets('a focused quick action glows gold and answers select', (
    tester,
  ) async {
    TraktItemMenuAction? picked;
    await pumpDetail(
      tester,
      screenFor(
        movie(id: 'tt7000002'),
        traktMenuOptions: [trakt(TraktItemMenuAction.rate, 'Rate')],
        onTraktAction: (a) => picked = a,
      ),
    );

    await focusOn(tester, find.text('Rate'));

    final gold = DetailThemes.signal.focus;
    // The circle is the caption's sibling, not its ancestor — reach it through
    // the cell's scale wrapper.
    final ring = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('Rate'),
              matching: find.byType(AnimatedScale),
            )
            .first,
        matching: find.byType(AnimatedContainer),
      ),
    );
    final deco = ring.decoration! as BoxDecoration;
    expect(deco.shape, BoxShape.circle);
    expect(deco.color, Colors.white.withValues(alpha: 0.16));
    expect(deco.border!.top.color, gold);
    expect(deco.border!.top.width, 1.6);
    expect(deco.boxShadow!.single.blurRadius, 18);
    expect(ring.constraints?.maxWidth, 54);
    expect(ancestorOf<AnimatedScale>(tester, find.text('Rate')).scale, 1.06);
    expect(
      tester.widget<Text>(find.text('Rate')).style!.color,
      Colors.white.withValues(alpha: 1.0),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(picked, TraktItemMenuAction.rate);
  });

  testWidgets('the phone layout lays quick actions out as a 3-up grid', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(
        movie(id: 'tt7000003'),
        traktMenuOptions: [
          for (var i = 0; i < 4; i++)
            trakt(TraktItemMenuAction.values[i], 'Q$i'),
        ],
        onTraktAction: (_) {},
      ),
      size: const Size(420, 900),
    );

    // Grid cells expand into their column instead of the fixed 80px box.
    expect(ancestorOf<SizedBox>(tester, find.text('Q0')).width, isNull);
    // Three per row: Q0..Q2 share a top, Q3 drops to the next row.
    final y0 = tester.getTopLeft(find.text('Q0')).dy;
    expect(tester.getTopLeft(find.text('Q1')).dy, y0);
    expect(tester.getTopLeft(find.text('Q2')).dy, y0);
    expect(tester.getTopLeft(find.text('Q3')).dy, greaterThan(y0));
  });

  // ── _SimklQuickActions / _SimklQuickAction ────────────────────────────────

  testWidgets('Simkl actions are their own section with a SIMKL badge', (
    tester,
  ) async {
    SimklItemMenuAction? picked;
    await pumpDetail(
      tester,
      screenFor(
        movie(id: 'tt8000001'),
        simklMenuOptions: [
          simkl(SimklItemMenuAction.moveToWatching, 'Watching'),
          simkl(SimklItemMenuAction.rate, 'Rate'),
        ],
        onSimklAction: (a) => picked = a,
      ),
    );

    expect(find.text('SIMKL ACTIONS'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('SIMKL ACTIONS')).style!.letterSpacing,
      2.2,
    );
    // Every Simkl cell is badged, unlike Trakt's isTrakt opt-in.
    expect(find.text('SIMKL'), findsNWidgets(2));
    final badge = ancestorOf<Container>(tester, find.text('SIMKL').first);
    expect(
      (badge.decoration! as BoxDecoration).color,
      const Color(0xFF22D3EE),
    );
    expect(
      tester.widget<Text>(find.text('SIMKL').first).style!.color,
      Colors.black,
    );

    await tester.tap(find.text('Watching'));
    await tester.pump();
    expect(picked, SimklItemMenuAction.moveToWatching);
  });

  // ── _MdblistQuickActions ──────────────────────────────────────────────────

  testWidgets('MDBList actions render as labelled ActionChips', (tester) async {
    MdblistItemMenuAction? picked;
    await pumpDetail(
      tester,
      screenFor(
        movie(id: 'tt8000002'),
        mdblistMenuOptions: [
          mdblist(MdblistItemMenuAction.addToWatchlist, 'Watchlist'),
        ],
        onMdblistAction: (a) => picked = a,
      ),
    );

    expect(find.text('MDBLIST ACTIONS'), findsOneWidget);
    expect(find.byType(ActionChip), findsOneWidget);
    final chip = tester.widget<ActionChip>(find.byType(ActionChip));
    expect(chip.tooltip, 'MDBList Watchlist');
    expect(find.text('Watchlist'), findsOneWidget);

    await tester.tap(find.text('Watchlist'));
    await tester.pump();
    expect(picked, MdblistItemMenuAction.addToWatchlist);
  });

  // ── _RecCard ──────────────────────────────────────────────────────────────

  testWidgets('More Like This cards render, focus gold and report taps', (
    tester,
  ) async {
    StremioMeta? tapped;
    await pumpDetail(
      tester,
      screenFor(
        movie(id: 'tt9000001'),
        recommendationsLoader: () async => const [
          StremioMeta(id: 'tt9000101', type: 'movie', name: 'Neighbour One'),
        ],
        onRecommendationTap: (m) => tapped = m,
      ),
    );

    expect(find.text('More Like This'), findsOneWidget);
    // No poster in the payload, so the card shows its text fallback twice:
    // once inside the poster box, once as the caption underneath.
    expect(find.text('Neighbour One'), findsNWidgets(2));
    final caption = tester.widget<Text>(find.text('Neighbour One').last).style!;
    expect(caption.color, Colors.white.withValues(alpha: 0.82));
    expect(caption.fontSize, 12);

    final poster = ancestorOf<Container>(tester, find.text('Neighbour One').first);
    expect(poster.constraints?.maxWidth, 120);
    expect(poster.constraints?.maxHeight, 180);
    var deco = poster.decoration! as BoxDecoration;
    expect(deco.color, Colors.white.withValues(alpha: 0.06));
    expect(deco.border!.top.color, Colors.white.withValues(alpha: 0.10));
    expect(deco.border!.top.width, 0.5);

    await focusOn(tester, find.text('Neighbour One').last);

    deco =
        ancestorOf<Container>(tester, find.text('Neighbour One').first)
                .decoration!
            as BoxDecoration;
    expect(deco.border!.top.color, DetailThemes.signal.focus);
    expect(deco.border!.top.width, 2);
    expect(
      ancestorOf<AnimatedScale>(tester, find.text('Neighbour One').last).scale,
      1.05,
    );

    await tester.tap(find.text('Neighbour One').last);
    await tester.pump();
    expect(tapped?.id, 'tt9000101');
  });

  // ── _GlassCard ────────────────────────────────────────────────────────────

  testWidgets('the phone layout wraps the synopsis in a glass card', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      screenFor(movie(id: 'tt9100001', description: 'A short synopsis.')),
      size: const Size(420, 900),
    );

    final body = find.text('A short synopsis.');
    expect(body, findsOneWidget);
    final card = tester
        .widgetList<Container>(
          find.ancestor(of: body, matching: find.byType(Container)),
        )
        .firstWhere((c) {
          final d = c.decoration;
          return d is BoxDecoration &&
              d.borderRadius == BorderRadius.circular(16);
        });
    final deco = card.decoration! as BoxDecoration;
    expect(deco.color, Colors.white.withValues(alpha: 0.05));
    expect(deco.border!.top.color, Colors.white.withValues(alpha: 0.08));
    expect(deco.border!.top.width, 0.5);
    expect(deco.boxShadow!.single.blurRadius, 20);
    expect(card.padding, const EdgeInsets.all(18));
  });
}

// ── Canned HTTP ─────────────────────────────────────────────────────────────

class _CannedImdb extends HttpOverrides {
  _CannedImdb(this.imdbBody);

  final String imdbBody;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeClient(imdbBody);
}

class _FakeClient implements HttpClient {
  _FakeClient(this.imdbBody);

  final String imdbBody;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final isImdb = url.host == 'graphql.imdb.com';
    return _FakeRequest(url, isImdb ? imdbBody : '', isImdb ? 200 : 404);
  }

  @override
  void close({bool force = false}) {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.uri, this.body, this.status);

  @override
  final Uri uri;
  final String body;
  final int status;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  bool bufferOutput = true;

  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) {}

  @override
  void write(Object? object) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(body, status);

  @override
  Future<HttpClientResponse> get done => close();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.body, this.statusCode);

  final String body;

  @override
  final int statusCode;

  @override
  int get contentLength => utf8.encode(body).length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _FakeHeaders();

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => '';

  @override
  List<Cookie> get cookies => const [];

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([
    utf8.encode(body),
  ]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  final _store = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _store[name.toLowerCase()] = [value.toString()];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _store.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());

  @override
  List<String>? operator [](String name) => _store[name.toLowerCase()];

  @override
  String? value(String name) => _store[name.toLowerCase()]?.first;

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _store.forEach(action);

  @override
  void remove(String name, Object value) {}

  @override
  void removeAll(String name) => _store.remove(name.toLowerCase());

  @override
  ContentType? contentType;

  @override
  int contentLength = -1;

  @override
  bool chunkedTransferEncoding = false;

  @override
  bool persistentConnection = true;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
