/// Metahub backdrop URLs that failed this session. A bounded memo avoids
/// repeatedly requesting missing derived stills while browsing title rails.
///
/// A full clear preserves the original policy: forgetting a failure costs one
/// re-request, without retaining every missing URL for the process lifetime.
class HomeStageArtFailures {
  static const _maximum = 512;
  final Set<String> _urls = <String>{};

  bool contains(String url) => _urls.contains(url);

  void remember(String url) {
    if (_urls.length >= _maximum) _urls.clear();
    _urls.add(url);
  }
}
