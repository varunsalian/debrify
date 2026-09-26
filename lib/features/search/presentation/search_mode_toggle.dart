import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme_scope.dart';
import '../../../utils/tv_keys.dart';
import '../../../widgets/see_all/stremio_dropdown.dart';
import '../models/search_mode.dart';

class SearchModeToggle extends StatelessWidget {
  final SearchMode mode;
  final bool isTelevision;
  final bool listsAvailable;
  final bool keywordAvailable;

  /// When true the two segments split the full available width (used when the
  /// toggle is stacked below the search box on narrow screens).
  final bool fullWidth;
  final ValueChanged<SearchMode> onChanged;

  /// TV-only DPAD focus nodes for the segments (null off-TV, where the
  /// InkWell handles pointer taps and normal Tab traversal instead).
  final FocusNode? catalogNode;
  final FocusNode? keywordNode;
  final FocusNode? listsNode;
  final FocusNode? dropdownNode;

  /// Use a single DPAD-capable dropdown when three labelled segments cannot
  /// fit without squeezing or overflowing the search header.
  final bool compact;

  /// Leave the toggle back to the search field (arrow-up, or arrow-left off the
  /// leftmost segment) / down into the board content.
  final VoidCallback? onLeaveToField;
  final VoidCallback? onLeaveToContent;

  const SearchModeToggle({
    super.key,
    required this.mode,
    required this.isTelevision,
    required this.listsAvailable,
    required this.keywordAvailable,
    required this.onChanged,
    this.fullWidth = false,
    this.catalogNode,
    this.keywordNode,
    this.listsNode,
    this.dropdownNode,
    this.compact = false,
    this.onLeaveToField,
    this.onLeaveToContent,
  });

  List<SearchMode> get _modes => [
    SearchMode.catalog,
    if (keywordAvailable) SearchMode.keyword,
    if (listsAvailable) SearchMode.lists,
  ];

  FocusNode? _nodeFor(SearchMode value) => switch (value) {
    SearchMode.catalog => catalogNode,
    SearchMode.keyword => keywordNode,
    SearchMode.lists => listsNode,
  };

  String _labelFor(SearchMode value) => switch (value) {
    SearchMode.catalog => 'Catalog',
    SearchMode.keyword => 'Keyword',
    SearchMode.lists => 'Lists',
  };

  /// DPAD handling for a focused segment: select switches mode, arrows move
  /// between the segments and out to the field (up/left) or content (down).
  KeyEventResult _handleSegmentKey(SearchMode value, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
      onChanged(value);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      onLeaveToField?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      onLeaveToContent?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      final index = _modes.indexOf(value);
      if (index > 0) {
        _nodeFor(_modes[index - 1])?.requestFocus();
      } else {
        onLeaveToField?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final index = _modes.indexOf(value);
      if (index >= 0 && index < _modes.length - 1) {
        _nodeFor(_modes[index + 1])?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final modes = _modes;
    if (modes.length <= 1) {
      return const SizedBox.shrink();
    }
    if (compact) {
      return SizedBox(
        width: fullWidth ? double.infinity : 156,
        child: StremioDropdown<SearchMode>(
          label: 'Search',
          value: modes.contains(mode) ? mode : modes.first,
          options: [
            for (final value in modes)
              StremioDropdownOption(value, _labelFor(value)),
          ],
          onSelected: onChanged,
          isTelevision: isTelevision,
          focusNode: dropdownNode,
          onUpArrowPressed: onLeaveToField,
          onDownArrowPressed: onLeaveToContent,
        ),
      );
    }
    final catalog = _segment(
      context,
      SearchMode.catalog,
      'Catalog',
      Icons.grid_view_rounded,
    );
    final keyword = _segment(
      context,
      SearchMode.keyword,
      'Keyword',
      Icons.bolt_rounded,
    );
    final lists = _segment(
      context,
      SearchMode.lists,
      'Lists',
      Icons.playlist_play_rounded,
    );
    final segments = <Widget>[
      catalog,
      if (modes.contains(SearchMode.keyword)) keyword,
      if (modes.contains(SearchMode.lists)) lists,
    ];
    return Container(
      height: isTelevision ? 54 : 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: app.shape.br(14),
        border: Border.all(color: app.fade(app.core.tx, 0.08)),
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: fullWidth
            ? [for (final segment in segments) Expanded(child: segment)]
            : segments,
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    SearchMode value,
    String label,
    IconData icon,
  ) {
    final app = AppThemeScope.of(context);
    final on = mode == value;
    final node = switch (value) {
      SearchMode.catalog => catalogNode,
      SearchMode.keyword => keywordNode,
      SearchMode.lists => listsNode,
    };

    Widget content(bool focused) => AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.symmetric(horizontal: isTelevision ? 16 : 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? app.home.chromeAccent : Colors.transparent,
        borderRadius: app.shape.br(10),
        // A white ring shows the remote's DPAD position. Drawn whenever the
        // segment is focused — including the selected one, since focus lands
        // there first (its accent fill alone wouldn't signal focus moved).
        border: Border.all(
          color: focused ? app.fade(app.core.tx, 0.9) : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            // Scored against the fill, not hardcoded white: chromeAccent IS
            // the accent, and 17 of the 18 selectable themes have one where
            // white fails — Noir's and Frost's are pure #FFFFFF, so the
            // selected segment was a white label on a white bar. inkOn
            // returns white on legacy's #7B5CFF (4.36, over the threshold),
            // so this is a no-op today.
            color: on
                ? app.inkOn(app.home.chromeAccent)
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: isTelevision ? 14 : 13,
              fontWeight: FontWeight.w700,
              color: on
                  ? app.inkOn(app.home.chromeAccent)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (node == null) {
      return InkWell(
        onTap: () => onChanged(value),
        borderRadius: app.shape.br(10),
        child: content(false),
      );
    }

    // The wrapping Focus owns the keyboard/DPAD focus node; the InkWell stays
    // pointer-only (canRequestFocus:false) so it doesn't compete for focus.
    return Focus(
      focusNode: node,
      onKeyEvent: (n, event) => _handleSegmentKey(value, event),
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return InkWell(
            onTap: () => onChanged(value),
            borderRadius: app.shape.br(10),
            canRequestFocus: false,
            child: content(focused),
          );
        },
      ),
    );
  }
}
