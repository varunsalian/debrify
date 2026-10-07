import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditProfilePhoneForm {
  final EditProfileDependencies _deps;
  EditProfilePhoneForm(this._deps);
  EditProfileOwners get _owners => _deps.owners;
  EditProfileSections get _sections => _deps.sections();
  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(_deps.context()).textTheme.labelSmall?.copyWith(
        letterSpacing: 1.8,
        color: Theme.of(_deps.context()).colorScheme.primary,
      ),
    ),
  );
  Widget build(BuildContext context) {
    if (PlatformUtil.isTelevision)
      return _sections.tvEditor.buildTvEditor(context);

    final editableFeatures = ProfileFeature.values.where(
      (feature) =>
          feature != ProfileFeature.manageProfiles ||
          _owners.form.role == UserProfileRole.admin,
    );
    return PopScope(
      canPop: !_owners.form.saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _deps.profile() == null ? 'Create profile' : 'Edit profile',
          ),
          actions: [
            TextButton(
              onPressed: _owners.form.saving ? null : _sections.save.save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: Focus(
          descendantsAreFocusable: !_owners.form.saving,
          descendantsAreTraversable: !_owners.form.saving,
          child: AbsorbPointer(
            absorbing: _owners.form.saving,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_owners.form.saving) const LinearProgressIndicator(),
                _sections.phone._sectionLabel('Avatar'),
                _sections.phoneParts.buildAvatarSection(),
                _sections.phone._sectionLabel('Identity'),
                TvTextField(
                  controller: _owners.form.name,
                  autofocus: true,
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(40),
                  ],
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                if (_deps.profile() == null)
                  SwitchListTile(
                    value: _owners.form.copyDefaults,
                    title: const Text('Copy appearance and playback defaults'),
                    subtitle: const Text(
                      'Does not copy accounts, history, downloads, paths, or IDs.',
                    ),
                    onChanged: (value) =>
                        _deps.setState(() => _owners.form.copyDefaults = value),
                  ),
                _sections.phone._sectionLabel('Role'),
                _sections.phoneParts.buildRoleCards(),
                if (_deps.showFeaturePolicyControls) ...[
                  const SizedBox(height: 12),
                  for (final feature in editableFeatures)
                    CheckboxListTile(
                      value:
                          _owners.form.features.contains(feature) &&
                          ProfilePolicy(
                            enabled: _owners.form.features,
                          ).allows(_owners.form.role, feature),
                      title: Text(_featureLabel(feature)),
                      onChanged: (enabled) {
                        _deps.setState(() {
                          if (enabled == true) {
                            _owners.form.features.add(feature);
                          } else {
                            _owners.form.features.remove(feature);
                          }
                        });
                      },
                    ),
                ],
                _sections.phone._sectionLabel('Lock'),
                TvTextField(
                  controller: _owners.form.pin,
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
                SwitchListTile(
                  value: _owners.form.lockOnResume,
                  title: const Text('Lock when the app resumes'),
                  onChanged: (value) =>
                      _deps.setState(() => _owners.form.lockOnResume = value),
                ),
                DropdownButtonFormField<int>(
                  initialValue: _owners.form.inactivityMinutes,
                  decoration: const InputDecoration(labelText: 'Auto-lock'),
                  items: const <DropdownMenuItem<int>>[
                    DropdownMenuItem(value: 0, child: Text('Never')),
                    DropdownMenuItem(value: 5, child: Text('After 5 minutes')),
                    DropdownMenuItem(
                      value: 15,
                      child: Text('After 15 minutes'),
                    ),
                    DropdownMenuItem(
                      value: 30,
                      child: Text('After 30 minutes'),
                    ),
                    DropdownMenuItem(value: 60, child: Text('After 1 hour')),
                  ],
                  onChanged: (value) => _deps.setState(
                    () => _owners.form.inactivityMinutes = value ?? 0,
                  ),
                ),
                _sections.phone._sectionLabel('Access'),
                if (_owners.access.setupLoadError != null)
                  ListTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: Text(_owners.access.setupLoadError!),
                    trailing: TextButton(
                      onPressed: _sections.setup.loadSetupOptions,
                      child: const Text('Retry'),
                    ),
                  )
                else if (_owners.access.engines == null)
                  const LinearProgressIndicator()
                else ...[
                  _sections.access.buildEngineGroup(),
                  ..._sections.access.buildConnectionGroups(),
                ],
                if (_deps.profile() != null) ...[
                  _sections.phone._sectionLabel('Data'),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('Diagnostics'),
                    subtitle: const Text(
                      'Registry, generation and lease state',
                    ),
                    onTap: _sections.adminActions.showDiagnostics,
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _featureLabel(ProfileFeature feature) {
    final spaced = feature.name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)!.toLowerCase()}',
    );
    return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }
}
