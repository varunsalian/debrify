import 'package:flutter/material.dart';

/// Keeps the existing responsive placement of the query field and mode control.
class SearchHeader extends StatelessWidget {
  const SearchHeader({
    super.key,
    required this.tv,
    required this.dedicatedSearch,
    required this.narrow,
    required this.compactModeMenu,
    required this.field,
    required this.toggle,
  });

  final bool tv;
  final bool dedicatedSearch;
  final bool narrow;
  final bool compactModeMenu;
  final Widget field;
  final Widget toggle;

  @override
  Widget build(BuildContext context) {
    if (narrow) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, tv ? 16 : 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [field, const SizedBox(height: 10), toggle],
        ),
      );
    }

    // Dedicated TV Search uses a compact toolbar without the balancing spacer.
    // Other wide surfaces retain their centered search field.
    return Padding(
      padding: tv && dedicatedSearch
          ? const EdgeInsets.fromLTRB(24, 8, 24, 8)
          : EdgeInsets.fromLTRB(20, tv ? 18 : 14, 20, 10),
      child: Row(
        children: [
          if (!tv || !dedicatedSearch)
            SizedBox(width: compactModeMenu ? 156 : 252),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: field,
              ),
            ),
          ),
          const SizedBox(width: 12),
          toggle,
        ],
      ),
    );
  }
}
