class EpisodesPanelPolicies {
  /// "Trakt, Simkl and this device"
  static String joinNames(List<String> names) => names.length <= 1
      ? names.join()
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

  /// Cinemeta episode stills come as episodes.metahub.space/…/w780.jpg — a 301
  /// to the full-width TMDB image (~50 KB) for a 124-logical-px row thumb. The
  /// size token maps straight to TMDB sizes, so ask for w300 (~11 KB) instead;
  /// on TV-grade WiFi that's the difference between a snap and a trickle.
  static String? downsizeMetahubThumb(String? url) {
    if (url == null || !url.contains('episodes.metahub.space')) return url;
    return url.replaceFirst(RegExp(r'/w\d+\.jpg$'), '/w300.jpg');
  }
}
