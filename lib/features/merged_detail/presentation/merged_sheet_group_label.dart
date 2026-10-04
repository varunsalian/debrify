import 'package:flutter/material.dart';

/// Section label inside a tracker sheet.
class _SheetGroupLabel extends StatelessWidget {
  final String label;
  const _SheetGroupLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.38),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    ),
  );
}

typedef MergedSheetGroupLabel = _SheetGroupLabel;

const mergedSheetGroupLabelConstructor = _SheetGroupLabel.new;
