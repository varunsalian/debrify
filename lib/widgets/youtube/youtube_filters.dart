import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/tv_keys.dart';

/// Selectable max playback resolutions for YouTube (pixel height).
const List<int> kYoutubeQualities = [1080, 720, 480, 360];

String youtubeQualityLabel(int height) => '${height}p';

/// Filter bar for the YouTube source: a quality (resolution) selector plus an
/// optional result count / download hint.
class YoutubeFiltersBar extends StatelessWidget {
  final int selectedHeight;
  final int resultCount;
  final bool isTelevision;
  final ValueChanged<int> onQualityChanged;
  final FocusNode? qualityFocusNode;

  const YoutubeFiltersBar({
    super.key,
    required this.selectedHeight,
    required this.resultCount,
    required this.isTelevision,
    required this.onQualityChanged,
    this.qualityFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _QualityDropdown(
              selectedHeight: selectedHeight,
              onChanged: onQualityChanged,
              focusNode: qualityFocusNode,
            ),
            const SizedBox(width: 12),
            if (resultCount > 0)
              Text(
                '$resultCount video${resultCount != 1 ? 's' : ''}'
                '${isTelevision ? '' : ' • long press to download'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Quality selection dropdown - TV-friendly (opens a focusable bottom sheet).
class _QualityDropdown extends StatefulWidget {
  final int selectedHeight;
  final ValueChanged<int> onChanged;
  final FocusNode? focusNode;

  const _QualityDropdown({
    required this.selectedHeight,
    required this.onChanged,
    this.focusNode,
  });

  @override
  State<_QualityDropdown> createState() => _QualityDropdownState();
}

class _QualityDropdownState extends State<_QualityDropdown> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _isFocused = widget.focusNode?.hasFocus ?? false);
  }

  Future<void> _showPicker() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => _QualityPickerSheet(current: widget.selectedHeight),
    );
    if (result != null) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          _showPicker();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _showPicker,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isFocused
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.3),
              width: _isFocused ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.high_quality_outlined,
                  size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                youtubeQualityLabel(widget.selectedHeight),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down,
                  size: 20, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for selecting a quality with DPAD support.
class _QualityPickerSheet extends StatefulWidget {
  final int current;

  const _QualityPickerSheet({required this.current});

  @override
  State<_QualityPickerSheet> createState() => _QualityPickerSheetState();
}

class _QualityPickerSheetState extends State<_QualityPickerSheet> {
  final List<FocusNode> _focusNodes = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < kYoutubeQualities.length; i++) {
      _focusNodes.add(FocusNode(debugLabel: 'youtube-quality-$i'));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusNodes.isEmpty) return;
      final idx = kYoutubeQualities.indexOf(widget.current);
      _focusNodes[idx >= 0 ? idx : 0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event, int index, int height) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (isActivateKey(event.logicalKey)) {
      Navigator.of(context).pop(height);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.browserBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && index > 0) {
      _focusNodes[index - 1].requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        index < _focusNodes.length - 1) {
      _focusNodes[index + 1].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: FocusScope(
        autofocus: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Max Quality',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...kYoutubeQualities.asMap().entries.map((entry) {
              final index = entry.key;
              final height = entry.value;
              final isSelected = height == widget.current;
              return _FocusableQualityTile(
                focusNode: _focusNodes[index],
                label: youtubeQualityLabel(height),
                isSelected: isSelected,
                onTap: () => Navigator.of(context).pop(height),
                onKeyEvent: (node, event) =>
                    _handleKeyEvent(node, event, index, height),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Focusable quality tile for DPAD navigation.
class _FocusableQualityTile extends StatefulWidget {
  final FocusNode focusNode;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  const _FocusableQualityTile({
    required this.focusNode,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.onKeyEvent,
  });

  @override
  State<_FocusableQualityTile> createState() => _FocusableQualityTileState();
}

class _FocusableQualityTileState extends State<_FocusableQualityTile> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _isFocused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: widget.onKeyEvent,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            color: _isFocused
                ? colorScheme.primaryContainer
                : (widget.isSelected ? colorScheme.surfaceContainerHighest : null),
            borderRadius: BorderRadius.circular(8),
            border: _isFocused
                ? Border.all(color: colorScheme.primary, width: 2)
                : null,
          ),
          child: ListTile(
            leading: Icon(
              widget.isSelected ? Icons.check_circle : Icons.high_quality_outlined,
              color: _isFocused
                  ? colorScheme.onPrimaryContainer
                  : (widget.isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
            ),
            title: Text(
              widget.label,
              style: TextStyle(
                fontWeight: widget.isSelected || _isFocused
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: _isFocused
                    ? colorScheme.onPrimaryContainer
                    : (widget.isSelected ? colorScheme.primary : colorScheme.onSurface),
              ),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }
}
