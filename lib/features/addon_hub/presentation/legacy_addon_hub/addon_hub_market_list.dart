import 'package:debrify/features/addon_hub/models/addon_hub_kinds.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_action_button.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_row.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_market_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:debrify/services/stremio_marketplace_service.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:url_launcher/url_launcher.dart';

typedef AddonHubMarketListDeps = ({
  AddonHubNavigationState navigationState,
  AddonHubMarketState marketState,
  Widget Function({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  })
  emptyState,
  Future<void> Function(AddonHubSource, {bool force}) loadMarket,
  bool Function({required List<String> types, required String name})
  matchesFilters,
  bool Function(MarketplaceAddon) isInstalled,
  AddonHubInstalledState installedState,
  Future<void> Function(MarketplaceAddon, int?) installFromMarket,
  Future<void> Function(MarketplaceAddon) configureInBrowser,
});

class AddonHubMarketList {
  AddonHubMarketList(this._deps);
  final AddonHubMarketListDeps _deps;

  Widget buildMarketList() {
    // Compatibility note pinned above BOTH marketplaces (Official/Community):
    // the catalogs list every Stremio addon, but only these four capability
    // families do anything in Debrify.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
          child: marketCompatNote(),
        ),
        Expanded(child: buildMarketListBody()),
        // Attribution required by the stremio-addons.net API terms — shown only
        // on the Community list AND only when that source actually served the
        // data (not the legacy fallback, which would be a misattribution).
        if (_deps.navigationState.source == AddonHubSource.community &&
            _deps.marketState.marketplace.communityFromNet)
          communityAttribution(),
      ],
    );
  }

  /// Visible credit link back to stremio-addons.net, required by their API's
  /// attribution terms when we display community-directory data.
  Widget communityAttribution() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: GestureDetector(
        onTap: () async {
          final uri = Uri.parse('https://stremio-addons.net');
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {
            /* no browser — the label still credits the source */
          }
        },
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Community addons from '),
              TextSpan(
                text: 'stremio-addons.net',
                style: TextStyle(
                  color: kSeeAllAccent,
                  decoration: TextDecoration.underline,
                  decorationColor: kSeeAllAccent.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11.5,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  /// Slim accent-tinted banner: which addon capabilities Debrify supports.
  Widget marketCompatNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: kSeeAllAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSeeAllAccent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: kSeeAllAccent.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Works with Debrify: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const TextSpan(
                    text:
                        'catalog, HTTP stream, torrent-scraping and '
                        'subtitle addons. Other types install but add '
                        'nothing here.',
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildMarketListBody() {
    if (_deps.marketState.marketLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kSeeAllAccent, strokeWidth: 2),
      );
    }
    if (_deps.marketState.marketError != null) {
      return _deps.emptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load addons',
        subtitle: _deps.marketState.marketError!,
        action: AddonHubHubActionButton(
          icon: Icons.refresh_rounded,
          label: 'Retry',
          primary: true,
          onTap: () =>
              _deps.loadMarket(_deps.navigationState.source, force: true),
        ),
      );
    }
    final items = _deps.marketState.market
        .where((m) => _deps.matchesFilters(types: m.types, name: m.name))
        .toList();
    if (items.isEmpty) {
      return _deps.emptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        subtitle: 'Try a different type or search.',
      );
    }
    // Assign each FOCUSABLE row (installed rows have no button) a nav index so
    // vertical DPAD can hop row-to-row deterministically.
    final navIndexOf = <int, int>{};
    var focusable = 0;
    for (var i = 0; i < items.length; i++) {
      if (!_deps.isInstalled(items[i])) navIndexOf[i] = focusable++;
    }
    _deps.navigationState.marketNav.ensure(focusable);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      // See installed list — keep DPAD off the unbuilt wall.
      scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        final m = items[i];
        final navIndex = navIndexOf[i];
        return AddonHubMarketRow(
          addon: m,
          installed: _deps.isInstalled(m),
          nav: _deps.navigationState.marketNav,
          navIndex: navIndex,
          navCount: focusable,
          warnDebrid:
              !_deps.installedState.hasDebrid && m.resources.contains('stream'),
          onInstall: () => _deps.installFromMarket(m, navIndex),
          onConfigure: () => _deps.configureInBrowser(m),
        );
      },
    );
  }
}
