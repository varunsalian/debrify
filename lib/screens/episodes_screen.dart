import 'package:flutter/material.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../widgets/episodes_panel.dart';

/// Route name for [EpisodesScreen]'s pushed route (a `MaterialPageRoute`,
/// or a zero-duration `PageRouteBuilder` on TV).
const String kEpisodesRouteName = 'episodes';

/// Route name the catalog host gives the pushed `CatalogItemDetailScreen`.
///
/// The detail screen no longer self-pops when "Browse" is tapped (so the
/// drill-down lands *on top of* it and back returns there). When a terminal
/// selection is made (Sources/Play/fallback) the drill-down + detail routes
/// must be torn back down to the host or the host's inline result (search
/// results / player) would be hidden behind them. These names let
/// [EpisodesScreen] and the host `popUntil` exactly those routes.
const String kCatalogDetailRouteName = 'catalog_item_detail';

/// A pushable route that presents the episode drill-down for a single series.
///
/// This was extracted out of `CatalogBrowser`'s inline "episode mode". Making
/// it a real route means system/back navigation returns to the previous
/// screen naturally instead of toggling host-screen state.
///
/// The screen is a thin route wrapper around [EpisodesPanel] (which holds the
/// drill-down engine + UI): it owns the [Scaffold], the route tear-down to the
/// host on a terminal selection ([_popToHost]), and the
/// [onExitedWithoutSelection] signal for a plain back-out.
///
/// Source-binding (the Select Source button + bound-source count) is owned by
/// the host and surfaced through the [boundSourceCount] / [onSelectSource]
/// callbacks; this screen owns no bound-source state.
class EpisodesScreen extends StatefulWidget {
  /// The series to browse.
  final StremioMeta show;

  /// Optional explicit season to land on (deep links / calendar).
  final int? initialSeason;

  /// Optional explicit episode to land on (deep links / calendar).
  final int? initialEpisode;

  /// The addon used to fetch series meta (replaces the host's selected addon).
  final StremioAddon addon;

  /// Whether running on Android TV (disables animations, changes focus flow).
  final bool isTelevision;

  /// Whether to show the Quick Play button on episode tiles.
  final bool showQuickPlay;

  /// Whether this series was opened from a Trakt context (e.g. Discover→Trakt).
  /// When true, episode Sources/Play carry the Trakt scrobble flag + Trakt
  /// resume position so playback syncs to Trakt exactly like the old home
  /// episode view. Left false for plain catalog/addon items so their scrobble
  /// stays governed by the user's "Sync Catalog Items" setting.
  final bool isTraktSource;

  /// Callback when user selects an episode (Sources) or the series falls back
  /// to a direct search.
  final void Function(AdvancedSearchSelection selection)? onItemSelected;

  /// Callback when user quick-plays an episode.
  final void Function(AdvancedSearchSelection selection)? onQuickPlay;

  /// Fired exactly once when this route is dismissed *without* a terminal
  /// selection (back button / system back / gesture). Not called when the
  /// user picks an episode or falls back to direct search — those dispatch
  /// [onItemSelected]/[onQuickPlay] and pop straight to the host.
  final VoidCallback? onExitedWithoutSelection;

  /// Returns the number of bound sources for [show] (host-owned state).
  final int Function(StremioMeta show)? boundSourceCount;

  /// Callback when user taps the Select Source button. When null, the button
  /// is hidden. Returns a Future that completes when the source picker/editor
  /// closes, so the header's bound-source count can refresh in place.
  final Future<void> Function(StremioMeta show)? onSelectSource;

  const EpisodesScreen({
    super.key,
    required this.show,
    required this.addon,
    this.initialSeason,
    this.initialEpisode,
    this.isTelevision = false,
    this.showQuickPlay = true,
    this.isTraktSource = false,
    this.onItemSelected,
    this.onQuickPlay,
    this.onExitedWithoutSelection,
    this.boundSourceCount,
    this.onSelectSource,
  });

  @override
  State<EpisodesScreen> createState() => _EpisodesScreenState();
}

class _EpisodesScreenState extends State<EpisodesScreen> {
  /// Set before any terminal pop (episode chosen / quick-play / fallback) so
  /// [dispose] can tell a real selection apart from a plain back-out and only
  /// fire [EpisodesScreen.onExitedWithoutSelection] for the latter.
  bool _selectionDispatched = false;

  @override
  void dispose() {
    // Plain back-out (no episode picked): tell the host to undo the source
    // switch it made on entry. Deferred a frame so the host's setState runs
    // after this route is fully torn down, never during it.
    if (!_selectionDispatched) {
      final cb = widget.onExitedWithoutSelection;
      if (cb != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => cb());
      }
    }
    super.dispose();
  }

  /// Tear the drill-down stack (this route + the detail route, if the host
  /// pushed one) back down to the host before a terminal dispatch, so the
  /// host's inline result isn't hidden behind these routes.
  void _popToHost() {
    Navigator.of(context).popUntil(
      (r) =>
          r.settings.name != kEpisodesRouteName &&
          r.settings.name != kCatalogDetailRouteName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E14),
      body: SafeArea(
        child: EpisodesPanel(
          show: widget.show,
          addon: widget.addon,
          initialSeason: widget.initialSeason,
          initialEpisode: widget.initialEpisode,
          isTelevision: widget.isTelevision,
          showQuickPlay: widget.showQuickPlay,
          isTraktSource: widget.isTraktSource,
          onItemSelected: widget.onItemSelected,
          onQuickPlay: widget.onQuickPlay,
          boundSourceCount: widget.boundSourceCount,
          onSelectSource: widget.onSelectSource,
          onBack: () => Navigator.of(context).pop(),
          // Mark the selection and tear the drill-down routes down to the host
          // before the panel dispatches — same order the inline flow used.
          onBeforeTerminalDispatch: () {
            _selectionDispatched = true;
            _popToHost();
          },
        ),
      ),
    );
  }
}
