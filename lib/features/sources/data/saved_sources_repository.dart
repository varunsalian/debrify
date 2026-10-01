import '../../../models/series_source.dart';
import '../models/saved_sources_state.dart';

abstract interface class SavedSourcesRepository {
  bool get isCurrent;
  Future<SavedSourcesState> load();
  Future<bool> remove(SeriesSource source);
  Future<bool> save(SeriesSource source);
}
