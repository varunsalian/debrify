import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/material.dart';

typedef AllDebridScope = ({
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  bool Function() isPushedRoute,
  bool Function() selectSourceMode,
  Future<void> Function(SeriesSource)? Function() onSourceSelected,
});
