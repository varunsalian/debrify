import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../models/gesture_state.dart';
import '../services/playback_ui_clock.dart';
import 'netflix_control_button.dart';

class Controls extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Map<String, dynamic> enhancedMetadata;
  final ValueListenable<PlaybackUiClockValue> clock;
  final bool isPlaying;
  final bool isReady;
  final VoidCallback onPlayPause;
  final VoidCallback onBack;
  final VoidCallback onAspect;
  final VoidCallback onSpeed;

  /// Opens the sleep-timer picker. Its label doubles as the indicator — the
  /// only place the armed state is visible once the picker closes.
  final VoidCallback onSleepTimer;

  /// Null when no timer is armed; otherwise the short form shown on the
  /// button ("30 min", "Episode").
  final String? sleepTimerLabel;
  final double speed;
  final AspectMode aspectMode;
  final bool isLandscape;
  final VoidCallback onRotate;
  final VoidCallback onShowPlaylist;
  final VoidCallback onShowTracks;
  final bool hasPlaylist;
  final VoidCallback onSeekBarChangedStart;
  final ValueChanged<double> onSeekBarChanged;
  final VoidCallback onSeekBarChangeEnd;
  final VoidCallback? onNext;
  final VoidCallback? onNextChannel;
  final VoidCallback? onShowGuide;
  final VoidCallback? onPrevious;
  final bool hasNext;
  final bool hasNextChannel;
  final bool hasGuide;
  final bool hasPrevious;
  final bool hideSeekbar;
  final bool hideOptions;
  final bool hideBackButton;

  /// Playback speed is meaningless on a live stream — the native TV dock
  /// drops it for live channels too.
  final bool hideSpeed;

  /// Shuffle needs a playlist to pick from. IPTV sessions have none, so the
  /// button opens a menu that cannot do anything.
  final bool hideRandom;
  final VoidCallback onRandom;
  final bool hasIptvChannels;
  final VoidCallback? onShowIptvChannels;
  final bool hasStremioSources;
  final VoidCallback? onShowStremioSources;
  final bool showPipButton;
  final VoidCallback? onPip;

  /// Record control for live IPTV (libmpv `stream-record`). Shown only when a
  /// live channel is playing on a native (libmpv) backend.
  final bool hasRecord;
  final bool isRecording;
  final VoidCallback? onRecord;

  /// Optional panel glued to the top edge of the bottom bar, so the two read
  /// as one surface. Live IPTV puts its channel identity and now/next here:
  /// the dock owns this strip, so the zap banner joins it rather than
  /// fighting it for the space.
  final Widget? infoPanel;

  const Controls({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.enhancedMetadata,
    required this.clock,
    required this.isPlaying,
    required this.isReady,
    required this.onPlayPause,
    required this.onBack,
    required this.onAspect,
    required this.onSpeed,
    required this.onSleepTimer,
    this.sleepTimerLabel,
    required this.speed,
    required this.aspectMode,
    required this.isLandscape,
    required this.onRotate,
    required this.onShowPlaylist,
    required this.onShowTracks,
    required this.hasPlaylist,
    required this.onSeekBarChangedStart,
    required this.onSeekBarChanged,
    required this.onSeekBarChangeEnd,
    this.onNext,
    this.onNextChannel,
    this.onShowGuide,
    this.onPrevious,
    this.hasNext = false,
    this.hasNextChannel = false,
    this.hasGuide = false,
    this.hasPrevious = false,
    required this.hideSeekbar,
    required this.hideOptions,
    required this.hideBackButton,
    this.hideSpeed = false,
    this.hideRandom = false,
    required this.onRandom,
    this.hasIptvChannels = false,
    this.onShowIptvChannels,
    this.hasStremioSources = false,
    this.onShowStremioSources,
    this.showPipButton = false,
    this.onPip,
    this.hasRecord = false,
    this.isRecording = false,
    this.onRecord,
    this.infoPanel,
  }) : super(key: key);

  String _getAspectRatioName() {
    switch (aspectMode) {
      case AspectMode.contain:
        return 'Contain';
      case AspectMode.cover:
        return 'Cover';
      case AspectMode.fitWidth:
        return 'Fit Width';
      case AspectMode.fitHeight:
        return 'Fit Height';
      case AspectMode.aspect16_9:
        return '16:9';
      case AspectMode.aspect4_3:
        return '4:3';
      case AspectMode.aspect21_9:
        return '21:9';
      case AspectMode.aspect1_1:
        return '1:1';
      case AspectMode.aspect3_2:
        return '3:2';
      case AspectMode.aspect5_4:
        return '5:4';
    }
  }

  String _format(Duration d) {
    final sign = d.isNegative ? '-' : '';
    final abs = d.abs();
    final h = abs.inHours;
    final m = abs.inMinutes % 60;
    final s = abs.inSeconds % 60;
    if (h > 0) {
      return '$sign${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$sign${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // Simple rating badge for top-right
  Widget _buildMetadataRow(Map<String, dynamic> metadata) {
    // Only show rating
    if (metadata['rating'] == null || metadata['rating'] <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
          const SizedBox(width: 4),
          Text(
            metadata['rating'].toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Non-interactive gradient overlay
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x80000000),
                    Color(0x26000000),
                    Color(0x80000000),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Metadata overlay at the very top-right
        if (enhancedMetadata.isNotEmpty)
          Positioned(
            top: 20,
            right: 20,
            child: _buildMetadataRow(enhancedMetadata),
          ),
        // Interactive controls
        SafeArea(
          left: true,
          right: true,
          top: true,
          bottom: true,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Netflix-style Top Bar - Back button and centered title when playing
              Row(
                children: [
                  if (!hideBackButton)
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      onPressed: onBack,
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Main title
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        // Enhanced metadata row - removed from center
                      ],
                    ),
                  ),
                  // Picture-in-picture (Android phone); otherwise empty space
                  // to balance the back button when it's visible.
                  if (showPipButton && onPip != null)
                    IconButton(
                      icon: const Icon(
                        Icons.picture_in_picture_alt_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Picture in picture',
                      onPressed: onPip,
                    )
                  else if (!hideBackButton)
                    const SizedBox(width: 48),
                ],
              ),

              // The bottom unit: optional info panel glued to the top of the
              // bottom bar. Kept in one Column so they move together and
              // nothing can open a gap between them.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (infoPanel != null) infoPanel!,
                  // Netflix-style Bottom Bar with all controls (conditionally shown)
                  if (!hideOptions)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Progress bar with time indicators
                          if (!hideSeekbar)
                            ValueListenableBuilder<PlaybackUiClockValue>(
                              valueListenable: clock,
                              builder: (context, value, _) {
                                final total = value.duration.inMilliseconds <= 0
                                    ? const Duration(seconds: 1)
                                    : value.duration;
                                final progress =
                                    (value.position.inMilliseconds /
                                            total.inMilliseconds)
                                        .clamp(0.0, 1.0);
                                return Row(
                                  children: [
                                    Text(
                                      _format(value.position),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 4,
                                          activeTrackColor: const Color(
                                            0xFFE50914,
                                          ),
                                          inactiveTrackColor: Colors.white
                                              .withOpacity(0.3),
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                enabledThumbRadius: 6,
                                                elevation: 2,
                                              ),
                                          thumbColor: const Color(0xFFE50914),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                overlayRadius: 12,
                                              ),
                                        ),
                                        child: Slider(
                                          min: 0,
                                          max: 1,
                                          value: progress,
                                          onChangeStart: (_) =>
                                              onSeekBarChangedStart(),
                                          onChanged: onSeekBarChanged,
                                          onChangeEnd: (_) =>
                                              onSeekBarChangeEnd(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      _format(value.duration),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),

                          // Separates the seek row from the buttons. Dropped
                          // only when there is no seek row AND a panel above
                          // it, where it would be a band of dead space under
                          // the panel. Other seekbar-less flows (Debrify TV)
                          // keep the spacing they have always had.
                          if (!(hideSeekbar && infoPanel != null))
                            const SizedBox(height: 16),

                          // Netflix-style control buttons row - responsive layout
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                // Previous episode button
                                if (hasPrevious)
                                  NetflixControlButton(
                                    icon: Icons.skip_previous_rounded,
                                    label: 'Previous',
                                    onPressed: onPrevious!,
                                    isCompact: true,
                                  ),

                                // Play/Pause button
                                NetflixControlButton(
                                  icon: isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  label: isPlaying ? 'Pause' : 'Play',
                                  onPressed: onPlayPause,
                                  isPrimary: true,
                                  isCompact: true,
                                ),

                                // Next episode button
                                if (hasNext)
                                  NetflixControlButton(
                                    icon: Icons.skip_next_rounded,
                                    label: 'Next',
                                    onPressed: onNext!,
                                    isCompact: true,
                                  ),

                                // Next channel button
                                if (hasNextChannel && onNextChannel != null)
                                  NetflixControlButton(
                                    icon: Icons.tv_rounded,
                                    label: 'Next Channel',
                                    onPressed: onNextChannel!,
                                    isCompact: true,
                                  ),

                                // Channel guide button
                                if (hasGuide && onShowGuide != null)
                                  NetflixControlButton(
                                    icon: Icons.grid_view_rounded,
                                    label: 'Guide',
                                    onPressed: onShowGuide!,
                                    isCompact: true,
                                  ),

                                // IPTV Channels button
                                if (hasIptvChannels &&
                                    onShowIptvChannels != null)
                                  NetflixControlButton(
                                    icon: Icons.calendar_view_week_rounded,
                                    label: 'Guide',
                                    onPressed: onShowIptvChannels!,
                                    isCompact: true,
                                  ),

                                // Stremio Sources button
                                if (hasStremioSources &&
                                    onShowStremioSources != null)
                                  NetflixControlButton(
                                    icon: Icons.swap_horiz_rounded,
                                    label: 'Sources',
                                    onPressed: onShowStremioSources!,
                                    isCompact: true,
                                  ),

                                // Record button (live IPTV, libmpv backend)
                                if (hasRecord && onRecord != null)
                                  NetflixControlButton(
                                    icon: isRecording
                                        ? Icons.stop_circle_rounded
                                        : Icons.fiber_manual_record_rounded,
                                    label: isRecording ? 'Stop' : 'Record',
                                    onPressed: onRecord!,
                                    isCompact: true,
                                  ),

                                // Speed indicator and button
                                if (!hideSpeed)
                                  NetflixControlButton(
                                    icon: Icons.speed_rounded,
                                    label: '${speed}x',
                                    onPressed: onSpeed,
                                    isCompact: true,
                                  ),

                                // Sleep timer — armed state shows in the label
                                NetflixControlButton(
                                  icon: sleepTimerLabel == null
                                      ? Icons.bedtime_outlined
                                      : Icons.bedtime_rounded,
                                  label: sleepTimerLabel ?? 'Sleep',
                                  onPressed: onSleepTimer,
                                  isCompact: true,
                                ),

                                // Aspect ratio button
                                NetflixControlButton(
                                  icon: Icons.aspect_ratio_rounded,
                                  label: _getAspectRatioName(),
                                  onPressed: onAspect,
                                  isCompact: true,
                                ),

                                // Audio & subtitles button
                                NetflixControlButton(
                                  icon: Icons.subtitles_rounded,
                                  label: 'Audio & Subs',
                                  onPressed: onShowTracks,
                                  isCompact: true,
                                ),

                                // Playlist button
                                if (hasPlaylist)
                                  NetflixControlButton(
                                    icon: Icons.playlist_play_rounded,
                                    label: 'Episodes',
                                    onPressed: onShowPlaylist,
                                    isCompact: true,
                                  ),

                                // Random button
                                if (!hideRandom)
                                  NetflixControlButton(
                                    icon: Icons.shuffle_rounded,
                                    label: 'Random',
                                    onPressed: onRandom,
                                    isCompact: true,
                                  ),

                                // Orientation toggle button
                                NetflixControlButton(
                                  icon: Icons.screen_rotation_rounded,
                                  label: isLandscape ? 'Portrait' : 'Landscape',
                                  onPressed: onRotate,
                                  isCompact: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
