import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';
import 'settings_layout.dart';

Widget buildConnectionGrid(
  SettingsLayout layout,
  BuildContext context,
  List<ConnectionInfo> items, {
  bool singleFullWidth = false,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns =
          constraints.maxWidth >= 680 &&
          !(singleFullWidth && items.length == 1);
      final width = twoColumns
          ? (constraints.maxWidth - 10) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final info in items)
            SizedBox(
              width: width,
              child: ConnectionCard(info: info, isLeftColumn: false),
            ),
        ],
      );
    },
  );
}
