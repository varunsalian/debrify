import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/home_preferences.dart';
import 'home_card_style.dart';
import '../application/home_layout_preference.dart';
import '../application/home_layout_policy.dart';
import '../application/home_display_preferences_controller.dart';
import '../models/home_display_preferences.dart';
import 'home_hero_section.dart';
import 'home_hero_preview.dart';
import 'home_hero_live.dart';

typedef HomeDisplayDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function() spotlightShellActive,
  bool Function() searchSheetOpen,
  VoidCallback resetStageNavigation,
});

/// Accepted display preferences and the ordered live-player layout transition.
class HomeDisplaySection {
  HomeDisplaySection(
    this._deps,
    this._heroSection,
    this._heroPreview,
    this._heroLive,
    this._shellArt,
  );
  final HomeDisplayDeps _deps;
  final HomeHeroSection _heroSection;
  final HomeHeroPreview _heroPreview;
  final HomeHeroLive _heroLive;
  final ValueNotifier<String?> _shellArt;

  /// Active home layout, from `tv_home_style`. The HOME board renders it on
  /// TV; off-TV the pref is resolved through [effectiveOffTvHomeStyle] and
  /// only Spotlight passes through — Search tab and Discover always render
  /// classic (via [homeStyleEffective], regardless of this field). Canvas is
  /// the TV default; matching it here avoids a one-frame classic flash at
  /// boot there, and resolves to classic off-TV.
  late String tvHomeStyle;
  late final ProviderSubscription<HomeLayoutPreference>
  homeLayoutPreferenceSubscription;

  // Landscape default matches the stored default, so a fresh boot doesn't
  // flash portrait rows before the async pref read lands.
  late final HomeDisplayPreferencesController homeDisplayController;
  late final ProviderSubscription<HomeDisplayPreferences>
  homeDisplaySubscription;
  HomeDisplayPreferences get homeDisplay => homeDisplayController.current;
  HomeCardOrientation get homeCardOrientation => homeDisplay.orientation;
  bool get hideHomeCardTitlesAndRatings => homeDisplay.hideTitlesAndRatings;
  bool get hideHomeCatalogAddonNames => homeDisplay.hideCatalogAddonNames;
  bool get hideHomeCollectionNames => homeDisplay.hideCollectionNames;
  bool get spotlightFocusDetails => homeDisplay.spotlightFocusDetails;
  bool get homeAnimationsEnabled => homeDisplay.animationsEnabled;
  String get homeAnimationStyle => homeDisplay.animationStyle;

  bool get homeLandscapeCards =>
      homeCardOrientation == HomeCardOrientation.landscape;

  double get homeArtPosterCaptionBand =>
      hideHomeCardTitlesAndRatings ? 0 : HomeArtCaption.band(_deps.context());

  bool get homeBoardMode =>
      _deps.isTelevision() && !_deps.searchMode() && !_deps.discoverMode();

  /// The layout the CURRENT surface should render (guards non-home surfaces).
  /// The layout the CURRENT surface should render. TV: the stored style on
  /// the Home board, classic everywhere else. Off-TV: Spotlight only while
  /// the full-bleed shell is actually on screen — results, keyword mode and
  /// the open search sheet all dispatch to the classic board, so the search
  /// experience is byte-identical to today whenever search is in play.
  String get homeStyleEffective {
    if (_deps.isTelevision()) return homeBoardMode ? tvHomeStyle : 'classic';
    return _deps.spotlightShellActive() && !_deps.searchSheetOpen()
        ? 'spotlight'
        : 'classic';
  }

  bool get stageActive => isHomeStageLayout(homeStyleEffective);

  bool get stageWantsAmbient => homeStageWantsAmbient(homeStyleEffective);

  // Live channel previews remain available on every stage, including Mosaic.
  bool get stageWantsLivePreview => stageActive;

  bool get stagePublishesShellArt =>
      homeStagePublishesShellArt(homeStyleEffective);

  bool get theaterEligible => homeStageTheaterEligible(homeStyleEffective);

  /// THE single layout-transition path. Both entry points route here — the
  /// Settings picker AND the cold-start load, which is also a transition
  /// (the field starts at the product default, so a saved 'mosaic' relayouts
  /// a board that may already have a trailer or a live preview running).
  void applyStageTransition(String style) {
    // Tear the live players down BEFORE the relayout: the underlay engine
    // widget must never be re-parented into a different geometry mid-play.
    _heroPreview.clearHeroTrailer();
    _heroLive.clearHeroLiveIptv();
    _deps.resetStageNavigation();
    // The shell's ambient art is per-layout (ink-ground layouts publish
    // none), so clear it rather than leaving the old layout's lighting in
    // the strip behind the ghost rail.
    _heroSection.ambientArtItemId = null;
    if (_shellArt.value != null) {
      _shellArt.value = null;
    }
    _deps.setState(() => tvHomeStyle = style);
    // …then republish for the layout we just switched TO: Canvas/Promenade
    // want the shell lit again, and the ink layouts want it to stay dark.
    // Without this the shell keeps whatever the previous layout left until
    // some unrelated hero change happens to refresh it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted()) return;
      _heroSection.publishAmbientArt(
        _heroSection.heroItem.value,
        _heroSection.heroEnriched.value,
      );
      _heroSection.publishHeroTintToShell(_heroSection.heroTint.value);
    });
  }

  Future<void> loadTvHomeStyle() =>
      homeLayoutPreferenceSubscription.read().load(
        isCurrent: () => _deps.mounted(),
        currentStyle: () => tvHomeStyle,
        transition: applyStageTransition,
      );

  Future<void> loadHomeCardOrientation({bool Function()? isCurrent}) async {
    final changed = await homeDisplayController.load(
      isCurrent: () => _deps.mounted() && (isCurrent?.call() ?? true),
    );
    if (_deps.mounted() && changed) _deps.setState(() {});
  }

  /// Settings picker fired: tear down live players BEFORE the relayout, so
  /// the underlay engine widget is never re-parented mid-play, then re-read
  /// the pref and rebuild.
  void onTvHomeStyleChanged() {
    if (!_deps.mounted()) return;
    unawaited(loadTvHomeStyle());
  }

  void onTvHeroArtworkQualityChanged() {
    if (!_deps.mounted() || !homeBoardMode) return;
    _deps.setState(() {});
  }
}
