import 'dart:async';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_ott_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_scroll_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentOttViewDeps = ({
  PlaylistContentSeriesState seriesState,
  PlaylistContentCatalogState catalogState,
  Future<void> Function() parseSeriesPlaylist,
  PlaylistContentOttState ottState,
  bool Function() mounted,
  PlaylistContentNavigationState navigationState,
  void Function(VoidCallback) setState,
  void Function(FolderViewMode mode) applyViewMode,
  BuildContext Function() context,
  Widget Function(SeriesSeason season) buildEpisodeList,
  PlaylistContentScrollState scrollState,
  Future<void> Function() showFixMetadataDialog,
});

class PlaylistContentOttView {
  PlaylistContentOttView(this._deps);
  final PlaylistContentOttViewDeps _deps;

  /// Build OTT-style view for Series Arrange mode
  Widget buildOTTView() {
    // Parse series playlist if not already done
    if (_deps.seriesState.seriesPlaylist == null &&
        _deps.catalogState.rootContent != null) {
      _deps.parseSeriesPlaylist();
    }

    if (_deps.seriesState.seriesPlaylist == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_deps.seriesState.seriesPlaylist!.isSeries) {
      // Auto-switch to Sort (A-Z) view after a brief delay
      // Cancel any pending timer to prevent duplicates
      _deps.ottState.ottViewAutoSwitchTimer?.cancel();
      _deps.ottState.ottViewAutoSwitchTimer = Timer(
        const Duration(seconds: 2),
        () {
          if (_deps.mounted() &&
              _deps.navigationState.currentViewMode ==
                  FolderViewMode.seriesArrange) {
            _deps.setState(() {
              _deps.navigationState.currentViewMode = FolderViewMode.sortedAZ;
              _deps.applyViewMode(FolderViewMode.sortedAZ);
            });
          }
        },
      );

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 48,
                color: AppThemeScope.of(_deps.context()).playlist.ink2,
              ),
              const SizedBox(height: 16),
              const Text(
                'No series detected in this content',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Switching to Sort (A-Z) view...',
                // Colors.white60 at its exact alpha, off the page ink.
                style: TextStyle(
                  color: AppThemeScope.of(
                    _deps.context(),
                  ).core.tx.withValues(alpha: 0x99 / 255),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final season = _deps.seriesState.seriesPlaylist!.getSeason(
      _deps.seriesState.selectedSeasonNumber,
    );
    if (season == null) {
      // Default to first available season
      if (_deps.seriesState.seriesPlaylist!.seasons.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _deps.setState(() {
            _deps.seriesState.selectedSeasonNumber =
                _deps.seriesState.seriesPlaylist!.seasons.first.seasonNumber;
          });
        });
      }
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Season selector
        buildSeasonSelector(),

        // Loading indicator for metadata
        if (_deps.seriesState.isLoadingSeriesMetadata)
          const LinearProgressIndicator(),

        // Episode list
        Expanded(child: _deps.buildEpisodeList(season)),
      ],
    );
  }

  /// Build season selector dropdown
  Widget buildSeasonSelector() {
    if (_deps.seriesState.seriesPlaylist == null) {
      return const SizedBox.shrink();
    }
    final app = AppThemeScope.of(_deps.context());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(
          _deps.context(),
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(
              _deps.context(),
            ).dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          DropdownButton<int>(
            value: _deps.seriesState.selectedSeasonNumber,
            dropdownColor: app.cloud.dialogSurface,
            underline: const SizedBox.shrink(),
            items: _deps.seriesState.seriesPlaylist!.seasons.map((season) {
              return DropdownMenuItem(
                value: season.seasonNumber,
                child: Text(
                  season.seasonNumber == 0
                      ? 'Specials'
                      : 'Season ${season.seasonNumber}',
                  style: const TextStyle(fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                // Cancel any pending scroll retry timer before season change
                _deps.scrollState.scrollRetryTimer?.cancel();

                _deps.setState(() {
                  _deps.seriesState.selectedSeasonNumber = value;
                  // Reset target episode index when season changes manually
                  // so it recalculates for the new season
                  _deps.scrollState.targetEpisodeIndex = null;
                  // Reset scroll scheduled flag to allow auto-scroll in new season
                  _deps.scrollState.isScrollScheduled = false;
                });
              }
            },
          ),
          const Spacer(),
          // Fix Metadata button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _deps.showFixMetadataDialog,
              borderRadius: app.shape.br(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: app.playlist.warning.withValues(alpha: 0.2),
                  borderRadius: app.shape.br(8),
                  border: Border.all(
                    color: app.playlist.warning.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.build, color: app.playlist.warning, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Fix Metadata',
                      style: TextStyle(
                        color: app.playlist.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
