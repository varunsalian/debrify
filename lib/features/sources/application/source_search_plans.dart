import 'package:debrify/models/quick_play_rules.dart';
import 'package:flutter/foundation.dart';

final class SourceSearchPlans {
  const SourceSearchPlans._();

  /// An explicit addon-only profile can search before opening the provider
  /// picker. Mixed modes must include engines and addons before applying the
  /// shared Addon Priority, so they stay on the provider-backed route.
  @visibleForTesting
  static bool shouldSearchAddonsBeforeProvider(
    QuickPlayRules rules, {
    required bool isMovie,
    bool hasPreferredProvider = false,
  }) {
    if (hasPreferredProvider) return false;
    final addonLeading = rules.sourceMode == QuickPlaySourceMode.addonsOnly;
    final exactEpisodeRoute =
        isMovie ||
        !rules.preferSeriesPacks ||
        rules.packPreference == QuickPlayPackPreference.exactEpisodeOnly;
    return addonLeading && exactEpisodeRoute;
  }

  /// Whether the selected source profile permits any Stremio/addon request.
  /// Fast paths must consult this before using a direct addon stream; otherwise
  /// `torrentsOnly` silently behaves like an addon-enabled profile.
  @visibleForTesting
  static bool allowsAddonSearch(QuickPlayRules rules) =>
      rules.sourceMode != QuickPlaySourceMode.torrentsOnly;

  /// Search stages used by the direct-stream/auto-advance flow. Forced and
  /// provider-free calls stay addon-only. Mixed modes query both families at
  /// once; Addon Priority, not network completion or family, chooses first.
  @visibleForTesting
  static List<QuickPlaySourceMode> addonStreamSearchPlan(
    QuickPlayRules rules, {
    bool noProvider = false,
    bool forceAddonOnly = false,
  }) {
    if (noProvider || forceAddonOnly) {
      return const [QuickPlaySourceMode.addonsOnly];
    }
    switch (rules.sourceMode) {
      case QuickPlaySourceMode.torrentsThenAddons:
      case QuickPlaySourceMode.addonsThenTorrents:
      case QuickPlaySourceMode.together:
        return const [QuickPlaySourceMode.together];
      case QuickPlaySourceMode.torrentsOnly:
        return const [QuickPlaySourceMode.torrentsOnly];
      case QuickPlaySourceMode.addonsOnly:
        return const [QuickPlaySourceMode.addonsOnly];
    }
  }

  /// Search services report per-engine/addon failures in-band. An empty pack
  /// result with one of these errors is inconclusive and must not be written to
  /// the multi-hour no-pack cache.
  @visibleForTesting
  static bool packSearchReportedErrors(
    Map<String, dynamic> result,
    QuickPlaySourceMode stage,
  ) {
    final errors = stage == QuickPlaySourceMode.addonsOnly
        ? result['addonErrors'] as Map?
        : result['engineErrors'] as Map?;
    return errors?.isNotEmpty ?? false;
  }

  /// Mixed source modes keep the whole-series bare-ID and season-probing
  /// search combined. Pack curation remains torrent-only; Addon Priority is
  /// applied after probing to choose between engine and addon packs.
  @visibleForTesting
  static List<QuickPlaySourceMode> seriesPackSearchPlan(QuickPlayRules rules) {
    return switch (rules.sourceMode) {
      QuickPlaySourceMode.torrentsThenAddons ||
      QuickPlaySourceMode.addonsThenTorrents ||
      QuickPlaySourceMode.together => const [QuickPlaySourceMode.together],
      QuickPlaySourceMode.torrentsOnly => const [
        QuickPlaySourceMode.torrentsOnly,
      ],
      QuickPlaySourceMode.addonsOnly => const [QuickPlaySourceMode.addonsOnly],
    };
  }
}
