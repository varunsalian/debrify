abstract interface class SourceSeasonGuide {
  List<int> get seasons;
  Future<void> record();
}

abstract interface class SourceSeasonsRepository {
  bool get isCurrent;
  Future<SourceSeasonGuide?> load();
}
