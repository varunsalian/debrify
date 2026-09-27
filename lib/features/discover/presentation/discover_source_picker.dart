import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';
import '../../../widgets/see_all/stremio_dropdown.dart';
import '../models/discover_source_state.dart';

/// Source control shared by Discover's embedded panels. The host owns inventory,
/// selection persistence and the focus node reattached when panels change.
StremioDropdown<String> buildDiscoverSourcePicker({
  required String selected,
  required bool isTelevision,
  required FocusNode focusNode,
  required bool discoveryEnabled,
  required bool mdblistEnabled,
  required bool mdblistAuthenticated,
  required List<StremioAddon> addons,
  required ValueChanged<String> onSelected,
}) => StremioDropdown<String>(
  label: 'Source',
  value: selected,
  isTelevision: isTelevision,
  // TV source identity uses a quiet violet segment; filter values stay white.
  quiet: isTelevision,
  quietAccent: true,
  focusNode: focusNode,
  options: [
    const StremioDropdownOption(DiscoverSources.cw, 'Continue Watching'),
    const StremioDropdownOption(DiscoverSources.trakt, 'Trakt'),
    const StremioDropdownOption(DiscoverSources.simkl, 'Simkl'),
    const StremioDropdownOption(DiscoverSources.jellyfin, 'Jellyfin'),
    const StremioDropdownOption(DiscoverSources.emby, 'Emby'),
    if (discoveryEnabled)
      const StremioDropdownOption(DiscoverSources.tmdb, 'TMDB'),
    // The release gate wins even for an active source. When enabled, retain an
    // already-selected MDBList through auth refresh so its option still exists.
    if (mdblistEnabled &&
        (mdblistAuthenticated || selected == DiscoverSources.mdblist))
      const StremioDropdownOption(DiscoverSources.mdblist, 'MDBList'),
    for (final addon in addons)
      StremioDropdownOption(
        '${DiscoverSources.addonPrefix}${addon.id}',
        addon.displayName,
      ),
  ],
  onSelected: onSelected,
);
