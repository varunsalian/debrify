import 'dart:async';
import 'package:flutter/material.dart';
import '../services/subtitle_cue_parser.dart';
import '../services/subtitle_settings_service.dart';
import '../constants/color_constants.dart';

class SubtitleLinePickerOverlay extends StatefulWidget {
  final String subtitleFilePath;
  final int Function() getCurrentPositionMs;
  final int currentOffsetMs;
  final ValueChanged<int> onOffsetChanged;
  final VoidCallback onDismiss;

  const SubtitleLinePickerOverlay({
    super.key,
    required this.subtitleFilePath,
    required this.getCurrentPositionMs,
    required this.currentOffsetMs,
    required this.onOffsetChanged,
    required this.onDismiss,
  });

  @override
  State<SubtitleLinePickerOverlay> createState() =>
      _SubtitleLinePickerOverlayState();
}

class _SubtitleLinePickerOverlayState extends State<SubtitleLinePickerOverlay> {
  List<SubtitleCue>? _cues;
  bool _loading = true;
  int _highlightedIndex = -1;
  final ScrollController _scrollController = ScrollController();
  Timer? _positionTimer;
  late int _appliedOffsetMs;
  bool _showManualSlider = false;

  static const _itemHeight = 62.0;

  @override
  void initState() {
    super.initState();
    _appliedOffsetMs = widget.currentOffsetMs;
    _loadCues();
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCues() async {
    final cues = await SubtitleCueParser.parseFile(widget.subtitleFilePath);
    if (!mounted) return;
    setState(() {
      _cues = cues;
      _loading = false;
    });
    if (cues.isNotEmpty) {
      _updateHighlight();
      _startPositionTracking();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_highlightedIndex >= 0) _scrollToIndex(_highlightedIndex);
      });
    }
  }

  void _startPositionTracking() {
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateHighlight();
    });
  }

  void _updateHighlight() {
    final cues = _cues;
    if (cues == null || cues.isEmpty) return;
    final posMs = widget.getCurrentPositionMs();

    int best = -1;
    for (int i = 0; i < cues.length; i++) {
      if (cues[i].startMs <= posMs - _appliedOffsetMs) {
        best = i;
      } else {
        break;
      }
    }

    if (best != _highlightedIndex && mounted) {
      setState(() => _highlightedIndex = best);
    }
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    final target = (index * _itemHeight) -
        (_scrollController.position.viewportDimension / 2) +
        (_itemHeight / 2);
    _scrollController.animateTo(
      target.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _onCueTapped(int index) {
    final cue = _cues![index];
    final posMs = widget.getCurrentPositionMs();
    final newOffset = posMs - cue.startMs;
    final clamped = newOffset.clamp(
      SubtitleSettingsService.syncOffsetMinMs,
      SubtitleSettingsService.syncOffsetMaxMs,
    );
    setState(() => _appliedOffsetMs = clamped);
    widget.onOffsetChanged(clamped);
  }

  void _onSliderChanged(int ms) {
    final clamped = ms.clamp(
      SubtitleSettingsService.syncOffsetMinMs,
      SubtitleSettingsService.syncOffsetMaxMs,
    );
    setState(() => _appliedOffsetMs = clamped);
    widget.onOffsetChanged(clamped);
  }

  void _resetOffset() {
    setState(() => _appliedOffsetMs = 0);
    widget.onOffsetChanged(0);
  }

  String _formatTime(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatOffset(int ms) {
    final sign = ms >= 0 ? '+' : '';
    final seconds = ms / 1000.0;
    return '$sign${seconds.toStringAsFixed(1)}s';
  }

  Color _offsetColor(int ms) {
    final abs = ms.abs();
    if (abs == 0) return const Color(0xFF4CAF50);
    if (abs <= 500) return const Color(0xFFCDDC39);
    if (abs <= 2000) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () {},
        child: Container(
          color: const Color(0xE6000000),
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                if (_loading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: VideoPlayerColors.netflixRed,
                      ),
                    ),
                  )
                else if (_cues == null || _cues!.isEmpty)
                  Expanded(child: _buildEmptyState())
                else
                  Expanded(child: _buildCueList()),
                if (_showManualSlider) _buildSlider(),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final accent = _offsetColor(_appliedOffsetMs);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.subtitles_rounded, color: Colors.white54, size: 20),
          const SizedBox(width: 10),
          Text(
            'SUBTITLE SYNC',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Text(
              _formatOffset(_appliedOffsetMs),
              style: TextStyle(
                color: accent,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          _headerButton(
            icon: Icons.tune_rounded,
            label: _showManualSlider ? 'Hide Slider' : 'Slider',
            onTap: () => setState(() => _showManualSlider = !_showManualSlider),
          ),
          const SizedBox(width: 6),
          _headerButton(
            icon: Icons.restart_alt_rounded,
            label: 'Reset',
            onTap: _resetOffset,
          ),
          const SizedBox(width: 6),
          _headerButton(
            icon: Icons.close_rounded,
            label: 'Done',
            onTap: widget.onDismiss,
            accent: true,
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: accent
              ? VideoPlayerColors.netflixRed.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accent ? VideoPlayerColors.netflixRed : Colors.white60),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: accent ? VideoPlayerColors.netflixRed : Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.subtitles_off_rounded,
              size: 48, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            'Could not parse subtitle lines',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the slider to adjust manually',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCueList() {
    final cues = _cues!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Row(
            children: [
              Text(
                'Tap the line you just heard',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (_highlightedIndex >= 0)
                GestureDetector(
                  onTap: () => _scrollToIndex(_highlightedIndex),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: VideoPlayerColors.netflixRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.my_location_rounded,
                            size: 12, color: VideoPlayerColors.netflixRed),
                        const SizedBox(width: 4),
                        Text(
                          'Now',
                          style: TextStyle(
                            color: VideoPlayerColors.netflixRed,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                '${cues.length} lines',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: cues.length,
            itemExtent: _itemHeight,
            itemBuilder: (context, index) {
              final cue = cues[index];
              final isCurrent = index == _highlightedIndex;
              final isPast = index < _highlightedIndex;

              return GestureDetector(
                onTap: () => _onCueTapped(index),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? VideoPlayerColors.netflixRed.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: isCurrent
                        ? Border.all(
                            color: VideoPlayerColors.netflixRed.withValues(alpha: 0.4),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 58,
                        child: Text(
                          _formatTime(cue.startMs),
                          style: TextStyle(
                            color: isCurrent
                                ? VideoPlayerColors.netflixRed
                                : Colors.white.withValues(alpha: isPast ? 0.35 : 0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (isCurrent) ...[
                        Container(
                          width: 3,
                          height: 28,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: VideoPlayerColors.netflixRed,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ] else
                        const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          cue.text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent
                                ? Colors.white
                                : Colors.white.withValues(alpha: isPast ? 0.35 : 0.7),
                            fontSize: 13,
                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSlider() {
    final accent = _offsetColor(_appliedOffsetMs);
    const minMs = SubtitleSettingsService.syncOffsetMinMs;
    const maxMs = SubtitleSettingsService.syncOffsetMaxMs;
    const step = SubtitleSettingsService.syncOffsetStepMs;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _onSliderChanged(_appliedOffsetMs - step),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.remove_rounded, color: Colors.white60, size: 18),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: accent,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                thumbColor: Colors.white,
                overlayColor: accent.withValues(alpha: 0.2),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: _appliedOffsetMs.toDouble(),
                min: minMs.toDouble(),
                max: maxMs.toDouble(),
                divisions: (maxMs - minMs) ~/ step,
                onChanged: (v) => _onSliderChanged(v.round()),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _onSliderChanged(_appliedOffsetMs + step),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white60, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.touch_app_rounded,
              size: 13, color: Colors.white.withValues(alpha: 0.25)),
          const SizedBox(width: 6),
          Text(
            'Tap a line to sync subtitles to that point',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
