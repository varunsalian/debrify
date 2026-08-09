import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/debrify_image_cache.dart';
import '../../services/imdb_parents_guide_service.dart';
import '../../services/storage_service.dart';
import '../../services/trakt/trakt_episode_model.dart';
import '../episodes_panel.dart';
import '../horizontal_mouse_wheel.dart';
import '../parents_guide_section.dart';
import 'detail_episode_cells.dart';
import 'detail_identity.dart';
import 'detail_model.dart';
import 'detail_style.dart';
import 'theme/detail_theme.dart';

/// The five showcase layouts developed after the original detail-page set.
///
/// They deliberately share one interaction layer. Only composition changes;
/// episode loading, playback, options, season selection, focus restoration and
/// recommendation routing continue to come from the same screen-owned model.
enum PremiumDetailKind { vista, monolith, mosaic, halo, premiere }

class DetailPremium extends StatefulWidget {
  final PremiumDetailKind kind;
  final DetailModel model;
  final Widget Function(
    Widget Function(BuildContext, EpisodesPanelView) contentBuilder,
  )?
  episodesHost;

  const DetailPremium({
    super.key,
    required this.kind,
    required this.model,
    required this.episodesHost,
  });

  @override
  State<DetailPremium> createState() => _DetailPremiumState();
}

class _DetailPremiumState extends State<DetailPremium> {
  final DetailCellNodes _cells = DetailCellNodes('premium');
  final FocusNode _seasonNode = FocusNode(debugLabel: 'premium-season');
  final FocusNode _retryNode = FocusNode(debugLabel: 'premium-retry');
  final FocusNode _guideNode = FocusNode(debugLabel: 'premium-guide');
  final FocusNode _continueNode = FocusNode(debugLabel: 'premium-continue');
  final ScrollController _rail = ScrollController();
  final ScrollController _list = ScrollController();
  final List<FocusNode> _recNodes = [];
  int _handledGeneration = -1;
  late DetailTheme _t;

  DetailModel get _m => widget.model;

