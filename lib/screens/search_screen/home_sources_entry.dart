import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/series_source.dart';
import '../../features/home/presentation/home_local_source_picker.dart';
import '../../features/home/presentation/home_sources_navigation.dart';
import '../../features/sources/presentation/local_source_picker.dart';
import '../../features/sources/presentation/sources_screen.dart';

/// Home's Sources entry points, bound to the Sources feature at the screen
/// composition. Home receives them through its dependencies.
final homeSourcesNavigationProvider = Provider<HomeSourcesNavigation>(
  (ref) => const HomeSourcesNavigation(buildScreen: SourcesScreen.new),
);

/// Adapts the Sources feature's local picker to the operations Home uses.
class HomeLocalSourcePickerAdapter implements HomeLocalSourcePicker {
  const HomeLocalSourcePickerAdapter(this._picker);
  final LocalSourcePicker _picker;

  @override
  String? get disabledReason => _picker.disabledReason;
  @override
  Future<SeriesSource?> pickSeriesSource(
    BuildContext context, {
    required String title,
    bool Function()? canContinue,
  }) =>
      _picker.pickSeriesSource(context, title: title, canContinue: canContinue);
  @override
  Future<SeriesSource?> pickMovieSource(
    BuildContext context, {
    required String title,
    String? year,
    bool Function()? canContinue,
  }) => _picker.pickMovieSource(
    context,
    title: title,
    year: year,
    canContinue: canContinue,
  );
}
