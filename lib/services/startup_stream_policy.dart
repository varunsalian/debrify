class StartupStreamPolicy {
  static const Duration aioStreamsErrorSlateMaxDuration = Duration(minutes: 3);

  static bool isAioStreams({String? addonId, String? sourceName, String? url}) {
    final identity = [
      addonId,
      sourceName,
      Uri.tryParse(url ?? '')?.host,
    ].whereType<String>().join(' ').toLowerCase();
    return identity.contains('aiostreams');
  }

  static bool isLikelyAioStreamsErrorSlate({
    String? addonId,
    String? sourceName,
    String? url,
    required Duration duration,
  }) {
    return duration > Duration.zero &&
        duration < aioStreamsErrorSlateMaxDuration &&
        isAioStreams(addonId: addonId, sourceName: sourceName, url: url);
  }

  /// Whether a resolved fallback playlist must prove it contains the exact
  /// requested episode. Only multi-file series packs can silently substitute
  /// the wrong episode; a singleton was already episode-scoped by the search
  /// that found it, and its lone filename often has no parseable SxxEyy.
  static bool requiresExactEpisodeMatch({
    required bool isSeries,
    required int playlistLength,
  }) {
    return isSeries && playlistLength > 1;
  }

  /// Returns the exact resolved row to open. Series fallbacks must prove that
  /// they contain the requested episode; other VOD playlists start at row 0.
  static int? resolvedPlaylistIndex({
    required bool requiresEpisodeMatch,
    int? matchedEpisodeIndex,
  }) {
    if (!requiresEpisodeMatch) return 0;
    if (matchedEpisodeIndex == null || matchedEpisodeIndex < 0) return null;
    return matchedEpisodeIndex;
  }

  static ({int sourceIndex, int attempts}) rankedFailoverStart({
    required int selectedSourceIndex,
    required bool initialAttemptAlreadyFailed,
  }) {
    return (
      sourceIndex: selectedSourceIndex + (initialAttemptAlreadyFailed ? 1 : 0),
      attempts: initialAttemptAlreadyFailed ? 1 : 0,
    );
  }
}
