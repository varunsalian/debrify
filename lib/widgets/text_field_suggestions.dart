import 'package:flutter/material.dart';

/// Presentation-only choices supplied by a field's owner. Keeping the action
/// with its stable identity avoids selecting a different item after a refresh.
class TextFieldSuggestion {
  const TextFieldSuggestion({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.onSelected,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final VoidCallback onSelected;
}

/// The editor retains focus, including on TV. Remote/arrow navigation supplies
/// [selectedIndex]; pointer selection never wakes or dismisses the editor IME
/// until the owning field handles the selected choice.
class TextFieldSuggestions extends StatefulWidget {
  const TextFieldSuggestions({
    super.key,
    required this.items,
    required this.onSelected,
    this.selectedIndex = -1,
    this.maxHeight = 280,
    this.label = 'Suggestions',
    this.hint,
    this.accent,
    this.ink,
  });

  final List<TextFieldSuggestion> items;
  final ValueChanged<TextFieldSuggestion> onSelected;
  final int selectedIndex;
  final double maxHeight;
  final String label;
  final String? hint;
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
          Scrollable.ensureVisible(selected, alignment: 0.5);
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
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Text(
                [
                  widget.label,
                  if (widget.hint != null) widget.hint!,
                ].join(' · '),
                style: TextStyle(
                  fontSize: 11,
                  color: ink.withValues(alpha: 0.7),
                ),
              ),
            ),
            for (var i = 0; i < widget.items.length; i++)
              _row(widget.items[i], i == widget.selectedIndex, ink, accent),
          ],
        ),
      ),
    );
  }

  Widget _row(
    TextFieldSuggestion item,
    bool selected,
    Color ink,
    Color accent,
  ) {
    final placeholder = Icon(
      Icons.movie_outlined,
      color: ink.withValues(alpha: 0.5),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        key: selected ? _selected : ValueKey('suggestion-${item.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSelected(item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.18) : null,
            border: Border(
              left: BorderSide(
                color: selected ? accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 32,
                  height: 48,
                  child: item.imageUrl == null
                      ? placeholder
                      : Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          cacheWidth: 96,
                          errorBuilder: (_, __, ___) => placeholder,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        color: ink.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
