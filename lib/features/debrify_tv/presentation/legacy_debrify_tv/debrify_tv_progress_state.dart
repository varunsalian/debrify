import 'package:flutter/material.dart';

class DebrifyTvProgressState {
  // Progress UI state
  final ValueNotifier<List<String>> progress = ValueNotifier<List<String>>([]);
  BuildContext? progressSheetContext;
  bool progressOpen = false;
}
