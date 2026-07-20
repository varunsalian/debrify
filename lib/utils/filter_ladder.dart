import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';
import '../services/storage_service.dart';
import '../widgets/torrent_result_row.dart' show qualityTierForName;
import 'torrent_filter_matcher.dart';

/// Quick-play's tiered filter preference (QUICK_PLAY_FILTERS_PLAN.md §3).
///
/// Built from the user's saved default filters, it ranks play candidates by
/// how strictly they match: tier 0 is a full match, each following tier
/// relaxes one dimension (language → rip source → quality), and the last
/// tier is unrestricted — so the ladder can only ever REORDER candidates,
/// never lose one. Cam-classified sources sink to an absolute floor below
/// every tier unless the user explicitly selected cam (§3.3c).
///
/// Empty filters ⇒ [isActive] is false and [order] is the identity, keeping
/// quick-play byte-identical for users without filters.
class FilterLadder {
  final TorrentFilterState filters;
  late final List<TorrentFilterState> _tiers;

  FilterLadder(this.filters) {
    _tiers = _buildTiers(filters);
  }

  /// Loads the saved default filters (Settings → Filter Settings) — the same
  /// persisted values the Search tab seeds its toolbar from.
  static Future<FilterLadder> fromSavedDefaults() async {
    final results = await Future.wait([
      StorageService.getDefaultFilterQualities(),
      StorageService.getDefaultFilterRipSources(),
      StorageService.getDefaultFilterLanguages(),
      StorageService.getDefaultFilterSizes(),
    ]);
    final qualities = <QualityTier>{
      for (final q in results[0])
        ...QualityTier.values.where((e) => e.name == q),
    };
    final ripSources = <RipSourceCategory>{
      for (final s in results[1])
        ...RipSourceCategory.values.where((e) => e.name == s),
    };
    final languages = <AudioLanguage>{
      for (final l in results[2])
        ...AudioLanguage.values.where((e) => e.name == l),
    };
    final sizes = <SizeBucket>{
      for (final s in results[3])
        ...SizeBucket.values.where((e) => e.name == s),
    };
    return FilterLadder(
      TorrentFilterState(
        qualities: qualities,
        ripSources: ripSources,
        languages: languages,
        sizes: sizes,
      ),
    );
  }

  bool get isActive => !filters.isEmpty;

  /// Number of regular tiers (tier 0 … tierCount-1, the last unrestricted).
  /// Demoted cams report [tierCount] itself — the floor bucket.
  int get tierCount => _tiers.length;

  static List<TorrentFilterState> _buildTiers(TorrentFilterState f) {
    if (f.isEmpty) return const [TorrentFilterState.empty()];
    final tiers = <TorrentFilterState>[f];
    var current = f;
    // Relaxation order (plan §3.1): language first — name-based language
    // detection is the least reliable signal — then rip source, then quality.
    // Size is a hard byte count (the most reliable dimension), so it's honored
    // the longest — relaxed last, just before the unrestricted floor.
    if (current.languages.isNotEmpty) {
      current = current.copyWith(languages: const <AudioLanguage>{});
      tiers.add(current);
    }
    if (current.ripSources.isNotEmpty) {
      current = current.copyWith(ripSources: const <RipSourceCategory>{});
      tiers.add(current);
    }
    if (current.qualities.isNotEmpty) {
      current = current.copyWith(qualities: const <QualityTier>{});
      tiers.add(current);
    }
    if (current.sizes.isNotEmpty) {
      tiers.add(const TorrentFilterState.empty());
    }
    return tiers;
  }

  /// Ladder-side language matching (§3.3 / §3.3b). Differs from the browse
  /// filter's single-detection semantics on purpose:
  /// - a name matches when ANY selected language's token appears (dual-audio
  ///   tag lists like "ENG.LATINO.HINDI" satisfy an English filter);
  /// - an explicit multi-audio tag satisfies any selection;
  /// - a name with NO language token counts as English when English is
  ///   selected: 89% of real release names carry no tag and are
  ///   overwhelmingly English — rejecting them would starve tier 0
  ///   (corpus-measured: 1/689 full matches without this rule, 240 with it).
  static bool langMatches(String name, Set<AudioLanguage> selected) {
    if (selected.isEmpty) return true;
    if (TorrentFilterMatcher.hasMultiAudioTag(name)) return true;
    for (final language in selected) {
      if (language == AudioLanguage.multiAudio) continue; // handled above
      if (TorrentFilterMatcher.nameHasLanguage(name, language)) return true;
    }
    return TorrentFilterMatcher.detectAudioLanguage(name) == null &&
        selected.contains(AudioLanguage.english);
  }

  bool _matchesTier(String name, int sizeBytes, TorrentFilterState tier) {
    if (tier.qualities.isNotEmpty &&
        !tier.qualities.contains(qualityTierForName(name))) {
      return false;
    }
    if (tier.ripSources.isNotEmpty &&
        !tier.ripSources
            .contains(TorrentFilterMatcher.detectRipSource(name))) {
      return false;
    }
    if (tier.languages.isNotEmpty && !langMatches(name, tier.languages)) {
      return false;
    }
    if (tier.sizes.isNotEmpty) {
      // Unknown size (bucket == null, e.g. addon streams with no size) matches
      // no bucket, so it fails size-bearing tiers and sinks to the relaxed
      // "any size" tier — never dropped, since the ladder only reorders.
      final bucket = sizeBucketForBytes(sizeBytes);
      if (bucket == null || !tier.sizes.contains(bucket)) return false;
    }
    return true;
  }

