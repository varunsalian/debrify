import 'package:debrify/features/search/data/keyword_cache_repository.dart';

class FakeKeywordCacheRepository implements KeywordCacheRepository {
  @override
  bool isCurrent = true;
  var opens = 0;
  FakeKeywordCacheSession session = FakeKeywordCacheSession();
  Future<KeywordCacheSession> Function()? configure;
  @override
  Future<KeywordCacheSession> open() async {
    opens++;
    return configure == null ? session : configure!();
  }
}

class FakeKeywordCacheSession implements KeywordCacheSession {
  @override
  bool torboxEnabled = true;
  @override
  bool premiumizeEnabled = false;
  @override
  bool otherProviderActive = false;
  final torboxCalls = <List<String>>[];
  final premiumizeCalls = <List<String>>[];
  Future<Set<String>> Function(List<String>)? tb;
  Future<List<bool>> Function(List<String>)? pm;

  @override
  Future<Set<String>> torbox(List<String> hashes) async {
    torboxCalls.add(List.of(hashes));
    return tb == null ? hashes.toSet() : tb!(hashes);
  }

  @override
  Future<List<bool>> premiumize(List<String> hashes) async {
    premiumizeCalls.add(List.of(hashes));
    return pm == null ? List.filled(hashes.length, true) : pm!(hashes);
  }
}