  @override
  void dispose() {
    _cells.dispose();
    _seasonNode.dispose();
    _retryNode.dispose();
    _guideNode.dispose();
    _continueNode.dispose();
    _rail.dispose();
    _list.dispose();
    for (final node in _recNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _t = DetailThemeScope.of(context);
    final mediaSize = MediaQuery.sizeOf(context);
    final size = resolveDetailSize(
      isTelevision: _m.isTelevision,
      size: mediaSize,
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compactHeight = !_m.isTelevision && mediaSize.height < 700;
    if (compactHeight || textScale > 1.25) {
      return _adaptiveLayout(size, stacked: mediaSize.width < 600);
    }
    return switch (widget.kind) {
      PremiumDetailKind.vista => _vista(size),
      PremiumDetailKind.monolith => _monolith(size),
      PremiumDetailKind.mosaic => _mosaic(size),
      PremiumDetailKind.halo => _halo(size),
      PremiumDetailKind.premiere => _premiere(size),
    };
  }

  Widget _vista(DetailSize size) {
    final gutter = size.gutter;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DetailScrim(),
        Positioned(
          top: size.isPhone ? 68 : 78,
          right: gutter,
          child: _conceptMark('VISTA', Icons.panorama_wide_angle_rounded),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: _identity(size, maxWidth: size.isWide ? 560 : null),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: _actionsAndGuide(center: false),
            ),
            const SizedBox(height: 14),
            Container(
              height: size.isPhone ? 226 : 206,
              decoration: BoxDecoration(
                color: _t.fade(_t.railBg, 0.94),
                gradient: _t.railWash,
                border: Border(top: BorderSide(color: _t.hair)),
              ),
              padding: const EdgeInsets.only(top: 12),
              child: _horizontalCollection(size, gutter),
            ),
          ],
        ),
      ],
    );
  }

  Widget _monolith(DetailSize size) {
    if (size.isPhone) return _phoneDeck(size, 'MONOLITH', vertical: true);
    final gutter = size.gutter;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DetailScrim(),
        Row(
          children: [
            Expanded(
              flex: 11,
              child: Padding(
                padding: EdgeInsets.fromLTRB(gutter, 76, gutter * .65, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _conceptMark('MONOLITH', Icons.view_sidebar_rounded),
                    const Spacer(),
                    _identity(size, maxWidth: 560, synopsis: true),
                    const SizedBox(height: 16),
                    _actionsAndGuide(center: false),
                  ],
                ),
              ),
            ),
            Container(
              width: (MediaQuery.sizeOf(context).width * .42).clamp(390, 590),
              decoration: BoxDecoration(
                color: _t.pane,
                gradient: _t.paneWash,
                border: Border(left: BorderSide(color: _t.hair)),
                boxShadow: _t.shadowFor(_m.isTelevision),
              ),
              padding: EdgeInsets.fromLTRB(gutter * .55, 76, gutter * .55, 22),
              child: _verticalCollection(
                size,
                title: _m.isMovie ? 'CURATED FOR YOU' : 'SEASON DECK',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _mosaic(DetailSize size) {
    if (size.isPhone) return _phoneDeck(size, 'MOSAIC', vertical: false);
    if (_m.isMovie) return _mosaicBoard(size, view: null);
    final host = widget.episodesHost;
    if (host == null) return _mosaicBoard(size, view: null);
    return host((context, view) => _mosaicBoard(size, view: view));
  }

  Widget _mosaicBoard(DetailSize size, {required EpisodesPanelView? view}) {
    final gutter = size.gutter;
    final hero = _mosaicHero(size);
    final utilities = Column(
      children: [
        Expanded(child: _mosaicFeature(view)),
        const SizedBox(height: 12),
        SizedBox(height: 106, child: _mosaicFactsTile()),
      ],
    );
    final top = size.isWide
        ? Row(
            children: [
              Expanded(flex: 7, child: hero),
              const SizedBox(width: 12),
              Expanded(flex: 5, child: utilities),
            ],
          )
        : Column(
            children: [
              Expanded(child: hero),
              const SizedBox(height: 12),
              SizedBox(
                height: 190,
                child: Row(
                  children: [
                    Expanded(flex: 6, child: _mosaicFeature(view)),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: _mosaicFactsTile()),
                  ],
                ),
              ),
            ],
          );
    final rail = _m.isMovie
        ? _movieRail(size, 18)
        : (view == null
              ? const SizedBox.shrink()
              : _episodeRail(size, 18, view, revealLanding: false));
    return ColoredBox(
      color: _t.fade(_t.ground, _t.lightGround ? 1 : .54),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 72, gutter, 20),
        child: Column(
          children: [
            Expanded(
              child: KeyedSubtree(key: const Key('mosaic-top'), child: top),
            ),
            const SizedBox(height: 12),
            SizedBox(
              key: const Key('mosaic-bottom-rail'),
              height: size.isTight ? 178 : 200,
              child: _premiumPanel(
                padding: const EdgeInsets.only(top: 10),
                child: rail,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mosaicHero(DetailSize size) => _mosaicTile(
    key: const Key('mosaic-hero'),
    child: Stack(
      fit: StackFit.expand,
      children: [
        _Poster(url: _m.backdrop, cacheWidth: 1000),
        const DetailScrim(),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _conceptMark('MOSAIC', Icons.grid_view_rounded),
              const Spacer(),
              _identity(size, maxWidth: 570),
              const SizedBox(height: 14),
              _actionsAndGuide(
                center: false,
                includeGuide: false,
                scrollActions: size.isTight,
                onRightEdge: () => _focusAndReveal(
                  _continueNode,
                  ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _mosaicFeature(EpisodesPanelView? view) {
    final episode =
        view?.landing ??
        ((view?.episodes.isNotEmpty ?? false) ? view!.episodes.first : null);
    final imageUrl = _m.isMovie
        ? _m.backdrop
        : (episode?.thumbnailUrl ?? view?.showImageUrl ?? _m.backdrop);
    final title = _m.isMovie ? _m.name : (episode?.title ?? _m.name);
    final eyebrow = _m.isMovie ? 'CONTINUE WATCHING' : 'NEXT EPISODE';
    final detail = _m.isMovie
        ? [_m.year, _m.runtime].whereType<String>().join(' · ')
        : (episode == null
              ? 'Choose an episode'
              : 'S${episode.season} · E${episode.number}');
    final VoidCallback onTap = episode == null
        ? _m.onPrimary
        : () => view!.play(episode);
    final down = _hasGuide
        ? () => _focusAndReveal(
            _guideNode,
            ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          )
        : _focusCollection;
    return DetailEdgeTrap(
      trapLeft: true,
      trapRight: true,
      trapUp: true,
      trapDown: true,
      onLeft: _focusEntryAndReveal,
      onUp: _focusEntryAndReveal,
      onDown: down,
      child: _MosaicFeatureTile(
        key: const Key('mosaic-feature'),
        imageUrl: imageUrl,
        eyebrow: eyebrow,
        title: title,
        detail: detail,
        focusNode: _continueNode,
        onTap: onTap,
      ),
    );
  }

  Widget _halo(DetailSize size) {
    final gutter = size.gutter;
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -.25),
              radius: 1.0,
              colors: [
                _t.fade(_m.accent, .24),
                _t.fade(_t.ground, .42),
                _t.fade(_t.ground, .96),
              ],
              stops: const [0, .45, 1],
            ),
          ),
        ),
        Center(
          child: Container(
            width: size.isPhone ? 280 : 390,
            height: size.isPhone ? 280 : 390,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _t.fade(_t.focus, .18)),
              boxShadow: [
                BoxShadow(color: _t.fade(_m.accent, .16), blurRadius: 60),
              ],
            ),
          ),
        ),
        if (_hasGuide)
          Positioned(
            top: size.isPhone ? 64 : 70,
            right: gutter,
            child: _guideControl(),
          ),
        Column(
          children: [
            SizedBox(height: size.isPhone ? 66 : 74),
            _conceptMark('HALO', Icons.radio_button_checked_rounded),
            const Spacer(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: Column(
                children: [
                  _identity(size, maxWidth: 680, centered: true),
                  const SizedBox(height: 13),
                  _actionsAndGuide(center: true, includeGuide: false),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Container(
              height: size.isPhone ? 218 : 174,
              margin: EdgeInsets.symmetric(
                horizontal: size.isPhone ? 0 : gutter,
              ),
              decoration: BoxDecoration(
                color: _t.fade(_t.railBg, .92),
                gradient: _t.railWash,
                borderRadius: size.isPhone ? null : _t.brRadius,
                border: Border.all(color: _t.hair),
                boxShadow: _t.shadowFor(_m.isTelevision),
              ),
              padding: const EdgeInsets.only(top: 10),
              child: _horizontalCollection(size, size.isPhone ? gutter : 18),
            ),
            SizedBox(height: size.isPhone ? 0 : 18),
          ],
        ),
      ],
    );
  }

  Widget _premiere(DetailSize size) {
    if (size.isPhone) return _phoneDeck(size, 'PREMIERE', vertical: true);
    final gutter = size.gutter;
    return ColoredBox(
      color: _t.fade(_t.ground, _t.lightGround ? 1 : .78),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 72, gutter, 22),
        child: Column(
          children: [
            Row(
              children: [
                _conceptMark('PREMIERE', Icons.local_movies_outlined),
                const SizedBox(width: 14),
                Expanded(child: Divider(color: _t.hair)),
                const SizedBox(width: 14),
                Text(_m.year ?? 'ORIGINAL', style: _t.slabStyle),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 9,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Spacer(),
                          _identity(size, maxWidth: 580, synopsis: true),
                          const SizedBox(height: 18),
                          _actionsAndGuide(center: false),
                          const Spacer(),
                          _ledgerRows(),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 7,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: _t.hair)),
                      ),
                      padding: const EdgeInsets.only(left: 22),
                      child: _verticalCollection(
                        size,
                        title: _m.isMovie
                            ? 'ENCORE SELECTION'
                            : 'NOW SCREENING',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phoneDeck(DetailSize size, String mark, {required bool vertical}) {
    final gutter = size.gutter;
    return ColoredBox(
      color: _t.fade(_t.ground, _t.lightGround ? 1 : .70),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 68, gutter, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _conceptMark(mark, Icons.movie_filter_outlined),
            const Spacer(),
            _identity(size, synopsis: false),
            const SizedBox(height: 11),
            _actionsAndGuide(center: false),
            const SizedBox(height: 12),
            SizedBox(
              height: vertical ? 300 : 230,
              child: _premiumPanel(
                padding: EdgeInsets.fromLTRB(12, 10, 12, vertical ? 8 : 0),
                child: vertical
                    ? _verticalCollection(
                        size,
                        title: _m.isMovie ? 'MORE LIKE THIS' : 'EPISODES',
                      )
                    : _horizontalCollection(size, 0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Short landscape phones and enlarged text need flexible planes instead of
  /// the showcase layouts' fixed cinematic bands. The identity plane scrolls;
  /// the collection keeps the remaining viewport and its normal interaction
  /// model. This preserves every action without clipping or shrinking it into
  /// an unusable target.
  Widget _adaptiveLayout(DetailSize size, {required bool stacked}) {
    final gutter = size.gutter;
    final identity = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(gutter, 58, gutter, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _conceptMark(_kindLabel, _kindIcon),
          const SizedBox(height: 18),
          _identity(size, synopsis: false),
          const SizedBox(height: 14),
          _actionsAndGuide(center: false, scrollActions: true),
        ],
      ),
    );
    final collection = Container(
      decoration: BoxDecoration(
        color: _t.pane,
        gradient: _t.paneWash,
        border: Border(left: BorderSide(color: _t.hair)),
      ),
      padding: EdgeInsets.fromLTRB(gutter * .65, 58, gutter * .65, 12),
      child: _verticalCollection(
        size,
        title: _m.isMovie ? 'MORE LIKE THIS' : 'EPISODES',
      ),
    );
    final planes = stacked
        ? Column(
            children: [
              Expanded(flex: 5, child: identity),
              Expanded(
                flex: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: _t.hair)),
                  ),
                  child: collection,
                ),
              ),
            ],
          )
        : Row(
            children: [
              Expanded(flex: 6, child: identity),
              Expanded(flex: 5, child: collection),
            ],
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _t.ground,
        gradient: widget.kind == PremiumDetailKind.halo
            ? RadialGradient(
                center: const Alignment(-.35, -.35),
                radius: 1.1,
                colors: [_t.fade(_m.accent, .20), _t.ground],
              )
            : _t.idWash,
      ),
      child: planes,
    );
  }

  String get _kindLabel => switch (widget.kind) {
    PremiumDetailKind.vista => 'VISTA',
    PremiumDetailKind.monolith => 'MONOLITH',
    PremiumDetailKind.mosaic => 'MOSAIC',
    PremiumDetailKind.halo => 'HALO',
    PremiumDetailKind.premiere => 'PREMIERE',
  };

  IconData get _kindIcon => switch (widget.kind) {
    PremiumDetailKind.vista => Icons.panorama_wide_angle_rounded,
    PremiumDetailKind.monolith => Icons.view_sidebar_rounded,
    PremiumDetailKind.mosaic => Icons.grid_view_rounded,
    PremiumDetailKind.halo => Icons.radio_button_checked_rounded,
    PremiumDetailKind.premiere => Icons.local_movies_outlined,
  };

  Widget _identity(
    DetailSize size, {
    double? maxWidth,
    bool synopsis = false,
    bool centered = false,
  }) {
    final genres = _m.genres;
    final content = Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DetailLogo(
          model: _m,
          height: size.isPhone ? 48 : 66,
          maxWidthFactor: .75,
        ),
        const SizedBox(height: 8),
        DetailMetaBar(model: _m, fontSize: size.isPhone ? 11.5 : 13),
        if (genres.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: centered ? WrapAlignment.center : WrapAlignment.start,
            spacing: 6,
            runSpacing: 5,
            children: [for (final genre in genres.take(3)) DetailPill(genre)],
          ),
        ],
        if (synopsis && (_m.synopsis?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 10),
          Text(
            _m.synopsis!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: centered ? TextAlign.center : TextAlign.start,
            style: _t.bodyStyle(size: 12.5, height: 1.45),
          ),
        ],
      ],
    );
    if (maxWidth == null) return content;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: content,
    );
  }

  /// Whether this kind lays the episode collection out as a side pane to the
  /// RIGHT of the identity column. Those layouts must honor RIGHT as the pane
  /// crossing — on a two-pane page that is the key everyone presses first, and
  /// dead-stopping it reads as "the arrows don't reach the episodes".
  bool get _sidePane =>
      widget.kind == PremiumDetailKind.monolith ||
      widget.kind == PremiumDetailKind.premiere;

  Widget _actionsAndGuide({
    required bool center,
    bool includeGuide = true,
    bool scrollActions = false,
    VoidCallback? onRightEdge,
  }) {
    final actions = DetailActionRow(
      model: _m,
      alignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
      compactTrackers: MediaQuery.sizeOf(context).width < 700,
      onUpEdge: () => _m.focus.backNode.requestFocus(),
      // Side-pane layouts cross RIGHT into the collection; the rest send RIGHT
      // to the guide when one exists (it sits beside or above the rail there).
      onRightEdge:
          onRightEdge ??
          (_sidePane
              ? _focusCollection
              : (_hasGuide
                    ? () => _focusAndReveal(
                        _guideNode,
                        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                      )
                    : null)),
      // In the side-pane layouts the guide button sits directly below the
      // actions, so DOWN reaches it on the way to the collection — RIGHT is
      // the pane crossing there, so DOWN is the only road to the guide.
      onDownEdge: (_sidePane && _hasGuide && includeGuide)
          ? () {
              if (_guideNode.context != null) {
                _focusAndReveal(
                  _guideNode,
                  ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                );
              } else {
                _focusCollection();
              }
            }
          : _focusCollection,
    );
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (scrollActions)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: actions,
          )
        else
          actions,
        if (includeGuide && _hasGuide) ...[
          const SizedBox(height: 7),
          _guideControl(),
        ],
      ],
    );
  }

  bool get _hasGuide => _m.parentsGuide?.categories.isNotEmpty ?? false;

  Widget _guideControl({VoidCallback? onUp}) => DetailEdgeTrap(
    trapLeft: true,
    trapRight: true,
    trapUp: true,
    trapDown: true,
    onLeft: _focusEntryAndReveal,
    onUp: onUp ?? _focusEntryAndReveal,
    onDown: _focusCollection,
    // Side-pane layouts: the collection is to the right of the whole identity
    // column, so RIGHT crosses from here too instead of dead-stopping.
    onRight: _sidePane ? _focusCollection : null,
    child: DetailGhostButton(
      label: 'Parents Guide',
      icon: Icons.family_restroom_rounded,
      focusNode: _guideNode,
      onTap: _showParentsGuide,
    ),
  );

  Future<void> _showParentsGuide() async {
    final guide = _m.parentsGuide;
    if (guide == null || guide.categories.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => DetailThemeScope(
        theme: _t,
        child: Dialog(
          backgroundColor: _t.pane,
          shape: RoundedRectangleBorder(
            borderRadius: _t.brRadius,
            side: BorderSide(color: _t.hair),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: StorageService.parentsGuideStyleCached == 'compass'
                  ? 900
                  : 620,
              maxHeight: 680,
            ),
            child: _ParentsGuideDialogBody(
              guide: guide,
              television: _m.isTelevision,
              accent: _m.accent,
              theme: _t,
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      _focusAndReveal(
        _guideNode,
        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    }
  }

  void _focusEntryAndReveal() {
    _m.focus.focusEntry();
    final target = _m.focus.primaryEntry.context != null
        ? _m.focus.primaryEntry
        : _m.focus.backNode;
    _reveal(target, ScrollPositionAlignmentPolicy.keepVisibleAtStart);
  }

  void _focusAndReveal(
    FocusNode target,
    ScrollPositionAlignmentPolicy alignmentPolicy,
  ) {
    target.requestFocus();
    _reveal(target, alignmentPolicy);
  }

  void _reveal(
    FocusNode target,
    ScrollPositionAlignmentPolicy alignmentPolicy,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = target.context;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.5,
        alignmentPolicy: alignmentPolicy,
        duration: Duration.zero,
      );
    });
  }

  Widget _conceptMark(String label, IconData icon) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: _m.accent),
      const SizedBox(width: 7),
      Text(label, style: _t.slabStyle.copyWith(color: _t.tx2)),
    ],
  );

  Widget _premiumPanel({required EdgeInsets padding, required Widget child}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _t.pane,
          gradient: _t.paneWash,
          borderRadius: _t.brRadius,
          border: Border.all(color: _t.hair),
          boxShadow: _t.shadowFor(_m.isTelevision),
        ),
        child: child,
      );

  Widget _mosaicTile({Key? key, required Widget child}) => Container(
    key: key,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: _t.pane,
      borderRadius: _t.brRadius,
      border: Border.all(color: _t.hair),
      boxShadow: _t.shadowFor(_m.isTelevision),
    ),
    child: child,
  );

  Widget _mosaicFactsTile() => _mosaicTile(
    child: DecoratedBox(
      decoration: BoxDecoration(color: _t.pane, gradient: _t.paneWash),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 440;
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 13 : 15,
              vertical: 10,
            ),
            child: Row(
              children: [
                Icon(Icons.star_rounded, color: _t.rating, size: 22),
                const SizedBox(width: 8),
                if (compact)
                  Text(
                    _m.rating == null ? '—' : _m.rating!.toStringAsFixed(1),
                    style: _t.titleStyle(
                      size: 18,
                      weight: FontWeight.w800,
                      tracking: -.2,
                    ),
                  )
                else ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _m.rating == null ? '—' : _m.rating!.toStringAsFixed(1),
                        style: _t.titleStyle(
                          size: 18,
                          weight: FontWeight.w800,
                          tracking: -.2,
                        ),
                      ),
                      Text('AT A GLANCE', style: _t.dataStyle(size: 8.5)),
                    ],
                  ),
                  const SizedBox(width: 15),
                  Container(width: 1, height: 32, color: _t.hair),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${_m.sourceCount}',
                        style: _t.titleStyle(
                          size: 16,
                          weight: FontWeight.w800,
                          tracking: 0,
                        ),
                      ),
                      Text(
                        _m.sourceCount == 1 ? 'SOURCE' : 'SOURCES',
                        style: _t.dataStyle(size: 8.5),
                      ),
                    ],
                  ),
                ],
                const Spacer(),
                if (_hasGuide)
                  _guideControl(
                    onUp: () => _focusAndReveal(
                      _continueNode,
                      ScrollPositionAlignmentPolicy.keepVisibleAtStart,
                    ),
                  )
                else
                  Text(
                    compact ? 'NO GUIDE' : 'GUIDE UNAVAILABLE',
                    style: _t.dataStyle(size: 8.5),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _ledgerRows() {
    final rows = _m.detailRows.take(3).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    row.$1.toUpperCase(),
                    style: _t.dataStyle(size: 9),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t.bodyStyle(size: 11.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _focusCollection() {
    if (_seasonNode.context != null) return _seasonNode.requestFocus();
    if (_retryNode.context != null) return _retryNode.requestFocus();
    final cell = _cells.firstMounted;
    if (cell != null) return cell.requestFocus();
    for (final node in _recNodes) {
      if (node.context != null) return node.requestFocus();
    }
  }

  Widget _horizontalCollection(DetailSize size, double gutter) {
    if (_m.isMovie) return _movieRail(size, gutter);
    final host = widget.episodesHost;
    if (host == null) return const SizedBox.shrink();
    return host((context, view) => _episodeRail(size, gutter, view));
  }

  Widget _verticalCollection(DetailSize size, {required String title}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailSlab(title),
        const SizedBox(height: 10),
        Expanded(
          child: _m.isMovie
              ? _movieList(size)
              : (widget.episodesHost?.call(
                      (context, view) => _episodeList(size, view),
                    ) ??
                    const SizedBox.shrink()),
        ),
      ],
    );
  }

  Widget _episodeRail(
    DetailSize size,
    double gutter,
    EpisodesPanelView view, {
    bool revealLanding = true,
  }) {
    if (view.loading || view.unavailable) return _status(view);
    if (revealLanding) _applyFocusIntent(view, horizontal: true);
    final many = view.seasons.length > 1;
    final width = size.isPhone ? 142.0 : 164.0;
    final captionHeight = 22 * MediaQuery.textScalerOf(context).scale(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (many)
          Padding(
            padding: EdgeInsets.only(left: gutter, right: gutter, bottom: 7),
            child: _seasonControl(view),
          )
        else
          Padding(
            padding: EdgeInsets.only(left: gutter, bottom: 7),
            child: DetailSlab('EPISODES'),
          ),
        Expanded(
          child: HorizontalMouseWheel(
            controller: _rail,
            child: ListView.separated(
              controller: _rail,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: gutter),
              itemCount: view.episodes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final episode = view.episodes[index];
                return DetailEdgeTrap(
                  trapLeft: index == 0,
                  trapRight: index == view.episodes.length - 1,
                  trapUp: true,
                  onUp: () =>
                      many ? _seasonNode.requestFocus() : _m.focus.focusEntry(),
                  child: DetailEpisodeCard(
                    episode: episode,
                    fallbackImage: view.showImageUrl,
                    progress: view.progressOf(episode),
                    isNext: view.isNext(episode),
                    focusNode: _cells.of(
                      view.generation,
                      episode.season,
                      episode.number,
                    ),
                    onPlay: () => view.play(episode),
                    onOptions: () => view.options(episode),
                    width: width,
                    captionHeight: captionHeight,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _episodeList(DetailSize size, EpisodesPanelView view) {
    if (view.loading || view.unavailable) return _status(view);
    _applyFocusIntent(view, horizontal: false);
    return Column(
      children: [
        if (view.seasons.length > 1) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _seasonControl(view),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: ListView.separated(
            controller: _list,
            itemCount: view.episodes.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: _t.hair),
            itemBuilder: (context, index) {
              final episode = view.episodes[index];
              final many = view.seasons.length > 1;
              final compactText =
                  MediaQuery.sizeOf(context).width < 600 &&
                  MediaQuery.textScalerOf(context).scale(1) > 1.25;
              return DetailEdgeTrap(
                trapUp: index == 0,
                trapDown: index == view.episodes.length - 1,
                onUp: () =>
                    many ? _seasonNode.requestFocus() : _m.focus.focusEntry(),
                child: compactText
                    ? _AccessibleEpisodeRow(
                        episode: episode,
                        progress: view.progressOf(episode),
                        isNext: view.isNext(episode),
                        focusNode: _cells.of(
                          view.generation,
                          episode.season,
                          episode.number,
                        ),
                        onPlay: () => view.play(episode),
                        onOptions: () => view.options(episode),
                        onLeftEdge: _m.focus.focusEntry,
                      )
                    : DetailEpisodeRow(
                        episode: episode,
                        fallbackImage: view.showImageUrl,
                        progress: view.progressOf(episode),
                        isNext: view.isNext(episode),
                        focusNode: _cells.of(
                          view.generation,
                          episode.season,
                          episode.number,
                        ),
                        onPlay: () => view.play(episode),
                        onOptions: () => view.options(episode),
                        onLeftEdge: _m.focus.focusEntry,
                        thumbWidth: size.isPhone ? 76 : 96,
                        showSynopsis: !size.isPhone,
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _status(EpisodesPanelView view) => DetailEpisodesStatus(
    loading: view.loading,
    onRetry: view.onRetry,
    onSearchForSources: view.onSearchForSources,
    isTelevision: _m.isTelevision,
    retryNode: _retryNode,
    onUpEdge: _m.focus.focusEntry,
  );

  Widget _seasonControl(EpisodesPanelView view) {
    final index = view.seasons.indexWhere(
      (s) => s.number == view.selectedSeasonNumber,
    );
    return DetailSeasonControl(
      seasonNumber: view.selectedSeasonNumber,
      episodeCount: view.episodes.length,
      canPrev: index > 0,
      canNext: index >= 0 && index < view.seasons.length - 1,
      onPrev: () => view.stepSeason(-1),
      onNext: () => view.stepSeason(1),
      onPick: () => showDetailSeasonPicker(
        context: context,
        seasonNumbers: [for (final season in view.seasons) season.number],
        selected: view.selectedSeasonNumber,
        isTelevision: _m.isTelevision,
        theme: _t,
        onSelected: view.selectSeason,
      ),
      focusNode: _seasonNode,
      onUpEdge: _m.focus.focusEntry,
      onDownEdge: () => _cells.firstMounted?.requestFocus(),
      hint: 'OK play · hold OK for options',
    );
  }

  void _applyFocusIntent(EpisodesPanelView view, {required bool horizontal}) {
    if (_handledGeneration == view.generation) return;
    _handledGeneration = view.generation;
    if (view.focusIntent == EpisodeFocusIntent.none) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (view.focusIntent == EpisodeFocusIntent.seasonControl) {
        if (_seasonNode.context != null) _seasonNode.requestFocus();
        return;
      }
      final landing = view.landing;
      if (landing == null) return;
      final index = view.episodes.indexWhere(
        (episode) =>
            episode.season == landing.season &&
            episode.number == landing.number,
      );
      revealDetailLanding(
        controller: horizontal ? _rail : _list,
        index: index,
        itemCount: view.episodes.length,
        contextOf: () => _cells
            .lookup(view.generation, landing.season, landing.number)
            ?.context,
        alignment: horizontal ? .25 : .35,
      );
    });
  }

  FocusNode _recNode(int index) {
    while (_recNodes.length <= index) {
      _recNodes.add(FocusNode(debugLabel: 'premium-rec-${_recNodes.length}'));
    }
    return _recNodes[index];
  }

  Widget _movieRail(DetailSize size, double gutter) {
    final recs = _m.recommendations;
    if (recs.isEmpty || _m.onRecommendationTap == null) {
      return Center(
        child: Text('No recommendations yet', style: _t.bodyStyle()),
      );
    }
    final width = size.isPhone ? 76.0 : 88.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: gutter, bottom: 7),
          child: DetailSlab('MORE LIKE THIS'),
        ),
        Expanded(
          child: HorizontalMouseWheel(
            controller: _rail,
            child: ListView.separated(
              controller: _rail,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: gutter),
              itemCount: recs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) => DetailEdgeTrap(
                trapLeft: index == 0,
                trapRight: index == recs.length - 1,
                trapUp: true,
                onUp: _m.focus.focusEntry,
                child: _PremiumRecCard(
                  rec: recs[index],
                  width: width,
                  focusNode: _recNode(index),
                  onTap: () => _m.onRecommendationTap!(recs[index]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _movieList(DetailSize size) {
    final recs = _m.recommendations;
    if (recs.isEmpty || _m.onRecommendationTap == null) {
      return Center(
        child: Text('No recommendations yet', style: _t.bodyStyle()),
      );
    }
    return ListView.separated(
      controller: _list,
      itemCount: recs.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: _t.hair),
      itemBuilder: (context, index) => DetailEdgeTrap(
        trapLeft: true,
        trapUp: index == 0,
        trapDown: index == recs.length - 1,
        onLeft: _m.focus.focusEntry,
        onUp: _m.focus.focusEntry,
        child: _PremiumRecRow(
          rec: recs[index],
          focusNode: _recNode(index),
          onTap: () => _m.onRecommendationTap!(recs[index]),
        ),
      ),
    );
  }
}

class _MosaicFeatureTile extends StatefulWidget {
  final String? imageUrl;
  final String eyebrow;
  final String title;
  final String detail;
  final FocusNode focusNode;
  final VoidCallback onTap;

  const _MosaicFeatureTile({
    super.key,
    required this.imageUrl,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.focusNode,
    required this.onTap,
  });

  @override
  State<_MosaicFeatureTile> createState() => _MosaicFeatureTileState();
}

class _MosaicFeatureTileState extends State<_MosaicFeatureTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    return DetailFocusRing(
      focused: _focused,
      radius: t.brRadius,
      child: Material(
        color: t.placeholder,
        borderRadius: t.brRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: widget.focusNode,
          onFocusChange: (focused) => setState(() => _focused = focused),
          onTap: widget.onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Poster(url: widget.imageUrl, cacheWidth: 700),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      t.ground,
                      t.fade(t.ground, .86),
                      t.fade(t.ground, .10),
                    ],
                    stops: const [0, .42, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.fade(t.ground, .78),
                        borderRadius: t.brBtn,
                        border: Border.all(color: t.hair),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        child: Text(
                          widget.eyebrow,
                          style: t.dataStyle(
                            size: 8.5,
                            color: t.callout,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleStyle(
                                  size: 18,
                                  weight: FontWeight.w800,
                                  tracking: -.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.detail,
                                style: t.dataStyle(size: 9.5, color: t.tx2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: t.btnFill,
                            gradient: t.btnGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: t.btnText,
                            size: 21,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParentsGuideDialogBody extends StatefulWidget {
  final ParentsGuideResult guide;
  final bool television;
  final Color accent;
  final DetailTheme theme;

  const _ParentsGuideDialogBody({
    required this.guide,
    required this.television,
    required this.accent,
    required this.theme,
  });

  @override
  State<_ParentsGuideDialogBody> createState() =>
      _ParentsGuideDialogBodyState();
}

class _ParentsGuideDialogBodyState extends State<_ParentsGuideDialogBody> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (direction == 0 || !_scrollController.hasClients) {
      return KeyEventResult.ignored;
    }
    final position = _scrollController.position;
    final target = (position.pixels + direction * 96).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) {
      return KeyEventResult.ignored;
    }
    position.jumpTo(target.toDouble());
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleKey,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(22),
        child: ParentsGuideSection(
          guide: widget.guide,
          tv: widget.television,
          accent: widget.accent,
          theme: widget.theme,
        ),
      ),
    );
  }
}

/// Narrow, large-text episode cell. It intentionally drops the thumbnail and
/// secondary metadata before shrinking text or focus targets; playback and the
/// RIGHT-for-options contract remain identical to the standard vertical row.
class _AccessibleEpisodeRow extends StatelessWidget {
  final TraktEpisode episode;
  final double? progress;
  final bool isNext;
  final FocusNode focusNode;
  final VoidCallback onPlay;
  final VoidCallback onOptions;
  final VoidCallback onLeftEdge;

  const _AccessibleEpisodeRow({
    required this.episode,
    required this.progress,
    required this.isNext,
    required this.focusNode,
    required this.onPlay,
    required this.onOptions,
    required this.onLeftEdge,
  });

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    return DetailEpisodeInteraction(
      focusNode: focusNode,
      gesture: DetailOptionsGesture.rightArrow,
      onPlay: onPlay,
      onOptions: onOptions,
      onLeftEdge: onLeftEdge,
      builder: (context, focused) => DetailFocusRing(
        focused: focused,
        radius: t.brRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: focused ? t.panel : null,
            borderRadius: t.brRadius,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '${episode.number}',
                  style: t.dataStyle(
                    size: 12,
                    color: isNext ? t.callout : t.tx3,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      episode.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyStyle(size: 13, color: t.tx, height: 1.25),
                    ),
                    Text(
                      (progress ?? 0) >= 100
                          ? 'WATCHED · RIGHT FOR OPTIONS'
                          : 'RIGHT FOR OPTIONS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.dataStyle(
                        size: 8.5,
                        color: (progress ?? 0) >= 100 ? t.state : t.tx3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumRecCard extends StatefulWidget {
  final StremioMeta rec;
  final double width;
  final FocusNode focusNode;
  final VoidCallback onTap;

  const _PremiumRecCard({
    required this.rec,
    required this.width,
    required this.focusNode,
    required this.onTap,
  });

  @override
  State<_PremiumRecCard> createState() => _PremiumRecCardState();
}

class _PremiumRecCardState extends State<_PremiumRecCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DetailFocusRing(
              focused: _focused,
              radius: t.brImg,
              child: Material(
                color: t.placeholder,
                borderRadius: t.brImg,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  focusNode: widget.focusNode,
                  onFocusChange: (focused) =>
                      setState(() => _focused = focused),
                  onTap: widget.onTap,
                  child: _Poster(url: widget.rec.poster),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            widget.rec.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodyStyle(size: 10.5, color: _focused ? t.tx : t.tx2),
          ),
        ],
      ),
    );
  }
}

class _PremiumRecRow extends StatefulWidget {
  final StremioMeta rec;
  final FocusNode focusNode;
  final VoidCallback onTap;

  const _PremiumRecRow({
    required this.rec,
    required this.focusNode,
    required this.onTap,
  });

  @override
  State<_PremiumRecRow> createState() => _PremiumRecRowState();
}

class _PremiumRecRowState extends State<_PremiumRecRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    return DetailFocusRing(
      focused: _focused,
      radius: t.brRadius,
      child: Material(
        color: _focused ? t.panel : Colors.transparent,
        borderRadius: t.brRadius,
        child: InkWell(
          focusNode: widget.focusNode,
          borderRadius: t.brRadius,
          onFocusChange: (focused) => setState(() => _focused = focused),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  height: 58,
                  child: ClipRRect(
                    borderRadius: t.brSm,
                    child: _Poster(url: widget.rec.poster),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.rec.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyStyle(size: 12.5, color: t.tx),
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, size: 17, color: t.tx3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  final String? url;
  final int cacheWidth;
  const _Poster({required this.url, this.cacheWidth = 260});

  @override
  Widget build(BuildContext context) {
    final t = DetailThemeScope.of(context);
    if (url == null || url!.isEmpty) return ColoredBox(color: t.placeholder);
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      cacheManager: DebrifyImageCache.manager,
      memCacheWidth: cacheWidth,
      placeholder: (_, __) => ColoredBox(color: t.placeholder),
      errorWidget: (_, __, ___) => ColoredBox(color: t.placeholder),
    );
  }
}
