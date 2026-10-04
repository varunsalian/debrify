import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsFeedbackDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
});

class IptvSettingsFeedback {
  IptvSettingsFeedback(this._deps);
  final IptvSettingsFeedbackDeps _deps;

  void showSnackBar(String message, {bool isError = true}) {
    if (!_deps.mounted()) return;
    final t = AppThemeScope.of(_deps.context()).settings;
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? t.danger : t.success,
      ),
    );
  }
}
