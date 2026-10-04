import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_action_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_hero_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_metadata_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_rail_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_root_layout.dart';
import 'package:debrify/features/merged_detail/presentation/merged_scroll_anchor.dart';
import 'package:debrify/features/merged_detail/presentation/merged_stagger_reveal.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/widgets/detail/detail_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MergedDetailPaneLayout {
  final MergedDetailDependencies _deps;
  MergedDetailPaneLayout(this._deps);
  StremioMeta get _item => _deps.presentedItem();
  MetadataPreferences get metadataPreferences => _deps.metadataPreferences();
  MergedDetailActionLayout get _ac => _deps.parts.actionLayout;
  MergedDetailFocusState get _f => _deps.parts.focusState;
  MergedDetailHeroLayout get _he => _deps.parts.heroLayout;
  MergedDetailMetadataState get _m => _deps.parts.metadataState;
  MergedDetailRailLayout get _ri => _deps.parts.railLayout;
  MergedDetailRootLayout get _ro => _deps.parts.rootLayout;

  /// Cross RIGHT into the episodes pane: the scope remembers its last-focused
  /// row, so re-entry lands where the user left off (first traversable —
  /// season header or first row — on a cold entry).
  void focusEpisodesPane() {
    final scope = _f.episodesPaneScope;
    FocusNode? target = scope.focusedChild;
    if (target == null) {
      final descendants = scope.traversalDescendants;
      target = descendants.isEmpty ? null : descendants.first;
    }
    target?.requestFocus();
  }

  /// Info-pane key policy. These fire only for keys the focused child ignored
  /// (buttons/tiles don't handle arrows), and always attempt an in-scope
  /// directional move first — so Play → Trailer etc. still work — falling back
  /// to the explicit pane behavior only at the pane's edge:
  ///  • RIGHT at the right edge crosses into the episodes pane;
  ///  • UP at the top goes to the floating back button;
  ///  • DOWN at the bottom is a dead stop (never leaks into episodes).
  KeyEventResult handleInfoPaneKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      if (!primary.focusInDirection(TraversalDirection.right)) {
        focusEpisodesPane();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (!primary.focusInDirection(TraversalDirection.up)) {
        _f.backButtonFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      primary.focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Episodes-pane key policy: Up/Down move within the pane only (dead stop at
  /// the first/last row — the scope already contains directional traversal;
  /// handling the key here just stops it from bubbling further). LEFT from the
  /// season header (rows handle their own LEFT) falls through the header
  /// controls and then crosses to the info column's primary action.
  KeyEventResult handleEpisodesPaneKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      primary.focusInDirection(
        key == LogicalKeyboardKey.arrowUp
            ? TraversalDirection.up
            : TraversalDirection.down,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!primary.focusInDirection(TraversalDirection.left) &&
          detailNodeMounted(_f.leftEntryFocusNode)) {
        _f.leftEntryFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget buildInfoPane() {
    final item = _item;
    final extra = _m.imdbExtra;
    final t = _ro.tight;
    final rating = extra?.rating ?? item.imdbRating;
    final year = item.year ?? extra?.year;
    final genres = MetadataDetailsService.informationGenres(
      item,
      extra,
      metadataPreferences,
    );
    final summary = (item.description?.isNotEmpty ?? false)
        ? item.description
        : extra?.plot;

    // No entrance stagger on TV: each _StaggerReveal animates Opacity (a
    // saveLayer per element per frame) during the exact window the page is
    // also hero-flying and resolving the trailer — the weak TV GPU pays for
    // polish nobody perceives at 3m. Same gate as the Home hero's motion.
    final animate =
        !(MediaQuery.maybeOf(_deps.context())?.disableAnimations ?? false) &&
        !_deps.isTelevision();
    return SingleChildScrollView(
      controller: _f.infoScroll,
      padding: EdgeInsets.fromLTRB(
        _deps.isTelevision() ? 34 : 24,
        // Clear the floating top-left back button (~64px) on TV so the eyebrow
        // and title don't sit under it.
        _deps.isTelevision() ? 64 : (t ? 46 : 30),
        18,
        22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MergedStaggerReveal(
            key: const ValueKey('rev-eyebrow'),
            delayMs: 0,
            enabled: animate,
            child: Text(
              _ro.isMovie ? 'MOVIE' : 'SERIES',
              style: TextStyle(
                color: _m.accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          SizedBox(height: t ? 5 : 8),
          MergedStaggerReveal(
            key: const ValueKey('rev-title'),
            delayMs: 55,
            enabled: animate,
            child: Text(
              item.name,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: t ? 22 : 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.05,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 14)],
              ),
            ),
          ),
          SizedBox(height: t ? 8 : 10),
          MergedStaggerReveal(
            key: const ValueKey('rev-meta'),
            delayMs: 110,
            enabled: animate,
            child: _he.buildMetaBar(year, extra, rating),
          ),
          // No tracker status chips here any more: the Trakt / Simkl pills in
          // the action row carry that state themselves, so this used to render
          // the same fact twice.
          if (genres.isNotEmpty) ...[
            SizedBox(height: t ? 8 : 10),
            MergedStaggerReveal(
              key: const ValueKey('rev-genres'),
              delayMs: 165,
              enabled: animate,
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [for (final g in genres.take(3)) _ri.pill(g)],
              ),
            ),
          ],
          SizedBox(height: t ? 12 : 16),
          // Focusing the action row snaps the column to the very top so the
          // title / meta / genres above it are revealed (fixes "can't scroll
          // back up to details").
          MergedStaggerReveal(
            key: const ValueKey('rev-actions'),
            delayMs: 220,
            enabled: animate,
            child: MergedScrollAnchor(
              toTop: true,
              active: _deps.isTelevision(),
              child: _ac.buildActionRow(),
            ),
          ),
          if (summary != null && summary.isNotEmpty) ...[
            SizedBox(height: t ? 16 : 20),
            _ri.sectionLabel('Summary'),
            const SizedBox(height: 8),
            Text(
              summary,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          // Awards / Credits / Cast / Details / Parents Guide / More Like This —
          // all inline & reachable by scrolling (no hidden "Details" sheet).
          ..._ri.referenceSections(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
