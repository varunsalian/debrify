import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;
import '../../../models/stremio_subtitle.dart';
import '../../../services/stremio_subtitle_service.dart';
import '../../../services/subtitle_font_service.dart';
import '../constants/color_constants.dart';
import '../utils/language_mapping.dart';
import '../services/subtitle_settings_service.dart';

/// Modal bottom sheet for selecting audio and subtitle tracks
///
/// Provides a Netflix-style UI for switching between available
/// audio tracks and subtitle options, with separate sections for
/// embedded and addon subtitles.
class TracksSheet {
  /// Shows the tracks selection bottom sheet
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
    String selectedSub = selectedStremioSubtitleId != null
        ? 'stremio:$selectedStremioSubtitleId'
        : player.state.track.subtitle.id;

    SubtitleSettingsData subtitleStyle =
        await SubtitleSettingsService.instance.loadAll();

    List<StremioSubtitle>? stremioSubtitles = cachedSubtitles;
    bool isLoadingStremioSubtitles = false;
    int selectedTabIndex = 0;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Fetch Stremio subtitles on first build
            if (stremioSubtitles == null &&
                !isLoadingStremioSubtitles &&
                contentImdbId != null &&
                contentType != null) {
              isLoadingStremioSubtitles = true;
              Future(() async {
                try {
                  final result =
                      await StremioSubtitleService.instance.fetchSubtitles(
                    type: contentType,
                    imdbId: contentImdbId,
                    season: contentSeason,
                    episode: contentEpisode,
                  );
                  setModalState(() {
                    stremioSubtitles = result.subtitles;
                    isLoadingStremioSubtitles = false;
                  });
                  onSubtitlesFetched?.call(result.subtitles);
                } catch (e) {
                  debugPrint('TracksSheet: Fetch error: $e');
                  setModalState(() => isLoadingStremioSubtitles = false);
                }
              });
            }

            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;
            final isWide = screenWidth > 600;
            final isLandscape = screenWidth > screenHeight;

            // Use more height on mobile landscape to show more options
            final sheetHeight = isLandscape
                ? screenHeight * 0.85  // 85% in landscape
                : screenHeight * 0.7;  // 70% in portrait

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
                            badge: audios.isNotEmpty ? '${audios.length}' : null,
                            isSelected: selectedTabIndex == 0,
                            onTap: () => setModalState(() => selectedTabIndex = 0),
                          ),
                          _buildTab(
                            icon: Icons.subtitles_rounded,
                            label: 'Subtitles',
                            badge: isLoadingStremioSubtitles
                                ? '...'
                                : _getSubtitleCount(embeddedSubs, stremioSubtitles),
                            isSelected: selectedTabIndex == 1,
                            onTap: () => setModalState(() => selectedTabIndex = 1),
                          ),
                          _buildTab(
                            icon: Icons.text_format_rounded,
                            label: 'Style',
                            isSelected: selectedTabIndex == 2,
                            onTap: () => setModalState(() => selectedTabIndex = 2),
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
                        onAudioChanged: (v) => setModalState(() => selectedAudio = v),
                        embeddedSubs: embeddedSubs,
                        stremioSubtitles: stremioSubtitles,
                        isLoadingStremioSubtitles: isLoadingStremioSubtitles,
                        onSubChanged: (v) {
                          setModalState(() => selectedSub = v);
                          if (!v.startsWith('stremio:')) {
                            onStremioSubtitleSelected?.call(null);
                          }
                        },
                        onStremioSubtitleSelected: onStremioSubtitleSelected,
                        subtitleStyle: subtitleStyle,
                        onStyleChanged: (newStyle) {
                          setModalState(() => subtitleStyle = newStyle);
                          onSubtitleStyleChanged?.call(newStyle);
                        },
                        isWide: isWide,
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

  static String? _getSubtitleCount(
    List<mk.SubtitleTrack> embedded,
    List<StremioSubtitle>? addon,
  ) {
    final count = embedded.length + (addon?.length ?? 0);
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    required List<StremioSubtitle>? stremioSubtitles,
    required bool isLoadingStremioSubtitles,
    required void Function(String) onSubChanged,
    required void Function(String? id)? onStremioSubtitleSelected,
    required SubtitleSettingsData subtitleStyle,
    required void Function(SubtitleSettingsData) onStyleChanged,
    required bool isWide,
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
          stremioSubtitles: stremioSubtitles,
          isLoading: isLoadingStremioSubtitles,
          selectedSub: selectedSub,
          selectedAudio: selectedAudio,
          player: player,
          onTrackChanged: onTrackChanged,
          onSubChanged: onSubChanged,
          onStremioSubtitleSelected: onStremioSubtitleSelected,
        );
      case 2:
        return _StyleTab(
          key: key,
          subtitleStyle: subtitleStyle,
          onStyleChanged: onStyleChanged,
          isWide: isWide,
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
// Subtitles Tab
// ============================================================================

class _SubtitlesTab extends StatelessWidget {
  final List<mk.SubtitleTrack> embeddedSubs;
  final List<StremioSubtitle>? stremioSubtitles;
  final bool isLoading;
  final String selectedSub;
  final String selectedAudio;
  final mk.Player player;
  final Future<void> Function(String, String) onTrackChanged;
  final void Function(String) onSubChanged;
  final void Function(String? id)? onStremioSubtitleSelected;

  const _SubtitlesTab({
    super.key,
    required this.embeddedSubs,
    required this.stremioSubtitles,
    required this.isLoading,
    required this.selectedSub,
    required this.selectedAudio,
    required this.player,
    required this.onTrackChanged,
    required this.onSubChanged,
    required this.onStremioSubtitleSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // Off option
        _TrackTile(
          title: 'Off',
          subtitle: 'Disable subtitles',
          isSelected: selectedSub == 'no',
          onTap: () async {
            onSubChanged('no');
            await player.setSubtitleTrack(mk.SubtitleTrack.no());
            await onTrackChanged(selectedAudio, 'no');
          },
        ),

        // Embedded subtitles
        if (embeddedSubs.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionLabel(label: 'Embedded', count: embeddedSubs.length),
          const SizedBox(height: 8),
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
                  onSubChanged(sub.id);
                  await player.setSubtitleTrack(sub);
                  await onTrackChanged(selectedAudio, sub.id);
                },
              ),
            );
          }),
        ],

        // Addon subtitles
        if (isLoading || (stremioSubtitles != null && stremioSubtitles!.isNotEmpty)) ...[
          const SizedBox(height: 16),
          _SectionLabel(
            label: 'From Addons',
            count: stremioSubtitles?.length,
            isLoading: isLoading,
          ),
          const SizedBox(height: 8),
          if (isLoading && (stremioSubtitles == null || stremioSubtitles!.isEmpty))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: VideoPlayerColors.netflixRed,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Loading subtitles...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (stremioSubtitles != null)
            ...stremioSubtitles!.map((sub) {
              final subId = 'stremio:${sub.id}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TrackTile(
                  title: sub.displayName,
                  subtitle: sub.source,
                  isSelected: subId == selectedSub,
                  onTap: () async {
                    onSubChanged(subId);
                    try {
                      final response = await http.get(Uri.parse(sub.url)).timeout(
                        const Duration(seconds: 15),
                      );
                      if (response.statusCode != 200) return;

                      final track = mk.SubtitleTrack.data(
                        response.body,
                        title: sub.displayName,
                        language: sub.lang,
                      );
                      await player.setSubtitleTrack(mk.SubtitleTrack.no());
                      await player.setSubtitleTrack(track);
                      onStremioSubtitleSelected?.call(sub.id);
                      await onTrackChanged(selectedAudio, subId);
                    } catch (e) {
                      debugPrint('TracksSheet: Subtitle error - $e');
                    }
                  },
                ),
              );
            }),
        ],

        const SizedBox(height: 20),
      ],
    );
  }
}

