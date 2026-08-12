import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/debrify_image_cache.dart';
import '../../theme/app_focus.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_scope.dart';
import '../../theme/widgets/focus_expression.dart';
import '../../theme/widgets/parallax_focus.dart';
import '../../utils/dominant_color.dart';
import '../../utils/platform_util.dart';
import '../../utils/wide_touch_scale.dart';

/// What a card is, once a shelf stops being a list of TITLES.
///
/// Continue Watching and the catalog are `StremioMeta`; the favourites rails
/// are not. A playlist is a container, not a title — it has no poster of its
/// own, which is why poster OVERRIDES exist — and an IPTV channel's logo is a
/// wide, often transparent mark that a 2:3 crop destroys. Forcing all four
/// through a poster model is how they end up looking wrong in four different
/// ways.
class SpotlightCard {
  /// Poster, channel logo, or a user override. Null draws the placeholder.
  final String? image;
  final String title;

  /// Item count, "LIVE", a genre — whatever this KIND of thing is identified
  /// by beyond its name.
  final String? subtitle;

  /// 0..100, or null.
  final double? progress;

  final VoidCallback onOpen;
  final VoidCallback? onOptions;
  final SpotlightCardShape shape;

  const SpotlightCard({
    required this.title,
    required this.onOpen,
    this.image,
    this.subtitle,
    this.progress,
    this.onOptions,
    this.shape = SpotlightCardShape.poster,
  });
}

/// Aspect and fit, per kind.
enum SpotlightCardShape {
  /// 2:3, art cropped to fill. Titles.
  poster(2 / 3, BoxFit.cover),

  /// 1:1, art CONTAINED on a plate. A channel logo is a mark, not a still:
  /// cropping it to fill cuts the wordmark in half.
  channel(1, BoxFit.contain),

  /// 16:9, cropped. Containers and wide art.
  wide(16 / 9, BoxFit.cover);

  const SpotlightCardShape(this.aspect, this.fit);

  /// width ÷ height.
  final double aspect;
  final BoxFit fit;
}

/// One row on the board.
///
/// [progressOf] is what makes Continue Watching possible without the board
/// knowing what Continue Watching IS: a shelf that returns null for every
/// item simply draws no bars.
class SpotlightShelf {
  final String title;
  final List<SpotlightCard> items;

  /// This shelf's focus nodes, owned by the host so focus survives a rebuild.
  /// Carried HERE rather than in a parallel list, because two lists that must
  /// stay the same length eventually will not be.
  final List<FocusNode> nodes;

  const SpotlightShelf({
    required this.title,
    required this.items,
    required this.nodes,
  });
}

/// **Spotlight** — the tvOS Home idiom.
///
/// The hero art is a **pinned full-screen backdrop** the shelves ride over —
/// the Apple TV app's grammar. Going DOWN does not scroll the picture away
/// (it used to be the first item of the scroll, which sent a hard band-edge
/// sliding up the screen — the one obviously-not-Apple frame this board
/// produced). Instead the shelves and the hero's identity translate up while
/// the art stays put, and a ground-coloured veil rises with the scroll so the
/// picture dims toward the page ground and the rows stay legible whatever the
/// theme. Only the PICTURE is pinned: identity, dots and the pointer surface
/// ride in the scroll, because text that slides away with the rows is the
/// reference behaviour.
///
/// Compact keeps the in-flow hero (the Apple *phone* measure): its art stops
/// at ~64% of the board and fades into the ground, so there is no band edge
/// to pin away and nothing under the fold to dim.
///
/// The hero is also **a focusable row**: LEFT/RIGHT page it, dots show
/// position, and it parks where you left it. That is the piece that changes
/// Home's focus topology rather than its paint — the other boards take their
/// identity from whatever is focused *below* them and have no cursor of their
/// own.
class SpotlightBoard extends StatefulWidget {
  /// The hero reel. Capped by the caller; parked position is restored by ITEM
  /// ID rather than index, because the rail list re-orders as tracker data
  /// arrives.
  final List<StremioMeta> hero;

  /// The shelves, in order.
  ///
  /// NOT `List<CatalogSection>` any more: Continue Watching and the favourites
  /// rails are neither that shape nor that card — they carry progress, a
  /// context menu, and entries that are not `StremioMeta` at all. A descriptor
  /// lets the host say "here is a row of things and what to do with them"
  /// without the board learning about six data sources.
  final List<SpotlightShelf> sections;

  /// The hero's own node. Registered with the host so sidebar re-entry and
  /// dead-focus reclaim can land on it.
  final FocusNode heroNode;


  /// Ask the host for another page of [row]'s items. Called when focus nears
  /// the end of a shelf — without it only each shelf's FIRST page is ever
  /// reachable, because this board owns its own scroll and the host's
  /// scroll-driven pagination never fires.
  final void Function(int row)? onLoadMoreRow;

  /// Ask the host for another batch of shelves, when DOWN runs out of them.
  ///
  /// Returns whether at least one shelf was appended. Spotlight awaits this
  /// result so the DOWN that started the fetch can finish its move instead of
  /// being swallowed at the old end of the board.
  final Future<bool> Function()? onLoadMoreShelves;

  /// The hero has been resting on [item] long enough to be worth a trailer.
  ///
  /// The board owns the CADENCE; the host owns the video. That split is why
  /// the two cannot fight: there is one timer, here, and the host is told when
  /// rather than deciding for itself.
  final void Function(StremioMeta item)? onDwell;

  /// Paints over the hero while a trailer is playing. Null when the host has
  /// no trailer to show, which is also what reduced motion and the
  /// `home_hero_trailer_enabled` pref produce.
  final Widget? trailer;

  /// Off when the user has disabled hero trailers, or under reduced motion.
  /// The reel still advances — the cadence is the layout, the video is not.
  final bool trailersEnabled;

  /// Tear the trailer down. Called on every exit from the rolling state —
  /// advancing, paging by hand, and losing focus — because a video that
  /// outlives the title it was resolved for is worse than no video.
  final VoidCallback? onTrailerStop;

  /// The addon behind the hero reel, which is the shelf it was taken from.
  final StremioAddon? heroAddon;

  /// Opens the hero. Separate from a shelf's own opener because the hero is
  /// its own row, not a member of one.
  final void Function(StremioMeta, StremioAddon) onHeroOpen;

  /// Published so the shell can light the room with the focused title's
  /// colour, exactly as the other stage layouts do.
  final void Function(String? art, Color? tint)? onAmbient;

  /// The INPUT axis, distinct from size: true on a television, where the
  /// remote drives everything and the cadence is armed by hero focus. False
  /// on phones, tablets and desktop — the hero advances on its own clock,
  /// pages on swipe and dot taps, and (under 600 wide) the whole board takes
  /// the compact presentation. Width never implies input: a narrow TV must
  /// stay a TV.
  final bool dpad;

  const SpotlightBoard({
    super.key,
    required this.hero,
    required this.sections,
    required this.heroNode,
    required this.onHeroOpen,
    required this.heroAddon,
    this.onLoadMoreRow,
    this.onLoadMoreShelves,
    this.onDwell,
    this.onTrailerStop,
    this.trailer,
    this.trailersEnabled = true,
    this.onAmbient,
    this.dpad = true,
  });

  /// The scrolled ground, taken from the THEME.
  ///
  /// It was `0xFF1B1C1C`/`0xFF1F1D1C` — measured off the reference screenshots
  /// at every gutter of a scrolled frame, and hardcoded so the Apple look was
  /// the Apple look whatever theme was selected.
  ///
  /// That stopped being defensible once tokens became editable: this was the
  /// one surface that ignored the Background setting, so changing it moved the
  /// whole app EXCEPT Home, with nothing on screen to explain why. The value
  /// moved into the Look — whose ground has since been re-chosen twice on
  /// real panels (true black, then the palette's Deep Navy; the story lives
  /// on `PremiumLooks.spotlight`) — and this getter simply follows whatever
  /// the active theme says.
  static Color groundOf(AppTheme app) => app.home.bg;

