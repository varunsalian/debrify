import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import '../constants/color_constants.dart';
import '../widgets/netflix_radio_tile.dart';
import '../utils/language_mapping.dart';
import '../services/subtitle_settings_service.dart';

/// Modal bottom sheet for selecting audio and subtitle tracks
///
/// Provides a Netflix-style UI for switching between available
/// audio tracks and subtitle options.
class TracksSheet {
  /// Shows the tracks selection bottom sheet
  ///
  /// Parameters:
  /// - [context]: Build context for showing the modal
  /// - [player]: media_kit player instance
  /// - [onTrackChanged]: Callback when tracks are changed (audio ID, subtitle ID)
  /// - [onSubtitleStyleChanged]: Callback when subtitle style settings change
  static Future<void> show(
    BuildContext context,
    mk.Player player, {
    required Future<void> Function(String audioId, String subtitleId) onTrackChanged,
    void Function(SubtitleSettingsData settings)? onSubtitleStyleChanged,
  }) async {
    final tracks = player.state.tracks;
    final audios = tracks.audio
        .where((a) => a.id.toLowerCase() != 'no')
        .toList(growable: false);
    final subs = tracks.subtitle
        .where(
          (s) => s.id.toLowerCase() != 'auto' && s.id.toLowerCase() != 'no',
        )
        .toList(growable: false);
    String selectedAudio = player.state.track.audio.id;
    String selectedSub = player.state.track.subtitle.id;

    // Load subtitle style settings
    SubtitleSettingsData subtitleStyle =
        await SubtitleSettingsService.instance.loadAll();

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
            heightFactor: 0.7,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
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
                      ),
                      const SizedBox(height: 16),

