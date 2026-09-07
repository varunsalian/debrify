import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/storage/app_style_prefs.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/detail_layout_showcase.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';

/// Origin pin for the presentational widgets that live in the tail of
/// `merged_series_detail_screen.dart` (the reveal/focus chrome, the action-row
/// buttons and pills, the rail tiles/cards, the trailer chip, the More menu and
/// the Trakt sheet's rows).
///
/// Every assertion drives the real [MergedDetailScreen] — the widgets are
/// private today, so the screen is the only door to them. Written before the
/// extraction so it pins the origin, and it must keep passing verbatim after
/// the widgets move under `lib/widgets/detail/`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── IMDb enrichment stub ────────────────────────────────────────────────
  // The Cast rail is the only region fed by `ImdbEnrichmentService.fetch`
  // (a POST to graphql.imdb.com), so the pin answers that one call with a
  // canned payload and 404s everything else. Cast entries deliberately carry
  // no primaryImage, so the tiles render their person-icon fallback rather
  // than reaching for a headshot.
  String imdbBody(List<String> starNames) => json.encode({
    'data': {
      'title': {
        'principalCredits': [
          {
            'category': {'text': 'Stars'},
            'credits': [
              for (final n in starNames)
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

  setUp(() {
    // Short single-word names on purpose: a name that wraps to the tile's
    // second line overflows the 92px rail by 2px in the origin, and this pin
    // is about the tile's content, not that (pre-existing) layout quirk.
    HttpOverrides.global = _CannedImdb(imdbBody(const ['Ada', 'Rex']));
  });
  tearDown(() => HttpOverrides.global = null);

  StremioAddon addon() => StremioAddon(
    id: 'pin-addon',
    name: 'Pin Addon',
    manifestUrl: '',
    baseUrl: '',
  );

  TraktMenuOption option(
    TraktItemMenuAction action,
    String label, {
    IconData icon = Icons.circle,
  }) => TraktMenuOption(
    action: action,
    icon: icon,
    color: Colors.amber,
    label: label,
    caption: label,
  );

  /// Pumps the real screen at a desktop-wide surface so the classic layout
  /// uses its left info pane (the `rev-*` reveals, Cast and More Like This
  /// rails all live there).
  Future<void> pumpScreen(
    WidgetTester tester,
    MergedDetailScreen screen, {
    String style = 'classic',
    Size size = const Size(1400, 1000),
    bool disableAnimations = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppStylePrefs.setDetailPageStyle(style);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppThemeScope(
          theme: AppThemes.legacy,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
        ),
        home: screen,
      ),
    );
  }

  Future<void> settleFrames(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  // ── _StaggerReveal ──────────────────────────────────────────────────────

  testWidgets('the title reveal fades and lifts, then settles at full opacity', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'reveal-movie',
          type: 'movie',
          name: 'Reveal Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
      ),
    );
    await tester.pump();

    double opacityOf(String key) => tester
        .widgetList<Opacity>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Opacity),
          ),
        )
        .first
        .opacity;
    // storage[13] is the matrix's y translation — Transform.translate's dy.
    double liftOf(String key) => tester
        .widgetList<Transform>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Transform),
          ),
        )
        .first
        .transform
        .storage[13];

    // The 55ms delay has not elapsed: the controller is still at 0.
    expect(opacityOf('rev-title'), 0.0);
    // …and the child sits 12px low.
    expect(liftOf('rev-title'), closeTo(12, 0.01));

    // Mid-flight: partially revealed, partially lifted. The 55ms delay timer
    // has to fire on its own frame before the controller starts ticking.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 140));
    final mid = opacityOf('rev-title');
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(1.0));
    expect(liftOf('rev-title'), greaterThan(0.0));

    // 55ms delay + 340ms duration, with room to spare.
    await tester.pump(const Duration(milliseconds: 400));
    expect(opacityOf('rev-title'), 1.0);
    expect(liftOf('rev-title'), 0.0);

    // The eyebrow runs with no delay, so it is always ahead of the title.
    expect(find.text('MOVIE'), findsOneWidget);
    await settleFrames(tester);
  });

  testWidgets('reduced motion drops the reveal controller entirely', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'reveal-static',
          type: 'movie',
          name: 'Static Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
      ),
      disableAnimations: true,
    );
    await tester.pump();

    // No Opacity/Transform wrapper at all — the child is rendered directly.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('rev-title')),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(find.text('Static Movie'), findsWidgets);
    await settleFrames(tester);
  });

  // ── _PrimaryButton / _GhostButton / _SourcePill / _FocusHalo ────────────

  testWidgets('the action row renders the primary pill, ghosts and source pill', (
    tester,
  ) async {
    var browses = 0;
    var binds = 0;
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'actions-movie',
          type: 'movie',
          name: 'Actions Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        onBrowse: () => browses++,
        boundSourceCount: (_) => 2,
        onSelectSource: (_) async => binds++,
      ),
    );
    await settleFrames(tester);

    // Primary pill: white ground, dark ink, play glyph.
    expect(find.text('Play'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);

    // Ghost button (movie-only Sources).
    expect(find.text('Sources'), findsOneWidget);
    expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
    await tester.tap(find.text('Sources'));
    await tester.pump();
    expect(browses, 1);

    // Source pill pluralises off the bound count.
    expect(find.text('2 sources'), findsOneWidget);
    expect(find.byIcon(Icons.link_rounded), findsOneWidget);
    await tester.tap(find.text('2 sources'));
    await tester.pump();
    expect(binds, 1);
    await settleFrames(tester);
  });

  testWidgets('an unbound title offers "Bind source" with the broken-link icon', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'unbound-movie',
          type: 'movie',
          name: 'Unbound Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        boundSourceCount: (_) => 0,
        onSelectSource: (_) async {},
      ),
    );
    await settleFrames(tester);

    expect(find.text('Bind source'), findsOneWidget);
    expect(find.byIcon(Icons.link_off_rounded), findsOneWidget);
    expect(find.text('1 source'), findsNothing);
    await settleFrames(tester);
  });

  testWidgets('a resolving primary pill shows a spinner instead of a label', (
    tester,
  ) async {
    final gate = Completer<({bool started, int? season, int? episode})>();
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'busy-series',
          type: 'series',
          name: 'Busy Series',
        ),
        addon: addon(),
        onResume: (_) async {},
        resumeInfoLoader: () => gate.future,
      ),
    );
    await tester.pump();

    expect(find.text('Start Watching'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    gate.complete((started: false, season: null, episode: null));
    await settleFrames(tester);
    expect(find.text('Start Watching'), findsOneWidget);
    await settleFrames(tester);
  });

  testWidgets('the focus halo paints a gold in-bounds ring on the focused pill', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'halo-movie',
          type: 'movie',
          name: 'Halo Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
      ),
    );
    await settleFrames(tester);

    // HomeTheme.focusGold — the same hue the episode rows use, so the cursor
    // does not change colour crossing panes.
    const gold = Color(0xFFFBBF24);
    int goldRings() {
      var n = 0;
      for (final c in tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      )) {
        final d = c.foregroundDecoration;
        if (d is BoxDecoration && d.border?.top.color == gold) n++;
      }
      return n;
    }

    expect(goldRings(), 0, reason: 'nothing is focused yet');

    // Focus the primary pill the way a remote would: the nearest enclosing
    // Focus of the label's context is the pill InkWell's own node.
    Focus.of(tester.element(find.text('Play'))).requestFocus();
    await tester.pumpAndSettle();

    expect(goldRings(), greaterThanOrEqualTo(1));
    // A foreground border, not a shadow — and rectangular (the pill's 999
    // radius), never the circle form the icon buttons use.
    final ring = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((c) => c.foregroundDecoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.border?.top.color == gold);
    expect(ring.shape, BoxShape.rectangle);
    expect(ring.border!.top.width, 2.5);
    expect(ring.boxShadow, isNull);
    await settleFrames(tester);
  });

  // ── _RoundIconButton + _QuickActionsMenu ────────────────────────────────

  testWidgets('the More button opens the labelled quick-actions sheet', (
    tester,
  ) async {
    TraktItemMenuAction? fired;
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'more-movie',
          type: 'movie',
          name: 'More Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        traktMenuOptions: [
          option(
            TraktItemMenuAction.selectSource,
            'Bind Source',
            icon: Icons.link_rounded,
          ),
        ],
        onTraktAction: (a) async => fired = a,
      ),
    );
    await settleFrames(tester);

    expect(find.byTooltip('More'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    // Header: the literal word "More" plus the title it applies to.
    expect(find.text('More'), findsOneWidget);
    expect(find.text('More Movie'), findsWidgets);
    // Every row carries its one-line description.
    expect(find.text('Bind Source'), findsOneWidget);
    expect(
      find.textContaining('Pin a specific torrent or file as this title'),
      findsOneWidget,
    );

    await tester.tap(find.text('Bind Source'));
    await tester.pumpAndSettle();
    expect(fired, TraktItemMenuAction.selectSource);
    await settleFrames(tester);
  });

  // ── _TrackerPill + _TraktSheet + sheet rows ─────────────────────────────

  testWidgets('the Trakt pill carries the live state and rating compartment', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'trakt-movie',
          type: 'movie',
          name: 'Trakt Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        traktMenuOptions: [
          option(TraktItemMenuAction.addToWatchlist, 'Add to Watchlist'),
        ],
        traktMenuBuilder: (status) =>
            buildTraktAddOnlyMenuOptions(isTraktAuthenticated: true),
        traktStatusLoader: () async => const TraktTitleStatus(
          inWatchlist: true,
          inCollection: true,
          rating: 8,
        ),
        onTraktAction: (_) async {},
      ),
    );
    await settleFrames(tester);

    expect(find.text('TRAKT'), findsOneWidget);
    expect(find.text('Watchlist · Collected'), findsOneWidget);
    expect(find.text('8'), findsWidgets);
    expect(find.byTooltip('Trakt options'), findsOneWidget);
    await settleFrames(tester);
  });

  testWidgets('the Trakt sheet renders switch rows, rating strip and copy', (
    tester,
  ) async {
    var status = const TraktTitleStatus(inWatchlist: true, rating: 7);
    final actions = <TraktItemMenuAction>[];
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'trakt-sheet-movie',
          type: 'movie',
          name: 'Sheet Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        traktMenuOptions: buildTraktAddOnlyMenuOptions(
          isTraktAuthenticated: true,
        ),
        traktMenuBuilder: (fresh) => buildTraktAddOnlyMenuOptions(
          isTraktAuthenticated: true,
          status: fresh,
        ),
        traktStatusLoader: () async => status,
        onTraktAction: (a) async {
          actions.add(a);
          if (a == TraktItemMenuAction.removeFromWatchlist) {
            status = const TraktTitleStatus(rating: 7);
          }
        },
        onTraktRate: (_) async {},
      ),
    );
    await settleFrames(tester);

    await tester.tap(find.byTooltip('Trakt options'));
    await tester.pumpAndSettle();

    // Header chrome.
    expect(find.text('Trakt'), findsOneWidget);
    expect(find.text('Sheet Movie'), findsWidgets);
    // Group labels are uppercased by the widget, not by the caller.
    expect(find.text('YOUR LIBRARY'), findsOneWidget);
    expect(find.text('RATING'), findsOneWidget);
    // Switch rows: label + the exact subtitle copy.
    // Two: the sheet's switch row plus the pill's state line behind it.
    expect(find.text('Watchlist'), findsNWidgets(2));
    expect(
      find.text('Synced to every device on your Trakt account'),
      findsOneWidget,
    );
    expect(find.text('Collection'), findsOneWidget);
    expect(
      find.text('Your library of everything you own or keep track of'),
      findsOneWidget,
    );
    // Rating strip: ten cells, the current score line and the clear affordance.
    for (var i = 1; i <= 10; i++) {
      expect(find.text('$i'), findsWidgets, reason: 'rating cell $i');
    }
    expect(find.text('Rated 7/10'), findsOneWidget);
    expect(find.text('Clear rating'), findsOneWidget);

    // Toggling the Watchlist row dispatches the remove action and the sheet
    // re-reads the live status rather than guessing.
    await tester.tap(find.text('Watchlist').last);
    await tester.pumpAndSettle();
    expect(actions, contains(TraktItemMenuAction.removeFromWatchlist));
    await settleFrames(tester);
  });

  // ── _CastTile ───────────────────────────────────────────────────────────

  testWidgets('cast tiles render the member names with the person fallback', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'tt7770001',
          imdbId: 'tt7770001',
          type: 'movie',
          name: 'Cast Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
      ),
    );
    await settleFrames(tester, frames: 20);

    expect(find.text('CAST'), findsOneWidget);
    // Each name renders twice: once in the Credits "Stars" block, once as a
    // cast tile. The tile is the 11px, two-line, centred one.
    // The Credits block joins the stars into one line, so the only standalone
    // "Ada Stone" text is the cast tile's own label.
    final ada = tester.widgetList<Text>(find.text('Ada')).toList();
    expect(ada.length, 1);
    expect(
      ada.any(
        (t) =>
            t.style?.fontSize == 11 &&
            t.maxLines == 2 &&
            t.textAlign == TextAlign.center,
      ),
      isTrue,
      reason: 'the cast tile label',
    );
    expect(find.text('Rex'), findsOneWidget);
    // No headshot url in the payload → the tile paints its person glyph.
    expect(find.byIcon(Icons.person), findsNWidgets(2));
    await settleFrames(tester);
  });

  // ── _ScrollAnchor ───────────────────────────────────────────────────────

  testWidgets('focusing the action row snaps the info column back to the top', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'tt7770002',
          imdbId: 'tt7770002',
          type: 'movie',
          name: 'Anchor Movie',
        ),
        addon: addon(),
        isTelevision: true,
        onResume: (_) async {},
      ),
      size: const Size(1000, 420),
    );
    await settleFrames(tester, frames: 20);

    final column = find
        .ancestor(
          of: find.byKey(const ValueKey('rev-title')),
          matching: find.byType(Scrollable),
        )
        .first;
    double offset() =>
        tester.state<ScrollableState>(column).position.pixels;

    // Start with nothing focused (a TV movie autofocuses its Play pill) and the
    // column scrolled away from the top.
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.drag(column, const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(offset(), greaterThan(0.0));

    // Coming back to the action row snaps the whole column to offset 0, so the
    // eyebrow/title/meta above it are revealed again.
    Focus.of(tester.element(find.text('Play'))).requestFocus();
    await tester.pumpAndSettle();
    expect(offset(), 0.0);
    await settleFrames(tester);
  });

  // ── _RecCard + _RailEdgeTrap ────────────────────────────────────────────

  testWidgets('rec cards tap through and the rail traps LEFT at its first card', (
    tester,
  ) async {
    StremioMeta? tapped;
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'recs-movie',
          type: 'movie',
          name: 'Recs Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        recommendationsLoader: () async => const [
          StremioMeta(id: 'rec-a', type: 'movie', name: 'Rec A'),
          StremioMeta(id: 'rec-b', type: 'movie', name: 'Rec B'),
        ],
        onRecommendationTap: (rec) => tapped = rec,
      ),
    );
    await settleFrames(tester, frames: 20);

    expect(find.text('MORE LIKE THIS'), findsOneWidget);
    final cards = find.byType(AspectRatio);
    expect(cards, findsNWidgets(2));

    // Focus the first card, then press LEFT: the edge trap eats it, so focus
    // stays exactly where it was instead of escaping the rail.
    Focus.of(tester.element(cards.first)).requestFocus();
    await tester.pumpAndSettle();
    final focusedBefore = FocusManager.instance.primaryFocus;
    expect(focusedBefore, isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(focusedBefore));

    // RIGHT is not trapped on a non-last card: it walks to the next one.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(same(focusedBefore)));

    // And the card is still a live tap target.
    await tester.tap(cards.first, warnIfMissed: false);
    await tester.pump();
    expect(tapped?.id, 'rec-a');
    await settleFrames(tester);
  });

  // ── _TrailerPlayingChip ─────────────────────────────────────────────────

  testWidgets('the ambient trailer publishes a chip and flips the ghost label', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'trailer-movie',
          type: 'movie',
          name: 'Trailer Movie',
          trailerYtId: 'synthetic-trailer',
        ),
        addon: addon(),
        onResume: (_) async {},
      ),
      style: 'showcase',
      disableAnimations: true,
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Trailer playing'), findsNothing);

    final backdrop = tester.widget<HeroTrailerBackdrop>(
      find.byType(HeroTrailerBackdrop),
    );
    backdrop.onPlayingChanged!(true);
    await tester.pump();

    expect(find.text('Trailer playing'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);

    tester
        .widget<HeroTrailerBackdrop>(find.byType(HeroTrailerBackdrop))
        .onPlayingChanged!(false);
    await tester.pump();
    expect(find.text('Trailer playing'), findsNothing);
    await settleFrames(tester);
  });

  // ── _AmbientStill ───────────────────────────────────────────────────────

  testWidgets('the published ambient still paints the focused episode frame', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'still-movie',
          type: 'movie',
          name: 'Still Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
      ),
      style: 'showcase',
      disableAnimations: true,
    );
    await settleFrames(tester);

    const url = 'https://stills.example/frame.jpg';
    expect(find.byKey(const ValueKey(url)), findsNothing);

    tester
        .widget<DetailShowcase>(find.byType(DetailShowcase))
        .model
        .onAmbientStill(url);
    await tester.pump();

    expect(find.byKey(const ValueKey(url)), findsOneWidget);
    await settleFrames(tester);
  });
}

/// Answers only the IMDb GraphQL endpoint; every other host 404s so nothing in
/// the pin can reach the network.
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
  ]).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

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
