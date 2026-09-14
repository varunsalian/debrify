import 'package:flutter/material.dart';

/// Presentation-only choices supplied by a field's owner. Keeping the action
/// with its stable identity avoids selecting a different item after a refresh.
class TextFieldSuggestion {
  const TextFieldSuggestion({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.onSelected,
    this.year,
  });

  final String id;
  final String title;
  final String subtitle;
  final String? year;
  final VoidCallback onSelected;

  String get displayText => year?.isNotEmpty == true ? '$title ($year)' : title;
}

/// A compact, horizontally scrolling prediction strip above the keyboard.
/// The editor retains focus, including on TV. Remote/arrow navigation supplies
/// [selectedIndex]; pointer selection never wakes or dismisses the editor IME
/// until the owning field handles the selected choice.
class TextFieldSuggestions extends StatefulWidget {
  const TextFieldSuggestions({
    super.key,
    required this.items,
    required this.onSelected,
    this.selectedIndex = -1,
    this.label = 'Suggestions',
    this.accent,
    this.ink,
  });

  final List<TextFieldSuggestion> items;
  final ValueChanged<TextFieldSuggestion> onSelected;
  final int selectedIndex;
  final String label;
  final Color? accent;
  final Color? ink;

  @override
  State<TextFieldSuggestions> createState() => _TextFieldSuggestionsState();
}

class _TextFieldSuggestionsState extends State<TextFieldSuggestions> {
  final _scroll = ScrollController();
  final _selected = GlobalKey();

  @override
  void didUpdateWidget(TextFieldSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final selected = _selected.currentContext;
        if (mounted && selected != null) {
          // Align long titles at the start instead of clipping both ends.
          Scrollable.ensureVisible(selected);
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = widget.ink ?? scheme.onSurface;
    final accent = widget.accent ?? scheme.primary;
    return Semantics(
      container: true,
      label: widget.label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.items.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    right: i < widget.items.length - 1 ? 8 : 0,
                  ),
                  child: _choice(
                    widget.items[i],
                    i == widget.selectedIndex,
                    ink,
                    accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice(
    TextFieldSuggestion item,
    bool selected,
    Color ink,
    Color accent,
  ) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${item.title}, ${item.subtitle}',
      excludeSemantics: true,
      onTap: () => widget.onSelected(item),
      child: GestureDetector(
        key: selected ? _selected : ValueKey('suggestion-${item.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelected(item),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.22)
                : ink.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: selected ? accent : Colors.transparent),
          ),
          child: Text(
            item.displayText,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: ink,
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
