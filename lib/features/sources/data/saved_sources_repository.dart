import '../models/saved_sources_state.dart';
import '../../../services/series_source_service.dart';

abstract interface class SavedSourcesRepository {
  bool get isCurrent;
  Future<SavedSourcesState> load();
  Future<bool> remove(SeriesSource source);
}
