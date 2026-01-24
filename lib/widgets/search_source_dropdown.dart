import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/stremio_addon.dart';
import '../services/stremio_service.dart';

/// Represents a search source type
enum SearchSourceType {
  all,      // Search across all sources
  keyword,  // Keyword/torrent search
  addon,    // Specific addon catalog
  reddit,   // Reddit video search
}

/// Represents a selectable search source option
class SearchSourceOption {
  final SearchSourceType type;
  final StremioAddon? addon;  // Only set for addon-specific options
  final String label;
  final IconData icon;

  const SearchSourceOption({
    required this.type,
    this.addon,
    required this.label,
    required this.icon,
  });

  /// Create "All" option
  factory SearchSourceOption.all() => const SearchSourceOption(
    type: SearchSourceType.all,
    label: 'All',
    icon: Icons.apps,
  );

  /// Create "Keyword" option
  factory SearchSourceOption.keyword() => const SearchSourceOption(
    type: SearchSourceType.keyword,
    label: 'Keyword',
    icon: Icons.search,
  );

  /// Create "Reddit" option
  factory SearchSourceOption.reddit() => const SearchSourceOption(
    type: SearchSourceType.reddit,
    label: 'Reddit',
    icon: Icons.play_circle_outline,
  );

  /// Create addon-specific option
  factory SearchSourceOption.fromAddon(StremioAddon addon) => SearchSourceOption(
    type: SearchSourceType.addon,
    addon: addon,
    label: addon.name,
    icon: Icons.extension,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchSourceOption &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          addon?.manifestUrl == other.addon?.manifestUrl;

  @override
  int get hashCode => type.hashCode ^ (addon?.manifestUrl.hashCode ?? 0);
}

/// A TV-optimized dropdown for selecting search source
///
/// Supports:
/// - Touch interactions (mobile)
/// - Mouse click (desktop)
/// - D-pad navigation (Android TV)
class SearchSourceDropdown extends StatefulWidget {
  final SearchSourceOption selectedOption;
  final List<SearchSourceOption> options;
  final ValueChanged<SearchSourceOption> onChanged;
  final FocusNode? focusNode;
  final bool isTelevision;
  /// Callback when left arrow is pressed (for DPAD navigation back to search bar)
  final VoidCallback? onLeftArrowPressed;

  const SearchSourceDropdown({
    super.key,
    required this.selectedOption,
    required this.options,
    required this.onChanged,
    this.focusNode,
    this.isTelevision = false,
    this.onLeftArrowPressed,
  });