  /// The gradient's lower stop. The reference drifts a few levels lighter down
  /// the page; derived rather than fixed so it drifts from whatever the ground
  /// now is.
  ///
  /// **Flat on Android TV**, where the drift renders as banding rather than as
  /// a drift.
  ///
  /// It is about three 8-bit levels spread over the full screen height — which
  /// is the most fragile thing you can hand that pipeline. Those boxes raster
  /// at ~720p on GLES2-class hardware and let the TV's scaler upscale, and the
  /// Flutter surface is TRANSLUCENT so the underlay trailer can show through;
  /// three levels through a low-res upscale and a blend become wide contour
  /// bands. Apple TV has neither constraint and draws it as intended.
  ///
  /// Returning the ground itself rather than skipping the gradient keeps one
  /// code path: a two-stop gradient between identical colours IS a flat fill.
  /// The drift is below the threshold anyone notices when it works, so nothing
  /// is lost where it is dropped.
  static Color groundLowOf(AppTheme app) => PlatformUtil.isAndroidTvCached
      ? app.home.bg
      : Color.lerp(app.home.bg, app.core.tx, 0.015)!;

  /// Above this, the backdrop's left third is too busy for text and the
  /// identity stack flips to the right edge. Without it, text lands on a face
  /// roughly a third of the time — metahub backdrops are frame grabs, not
  /// editorial stills composed for a caption.
  static const double leftThirdBusy = 0.32;

  @override
  State<SpotlightBoard> createState() => SpotlightBoardState();
}

/// Card metrics as FRACTIONS of the space the board is actually GIVEN.
///
/// The reference is 1920 wide and its posters are 260 with a 40 gap — a pitch
/// of 300. Expressed as absolute logical pixels those only match a panel whose
/// logical width happens to be exactly half of 1920; on anything else the
/// cards come out the wrong size relative to the screen, which is precisely
/// how "a bit big, and less space between them" happens.
///
/// Proportions hold everywhere. The divisors are the raw 1920-scale numbers.
///
/// Measured against the board's own constraints rather than
/// `MediaQuery.sizeOf`, because those differ: tvOS reports a full-screen size
/// while the shell insets the content for overscan safe area (and, under
/// non-pill sidebar styles, for the rail). Sizing off the screen makes every
/// card proportionally too large for the region it is drawn in — a 260-wide
/// card in a 1920 screen becomes a 260-wide card in a ~1800 visible band.
/// The presentation tier — the SIZE axis, chosen from the board's own width
/// but only ever leaving `wide` when the input is not a remote. A narrow TV
/// (UI scale, odd panel) keeps the wide presentation with proportionally
/// smaller cards, so the DPAD ladder never targets widgets that don't exist.
enum _Tier { compact, mid, wide }

class _M {
  final double w;
  final bool dpad;
  final _Tier tier;

  _M(this.w, {this.dpad = true})
      : tier = dpad
            ? _Tier.wide
            : w < 600
                ? _Tier.compact
                : w < 1100
                    ? _Tier.mid
                    : _Tier.wide;

  bool get compact => tier == _Tier.compact;

  /// The type scale for the wide TOUCH tiers — the same correction the
  /// Showcase detail page applies (see `ShowcaseMetrics.k`).
  ///
  /// The wide hero's fixed values (identity type, the logo slot, the
  /// identity/dots insets' non-overlap share) are 960-canvas numbers, and a
  /// TV's logical width IS ~960. A tablet reaches the same layout at its real
  /// width — 1366 on an iPad Pro — where those absolutes render at ~70% of
  /// their designed proportion. Exactly 1.0 on TV (every shipped pixel keeps)
  /// and on compact (its absolutes are phone-measured, not derived); the
  /// formula lives in [wideTouchScale], shared with the detail page.
  double get k => (dpad || compact) ? 1.0 : wideTouchScale(w);

  /// Compact values are MEASURED off the Apple TV phone app on the reference
  /// device (see design/mockups/spotlight_responsive_mockup/): gutter 4.8%, posters 24.3%
  /// with 4.6% gaps (~2.9 per screen plus a peek), fixed type. Mid is the
  /// tablet tier — the TV fractions with the posters bumped for fingers.
  /// Wide is the TV mock's 1920-scale table, byte-for-byte what shipped.
  double get gutter => compact ? w * 0.048 : w * (84 / 1920);
  double get poster => switch (tier) {
        _Tier.compact => w * 0.243,
        _Tier.mid => w * 0.16,
        _Tier.wide => w * (260 / 1920),
      };
  double get posterH => poster * (390 / 260);
  double get gap => switch (tier) {
        _Tier.compact => w * 0.046,
        _Tier.mid => w * 0.026,
        _Tier.wide => w * (40 / 1920),
      };

  /// Card corner radius. 7 is the TV mock's number, moved here from the
  /// card's hardcode; compact grows it the way every phone card idiom does.
  double get radius => switch (tier) {
        _Tier.compact => 10.0,
        _Tier.mid => 8.0,
        _Tier.wide => 7.0,
      };

  /// What the focus effect paints OUTSIDE the resting card, which the row
  /// reserves so the lift lands on ground instead of on the headings.
  ///
  /// The card grows about its centre, so half of the 10% goes upward, and
  /// `ParallaxFocus` rises it a further 7. Reserving that much means nothing
  /// OPAQUE ever reaches the title above.
  ///
  /// The shadow reaches 9 higher still (25 of blur less its 16 of downward
  /// offset) and is deliberately NOT reserved: it is a soft blur whose far
  /// edge is invisible, and paying for it would push every row apart by more
  /// than the reference puts between them.
  ///
  /// Zero on compact: nothing there ever focuses or hovers, so the lift
  /// never fires and the reservation would just be dead air between rows.
  double get liftUp => compact ? 0 : posterH * 0.05 + 7;

  /// Downward the rise works in our favour, so only the growth is reserved.
  double get liftDown => compact ? 0 : posterH * 0.05;
  double get title => compact ? 19.0 : w * (26 / 1920);
  double get caption => compact ? 12.0 : w * (21 / 1920);

  /// The caption strip below the art — compact only; wide overlays it on the
  /// card. One 12pt line plus its 6px gap.
  double get captionBlock => compact ? 24.0 : 0;
}

class SpotlightBoardState extends State<SpotlightBoard> {
  /// The hero as a FRACTION of the board: the art reaches the bottom edge of
  /// the screen, and the first shelf sits ON it.
  ///
  /// Two things were wrong before. It was `540` logical pixels flat, and
  /// logical size differs per device — so one constant drew a hero at ~89% of
  /// an Android TV box and ~40% of an Apple TV. Same code, same number, a
  /// different design on each, and on tvOS a trailer playing in a slot half its
  /// intended height, which is why `cover` was discarding half the frame.
  ///
  /// And the target itself was wrong: ending the artwork above the first shelf
  /// leaves a band of flat grey under the cards at rest, which is exactly what
  /// "the poster is not full screen" describes. The ground is what you land on
  /// once you SCROLL — that is where the measured `rgb(28,28,28)` gutter came
  /// from, and it was taken from scrolled frames and applied to the resting one
  /// by mistake.
  static const double _heroFraction = 1.0;

  /// Compact keeps the hero to ~64% of the board — the Apple phone measure —
  /// with the rows below it in flow rather than riding over the art.
  static const double _heroFractionCompact = 0.64;

  /// How far the first shelf rides up over the hero's lower edge, as a
  /// fraction of the hero. Was 88 of 540, kept in proportion — with a
  /// full-height hero this is what puts the cards OVER the artwork rather than
  /// below it. Compact has no overlap: the hero fades into the ground and the
  /// first shelf starts ON the ground (the reference does exactly this).
  static const double _shelfOverlapFraction = 88 / 540;

  final ScrollController _scroll = ScrollController();

  /// The hero band's height as of the last build — the scroll listener needs
  /// it to decide "scrolled away", and a listener has no BuildContext to
  /// measure with.
  double _heroBandH = 0;

  /// True once the board is scrolled far enough that the pinned hero is
  /// effectively covered. Owns the trailer's lifecycle for SCROLLING, which
  /// touch and wheel produce without ever telling the cursor: DPAD descent
  /// goes through [_down] (which stops the trailer itself), but a swipe or a
  /// wheel just moves the list — and the backdrop being permanently mounted
  /// now, the video would keep decoding behind an opaque veil forever.
  bool _scrolledAway = false;

  /// Crossing detector for [_scrolledAway]: teardown on the way out,
  /// re-arm on the way back. Also called on metrics corrections (see
  /// [_board]) because a clamped offset never notifies the controller.
  void _onBoardScrolled() {
    if (_heroBandH <= 0 || !_scroll.hasClients) return;
    final away = _scroll.offset > _heroBandH * 0.35;
    if (away == _scrolledAway) return;
    _scrolledAway = away;
    if (away) {
      _cadence?.cancel();
      _cadence = null;
      _stopRolling();
    } else {
      // Applies its own gates (DPAD hero focus, pref, dwell callback), so
      // this is safe to fire from any scroll back to the top.
      _restartCadence();
    }
  }

