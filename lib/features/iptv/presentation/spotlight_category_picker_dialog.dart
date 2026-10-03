import 'dart:math' as math;

import 'package:debrify/utils/tv_keys.dart' show TvHeldKeyGuard;
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

/// Lazily renders Spotlight's category choices while restoring the current
/// selection on every open. The dialog owns both navigation objects because a
/// route can remain mounted during its reverse transition after `pop`.
class SpotlightCategoryPickerDialog extends StatefulWidget {
  final List<String> categories;
  final String? selectedCategory;
  final Map<String, int> categoryCounts;
  final int allChannelCount;
  final bool showOptionsHint;
  final String allCategoryValue;

  const SpotlightCategoryPickerDialog({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.categoryCounts,
    required this.allChannelCount,
    required this.showOptionsHint,
    required this.allCategoryValue,
  });

  @override
  State<SpotlightCategoryPickerDialog> createState() =>
      _SpotlightCategoryPickerDialogState();
}

class _SpotlightCategoryPickerDialogState
    extends State<SpotlightCategoryPickerDialog> {
  static const double _itemExtent = 56;

  late final int _selectedIndex;
  late final ScrollController _scrollController;
  late final FocusNode _selectedFocusNode;

  @override
  void initState() {
    super.initState();
    final categoryIndex = widget.selectedCategory == null
        ? -1
        : widget.categories.indexOf(widget.selectedCategory!);
    _selectedIndex = categoryIndex < 0 ? 0 : categoryIndex + 1;
    _scrollController = ScrollController(
      initialScrollOffset: _selectedIndex * _itemExtent,
    );
    _selectedFocusNode = FocusNode(
      debugLabel: 'iptv-spotlight-selected-category',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedFocusNode.canRequestFocus) {
        _selectedFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _selectedFocusNode.dispose();
    super.dispose();
  }

  void _pick(String value) => Navigator.of(context).pop(value);

  @override
  Widget build(BuildContext context) {
    final t = IptvStyleTokens.spotlight;
    final size = MediaQuery.sizeOf(context);
    return TvHeldKeyGuard(
      child: Dialog(
        key: const ValueKey<String>('spotlight-category-picker'),
        backgroundColor: t.panel,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: t.hairline2),
        ),
        child: SizedBox(
          width: math.min(440, size.width - 32),
          height: math.min(620, size.height - 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose category',
                        style: TextStyle(
                          color: t.fg,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    CloseButton(onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
              Divider(height: 1, color: t.hairline),
              Expanded(
                child: ListView.builder(
                  key: const ValueKey<String>('spotlight-category-list'),
                  controller: _scrollController,
                  itemExtent: _itemExtent,
                  itemCount: 1 + widget.categories.length,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final selected = _selectedIndex == 0;
                      return ListTile(
                        key: selected
                            ? const ValueKey<String>(
                                'spotlight-selected-category-tile',
                              )
                            : null,
                        focusNode: selected ? _selectedFocusNode : null,
                        autofocus: selected,
                        selected: selected,
                        selectedTileColor: t.selectedTint,
                        leading: Icon(Icons.apps_rounded, color: t.accent),
                        title: Text(
                          'All channels',
                          style: TextStyle(color: t.fg),
                        ),
                        trailing: Text(
                          '${widget.allChannelCount}',
                          style: TextStyle(color: t.fgDim),
                        ),
                        onTap: () => _pick(widget.allCategoryValue),
                      );
                    }
                    final category = widget.categories[index - 1];
                    final selected = index == _selectedIndex;
                    return ListTile(
                      key: selected
                          ? const ValueKey<String>(
                              'spotlight-selected-category-tile',
                            )
                          : null,
                      focusNode: selected ? _selectedFocusNode : null,
                      autofocus: selected,
                      selected: selected,
                      selectedTileColor: t.selectedTint,
                      leading: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.folder_outlined,
                        color: selected ? t.accent : t.fgDim,
                      ),
                      title: Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: t.fg),
                      ),
                      trailing: Text(
                        '${widget.categoryCounts[category] ?? 0}',
                        style: TextStyle(color: t.fgDim),
                      ),
                      onTap: () => _pick(category),
                    );
                  },
                ),
              ),
              if (widget.showOptionsHint) ...[
                Divider(height: 1, color: t.hairline),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
                  child: Text(
                    'Select a category, then use ••• to set it as the default '
                    'or hide it.',
                    style: TextStyle(color: t.fgFaint, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
