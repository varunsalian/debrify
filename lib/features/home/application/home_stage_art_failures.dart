/// Home artwork URLs that failed this session. A bounded memo avoids
/// repeatedly requesting missing stills/logos while browsing title rails.
///
/// The original stage full-clear policy: forgetting a failure costs one
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
