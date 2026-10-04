import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_dependencies.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_episodes_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_focus_state.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_hero_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_model_factory.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_pane_layout.dart';
import 'package:debrify/features/merged_detail/presentation/legacy_merged_detail/merged_detail_root_layout.dart';
import 'package:debrify/features/merged_detail/presentation/merged_detail_palette.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/detail/detail_episode_cells.dart';
import 'package:debrify/widgets/detail/detail_layout_console.dart';
import 'package:debrify/widgets/detail/detail_layout_dossier.dart';
import 'package:debrify/widgets/detail/detail_layout_marquee.dart';
import 'package:debrify/widgets/detail/detail_layout_premium.dart';
import 'package:debrify/widgets/detail/detail_layout_showcase.dart';
import 'package:debrify/widgets/detail/detail_layout_stage.dart';
import 'package:debrify/widgets/detail/detail_model.dart';
import 'package:debrify/widgets/detail/detail_style.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/episodes_panel.dart';
import 'package:flutter/material.dart';

class MergedDetailBodyLayout {
  final MergedDetailDependencies _deps;
  MergedDetailBodyLayout(this._deps);
  String get _style => _deps.style();
  MergedDetailEpisodesLayout get _ep => _deps.parts.episodesLayout;
  MergedDetailFocusState get _f => _deps.parts.focusState;
  MergedDetailHeroLayout get _he => _deps.parts.heroLayout;
  MergedDetailModelFactory get _b => _deps.parts.modelFactory;
  MergedDetailPaneLayout get _pa => _deps.parts.paneLayout;
  MergedDetailRootLayout get _ro => _deps.parts.rootLayout;

  /// Hands an alternate layout the hosted engine. Null for movies, which have
  /// no episode list at all.
  Widget Function(Widget Function(BuildContext, EpisodesPanelView))?
  get episodesHost => _ro.isMovie
      ? null
      : (builder) => _ep.buildEpisodesPanel(contentBuilder: builder);

  /// What the active body wants painted behind it.
  DetailBodySpec get bodySpec => switch (_style) {
    // Marquee and Stage are showcase layouts — the artwork is the point, and
    // each already paints the gradient its own identity block sits on.
    'marquee' ||
    'stage' ||
    'vista' ||
    'halo' => const DetailBodySpec(ownScrim: true),
    // Showcase paints a SPECIFIC angled scrim (100° from the left) and its own
    // ambient field. `ownScrim` alone only swaps the shell's diagonal for a
    // lighter one; compounded with Showcase's own gradient neither reaches the
    // spec. `shellTint: false` is the only mode that leaves the artwork alone.
    'showcase' => const DetailBodySpec(ownScrim: true, shellTint: false),
    // A light theme cannot sit on the artwork at all: its own ground has to
    // cover it, or black-on-paper text lands on a photograph.
    _ => DetailBodySpec(inkGround: themedBody && _ro.theme.lightGround),
  };

  /// Whether the active layout is one the theme applies to.
  bool get themedBody => _style != 'classic';

