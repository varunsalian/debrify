/// Credentials and provider calls stay behind a search-owned session; neither
/// widgets nor published cache state need access to API keys.
abstract interface class KeywordCacheSession {
  bool get torboxEnabled;
  bool get premiumizeEnabled;
  bool get otherProviderActive;
  Future<Set<String>> torbox(List<String> hashes);
  Future<List<bool>> premiumize(List<String> hashes);
}

abstract interface class KeywordCacheRepository {
  bool get isCurrent;
  Future<KeywordCacheSession> open();
}
