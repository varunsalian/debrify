import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'home_board_media.dart';
import 'home_classic_hero.dart';
import 'home_classic_layout.dart';
import 'home_takeover_info.dart';
import 'home_trailer_transitions.dart';

/// Classic's hero, streaming status, dimmed rows and media overlays. The
/// original LayoutBuilder/Builder boundaries keep row evaluation lazy.
Widget buildHomeClassicBoard({
  required BuildContext context,
  required bool isTelevision,
  required double Function(double) tvHeroBudget,
  required HomeBoardMedia Function() media,
  required bool Function() trailerActive,
  required bool Function() heroActive,
  required HomeClassicHeroConfiguration Function() readHeroConfiguration,
  required ValueListenable<Color?> tint,
  required ValueListenable<bool> trailerShowing,
  required ValueListenable<bool> liveTakeover,
  required bool Function() showSearchStatus,
  required Widget Function() searchStatus,
  required WidgetBuilder rowsBuilder,
}) {
  final surfaces = media();
  return buildHomeClassicLayout(
    isTelevision: isTelevision,
    viewportWidth: MediaQuery.of(context).size.width,
    tvHeroBudget: tvHeroBudget,
    trailerActive: trailerActive(),
    takeover: surfaces.takeover,
    boardBuilder: (height) => Column(
      children: [
        // The host shows the focus-driven hero on TV, including Search results,
        // and keeps it hidden for the blank Search prompt and touch-only Home.
        if (heroActive())
          buildHomeClassicHero(
            focused: surfaces.item,
            enriched: surfaces.enriched,
            height: height,
            readConfiguration: readHeroConfiguration,
            tint: tint,
            trailerShowing: trailerShowing,
            liveTakeover: liveTakeover,
          ),
        if (showSearchStatus()) searchStatus(),
        Expanded(
          child: buildHomeTrailerRowsDim(
            active: trailerActive(),
            showing: trailerShowing,
            rows: Builder(builder: rowsBuilder),
          ),
        ),
      ],
    ),
    trailerBuilder: (height) => media().trailerLayer(height),
    liveBuilder: (height) => media().liveLayer(height),
    infoBuilder: () => buildHomeTakeoverInfo(
      context,
      heroItem: surfaces.item,
      heroEnriched: surfaces.enriched,
      heroTakeover: surfaces.takeover,
    ),
  );
}
