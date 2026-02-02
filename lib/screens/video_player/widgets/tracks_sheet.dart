import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;
import '../../../models/stremio_subtitle.dart';
import '../../../services/stremio_subtitle_service.dart';
import '../../../services/subtitle_font_service.dart';
import '../constants/color_constants.dart';
import '../widgets/netflix_radio_tile.dart';
import '../utils/language_mapping.dart';
import '../services/subtitle_settings_service.dart';

/// Modal bottom sheet for selecting audio and subtitle tracks
///
/// Provides a Netflix-style UI for switching between available
/// audio tracks and subtitle options, with separate sections for
/// embedded and addon subtitles.
class TracksSheet {
  /// Shows the tracks selection bottom sheet
  ///
  /// Parameters:
  /// - [context]: Build context for showing the modal
  /// - [player]: media_kit player instance
  /// - [onTrackChanged]: Callback when tracks are changed (audio ID, subtitle ID)
  /// - [onSubtitleStyleChanged]: Callback when subtitle style settings change
  /// - [contentImdbId]: IMDB ID for fetching addon subtitles
  /// - [contentType]: Content type ('movie' or 'series')
  /// - [contentSeason]: Season number for series
  /// - [contentEpisode]: Episode number for series
  /// - [cachedSubtitles]: Pre-fetched subtitles from parent (per-item cache)
  /// - [onSubtitlesFetched]: Callback to return fetched subtitles for caching
  /// - [selectedStremioSubtitleId]: Currently selected addon subtitle ID (for UI state)
  /// - [onStremioSubtitleSelected]: Callback when addon subtitle selection changes
  static Future<void> show(
    BuildContext context,
    mk.Player player, {
    required Future<void> Function(String audioId, String subtitleId)
        onTrackChanged,
    void Function(SubtitleSettingsData settings)? onSubtitleStyleChanged,
    String? contentImdbId,
    String? contentType,
    int? contentSeason,
    int? contentEpisode,
    List<StremioSubtitle>? cachedSubtitles,
    void Function(List<StremioSubtitle> subtitles)? onSubtitlesFetched,
    String? selectedStremioSubtitleId,
    void Function(String? id)? onStremioSubtitleSelected,
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
    // For subtitle selection: use stremio ID if one is selected, otherwise use player's track ID
    String selectedSub = selectedStremioSubtitleId != null
        ? 'stremio:$selectedStremioSubtitleId'
        : player.state.track.subtitle.id;

    // Load subtitle style settings
    SubtitleSettingsData subtitleStyle =
        await SubtitleSettingsService.instance.loadAll();

    // Stremio addon subtitles state
    // Use cached subtitles if provided (per-item cache like Android TV)
    List<StremioSubtitle>? stremioSubtitles = cachedSubtitles;
    bool isLoadingStremioSubtitles = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: VideoPlayerColors.darkBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.75,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  // Debug: Log content metadata
                  debugPrint('TracksSheet: contentImdbId=$contentImdbId, '
                      'contentType=$contentType, '
                      'season=$contentSeason, episode=$contentEpisode');
                  debugPrint('TracksSheet: stremioSubtitles=${stremioSubtitles?.length}, '
                      'isLoading=$isLoadingStremioSubtitles');

                  // Fetch Stremio subtitles on first build (skip if cached)
                  if (stremioSubtitles == null &&
                      !isLoadingStremioSubtitles &&
                      contentImdbId != null &&
                      contentType != null) {
                    // Set loading state
                    isLoadingStremioSubtitles = true;
                    debugPrint('TracksSheet: Starting subtitle fetch...');
                    // Trigger async fetch
                    Future(() async {
                      try {
                        debugPrint('TracksSheet: Calling StremioSubtitleService.fetchSubtitles()');
                        final result =
                            await StremioSubtitleService.instance.fetchSubtitles(
                          type: contentType,
                          imdbId: contentImdbId,
                          season: contentSeason,
                          episode: contentEpisode,
                        );
                        debugPrint('TracksSheet: Fetch complete, got ${result.subtitles.length} subtitles');
                        setModalState(() {
                          stremioSubtitles = result.subtitles;
                          isLoadingStremioSubtitles = false;
                        });
                        // Notify parent to cache these subtitles
                        onSubtitlesFetched?.call(result.subtitles);
                      } catch (e) {
                        debugPrint('TracksSheet: Fetch error: $e');
                        setModalState(() {
                          isLoadingStremioSubtitles = false;
                        });
                      }
                    });
                  } else if (stremioSubtitles != null) {
                    debugPrint('TracksSheet: Using ${stremioSubtitles!.length} cached subtitles');
                  } else if (contentImdbId == null || contentType == null) {
                    debugPrint('TracksSheet: No content metadata provided, skipping subtitle fetch');
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      _buildHeader(context),
                      const SizedBox(height: 16),

                      // Scrollable content
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Audio tracks section
                              if (audios.isNotEmpty) ...[
                                _buildSectionHeader(
                                  icon: Icons.audiotrack_rounded,
                                  title: 'AUDIO TRACK',
                                ),
                                const SizedBox(height: 12),
                                _buildAudioTracksList(
                                  audios: audios,
                                  selectedAudio: selectedAudio,
                                  player: player,
                                  selectedSub: selectedSub,
                                  onTrackChanged: onTrackChanged,
                                  setModalState: setModalState,
                                  onAudioChanged: (v) {
                                    setModalState(() => selectedAudio = v);
                                  },
                                ),
                                const SizedBox(height: 20),
                              ],

                              // Subtitles Off option + Embedded subtitles section
                              _buildSectionHeader(
                                icon: Icons.subtitles_rounded,
                                title: embeddedSubs.isNotEmpty
                                    ? 'EMBEDDED SUBTITLES'
                                    : 'SUBTITLES',
                              ),
                              const SizedBox(height: 12),
                              _buildSubtitleOffTile(
                                selectedSub: selectedSub,
                                selectedAudio: selectedAudio,
                                player: player,
                                onTrackChanged: onTrackChanged,
                                setModalState: setModalState,
                                onSubChanged: (v) {
                                  setModalState(() => selectedSub = v);
                                  onStremioSubtitleSelected?.call(null); // Clear addon selection
                                },
                              ),
                              if (embeddedSubs.isNotEmpty)
                                _buildEmbeddedSubtitlesList(
                                  subs: embeddedSubs,
                                  selectedSub: selectedSub,
                                  selectedAudio: selectedAudio,
                                  player: player,
                                  onTrackChanged: onTrackChanged,
                                  setModalState: setModalState,
                                  onSubChanged: (v) {
                                    setModalState(() => selectedSub = v);
                                    onStremioSubtitleSelected?.call(null); // Clear addon selection
                                  },
                                ),

                              // Addon subtitles section
                              if ((stremioSubtitles != null &&
                                      stremioSubtitles!.isNotEmpty) ||
                                  isLoadingStremioSubtitles) ...[
                                const SizedBox(height: 20),
                                _buildSectionHeader(
                                  icon: Icons.extension_rounded,
                                  title: 'ADDON SUBTITLES',
                                  trailing: isLoadingStremioSubtitles
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white54,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                if (isLoadingStremioSubtitles &&
                                    (stremioSubtitles == null ||
                                        stremioSubtitles!.isEmpty))
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: Text(
                                        'Loading subtitles from addons...',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  )
                                else if (stremioSubtitles != null)
                                  _buildAddonSubtitlesList(
                                    subtitles: stremioSubtitles!,
                                    selectedSub: selectedSub,
                                    selectedAudio: selectedAudio,
                                    player: player,
                                    onTrackChanged: onTrackChanged,
                                    setModalState: setModalState,
                                    onSubChanged: (v) {
                                      setModalState(() => selectedSub = v);
                                    },
                                    onStremioSubtitleSelected: onStremioSubtitleSelected,
                                  ),
                              ],

                              // Subtitle Style section
                              const SizedBox(height: 20),
                              _buildSectionHeader(
                                icon: Icons.format_size_rounded,
                                title: 'SUBTITLE STYLE',
                              ),
                              const SizedBox(height: 12),
                              _buildSubtitleStyleSettings(
                                subtitleStyle: subtitleStyle,
                                setModalState: setModalState,
                                onStyleChanged: (newStyle) {
                                  setModalState(() => subtitleStyle = newStyle);
                                  onSubtitleStyleChanged?.call(newStyle);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: VideoPlayerColors.netflixRed.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.tune_rounded,
            color: VideoPlayerColors.netflixRed,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'Audio & Subtitles',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          if (trailing != null) ...[
            const Spacer(),
            trailing,
          ],
        ],
      ),
    );
  }

  static Widget _buildAudioTracksList({
    required List<mk.AudioTrack> audios,
    required String selectedAudio,
    required mk.Player player,
    required String selectedSub,
    required Future<void> Function(String, String) onTrackChanged,
    required StateSetter setModalState,
    required void Function(String) onAudioChanged,
  }) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: audios.length,
      itemBuilder: (context, index) {
        final a = audios[index];
        return NetflixRadioTile(
          value: a.id,
          groupValue: selectedAudio,
          title: LanguageMapper.labelForTrack(a, index),
          onChanged: (v) async {
            if (v == null) return;
            onAudioChanged(v);
            await player.setAudioTrack(a);
            await onTrackChanged(v, selectedSub);
          },
        );
      },
    );
  }

