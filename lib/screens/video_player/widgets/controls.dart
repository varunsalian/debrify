import 'package:flutter/material.dart';
import '../models/gesture_state.dart';
import 'netflix_control_button.dart';

class Controls extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Map<String, dynamic> enhancedMetadata;
  final Duration duration;
  final Duration position;
  final bool isPlaying;
  final bool isReady;
  final VoidCallback onPlayPause;
  final VoidCallback onBack;
  final VoidCallback onAspect;
  final VoidCallback onSpeed;
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
  final VoidCallback onRandom;
  final bool hasIptvChannels;
  final VoidCallback? onShowIptvChannels;

  const Controls({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.enhancedMetadata,
    required this.duration,
    required this.position,
    required this.isPlaying,
    required this.isReady,
    required this.onPlayPause,
    required this.onBack,
    required this.onAspect,
    required this.onSpeed,
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
    required this.onRandom,
    this.hasIptvChannels = false,
    this.onShowIptvChannels,
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
    final total = duration.inMilliseconds <= 0
        ? const Duration(seconds: 1)
        : duration;
    final progress = (position.inMilliseconds / total.inMilliseconds).clamp(
      0.0,
      1.0,
    );

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
                  // Empty space to balance the back button (when visible)
                  if (!hideBackButton) const SizedBox(width: 48),
                ],
              ),

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
                      Row(
                        children: [
                          if (!hideSeekbar) ...[
                            Text(
                              _format(position),
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
                                  activeTrackColor: const Color(0xFFE50914),
                                  inactiveTrackColor: Colors.white.withOpacity(
                                    0.3,
                                  ),
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                    elevation: 2,
                                  ),
                                  thumbColor: const Color(0xFFE50914),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                ),
                                child: Slider(
                                  min: 0,
                                  max: 1,
                                  value:
                                      (position.inMilliseconds /
                                              (total.inMilliseconds == 0
                                                  ? 1
                                                  : total.inMilliseconds))
                                          .clamp(0.0, 1.0),
                                  onChangeStart: (_) => onSeekBarChangedStart(),
                                  onChanged: (v) => onSeekBarChanged(v),
                                  onChangeEnd: (_) => onSeekBarChangeEnd(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _format(duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ] else ...[
                            const SizedBox.shrink(),
                          ],
                        ],
                      ),

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
                            if (hasIptvChannels && onShowIptvChannels != null)
                              NetflixControlButton(
                                icon: Icons.live_tv_rounded,
                                label: 'Channels',
                                onPressed: onShowIptvChannels!,
                                isCompact: true,
                              ),

                            // Speed indicator and button
                            NetflixControlButton(
                              icon: Icons.speed_rounded,
                              label: '${speed}x',
                              onPressed: onSpeed,
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
        ),
      ],
    );
  }
}
