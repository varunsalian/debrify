import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/debrify_image_cache.dart';
import '../../services/imdb_enrichment_service.dart';
import '../episodes_panel.dart';
import '../parents_guide_section.dart';
import 'detail_episode_cells.dart';
import 'detail_identity.dart';
import 'detail_model.dart';
import 'detail_style.dart';

/// **Dossier** — a fixed identity card on the left that never scrolls, and the
/// whole right side given to the episode list.
///
/// The structural axis is **two independent scroll planes**: the left is a
/// reference card, the right is a pure list, and browsing one never moves the
/// other. Vertical traversal is contained per pane by a [FocusScope] — the
/// proven fix for DOWN on the last episode landing on a cast tile — and the
/// panes are crossed horizontally only.
///
/// For a movie the right pane becomes the reference column.
class DetailDossier extends StatefulWidget {
  final DetailModel model;
  final Widget Function(
    Widget Function(BuildContext, EpisodesPanelView) contentBuilder,
  )?
  episodesHost;

  const DetailDossier({
    super.key,
    required this.model,
    required this.episodesHost,
  });

  @override
  State<DetailDossier> createState() => _DetailDossierState();
}

class _DetailDossierState extends State<DetailDossier> {
  final DetailCellNodes _cellNodes = DetailCellNodes('dossier');
  int _handledGeneration = -1;

  final FocusNode _seasonNode = FocusNode(debugLabel: 'dossier-season');
  final FocusNode _retryNode = FocusNode(debugLabel: 'dossier-retry');
  final FocusScopeNode _leftScope = FocusScopeNode(debugLabel: 'dossier-left');
  final FocusScopeNode _rightScope = FocusScopeNode(
    debugLabel: 'dossier-right',
  );
  final ScrollController _listScroll = ScrollController();

  @override
  void dispose() {
    _cellNodes.dispose();
    _seasonNode.dispose();
    _retryNode.dispose();
    _leftScope.dispose();
    _rightScope.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final size = resolveDetailSize(
      isTelevision: m.isTelevision,
      size: MediaQuery.of(context).size,
    );
    if (size.isPhone) return _stacked(m, size);
    return _twoPane(m, size);
  }

  // ── Wide ──────────────────────────────────────────────────────────────────

