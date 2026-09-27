/// What Tonight's big card says about the focused entry. Derived per focus —
/// the OK hint has to tell the truth: a part-watched title resumes, a catalog
/// title opens, a favourite is watched.
class HomeTonightCardInfo {
  /// What OK actually does — never what the layout wishes it did. Continue
  /// Watching cards open their detail page on OK across the whole app, and
  /// Tonight keeps that grammar rather than diverging.
  final String action;

  /// What a HELD OK does, when that differs (resume, or the card menu).
  final String? holdAction;
  final String? episode;
  final double? progress;
  const HomeTonightCardInfo({
    required this.action,
    this.holdAction,
    this.episode,
    this.progress,
  });
}