  static Widget _buildSubtitleOffTile({
    required String selectedSub,
    required String selectedAudio,
    required mk.Player player,
    required Future<void> Function(String, String) onTrackChanged,
    required StateSetter setModalState,
    required void Function(String) onSubChanged,
  }) {
    return NetflixRadioTile(
      value: 'no',
      groupValue: selectedSub,
      title: 'Off',
      onChanged: (v) async {
        if (v == null) return;
        onSubChanged(v);
        await player.setSubtitleTrack(mk.SubtitleTrack.no());
        await onTrackChanged(selectedAudio, v);
      },
    );
  }

  static Widget _buildEmbeddedSubtitlesList({
    required List<mk.SubtitleTrack> subs,
    required String selectedSub,
    required String selectedAudio,
    required mk.Player player,
    required Future<void> Function(String, String) onTrackChanged,
    required StateSetter setModalState,
    required void Function(String) onSubChanged,
  }) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: subs.length,
      itemBuilder: (context, index) {
        final s = subs[index];
        return NetflixRadioTile(
          value: s.id,
          groupValue: selectedSub,
          title: LanguageMapper.labelForTrack(s, index),
          onChanged: (v) async {
            if (v == null) return;
            onSubChanged(v);
            await player.setSubtitleTrack(s);
            await onTrackChanged(selectedAudio, v);
          },
        );
      },
    );
  }

  static Widget _buildAddonSubtitlesList({
    required List<StremioSubtitle> subtitles,
    required String selectedSub,
    required String selectedAudio,
    required mk.Player player,
    required Future<void> Function(String, String) onTrackChanged,
    required StateSetter setModalState,
    required void Function(String) onSubChanged,
    void Function(String? id)? onStremioSubtitleSelected,
  }) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: subtitles.length,
      itemBuilder: (context, index) {
        final sub = subtitles[index];
        // Use a prefix to distinguish addon subtitles from embedded ones
        final subId = 'stremio:${sub.id}';
        return NetflixRadioTile(
          value: subId,
          groupValue: selectedSub,
          title: sub.displayName,
          subtitle: sub.source,
          onChanged: (v) async {
            if (v == null) return;
            onSubChanged(v);

            // Fetch and load external subtitle using data() for reliability
            try {
              final response = await http.get(Uri.parse(sub.url)).timeout(
                const Duration(seconds: 15),
              );

              if (response.statusCode != 200) {
                debugPrint('TracksSheet: Subtitle fetch failed - HTTP ${response.statusCode}');
                return;
              }

              final track = mk.SubtitleTrack.data(
                response.body,
                title: sub.displayName,
                language: sub.lang,
              );

              // Disable current subtitle first to prevent duplicates
              await player.setSubtitleTrack(mk.SubtitleTrack.no());
              await player.setSubtitleTrack(track);
              debugPrint('TracksSheet: Loaded "${sub.displayName}" (${response.body.length} bytes)');

              // Notify parent of addon subtitle selection
              onStremioSubtitleSelected?.call(sub.id);

              await onTrackChanged(selectedAudio, v);
            } catch (e) {
              debugPrint('TracksSheet: Subtitle error - $e');
            }
          },
        );
      },
    );
  }

  static Widget _buildSubtitleStyleSettings({
    required SubtitleSettingsData subtitleStyle,
    required StateSetter setModalState,
    required void Function(SubtitleSettingsData) onStyleChanged,
  }) {
    return Column(
      children: [
        // Size setting
        _SubtitleStyleRow(
          label: 'Size',
          value: subtitleStyle.size.label,
          onDecrease: () async {
            final newIndex = (subtitleStyle.sizeIndex - 1)
                .clamp(0, SubtitleSize.options.length - 1);
            await SubtitleSettingsService.instance.setSizeIndex(newIndex);
            onStyleChanged(subtitleStyle.copyWith(sizeIndex: newIndex));
          },
          onIncrease: () async {
            final newIndex = (subtitleStyle.sizeIndex + 1)
                .clamp(0, SubtitleSize.options.length - 1);
            await SubtitleSettingsService.instance.setSizeIndex(newIndex);
            onStyleChanged(subtitleStyle.copyWith(sizeIndex: newIndex));
          },
        ),

        // Style setting
        _SubtitleStyleRow(
          label: 'Style',
          value: subtitleStyle.style.label,
          onDecrease: () async {
            final newIndex = (subtitleStyle.styleIndex - 1)
                .clamp(0, SubtitleStyle.options.length - 1);
            await SubtitleSettingsService.instance.setStyleIndex(newIndex);
            onStyleChanged(subtitleStyle.copyWith(styleIndex: newIndex));
          },
          onIncrease: () async {
            final newIndex = (subtitleStyle.styleIndex + 1)
                .clamp(0, SubtitleStyle.options.length - 1);
            await SubtitleSettingsService.instance.setStyleIndex(newIndex);
            onStyleChanged(subtitleStyle.copyWith(styleIndex: newIndex));
          },
        ),

        // Color setting
        _SubtitleStyleRow(
          label: 'Color',
          value: subtitleStyle.color.label,
          valueColor: subtitleStyle.color.color,
          onDecrease: () async {
            final newIndex = (subtitleStyle.colorIndex - 1)
                .clamp(0, SubtitleColor.options.length - 1);
            await SubtitleSettingsService.instance.setColorIndex(newIndex);
            onStyleChanged(subtitleStyle.copyWith(colorIndex: newIndex));
          },
          onIncrease: () async {
            final newIndex = (subtitleStyle.colorIndex + 1)
                .clamp(0, SubtitleColor.options.length - 1);
            await SubtitleSettingsService.instance.setColorIndex(newIndex);
            onStyleChanged(subtitleStyle.copyWith(colorIndex: newIndex));
          },
        ),

        // Background setting
        _SubtitleStyleRow(
          label: 'Background',
          value: subtitleStyle.background.label,
          onDecrease: () async {
            final newIndex = (subtitleStyle.bgIndex - 1)
                .clamp(0, SubtitleBackground.options.length - 1);
            await SubtitleSettingsService.instance.setBgIndex(newIndex);
            onStyleChanged(subtitleStyle.copyWith(bgIndex: newIndex));
          },
          onIncrease: () async {
            final newIndex = (subtitleStyle.bgIndex + 1)
                .clamp(0, SubtitleBackground.options.length - 1);
            await SubtitleSettingsService.instance.setBgIndex(newIndex);
            onStyleChanged(subtitleStyle.copyWith(bgIndex: newIndex));
          },
        ),

        // Font setting
        _SubtitleStyleRow(
          label: 'Font',
          value: subtitleStyle.font.label,
          onDecrease: () async {
            final newIndex = await SubtitleFontService.instance.cycleFontDown();
            final fontFamily = await SubtitleFontService.instance.getFontFamily();
            onStyleChanged(subtitleStyle.copyWith(
              fontIndex: newIndex,
              fontFamily: fontFamily,
            ));
          },
          onIncrease: () async {
            final newIndex = await SubtitleFontService.instance.cycleFontUp();
            final fontFamily = await SubtitleFontService.instance.getFontFamily();
            onStyleChanged(subtitleStyle.copyWith(
              fontIndex: newIndex,
              fontFamily: fontFamily,
            ));
          },
        ),

        // Reset button
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: () async {
              await SubtitleSettingsService.instance.resetToDefaults();
              final newSettings =
                  await SubtitleSettingsService.instance.loadAll();
              onStyleChanged(newSettings);
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reset to Defaults'),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ),
      ],
    );
  }
}

/// A row widget for adjusting subtitle style settings
class _SubtitleStyleRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _SubtitleStyleRow({
    required this.label,
    required this.value,
    this.valueColor,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            onPressed: onDecrease,
            icon: const Icon(Icons.remove_rounded),
            iconSize: 20,
            color: Colors.white70,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              padding: const EdgeInsets.all(8),
            ),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (valueColor != null) ...[
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: valueColor,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onIncrease,
            icon: const Icon(Icons.add_rounded),
            iconSize: 20,
            color: Colors.white70,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }
}
