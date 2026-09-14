import 'package:flutter/material.dart';

/// Touch-friendly category navigation that scrolls independently of the grid.
class CollectionCategoryTabs extends StatelessWidget {
  const CollectionCategoryTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    child: Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(labels[index]),
              selected: selectedIndex == index,
              showCheckmark: false,
              onSelected: (_) => onSelected(index),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ),
      ],
    ),
  );
}
