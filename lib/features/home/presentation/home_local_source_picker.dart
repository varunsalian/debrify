import 'package:flutter/widgets.dart';
import '../../../models/series_source.dart';

/// The local-file source picking Home's source editor offers. Home declares
/// what it uses; the composition adapts the Sources feature's picker.
abstract interface class HomeLocalSourcePicker {
  /// Why local sources are unavailable on this device, or null when available.
  String? get disabledReason;

  Future<SeriesSource?> pickSeriesSource(
    BuildContext context, {
    required String title,
    bool Function()? canContinue,
  });

  Future<SeriesSource?> pickMovieSource(
    BuildContext context, {
    required String title,
    String? year,
    bool Function()? canContinue,
  });
}
