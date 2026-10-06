import 'package:debrify/features/edit_profile/presentation/edit_profile_tv_surfaces.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditProfileTvPanes {
  final EditProfileDependencies _deps;
  EditProfileTvPanes(this._deps);
  EditProfileOwners get _owners => _deps.owners;
  EditProfileSections get _sections => _deps.sections();
  Widget buildTvPagesSection() {
    bool on(ProfileFeature feature) => ProfilePolicy(
      enabled: _owners.form.features,
    ).allows(_owners.form.role, feature);
    void toggle(ProfileFeature feature) {
      if (_owners.form.saving) return;
      _deps.setState(() {
        _owners.form.policyTouched = true;
        if (!_owners.form.features.remove(feature))
          _owners.form.features.add(feature);
      });
    }

    Widget group(String label) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        label,
        style: Theme.of(_deps.context()).textTheme.labelSmall?.copyWith(
          letterSpacing: 1.8,
          color: Theme.of(_deps.context()).colorScheme.primary,
        ),
      ),
    );
    Widget tile(ProfileFeature feature, String title, String description) {
      final enabled = on(feature);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: editProfileTvActionSurface(
          key: ValueKey('tv-pages-${feature.name}'),
          onPressed: () => toggle(feature),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(_deps.context()).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: Theme.of(_deps.context()).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Icon(
                  enabled
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 28,
                  color: enabled
                      ? Theme.of(_deps.context()).colorScheme.primary
                      : Theme.of(
                          _deps.context(),
                        ).colorScheme.onSurface.withValues(alpha: .35),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: _sections.tvPanes.tvPanel(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pages & abilities',
                  style: Theme.of(_deps.context()).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose what this profile sees and can do. Playback always '
                  'keeps working through its granted sources.',
                  style: Theme.of(_deps.context()).textTheme.bodyLarge,
                ),
                group('SEARCH'),
                tile(
                  ProfileFeature.keywordSearch,
                  'Keyword search',
                  'Raw release search across torrent engines. Off = search '
                      'by title only.',
                ),
                group('SOURCE PAGES'),
                tile(
                  ProfileFeature.debrifyTv,
                  'Debrify TV',
                  'Channels curated on this device.',
                ),
                tile(
                  ProfileFeature.stremioTv,
                  'Stremio TV',
                  'Addon live channels.',
                ),
                tile(ProfileFeature.iptv, 'Live TV', 'IPTV playlists & guide.'),
                tile(ProfileFeature.youtube, 'YouTube', 'The YouTube tab.'),
                group('ABILITIES'),
                tile(
                  ProfileFeature.downloads,
                  'Download & record',
                  "Save things offline and use the DVR. Uses this device's "
                      "storage and your accounts' quotas.",
                ),
                tile(
                  ProfileFeature.remoteControl,
                  'Remote',
                  'Control other Debrify devices and send this setup to '
                      'them.',
                ),
                tile(
                  ProfileFeature.addonsAndEngines,
                  'Manage own sources',
                  'Install or remove their own addons and torrent engines.',
                ),
                tile(
                  ProfileFeature.cloudFiles,
                  'Cloud files',
                  'Browse the raw file lists on connected accounts — '
                      'including yours, if shared.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildTvLockSection() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: _sections.tvPanes.tvPanel(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile lock',
                style: Theme.of(_deps.context()).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose when this profile asks for its PIN.',
                style: Theme.of(_deps.context()).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              TvTextField(
                key: const ValueKey('tv-profile-pin'),
                controller: _owners.form.pin,
                onLeftArrow: _sections.tvNav.returnToTvRail,
                onRightArrow: () =>
                    _sections.tvNav.moveTvContent(TraversalDirection.right),
                onUpArrow: () =>
                    _sections.tvNav.moveTvContent(TraversalDirection.up),
                onDownArrow: () =>
                    _sections.tvNav.moveTvContent(TraversalDirection.down),
                keyboardType: TextInputType.number,
                obscureText: true,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(
                  labelText: _deps.profile()?.hasPin == true
                      ? 'New PIN (leave blank to keep current)'
                      : 'PIN (optional)',
                ),
              ),
              if (_deps.profile()?.hasPin == true ||
                  _deps.profile()?.pinResetRequired == true)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _owners.form.saving
                        ? null
                        : _sections.adminActions.removePinAsAdmin,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Admin reset: remove PIN'),
                  ),
                ),
              const SizedBox(height: 16),
              editProfileEnsureVisibleOnFocus(
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  value: _owners.form.lockOnResume,
                  title: const Text('Lock when the app resumes'),
                  subtitle: const Text('Require the PIN after leaving Debrify'),
                  onChanged: (value) =>
                      _deps.setState(() => _owners.form.lockOnResume = value),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: Theme.of(
                    _deps.context(),
                  ).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 16),
              EditProfileTvAutoLockField(
                value: _owners.form.inactivityMinutes,
                onChanged: (value) => _deps.setState(
                  () => _owners.form.inactivityMinutes = value,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget buildTvAccessSection() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: _sections.tvPanes.tvPanel(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile access',
                style: Theme.of(_deps.context()).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose which engines and connections this profile can use.',
                style: Theme.of(_deps.context()).textTheme.bodyLarge,
              ),
              const SizedBox(height: 14),
              if (_owners.access.setupLoadError != null)
                editProfileEnsureVisibleOnFocus(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: Text(_owners.access.setupLoadError!),
                    trailing: TextButton(
                      onPressed: _sections.setup.loadSetupOptions,
                      child: const Text('Retry'),
                    ),
                  ),
                )
              else if (_owners.access.engines == null)
                const LinearProgressIndicator()
              else ...[
                _sections.access.buildEngineGroup(),
                ..._sections.access.buildConnectionGroups(),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  Widget buildTvDataSection() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: _sections.tvPanes.tvPanel(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile data',
                style: Theme.of(_deps.context()).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _deps.profile() == null
                    ? 'Data tools become available after the profile is created.'
                    : 'Inspect this profile’s registry and session state.',
                style: Theme.of(_deps.context()).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              if (_deps.profile() != null)
                SizedBox(
                  height: 92,
                  child: editProfileTvActionSurface(
                    onPressed: _sections.adminActions.showDiagnostics,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 32),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Diagnostics',
                                  style: Theme.of(
                                    _deps.context(),
                                  ).textTheme.titleLarge,
                                ),
                                const Text(
                                  'Registry, generation and lease state',
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 32),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget tvPanel({required Widget child}) => Material(
    color: Theme.of(_deps.context()).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: Theme.of(
          _deps.context(),
        ).colorScheme.outlineVariant.withValues(alpha: .4),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
