import 'package:debrify/features/catalog_detail/presentation/catalog_action_row.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_description.dart';
import 'package:debrify/features/catalog_detail/presentation/catalog_reveal.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_bound_sources.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_metadata.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_primary_action.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_resources.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_root_layout.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_watchlist.dart';
import 'package:flutter/material.dart';

class CatalogDetailActionLayout {
  final CatalogDetailDependencies _deps;

  CatalogDetailActionLayout(this._deps);

  CatalogDetailResources get _f => _deps.parts.resources;

  CatalogDetailMetadata get _m => _deps.parts.metadata;

  CatalogDetailWatchlist get _w => _deps.parts.watchlist;

  CatalogDetailPrimaryAction get _p => _deps.parts.primaryAction;

  CatalogDetailBoundSources get _b => _deps.parts.boundSources;

  CatalogDetailRootLayout get _ro => _deps.parts.rootLayout;

  Widget? secDescription(double start) {
    var description = _deps.presentedItem().description ?? '';
    if (description.isEmpty || description.length < 40) {
      description = _m.imdbExtra?.plot ?? description;
    }
    if (description.isEmpty) return null;
    final tagline = _m.imdbExtra?.tagline;
    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tagline != null && tagline.isNotEmpty) ...[
            Text(
              '"$tagline"',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: _ro.tight ? 12 : (_ro.wide ? 15 : 13),
                fontStyle: FontStyle.italic,
                height: 1.4,
                letterSpacing: 0.2,
                shadows: const [
                  Shadow(color: Color(0x88000000), blurRadius: 8),
                ],
              ),
            ),
            SizedBox(height: _ro.tight ? 6 : 10),
          ],
          if (_ro.wide)
            CatalogDescription(
              text: description,
              wide: true,
              dense: _ro.tight,
              collapsedLines: _ro.tight ? 2 : 4,
              expanded: _f.descriptionExpanded,
              onToggle: () => _deps.setState(
                () => _f.descriptionExpanded = !_f.descriptionExpanded,
              ),
            )
          else
            Text(
              description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 15,
                height: 1.5,
                letterSpacing: 0.1,
                shadows: const [
                  Shadow(color: Color(0x66000000), blurRadius: 6),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Snap the wide/TV sheet back to the top so the (non-focusable) header
  /// is visible again. Triggered by a D-pad "up" on the top action row,
  /// where focus traversal would otherwise dead-end at Play/Sources.
  void scrollWideToTop() {
    if (!_f.wideScroll.hasClients || _f.wideScroll.offset <= 0) return;
    _f.wideScroll.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// The Play / Sources action row.
  Widget buildActionRow(double start) {
    final item = _deps.item();
    return CatalogReveal(
      parent: _deps.revealCtrl,
      start: start,
      dy: 16,
      child: CatalogActionRow(
        compact: !_ro.wide,
        showQuickPlay: _deps.showQuickPlay(),
        isSeries: item.type == 'series',
        hasBoundSource: _deps.hasBoundSource,
        playFocus: _f.playFocus,
        browseFocus: _f.browseFocus,
        watchlistFocus: _f.watchlistFocus,
        tv: _deps.isTelevision(),
        playLabel: _p.primaryLabel,
        playBusy: _p.primaryBusy,
        // TV only: the top row is the highest focusable widget, so a D-pad
        // "up" there reveals the header instead of dead-ending.
        onArrowUp: _deps.isTelevision() ? scrollWideToTop : null,
        onPlay: _p.playPrimary,
        onPlayLongPress: _b.canBrowsePrimarySources
            ? _b.browsePrimarySources
            : null,
        // Neither Play nor Browse pop here: the player pushes on top of
        // this detail screen so the user returns here when playback ends.
        // Browse keeps the detail for the same reason (series drill-down
        // stacks on top). The host handles teardown via _returnToCatalogIfNeeded.
        onBrowse: _deps.onBrowse(),
        inMyWatchlist: _w.inMyWatchlist,
        onToggleMyWatchlist: _w.supportsMyWatchlist
            ? _w.toggleMyWatchlist
            : null,
      ),
    );
  }

  Widget dot() => Text(
    '·',
    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
  );
}
