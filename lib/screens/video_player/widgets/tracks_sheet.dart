import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import '../../../models/stremio_subtitle.dart';
import '../../../services/stremio_subtitle_service.dart';
import '../../../services/subtitle_font_service.dart';
import '../constants/color_constants.dart';
import '../utils/language_mapping.dart';
import '../services/subtitle_settings_service.dart';

class TracksSheetSubtitleSearchResult {
  final List<StremioSubtitle> subtitles;
  final List<AddonSubtitleSlot>? slots;
  final String? selectedSubtitleId;
  final String? identityLabel;
  // The manually-fixed identity these results were fetched for. The sheet
  // adopts it so a later per-addon Retry re-fetches the SAME content, not
  // the identity the sheet was opened with.
  final String? imdbId;
  final String? contentType;
  final int? season;
  final int? episode;

  const TracksSheetSubtitleSearchResult({
    required this.subtitles,
    this.slots,
    this.selectedSubtitleId,
    this.identityLabel,
    this.imdbId,
    this.contentType,
    this.season,
    this.episode,
  });
}

/// Modal bottom sheet for selecting audio and subtitle tracks
///
/// Netflix-style UI for switching between available audio tracks and
/// subtitle options. Addon subtitles are grouped per addon (mirroring the
/// Android TV player): each addon gets its own group with a live status
/// badge — count, spinner while loading, warning on failure — and a
/// failed addon can be retried individually.
class TracksSheet {
  /// Shows the tracks selection bottom sheet
  static Future<void> show(
    BuildContext context,
    mk.Player player, {
    required Future<void> Function(String audioId, String subtitleId)
    onTrackChanged,
    void Function(SubtitleSettingsData settings)? onSubtitleStyleChanged,
    VoidCallback? onSyncOverlayRequested,
    String? contentImdbId,
    String? contentType,
    int? contentSeason,
    int? contentEpisode,
    List<AddonSubtitleSlot>? cachedAddonSlots,
    void Function(List<AddonSubtitleSlot> slots)? onAddonSlotsFetched,
    String? selectedStremioSubtitleId,
    void Function(String? id)? onStremioSubtitleSelected,
    Future<String?> Function(StremioSubtitle subtitle)?
    onDownloadStremioSubtitleToFile,
    Future<TracksSheetSubtitleSearchResult?> Function()? onIdentifyTitle,
    String? subtitleIdentityLabel,
    // Fired only when the user applies an ACTUAL subtitle change (not an audio
    // change, not a re-selection of the current subtitle, not a failed load).
    // Used to reset the per-subtitle sync offset.
    VoidCallback? onSubtitleTrackChanged,
  }) async {
    final tracks = player.state.tracks;
    final audios = tracks.audio
        .where((a) => a.id.toLowerCase() != 'no')
        .toList(growable: false);
    final embeddedSubs = tracks.subtitle
        .where(
          (s) => s.id.toLowerCase() != 'auto' && s.id.toLowerCase() != 'no',
        )
        .toList(growable: false);
    String selectedAudio = player.state.track.audio.id;
    String selectedSub = selectedStremioSubtitleId != null
        ? 'stremio:$selectedStremioSubtitleId'
        : player.state.track.subtitle.id;

    SubtitleSettingsData subtitleStyle = await SubtitleSettingsService.instance
        .loadAll();
    if (!context.mounted) return;

    // Cached slots may contain LOADING entries if the sheet was closed
    // mid-fetch last time (the reopened sheet can't receive that old fetch's
    // updates) — surface them as retriable failures instead of stuck spinners.
    List<AddonSubtitleSlot>? addonSlots = cachedAddonSlots == null
        ? null
        : [
            for (final s in cachedAddonSlots)
              s.status == AddonSubtitleStatus.loading
                  ? s.copyWith(
                      status: AddonSubtitleStatus.failed,
                      error: 'Fetch was interrupted',
                    )
                  : s,
          ];
    bool slotsFetchStarted = addonSlots != null;
    String? activeSubtitleIdentityLabel = subtitleIdentityLabel;
    // Identity the slot fetches run against; replaced by a "Fix show" search.
    String? activeImdbId = contentImdbId;
    String? activeContentType = contentType;
    int? activeSeason = contentSeason;
    int? activeEpisode = contentEpisode;
    bool isIdentifyingTitle = false;
    int subtitleFetchGeneration = 0;
    int selectedTabIndex = 0;
    // Addons the user retried: a late snapshot from the initial full fetch
    // must not clobber their (newer) retry outcome.
    final retriedAddonIds = <String>{};

    // Cache slots with the owner — but only fully-settled snapshots. Caching
    // an in-flight list would (a) let an empty flat projection suppress the
    // screen's subtitle auto-select and (b) strand LOADING entries in the
    // cache if the sheet closes mid-fetch.
    void cacheSlots(List<AddonSubtitleSlot> slots) {
      if (slots.any((s) => s.status == AddonSubtitleStatus.loading)) return;
      onAddonSlotsFetched?.call(slots);
    }

    // Land on the group owning the active addon subtitle, if known.
    String selectedProviderId = 'emb';
    if (selectedStremioSubtitleId != null && addonSlots != null) {
      for (final slot in addonSlots) {
        if (slot.subtitles.any((s) => s.id == selectedStremioSubtitleId)) {
          selectedProviderId = slot.addonId;
          break;
        }
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Kick off the per-addon fetch on first build (cache miss).
            final fetchImdbId = activeImdbId;
            final fetchType = activeContentType;
            if (!slotsFetchStarted && fetchImdbId != null && fetchType != null) {
              slotsFetchStarted = true;
              final generation = ++subtitleFetchGeneration;
              StremioSubtitleService.instance
                  .fetchSubtitleSlots(
                type: fetchType,
                imdbId: fetchImdbId,
                season: activeSeason,
                episode: activeEpisode,
                onUpdate: (slots) {
                  if (generation != subtitleFetchGeneration) return;
                  // The service snapshot doesn't know about retries — keep
                  // the locally newer outcome for any retried addon.
                  var next = slots;
                  final local = addonSlots;
                  if (local != null && retriedAddonIds.isNotEmpty) {
                    next = [
                      for (final s in slots)
                        if (retriedAddonIds.contains(s.addonId))
                          local.firstWhere(
                            (l) => l.addonId == s.addonId,
                            orElse: () => s,
                          )
                        else
                          s,
                    ];
                  }
                  // Cache runs even if the sheet was closed mid-fetch.
                  cacheSlots(next);
                  if (!context.mounted) return;
                  setModalState(() => addonSlots = next);
                },
              )
                  .catchError((Object e) {
                // Addon-level errors are caught per-slot inside the service;
                // this only fires when listing the addons itself blew up.
                debugPrint('TracksSheet: Slot fetch failed: $e');
                if (generation == subtitleFetchGeneration &&
                    context.mounted) {
                  setModalState(() => addonSlots ??= const []);
                }
                return const <AddonSubtitleSlot>[];
              });
            }

            void retryAddon(String addonId) {
              final slots = addonSlots;
              final imdbId = activeImdbId;
              final type = activeContentType;
              if (slots == null || imdbId == null || type == null) {
                return;
              }
              final idx = slots.indexWhere((s) => s.addonId == addonId);
              if (idx < 0 || slots[idx].status == AddonSubtitleStatus.loading) {
                return;
              }
              final generation = subtitleFetchGeneration;
              retriedAddonIds.add(addonId);
              setModalState(() {
                addonSlots = List.of(slots)
                  ..[idx] = slots[idx]
                      .copyWith(status: AddonSubtitleStatus.loading);
              });
              StremioSubtitleService.instance
                  .fetchSingleAddonSlot(
                addonId: addonId,
                type: type,
                imdbId: imdbId,
                season: activeSeason,
                episode: activeEpisode,
              )
                  .then((settled) {
                if (generation != subtitleFetchGeneration) return;
                final cur = addonSlots;
                if (cur == null) return;
                final i = cur.indexWhere((s) => s.addonId == addonId);
                if (i < 0) return;
                final updated = List.of(cur)..[i] = settled;
                cacheSlots(updated);
                if (!context.mounted) return;
                setModalState(() => addonSlots = updated);
              });
            }

            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;
            final isWide = screenWidth > 600;
            final isLandscape = screenWidth > screenHeight;

            // Use more height on mobile landscape to show more options
            final sheetHeight = isLandscape
                ? screenHeight *
                      0.85 // 85% in landscape
                : screenHeight * 0.7; // 70% in portrait

            return Container(
              height: sheetHeight,
              decoration: const BoxDecoration(
                color: Color(0xFF141414),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.tune_rounded,
                          color: VideoPlayerColors.netflixRed,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Audio & Subtitles',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white70,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Tab bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _buildTab(
                            icon: Icons.audiotrack_rounded,
                            label: 'Audio',
                            badge: audios.isNotEmpty
                                ? '${audios.length}'
                                : null,
                            isSelected: selectedTabIndex == 0,
                            onTap: () =>
                                setModalState(() => selectedTabIndex = 0),
                          ),
                          _buildTab(
                            icon: Icons.subtitles_rounded,
                            label: 'Subtitles',
                            badge: _subtitleBadge(embeddedSubs, addonSlots,
                                slotsFetchStarted),
                            isSelected: selectedTabIndex == 1,
                            onTap: () =>
                                setModalState(() => selectedTabIndex = 1),
                          ),
                          _buildTab(
                            icon: Icons.text_format_rounded,
                            label: 'Style',
                            isSelected: selectedTabIndex == 2,
                            onTap: () =>
                                setModalState(() => selectedTabIndex = 2),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Content area
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _buildTabContent(
                        key: ValueKey(selectedTabIndex),
                        tabIndex: selectedTabIndex,
                        audios: audios,
                        selectedAudio: selectedAudio,
                        player: player,
                        selectedSub: selectedSub,
                        onTrackChanged: onTrackChanged,
                        setModalState: setModalState,
                        onAudioChanged: (v) =>
                            setModalState(() => selectedAudio = v),
                        embeddedSubs: embeddedSubs,
                        addonSlots: addonSlots,
                        slotsPending: slotsFetchStarted && addonSlots == null,
                        selectedProviderId: selectedProviderId,
                        onProviderSelected: (id) =>
                            setModalState(() => selectedProviderId = id),
                        onRetryAddon: retryAddon,
                        onSubChanged: (v) {
                          setModalState(() => selectedSub = v);
                          if (!v.startsWith('stremio:')) {
                            onStremioSubtitleSelected?.call(null);
                          }
                        },
                        onStremioSubtitleSelected: onStremioSubtitleSelected,
                        onDownloadStremioSubtitleToFile:
                            onDownloadStremioSubtitleToFile,
                        onSubtitleTrackChanged: onSubtitleTrackChanged,
                        isIdentifyingTitle: isIdentifyingTitle,
                        subtitleIdentityLabel: activeSubtitleIdentityLabel,
                        onIdentifyTitle: onIdentifyTitle == null
                            ? null
                            : () async {
                                if (isIdentifyingTitle) return;
                                final generation = ++subtitleFetchGeneration;
                                setModalState(() {
                                  isIdentifyingTitle = true;
                                });
                                try {
                                  final result = await onIdentifyTitle();
                                  if (!context.mounted ||
                                      generation != subtitleFetchGeneration) {
                                    return;
                                  }
                                  setModalState(() {
                                    if (result != null) {
                                      if (result.slots != null) {
                                        addonSlots = result.slots;
                                        // The fix delivered fresh slots — a
                                        // sheet opened without an identity
                                        // must NOT kick off its own fetch
                                        // over them on the next rebuild.
                                        slotsFetchStarted = true;
                                        retriedAddonIds.clear();
                                      }
                                      if (result.imdbId != null) {
                                        activeImdbId = result.imdbId;
                                        activeContentType =
                                            result.contentType;
                                        activeSeason = result.season;
                                        activeEpisode = result.episode;
                                      }
                                      activeSubtitleIdentityLabel =
                                          result.identityLabel ??
                                          activeSubtitleIdentityLabel;
                                      final selectedId =
                                          result.selectedSubtitleId;
                                      if (selectedId != null) {
                                        selectedSub = 'stremio:$selectedId';
                                        final slots = result.slots;
                                        if (slots != null) {
                                          for (final slot in slots) {
                                            if (slot.subtitles.any(
                                                (s) => s.id == selectedId)) {
                                              selectedProviderId =
                                                  slot.addonId;
                                              break;
                                            }
                                          }
                                        }
                                      }
                                    }
                                    isIdentifyingTitle = false;
                                  });
                                } catch (e) {
                                  debugPrint(
                                    'TracksSheet: Search subtitle error: $e',
                                  );
                                  if (context.mounted &&
                                      generation == subtitleFetchGeneration) {
                                    setModalState(() {
                                      isIdentifyingTitle = false;
                                    });
                                  }
                                }
                              },
                        subtitleStyle: subtitleStyle,
                        onStyleChanged: (newStyle) {
                          setModalState(() => subtitleStyle = newStyle);
                          onSubtitleStyleChanged?.call(newStyle);
                        },
                        isWide: isWide,
                        onSyncOverlayRequested: onSyncOverlayRequested == null
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                onSyncOverlayRequested();
                              },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static String? _subtitleBadge(
    List<mk.SubtitleTrack> embedded,
    List<AddonSubtitleSlot>? slots,
    bool fetchStarted,
  ) {
    if (slots == null) {
      return fetchStarted ? '…' : (embedded.isNotEmpty ? '${embedded.length}' : null);
    }
    if (slots.any((s) => s.status == AddonSubtitleStatus.loading)) return '…';
    final count = embedded.length + AddonSubtitleSlot.flatten(slots).length;
    return count > 0 ? '$count' : null;
  }

  static Widget _buildTab({
    required IconData icon,
    required String label,
    String? badge,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? VideoPlayerColors.netflixRed
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : Colors.white60,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildTabContent({
    required Key key,
    required int tabIndex,
    required List<mk.AudioTrack> audios,
    required String selectedAudio,
    required mk.Player player,
    required String selectedSub,
    required Future<void> Function(String, String) onTrackChanged,
    required StateSetter setModalState,
    required void Function(String) onAudioChanged,
    required List<mk.SubtitleTrack> embeddedSubs,
    required List<AddonSubtitleSlot>? addonSlots,
    required bool slotsPending,
    required String selectedProviderId,
    required void Function(String) onProviderSelected,
    required void Function(String) onRetryAddon,
    required void Function(String) onSubChanged,
    required void Function(String? id)? onStremioSubtitleSelected,
    required Future<String?> Function(StremioSubtitle subtitle)?
    onDownloadStremioSubtitleToFile,
    VoidCallback? onSubtitleTrackChanged,
    required bool isIdentifyingTitle,
    required String? subtitleIdentityLabel,
    required Future<void> Function()? onIdentifyTitle,
    required SubtitleSettingsData subtitleStyle,
    required void Function(SubtitleSettingsData) onStyleChanged,
    required bool isWide,
    VoidCallback? onSyncOverlayRequested,
  }) {
    switch (tabIndex) {
      case 0:
        return _AudioTab(
          key: key,
          audios: audios,
          selectedAudio: selectedAudio,
          player: player,
          selectedSub: selectedSub,
          onTrackChanged: onTrackChanged,
          onAudioChanged: onAudioChanged,
        );
      case 1:
        return _SubtitlesTab(
          key: key,
          embeddedSubs: embeddedSubs,
          addonSlots: addonSlots,
          slotsPending: slotsPending,
          selectedProviderId: selectedProviderId,
          onProviderSelected: onProviderSelected,
          onRetryAddon: onRetryAddon,
          selectedSub: selectedSub,
          selectedAudio: selectedAudio,
          player: player,
          onTrackChanged: onTrackChanged,
          onSubChanged: onSubChanged,
          onStremioSubtitleSelected: onStremioSubtitleSelected,
          onDownloadStremioSubtitleToFile: onDownloadStremioSubtitleToFile,
          onSubtitleTrackChanged: onSubtitleTrackChanged,
          isIdentifyingTitle: isIdentifyingTitle,
          subtitleIdentityLabel: subtitleIdentityLabel,
          onIdentifyTitle: onIdentifyTitle,
          isWide: isWide,
        );
      case 2:
        return _StyleTab(
          key: key,
          subtitleStyle: subtitleStyle,
          onStyleChanged: onStyleChanged,
          isWide: isWide,
          onSyncOverlayRequested: onSyncOverlayRequested,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ============================================================================
// Audio Tab
// ============================================================================

class _AudioTab extends StatelessWidget {
  final List<mk.AudioTrack> audios;
  final String selectedAudio;
  final mk.Player player;
  final String selectedSub;
  final Future<void> Function(String, String) onTrackChanged;
  final void Function(String) onAudioChanged;

  const _AudioTab({
    super.key,
    required this.audios,
    required this.selectedAudio,
    required this.player,
    required this.selectedSub,
    required this.onTrackChanged,
    required this.onAudioChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (audios.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.audiotrack_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              'No audio tracks available',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: audios.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final audio = audios[index];
        final isSelected = audio.id == selectedAudio;
        final label = LanguageMapper.labelForTrack(audio, index);

        return _TrackTile(
          title: label,
          isSelected: isSelected,
          onTap: () async {
            onAudioChanged(audio.id);
            await player.setAudioTrack(audio);
            await onTrackChanged(audio.id, selectedSub);
          },
        );
      },
    );
  }
}

// ============================================================================
// Subtitles Tab — per-addon groups (Embedded | addon | addon …)
// ============================================================================

class _ProviderEntry {
  final String id;
  final String name;
  final AddonSubtitleSlot? slot; // null for the Embedded pseudo-provider
  const _ProviderEntry(this.id, this.name, this.slot);
}

class _SubtitlesTab extends StatelessWidget {
  final List<mk.SubtitleTrack> embeddedSubs;
  final List<AddonSubtitleSlot>? addonSlots;
  final bool slotsPending;
  final String selectedProviderId;
  final void Function(String) onProviderSelected;
  final void Function(String) onRetryAddon;
  final String selectedSub;
  final String selectedAudio;
  final mk.Player player;
  final Future<void> Function(String, String) onTrackChanged;
  final void Function(String) onSubChanged;
  final void Function(String? id)? onStremioSubtitleSelected;
  final Future<String?> Function(StremioSubtitle subtitle)?
  onDownloadStremioSubtitleToFile;
  final VoidCallback? onSubtitleTrackChanged;
  final bool isIdentifyingTitle;
  final String? subtitleIdentityLabel;
  final Future<void> Function()? onIdentifyTitle;
  final bool isWide;

  const _SubtitlesTab({
    super.key,
    required this.embeddedSubs,
    required this.addonSlots,
    required this.slotsPending,
    required this.selectedProviderId,
    required this.onProviderSelected,
    required this.onRetryAddon,
    required this.selectedSub,
    required this.selectedAudio,
    required this.player,
    required this.onTrackChanged,
    required this.onSubChanged,
    required this.onStremioSubtitleSelected,
    required this.onDownloadStremioSubtitleToFile,
    this.onSubtitleTrackChanged,
    required this.isIdentifyingTitle,
    required this.subtitleIdentityLabel,
    required this.onIdentifyTitle,
    required this.isWide,
  });

  /// A tap on subtitle [tappedId] is a genuine subtitle switch worth resetting
  /// the sync offset for — but only if it differs from what's already selected
  /// and the current selection isn't the ambiguous 'auto' sentinel (whose real
  /// track id we can't compare against, so we bias toward keeping the offset).
  bool _isRealSubtitleChange(String tappedId) =>
      tappedId != selectedSub && selectedSub != 'auto';

  List<_ProviderEntry> get _providers => [
        const _ProviderEntry('emb', 'Embedded', null),
        for (final slot in addonSlots ?? const <AddonSubtitleSlot>[])
          _ProviderEntry(slot.addonId, slot.addonName, slot),
      ];

  /// Whether the currently applied subtitle lives in this provider's group.
  bool _providerHasSelection(_ProviderEntry p) {
    if (p.slot == null) {
      return !selectedSub.startsWith('stremio:');
    }
    return p.slot!.subtitles.any((s) => 'stremio:${s.id}' == selectedSub);
  }

  String _effectiveProviderId(List<_ProviderEntry> providers) {
    if (providers.any((p) => p.id == selectedProviderId)) {
      return selectedProviderId;
    }
    return 'emb';
  }

  @override
  Widget build(BuildContext context) {
    final providers = _providers;
    final effectiveId = _effectiveProviderId(providers);
    final selected = providers.firstWhere((p) => p.id == effectiveId);

    final identity = onIdentifyTitle == null
        ? null
        : _IdentityStrip(
            identityLabel: subtitleIdentityLabel,
            isSearching: isIdentifyingTitle,
            onSearch: () => onIdentifyTitle!(),
          );

    if (isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (identity != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: identity,
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 220,
                    child: ListView(
                      children: [
                        for (final p in providers)
                          _ProviderTile(
                            entry: p,
                            embeddedCount: embeddedSubs.length,
                            isSelected: p.id == effectiveId,
                            hasActiveSub: _providerHasSelection(p),
                            onTap: () => onProviderSelected(p.id),
                          ),
                        if (slotsPending) const _ProviderPendingTile(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(width: 1, color: Colors.white.withValues(alpha: 0.06)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildProviderContent(selected)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (identity != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: identity,
          ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final p in providers)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ProviderChip(
                    entry: p,
                    embeddedCount: embeddedSubs.length,
                    isSelected: p.id == effectiveId,
                    hasActiveSub: _providerHasSelection(p),
                    onTap: () => onProviderSelected(p.id),
                  ),
                ),
              if (slotsPending)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: _ProviderChip.pending(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: _buildProviderContent(selected)),
      ],
    );
  }

  Widget _buildProviderContent(_ProviderEntry provider) {
    final padding = isWide
        ? EdgeInsets.zero
        : const EdgeInsets.fromLTRB(20, 0, 20, 20);

    if (provider.slot == null) {
      return ListView(
        padding: padding,
        children: [
          _TrackTile(
            title: 'Off',
            subtitle: 'Disable subtitles',
            isSelected: selectedSub == 'no',
            onTap: () async {
              final realChange = _isRealSubtitleChange('no');
              onSubChanged('no');
              await player.setSubtitleTrack(mk.SubtitleTrack.no());
              await onTrackChanged(selectedAudio, 'no');
              if (realChange) onSubtitleTrackChanged?.call();
            },
          ),
          const SizedBox(height: 8),
          if (embeddedSubs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'No embedded subtitle tracks in this file',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12.5,
                  ),
                ),
              ),
            )
          else
            ...embeddedSubs.asMap().entries.map((entry) {
              final index = entry.key;
              final sub = entry.value;
              final label = LanguageMapper.labelForTrack(sub, index);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TrackTile(
                  title: label,
                  isSelected: sub.id == selectedSub,
                  onTap: () async {
                    final realChange = _isRealSubtitleChange(sub.id);
                    onSubChanged(sub.id);
                    await player.setSubtitleTrack(sub);
                    await onTrackChanged(selectedAudio, sub.id);
                    if (realChange) onSubtitleTrackChanged?.call();
                  },
                ),
              );
            }),
        ],
      );
    }

    final slot = provider.slot!;
    switch (slot.status) {
      case AddonSubtitleStatus.loading:
        return ListView(
          padding: padding,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                height: 46,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            const SizedBox(height: 6),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: VideoPlayerColors.netflixRed,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Fetching from ${slot.addonName}…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case AddonSubtitleStatus.failed:
        return ListView(
          padding: padding,
          children: [
            _RetryCard(
              addonName: slot.addonName,
              error: slot.error,
              onRetry: () => onRetryAddon(slot.addonId),
            ),
          ],
        );
      case AddonSubtitleStatus.ok:
        if (slot.subtitles.isEmpty) {
          return ListView(
            padding: padding,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.subtitles_off_rounded,
                      size: 26,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No subtitles from this addon',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return ListView.builder(
          padding: padding,
          itemCount: slot.subtitles.length,
          itemBuilder: (context, index) {
            final sub = slot.subtitles[index];
            final subId = 'stremio:${sub.id}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TrackTile(
                title: sub.displayName,
                trailing: sub.lang.toUpperCase(),
                isSelected: subId == selectedSub,
                onTap: () async {
                  final realChange = _isRealSubtitleChange(subId);
                  onSubChanged(subId);
                  try {
                    final filePath = await onDownloadStremioSubtitleToFile
                        ?.call(sub);
                    // Download failed: leave the current subtitle (and its
                    // offset) untouched — do NOT fire onSubtitleTrackChanged.
                    if (filePath == null) return;

                    final track = mk.SubtitleTrack.uri(
                      filePath,
                      title: sub.displayName,
                      language: sub.lang,
                    );
                    await player.setSubtitleTrack(mk.SubtitleTrack.no());
                    await player.setSubtitleTrack(track);
                    onStremioSubtitleSelected?.call(sub.id);
                    await onTrackChanged(selectedAudio, subId);
                    if (realChange) onSubtitleTrackChanged?.call();
                  } catch (e) {
                    debugPrint('TracksSheet: Subtitle error - $e');
                  }
                },
              ),
            );
          },
        );
    }
  }
}

// ============================================================================
// Style Tab
// ============================================================================

class _StyleTab extends StatelessWidget {
  final SubtitleSettingsData subtitleStyle;
  final void Function(SubtitleSettingsData) onStyleChanged;
  final bool isWide;
  final VoidCallback? onSyncOverlayRequested;

  const _StyleTab({
    super.key,
    required this.subtitleStyle,
    required this.onStyleChanged,
    required this.isWide,
    this.onSyncOverlayRequested,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Preview
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: subtitleStyle.background.color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Sample Subtitle Text',
                  style: TextStyle(
                    color: subtitleStyle.color.color,
                    fontSize: subtitleStyle.size.sizePx * 0.5,
                    fontFamily: subtitleStyle.fontFamily,
                    shadows: subtitleStyle.resolvedShadows,
                  ),
                ),
              ),
            ),
          ),

          // Settings grid
          _StyleOption(
            label: 'Size',
            value: subtitleStyle.size.label,
            onDecrease: () async {
              final newIndex = (subtitleStyle.sizeIndex - 1).clamp(
                0,
                SubtitleSize.options.length - 1,
              );
              await SubtitleSettingsService.instance.setSizeIndex(newIndex);
              onStyleChanged(subtitleStyle.copyWith(sizeIndex: newIndex));
            },
            onIncrease: () async {
              final newIndex = (subtitleStyle.sizeIndex + 1).clamp(
                0,
                SubtitleSize.options.length - 1,
              );
              await SubtitleSettingsService.instance.setSizeIndex(newIndex);
              onStyleChanged(subtitleStyle.copyWith(sizeIndex: newIndex));
            },
          ),

          _StyleOption(
            label: 'Style',
            value: subtitleStyle.style.label,
            onDecrease: () async {
              final newIndex = (subtitleStyle.styleIndex - 1).clamp(
                0,
                SubtitleStyle.options.length - 1,
              );
              await SubtitleSettingsService.instance.setStyleIndex(newIndex);
              onStyleChanged(subtitleStyle.copyWith(styleIndex: newIndex));
            },
            onIncrease: () async {
              final newIndex = (subtitleStyle.styleIndex + 1).clamp(
                0,
                SubtitleStyle.options.length - 1,
              );
              await SubtitleSettingsService.instance.setStyleIndex(newIndex);
              onStyleChanged(subtitleStyle.copyWith(styleIndex: newIndex));
            },
          ),

          _StyleOption(
            label: 'Color',
            value: subtitleStyle.color.label,
            valueColor: subtitleStyle.color.color,
            onDecrease: () async {
              final newIndex = (subtitleStyle.colorIndex - 1).clamp(
                0,
                SubtitleColor.options.length - 1,
              );
              await SubtitleSettingsService.instance.setColorIndex(newIndex);
              onStyleChanged(subtitleStyle.copyWith(colorIndex: newIndex));
            },
            onIncrease: () async {
              final newIndex = (subtitleStyle.colorIndex + 1).clamp(
                0,
                SubtitleColor.options.length - 1,
              );
              await SubtitleSettingsService.instance.setColorIndex(newIndex);
              onStyleChanged(subtitleStyle.copyWith(colorIndex: newIndex));
            },
          ),

          _StyleOption(
            label: 'Outline',
            value: subtitleStyle.outlineColor.label,
            valueColor: subtitleStyle.outlineColor.color,
            onDecrease: () async {
              final newIndex = (subtitleStyle.outlineColorIndex - 1).clamp(
                0,
                SubtitleOutlineColor.options.length - 1,
              );
              await SubtitleSettingsService.instance.setOutlineColorIndex(
                newIndex,
              );
              onStyleChanged(
                subtitleStyle.copyWith(outlineColorIndex: newIndex),
              );
            },
            onIncrease: () async {
              final newIndex = (subtitleStyle.outlineColorIndex + 1).clamp(
                0,
                SubtitleOutlineColor.options.length - 1,
              );
              await SubtitleSettingsService.instance.setOutlineColorIndex(
                newIndex,
              );
              onStyleChanged(
                subtitleStyle.copyWith(outlineColorIndex: newIndex),
              );
            },
          ),

          _StyleOption(
            label: 'Background',
            value: subtitleStyle.background.label,
            onDecrease: () async {
              final newIndex = (subtitleStyle.bgIndex - 1).clamp(
                0,
                SubtitleBackground.options.length - 1,
              );
              await SubtitleSettingsService.instance.setBgIndex(newIndex);
              onStyleChanged(subtitleStyle.copyWith(bgIndex: newIndex));
            },
            onIncrease: () async {
              final newIndex = (subtitleStyle.bgIndex + 1).clamp(
                0,
                SubtitleBackground.options.length - 1,
              );
              await SubtitleSettingsService.instance.setBgIndex(newIndex);
              onStyleChanged(subtitleStyle.copyWith(bgIndex: newIndex));
            },
          ),

          _StyleOption(
            label: 'Font',
            value: subtitleStyle.font.label,
            onDecrease: () async {
              final newIndex = await SubtitleFontService.instance
                  .cycleFontDown();
              final font = await SubtitleFontService.instance.getSelectedFont();
              onStyleChanged(
                subtitleStyle.copyWith(
                  fontIndex: newIndex,
                  fontFamily: font.fontFamily,
                  fontLabel: font.label,
                ),
              );
            },
            onIncrease: () async {
              final newIndex = await SubtitleFontService.instance.cycleFontUp();
              final font = await SubtitleFontService.instance.getSelectedFont();
              onStyleChanged(
                subtitleStyle.copyWith(
                  fontIndex: newIndex,
                  fontFamily: font.fontFamily,
                  fontLabel: font.label,
                ),
              );
            },
          ),

          _StyleOption(
            label: 'Elevation',
            value: subtitleStyle.elevation.label,
            onDecrease: () async {
              final newIndex = (subtitleStyle.elevationIndex - 1).clamp(
                0,
                SubtitleElevation.options.length - 1,
              );
              await SubtitleSettingsService.instance.setElevationIndex(
                newIndex,
              );
              onStyleChanged(subtitleStyle.copyWith(elevationIndex: newIndex));
            },
            onIncrease: () async {
              final newIndex = (subtitleStyle.elevationIndex + 1).clamp(
                0,
                SubtitleElevation.options.length - 1,
              );
              await SubtitleSettingsService.instance.setElevationIndex(
                newIndex,
              );
              onStyleChanged(subtitleStyle.copyWith(elevationIndex: newIndex));
            },
          ),

          GestureDetector(
            onTap: onSyncOverlayRequested,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Sync',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    subtitleStyle.syncOffsetLabel,
                    style: TextStyle(
                      color: subtitleStyle.syncOffsetColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Reset button
          TextButton.icon(
            onPressed: () async {
              await SubtitleSettingsService.instance.resetToDefaults();
              final newSettings = await SubtitleSettingsService.instance
                  .loadAll();
              onStyleChanged(newSettings);
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reset to Defaults'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white60,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ============================================================================
// Shared Widgets
// ============================================================================

/// Compact "Detected: <title> · Fix" strip — the entry into the identify
/// flow, replacing the old full-width online-search panel.
class _IdentityStrip extends StatelessWidget {
  final String? identityLabel;
  final bool isSearching;
  final VoidCallback onSearch;

  const _IdentityStrip({
    required this.identityLabel,
    required this.isSearching,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final label = identityLabel?.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.travel_explore_rounded,
            size: 16,
            color: Colors.white54,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label == null || label.isEmpty
                  ? 'Title not detected — fix it to find subtitles'
                  : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: isSearching ? null : onSearch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFF4D57).withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSearching)
                    const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFFFF4D57),
                      ),
                    )
                  else
                    const Icon(
                      Icons.search_rounded,
                      size: 13,
                      color: Color(0xFFFF4D57),
                    ),
                  const SizedBox(width: 5),
                  const Text(
                    'Fix',
                    style: TextStyle(
                      color: Color(0xFFFF4D57),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal provider chip (phone layout).
class _ProviderChip extends StatelessWidget {
  final _ProviderEntry? entry;
  final int embeddedCount;
  final bool isSelected;
  final bool hasActiveSub;
  final VoidCallback? onTap;

  const _ProviderChip({
    required _ProviderEntry this.entry,
    required this.embeddedCount,
    required this.isSelected,
    required this.hasActiveSub,
    required this.onTap,
  });

  const _ProviderChip.pending()
      : entry = null,
        embeddedCount = 0,
        isSelected = false,
        hasActiveSub = false,
        onTap = null;

  @override
  Widget build(BuildContext context) {
    if (entry == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Colors.white38,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: isSelected
              ? VideoPlayerColors.netflixRed.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? VideoPlayerColors.netflixRed.withValues(alpha: 0.55)
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasActiveSub) ...[
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF4D57),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              entry!.name,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            _ProviderBadge(
              entry: entry!,
              embeddedCount: embeddedCount,
              emphasized: isSelected,
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical provider row (wide/desktop two-pane layout).
class _ProviderTile extends StatelessWidget {
  final _ProviderEntry entry;
  final int embeddedCount;
  final bool isSelected;
  final bool hasActiveSub;
  final VoidCallback onTap;

  const _ProviderTile({
    required this.entry,
    required this.embeddedCount,
    required this.isSelected,
    required this.hasActiveSub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected
              ? VideoPlayerColors.netflixRed.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isSelected
                ? VideoPlayerColors.netflixRed.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (hasActiveSub) ...[
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF4D57),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ProviderBadge(
              entry: entry,
              embeddedCount: embeddedCount,
              emphasized: isSelected,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderPendingTile extends StatelessWidget {
  const _ProviderPendingTile();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Colors.white38,
          ),
        ),
      ),
    );
  }
}

/// Count / spinner / warning badge shared by chip and tile.
class _ProviderBadge extends StatelessWidget {
  final _ProviderEntry entry;
  final int embeddedCount;
  final bool emphasized;

  const _ProviderBadge({
    required this.entry,
    required this.embeddedCount,
    required this.emphasized,
  });

  @override
  Widget build(BuildContext context) {
    final slot = entry.slot;
    if (slot != null && slot.status == AddonSubtitleStatus.loading) {
      return const SizedBox(
        width: 11,
        height: 11,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Colors.white54,
        ),
      );
    }
    if (slot != null && slot.status == AddonSubtitleStatus.failed) {
      return const Icon(
        Icons.warning_amber_rounded,
        size: 14,
        color: Color(0xFFFFB300),
      );
    }
    final count = slot == null ? embeddedCount : slot.subtitles.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: emphasized
            ? VideoPlayerColors.netflixRed.withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: emphasized ? Colors.white : Colors.white54,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Failed addon: error card with a per-addon retry, mirroring the TV menu's
/// "Failed — retry this addon" row.
class _RetryCard extends StatelessWidget {
  final String addonName;
  final String? error;
  final VoidCallback onRetry;

  const _RetryCard({
    required this.addonName,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final err = error?.trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0xFFEF4444).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 26,
            color: Color(0xFFFFB300),
          ),
          const SizedBox(height: 8),
          Text(
            '$addonName failed to load',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (err != null && err.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              err.length > 90 ? '${err.substring(0, 90)}…' : err,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFFEF4444).withValues(alpha: 0.85),
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE50914), Color(0xFFFF4D57)],
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, size: 16, color: Colors.white),
                  SizedBox(width: 7),
                  Text(
                    'Retry this addon',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;
  final bool isSelected;
  final VoidCallback onTap;

  const _TrackTile({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? VideoPlayerColors.netflixRed.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? VideoPlayerColors.netflixRed.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? VideoPlayerColors.netflixRed
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? VideoPlayerColors.netflixRed
                      : Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            // Title & subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? VideoPlayerColors.netflixRed.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  trailing!,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StyleOption extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _StyleOption({
    required this.label,
    required this.value,
    this.valueColor,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Label
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Decrease
          GestureDetector(
            onTap: onDecrease,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.chevron_left_rounded,
                color: Colors.white70,
                size: 24,
              ),
            ),
          ),
          // Value
          Container(
            width: 90,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (valueColor != null) ...[
                  Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: valueColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ],
                Flexible(
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Increase
          GestureDetector(
            onTap: onIncrease,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white70,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
