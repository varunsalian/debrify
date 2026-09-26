import 'dart:async';
import 'package:debrify/features/sources/data/source_cache_repository.dart';

class FakeSourceCacheRepository implements SourceCacheRepository {
  @override
  bool isCurrent = true;
  final opens = <Completer<SourceCacheSession>>[];
  @override
  Future<SourceCacheSession> open() {
    final next = Completer<SourceCacheSession>();
    opens.add(next);
    return next.future;
  }
}

class FakeSourceCacheSession implements SourceCacheSession {
  FakeSourceCacheSession({
    this.torboxEnabled = true,
    this.premiumizeEnabled = true,
  });
  @override
  final bool torboxEnabled;
  @override
  final bool premiumizeEnabled;
  final tb = <(List<String>, Completer<Set<String>>)>[];
  final pm = <(List<String>, Completer<List<bool>>)>[];
  @override
  Future<Set<String>> torbox(List<String> hashes) {
    final next = Completer<Set<String>>();
    tb.add((List.of(hashes), next));
    return next.future;
  }

  @override
  Future<List<bool>> premiumize(List<String> hashes) {
    final next = Completer<List<bool>>();
    pm.add((List.of(hashes), next));
    return next.future;
  }
}
