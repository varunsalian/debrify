import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Constants for random start percentage limits
const int randomStartPercentMin = 10;
const int randomStartPercentMax = 90;

int clampRandomStartPercent(int? value, {int defaultValue = 20}) {
  final candidate = value ?? defaultValue;
  if (candidate < randomStartPercentMin) {
    return randomStartPercentMin;
  }
  if (candidate > randomStartPercentMax) {
    return randomStartPercentMax;
  }
  return candidate;
}

/// A slider widget for adjusting the random start percentage.
///
/// Supports Android TV focus navigation with D-pad controls.
class RandomStartSlider extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onChangeEnd;
  final bool isAndroidTv;

  const RandomStartSlider({
    super.key,
    required this.value,
    required this.isAndroidTv,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  State<RandomStartSlider> createState() => _RandomStartSliderState();
}

class _RandomStartSliderState extends State<RandomStartSlider> {
  FocusNode? _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    if (widget.isAndroidTv) {
      _focusNode = FocusNode(
        debugLabel: 'RandomStartSlider',
        onKeyEvent: _handleKeyEvent,
      );
      _focusNode!.addListener(_handleFocusChange);
    }
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode?.hasFocus ?? false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant RandomStartSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAndroidTv && _focusNode == null) {
      _focusNode = FocusNode(
        debugLabel: 'RandomStartSlider',
        onKeyEvent: _handleKeyEvent,
      );
      _focusNode!.addListener(_handleFocusChange);
    } else if (!widget.isAndroidTv && _focusNode != null) {
      _focusNode!.removeListener(_handleFocusChange);
      _focusNode!.dispose();
      _focusNode = null;
    }
  }

  @override
  void dispose() {
    _focusNode?.removeListener(_handleFocusChange);
    _focusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: Colors.white70,
      fontWeight: FontWeight.w600,
    );
    final helperStyle = theme.textTheme.bodySmall?.copyWith(
      color: Colors.white60,
    );
    final divisions = (randomStartPercentMax - randomStartPercentMin) ~/ 5;

    Widget sliderColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Random start within first ${widget.value}%', style: textStyle),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackShape: const RoundedRectSliderTrackShape(),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Slider(
            value: widget.value.toDouble(),
            focusNode: widget.isAndroidTv ? _focusNode : null,
            min: randomStartPercentMin.toDouble(),
            max: randomStartPercentMax.toDouble(),
            divisions: divisions == 0 ? null : divisions,
            label: '${widget.value}%',
            onChanged: (raw) {
              final next = clampRandomStartPercent(raw.round());
              widget.onChanged(next);
            },
            onChangeEnd: widget.onChangeEnd == null
                ? null
                : (raw) => widget.onChangeEnd!(
                    clampRandomStartPercent(raw.round()),
                  ),
          ),
        ),
        Text(
          'Videos will jump to a random moment inside the first ${widget.value}% of playback.',
          style: helperStyle,
        ),
      ],
    );

    // Wrap in focus indicator container for TV
    if (widget.isAndroidTv) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _isFocused ? const Color(0xFF2A2A2A) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isFocused ? Colors.white : Colors.white12,
            width: _isFocused ? 2 : 1,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.15),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: sliderColumn,
      );
    }

    return sliderColumn;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (node.context != null) {
        FocusScope.of(node.context!).nextFocus();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (node.context != null) {
        FocusScope.of(node.context!).previousFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }
}
