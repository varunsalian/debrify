abstract interface class SourceCacheSession {
  bool get torboxEnabled;
  bool get premiumizeEnabled;
  Future<Set<String>> torbox(List<String> hashes);
  Future<List<bool>> premiumize(List<String> hashes);
}

abstract interface class SourceCacheRepository {
  bool get isCurrent;
  Future<SourceCacheSession> open();
}
