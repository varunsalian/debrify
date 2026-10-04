import 'package:debrify/widgets/episodes_panel.dart';
import 'package:debrify/widgets/hero_trailer_backdrop.dart';
import 'package:flutter/material.dart';

class MergedDetailFocusState {
  /// Scrolls the left info column. Focus-anchored (see [_ScrollAnchor]) so that
  /// focusing the top action row snaps to the very top (revealing the
  /// title/meta/summary above it), and focusing a lower section brings it fully
  /// into view — fixing the "can't scroll back up to the details" DPAD bug.
  final ScrollController infoScroll = ScrollController();
  final ScrollController castRailScroll = ScrollController();
  final ScrollController recommendationRailScroll = ScrollController();

  /// The stable LEFT-crossing target for episodes: the info column's primary
  /// action (Play/Resume, or the source pill when Play is hidden). Pressing LEFT
  /// on an episode focuses this instead of a geometry-picked mid-column item.
  final FocusNode leftEntryFocusNode = FocusNode(
    debugLabel: 'merged-left-entry',
  );

  /// Pane containment (two-pane layout). Each pane lives in its own
  /// [FocusScope]: directional traversal only considers candidates inside the
  /// focused node's nearest scope, so Up/Down can never geometry-jump across
  /// the pane border (DOWN on the last episode used to land on a cast tile in
  /// the info column). Crossing is explicit and horizontal only: LEFT from the
  /// episodes pane → [_leftEntryFocusNode]; RIGHT from the info pane →
  /// [_focusEpisodesPane] (the pane's last-focused row, remembered by its
  /// scope).
  final FocusScopeNode infoPaneScope = FocusScopeNode(
    debugLabel: 'merged-info-pane',
  );
  final FocusScopeNode episodesPaneScope = FocusScopeNode(
    debugLabel: 'merged-episodes-pane',
  );

  /// The floating back button — the info pane hands focus here when UP is
  /// pressed at its top (it sits outside the pane scopes, so contained
  /// traversal alone could never reach it).
  final FocusNode backButtonFocusNode = FocusNode(debugLabel: 'merged-back');

  /// Reaches the hosted panel so [didPopNext] can refresh its watched
  /// ticks/progress after inline playback (episode quick-play, hero Resume)
  /// pops back onto this screen. Single key is safe: only one layout (two-pane
  /// or stacked) builds the panel at a time.
  final GlobalKey<EpisodesPanelState> episodesPanelKey =
      GlobalKey<EpisodesPanelState>();

  /// Filmstrip pushes the focused episode's still here. Painted by the shell as
  /// an ambient layer — never as [HeroTrailerBackdrop.imageUrl], which stays
  /// the title art the route Hero flies back into on pop.
  String? focusedStillUrl;

  /// The Showcase body has descended past its hero.
  ///
  /// Showcase wants the reference's two grounds: sharp key art while the
  /// identity owns the screen, a blurred field once you walk down into the
  /// bands. Both have to be painted HERE, because this backdrop is the only
  /// layer outside the overscan `SafeArea` — art painted inside the body would
  /// stop short of the screen edges and the two states would not line up.
  bool bodyDeep = false;
}
