import '../application/home_layout_preference_dependencies.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../search/models/keyword_snapshot.dart';
import '../../search/presentation/search_session_lifecycle.dart';
import '../models/home_return_snapshot.dart';
import '../models/home_board_configuration.dart';
import '../models/home_catalog_session.dart';
import '../models/home_continuation_session.dart';
import '../models/home_display_preferences.dart';
import '../application/home_return_dependencies.dart';
import '../application/home_collections_dependencies.dart';
import '../application/home_default_view_dependencies.dart';
import '../application/home_display_preferences_controller.dart';
import 'home_board_bindings.dart';
import 'home_media_bindings.dart';
import 'home_favorite_bindings.dart';
import 'home_continuation_bindings.dart';
import 'home_board_section.dart';
import 'home_board_configuration_section.dart';
import 'home_display_section.dart';
import 'home_hero_preview.dart';

typedef HomeViewBindingsDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function() hideWatched,
  SearchSessionLifecycle Function() search,
});

/// Owns the Home view's provider bindings and immutable startup restore decision.
/// Initialization methods are called at their original points, around Search setup.
class HomeViewBindings {
  HomeViewBindings(
    this.ref,
    this._deps,
    this._initial,
    this._board,
    this._configuration,
    this._display,
    this._preview,
  );
  final WidgetRef ref;
  final HomeViewBindingsDeps _deps;
  final HomeBoardConfiguration _initial;
  final HomeBoardSection _board;
  final HomeBoardConfigurationSection _configuration;
  final HomeDisplaySection _display;
  final HomeHeroPreview _preview;

  late final HomeCatalogSession homeCatalogSession;
  late final HomeBoardBindings homeBoardBindings;
  late final HomeMediaBindings homeMediaBindings;
  late final HomeFavoriteBindings favoriteBindings;
  late final HomeContinuationBindings continuationBindings;
  late final HomeReturnSnapshot? homeSnapshot;
  late final bool restoredHome;

  void initializeRepositories() {
    _board.homeReturnRepository = ref.read(
      homeReturnRepositoryProvider(_deps.search().profileSessionOwner),
    );
    _board.homeCollectionsRepository = ref.read(
      homeCollectionsRepositoryProvider,
    );
  }

  void initialize(KeywordSnapshot? keywordSnapshot) {
    if (!_deps.searchMode() && !_deps.discoverMode()) {
      _board.homeReturnRepository.observeInvalidation();
    }
    final homeSnapshot = !_deps.searchMode() && !_deps.discoverMode()
        ? _board.homeReturnRepository.take()
        : null;
    final restoredHome =
        homeSnapshot != null &&
        homeSnapshot.configuration.hideWatched == _deps.hideWatched();
    // Seed cached state in provider construction so the first return frame
    // does not mutate a provider during initState or wait for another frame.
    final homeSession = HomeCatalogSession(
      owner: _deps.search().profileSessionOwner,
      viewIdentity: Object(),
      initialBoard: restoredHome && keywordSnapshot == null
          ? homeSnapshot.board
          : null,
      initialConfiguration: restoredHome && keywordSnapshot == null
          ? homeSnapshot.configuration
          : _initial,
      initialRows: restoredHome && keywordSnapshot == null
          ? homeSnapshot.sections
          : const [],
      initiallyRefreshing:
          !_deps.searchMode() &&
          !_deps.discoverMode() &&
          !(restoredHome && keywordSnapshot == null),
    );
    homeCatalogSession = homeSession;
    homeBoardBindings = HomeBoardBindings(
      ref,
      homeSession,
      isCurrent: _deps.mounted,
      onContinuationChanged: () => _deps.setState(() {}),
    );
    homeMediaBindings = HomeMediaBindings(ref, homeSession);
    _display.homeLayoutPreferenceSubscription = ref.listenManual(
      homeLayoutPreferenceProvider(homeSession),
      (previous, next) {},
    );
    _display.tvHomeStyle = _display.homeLayoutPreferenceSubscription
        .read()
        .initialStyle;
    _preview.startPreferences(ref, homeSession);
    _configuration.homeDefaultViewSubscription = ref.listenManual(
      homeDefaultViewProvider(homeSession),
      (previous, next) {},
    );
    final displaySession = (
      owner: _deps.search().profileSessionOwner,
      viewIdentity: Object(),
      initial: restoredHome && keywordSnapshot == null
          ? (
              orientation: homeSnapshot.cardOrientation,
              hideTitlesAndRatings: homeSnapshot.hideCardTitlesAndRatings,
              hideCatalogAddonNames: homeSnapshot.hideCatalogAddonNames,
              hideCollectionNames: homeSnapshot.hideCollectionNames,
              spotlightFocusDetails: false,
              animationsEnabled: false,
              animationStyle: 'snowy_mountain',
            )
          : initialHomeDisplayPreferences,
    );
    _display.homeDisplaySubscription = ref.listenManual(
      homeDisplayPreferencesProvider(displaySession),
      (previous, next) {},
    );
    _display.homeDisplayController = ref.read(
      homeDisplayPreferencesProvider(displaySession).notifier,
    );
    favoriteBindings = HomeFavoriteBindings(
      ref,
      newSession: () =>
          (owner: _deps.search().profileSessionOwner, viewIdentity: Object()),
    );
    final localContinuationSession = HomeContinuationSession(
      owner: _deps.search().profileSessionOwner,
      viewIdentity: Object(),
    );
    continuationBindings = HomeContinuationBindings(
      ref,
      localContinuationSession,
      initiallyLoadingTrakt: !_deps.searchMode(),
    );
    _board.rememberScroll(
      restoredHome && !_deps.isTelevision() ? homeSnapshot.scrollOffset : 0,
    );
    _board.boardViewport.initializeScroll(_board.homeLastScroll);
    this.homeSnapshot = homeSnapshot;
    this.restoredHome = restoredHome;
  }

  /// Closes view subscriptions in their original teardown order.
  void closePresentationBindings() {
    homeBoardBindings.close();
    homeMediaBindings.close();
    _display.homeLayoutPreferenceSubscription.close();
    _preview.heroTrailerPreferencesSubscription.close();
    _configuration.homeDefaultViewSubscription.close();
    _display.homeDisplaySubscription.close();
    continuationBindings.closeContent();
    favoriteBindings.close();
    continuationBindings.closeLayout();
  }
}
