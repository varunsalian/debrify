import 'package:debrify/features/episodes_panel/presentation/episodes_panel_source_button.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_auth.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_deps.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_navigation.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_resources.dart';
import 'package:debrify/features/episodes_panel/presentation/legacy_episodes_panel/episodes_panel_view_state.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/season_action_region.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EpisodesPanelClassicChrome {
  final EpisodesPanelDeps _deps;
  EpisodesPanelClassicChrome(this._deps);
  EpisodesPanelViewState get _s => _deps.parts.viewState;
  EpisodesPanelAuth get _a => _deps.parts.auth;
  EpisodesPanelResources get _r => _deps.parts.resources;
  EpisodesPanelNavigation get _n => _deps.parts.navigation;
  bool get mounted => _deps.mounted();

  Widget buildEpisodeFiltersBar() {
    final t = DetailThemeScope.maybeOf(_deps.context());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            // Back button — Focus-wrapped with blue accent border like Trakt
            Focus(
              focusNode: _r.episodeBackButtonFocusNode,
              onFocusChange: (focused) => _deps.setState(() {}),
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  // Top of a standalone route — nothing above to focus
                  // (the host is covered). Swallow so focus stays put.
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  if (_s.episodesUnavailable) {
                    _r.episodeRetryFocusNode.requestFocus();
                  } else {
                    _r.episodeSeasonDropdownFocusNode.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (_s.episodesUnavailable) {
                    _r.episodeRetryFocusNode.requestFocus();
                  } else if (_r.episodeFocusNodes.isNotEmpty) {
                    _r.episodeFocusNodes.first.requestFocus();
                  }
                  return KeyEventResult.handled;
                }
                if (isActivateKey(event.logicalKey) ||
                    event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.goBack) {
                  _deps.onBack()?.call();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _r.episodeBackButtonFocusNode.hasFocus
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.06),
                  border: Border.all(
                    color: _r.episodeBackButtonFocusNode.hasFocus
                        ? t.focus
                        : Colors.white.withValues(alpha: 0.14),
                    width: _r.episodeBackButtonFocusNode.hasFocus ? 2 : 1,
                  ),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => _deps.onBack()?.call(),
                  tooltip: 'Back to shows',
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Show title
            Expanded(
              child: Text(
                _s.selectedShow?.name ?? '',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Season dropdown — Trakt-style with blue accent border
            if (_s.episodeSeasons.isNotEmpty) ...[
              const SizedBox(width: 8),
              buildEpisodeSeasonDropdown(),
            ],

            // Select Source button
            if (_s.selectedShow != null && _deps.onSelectSource() != null) ...[
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final sourceCount =
                      _deps.boundSourceCount()?.call(_s.selectedShow!) ?? 0;
                  return EpisodesPanelSourceButton(
                    hasBoundSource: sourceCount > 0,
                    sourceCount: sourceCount,
                    // Await the picker so the bound-source count updates in
                    // place when it closes (no need to leave and re-enter).
                    onTap: () async {
                      await _deps.onSelectSource()!(_s.selectedShow!);
                      if (mounted) _deps.setState(() {});
                    },
                    onLeftFocus: _s.episodeSeasons.isNotEmpty
                        ? _r.episodeSeasonDropdownFocusNode
                        : _r.episodeBackButtonFocusNode,
                    onDownArrow: _r.episodeFocusNodes.isNotEmpty
                        ? () => _r.episodeFocusNodes.first.requestFocus()
                        : null,
                    // Top row of a standalone route — swallow Up (a non-null
                    // no-op makes the button report the key handled).
                    onUpArrow: () {},
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  KeyEventResult handleEpisodeSeasonDropdownKeyEvent(
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      // Top row of a standalone route — swallow (nothing above).
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_r.episodeFocusNodes.isNotEmpty) {
        _r.episodeFocusNodes.first.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _r.episodeBackButtonFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_deps.onSelectSource() != null) {
        node.nextFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget buildEpisodeSeasonDropdown() {
    // Resolved OUTSIDE the ListenableBuilder: the callback re-runs on every
    // focus change, and an inherited-widget lookup there would re-subscribe
    // per DPAD move on the weak TV GPU.
    final t = DetailThemeScope.maybeOf(_deps.context());
    return SeasonActionRegion(
      onOptions: _a.isDirectSource
          ? null
          : () => _deps.parts.seasonOptions.showSeasonOptions(
              _s.selectedSeasonNumber,
            ),
      onTap: () async {
        final number = await showModalBottomSheet<int>(
          context: _deps.context(),
          builder: (ctx) => TvHeldKeyGuard(
            child: SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final season in _s.episodeSeasons)
                    ListTile(
                      title: Text('Season ${season.number}'),
                      onTap: () => Navigator.pop(ctx, season.number),
                    ),
                ],
              ),
            ),
          ),
        );
        if (mounted && number != null) _n.onSeasonChanged(number);
      },
      child: ListenableBuilder(
        listenable: _r.episodeSeasonDropdownFocusNode,
        builder: (context, _) {
          final hasFocus = _r.episodeSeasonDropdownFocusNode.hasFocus;
          return AnimatedContainer(
            // TV: snap the focus ring and skip the blurred glow — the animated
            // blur shadow re-rasters every frame of the fade on the weak GPU.
            duration: _deps.isTelevision()
                ? Duration.zero
                : const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: hasFocus ? 0.12 : 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasFocus
                    ? t.focus
                    : Colors.white.withValues(alpha: 0.10),
                width: hasFocus ? 2.0 : 1.0,
              ),
              boxShadow: (hasFocus && !_deps.isTelevision())
                  ? [
                      BoxShadow(
                        color: t.fade(t.focus, 0.32),
                        blurRadius: 14,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                focusNode: _r.episodeSeasonDropdownFocusNode,
                focusColor: Colors.transparent,
                value: _s.selectedSeasonNumber,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                dropdownColor: const Color(0xFF14141C),
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: hasFocus
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.7),
                ),
                items: _s.episodeSeasons.map((s) {
                  return DropdownMenuItem(
                    value: s.number,
                    child: Text(
                      s.displayLabel,
                      // Explicit color: dropdown menu items render outside the
                      // page's DefaultTextStyle. onSurface follows the
                      // Appearance → Text Brightness preset.
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: _n.onSeasonChanged,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Chromeless header: just a left-aligned season selector (when there is more
  /// than one season). Used by the merged series page, which owns the back
  /// button, title and source binding in its own hero.
  Widget buildSlimSeasonRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: buildEpisodeSeasonDropdown(),
      ),
    );
  }
}