  /// Tier for a release name: index of the strictest tier it satisfies,
  /// or [tierCount] (the floor) for a cam the user didn't ask for.
  /// [allowCamFloor] is off for addon/IPTV streams (see [tierOf]) whose
  /// labels aren't scene names — a stream called "channel.ts" is a transport
  /// stream, not a telesync, and must not sink below everything.
  int tierOfName(String name, {bool allowCamFloor = true, int sizeBytes = 0}) {
    if (!isActive) return 0;
    if (allowCamFloor &&
        !filters.ripSources.contains(RipSourceCategory.cam) &&
        TorrentFilterMatcher.detectRipSource(name) ==
            RipSourceCategory.cam) {
      return tierCount; // §3.3c: cams never outrank a real rip.
    }
    for (var i = 0; i < _tiers.length; i++) {
      if (_matchesTier(name, sizeBytes, _tiers[i])) return i;
    }
    // Unreachable — the last tier is unrestricted — but stay total.
    return tierCount - 1;
  }

  int tierOf(Torrent t) => tierOfName(
        t.name,
        // The cam heuristic (\b(ts|tc|cam)\b …) is meant for torrent scene
        // names; addon/IPTV stream labels false-positive on it (".ts" files,
        // "TC" channel tags), so non-torrent streams skip the floor.
        allowCamFloor: t.streamType == StreamType.torrent,
        sizeBytes: t.sizeBytes,
      );

  /// Stable tier sort: in-tier order (relevance/seeders from curation) is
  /// preserved; identity when [isActive] is false.
  List<Torrent> order(List<Torrent> torrents) {
    if (!isActive || torrents.length < 2) return torrents;
    final tiers = [for (final t in torrents) tierOf(t)];
    final indices = List<int>.generate(torrents.length, (i) => i);
    indices.sort((a, b) {
      final d = tiers[a] - tiers[b];
      return d != 0 ? d : a - b; // index tiebreak == stable
    });
    return [for (final i in indices) torrents[i]];
  }

  /// Per-tier candidate counts, for the overlay note.
  Map<int, int> counts(Iterable<Torrent> torrents) {
    final map = <int, int>{};
    for (final t in torrents) {
      map.update(tierOf(t), (v) => v + 1, ifAbsent: () => 1);
    }
    return map;
  }

  /// Short human summary of the active filters ("1080p · WEB · English").
  String filterSummary() {
    final parts = <String>[
      ...filters.qualities.map(_qualityLabel),
      ...filters.ripSources.map(_ripLabel),
      ...filters.languages.map(_languageLabel),
      ...filters.sizes.map(_sizeLabel),
    ];
    return parts.join(' · ');
  }

  /// Overlay copy for a tier: null for tier 0 (full match — the summary
  /// alone reads right), a "without …" clause for relaxed tiers, and
  /// catch-alls for the unrestricted tier and the cam floor.
  String? describeTier(int tier) {
    if (!isActive || tier <= 0) return null;
    if (tier >= tierCount) return 'low-quality (cam) sources';
    if (tier == tierCount - 1) return 'any available source';
    final dropped = <String>[];
    if (filters.languages.isNotEmpty && _tiers[tier].languages.isEmpty) {
      dropped.add('language');
    }
    if (filters.ripSources.isNotEmpty && _tiers[tier].ripSources.isEmpty) {
      dropped.add('source type');
    }
    if (filters.sizes.isNotEmpty && _tiers[tier].sizes.isEmpty) {
      dropped.add('size');
    }
    if (dropped.isEmpty) return null;
    return 'without ${dropped.join(' or ')} match';
  }

  static String _qualityLabel(QualityTier q) => switch (q) {
    QualityTier.ultraHd => '4K',
    QualityTier.fullHd => '1080p',
    QualityTier.hd => '720p',
    QualityTier.sd => 'SD',
  };

  static String _ripLabel(RipSourceCategory r) => switch (r) {
    RipSourceCategory.web => 'WEB',
    RipSourceCategory.bluRay => 'Blu-ray',
    RipSourceCategory.hdrip => 'HDRip',
    RipSourceCategory.dvdrip => 'DVDRip',
    RipSourceCategory.cam => 'CAM',
    RipSourceCategory.other => 'Other',
  };

  static String _languageLabel(AudioLanguage l) => switch (l) {
    AudioLanguage.multiAudio => 'Multi-audio',
    _ => l.name[0].toUpperCase() + l.name.substring(1),
  };

  static String _sizeLabel(SizeBucket s) => switch (s) {
    SizeBucket.under500mb => '<500MB',
    SizeBucket.mb500to1gb => '500MB–1GB',
    SizeBucket.gb1to1p5 => '1–1.5GB',
    SizeBucket.gb1p5to2p5 => '1.5–2.5GB',
    SizeBucket.gb2p5to4 => '2.5–4GB',
    SizeBucket.gb4to6 => '4–6GB',
    SizeBucket.gb6to10 => '6–10GB',
    SizeBucket.gb10to20 => '10–20GB',
    SizeBucket.gb20to40 => '20–40GB',
    SizeBucket.over40gb => '>40GB',
  };
}
