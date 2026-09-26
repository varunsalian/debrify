import 'package:flutter/widgets.dart';

import '../features/sources/data/local_source_files.dart';
import '../features/sources/models/local_source_file.dart';
import '../features/sources/presentation/local_source_picker_composition.dart';
import '../models/series_source.dart';

export '../features/sources/models/local_source_file.dart'
    show LocalSeriesEpisodeFile;

/// Compatibility entry points for existing catalog and playback callers.
/// Picker UI and platform wiring live in the Sources presentation composition.
class LocalBoundSourceService {
  static const String mobileDisabledReason = localBindingMobileDisabledReason;

  static Future<SeriesSource?> pickMovieSource(
    BuildContext context, {
    required String title,
    String? year,
    bool Function()? canContinue,
  }) => localSourcePicker.pickMovieSource(
    context,
    title: title,
    year: year,
    canContinue: canContinue,
  );

  static Future<SeriesSource?> pickSeriesSource(
    BuildContext context, {
    required String title,
    bool Function()? canContinue,
  }) => localSourcePicker.pickSeriesSource(
    context,
    title: title,
    canContinue: canContinue,
  );

  static Future<List<LocalSeriesEpisodeFile>> scanSeriesFolder(
    String path,
  ) async => (await scanLocalSeriesFolder(path)).toList();

  static bool get isLocalBindingDisabled => localDisabledReason != null;

  static String? get localDisabledReason => localSourcePicker.disabledReason;
}
