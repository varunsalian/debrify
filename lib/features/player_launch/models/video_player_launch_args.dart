import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playback_resume_policy.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/source_playlist_resolver.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/series_source_fetcher.dart';

class VideoPlayerLaunchArgs {
  final String videoUrl;

  /// Optional separate audio track to play alongside [videoUrl] (used for
  /// high-res YouTube, where video and audio are served as separate streams).
  final String? audioUrl;

  /// Optional muxed stream (already has audio) used as a never-silent fallback
  /// by players that can only accept one URL, where [videoUrl] may be a
  /// video-only HD track.
  final String? fallbackUrl;

  final String title;

  final String? subtitle;

  final List<PlaylistEntry>? playlist;

  final int? startIndex;

  final String? rdTorrentId;

  final String? torboxTorrentId;

  final String? pikpakCollectionId;

  final String? webDavServerId;

  final String? webDavBaseUrl;

  final String? webDavPath;

  final Future<Map<String, String>?> Function()? requestMagicNext;

  final Future<Map<String, dynamic>?> Function()? requestNextChannel;

  final bool initialContinuousShuffle;

  final bool startFromRandom;

  final int randomStartMaxPercent;

  final double? startAtPercent;

  final bool hideSeekbar;

  final bool showChannelName;

  final String? channelName;

  final int? channelNumber;

  final bool showVideoTitle;

  final bool hideOptions;

  final bool hideBackButton;

  final Map<String, String>? httpHeaders;

  final bool disableExternalPlayer;

  final bool Function()? isAndroidTvOverride;

  final bool disableAutoResume;

  final PlaylistViewMode? viewMode;

  // Content metadata for fetching external subtitles from Stremio addons
  final String? contentImdbId;

  final String? contentType; // 'movie' or 'series'

  final int? contentSeason;

  final int? contentEpisode;

  /// Whether local resume follows the exact source or canonical catalog
  /// identity. Direct/generic launchers default to source-specific behavior.
  final PlaybackResumePolicy resumePolicy;

  // IPTV channel list for in-player channel switching
  final List<IptvChannel>? iptvChannels;

  final int? iptvStartIndex;

  /// The source's FULL category list, in provider order. Without it the player
  /// derived categories from the windowed (~1500) channel list, so the picker
  /// only ever showed the handful of groups in that window.
  final List<String>? iptvCategories;

  final String? iptvSourceId;

  final String? iptvSourceName;

  final String? iptvSelectedCategory;

  final String? iptvContentType;

  final List<Map<String, dynamic>>? iptvSources;

  /// The user's channel lists ({id, name, isBuiltin}), for the players'
  /// "add to list" picker. Shipped once per launch rather than as a field on
  /// every channel — the channel payload is already capped for size.
  final List<Map<String, dynamic>>? iptvLists;

  final Future<Map<String, dynamic>?> Function(Map<String, dynamic>)? iptvBrowseProvider;

  // Stremio sources for in-player source switching
  final List<Torrent>? stremioSources;

  final int? stremioCurrentSourceIndex;

  final Future<String?> Function(Torrent)? resolveStremioSource;

  // Torrent search source switching: resolves a Torrent to a full playlist
  final SourcePlaylistResolve? resolveSourceToPlaylist;

  /// Startup failover is an automatic Quick Play behavior. Explicit source
  /// launches still validate their selected row, but must never advance.
  final bool startupFailoverEnabled;

  /// Provider used by the startup playlist resolver. PikPak needs this so the
  /// automatic ladder cannot enqueue more than one cold-storage acquisition.
  final String? startupResolverProvider;

  /// Persist a source switch only after the player has validated and committed
  /// the candidate. Resolution alone is deliberately side-effect free.
  final Future<void> Function(Torrent)? onStremioSourceCommitted;

  /// Invoked after the startup ladder is exhausted and the player surface has
  /// closed. Bound-source launches use this to continue through the remaining
  /// eligible pins, then perform a fresh search without replaying failed pins.
  final Future<void> Function()? onStartupSourcesExhausted;

  final bool startupHasRemainingSavedSources;

  // Series source tabs: on-demand "Load more sources" fetcher for the
  // pack/episode split. Non-null only for series plays with a searchable id.
  final SeriesSourceFetcher? seriesSourceFetcher;

  // Stremio TV in-player channel guide
  final List<Map<String, dynamic>>? stremioTvChannels;

  final String? stremioTvCurrentChannelId;