// ============================================================================
// Style Tab
// ============================================================================

class _StyleTab extends StatelessWidget {
  final SubtitleSettingsData subtitleStyle;
  final void Function(SubtitleSettingsData) onStyleChanged;
  final bool isWide;

  const _StyleTab({
    super.key,
    required this.subtitleStyle,
    required this.onStyleChanged,
    required this.isWide,
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
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

          _StyleOption(
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

          _StyleOption(
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

          _StyleOption(
            label: 'Outline',
            value: subtitleStyle.outlineColor.label,
            valueColor: subtitleStyle.outlineColor.color,
            onDecrease: () async {
              final newIndex = (subtitleStyle.outlineColorIndex - 1)
                  .clamp(0, SubtitleOutlineColor.options.length - 1);
              await SubtitleSettingsService.instance
                  .setOutlineColorIndex(newIndex);
              onStyleChanged(
                  subtitleStyle.copyWith(outlineColorIndex: newIndex));
            },
            onIncrease: () async {
              final newIndex = (subtitleStyle.outlineColorIndex + 1)
                  .clamp(0, SubtitleOutlineColor.options.length - 1);
              await SubtitleSettingsService.instance
                  .setOutlineColorIndex(newIndex);
              onStyleChanged(
                  subtitleStyle.copyWith(outlineColorIndex: newIndex));
            },
          ),

          _StyleOption(
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

          _StyleOption(
            label: 'Font',
            value: subtitleStyle.font.label,
            onDecrease: () async {
              final newIndex = await SubtitleFontService.instance.cycleFontDown();
              final font = await SubtitleFontService.instance.getSelectedFont();
              onStyleChanged(subtitleStyle.copyWith(
                fontIndex: newIndex,
                fontFamily: font.fontFamily,
                fontLabel: font.label,
              ));
            },
            onIncrease: () async {
              final newIndex = await SubtitleFontService.instance.cycleFontUp();
              final font = await SubtitleFontService.instance.getSelectedFont();
              onStyleChanged(subtitleStyle.copyWith(
                fontIndex: newIndex,
                fontFamily: font.fontFamily,
                fontLabel: font.label,
              ));
            },
          ),

          _StyleOption(
            label: 'Elevation',
            value: subtitleStyle.elevation.label,
            onDecrease: () async {
              final newIndex = (subtitleStyle.elevationIndex - 1)
                  .clamp(0, SubtitleElevation.options.length - 1);
              await SubtitleSettingsService.instance
                  .setElevationIndex(newIndex);
              onStyleChanged(
                  subtitleStyle.copyWith(elevationIndex: newIndex));
            },
            onIncrease: () async {
              final newIndex = (subtitleStyle.elevationIndex + 1)
                  .clamp(0, SubtitleElevation.options.length - 1);
              await SubtitleSettingsService.instance
                  .setElevationIndex(newIndex);
              onStyleChanged(
                  subtitleStyle.copyWith(elevationIndex: newIndex));
            },
          ),

          const SizedBox(height: 20),

          // Reset button
          TextButton.icon(
            onPressed: () async {
              await SubtitleSettingsService.instance.resetToDefaults();
              final newSettings =
                  await SubtitleSettingsService.instance.loadAll();
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

class _TrackTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _TrackTile({
    required this.title,
    this.subtitle,
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
            // Selection indicator
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
                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
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
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final int? count;
  final bool isLoading;

  const _SectionLabel({
    required this.label,
    this.count,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: VideoPlayerColors.netflixRed,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        if (count != null || isLoading) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: isLoading && count == null
                ? const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white54,
                    ),
                  )
                : Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ],
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
