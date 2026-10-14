import 'package:debrify/features/video_player/application/vp_identity_text.dart';
import 'package:debrify/features/video_player/models/vp_season_episode_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/video_player/widgets/spotlight_dialog.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/tv_search_focus_handoff.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';

abstract interface class VpIdentifyTitleUiHost {
  BuildContext get context;
  bool get mounted;
}

class VpIdentifyTitleUi {
  VpIdentifyTitleUi(this._host);
  final VpIdentifyTitleUiHost _host;

  Widget buildIdentifyTitleResultTile(
    StremioMeta meta, {
    FocusNode? focusNode,
  }) {
    final posterUrl = vpNormalisePosterUrl(meta.poster);

    return InkWell(
      focusNode: focusNode,
      onTap: () => Navigator.of(_host.context).pop(meta),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 46,
                height: 68,
                color: Colors.white.withValues(alpha: 0.08),
                child: posterUrl == null
                    ? Icon(
                        Icons.movie_creation_outlined,
                        color: Colors.white.withValues(alpha: 0.45),
                      )
                    : Image.network(
                        posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.movie_creation_outlined,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vpIdentityMetaSubtitle(meta),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<StremioMeta?> showIdentifyTitleSearchSheet({
    required String initialQuery,
  }) async {
    if (!_host.mounted) return null;

    final controller = TextEditingController(text: initialQuery);
    final searchFocusNode = FocusNode(debugLabel: 'identify-title-search');
    final firstResultFocusNode = FocusNode(
      debugLabel: 'identify-title-first-result',
    );
    final searchSubmitFocus = TvSearchFocusHandoff();
    var results = <StremioMeta>[];
    var isSearching = false;
    var hasSearched = false;
    String? errorMessage;
    var searchToken = 0;
    var sheetActive = true;

    Future<void> runSearch(String rawQuery, StateSetter setSheetState) async {
      final query = rawQuery.trim();
      final token = ++searchToken;

      if (query.isEmpty) {
        searchSubmitFocus.cancel();
        setSheetState(() {
          results = [];
          errorMessage = null;
          isSearching = false;
          hasSearched = false;
        });
        return;
      }

      setSheetState(() {
        isSearching = true;
        errorMessage = null;
        hasSearched = true;
      });

      try {
        final metas = await StremioService.instance.searchCatalogs(query);
        if (!sheetActive || !_host.mounted || token != searchToken) return;
        setSheetState(() {
          results = vpFilterIdentitySearchResults(metas);
          isSearching = false;
        });
        if (results.isEmpty) {
          searchSubmitFocus.cancel();
        } else {
          searchSubmitFocus.complete(
            field: searchFocusNode,
            isMounted: () => sheetActive && _host.mounted,
            requestFocus: firstResultFocusNode.requestFocus,
            targetHasFocus: () => firstResultFocusNode.hasFocus,
          );
        }
      } catch (e) {
        if (!sheetActive || !_host.mounted || token != searchToken) return;
        searchSubmitFocus.cancel();
        setSheetState(() {
          results = [];
          errorMessage = 'Search failed. Try again.';
          isSearching = false;
        });
      }
    }

    Future<void> submitSearch(
      String rawQuery,
      StateSetter setSheetState,
    ) async {
      searchSubmitFocus.arm(enabled: PlatformUtil.isTelevision);
      await runSearch(rawQuery, setSheetState);
    }

    // Right-side glass panel (the player menu's grammar) rather than the old
    // Material bottom sheet — the picture stays visible on the left.
    final selected =
        await showGeneralDialog<StremioMeta>(
          context: _host.context,
          barrierDismissible: true,
          barrierLabel: 'dismiss',
          barrierColor: Colors.black.withValues(alpha: 0.45),
          transitionDuration: const Duration(milliseconds: 280),
          transitionBuilder: (context, anim, _, child) {
            final curved = CurvedAnimation(
              parent: anim,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.12, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
          pageBuilder: (sheetContext, _, __) {
            var initialSearchStarted = false;
            return StatefulBuilder(
              builder: (sheetContext, setSheetState) {
                if (!initialSearchStarted && initialQuery.trim().isNotEmpty) {
                  initialSearchStarted = true;
                  Future(() => runSearch(initialQuery, setSheetState));
                }

                final screenSize = MediaQuery.of(sheetContext).size;
                final compact = screenSize.width < 720;
                final panelWidth = compact
                    ? screenSize.width
                    : (screenSize.width * 0.46).clamp(430.0, 560.0);

                final panel = Container(
                  width: panelWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: PlatformUtil.isAndroidTvCached
                        ? const Color(0xF5101012)
                        : const Color(0xFF101012).withValues(alpha: 0.86),
                    border: Border(
                      left: BorderSide(
                        color: Colors.white.withValues(alpha: 0.14),
                        width: 0.75,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    left: false,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 14, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'FIX THE TITLE',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.42),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.8,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded),
                                color: Colors.white70,
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                          child: TvTextField(
                            controller: controller,
                            focusNode: searchFocusNode,
                            autofocus: initialQuery.trim().isEmpty,
                            onChanged: (_) => searchSubmitFocus.cancel(),
                            onSubmitted: (value) =>
                                submitSearch(value, setSheetState),
                            style: const TextStyle(color: Colors.white),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Search movie or show',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.42),
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.arrow_forward_rounded),
                                color: Colors.white70,
                                onPressed: () =>
                                    runSearch(controller.text, setSheetState),
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.08),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Builder(
                            builder: (_) {
                              if (isSearching) {
                                return Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              if (errorMessage != null) {
                                return Center(
                                  child: Text(
                                    errorMessage!,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.65,
                                      ),
                                      fontSize: 14,
                                    ),
                                  ),
                                );
                              }

                              if (hasSearched && results.isEmpty) {
                                return Center(
                                  child: Text(
                                    'No IMDb-backed results found',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.65,
                                      ),
                                      fontSize: 14,
                                    ),
                                  ),
                                );
                              }

                              return ListView.separated(
                                padding: const EdgeInsets.only(bottom: 20),
                                itemCount: results.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: Colors.white.withValues(alpha: 0.06),
                                ),
                                itemBuilder: (_, index) =>
                                    buildIdentifyTitleResultTile(
                                      results[index],
                                      focusNode: index == 0
                                          ? firstResultFocusNode
                                          : null,
                                    ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                return Align(
                  alignment: Alignment.centerRight,
                  child: Material(color: Colors.transparent, child: panel),
                );
              },
            );
          },
        ).whenComplete(() {
          sheetActive = false;
        });

    searchSubmitFocus.cancel();
    searchFocusNode.dispose();
    firstResultFocusNode.dispose();
    controller.dispose();
    return selected;
  }

  Future<VpSeasonEpisodeSelection?> requestSeasonEpisodeForIdentity(
    String title,
  ) async {
    if (!_host.mounted) return null;

    final seasonController = TextEditingController();
    final episodeController = TextEditingController();
    String? errorText;

    final result = await showSpotlightDialog<VpSeasonEpisodeSelection>(
      _host.context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return SpotlightDialogCard(
              title: 'Which episode?',
              bodyText: title,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TvTextField(
                          controller: seasonController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Season',
                            labelStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TvTextField(
                          controller: episodeController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Episode',
                            labelStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      errorText!,
                      style: const TextStyle(
                        color: SpotlightDialogCard.statusRed,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                SpotlightDialogAction(
                  'Cancel',
                  () => Navigator.of(dialogContext).pop(),
                ),
                // solid: the recommended action, and on TV the autofocus
                // anchor — without it the dialog opens with nothing focused
                // and the first OK press dies.
                SpotlightDialogAction('Apply', solid: true, () {
                  final season = int.tryParse(seasonController.text.trim());
                  final episode = int.tryParse(episodeController.text.trim());
                  if (season == null ||
                      season <= 0 ||
                      episode == null ||
                      episode <= 0) {
                    setDialogState(() {
                      errorText = 'Enter a valid season and episode.';
                    });
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                    VpSeasonEpisodeSelection(season: season, episode: episode),
                  );
                }),
              ],
            );
          },
        );
      },
    );

    seasonController.dispose();
    episodeController.dispose();
    return result;
  }
}
