import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/imdb_parents_guide_service.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/detail/detail_layout_showcase.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Public-parts fixture derived from the original detail_showcase_test builders.
/// All resources belong to the host; no artwork, network or trailer engine.
class ShowcaseFixture {
  final List<FocusNode> _owned = [];
  final List<String> calls = [];
  late final back = node('back');
  late final primary = node('primary');
  late final actions = nodes(8, 'action');
  final scroll = ScrollController();

  FocusNode node(String label) {
    final value = FocusNode(debugLabel: 'showcase-$label');
    _owned.add(value);
    return value;
  }

  List<FocusNode> nodes(int count, String label) => [
    for (var i = 0; i < count; i++) node('$label-$i'),
  ];

  TraktEpisode episode(int n) => TraktEpisode(
    season: 2,
    number: n,
    title: 'Episode $n',
    overview: 'Synopsis $n.',
    firstAired: DateTime.utc(2026, 1, n).toIso8601String(),
    runtime: 47,
  );

  EpisodesPanelView view({void Function(int)? selectSeason}) {
    final eps = [episode(1), episode(2)];
    return EpisodesPanelView(
      seasons: [
        const TraktSeason(number: 1, episodeCount: 2, episodes: []),
        TraktSeason(number: 2, episodeCount: 2, episodes: eps),
      ],
      selectedSeasonNumber: 2,
      episodes: eps,
      loading: false,
      unavailable: false,
      showImageUrl: null,
      generation: 1,
      landing: eps.first,
      focusIntent: EpisodeFocusIntent.none,
      progressOf: (_) => null,
      isNext: (e) => e.number == 1,
      play: (_) => calls.add('play'),
      options: (_) => calls.add('options'),
      stepSeason: (_) {},
      selectSeason: selectSeason ?? (n) => calls.add('season:$n'),
      onLeftEdge: null,
      onRetry: () => calls.add('retry'),
      onSearchForSources: () => calls.add('search'),
    );
  }

  DetailModel model({
    bool movie = true,
    bool trailer = true,
    bool longPress = true,
    bool allActions = false,
    VoidCallback? onPrimary,
    VoidCallback? onHold,
    ParentsGuideResult? guide,
    ImdbEnrichment? extra,
    List<SeriesSource> sources = const [],
    List<StremioMeta> recs = const [],
  }) => DetailModel(
    item: StremioMeta(
      id: 'tt0903747',
      imdbId: 'tt0903747',
      type: movie ? 'movie' : 'series',
      name: movie ? 'Original Movie' : 'Original Series',
      description: 'A fixed original-code synopsis.',
      year: '2026',
      genres: const ['Crime', 'Drama'],
    ),
    metadataPreferences: MetadataPreferences(features: {}),
    isMovie: movie,
    isTelevision: false,
    accent: const Color(0xFFABA124),
    imdbExtra: extra,
    parentsGuide: guide,
    recommendations: recs,
    openingDataReady: true,
    primaryLabel: 'Resume',
    sourceCount: sources.length,
    boundSources: sources,
    hasTrailer: trailer,
    trailerBusy: false,
    trailerPlaying: false,
    hasTrakt: allActions,
    traktTracked: false,
    traktLabel: 'Watchlist',
    traktRating: null,
    hasSimkl: allActions,
    simklTracked: false,
    simklLabel: 'Not tracked',
    simklRating: null,
    hasMdblist: allActions,
    mdblistTracked: false,
    mdblistLabel: 'Watchlist',
    mdblistRating: null,
    showPrimary: true,
    onPrimary: onPrimary ?? () => calls.add('primary'),
    onPrimaryLongPress: longPress ? (onHold ?? () => calls.add('hold')) : null,
    onBrowse: allActions ? () => calls.add('browse') : null,
    onTrailer: () => calls.add('trailer'),
    onSelectSource: null,
    onAppMenu: allActions ? () => calls.add('more') : null,
    onMetadataExplore: allActions ? () => calls.add('explore') : null,
    onTraktMenu: null,
    onSimklMenu: null,
    onMdblistMenu: null,
    onToggleMyWatchlist: allActions ? () => calls.add('watchlist') : null,
    onTrackers: allActions ? () => calls.add('trackers') : null,
    onTrackersSecondary: allActions ? () => calls.add('secondary') : null,
    onTrackersTertiary: allActions ? () => calls.add('tertiary') : null,
    onManageSources: () => calls.add('manage'),
    onRecommendationTap: (_) => calls.add('recommendation'),
    onAmbientStill: (_) {},
    focus: DetailFocusCoordinator(backNode: back, primaryEntry: primary),
  );

  Widget identity({DetailModel? value, double height = 320}) =>
      ShowcaseIdentity(
        model: value ?? model(),
        primaryNode: primary,
        actionNodes: actions,
        onFocused: () => calls.add('focused'),
        height: height,
      );

  Widget host(
    Widget child, {
    Size size = const Size(960, 540),
    bool compact = false,
    bool touch = false,
  }) => MaterialApp(
    locale: const Locale('en', 'US'),
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.noScaling),
      child: AppThemeScope(
        theme: AppTheme.fromDetail(DetailThemes.byId('signal')),
        child: ShowcaseMetricsScope(
          metrics: ShowcaseMetrics(size.width, compact: compact, touch: touch),
          child: Scaffold(body: child),
        ),
      ),
    ),
  );

  Widget page({required DetailModel value, bool dpad = true}) => DetailShowcase(
    model: value,
    dpad: dpad,
    episodesHost: value.isMovie
        ? null
        : (builder) => Builder(builder: (context) => builder(context, view())),
  );

  void dispose() {
    scroll.dispose();
    for (final n in _owned) {
      n.dispose();
    }
  }
}

ParentsGuideResult showcaseGuide({String prefix = ''}) => ParentsGuideResult(
  categories: [
    for (var i = 0; i < 3; i++)
      ParentsGuideCategory(
        id: 'category-$i',
        label: '${prefix}Category $i',
        severity: ['Mild', 'Moderate', 'Severe'][i],
        severityVotes: 10,
        totalVotes: 12,
        items: [
          ParentsGuideItem(text: '${prefix}Plain $i'),
          ParentsGuideItem(text: '${prefix}Spoiler $i', isSpoiler: true),
        ],
      ),
  ],
);

Future<void> showcaseCase(
  WidgetTester tester,
  Future<void> Function(ShowcaseFixture) body, {
  Size size = const Size(960, 540),
  bool television = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  PlatformUtil.debugSetAndroidTvCached(television);
  PlatformUtil.debugSetTvOS(false);
  ParallaxTravel.resetForTest();
  final fixture = ShowcaseFixture();
  try {
    await body(fixture);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    fixture.dispose();
    PlatformUtil.debugSetAndroidTvCached(null);
    PlatformUtil.debugSetTvOS(null);
    ParallaxTravel.resetForTest();
  }
}

Future<void> showcasePump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 240));
  await tester.pump();
}
