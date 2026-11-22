enum HomeEpisodeArtworkSource { local, trakt, simkl, ledger }

typedef HomeEpisodeReference = ({int season, int episode});
typedef HomeEpisodeArtwork = Map<HomeEpisodeArtworkSource, Map<String, String>>;
typedef HomeEpisodeArtworkReader =
    Future<String?> Function({
      required String imdbId,
      required int season,
      required int episode,
    });
