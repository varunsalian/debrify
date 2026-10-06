import 'package:debrify/features/edit_profile/presentation/edit_profile_tv_surfaces.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

class EditProfileAccessRows {
  final EditProfileDependencies _deps;
  EditProfileAccessRows(this._deps);
  EditProfileOwners get _owners => _deps.owners;
  EditProfileSections get _sections => _deps.sections();
  Widget buildEngineGroup() {
    final engines = _owners.access.engines!;
    final ownEditor = _deps.profile()?.id == _deps.authorization.profileId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sections.access._groupHeader(
          'Torrent engines',
          selected: _owners.access.selectedEngines.length,
          total: engines.length,
          onAll: engines.isEmpty || ownEditor
              ? null
              : () => _deps.setState(
                  () => _owners.access.selectedEngines.addAll(
                    engines.map((engine) => engine.id),
                  ),
                ),
          onNone: engines.isEmpty || ownEditor
              ? null
              : () => _deps.setState(_owners.access.selectedEngines.clear),
        ),
        Text(
          ownEditor
              ? 'Manage engines for the active Admin from Torrent Engines.'
              : 'Each profile keeps an independent copy and settings.',
          style: Theme.of(_deps.context()).textTheme.bodySmall,
        ),
        if (engines.isEmpty)
          const ListTile(
            leading: Icon(Icons.travel_explore_rounded),
            title: Text('No torrent engines installed'),
            subtitle: Text(
              'Install engines in the Admin profile before assigning them.',
            ),
          )
        else
          for (final engine in engines)
            _sections.access._tvAccessFocusRow(
              key: ValueKey('tv-profile-engine-${engine.id}'),
              interactive: !ownEditor,
              child: CheckboxListTile(
                value: _owners.access.selectedEngines.contains(engine.id),
                title: Text(engine.displayName),
                subtitle: !engine.availableFromManager
                    ? Text(
                        'Installed only in ${_deps.profile()?.name ?? 'this profile'}',
                      )
                    : null,
                secondary: const Icon(Icons.travel_explore_rounded),
                onChanged: ownEditor
                    ? null
                    : (selected) => _deps.setState(() {
                        if (selected == true) {
                          _owners.access.selectedEngines.add(engine.id);
                        } else {
                          _owners.access.selectedEngines.remove(engine.id);
                        }
                      }),
              ),
            ),
      ],
    );
  }

  Widget _tvAccessFocusRow({
    Key? key,
    required bool interactive,
    required Widget child,
  }) {
    if (!PlatformUtil.isTelevision) return child;
    return interactive
        ? editProfileEnsureVisibleOnFocus(key: key, child: child)
        : editProfileTvReadOnlyScrollAnchor(key: key, child: child);
  }

  /// The order and membership of the Access groups. Anything a future type
  /// falls out of lands in the final bucket rather than disappearing.
  static const List<(String, Set<ConnectionResourceType>)> accessGroups = [
    (
      'Debrid & cloud',
      {
        ConnectionResourceType.realDebrid,
        ConnectionResourceType.torbox,
        ConnectionResourceType.premiumize,
        ConnectionResourceType.allDebrid,
        ConnectionResourceType.pikpak,
        ConnectionResourceType.webDav,
      },
    ),
    ('Addons', {ConnectionResourceType.stremioAddon}),
    (
      'Trackers & lists',
      {
        ConnectionResourceType.trakt,
        ConnectionResourceType.simkl,
        ConnectionResourceType.mdblist,
      },
    ),
    (
      'Live TV & indexers',
      {
        ConnectionResourceType.iptvM3u,
        ConnectionResourceType.iptvXtream,
        ConnectionResourceType.xmltv,
        ConnectionResourceType.jackett,
        ConnectionResourceType.prowlarr,
      },
    ),
  ];
  List<Widget> buildConnectionGroups() {
    final resources = _owners.access.resources;
    if (resources == null || resources.isEmpty) return const <Widget>[];
    final grouped = <String, List<ConnectionResource>>{};
    for (final resource in resources) {
      // Reddit is a vestige — no sharing section for it.
      if (resource.type == ConnectionResourceType.reddit) continue;
      final label = accessGroups
          .where((group) => group.$2.contains(resource.type))
          .map((group) => group.$1)
          .firstOrNull;
      grouped.putIfAbsent(label ?? 'Other connections', () => []).add(resource);
    }
    final widgets = <Widget>[
      const SizedBox(height: 10),
      Text(
        'Tracker and cloud access can modify the upstream account.',
        style: Theme.of(_deps.context()).textTheme.bodySmall,
      ),
    ];
    for (final (label, _) in accessGroups) {
      final group = grouped[label];
      if (group != null)
        widgets.addAll(_sections.access._connectionGroup(label, group));
    }
    final other = grouped['Other connections'];
    if (other != null) {
      widgets.addAll(
        _sections.access._connectionGroup('Other connections', other),
      );
    }
    return widgets;
  }

  List<Widget> _connectionGroup(String label, List<ConnectionResource> group) {
    final selected = group
        .where(
          (resource) => _owners.access.selectedResources.contains(resource.id),
        )
        .length;
    final editable = _sections.selection.editableIn(group).toList();
    return [
      _sections.access._groupHeader(
        label,
        selected: selected,
        total: group.length,
        onAll: editable.isEmpty
            ? null
            : () => _deps.setState(
                () => editable.forEach(_sections.selection.selectResource),
              ),
        onNone: editable.isEmpty
            ? null
            : () => _deps.setState(
                () => editable.forEach(_sections.selection.deselectResource),
              ),
      ),
      for (final resource in group)
        ..._sections.access._connectionRow(resource),
    ];
  }

  Widget _groupHeader(
    String label, {
    required int selected,
    required int total,
    VoidCallback? onAll,
    VoidCallback? onNone,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 2),
    child: Row(
      children: [
        Text(label, style: Theme.of(_deps.context()).textTheme.titleSmall),
        const SizedBox(width: 8),
        Text(
          '$selected of $total',
          style: Theme.of(_deps.context()).textTheme.labelSmall?.copyWith(
            color: Theme.of(
              _deps.context(),
            ).colorScheme.onSurface.withValues(alpha: .5),
          ),
        ),
        const Spacer(),
        if (onAll != null)
          TextButton(onPressed: onAll, child: const Text('All')),
        if (onNone != null)
          TextButton(onPressed: onNone, child: const Text('None')),
      ],
    ),
  );
  List<Widget> _connectionRow(ConnectionResource resource) {
    final interactive = resource.ownerProfileId != _deps.profile()?.id;
    return [
      _sections.access._tvAccessFocusRow(
        key: ValueKey('tv-profile-connection-${resource.id}'),
        interactive: interactive,
        child: CheckboxListTile(
          value: _owners.access.selectedResources.contains(resource.id),
          title: Text(resource.label),
          subtitle: Text(
            resource.needsReconnect ? 'Reconnect required' : resource.type.name,
          ),
          secondary:
              _deps.profile() != null &&
                  resource.ownerProfileId != _deps.profile()!.id &&
                  _owners.form.role != UserProfileRole.child &&
                  _owners.form.features.contains(
                    ProfileFeature.manageConnections,
                  )
              ? IconButton(
                  tooltip: 'Transfer ownership to this profile',
                  onPressed: () =>
                      _sections.adminActions.transferOwnership(resource),
                  icon: const Icon(Icons.swap_horiz_rounded),
                )
              : const Icon(Icons.key_rounded),
          onChanged: interactive
              ? (selected) => _deps.setState(() {
                  if (selected == true) {
                    _sections.selection.selectResource(resource);
                  } else {
                    _sections.selection.deselectResource(resource);
                  }
                })
              : null,
        ),
      ),
      // Sharing is BINARY now (profile_features spec): the per-resource
      // permission chips are gone. A newly ticked resource gets the mask
      // DERIVED from the profile's feature policy (_defaultResourcePermissions);
      // an already-granted one keeps its stored mask via the load-time seeding,
      // so explicit grants never churn on an unrelated save.
    ];
  }
}