  @override
  State<SearchSourceDropdown> createState() => _SearchSourceDropdownState();
}

class _SearchSourceDropdownState extends State<SearchSourceDropdown> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isExpanded = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _removeOverlay();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
    // Don't auto-close dropdown when focus changes on TV
    // The dropdown will close when an item is selected or escape is pressed
    // This prevents the dropdown from closing immediately when focus
    // transfers to the dropdown menu items
  }

  void _toggleDropdown() {
    if (_isExpanded) {
      _removeOverlay();
      setState(() => _isExpanded = false);
    } else {
      _showOverlay();
      setState(() => _isExpanded = true);
    }
  }

  void _showOverlay() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    // Minimum width for dropdown to prevent text wrapping
    const double minDropdownWidth = 220;
    final dropdownWidth = size.width < minDropdownWidth ? minDropdownWidth : size.width;
    // Offset to align right edge if dropdown is wider than trigger
    final horizontalOffset = size.width - dropdownWidth;

    return OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Fullscreen barrier to detect taps outside (for touch/mouse)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _removeOverlay();
                setState(() => _isExpanded = false);
                _focusNode.requestFocus();
              },
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          // The actual dropdown menu
          Positioned(
            width: dropdownWidth,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(horizontalOffset, size.height + 4),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: _DropdownMenu(
                  options: widget.options,
                  selectedOption: widget.selectedOption,
                  isTelevision: widget.isTelevision,
                  onSelected: (option) {
                    _removeOverlay();
                    setState(() => _isExpanded = false);
                    widget.onChanged(option);
                    _focusNode.requestFocus();
                  },
                  onClose: () {
                    _removeOverlay();
                    setState(() => _isExpanded = false);
                    _focusNode.requestFocus();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Select/Enter opens dropdown or selects if expanded
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        _toggleDropdown();
        return KeyEventResult.handled;
      }
      // Escape closes dropdown
      if (event.logicalKey == LogicalKeyboardKey.escape && _isExpanded) {
        _removeOverlay();
        setState(() => _isExpanded = false);
        return KeyEventResult.handled;
      }
      // Left arrow: go back to search bar (clear button or text field)
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft && !_isExpanded) {
        if (widget.onLeftArrowPressed != null) {
          widget.onLeftArrowPressed!();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          onTap: _toggleDropdown,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isFocused
                    ? colorScheme.primary
                    : colorScheme.outline.withOpacity(0.3),
                width: _isFocused ? 2 : 1,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.selectedOption.icon,
                  size: 18,
                  color: colorScheme.onSurface,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.selectedOption.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dropdown menu overlay
class _DropdownMenu extends StatefulWidget {
  final List<SearchSourceOption> options;
  final SearchSourceOption selectedOption;
  final bool isTelevision;
  final ValueChanged<SearchSourceOption> onSelected;
  final VoidCallback onClose;

  const _DropdownMenu({
    required this.options,
    required this.selectedOption,
    required this.isTelevision,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<_DropdownMenu> createState() => _DropdownMenuState();
}

class _DropdownMenuState extends State<_DropdownMenu> {
  late List<FocusNode> _itemFocusNodes;
  int _focusedIndex = -1;

  @override
  void initState() {
    super.initState();
    _itemFocusNodes = List.generate(
      widget.options.length,
      (i) => FocusNode(),
    );
    // Auto-focus the selected item on TV
    if (widget.isTelevision) {
      final selectedIndex = widget.options.indexOf(widget.selectedOption);
      if (selectedIndex >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _itemFocusNodes[selectedIndex].requestFocus();
        });
      }
    }
  }

  @override
  void dispose() {
    for (final node in _itemFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleItemKeyEvent(FocusNode node, KeyEvent event, int index) {
    if (event is KeyDownEvent) {
      // Select/Enter picks the option
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        widget.onSelected(widget.options[index]);
        return KeyEventResult.handled;
      }
      // Escape closes menu
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onClose();
        return KeyEventResult.handled;
      }
      // Arrow navigation
      if (event.logicalKey == LogicalKeyboardKey.arrowUp && index > 0) {
        _itemFocusNodes[index - 1].requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
          index < widget.options.length - 1) {
        _itemFocusNodes[index + 1].requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: widget.options.length,
          itemBuilder: (context, index) {
            final option = widget.options[index];
            final isSelected = option == widget.selectedOption;

            return Focus(
              focusNode: _itemFocusNodes[index],
              onFocusChange: (focused) {
                setState(() {
                  _focusedIndex = focused ? index : -1;
                });
              },
              onKeyEvent: (node, event) => _handleItemKeyEvent(node, event, index),
              child: InkWell(
                onTap: () => widget.onSelected(option),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _focusedIndex == index
                        ? colorScheme.primary.withOpacity(0.2)
                        : isSelected
                            ? colorScheme.primaryContainer.withOpacity(0.5)
                            : null,
                    border: _focusedIndex == index
                        ? Border.all(color: colorScheme.primary, width: 2)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        option.icon,
                        size: 20,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            if (option.type == SearchSourceType.addon &&
                                option.addon != null)
                              Text(
                                option.addon!.supportsCatalogs
                                    ? '${option.addon!.catalogs.length} catalog${option.addon!.catalogs.length != 1 ? 's' : ''}'
                                    : 'Search only',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Helper class to load and manage search source options
class SearchSourceOptionsLoader {
  final StremioService _stremioService = StremioService.instance;

  /// Load all available search source options
  /// Includes addons with catalogs OR search capability
  Future<List<SearchSourceOption>> loadOptions() async {
    final options = <SearchSourceOption>[
      SearchSourceOption.all(),
      SearchSourceOption.keyword(),
    ];

    try {
      final addons = await _stremioService.getBrowseableOrSearchableAddons();
      for (final addon in addons) {
        options.add(SearchSourceOption.fromAddon(addon));
      }
    } catch (e) {
      debugPrint('SearchSourceOptionsLoader: Error loading addons: $e');
    }

    // Reddit always goes last
    options.add(SearchSourceOption.reddit());

    return options;
  }
}
