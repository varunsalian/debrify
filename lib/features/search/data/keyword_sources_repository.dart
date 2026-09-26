import '../models/keyword_source.dart';

abstract interface class KeywordSourcesRepository {
  bool get isCurrent;
  Future<List<KeywordSource>> load();
  Future<void> setEnabled(String id, bool enabled);
}
