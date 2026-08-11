import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'tv_tappable.dart';
import '../../../utils/platform_util.dart';
import '../services/subtitle_cue_parser.dart';
import '../services/subtitle_settings_service.dart';

/// Sync line picker for addon/external subtitles — pause on a line you can
/// hear, pick the matching cue, and the offset is computed from it.
///
/// Spotlight grammar: a right-side glass panel (same shape as the player
/// menu) instead of a full-screen sheet, so the picture — the thing being
/// synced against — stays visible. The playing cue carries a white marker
/// bar; TvTappable rows keep the DPAD traversal that already worked here.
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
  static const _ink = Colors.white;
  static const _glass = Color(0xFF101012);

  List<SubtitleCue>? _cues;
  bool _loading = true;
  int _highlightedIndex = -1;
  final ScrollController _scrollController = ScrollController();
  Timer? _positionTimer;
  late int _appliedOffsetMs;
  bool _showManualStepper = false;

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

  void _stepOffset(int deltaMs) {
    final clamped = (_appliedOffsetMs + deltaMs).clamp(
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
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatOffset(int ms) {
    if (ms == 0) return 'In sync';
    final sign = ms > 0 ? '+' : '−';
    return '$sign${(ms.abs() / 1000.0).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 720;
    final panelWidth = compact
        ? size.width
        : (size.width * 0.46).clamp(430.0, 560.0);

    return Positioned.fill(
      child: Stack(
        children: [
          // Scrim: the picture dims but stays visible. Tap keeps & closes.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.20),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: panelWidth,
              height: double.infinity,
              child: _buildGlass(
                child: SafeArea(
                  left: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      if (_loading)
                        Expanded(
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _ink.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        )
                      else if (_cues == null || _cues!.isEmpty)
                        Expanded(child: _buildEmptyState())
                      else
                        Expanded(child: _buildCueList()),
                      if (_showManualStepper) _buildStepperRow(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlass({required Widget child}) {
    final content = Container(
      decoration: BoxDecoration(
        color: PlatformUtil.isAndroidTvCached
            ? const Color(0xF5101012)
            : _glass.withValues(alpha: 0.72),
        border: Border(
          left: BorderSide(color: _ink.withValues(alpha: 0.14), width: 0.75),
        ),
      ),
      child: child,
    );
    if (PlatformUtil.isAndroidTvCached) return content;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: content,
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'WHICH LINE IS BEING SPOKEN?',
                style: TextStyle(
                  color: _ink.withValues(alpha: 0.42),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.8,
                ),
              ),
              const Spacer(),
              Text(
                _formatOffset(_appliedOffsetMs),
                style: TextStyle(
                  color: _appliedOffsetMs == 0
                      ? _ink.withValues(alpha: 0.45)
                      : _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _headerButton(
                autofocus: true,
                label: _showManualStepper ? 'Hide stepper' : 'Stepper',
                onTap: () =>
                    setState(() => _showManualStepper = !_showManualStepper),
              ),
              const SizedBox(width: 6),
              _headerButton(label: 'Reset', onTap: _resetOffset),
              const SizedBox(width: 6),
              if (_highlightedIndex >= 0)
                _headerButton(
                  label: 'Now',
                  onTap: () => _scrollToIndex(_highlightedIndex),
                ),
              const Spacer(),
              _headerButton(label: 'Done', onTap: widget.onDismiss, solid: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required String label,
    required VoidCallback onTap,
    bool solid = false,
    bool autofocus = false,
  }) {
    return TvTappable(
      autofocus: autofocus,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: solid ? _ink : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: _ink.withValues(alpha: solid ? 1 : 0.30),
            width: 0.75,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: solid ? Colors.black : _ink.withValues(alpha: 0.80),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.subtitles_off_rounded,
            size: 40,
            color: _ink.withValues(alpha: 0.20),
          ),
          const SizedBox(height: 12),
          Text(
            'Could not parse subtitle lines',
            style: TextStyle(
              color: _ink.withValues(alpha: 0.45),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Use the stepper to adjust manually',
            style: TextStyle(
              color: _ink.withValues(alpha: 0.30),
              fontSize: 11.5,
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
          padding: const EdgeInsets.fromLTRB(24, 2, 24, 6),
          child: Row(
            children: [
              Text(
                'Pick the line you just heard',
                style: TextStyle(
                  color: _ink.withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                '${cues.length} lines',
                style: TextStyle(
                  color: _ink.withValues(alpha: 0.30),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: cues.length,
            itemExtent: _itemHeight,
            itemBuilder: (context, index) {
              final cue = cues[index];
              final isCurrent = index == _highlightedIndex;
              final isPast = index < _highlightedIndex;

              return TvTappable(
                onTap: () => _onCueTapped(index),
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? _ink.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      // Playing-position marker: a white bar, not a color.
                      Container(
                        width: 2.5,
                        height: 30,
                        margin: const EdgeInsets.only(right: 11),
                        decoration: BoxDecoration(
                          color: isCurrent ? _ink : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _formatTime(cue.startMs),
                              style: TextStyle(
                                color: _ink.withValues(
                                  alpha: isCurrent
                                      ? 0.55
                                      : isPast
                                      ? 0.28
                                      : 0.40,
                                ),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.6,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              cue.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _ink.withValues(
                                  alpha: isCurrent
                                      ? 1
                                      : isPast
                                      ? 0.35
                                      : 0.72,
                                ),
                                fontSize: 13,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                height: 1.25,
                              ),
                            ),
                          ],
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

  /// Manual fallback for when no line matches (or nothing parses): the same
  /// stepper grammar as the embedded-subtitle overlay, no Material slider.
  Widget _buildStepperRow() {
    const step = SubtitleSettingsService.syncOffsetStepMs;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _ink.withValues(alpha: 0.09), width: 0.75),
        ),
      ),
      child: Row(
        children: [
          _stepButton(Icons.remove_rounded, () => _stepOffset(-step * 5)),
          const SizedBox(width: 6),
          _stepButton(Icons.chevron_left_rounded, () => _stepOffset(-step)),
          Expanded(
            child: Text(
              _formatOffset(_appliedOffsetMs),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _stepButton(Icons.chevron_right_rounded, () => _stepOffset(step)),
          const SizedBox(width: 6),
          _stepButton(Icons.add_rounded, () => _stepOffset(step * 5)),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback onTap) {
    return TvTappable(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _ink.withValues(alpha: 0.30), width: 0.75),
        ),
        child: Icon(icon, color: _ink.withValues(alpha: 0.85), size: 17),
      ),
    );
  }
}