  /// Which hero item is showing. Held by ID so a rail re-order does not move
  /// the page under the user.
  String? _heroId;
  int _row = -1; // -1 = the hero owns the cursor
  final Map<int, int> _col = {};

  /// A DOWN at the last loaded shelf owns the catalog fetch until it settles.
  /// While true, repeated key events cannot start duplicate loads and the
  /// board paints a visible acknowledgement instead of looking exhausted.
  bool _loadingMoreShelves = false;

  /// Left-third luminance per backdrop URL. Probed once; the result decides
  /// which side the identity sits on.
  final Map<String, double> _leftThird = {};

  /// The hero's cadence: art, then a trailer. **Never an advance.**
  ///
  ///     art (4s) ──▶ trailer (loops until a deliberate move)
  ///      ▲                       │
  ///      └── swipe / LEFT/RIGHT ─┘
  ///
  /// The reel used to page itself (art → trailer → advance → next art, and a
  /// plain 4s advance with trailers off). Killed by user call, on every
  /// device: a carousel that moves under you takes the choice away — the
  /// reel now moves ONLY on a swipe, a dot tap, or a DPAD page. The one
  /// timer's one remaining job is the trailer dwell.
  ///
  /// ONE timer with ONE owner. The shared `_scheduleHeroTrailer` is excluded
  /// for this style precisely so the two cannot interleave and start a trailer
  /// under the wrong title.
  static const Duration _artDwell = Duration(seconds: 4);

  Timer? _cadence;

  /// Whether the cadence has asked the host for a trailer.
  ///
  /// Bookkeeping for the CLOCK only — it must never gate the trailer widget.
  /// The host owns the engine's lifetime and tears it down on playback launch,
  /// route push and style change; a second opinion here is how a released
  /// engine stayed mounted.
  bool _rolling = false;

  /// One funnel for leaving the rolling state, so no exit path can forget to
  /// tell the host to tear the video down.
  void _stopRolling() {
    if (!_rolling) return;
    if (mounted) setState(() => _rolling = false);
    widget.onTrailerStop?.call();
  }

  void _restartCadence() {
    _cadence?.cancel();
    // Nulled, not just cancelled: didUpdateWidget's reconcile decides "is a
    // timer armed" by null-ness, and a cancelled-but-non-null handle reads
    // as armed.
    _cadence = null;
    _rolling = false;
    if (!mounted) return;
    // The cadence's only job is the trailer dwell now — with no trailer to
    // arm there is nothing to time. The reel itself moves only on input.
    if (!widget.trailersEnabled || widget.onDwell == null) return;
    // TV: frozen while focus is off the hero. `_row == -1` alone is NOT that
    // test: it stays -1 when focus goes to the sidebar, another tab, or a
    // pushed detail route — the node's own `hasFocus` is the real question.
    // Touch has no focus to gate on; visibility is checked at FIRE time.
    if (widget.dpad && (_row >= 0 || !widget.heroNode.hasFocus)) return;
    _cadence = Timer(_artDwell, _onArtDone);
  }

  /// Dot tap / swipe target: show slide [i] and restart the clock.
  void _jumpTo(int i) {
    if (i < 0 || i >= widget.hero.length) return;
    _stopRolling();
    setState(() => _heroId = widget.hero[i].id);
    _probe();
    _restartCadence();
  }

