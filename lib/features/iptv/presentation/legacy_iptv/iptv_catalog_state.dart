import 'dart:async';
import 'dart:collection';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/widgets/iptv/db_channel_list.dart';

class IptvCatalogState {
  List<IptvChannel> allChannels = [];

  List<IptvChannel> filteredChannels = [];

  List<String> categories = [];

  String? selectedCategory;

  /// True once the user has picked a category — INCLUDING "All" — for the
  /// current load. Needed because "All" and "nothing picked yet" are the same
  /// null [selectedCategory]: the landing-category seed fills the latter and
  /// must never override the former (a background revalidate re-presenting
  /// the catalog would otherwise yank an explicit "All" back to a category).
  bool categoryManuallyChosen = false;

  /// Armed by [_loadPlaylistInner]'s clearing setState and consumed by the
  /// FIRST present of that load. Only that present may seed a landing
  /// category: the background revalidate re-uses the same present functions
  /// (including the materialized fallback when the DB flag flips off
  /// mid-flight), and an unarmed seed there would yank a user who is sitting
  /// on All mid-browse.
  bool landingSeedArmed = false;

  /// Non-null exactly while the CURRENT view is DB-backed.
  CatalogSnapshot? dbSnapshot;

  /// Per-group counts for the DB-backed catalog (replaces the
  /// [_categoryCounts] scan, which would page the whole facade).
  Map<String, int> dbGroupCounts = const {};

  /// Categories the user has hidden in the CURRENT catalog.
  ///
  /// The channel rows are already excluded in SQL, and so are the groups
  /// derived from them — this set exists for the one list SQL can't reach:
  /// the provider's own `categories_json`, which names categories verbatim
  /// rather than deriving them from rows.
  Set<String> hiddenCategories = const {};

  /// Shared instance cache for the DB facades of the CURRENT catalog
  /// generation (see [DbChannelList.instanceCache]): reused so a filter /
  /// search recompute keeps identity for rows that stay on screen, instead
  /// of minting new instances that tear down and rebuild every visible row
  /// (EPG re-resolve, focus/image churn — what made search feel laggy).
  final LinkedHashMap<int, IptvChannel> dbInstanceCache = LinkedHashMap();

  /// `<catalogKey>#<generation>` the [dbInstanceCache] currently holds —
  /// cleared when either changes (a different playlist, or a refresh's new
  /// generation, whose rows can carry changed data).
  String? dbInstanceCacheKey;

  String selectedContentType = 'live';

  bool isLoading = false;

  String? errorMessage;

  int loadTicket = 0;

  /// Changes whenever the visible channel projection changes inside one
  /// playlist load (search/category filters can replace DB-backed channel
  /// instances without bumping [loadTicket]). Spotlight timeline requests
  /// include this generation so an answer for an outgoing filtered ordinal
  /// can never land on a different row that took its place.
  int spotlightViewGeneration = 0;

  /// Ticket of a [_loadPlaylist] run that is still in flight, or null.
  /// Guards [_loadSettings]' "no channels yet" fallback: `allChannels` is
  /// empty for the ENTIRE duration of a first load (cleared at start, filled
  /// at present — tens of seconds on a big panel), so without this any
  /// re-entry in that window (Stremio addons-changed listener, a settings
  /// return, refreshPlaylists) started a SECOND full pipeline. The first was
  /// never cancelled — only its result discarded by ticket. URL M3Us are now
  /// disk-staged and streamed, but duplicate pipelines would still duplicate
  /// the network transfer, staging space, parse worker and SQLite generation.
  int? inFlightLoadTicket;

  bool isLoadingMore = false;

  DateTime? lastProgressiveApply;

  /// Per-category channel counts for the current catalog (redesign labels).
  /// Memoized against the list instance AND its length — progressive Stremio
  /// loads append to one list, so identity alone would freeze the counts at
  /// the first batch.
  List<IptvChannel>? categoryCountsSource;

  int categoryCountsLength = -1;

  Map<String, int> categoryCountsCache = const {};

  bool applyingCatalogRefresh = false;

  final catalogPresentationJobs = <String, Future<void>>{};

  /// The last successfully loaded parse result (same list instances the page
  /// renders — a couple of references, not a copy).
  IptvParseResult? lastLoadResult;
}
