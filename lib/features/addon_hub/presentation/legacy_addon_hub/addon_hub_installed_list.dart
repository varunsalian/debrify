import 'package:debrify/features/addon_hub/presentation/addon_hub_installed_row.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_installed_state.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

typedef AddonHubInstalledListDeps = ({
  AddonHubInstalledState installedState,
  bool Function({required List<String> types, required String name})
  matchesFilters,
  Widget Function({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  })
  emptyState,
  AddonHubNavigationState navigationState,
  void Function(StremioAddon) showOptions,
  BuildContext Function() context,
  void Function(VoidCallback) setState,
  bool Function() mounted,
});

class AddonHubInstalledList {
  AddonHubInstalledList(this._deps);
  final AddonHubInstalledListDeps _deps;

  Widget buildInstalledList() {
    if (_deps.installedState.installedLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kSeeAllAccent, strokeWidth: 2),
      );
    }
    final items = _deps.installedState.installed
        .where((a) => _deps.matchesFilters(types: a.types, name: a.displayName))
        .toList();
    return Column(
      children: [
        buildMetadataProviderSetting(),
        Expanded(
          child: items.isEmpty
              ? _deps.emptyState(
                  icon: Icons.extension_outlined,
                  title: _deps.installedState.installed.isEmpty
                      ? 'No addons yet'
                      : 'No matches',
                  subtitle: _deps.installedState.installed.isEmpty
                      ? 'Add a manifest URL, or install one from Discover.'
                      : 'Try a different type or search.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
                  // DPAD can only move to rows that are BUILT — pre-build far
                  // past the viewport so focus never hits an unbuilt-row wall.
                  scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => AddonHubInstalledRow(
                    addon: items[i],
                    focusNode: i == 0
                        ? _deps.navigationState.firstRowFocus
                        : null,
                    warnDebrid:
                        !_deps.installedState.hasDebrid &&
                        items[i].resources.contains('stream'),
                    onTap: () => _deps.showOptions(items[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget buildMetadataProviderSetting() {
    final app = AppThemeScope.of(_deps.context());
    final providers = _deps.installedState.installed
        .where(
          (a) =>
              a.enabled && a.resources.contains('meta') && a.baseUrl.isNotEmpty,
        )
        .toList();
    providers.sort((a, b) {
      final aCinemeta = StremioService.isCinemetaAddon(a);
      final bCinemeta = StremioService.isCinemetaAddon(b);
      if (aCinemeta == bCinemeta) return 0;
      return aCinemeta ? -1 : 1;
    });

    final providerValues = providers
        .map(StremioService.metadataProviderValue)
        .toSet();
    String value;
    if (_deps.installedState.metadataProviderPreference ==
        StremioService.automaticMetadataProvider) {
      value = StremioService.automaticMetadataProvider;
    } else if (_deps.installedState.metadataProviderPreference != null &&
        providerValues.contains(
          _deps.installedState.metadataProviderPreference,
        )) {
      value = _deps.installedState.metadataProviderPreference!;
    } else {
      final cinemeta = providers.where(StremioService.isCinemetaAddon);
      value = cinemeta.isNotEmpty
          ? StremioService.metadataProviderValue(cinemeta.first)
          : StremioService.automaticMetadataProvider;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: app.seeAll.panel,
        borderRadius: app.shape.br(13),
        border: Border.all(color: app.seeAll.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Row(
            children: [
              Icon(
                Icons.badge_outlined,
                size: 20,
                color: app.fade(app.seeAll.accent2, 0.9),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Metadata provider',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Used to enrich details from Trakt, Simkl and MDBList.',
                      style: TextStyle(
                        fontSize: 12,
                        color: app.fade(app.core.tx, 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final picker = StremioDropdown<String>(
            value: value,
            focusNode: _deps.navigationState.metadataFocus,
            isTelevision: _deps.navigationState.isTv,
            onUpArrowPressed: () =>
                _deps.navigationState.typeFocus.requestFocus(),
            onDownArrowPressed: () {
              if (_deps.navigationState.firstRowFocus.context != null) {
                _deps.navigationState.firstRowFocus.requestFocus();
              }
            },
            options: [
              for (final addon in providers)
                StremioDropdownOption(
                  StremioService.metadataProviderValue(addon),
                  StremioService.isCinemetaAddon(addon)
                      ? '${addon.displayName} · Recommended'
                      : addon.displayName,
                ),
              const StremioDropdownOption(
                StremioService.automaticMetadataProvider,
                'Automatic',
              ),
            ],
            onSelected: setMetadataProvider,
          );
          if (constraints.maxWidth < 500) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: picker),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 14),
              picker,
            ],
          );
        },
      ),
    );
  }

  Future<void> setMetadataProvider(String value) async {
    final previous = _deps.installedState.metadataProviderPreference;
    _deps.setState(
      () => _deps.installedState.metadataProviderPreference = value,
    );
    try {
      await _deps.installedState.stremio.setMetadataProviderPreference(value);
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(
        () => _deps.installedState.metadataProviderPreference = previous,
      );
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        SnackBar(
          content: Text('Couldn\'t save metadata provider: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