  void _onArtDone() {
    // The one-shot is consumed the moment this runs — null it, or the
    // reconcile in didUpdateWidget reads a dead handle as "armed" and a
    // disable→re-enable of trailers strands the cadence forever.
    _cadence = null;
    if (!mounted || _row >= 0) return;
    // Scrolled off the hero (touch/wheel — a DPAD descent goes through
    // [_down] and cancels the clock itself): do not start a decoder behind
    // the veil. No re-arm — scrolling back under the threshold restarts the
    // cadence via [_onBoardScrolled].
    if (_scrolledAway) return;
    // Touch: a covered or backgrounded board must not spin up an engine for
    // a hero nobody can see. Re-arm and wait rather than dying — the route
    // pop that reveals the board again gives no callback here.
    if (!widget.dpad) {
      final route = ModalRoute.of(context);
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final visible = (route == null || route.isCurrent) &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed);
      if (!visible) {
        _cadence = Timer(_artDwell, _onArtDone);
        return;
      }
    }
    final item = _heroItem;
    if (item == null) {
      // An empty reel consumed the one-shot — re-arm, or a hero arriving
      // later (CW mounts before the first catalog section) finds a dead
      // clock and never dwells.
      _cadence = Timer(_artDwell, _onArtDone);
      return;
    }
    if (widget.trailersEnabled && widget.onDwell != null) {
      // Once a trailer is rolling the reel stays put — the video loops until
      // the next deliberate move (swipe, dot tap, LEFT/RIGHT, DOWN).
      setState(() => _rolling = true);
      widget.onDwell!(item);
    }
    // Never an advance — see the cadence comment.
  }

  /// Best full-bleed art for [item]: its own backdrop, else a metahub 16:9
  /// still derived from its IMDb id — the same synchronous trick the other
  /// stage layouts use, because catalog and Continue Watching items carry a
  /// poster but rarely a backdrop — and the poster only as a last resort.
  /// The poster fallback is what blurry heroes are made of (~350px of 2:3
  /// art cover-cropped over a full screen), so it is LAST, not second.
  static String? _heroArt(StremioMeta item) {
    final b = item.background;
    if (b != null && b.isNotEmpty) return b;
    final tt = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    if (tt != null) {
      return 'https://images.metahub.space/background/medium/$tt/img';
    }
    final p = item.poster;
    return (p != null && p.isNotEmpty) ? p : null;
  }

  int get _heroIndex {
    if (widget.hero.isEmpty) return 0;
    final i = widget.hero.indexWhere((m) => m.id == _heroId);
    return i < 0 ? 0 : i;
  }

  StremioMeta? get _heroItem =>
      widget.hero.isEmpty ? null : widget.hero[_heroIndex];

  /// The id of the slide currently SHOWING — the host's suppression snapshot
  /// reads this at content-playback launch, because its own bookkeeping only
  /// knows the last *dwelled* item and playback can start before any dwell.
  String? get currentHeroId => _heroItem?.id;

  @override
  void initState() {
    super.initState();
    _heroId = widget.hero.isNotEmpty ? widget.hero.first.id : null;
    widget.heroNode.addListener(_onHeroFocus);
    _scroll.addListener(_onBoardScrolled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _probe();
      _restartCadence();
    });
  }

  @override
  void didUpdateWidget(SpotlightBoard old) {
    super.didUpdateWidget(old);
    // The reel can change under us as sections load. Keep the parked item if
    // it is still present; otherwise fall back to the head rather than to a
    // stale index pointing at a different title.
    // The host can hand us a different node across a rebuild; without moving
    // the listener the old node keeps one forever and the new one has none.
    if (old.heroNode != widget.heroNode) {
      old.heroNode.removeListener(_onHeroFocus);
      widget.heroNode.addListener(_onHeroFocus);
    }
    // The trailer pref flipped: rebuild the cadence from scratch. Disable
    // must also clear a stale `_rolling` (or nothing ever re-arms — the
    // reconcile below skips while rolling), and enable must arm a clock that
    // has nothing else to wake it.
    if (old.trailersEnabled != widget.trailersEnabled) {
      _restartCadence();
    }
    if (_heroId != null && !widget.hero.any((m) => m.id == _heroId)) {
      // The title we were on is gone. Tear the trailer down FIRST: it was
      // resolved for that title, and leaving it rolling paints it over the new
      // head until the 20s cap expires.
      _stopRolling();
      _heroId = widget.hero.isNotEmpty ? widget.hero.first.id : null;
      _restartCadence();
    } else if (_cadence == null && !_rolling) {
      // Reconcile for BOTH inputs: the host often enables trailers (the
      // pref read lands) or grows the reel AFTER first build, with the
      // parked id intact — the branch above never runs then, and without
      // this the dwell clock would simply never start. _restartCadence
      // applies its own gates (focus on DPAD, pref, dwell callback), so an
      // uncalled-for restart is a no-op, not a stolen cadence.
      _restartCadence();
    }
    // A board reload can shrink or reorder the shelves under a parked cursor.
    // `_row` is positional, so without this the next arrow key indexes past
    // the end of `rowNodes` and throws.
    if (_row >= widget.sections.length) {
      _row = widget.sections.isEmpty ? -1 : widget.sections.length - 1;
    }
    for (final row in _col.keys.toList()) {
      if (row >= widget.sections.length) {
        _col.remove(row);
        continue;
      }
      final len = widget.sections[row].nodes.length;
      if (len == 0) {
        _col.remove(row);
      } else if ((_col[row] ?? 0) >= len) {
        _col[row] = len - 1;
      }
    }
    _probe();
  }

  /// Re-arms when the hero actually holds focus and stops the moment it does
  /// not — covering the sidebar, tab switches and pushed routes in one place.
  void _onHeroFocus() {
    if (!mounted) return;
    if (widget.heroNode.hasFocus) {
      _restartCadence();
    } else {
      _cadence?.cancel();
      _stopRolling();
    }
  }

  @override
  void dispose() {
    widget.heroNode.removeListener(_onHeroFocus);
    if (_rolling) widget.onTrailerStop?.call();
    _cadence?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Bumped on every hero change. A probe that resolves after the user has
  /// paged on must not publish its colour over the current one.
  int _probeGen = 0;
  final Map<String, Color?> _tints = {};

  Future<void> _probe() async {
    // The RESOLVED art, not the raw fields — tint and side-flip must be
    // measured on the image actually drawn.
    final item = _heroItem;
    final url = item == null ? null : _heroArt(item);
    if (url == null || url.isEmpty) return;
    final gen = ++_probeGen;

    // Publish FIRST from cache when we have it. Skipping the publish for a
    // cached URL meant paging A→B→A left B's art and tint on the shell —
    // the cache short-circuited the only code path that told anyone.
    if (_tints.containsKey(url)) {
      widget.onAmbient?.call(url, _tints[url]);
    } else {
      final tint = await extractDominantColor(
        CachedNetworkImageProvider(url,
            cacheManager: DebrifyImageCache.manager),
      );
      if (!mounted || gen != _probeGen) return;
      setState(() => _remember(url, tint));
      widget.onAmbient?.call(url, tint);
    }
    unawaited(_warmNext());
  }

  /// Luminance of the extracted colour stands in for "is the left third busy":
  /// a bright dominant means a bright image, and a bright image is one whose
  /// text side cannot be trusted. A true left-third measurement would be
  /// better and is noted in the plan.
  void _remember(String url, Color? tint) {
    _leftThird[url] = tint == null ? 0.0 : tint.computeLuminance();
    _tints[url] = tint;
  }

  /// Resolve the NEXT slide's art while this one is still showing.
  ///
  /// Without this, freezing the side below would mean every slide's FIRST
  /// appearance used the default side, because the probe cannot possibly have
  /// finished by the time the slide is drawn. The cadence gives us seconds of
  /// lead time; one image is a cheap way to spend it.
  Future<void> _warmNext() async {
    if (widget.hero.length < 2) return;
    final next = widget.hero[(_heroIndex + 1) % widget.hero.length];
    final url = _heroArt(next);
    if (url == null || url.isEmpty || _tints.containsKey(url)) return;
    final tint = await extractDominantColor(
      CachedNetworkImageProvider(url, cacheManager: DebrifyImageCache.manager),
    );
    if (!mounted) return;
    setState(() => _remember(url, tint));
  }

  /// Which item `_flipValue` was decided for.
  String? _flipFor;
  bool _flipValue = false;

  /// The side the identity sits on, FROZEN for as long as an item is showing.
  ///
  /// This used to read `_leftThird` directly on every build. That map is
  /// filled by an async probe, so a slide appeared with its logo on one side
  /// and then, a second or two later, jumped to the other as the probe landed
  /// — the one thing a title card must never do while someone is reading it.
  ///
  /// Memoised by item id rather than recomputed: a probe that resolves for the
  /// slide currently on screen updates the map for NEXT time, and moves
  /// nothing now. `_warmNext` is what keeps "next time" from being the common
  /// case.
  bool get _flip {
    final item = _heroItem;
    if (item == null) return false;
    if (_flipFor != item.id) {
      _flipFor = item.id;
      final url = _heroArt(item);
      _flipValue = url != null &&
          (_leftThird[url] ?? 0) > SpotlightBoard.leftThirdBusy;
    }
    return _flipValue;
  }

  // ── movement ───────────────────────────────────────────────────────────

  void _go(FocusNode node, Offset dir) {
    ParallaxTravel.note(dir);
    node.requestFocus();
  }

  void _page(int delta) {
    if (widget.hero.length < 2) return;
    final n = widget.hero.length;
    final next = (_heroIndex + delta + n) % n;
    _stopRolling();
    setState(() => _heroId = widget.hero[next].id);
    ParallaxTravel.note(Offset(delta.toDouble(), 0));
    _probe();
    _restartCadence();
  }

  Future<void> _loadShelvesAndFinishDown() async {
    final load = widget.onLoadMoreShelves;
    if (load == null || _loadingMoreShelves) return;

    final origin = FocusManager.instance.primaryFocus;
    final oldLength = widget.sections.length;
    setState(() => _loadingMoreShelves = true);

    var appended = false;
    try {
      appended = await load();
    } catch (_) {
      // A catalog failure is recoverable: leave focus where it was so another
      // DOWN can retry, and always remove the loading acknowledgement below.
    }
    if (!mounted) return;
    setState(() => _loadingMoreShelves = false);
    if (!appended) return;

    // The host's setState that appended the shelves mounts their focus nodes
    // on the next frame. Complete the original DOWN only if the user is still
    // on the exact card that requested it; a slow addon must never pull focus
    // back after they moved sideways or opened the sidebar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.sections.length <= oldLength) return;
      // Inserting a leading shelf reuses the positional shelf elements and can
      // briefly detach [origin], leaving primaryFocus null. That is safe to
      // recover. A different focused node means the user deliberately moved;
      // a different route means they opened content while the addon loaded.
      final primary = FocusManager.instance.primaryFocus;
      if ((primary != null && !identical(primary, origin)) ||
          !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      // Continue Watching and favourites resolve independently and can insert
      // shelves at the front while the catalog request is in flight. Find the
      // origin by its stable FocusNode after the rebuild instead of assuming
      // the old list length is still the appended shelf's index.
      final currentRow = widget.sections.indexWhere(
        (section) => section.nodes.contains(origin),
      );
      if (currentRow < 0 || currentRow + 1 >= widget.sections.length) return;
      setState(() => _row = currentRow + 1);
      _focusRow(_row, const Offset(0, 1));
    });
  }

  void _down() {
    if (_row < 0) {
      if (widget.sections.isEmpty) return;
      _stopRolling();
      setState(() => _row = 0);
      _cadence?.cancel();
      _focusRow(0, const Offset(0, 1));
      return;
    }
    if (_row + 1 >= widget.sections.length) {
      // Out of shelves: retain this DOWN while the next batch loads. When it
      // lands, focus advances into its first shelf without a second keypress.
      unawaited(_loadShelvesAndFinishDown());
      return;
    }
    setState(() => _row = _row + 1);
    _focusRow(_row, const Offset(0, 1));
  }

  void _up() {
    if (_row <= 0) {
      setState(() => _row = -1);
      _restartCadence();
      _go(widget.heroNode, const Offset(0, -1));
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    setState(() => _row = _row - 1);
    _focusRow(_row, const Offset(0, -1));
  }

  void _focusRow(int row, Offset dir) {
    if (row < 0 || row >= widget.sections.length) return;
    final nodes = widget.sections[row].nodes;
    if (nodes.isEmpty) return;
    final col = (_col[row] ?? 0).clamp(0, nodes.length - 1);
    _go(nodes[col], dir);
  }

  /// Where the cursor ACTUALLY is in [nodes].
  ///
  /// `_col` is bookkeeping and can drift — a scroll-into-view, a rebuild, or
  /// anything that moves focus without going through `_walk` leaves it stale.
  /// A stale column is what made LEFT fall through while focus sat mid-row,
  /// handing the key to the shell's geometric search, which then jumped to
  /// whatever row happened to be nearest.
  int _liveCol(List<FocusNode> nodes) {
    final i = nodes.indexWhere((n) => n.hasFocus);
    if (i >= 0) return i;
    return (_col[_row] ?? 0).clamp(0, nodes.length - 1);
  }

  /// The shelf that actually holds focus, or -1 for the hero.
  int _liveRow() {
    for (var i = 0; i < widget.sections.length; i++) {
      if (widget.sections[i].nodes.any((n) => n.hasFocus)) return i;
    }
    return -1;
  }

  void _walk(int delta) {
    if (_row < 0 || _row >= widget.sections.length) {
      _page(delta);
      return;
    }
    final nodes = widget.sections[_row].nodes;
    if (nodes.isEmpty) return;
    final at = _liveCol(nodes);
    final next = at + delta;
    if (next < 0 || next >= nodes.length) return;
    // No setState: a horizontal step changes nothing this board PAINTS —
    // the cursor's visuals live inside each cell's own Focus widget, and
    // `_col` is read only by the focus-targeting helpers. Wrapped in
    // setState it rebuilt the hero stack and every shelf shell on every
    // LEFT/RIGHT of a held key — per-keypress cost a MiBox-class CPU
    // renders as visible lag.
    _col[_row] = next;
    _go(nodes[next], Offset(delta.toDouble(), 0));
    // Four from the end is roughly one screen of posters — enough lead time
    // for a page to land before the cursor reaches where it would have
    // stopped.
    if (next >= nodes.length - 4) widget.onLoadMoreRow?.call(_row);
  }

  KeyEventResult _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Re-sync from reality before acting on it.
    final live = _liveRow();
    if (live != _row) _row = live;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _down();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _up();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _walk(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.gameButtonA:
        // The hero was focusable and inert: arrows paged it, but OK did
        // nothing at all, so the reel could be browsed and never opened.
        final item = _heroItem;
        final addon = widget.heroAddon;
        if (_row < 0 && item != null && addon != null) {
          widget.onHeroOpen(item, addon);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.arrowLeft:
        // Column 0 and LEFT again falls THROUGH, so the shell's sidebar
        // handler sees it. That is the one and only way in, per the LEFT-only
        // policy — nothing here calls focusTvSidebar.
        //
        // Tested against LIVE focus, not `_col`: falling through from the
        // middle of a row hands the key to a geometric search that lands in
        // another row, which is what made the sidebar hard to reach.
        if (_row >= 0 && _row < widget.sections.length) {
          final nodes = widget.sections[_row].nodes;
          if (nodes.isEmpty || _liveCol(nodes) == 0) {
            return KeyEventResult.ignored;
          }
        }
        // The hero obeys the same rule as a shelf: at the FIRST item there is
        // nothing to its left but the sidebar. It used to wrap round to the
        // last slide instead, which made the reel a loop with no exit — the
        // one gesture that opens the sidebar was the one gesture it ate.
        if (_row < 0 && (widget.hero.length < 2 || _heroIndex == 0)) {
          return KeyEventResult.ignored;
        }
        _walk(-1);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Where the shell should land focus on re-entry.
  FocusNode? focusTarget() {
    if (_row < 0) return widget.heroNode;
    if (_row >= widget.sections.length) return widget.heroNode;
    final nodes = widget.sections[_row].nodes;
    if (nodes.isEmpty) return widget.heroNode;
    return nodes[(_col[_row] ?? 0).clamp(0, nodes.length - 1)];
  }

  // ── paint ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) => _onKey(e),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final m = _M(constraints.maxWidth, dpad: widget.dpad);
          // The hero is measured against the board's real height, so it is the
          // same share of the screen on every panel.
          final viewport = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;
          return _board(
            m,
            viewport * (m.compact ? _heroFractionCompact : _heroFraction),
          );
        },
      ),
    );
  }

  Widget _board(_M m, double heroH) {
    _heroBandH = heroH;
    final app = AppThemeScope.of(context);
    final ground = SpotlightBoard.groundOf(app);
    final list = ListView(
      controller: _scroll,
      padding: EdgeInsets.zero,
      children: [
        // Laid out 88 short so the first shelf sits over the hero's lower
        // edge; the band overflows to the hero's full height so its contents
        // lay out against the same geometry the pinned art is drawn in. On
        // wide this band carries only the hero's FOREGROUND (identity, dots,
        // pointer surface, focus node) — the picture itself is pinned behind
        // the list in the Stack below. Compact has no overlap and keeps art
        // and identity together in flow — the hero fades to ground and the
        // rows follow.
        SizedBox(
          height: heroH * (1 - (m.compact ? 0 : _shelfOverlapFraction)),
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: heroH,
            child: SizedBox(height: heroH, child: _hero(m, heroH)),
          ),
        ),
        // The first shelf overlaps the hero's lower edge — the tell that
        // the page continues.
        //
        // The hero is drawn 88 SHORTER than its visual height rather than
        // the shelves being transformed up over it. A `Transform` moves
        // paint and hit-testing but leaves the ListView's extent alone, so
        // the overlap reappears as a phantom 88px gap at the bottom and
        // the page overscrolls past its own last shelf. Sizing the hero
        // box is the version the scroll extent agrees with.
        Padding(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.sections.length; i++) _shelf(i, m),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
    // A board reload can SHRINK the list under a parked scroll. The framework
    // clamps the offset during layout WITHOUT notifying the controller, so
    // the veil and the scrolled-away trailer gate would keep acting on an
    // offset the list no longer has — a hero veiled opaque with nothing left
    // to scroll back from. Metrics changes on the board's own axis are rare
    // (shelf batches, viewport resizes), so a rebuild is cheap; depth 0
    // filters out every horizontal shelf list bubbling through.
    final content = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        if (n.depth == 0) {
          // Always re-run the crossing detector — a clamped offset never
          // notifies the controller (cheap: no rebuild of its own).
          _onBoardScrolled();
          // The rebuild exists ONLY for the touch veil, whose ramp reads
          // the clamped offset. The TV veil snaps off the cursor row and
          // never reads the offset — and on TV every board-entry batch
          // append changes the extent, so this setState was a second full
          // rebuild per append, stacked on the append's own, during the
          // exact seconds a MiBox is busiest.
          if (!widget.dpad && mounted) setState(() {});
        }
        return false;
      },
      child: list,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ground, SpotlightBoard.groundLowOf(app)],
        ),
      ),
      // Wide pins the picture BEHIND the scroll view. A Scrollable claims
      // every pointer in its viewport, which is fine here because nothing in
      // the backdrop is interactive — the hero's tap/swipe surface and the
      // tappable dots ride in the list with the identity.
      child: m.compact
          ? content
          : Stack(
              fit: StackFit.expand,
              children: [
                // Its own layer: the backdrop is a full-screen image under
                // two full-screen gradients — the most expensive paint on
                // the page. Isolated, a board rebuild (row moves, the
                // trailer's rolling flips) re-composites a cached texture
                // instead of re-rasterising all three.
                RepaintBoundary(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: heroH,
                      child: _heroBackdrop(heroH),
                    ),
                  ),
                ),
                content,
                if (_loadingMoreShelves)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 20,
                    child: IgnorePointer(
                      child: Center(
                        child: DecoratedBox(
                          key: const ValueKey('spotlight-loading-more-shelves'),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 9),
                                Text(
                                  'Loading more',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _hero(_M m, double heroH) {
    if (m.compact) return _heroCompact(m);
    return _heroWide(m, heroH);
  }

  /// The phone hero — the Apple phone idiom, not the TV hero cropped.
  ///
  /// Centered identity stack over the art's lower third (logo → metadata →
  /// CTA → dots), a vertical scrim whose bottom stop is the page ground
  /// exactly (the seam rule), swipe paging, tappable dots. No description
  /// line and no side-flip heuristic: there is no "side" when the stack is
  /// centered.
  Widget _heroCompact(_M m) {
    final item = _heroItem;
    if (item == null) return const SizedBox.shrink();
    final url = _heroArt(item);
    final app = AppThemeScope.of(context);
    final ground = SpotlightBoard.groundOf(app);
    final rolling = _rolling;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 120) return;
        _jumpTo((_heroIndex + (v < 0 ? 1 : -1) + widget.hero.length) %
            widget.hero.length);
      },
      onTap: () {
        final addon = widget.heroAddon;
        if (addon != null) widget.onHeroOpen(item, addon);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: url,
              key: ValueKey(url),
              fit: BoxFit.cover,
              cacheManager: DebrifyImageCache.manager,
              // Decode at the PANEL's resolution, not a guessed constant —
              // 900 was under a 1080-class phone's physical width (390 × 3),
              // so the one full-bleed image on the screen was the soft one.
              // Clamped: metahub art tops out around 1920.
              memCacheWidth: (MediaQuery.devicePixelRatioOf(context) *
                      MediaQuery.sizeOf(context).width)
                  .round()
                  .clamp(720, 1920),
              fadeInDuration: const Duration(milliseconds: 420),
              placeholder: (_, __) => ColoredBox(color: ground),
              // Same guess-404 fallback as the wide backdrop: derived
              // metahub art can miss, and the poster beats a blank hero.
              errorWidget: (_, __, ___) =>
                  (item.poster != null &&
                          item.poster!.isNotEmpty &&
                          item.poster != url)
                      ? CachedNetworkImage(
                          imageUrl: item.poster!,
                          fit: BoxFit.cover,
                          cacheManager: DebrifyImageCache.manager,
                          memCacheWidth: 900,
                          placeholder: (_, __) => ColoredBox(color: ground),
                          errorWidget: (_, __, ___) =>
                              ColoredBox(color: ground),
                        )
                      : ColoredBox(color: ground),
            ),
          // The trailer, when the host supplies one. This was mounted only in
          // the WIDE hero — so the phone resolved a stream into a layer that
          // was never in the tree, which read as "trailers don't load".
          if (widget.trailer != null) Positioned.fill(child: widget.trailer!),
          // One vertical scrim doing both jobs: a light cap up top so the
          // status-bar clock stays readable over bright art, and a heavy bed
          // below for the identity — ending ON the ground so the hero meets
          // the rows without a seam. Thinned while the picture rolls, same
          // rule as everywhere else tonight: snapped, and the bottom stop is
          // still the ground exactly so the seam never opens.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: rolling
                      ? [
                          const Color(0x2E000000),
                          const Color(0x00000000),
                          const Color(0x00000000),
                          ground.withValues(alpha: 0.55),
                          ground,
                        ]
                      : [
                          const Color(0x6B000000),
                          const Color(0x00000000),
                          const Color(0x00000000),
                          ground.withValues(alpha: 0.78),
                          ground,
                        ],
                  stops: rolling
                      ? const [0, 0.18, 0.62, 0.88, 1]
                      : const [0, 0.24, 0.46, 0.8, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 12,
            child: _identityCompact(item, m),
          ),
        ],
      ),
    );
  }

  Widget _identityCompact(StremioMeta item, _M m) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: _LogoOrTitle(
            url: item.logo,
            name: item.name,
            align: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            item.type == 'series' ? 'Series' : 'Film',
            ...(item.genres ?? const []).take(2),
          ].join(' · '),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.white.withValues(alpha: 0.86),
          ),
        ),
        const SizedBox(height: 12),
        // The CTA the mock promises. "Open" rather than "Play": it routes to
        // the detail page (the same thing OK does on TV) — a button that says
        // Play and then shows a detail page would be a lie.
        _HeroOpenPill(
          onTap: () {
            final addon = widget.heroAddon;
            if (addon != null) widget.onHeroOpen(item, addon);
          },
        ),
        if (widget.hero.length > 1) ...[
          const SizedBox(height: 13),
          _dots(tappable: true),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  /// The TV hero's SCROLLING half: identity, dots, pointer surface, focus
  /// node. The picture it reads against is [_heroBackdrop], pinned behind the
  /// list — split so the text can ride away with the shelves while the art
  /// stays put.
  Widget _heroWide(_M m, double heroH) {
    final item = _heroItem;
    if (item == null) return const SizedBox.shrink();
    final wide = _heroForeground(m, item, heroH);
    if (widget.dpad) return wide;
    // Desktop and tablet drive the same wide layout by pointer/touch: swipe
    // pages the reel, a tap opens the showcased title — the exact gestures
    // the compact hero has. TV returns the bare stack above, untouched.
    // This surface must live HERE, in the list, not on the backdrop: the
    // Scrollable in front of the backdrop claims every pointer in its
    // viewport, so a tap layer down there would never hear anything.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 120 || widget.hero.length < 2) return;
        _jumpTo((_heroIndex + (v < 0 ? 1 : -1) + widget.hero.length) %
            widget.hero.length);
      },
      onTap: () {
        final addon = widget.heroAddon;
        if (addon != null) widget.onHeroOpen(item, addon);
      },
      child: wide,
    );
  }

  /// The pinned picture: art, trailer, scrims, and the scroll veil. Sits
  /// BEHIND the scroll view (see [_board]); everything here is
  /// non-interactive by construction.
  Widget _heroBackdrop(double heroH) {
    final item = _heroItem;
    if (item == null) return const SizedBox.shrink();
    final url = _heroArt(item);
    final flip = _flip;
    // Both scrims below were tuned against a STILL, where they only have to
    // keep white text off busy artwork. Left at that strength over a moving
    // picture they are most of why the trailer reads dim: the identity scrim
    // blacks out the left two thirds, and the ground fade covers 260 of the
    // band's 540 across its full width.
    //
    // The page already has a name for this — theater, "veils thin to
    // near-clear" — but that flag is read only inside the Canvas branch and
    // never reaches this board, so Spotlight armed the timer and got none of
    // the lift. Driven off the board's own cadence flag instead, which is the
    // thing that actually knows a picture is rolling.
    //
    // Snapped, not tweened: animating a full-width gradient every frame is
    // exactly what the TV veil policy exists to avoid.
    final rolling = _rolling;
    final app = AppThemeScope.of(context);
    final ground = SpotlightBoard.groundOf(app);
    // The legibility bed under the hero's white identity — always dark, see the
    // gradient below.
    final bed = Color.lerp(ground, const Color(0xFF000000), 0.75)!;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null && url.isNotEmpty)
          CachedNetworkImage(
            imageUrl: url,
            key: ValueKey(url),
            fit: BoxFit.cover,
            cacheManager: DebrifyImageCache.manager,
            // Decode at the PANEL's resolution off-TV, same as the compact
            // hero — 1400 flat was under a retina desktop's physical width,
            // so the one full-bleed image on the screen was the soft one.
            // TV keeps the 1400: its panels sit behind the box's own
            // upscaler and the decode budget there is the tighter constraint
            // (see TvHeroArtworkQuality).
            memCacheWidth: widget.dpad
                ? 1400
                : (MediaQuery.devicePixelRatioOf(context) *
                        MediaQuery.sizeOf(context).width)
                    .round()
                    .clamp(720, 1920),
            fadeInDuration: const Duration(milliseconds: 420),
            placeholder: (_, __) => ColoredBox(color: ground),
            // The derived metahub URL is a GUESS — when it 404s (no still
            // for that title), fall back to the poster rather than a flat
            // ground: a soft hero beats a blank one.
            errorWidget: (_, __, ___) =>
                (item.poster != null &&
                        item.poster!.isNotEmpty &&
                        item.poster != url)
                    ? CachedNetworkImage(
                        imageUrl: item.poster!,
                        fit: BoxFit.cover,
                        cacheManager: DebrifyImageCache.manager,
                        memCacheWidth: 1400,
                        placeholder: (_, __) => ColoredBox(color: ground),
                        errorWidget: (_, __, ___) =>
                            ColoredBox(color: ground),
                      )
                    : ColoredBox(color: ground),
          ),
        // Mounted whenever the HOST supplies one — never gated on this
        // board's own `_rolling`.
        //
        // Gating it here kept the layer alive after the host tore the trailer
        // down (`_clearHeroTrailer` on playback launch), so its media_kit
        // engine was still holding a VideoOutput when the player created its
        // own. Two VideoOutputs is SIGABRT on tvOS — the crash was at
        // `enableHardwareAcceleration`, in the second one's constructor.
        //
        // The host already owns this lifecycle for every other board; the
        // board's job is the cadence, and only the cadence.
        if (widget.trailer != null) Positioned.fill(child: widget.trailer!),
        // The identity scrim, on whichever side the text is. Pinned WITH the
        // art rather than scrolling with the text it serves: it covers that
        // side's full height, so the identity stays on scrimmed picture for
        // its whole upward travel — and a scrim that translated away with
        // the list would drag its visible edge up the artwork.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: flip ? const Alignment(1, -0.2) : const Alignment(-1, -0.2),
                end: flip ? const Alignment(-1, 0.2) : const Alignment(1, 0.2),
                colors: rolling
                    ? const [
                        Color(0x9E000000),
                        Color(0x66000000),
                        Color(0x1C000000),
                        Color(0x00000000),
                      ]
                    : const [
                        Color(0xE0000000),
                        Color(0xA8000000),
                        Color(0x2E000000),
                        Color(0x00000000),
                      ],
                stops: const [0, 0.26, 0.52, 0.68],
              ),
            ),
          ),
        ),
        // Fades into the SHELF GROUND, not into black — a scrim landing on a
        // colour the page never paints leaves a visible seam where the hero
        // ends.
        IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              // Pulled in tight while the picture rolls. The seam still has to
              // be sealed — the bottom stop is the ground colour exactly, so
              // the hero still meets the shelf without a visible edge — but
              // the long soft tail costs half the frame for no legibility.
              //
              // Deliberately absolute, unlike the hero's own height: this is a
              // blend DISTANCE, not a share of the layout, and a fade that
              // scaled with the panel would smear further on a large one for no
              // reason. The identity's `bottom` insets below are the same kind
              // of number.
              height: rolling ? 150 : 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    // TWO jobs, and only one of them follows the ground.
                    //
                    // The bottom stop is the page ground exactly, so the hero
                    // meets the shelf with no seam. Everything above it is a
                    // legibility bed for the hero's identity and dots, which
                    // are white because they sit on a photograph — so it stays
                    // DARK. Tinting the whole ramp with the ground put a white
                    // wash under white text the moment a pale background was
                    // chosen.
                    colors: [
                      ground,
                      bed.withValues(alpha: 0.92),
                      bed.withValues(alpha: 0.45),
                      bed.withValues(alpha: 0),
                    ],
                    stops: const [0.04, 0.22, 0.56, 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        // The veil — what going DOWN does to the picture now that it no
        // longer scrolls away. Ground-coloured for the same reason the fade
        // above ends on ground: the rows and their titles are inked for the
        // page ground, so the picture must dim TOWARD it — a black veil
        // would put theme-inked text on a surface the theme never chose.
        //
        // A solid fill whose alpha lives in the COLOUR — an Opacity widget
        // would add a compositing layer per change — inside its own
        // RepaintBoundary, so a veil change redraws one flat quad and never
        // dirties the layer holding the art and both gradients.
        //
        // TWO drivers, per input. TV snaps it off the CURSOR — hero clear,
        // first shelf 0.72, deeper opaque — because tracking the scroll
        // glide repaints every frame of every row move, which is exactly
        // what the TV veil policy exists to avoid (and what a MiBox-class
        // GPU renders as lag). Touch and desktop keep the continuous
        // scroll-driven ramp: free scrolling has no discrete states to snap
        // between, and those GPUs absorb the fill.
        RepaintBoundary(
          child: IgnorePointer(
            child: widget.dpad
                ? _veil(ground, _row < 0 ? 0.0 : (_row == 0 ? 0.72 : 1.0))
                : AnimatedBuilder(
                    animation: _scroll,
                    builder: (context, _) {
                      final off = _scroll.hasClients ? _scroll.offset : 0.0;
                      final t = (off / (heroH * 0.8)).clamp(0.0, 1.0);
                      return _veil(ground, t);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// One alpha-in-the-colour fill. Fully transparent paints nothing at all.
  static Widget _veil(Color ground, double t) => t <= 0
      ? const SizedBox.shrink()
      : ColoredBox(color: ground.withValues(alpha: t));

  Widget _heroForeground(_M m, StremioMeta item, double heroH) {
    final flip = _flip;
    // TV keeps the shipped absolutes: on a ~960×540 canvas, 128 is the
    // proportional shelf overlap (88) plus 40 of clearance, and 92 is the
    // overlap plus 4. On touch the SAME structure is derived instead of
    // fixed, because the overlap is a FRACTION of the hero and the hero is a
    // full tablet viewport — at heroH≈1024 the overlap alone is ~167, so the
    // absolute 128 parked the identity UNDER the first shelf's header (the
    // observed collision), with the dots on the posters below it.
    final overlap = heroH * _shelfOverlapFraction;
    final identityBottom = widget.dpad ? 128.0 : overlap + 40 * m.k;
    final dotsBottom = widget.dpad ? 92.0 : overlap + 4 * m.k;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: flip ? null : m.gutter,
          right: flip ? m.gutter : null,
          bottom: identityBottom,
          width: m.w * (820 / 1920),
          child: _identity(item, flip, m),
        ),
        if (widget.hero.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: dotsBottom,
            // Tappable wherever there is no remote — desktop and tablet run
            // this wide layout too. On TV the padding-free dots render
            // byte-identically to HEAD.
            child: _dots(tappable: !widget.dpad),
          ),
        // The hero's focusable surface. IgnorePointer-free and zero-sized in
        // paint terms: the hero shows focus through the page, not through a
        // ring on a full-screen box.
        // `skipTraversal`: the hero is reached ONLY by the explicit UP
        // handler. Left findable, a geometric LEFT/UP search from the first
        // shelves lands on it — which is why LEFT from row 1 and 2 went to the
        // hero instead of falling through to the sidebar. It sits at x=0, so
        // it is the nearest thing to the left of everything.
        Positioned(
          left: 0,
          top: 0,
          child: Focus(
            focusNode: widget.heroNode,
            skipTraversal: true,
            descendantsAreTraversable: false,
            child: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Widget _identity(StremioMeta item, bool flip, _M m) {
    final cross = flip ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final align = flip ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        _LogoOrTitle(url: item.logo, name: item.name, align: align, scale: m.k),
        const SizedBox(height: 9),
        Text(
          [
            item.type == 'series' ? 'Series' : 'Film',
            ...(item.genres ?? const []).take(2),
          ].join(' · '),
          textAlign: align,
          style: TextStyle(
            fontSize: 10.5 * m.k,
            color: Colors.white.withValues(alpha: 0.86),
          ),
        ),
        if ((item.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            item.description!,
            maxLines: 2,
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5 * m.k,
              height: 1.42,
              color: Colors.white.withValues(alpha: 0.74),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dots({bool tappable = false}) => Row(
        // Keyed so the single-page guard is pinnable: the board grew other
        // AnimatedContainers (the off-parallax focus ring), so "no
        // AnimatedContainer anywhere" stopped meaning "no dots".
        key: const ValueKey('spotlight-hero-dots'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.hero.length; i++)
            GestureDetector(
              // A 4px dot is not a tap target — the padding is.
              onTap: tappable ? () => _jumpTo(i) : null,
              behavior: tappable ? HitTestBehavior.opaque : null,
              child: Padding(
                padding: tappable
                    ? const EdgeInsets.symmetric(horizontal: 2, vertical: 8)
                    : EdgeInsets.zero,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 2.25),
                  width: i == _heroIndex ? 11 : 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white
                        .withValues(alpha: i == _heroIndex ? 0.95 : 0.34),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _shelf(int i, _M m) {
    final section = widget.sections[i];
    final nodes = section.nodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          // The gap under the title is `liftUp`, supplied by the row below —
          // reserved space that is empty at rest and consumed by the lift.
          padding: EdgeInsets.fromLTRB(m.gutter, 20, m.gutter, 0),
          child: Text(
            section.title,
            style: TextStyle(
              fontSize: m.title,
              fontWeight: FontWeight.w600,
              // The one label on this board that sits on the PAGE rather than
              // on artwork, so it is the one that has to follow the ink. The
              // hero's text, the dots and the card captions all sit over a
              // photograph and stay white whatever the ground is.
              color: AppThemeScope.of(context)
                  .core
                  .tx
                  .withValues(alpha: 0.84),
            ),
          ),
        ),
        Padding(
          // The room the lift needs sits OUTSIDE the viewport, as padding.
          //
          // It used to be added to the viewport's own height instead, and that
          // was the bug behind cards reading far too tall: a horizontal
          // ListView constrains its children to the viewport height TIGHTLY,
          // so every card was stretched to `posterH * 1.10 + 24` while its
          // width was still computed from `posterH`. A 2:3 poster drew at
          // 0.53:1. No amount of re-deriving the ratio could have fixed it.
          padding: EdgeInsets.only(top: m.liftUp, bottom: m.liftDown),
          child: SizedBox(
            // The viewport IS the card now, so the tight cross-axis constraint
            // hands each card exactly the height it asked for. On compact the
            // caption strip below the art is part of the card, and the
            // viewport grows by exactly that strip — the art box itself stays
            // posterH, so the ratio guard still holds.
            height: m.posterH + m.captionBlock,
            child: ListView.separated(
              // The lift paints into the padding above and below rather than
              // being sliced off at the viewport edge.
              clipBehavior: Clip.none,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: m.gutter),
              itemCount: section.items.length,
              separatorBuilder: (_, __) => SizedBox(width: m.gap),
              itemBuilder: (context, c) => _Card(
                card: section.items[c],
                node: c < nodes.length ? nodes[c] : null,
                // Every shape shares the ROW's height and takes the width its
                // aspect implies, so a shelf that mixes posters and channel
                // tiles sits on one baseline instead of stepping up and down.
                height: m.posterH,
                caption: m.caption,
                radius: m.radius,
                captionBelow: m.compact,
                captionBlock: m.captionBlock,
                hoverable: !widget.dpad,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Logo art when it exists and is light enough to see; the title otherwise.
class _LogoOrTitle extends StatelessWidget {
  final String? url;
  final String name;
  final TextAlign align;

  /// `_M.k` — 1.0 on TV and compact, the wide-touch correction elsewhere.
  final double scale;

  const _LogoOrTitle({
    required this.url,
    required this.name,
    required this.align,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      maxLines: 2,
      textAlign: align,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 39 * scale,
        height: 1,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: Colors.white,
      ),
    );
    if (url == null || url!.isEmpty) return text;
    final corner = align == TextAlign.right
        ? Alignment.bottomRight
        : align == TextAlign.center
            ? Alignment.bottomCenter
            : Alignment.bottomLeft;
    // A RESERVED slot, not a maximum.
    //
    // This was a `ConstrainedBox(maxWidth: 235, maxHeight: 60)`, which sizes
    // itself to whatever is inside it. Before the art lands there is nothing
    // inside it, so the slot collapsed and the identity below sat higher up;
    // when the logo arrived a second or two later the block reflowed and
    // everything settled into a different place. The column is anchored by its
    // BOTTOM, so the whole identity moved, not just the logo.
    //
    // Holding the box at full size from the first frame means the art fades
    // into a space already shaped for it and nothing else moves.
    return SizedBox(
      width: 235 * scale,
      height: 60 * scale,
      child: CachedNetworkImage(
        imageUrl: url!,
        fit: BoxFit.contain,
        alignment: corner,
        cacheManager: DebrifyImageCache.manager,
        memCacheWidth: 520,
        placeholder: (_, __) => const SizedBox.shrink(),
        // The title has to earn its way into the same slot rather than
        // resizing it — scaleDown only shrinks, so short titles keep their
        // intended weight.
        //
        // The inner width is what makes that bearable: FittedBox offers its
        // child unbounded width, so without it `maxLines: 2` never wraps and a
        // long title is scaled down as one very long line.
        errorWidget: (_, __, ___) => Align(
          alignment: corner,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: corner,
            child: SizedBox(width: 235 * scale, child: text),
          ),
        ),
      ),
    );
  }
}

/// The compact hero's one button — white pill, black glyph, the phone idiom.
class _HeroOpenPill extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroOpenPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(21),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, size: 20, color: Colors.black),
            SizedBox(width: 6),
            Text(
              'Open',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatefulWidget {
  final SpotlightCard card;
  final FocusNode? node;

  /// The ROW's height. Width follows from the shape's aspect, so a shelf that
  /// mixes posters and channel tiles keeps one baseline.
  final double height;
  final double caption;
  final double radius;

  /// Compact: the caption sits BELOW the art (small art can't afford an
  /// overlay eating its bottom quarter — the measured Apple phone idiom).
  /// Wide keeps the overlay-on-gradient the TV mock specifies.
  final bool captionBelow;
  final double captionBlock;

  /// Pointer hover lifts the card — desktop only. OFF on TV: an Apple TV
  /// trackpad delivers pointer events (see main.dart), and a hover lift
  /// independent of DPAD focus would put two cursors on a board that had
  /// exactly one at HEAD.
  final bool hoverable;

  const _Card({
    required this.card,
    required this.node,
    required this.height,
    required this.caption,
    this.radius = 7,
    this.captionBelow = false,
    this.captionBlock = 0,
    this.hoverable = false,
  });

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _f = false;

  /// Pointer hover — desktop's focus. Kept SEPARATE from [_f] and OR-ed at
  /// paint, so a pointer wandering off a card can never erase a real focus
  /// visual that a keyboard put there.
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final c = widget.card;
    final w = widget.height * c.shape.aspect;
    final url = c.image;
    final contained = c.shape.fit == BoxFit.contain;

    final art = ParallaxFocus(
      focused: _f || _h,
      radius: BorderRadius.circular(widget.radius),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: SizedBox(
          width: w,
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Both plates step AWAY from the page, toward the ink, so a
              // card still reads as a card whatever the Background is set to —
              // and a contained mark gets the bigger step, because a channel
              // logo needs more of a backing than an empty poster slot does.
              //
              // The contained one used to DARKEN instead, so light-on-
              // transparent logos had something to sit on. That is degenerate
              // on a black ground — `lerp(black, black)` is black — and an
              // entire row of channels went invisible while still being
              // painted. A step toward the ink works on any ground, and a light
              // mark still reads on it because the step is small.
              ColoredBox(
                color: Color.lerp(
                  app.home.bg,
                  app.core.tx,
                  contained ? 0.10 : 0.045,
                )!,
              ),
              if (url != null && url.isNotEmpty)
                Padding(
                  padding: EdgeInsets.all(contained ? w * 0.14 : 0),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: c.shape.fit,
                    cacheManager: DebrifyImageCache.manager,
                    memCacheWidth: 400,
                    // Android TV pops, no fade. The package defaults are a
                    // 500ms image fade over a 1000ms placeholder fade —
                    // fine for one image, but a board entry lands 20-30
                    // posters inside a few seconds, and that many
                    // concurrent per-frame opacity composites is exactly
                    // the first-seconds jank a MiBox reports. Fades never
                    // run again once the memory cache is warm, which is
                    // why the page "becomes smooth" — this makes the first
                    // seconds behave like every second after them.
                    fadeInDuration: PlatformUtil.isAndroidTvCached
                        ? Duration.zero
                        : const Duration(milliseconds: 500),
                    fadeOutDuration: PlatformUtil.isAndroidTvCached
                        ? Duration.zero
                        : const Duration(milliseconds: 1000),
                    placeholder: (_, __) => const SizedBox.shrink(),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              if ((c.progress ?? 0) > 0 && (c.progress ?? 0) < 100)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    value: c.progress! / 100,
                    minHeight: 2,
                    backgroundColor: Colors.black.withValues(alpha: 0.45),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              // The caption sits INSIDE over a gradient bed on wide — below
              // the card on compact, where the art is too small to spare its
              // bottom quarter.
              if (!widget.captionBelow)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xDB000000), Color(0x00000000)],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(7, 26, 7, 7),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.title,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: widget.caption,
                              color: Colors.white.withValues(alpha: 0.86),
                            ),
                          ),
                          if ((c.subtitle ?? '').isNotEmpty)
                            Text(
                              c.subtitle!,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: widget.caption * 0.85,
                                color: Colors.white.withValues(alpha: 0.58),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // The parallax lift is this card's only cursor, and it is a THEME
    // expression — under any other look ParallaxFocus returns the art
    // untouched, so a focused card would be indistinguishable from a resting
    // one (the Classic-look + Spotlight-layout combination shipped exactly
    // that). Off-parallax the theme paints the cursor it asked for instead —
    // CardFocusRise's delegation, from the other side. NOT unconditional
    // FocusExpressionBox: its parallax arm clips the glare at the theme's
    // scaled radius, and Spotlight's 0.7 shape scale would shrink the
    // shipped look's clip from 7 to 4.9.
    final cursored = app.focus.expression == FocusExpression.parallax
        ? art
        : FocusExpressionBox(
            focused: _f || _h,
            radius: widget.radius,
            child: art,
          );

    // Compact: art + a one-line caption below, one Column — the caption is
    // part of the card so the tap target covers both.
    final card = widget.captionBelow
        ? SizedBox(
            width: w,
            child: Column(
              children: [
                cursored,
                SizedBox(
                  height: widget.captionBlock,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      c.title,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: widget.caption,
                        color: app.core.tx.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : cursored;

    // The gesture layer is UNCONDITIONAL now. It used to hang off the focus
    // wrapper, so a card whose row had run out of focus nodes silently lost
    // its tap — invisible on TV (DPAD never reaches an un-noded card),
    // real on touch. The hover layer is NOT unconditional — see [hoverable].
    final tappable = GestureDetector(
      onTap: c.onOpen,
      onLongPress: c.onOptions,
      child: card,
    );
    final interactive = widget.hoverable
        ? MouseRegion(
            onEnter: (_) => setState(() => _h = true),
            onExit: (_) => setState(() => _h = false),
            child: tappable,
          )
        : tappable;

    if (widget.node == null) return interactive;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (v) {
        setState(() => _f = v);
        if (v && context.findRenderObject() is RenderBox) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            // Snap on TV — the detail rails' rule: a held key retargets an
            // in-flight glide every repeat, so the cursor perpetually
            // trails the press, and every glide frame is scroll paint a
            // MiBox-class GPU visibly drops. Pointer/touch keeps the glide.
            duration: PlatformUtil.isAndroidTvCached
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.gameButtonA) {
          c.onOpen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: interactive,
    );
  }
}