  /// The one thing that switches on the chosen layout. Everything around it —
  /// PopScope, the trailer backdrop and its promote/dismiss, the tint, the back
  /// button, the trailer chip — is shell, written once.
  Widget buildBody(String? backdropUrl) {
    // Every alternate body is wrapped; Classic never is, so it cannot be
    // affected by a theme even accidentally.
    // Grid and grain are whole-page textures, so they are applied once here
    // rather than by each layout — and Classic, which is never wrapped, cannot
    // pick them up by accident.
    // DetailHoldHint is the page-level affordance for the episode cells' held
    // OK — one pill in the screen's corner rather than chrome on every card.
    // It sits here, around every alternate layout at once, so no layout has to
    // opt in; it renders nothing off TV and nothing until a cell takes focus.
    Widget themed(Widget body) => DetailThemeScope(
      theme: _ro.theme,
      child: DetailAtmosphere(child: DetailHoldHint(child: body)),
    );

    switch (_style) {
      case 'marquee':
        return themed(
          DetailMarquee(
            model: _b.buildDetailModel(),
            episodesHost: episodesHost,
          ),
        );
      case 'dossier':
        return themed(
          DetailDossier(
            model: _b.buildDetailModel(),
            episodesHost: episodesHost,
          ),
        );
      case 'stage':
        return themed(
          DetailStage(model: _b.buildDetailModel(), episodesHost: episodesHost),
        );
      case 'console':
        return themed(
          DetailConsole(
            model: _b.buildDetailModel(),
            episodesHost: episodesHost,
          ),
        );
      case 'vista':
        return themed(
          DetailPremium(
            kind: PremiumDetailKind.vista,
            model: _b.buildDetailModel(),
            episodesHost: episodesHost,
          ),
        );
      case 'monolith':
        return themed(
          DetailPremium(
            kind: PremiumDetailKind.monolith,
            model: _b.buildDetailModel(),
            episodesHost: episodesHost,
          ),
        );
      case 'mosaic':
        return themed(
          DetailPremium(
            kind: PremiumDetailKind.mosaic,
            model: _b.buildDetailModel(),
            episodesHost: episodesHost,
          ),
        );
      case 'halo':
        return themed(
          DetailPremium(
            kind: PremiumDetailKind.halo,
            model: _b.buildDetailModel(),
            episodesHost: episodesHost,
          ),
        );
      case 'premiere':
        return themed(
          DetailPremium(
            kind: PremiumDetailKind.premiere,
            model: _b.buildDetailModel(),
            episodesHost: episodesHost,
          ),
        );
      case 'showcase':
        return themed(
          DetailShowcase(
            model: _b.buildDetailModel(),
            episodesHost: episodesHost,
            // The INPUT axis: unlocks the touch drivers (scroll dissolve,
            // kebab, compact presentation under 600 wide) off-TV. Width is
            // deliberately not the test — a narrow TV must stay a TV.
            dpad: PlatformUtil.isTelevision,
          ),
        );
      // Only 'classic' reaches here: every shipped alternate has a case above,
      // and anything not yet drawable was already narrowed to the DEFAULT by
      // effectiveDetailPageStyle — which is no longer Classic, so this arm is
      // now the explicit choice rather than the fallback.
      default:
        return buildClassicBody(backdropUrl);
    }
  }

  /// Today's screen, unchanged: movie column, two-pane, or stacked.
  Widget buildClassicBody(String? backdropUrl) {
    if (_ro.isMovie) {
      // A movie has no episode list — one centered, scrollable detail column.
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _pa.buildInfoPane(),
        ),
      );
    }
    if (_ro.wide) return buildTwoPane(backdropUrl);
    return Column(
      children: [
        _he.buildHero(),
        Expanded(child: buildStackedBody()),
      ],
    );
  }

  /// TV + desktop: left info column (scrollable) + right episode column (full
  /// height). Each pane is its own [FocusScope] so vertical traversal is
  /// contained within it; panes are crossed only horizontally — LEFT from an
  /// episode to the info column's primary action, RIGHT from the info column
  /// back to the pane's remembered episode row.
  Widget buildTwoPane(String? backdropUrl) {
    final w = MediaQuery.of(_deps.context()).size.width;
    final leftW = (w * 0.42).clamp(320.0, 480.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left info column, darkened so text stays legible over any backdrop.
        SizedBox(
          width: leftW,
          child: FocusScope(
            node: _f.infoPaneScope,
            onKeyEvent: _pa.handleInfoPaneKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    MergedDetailPalette.bg.withValues(alpha: 0.82),
                    MergedDetailPalette.bg.withValues(alpha: 0.5),
                  ],
                ),
              ),
              child: _pa.buildInfoPane(),
            ),
          ),
        ),
        Expanded(
          child: FocusScope(
            node: _f.episodesPaneScope,
            onKeyEvent: _pa.handleEpisodesPaneKey,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0E0B14).withValues(alpha: 0.82),
                border: Border(
                  left: BorderSide(color: MergedDetailPalette.hair),
                ),
              ),
              child: _ep.buildEpisodesPanel(),
            ),
          ),
        ),
      ],
    );
  }

  /// Stacked layout — mobile only. Compact hero (with Play/Bind/More) → a
  /// "Details" opener for cast/ratings/parents/recs → episodes. Quick actions
  /// live behind the hero's More (⋮) button.
  Widget buildStackedBody() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 16, 4),
            child: TextButton.icon(
              onPressed: _ep.openDetailsSheet,
              icon: Icon(Icons.info_outline_rounded, size: 18),
              label: const Text('Cast, ratings & more'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
          ),
        ),
        Expanded(child: _ep.buildEpisodesPanel()),
      ],
    );
  }
}