                      // Scrollable content
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Audio tracks section
                              if (audios.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    children: [
                                      Icon(Icons.audiotrack_rounded,
                                          color: Colors.white70, size: 18),
                                      SizedBox(width: 8),
                                      Text(
                                        'AUDIO TRACK',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ListView.builder(
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
                                        setModalState(() {
                                          selectedAudio = v;
                                        });
                                        await player.setAudioTrack(a);
                                        await onTrackChanged(v, selectedSub);
                                      },
                                    );
                                  },
                                ),
                                const SizedBox(height: 20),
                              ],

                              // Subtitle tracks section
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.subtitles_rounded,
                                        color: Colors.white70, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'SUBTITLES',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: subs.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == 0) {
                                    return NetflixRadioTile(
                                      value: 'no',
                                      groupValue: selectedSub,
                                      title: 'Off',
                                      onChanged: (v) async {
                                        if (v == null) return;
                                        setModalState(() {
                                          selectedSub = v;
                                        });
                                        await player.setSubtitleTrack(mk.SubtitleTrack.no());
                                        await onTrackChanged(
                                          selectedAudio,
                                          v,
                                        );
                                      },
                                    );
                                  }
                                  final s = subs[index - 1];
                                  return NetflixRadioTile(
                                    value: s.id,
                                    groupValue: selectedSub,
                                    title: LanguageMapper.labelForTrack(s, index - 1),
                                    onChanged: (v) async {
                                      if (v == null) return;
                                      setModalState(() {
                                        selectedSub = v;
                                      });
                                      await player.setSubtitleTrack(s);
                                      await onTrackChanged(
                                        selectedAudio,
                                        v,
                                      );
                                    },
                                  );
                                },
                              ),

                              // Subtitle Style section
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.format_size_rounded,
                                        color: Colors.white70, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'SUBTITLE STYLE',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Size setting
                              _SubtitleStyleRow(
                                label: 'Size',
                                value: subtitleStyle.size.label,
                                onDecrease: () async {
                                  final newIndex = (subtitleStyle.sizeIndex - 1)
                                      .clamp(0, SubtitleSize.options.length - 1);
                                  await SubtitleSettingsService.instance
                                      .setSizeIndex(newIndex);
                                  setModalState(() {
                                    subtitleStyle = subtitleStyle.copyWith(
                                        sizeIndex: newIndex);
                                  });
                                  onSubtitleStyleChanged?.call(subtitleStyle);
                                },
                                onIncrease: () async {
                                  final newIndex = (subtitleStyle.sizeIndex + 1)
                                      .clamp(0, SubtitleSize.options.length - 1);
                                  await SubtitleSettingsService.instance
                                      .setSizeIndex(newIndex);
                                  setModalState(() {
                                    subtitleStyle = subtitleStyle.copyWith(
                                        sizeIndex: newIndex);
                                  });
                                  onSubtitleStyleChanged?.call(subtitleStyle);
                                },
                              ),

                              // Style setting
                              _SubtitleStyleRow(
                                label: 'Style',
                                value: subtitleStyle.style.label,
                                onDecrease: () async {
                                  final newIndex = (subtitleStyle.styleIndex - 1)
                                      .clamp(0, SubtitleStyle.options.length - 1);
                                  await SubtitleSettingsService.instance
                                      .setStyleIndex(newIndex);
                                  setModalState(() {
                                    subtitleStyle = subtitleStyle.copyWith(
                                        styleIndex: newIndex);
                                  });
                                  onSubtitleStyleChanged?.call(subtitleStyle);
                                },
                                onIncrease: () async {
                                  final newIndex = (subtitleStyle.styleIndex + 1)
                                      .clamp(0, SubtitleStyle.options.length - 1);
                                  await SubtitleSettingsService.instance
                                      .setStyleIndex(newIndex);
                                  setModalState(() {
                                    subtitleStyle = subtitleStyle.copyWith(
                                        styleIndex: newIndex);
                                  });
                                  onSubtitleStyleChanged?.call(subtitleStyle);
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
                                  await SubtitleSettingsService.instance
                                      .setColorIndex(newIndex);
                                  setModalState(() {
                                    subtitleStyle = subtitleStyle.copyWith(
                                        colorIndex: newIndex);
                                  });
                                  onSubtitleStyleChanged?.call(subtitleStyle);
                                },
                                onIncrease: () async {
                                  final newIndex = (subtitleStyle.colorIndex + 1)
                                      .clamp(0, SubtitleColor.options.length - 1);
                                  await SubtitleSettingsService.instance
                                      .setColorIndex(newIndex);
                                  setModalState(() {
                                    subtitleStyle = subtitleStyle.copyWith(
                                        colorIndex: newIndex);
                                  });
                                  onSubtitleStyleChanged?.call(subtitleStyle);
                                },
                              ),

                              // Background setting
                              _SubtitleStyleRow(
                                label: 'Background',
                                value: subtitleStyle.background.label,
                                onDecrease: () async {
                                  final newIndex = (subtitleStyle.bgIndex - 1)
                                      .clamp(0, SubtitleBackground.options.length - 1);
                                  await SubtitleSettingsService.instance
                                      .setBgIndex(newIndex);
                                  setModalState(() {
                                    subtitleStyle =
                                        subtitleStyle.copyWith(bgIndex: newIndex);
                                  });
                                  onSubtitleStyleChanged?.call(subtitleStyle);
                                },
                                onIncrease: () async {
                                  final newIndex = (subtitleStyle.bgIndex + 1)
                                      .clamp(0, SubtitleBackground.options.length - 1);
                                  await SubtitleSettingsService.instance
                                      .setBgIndex(newIndex);
                                  setModalState(() {
                                    subtitleStyle =
                                        subtitleStyle.copyWith(bgIndex: newIndex);
                                  });
                                  onSubtitleStyleChanged?.call(subtitleStyle);
                                },
                              ),

                              // Reset button
                              const SizedBox(height: 16),
                              Center(
                                child: TextButton.icon(
                                  onPressed: () async {
                                    await SubtitleSettingsService.instance
                                        .resetToDefaults();
                                    final newSettings =
                                        await SubtitleSettingsService.instance
                                            .loadAll();
                                    setModalState(() {
                                      subtitleStyle = newSettings;
                                    });
                                    onSubtitleStyleChanged?.call(subtitleStyle);
                                  },
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 18),
                                  label: const Text('Reset to Defaults'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                  ),
                                ),
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
