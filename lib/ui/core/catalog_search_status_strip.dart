import 'package:flutter/material.dart';
import '../../theme/app_theme_scope.dart';

/// Fixed-height streaming status preserves card positions when search settles.
Widget buildCatalogSearchStatus(
  BuildContext context, {
  required bool searching,
  required int failures,
}) {
  final app = AppThemeScope.of(context);
  return SizedBox(
    height: 16,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: searching
          ? Center(
              child: LinearProgressIndicator(
                minHeight: 2,
                color: app.home.chromeAccent,
                backgroundColor: const Color(0x22FFFFFF),
              ),
            )
          : Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$failures source'
                '${failures == 1 ? '' : 's'} didn\'t respond',
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.45),
                  fontSize: 11,
                ),
              ),
            ),
    ),
  );
}