  final int? stremioTvRotationMinutes;

  final int? stremioTvSeriesRotationMinutes;

  final int? stremioTvMixSalt;

  final Future<Map<String, dynamic>?> Function(List<String>)? stremioTvGuideDataProvider;

  final Future<Map<String, dynamic>?> Function(String)? stremioTvChannelSwitchProvider;

  final Future<Map<String, dynamic>?> Function(String)? stremioTvNextProvider;

  // Trakt scrobble: send playback progress to Trakt
  final bool traktScrobble;

  // Prevent launcher-level Trakt auto-sync upgrade for playlist-origin playback.
  // Context-scoped, not Trakt-specific: contexts that suppress Trakt auto-sync
  // (playlists, Stremio TV) suppress the Simkl auto-sync upgrade too.
  final bool suppressTrackerAutoSync;

  @Deprecated('Use suppressTrackerAutoSync')
  bool get suppressTraktAutoSync => suppressTrackerAutoSync;

  // Trakt progress: resume fallback when no local resume exists (0-100)
  final double? traktProgressPercent;

  // Simkl scrobble/progress — fully parallel to the Trakt pair above.
  final bool simklScrobble;

  final double? simklProgressPercent;

  final bool mdblistScrobble;

  final double? mdblistProgressPercent;

  // Continue watching metadata (for home screen section)
  final String? contentTitle; // Clean display name (IMDB title)

  final String? posterUrl;

  final String? contentYear;

  final String? addonId; // Stremio addon used for playback

  /// Subtitle tracks known at launch time, surfaced in the player's subtitle
  /// menu as a pre-loaded provider group (no addon fetch needed). Used for
  /// sources that carry their own captions — e.g. YouTube closed captions —
  /// where the IMDb-keyed addon fetch never runs.
  final List<StremioSubtitle>? initialSubtitles;

  const VideoPlayerLaunchArgs({
    required this.videoUrl,
    this.audioUrl,
    this.fallbackUrl,
    required this.title,
    this.subtitle,
    this.playlist,
    this.startIndex,
    this.rdTorrentId,
    this.torboxTorrentId,
    this.pikpakCollectionId,
    this.webDavServerId,
    this.webDavBaseUrl,
    this.webDavPath,
    this.requestMagicNext,
    this.requestNextChannel,
    this.initialContinuousShuffle = false,
    this.startFromRandom = false,
    this.randomStartMaxPercent = 40,
    this.startAtPercent,
    this.hideSeekbar = false,
    this.showChannelName = false,
    this.channelName,
    this.channelNumber,
    this.showVideoTitle = true,
    this.hideOptions = false,
    this.hideBackButton = false,
    this.httpHeaders,
    this.disableExternalPlayer = false,
    this.isAndroidTvOverride,
    this.disableAutoResume = false,
    this.viewMode,
    this.contentImdbId,
    this.contentType,
    this.contentSeason,
    this.contentEpisode,
    this.resumePolicy = PlaybackResumePolicy.sourceSpecific,
    this.iptvChannels,
    this.iptvStartIndex,
    this.iptvCategories,
    this.iptvSourceId,
    this.iptvSourceName,
    this.iptvSelectedCategory,
    this.iptvContentType,
    this.iptvSources,
    this.iptvLists,
    this.iptvBrowseProvider,
    this.stremioSources,
    this.stremioCurrentSourceIndex,
    this.resolveStremioSource,
    this.resolveSourceToPlaylist,
    this.startupFailoverEnabled = false,
    this.startupResolverProvider,
    this.onStremioSourceCommitted,
    this.onStartupSourcesExhausted,
    this.startupHasRemainingSavedSources = false,
    this.seriesSourceFetcher,
    this.stremioTvChannels,
    this.stremioTvCurrentChannelId,
    this.stremioTvRotationMinutes,
    this.stremioTvSeriesRotationMinutes,
    this.stremioTvMixSalt,
    this.stremioTvGuideDataProvider,
    this.stremioTvChannelSwitchProvider,
    this.stremioTvNextProvider,
    this.traktScrobble = false,
    bool? suppressTrackerAutoSync,
    bool suppressTraktAutoSync = false,
    this.traktProgressPercent,
    this.simklScrobble = false,
    this.simklProgressPercent,
    this.mdblistScrobble = false,
    this.mdblistProgressPercent,
    this.contentTitle,
    this.posterUrl,
    this.contentYear,
    this.addonId,
    this.initialSubtitles,
  }) : suppressTrackerAutoSync = suppressTrackerAutoSync ?? suppressTraktAutoSync;