  Widget _twoPane(DetailModel m, DetailSize size) {
    final w = MediaQuery.of(context).size.width;
    final leftW = (w * 0.34).clamp(280.0, 380.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: leftW,
          child: FocusScope(
            node: _leftScope,
            onKeyEvent: _leftKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    DetailPalette.ink.withValues(alpha: 0.90),
                    DetailPalette.ink.withValues(alpha: 0.62),
                  ],
                ),
              ),
              child: _card(m, size),
            ),
          ),
        ),
        Expanded(
          child: FocusScope(
            node: _rightScope,
            onKeyEvent: _rightKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: DetailPalette.ink2.withValues(alpha: 0.86),
                border: Border(left: BorderSide(color: DetailPalette.hair)),
              ),
              child: _rightPane(m, size),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stacked(DetailModel m, DetailSize size) {
    return Column(
      children: [
        FocusScope(
          node: _leftScope,
          onKeyEvent: _leftKey,
          child: _card(m, size),
        ),
        Expanded(
          child: FocusScope(
            node: _rightScope,
            onKeyEvent: _rightKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: DetailPalette.ink2.withValues(alpha: 0.86),
                border: Border(top: BorderSide(color: DetailPalette.hair)),
              ),
              child: _rightPane(m, size),
            ),
          ),
        ),
      ],
    );
  }

  // ── Left card ─────────────────────────────────────────────────────────────

  Widget _card(DetailModel m, DetailSize size) {
    final poster = m.poster;
    final synopsis = m.synopsis;
    final cast = m.cast;
    // Only when the column is tall enough to hold it — on a 540px TV this is
    // the first thing that would push the cast off the bottom.
    final tall = MediaQuery.of(context).size.height >= 860;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        size.gutter,
        m.isTelevision ? 58 : 46,
        size.gutter,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (poster != null && poster.isNotEmpty) ...[
                SizedBox(
                  width: size.isPhone ? 62 : 76,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: CachedNetworkImage(
                        imageUrl: poster,
                        fit: BoxFit.cover,
                        cacheManager: DebrifyImageCache.manager,
                        memCacheWidth: 240,
                        placeholder: (_, __) =>
                            ColoredBox(color: DetailPalette.glass),
                        errorWidget: (_, __, ___) =>
                            ColoredBox(color: DetailPalette.glass),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 13),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      m.isMovie ? 'MOVIE' : 'SERIES',
                      style: TextStyle(
                        color: m.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      m.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: size.isTight ? 20 : 23,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DetailMetaBar(model: m, fontSize: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DetailActionRow(
            model: m,
            onUpEdge: () => m.focus.backNode.requestFocus(),
            onRightEdge: _focusRightPane,
          ),
          if (synopsis != null && synopsis.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              synopsis,
              maxLines: size.isPhone ? 3 : 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: DetailPalette.tx2,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          // Cast is informational here — its tiles are not focusable, so it can
          // never become a wall of no-op DPAD targets.
          if (cast.isNotEmpty && !size.isPhone && tall) ...[
            const SizedBox(height: 18),
            detailSlab('Cast'),
            const SizedBox(height: 9),
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: cast.length.clamp(0, 8),
                separatorBuilder: (_, __) => const SizedBox(width: 11),
                itemBuilder: (context, i) => _CastChip(member: cast[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Right pane ────────────────────────────────────────────────────────────

  Widget _rightPane(DetailModel m, DetailSize size) {
    if (m.isMovie) return _reference(m, size);
    final host = widget.episodesHost;
    if (host == null) return const SizedBox.shrink();
    return host((context, view) => _episodeList(m, view, size));
  }

  Widget _episodeList(DetailModel m, EpisodesPanelView view, DetailSize size) {
    if (view.loading || view.unavailable) {
      return DetailEpisodesStatus(
        loading: view.loading,
        onRetry: view.onRetry,
        onSearchForSources: view.onSearchForSources,
        isTelevision: m.isTelevision,
        retryNode: _retryNode,
        onUpEdge: () => m.focus.focusEntry(),
      );
    }
    _applyFocusIntent(view);
    final episodes = view.episodes;
    final many = view.seasons.length > 1;
    final idx = view.seasons.indexWhere(
      (s) => s.number == view.selectedSeasonNumber,
    );
    return Column(
      children: [
        if (many)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: DetailPalette.hair)),
            ),
            child: Row(
              children: [
                DetailSeasonControl(
                  seasonNumber: view.selectedSeasonNumber,
                  episodeCount: episodes.length,
                  canPrev: idx > 0,
                  canNext: idx < view.seasons.length - 1,
                  onPrev: () => view.stepSeason(-1),
                  onNext: () => view.stepSeason(1),
                  onPick: () => showDetailSeasonPicker(
                    context: context,
                    seasonNumbers: [for (final s in view.seasons) s.number],
                    selected: view.selectedSeasonNumber,
                    isTelevision: m.isTelevision,
                    onSelected: view.selectSeason,
                  ),
                  focusNode: _seasonNode,
                  onUpEdge: () => m.focus.backNode.requestFocus(),
                  onDownEdge: _focusFirstCell,
                  hint: 'OK play · ▶ options',
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            controller: _listScroll,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
            itemCount: episodes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final e = episodes[i];
              return DetailEdgeTrap(
                trapUp: i == 0,
                onUp: () => many
                    ? _seasonNode.requestFocus()
                    : m.focus.backNode.requestFocus(),
                child: DetailEpisodeRow(
                  episode: e,
                  fallbackImage: view.showImageUrl,
                  progress: view.progressOf(e),
                  isNext: view.isNext(e),
                  focusNode: _cellNodes.of(view.generation, e.season, e.number),
                  onPlay: () => view.play(e),
                  onOptions: () => view.options(e),
                  onLeftEdge: () => m.focus.focusEntry(),
                  thumbWidth: size.isPhone ? 92 : 108,
                  showSynopsis: !size.isPhone,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// A movie has no episode list — the right pane becomes the reference
  /// column. Every region here is omitted when empty rather than rendered
  /// blank: sparse rows from Trakt/Simkl/MDBList arrive with little more than a
  /// title and a poster.
  Widget _reference(DetailModel m, DetailSize size) {
    final rows = m.detailRows;
    final cast = m.cast;
    final recs = m.recommendations;
    final guide = m.parentsGuide;
    final synopsis = m.synopsis;
    return ListView(
      padding: EdgeInsets.fromLTRB(size.gutter, 16, size.gutter, 24),
      children: [
        if (synopsis != null && synopsis.isNotEmpty) ...[
          detailSlab('Summary'),
          const SizedBox(height: 8),
          Text(
            synopsis,
            style: TextStyle(
              color: DetailPalette.tx2,
              fontSize: 13,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (cast.isNotEmpty) ...[
          detailSlab('Cast'),
          const SizedBox(height: 10),
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length.clamp(0, 12),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _CastChip(member: cast[i]),
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (rows.isNotEmpty) ...[
          detailSlab('Details'),
          const SizedBox(height: 8),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(
                      r.$1,
                      style: TextStyle(
                        color: DetailPalette.tx3,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: TextStyle(
                        color: DetailPalette.tx2,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 22),
        ],
        if (recs.isNotEmpty && m.onRecommendationTap != null) ...[
          detailSlab('More like this'),
          const SizedBox(height: 10),
          SizedBox(
            height: 156,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recs.length.clamp(0, 12),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _RecPoster(
                rec: recs[i],
                onTap: () => m.onRecommendationTap!(recs[i]),
              ),
            ),
          ),
          const SizedBox(height: 22),
        ],
        if (guide != null && !guide.isEmpty) ...[
          detailSlab('Parents guide'),
          const SizedBox(height: 10),
          ParentsGuideSection(guide: guide, tv: m.isTelevision, dense: true),
        ],
      ],
    );
  }

  // ── Focus ─────────────────────────────────────────────────────────────────

  void _focusRightPane() {
    final target =
        _rightScope.focusedChild ??
        _rightScope.traversalDescendants.firstOrNull;
    target?.requestFocus();
  }

  void _focusFirstCell() {
    final first = _cellNodes.firstMounted;
    first?.requestFocus();
  }

  KeyEventResult _leftKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight) {
      if (!primary.focusInDirection(TraversalDirection.right)) {
        _focusRightPane();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (!primary.focusInDirection(TraversalDirection.up)) {
        widget.model.focus.backNode.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      // Contained: DOWN never leaks into the episode pane.
      primary.focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _rightKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      primary.focusInDirection(
        k == LogicalKeyboardKey.arrowUp
            ? TraversalDirection.up
            : TraversalDirection.down,
      );
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (!primary.focusInDirection(TraversalDirection.left)) {
        widget.model.focus.focusEntry();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _applyFocusIntent(EpisodesPanelView view) {
    if (view.generation == _handledGeneration) return;
    _handledGeneration = view.generation;
    final intent = view.focusIntent;
    if (intent == EpisodeFocusIntent.none) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (intent == EpisodeFocusIntent.seasonControl) {
        if (_seasonNode.context != null) _seasonNode.requestFocus();
        return;
      }
      final landing = view.landing;
      if (landing == null) return;
      final index = view.episodes.indexWhere(
        (e) => e.season == landing.season && e.number == landing.number,
      );
      // Reveal without stealing focus — entry focus belongs to the primary
      // action; this only brings the resumed episode into view.
      revealDetailLanding(
        controller: _listScroll,
        index: index,
        itemCount: view.episodes.length,

        contextOf: () => _cellNodes
            .lookup(view.generation, landing.season, landing.number)
            ?.context,
        alignment: 0.35,
      );
    });
  }
}

/// Non-focusable cast portrait — informational only.
class _CastChip extends StatelessWidget {
  final CastMember member;
  const _CastChip({required this.member});

  @override
  Widget build(BuildContext context) {
    final url = member.imageUrl;
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: SizedBox(
              width: 46,
              height: 46,
              child: (url != null && url.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      cacheManager: DebrifyImageCache.manager,
                      memCacheWidth: 150,
                      placeholder: (_, __) =>
                          ColoredBox(color: DetailPalette.glass),
                      errorWidget: (_, __, ___) =>
                          ColoredBox(color: DetailPalette.glass),
                    )
                  : ColoredBox(color: DetailPalette.glass),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            member.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: DetailPalette.tx2, fontSize: 9.5),
          ),
        ],
      ),
    );
  }
}

class _RecPoster extends StatefulWidget {
  final dynamic rec;
  final VoidCallback onTap;
  const _RecPoster({required this.rec, required this.onTap});

  @override
  State<_RecPoster> createState() => _RecPosterState();
}

class _RecPosterState extends State<_RecPoster> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final String? poster = widget.rec.poster as String?;
    return SizedBox(
      width: 100,
      child: DetailFocusRing(
        focused: _focused,
        radius: BorderRadius.circular(9),
        child: Material(
          color: DetailPalette.glass,
          borderRadius: BorderRadius.circular(9),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (f) => setState(() => _focused = f),
            child: (poster != null && poster.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: poster,
                    fit: BoxFit.cover,
                    cacheManager: DebrifyImageCache.manager,
                    memCacheWidth: 300,
                    placeholder: (_, __) =>
                        ColoredBox(color: DetailPalette.glass),
                    errorWidget: (_, __, ___) =>
                        ColoredBox(color: DetailPalette.glass),
                  )
                : ColoredBox(color: DetailPalette.glass),
          ),
        ),
      ),
    );
  }
}
