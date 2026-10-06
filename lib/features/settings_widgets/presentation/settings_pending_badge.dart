import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

class WebDavSyncPendingBadge extends StatelessWidget {
  const WebDavSyncPendingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color:
          IconTheme.of(context).color ??
          AppThemeScope.of(context).settings.dim2,
    );
  }
}