  VideoPlayerLaunchArgs copyWith({
    bool? traktScrobble,
    bool? simklScrobble,
    bool? mdblistScrobble,
    double? traktProgressPercent,
    double? simklProgressPercent,
    double? mdblistProgressPercent,
    bool? suppressTrackerAutoSync,
  }) => VideoPlayerLaunchArgs(
    videoUrl: videoUrl,
    audioUrl: audioUrl,
    fallbackUrl: fallbackUrl,
    title: title,
    subtitle: subtitle,
    playlist: playlist,
    startIndex: startIndex,
    rdTorrentId: rdTorrentId,
    torboxTorrentId: torboxTorrentId,
    pikpakCollectionId: pikpakCollectionId,
    webDavServerId: webDavServerId,
    webDavBaseUrl: webDavBaseUrl,
    webDavPath: webDavPath,
    requestMagicNext: requestMagicNext,
    requestNextChannel: requestNextChannel,
    initialContinuousShuffle: initialContinuousShuffle,
    startFromRandom: startFromRandom,
    randomStartMaxPercent: randomStartMaxPercent,
    startAtPercent: startAtPercent,
    hideSeekbar: hideSeekbar,
    showChannelName: showChannelName,
    channelName: channelName,
    channelNumber: channelNumber,
    showVideoTitle: showVideoTitle,
    hideOptions: hideOptions,
    hideBackButton: hideBackButton,
    httpHeaders: httpHeaders,
    disableExternalPlayer: disableExternalPlayer,
    isAndroidTvOverride: isAndroidTvOverride,
    disableAutoResume: disableAutoResume,
    viewMode: viewMode,
    contentImdbId: contentImdbId,
    contentType: contentType,
    contentSeason: contentSeason,
    contentEpisode: contentEpisode,
    resumePolicy: resumePolicy,
    iptvChannels: iptvChannels,
    iptvStartIndex: iptvStartIndex,
    iptvCategories: iptvCategories,
    iptvSourceId: iptvSourceId,
    iptvSourceName: iptvSourceName,
    iptvSelectedCategory: iptvSelectedCategory,
    iptvContentType: iptvContentType,
    iptvSources: iptvSources,
    iptvLists: iptvLists,
    iptvBrowseProvider: iptvBrowseProvider,
    stremioSources: stremioSources,
    stremioCurrentSourceIndex: stremioCurrentSourceIndex,
    resolveStremioSource: resolveStremioSource,
    resolveSourceToPlaylist: resolveSourceToPlaylist,
    startupFailoverEnabled: startupFailoverEnabled,
    startupResolverProvider: startupResolverProvider,
    onStremioSourceCommitted: onStremioSourceCommitted,
    onStartupSourcesExhausted: onStartupSourcesExhausted,
    startupHasRemainingSavedSources: startupHasRemainingSavedSources,
    seriesSourceFetcher: seriesSourceFetcher,
    stremioTvChannels: stremioTvChannels,
    stremioTvCurrentChannelId: stremioTvCurrentChannelId,
    stremioTvRotationMinutes: stremioTvRotationMinutes,
    stremioTvSeriesRotationMinutes: stremioTvSeriesRotationMinutes,
    stremioTvMixSalt: stremioTvMixSalt,
    stremioTvGuideDataProvider: stremioTvGuideDataProvider,
    stremioTvChannelSwitchProvider: stremioTvChannelSwitchProvider,
    stremioTvNextProvider: stremioTvNextProvider,
    traktScrobble: traktScrobble ?? this.traktScrobble,
    traktProgressPercent: traktProgressPercent ?? this.traktProgressPercent,
    simklScrobble: simklScrobble ?? this.simklScrobble,
    simklProgressPercent: simklProgressPercent ?? this.simklProgressPercent,
    mdblistScrobble: mdblistScrobble ?? this.mdblistScrobble,
    mdblistProgressPercent: mdblistProgressPercent ?? this.mdblistProgressPercent,
    suppressTrackerAutoSync: suppressTrackerAutoSync ?? this.suppressTrackerAutoSync,
    contentTitle: contentTitle,
    posterUrl: posterUrl,
    contentYear: contentYear,
    addonId: addonId,
    initialSubtitles: initialSubtitles,
  );
}
