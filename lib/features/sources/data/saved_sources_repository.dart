import '../models/saved_sources_state.dart';

abstract interface class SavedSourcesRepository {
  bool get isCurrent;
  Future<SavedSourcesState> load();
}
