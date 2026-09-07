import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/mdblist/mdblist_menu_helpers.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/simkl/simkl_menu_helpers.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage/app_style_prefs.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/detail/detail_action_buttons.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:debrify/widgets/tracker_brand_marks.dart';
import 'package:debrify/widgets/trakt/trakt_menu_helpers.dart';

/// Origin pin for the merged detail screen's tracker-status block and its
/// trailer lifecycle: the Trakt/Simkl/MDBList pill labels and tracked flags,
/// the app-vs-tracker split of the incoming Trakt option list, the three
/// quick-actions presenters and the status re-read that follows an MDBList
/// action, plus the Trailer button's load/play state transitions.
///
/// Everything is asserted through the real [MergedDetailScreen]; the logic is
/// private to its State today, so the screen is the only door to it. Written
/// before the extraction, and it must keep passing verbatim afterwards.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Nothing in this pin is allowed to reach the network: every host 404s.
    HttpOverrides.global = _CannedNet();
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
    caption: 'caption for $label',
  );

  MdblistMenuOption mdblistOption(
    MdblistItemMenuAction action,
    String label,
  ) => MdblistMenuOption(
    action: action,
    icon: Icons.circle,
    color: Colors.purple,
    label: label,
    caption: 'caption for $label',
  );

  Future<void> pumpScreen(
    WidgetTester tester,
    MergedDetailScreen screen, {
    String style = 'classic',
    Size size = const Size(1400, 1000),
    bool disableAnimations = true,
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

  /// The state line inside a tracker pill: the pill renders brand + state as
  /// two texts, so the state is read off the pill by its brand neighbour.
  double markOpacity<T extends Widget>(WidgetTester tester) {
    final w = tester.widget<T>(find.byType(T));
    if (w is TraktMark) return w.opacity;
    if (w is SimklMark) return w.opacity;
    if (w is MdblistMark) return w.opacity;
    throw StateError('not a brand mark');
  }

  // ── Trakt pill label ────────────────────────────────────────────────────

  testWidgets('the Trakt pill says "Checking…" until the loader answers', (
    tester,
  ) async {
    final gate = Completer<TraktTitleStatus?>();
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'trakt-checking',
          type: 'movie',
          name: 'Checking Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        traktMenuOptions: [
          option(TraktItemMenuAction.addToWatchlist, 'Add to Watchlist'),
        ],
        traktStatusLoader: () => gate.future,
        onTraktAction: (_) async {},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('TRAKT'), findsOneWidget);
    expect(find.text('Checking…'), findsOneWidget);
    // Untracked form while the answer is out: the mark is dimmed.
    expect(markOpacity<TraktMark>(tester), 0.55);

    gate.complete(
      const TraktTitleStatus(inWatchlist: true, inCollection: true, rating: 9),
    );
    await settleFrames(tester);

    expect(find.text('Checking…'), findsNothing);
    expect(find.text('Watchlist · Collected'), findsOneWidget);
    expect(markOpacity<TraktMark>(tester), 1.0);
    await settleFrames(tester);
  });

  testWidgets('the Trakt pill caps the joined state at two relationships', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'trakt-three',
          type: 'movie',
          name: 'Three Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        traktMenuOptions: [
          option(TraktItemMenuAction.addToWatchlist, 'Add to Watchlist'),
        ],
        traktStatusLoader: () async => const TraktTitleStatus(
          inWatchlist: true,
          inCollection: true,
          watched: true,
        ),
        onTraktAction: (_) async {},
      ),
    );
    await settleFrames(tester);

    // Watchlist + Collected + Watched, capped at the first two.
    expect(find.text('Watchlist · Collected'), findsOneWidget);
    expect(find.textContaining('Watched'), findsNothing);
    await settleFrames(tester);
  });

  testWidgets('a rating-only Trakt status reads "Rated" and counts as tracked', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'trakt-rated',
          type: 'movie',
          name: 'Rated Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        traktMenuOptions: [
          option(TraktItemMenuAction.addToWatchlist, 'Add to Watchlist'),
        ],
        traktStatusLoader: () async => const TraktTitleStatus(rating: 6),
        onTraktAction: (_) async {},
      ),
    );
    await settleFrames(tester);

    expect(find.text('Rated'), findsOneWidget);
    // The rating rides in the pill's own compartment, not in the state line.
    expect(find.text('6'), findsWidgets);
    expect(markOpacity<TraktMark>(tester), 1.0);
    await settleFrames(tester);
  });

  testWidgets(
    'an all-false Trakt status with no watched answer reads "Status unavailable"',
    (tester) async {
      await pumpScreen(
        tester,
        MergedDetailScreen(
          item: const StremioMeta(
            id: 'trakt-unknown',
            type: 'movie',
            name: 'Unknown Movie',
          ),
          addon: addon(),
          onResume: (_) async {},
          traktMenuOptions: [
            option(TraktItemMenuAction.addToWatchlist, 'Add to Watchlist'),
          ],
          // watched/seriesFullyWatched both null → titleWatched is null.
          traktStatusLoader: () async => const TraktTitleStatus(),
          onTraktAction: (_) async {},
        ),
      );
      await settleFrames(tester);

      expect(find.text('Status unavailable'), findsOneWidget);
      // Untracked: nothing is set.
      expect(markOpacity<TraktMark>(tester), 0.55);
      await settleFrames(tester);
    },
  );

  testWidgets('a known-unwatched Trakt status reads "Not tracked"', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'trakt-untracked',
          type: 'movie',
          name: 'Untracked Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        traktMenuOptions: [
          option(TraktItemMenuAction.addToWatchlist, 'Add to Watchlist'),
        ],
        traktStatusLoader: () async => const TraktTitleStatus(watched: false),
        onTraktAction: (_) async {},
      ),
    );
    await settleFrames(tester);

    expect(find.text('Not tracked'), findsOneWidget);
    await settleFrames(tester);
  });

  testWidgets('with no status loader at all the pill never says "Checking…"', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'trakt-noloader',
          type: 'movie',
          name: 'No Loader Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        traktMenuOptions: [
          option(TraktItemMenuAction.addToWatchlist, 'Add to Watchlist'),
        ],
        onTraktAction: (_) async {},
      ),
    );
    await tester.pump();

    expect(find.text('Checking…'), findsNothing);
    expect(find.text('Not tracked'), findsOneWidget);
    await settleFrames(tester);
  });

  // ── Simkl pill label ────────────────────────────────────────────────────

  testWidgets('the Simkl pill maps each raw status to its display label', (
    tester,
  ) async {
    Future<void> pumpWith(String raw) async {
      await pumpScreen(
        tester,
        MergedDetailScreen(
          // A fresh key per case: without it the element tree reuses the one
          // State and never re-runs the status load.
          key: ValueKey('simkl-$raw'),
          item: StremioMeta(
            id: 'simkl-$raw',
            type: 'movie',
            name: 'Simkl Movie',
          ),
          addon: addon(),
          onResume: (_) async {},
          simklMenuOptions: buildSimklMenuOptions(isSimklAuthenticated: true),
          simklStatusLoader: () async => SimklTitleStatus(currentStatus: raw),
          onSimklAction: (_) async {},
        ),
      );
      await settleFrames(tester);
    }

    const cases = <String, String>{
      'plantowatch': 'Plan to Watch',
      'watching': 'Watching',
      'hold': 'On Hold',
      'completed': 'Completed',
      'dropped': 'Dropped',
      // Unknown statuses pass through verbatim rather than being swallowed.
      'wishlist': 'wishlist',
    };
    for (final entry in cases.entries) {
      await pumpWith(entry.key);
      expect(find.text('SIMKL'), findsOneWidget, reason: entry.key);
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      expect(markOpacity<SimklMark>(tester), 1.0, reason: entry.key);
    }
    await settleFrames(tester);
  });

  testWidgets('the Simkl pill checks, then rates, then falls to untracked', (
    tester,
  ) async {
    final gate = Completer<SimklTitleStatus?>();
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'simkl-rated',
          type: 'movie',
          name: 'Simkl Rated',
        ),
        addon: addon(),
        onResume: (_) async {},
        simklMenuOptions: buildSimklMenuOptions(isSimklAuthenticated: true),
        simklStatusLoader: () => gate.future,
        onSimklAction: (_) async {},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Checking…'), findsOneWidget);
    expect(markOpacity<SimklMark>(tester), 0.55);

    // No list status but a rating: Simkl is single-state, so the label is the
    // bare word rather than a join.
    gate.complete(const SimklTitleStatus(rating: 4));
    await settleFrames(tester);

    expect(find.text('Rated'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    expect(markOpacity<SimklMark>(tester), 1.0);
    await settleFrames(tester);
  });

  testWidgets('a null Simkl answer resolves the pill to "Not tracked"', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'simkl-null',
          type: 'movie',
          name: 'Simkl Null',
        ),
        addon: addon(),
        onResume: (_) async {},
        simklMenuOptions: buildSimklMenuOptions(isSimklAuthenticated: true),
        // Null: the loader answered, but with nothing.
        simklStatusLoader: () async => null,
        onSimklAction: (_) async {},
      ),
    );
    await settleFrames(tester);

    expect(find.text('Not tracked'), findsOneWidget);
    expect(markOpacity<SimklMark>(tester), 0.55);
    await settleFrames(tester);
  });

  // ── The app-vs-tracker split of the one incoming option list ────────────

  testWidgets('app-owned actions go to More; only tracker actions reach Trakt', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'split-movie',
          type: 'movie',
          name: 'Split Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        traktMenuOptions: [
          option(TraktItemMenuAction.selectSource, 'Bind Source'),
          option(TraktItemMenuAction.addToStremioTv, 'Add to Stremio TV'),
          option(TraktItemMenuAction.playRandomEpisode, 'Random Episode'),
          option(TraktItemMenuAction.searchPacks, 'Search Packs'),
          option(TraktItemMenuAction.removeFromPlayback, 'Remove From CW'),
          option(TraktItemMenuAction.addToWatchlist, 'Add to Watchlist'),
          option(TraktItemMenuAction.addToCollection, 'Add to Collection'),
        ],
        traktStatusLoader: () async => const TraktTitleStatus(watched: false),
        onTraktAction: (_) async {},
      ),
    );
    await settleFrames(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    // Exactly the five app-owned actions, and nothing Trakt-flavoured.
    expect(find.text('Bind Source'), findsOneWidget);
    expect(find.text('Add to Stremio TV'), findsOneWidget);
    expect(find.text('Random Episode'), findsOneWidget);
    expect(find.text('Search Packs'), findsOneWidget);
    expect(find.text('Remove From CW'), findsOneWidget);
    expect(find.text('Add to Watchlist'), findsNothing);
    expect(find.text('Add to Collection'), findsNothing);

    // The app sheet closes on selection.
    await tester.tap(find.text('Search Packs'));
    await tester.pumpAndSettle();
    expect(find.text('Search Packs'), findsNothing);

    // The Trakt sheet is the mirror image: no app-owned rows in it.
    await tester.tap(find.byTooltip('Trakt options'));
    await tester.pumpAndSettle();
    expect(find.text('Bind Source'), findsNothing);
    expect(find.text('Search Packs'), findsNothing);
    expect(find.text('Trakt'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await settleFrames(tester);
  });

  testWidgets('the Simkl pill opens the Simkl sheet, not the Trakt one', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'simkl-sheet',
          type: 'movie',
          name: 'Simkl Sheet Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        traktMenuOptions: [
          option(TraktItemMenuAction.addToWatchlist, 'Add to Watchlist'),
        ],
        traktStatusLoader: () async => const TraktTitleStatus(watched: false),
        onTraktAction: (_) async {},
        simklMenuOptions: buildSimklMenuOptions(isSimklAuthenticated: true),
        simklMenuBuilder: (fresh) =>
            buildSimklMenuOptions(isSimklAuthenticated: true, status: fresh),
        simklStatusLoader: () async =>
            const SimklTitleStatus(currentStatus: 'watching'),
        onSimklAction: (_) async {},
      ),
    );
    await settleFrames(tester);

    expect(find.byTooltip('Simkl options'), findsOneWidget);
    await tester.tap(find.byTooltip('Simkl options'));
    await tester.pumpAndSettle();

    // Simkl's five statuses render as an exclusive group, so the sheet shows
    // its own brand header and the status set — never Trakt's library switches.
    expect(find.text('Simkl'), findsOneWidget);
    expect(find.text('Trakt'), findsNothing);
    expect(find.text('Plan to Watch'), findsWidgets);
    expect(find.text('Collection'), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await settleFrames(tester);
  });

  // ── The status re-read after an action ──────────────────────────────────

  testWidgets('an MDBList action re-reads the status and refreshes the pill', (
    tester,
  ) async {
    var status = const MdblistTitleStatus(id: 'mdb-1');
    final actions = <MdblistItemMenuAction>[];
    var loads = 0;
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'mdblist-movie',
          type: 'movie',
          name: 'MDBList Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
        mdblistMenuOptions: [
          mdblistOption(MdblistItemMenuAction.addToWatchlist, 'Add to List'),
          mdblistOption(MdblistItemMenuAction.markWatched, 'Mark Watched'),
        ],
        mdblistStatusLoader: () async {
          loads++;
          return status;
        },
        onMdblistAction: (a) async {
          actions.add(a);
          if (a == MdblistItemMenuAction.addToWatchlist) {
            status = const MdblistTitleStatus(id: 'mdb-1', inWatchlist: true);
          }
        },
      ),
    );
    await settleFrames(tester);

    expect(find.text('MDBLIST'), findsOneWidget);
    expect(find.text('Not tracked'), findsOneWidget);
    expect(markOpacity<MdblistMark>(tester), 0.55);
    expect(loads, 1);

    await tester.tap(find.byTooltip('MDBList options'));
    await tester.pumpAndSettle();

    // The sheet is a plain labelled list under the brand word.
    expect(find.text('MDBList'), findsOneWidget);
    expect(find.text('MDBList Movie'), findsWidgets);
    expect(find.text('Add to List'), findsOneWidget);
    expect(find.text('Mark Watched'), findsOneWidget);

    await tester.tap(find.text('Add to List'));
    await tester.pumpAndSettle();

    // Action dispatched, status re-read, sheet closed, pill updated.
    expect(actions, [MdblistItemMenuAction.addToWatchlist]);
    expect(loads, 2);
    expect(find.text('Add to List'), findsNothing);
    expect(find.text('Watchlist'), findsOneWidget);
    expect(markOpacity<MdblistMark>(tester), 1.0);
    await settleFrames(tester);
  });

  testWidgets('the MDBList pill joins its flags and caps them at two', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'mdblist-join',
          type: 'movie',
          name: 'MDBList Join',
        ),
        addon: addon(),
        onResume: (_) async {},
        mdblistMenuOptions: [
          mdblistOption(MdblistItemMenuAction.markWatched, 'Mark Watched'),
        ],
        mdblistStatusLoader: () async => const MdblistTitleStatus(
          id: 'mdb-2',
          inWatchlist: true,
          collected: true,
          watched: true,
          dropped: true,
        ),
        onMdblistAction: (_) async {},
      ),
    );
    await settleFrames(tester);

    expect(find.text('Watchlist · Collected'), findsOneWidget);
    expect(markOpacity<MdblistMark>(tester), 1.0);
    await settleFrames(tester);
  });

  // ── Trailer lifecycle ───────────────────────────────────────────────────

  testWidgets('no trailer id means no Trailer button at all', (tester) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'no-trailer',
          type: 'movie',
          name: 'No Trailer Movie',
        ),
        addon: addon(),
        onResume: (_) async {},
      ),
    );
    await settleFrames(tester);

    expect(find.text('Trailer'), findsNothing);
    expect(find.byIcon(Icons.movie_outlined), findsNothing);
    await settleFrames(tester);
  });

  testWidgets('reduced motion skips the autoplay pipeline: button, no spinner', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'trailer-reduced',
          type: 'movie',
          name: 'Reduced Trailer',
          trailerYtId: 'pin-trailer-id',
        ),
        addon: addon(),
        onResume: (_) async {},
      ),
      // disableAnimations: true is already the default here — the backdrop
      // refuses to autoplay under OS reduced motion, so the whole resolve /
      // spinner pipeline is skipped rather than spinning forever.
    );
    await settleFrames(tester);

    expect(find.text('Trailer'), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.text('Watch Trailer'), findsNothing);
    // Not resolving: the ghost button shows its label, not a spinner.
    expect(find.text('Trailer playing'), findsNothing);
    await settleFrames(tester);
  });

  testWidgets('the ambient trailer flips the button label and raises the chip', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'trailer-ambient',
          type: 'movie',
          name: 'Ambient Trailer',
          trailerYtId: 'pin-trailer-id',
        ),
        addon: addon(),
        onResume: (_) async {},
      ),
    );
    await settleFrames(tester);

    expect(find.text('Trailer playing'), findsNothing);
    expect(find.text('Trailer'), findsOneWidget);

    tester
        .widget<HeroTrailerBackdrop>(find.byType(HeroTrailerBackdrop))
        .onPlayingChanged!(true);
    await tester.pump();

    // "it's playing, tap to view"
    expect(find.text('Trailer playing'), findsOneWidget);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(find.text('Watch Trailer'), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline_rounded), findsOneWidget);
    expect(find.text('Trailer'), findsNothing);

    tester
        .widget<HeroTrailerBackdrop>(find.byType(HeroTrailerBackdrop))
        .onPlayingChanged!(false);
    await tester.pump();

    expect(find.text('Trailer playing'), findsNothing);
    expect(find.text('Watch Trailer'), findsNothing);
    await settleFrames(tester);
  });

  testWidgets('tapping Trailer with no promotable player resolves and fails', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      MergedDetailScreen(
        item: const StremioMeta(
          id: 'trailer-tap',
          type: 'movie',
          name: 'Tap Trailer',
          trailerYtId: 'pin-trailer-id',
        ),
        addon: addon(),
        onResume: (_) async {},
      ),
    );
    await settleFrames(tester);

    bool trailerBusy() => tester
        .widgetList<DetailGhostButton>(find.byType(DetailGhostButton))
        .firstWhere((b) => b.label == 'Trailer')
        .busy;

    expect(trailerBusy(), isFalse);

    await tester.tap(find.text('Trailer'));
    await tester.pump();

    // Busy: the button carries a spinner alongside its label, and the
    // "Loading trailer…" snackbar goes up.
    expect(find.text('Loading trailer…'), findsOneWidget);
    expect(trailerBusy(), isTrue);

    // Both resolvers are offline in this pin, so the launch bails with the
    // failure snackbar and the button comes back.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('Couldn\'t load trailer'), findsOneWidget);
    expect(trailerBusy(), isFalse);
    await settleFrames(tester);
  });
}

/// 404s every host so nothing in the pin can reach the network.
class _CannedNet extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeClient();
}

class _FakeClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeRequest(url);

  @override
  void close({bool force = false}) {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.uri);

  @override
  final Uri uri;

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
  Future<HttpClientResponse> close() async => _FakeResponse();

  @override
  Future<HttpClientResponse> get done => close();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode = 404;

  @override
  int get contentLength => 0;

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
  }) => Stream<List<int>>.fromIterable(<List<int>>[<int>[]]).listen(
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
