import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import '../constants/color_constants.dart';
import '../widgets/netflix_radio_tile.dart';
import '../utils/language_mapping.dart';

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
  static Future<void> show(
    BuildContext context,
    mk.Player player, {
    required Future<void> Function(String audioId, String subtitleId) onTrackChanged,
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
