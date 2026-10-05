class DebrifyTvConstants {
  static const String providerRealDebrid = 'real_debrid';
  static const String providerTorbox = 'torbox';
  static const String providerPikPak = 'pikpak';
  static const String providerPremiumize = 'premiumize';
  static const String providerAllDebrid = 'alldebrid';
  static const String torboxFileEntryType = 'torbox_file';
  static const int torboxMinVideoSizeBytes =
      50 * 1024 * 1024; // 50 MB filter threshold
  static const int playbackTorrentThreshold = 1000;
  static const int maxTorrentsPerKeywordPlayback = 25;
  static const int minimumTorrentsForChannel = 1;
  static const int maxChannelKeywords = 1000;
  static const int keywordWarmEstimateMs = 1000;
  // Real-Debrid only: consecutive links rejected purely on size, and the
  // resulting session-wide relaxation. See _rdLinkPassesSizeRules.
  static const int rdSizeRejectionLimit = 12;
  // Prefetch state
  static const int minPrepared = 6; // maintain at least 6 prepared items
  static const int lookaheadWindow = 10; // window near head to keep prepared
}
