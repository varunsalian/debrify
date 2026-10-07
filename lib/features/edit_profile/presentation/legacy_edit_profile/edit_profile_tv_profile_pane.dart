import 'package:debrify/features/edit_profile/presentation/edit_profile_tv_surfaces.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/profile_avatar.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_avatar_policy.dart';
import 'package:debrify/widgets/profiles/profile_art.dart';
import 'package:debrify/widgets/profiles/profile_avatar_view.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditProfileTvProfilePane {
  final EditProfileDependencies _deps;
  EditProfileTvProfilePane(this._deps);
  EditProfileOwners get _owners => _deps.owners;
  EditProfileSections get _sections => _deps.sections();
  Widget buildTvProfileSection() {
    final colors = Theme.of(_deps.context()).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 230,
          child: _sections.tvProfile._buildTvProfilePreview(colors),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: _sections.tvPanes.tvPanel(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Choose an avatar',
                        style: Theme.of(_deps.context()).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (ProfileAvatarPolicy.userImagesSupported)
                        editProfileEnsureVisibleOnFocus(
                          child: OutlinedButton.icon(
                            onPressed: _owners.form.saving
                                ? null
                                : _sections.avatar.pickAvatarImage,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text(
                              'Choose image or GIF (this device only)',
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_owners.form.pendingAvatarBytes != null &&
                      ProfileAvatarPolicy.userImagesSupported)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _owners.form.saving
                            ? null
                            : () => _deps.setState(
                                () => _owners.form.pendingAvatarBytes = null,
                              ),
                        icon: const Icon(Icons.undo_rounded),
                        label: const Text('Discard picked image'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final art in ProfileArtRegistry.all)
                        _sections.tvProfile._tvAvatarTile(
                          keyName: 'art:${art.id}',
                          label: art.label,
                        ),
                      for (final iconKey in ProfileAvatar.legacyIconIds)
                        _sections.tvProfile._tvAvatarTile(
                          keyName: iconKey,
                          label: iconKey,
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Name',
                    style: Theme.of(_deps.context()).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TvTextField(
                    key: const ValueKey('tv-profile-name'),
                    controller: _owners.form.name,
                    onLeftArrow: _sections.tvNav.returnToTvRail,
                    onRightArrow: () =>
                        _sections.tvNav.moveTvContent(TraversalDirection.right),
                    onUpArrow: () =>
                        _sections.tvNav.moveTvContent(TraversalDirection.up),
                    onDownArrow: () =>
                        _sections.tvNav.moveTvContent(TraversalDirection.down),
                    onChanged: (_) => _deps.setState(() {}),
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(40),
                    ],
                    decoration: const InputDecoration(hintText: 'Profile name'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Role',
                    style: Theme.of(_deps.context()).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _sections.tvProfile._buildTvRoleCards(),
                  if (_deps.profile() == null) ...[
                    const SizedBox(height: 14),
                    editProfileEnsureVisibleOnFocus(
                      child: SwitchListTile(
                        value: _owners.form.copyDefaults,
                        title: const Text(
                          'Copy appearance and playback defaults',
                        ),
                        onChanged: (value) => _deps.setState(
                          () => _owners.form.copyDefaults = value,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTvProfilePreview(ColorScheme colors) =>
      _sections.tvPanes.tvPanel(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 420;
            final avatarSize = compact ? 118.0 : 164.0;
            return Padding(
              padding: EdgeInsets.all(compact ? 16 : 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(compact ? 22 : 28),
                    child: SizedBox(
                      width: avatarSize,
                      height: avatarSize,
                      child: _owners.form.pendingAvatarBytes != null
                          ? Image.memory(
                              _owners.form.pendingAvatarBytes!,
                              fit: BoxFit.cover,
                            )
                          : ProfileAvatarView(
                              profileId:
                                  _deps.profile()?.id ?? 'staging-preview',
                              avatarKey: _owners.form.avatarKey,
                              role: _owners.form.role,
                              name: _owners.form.name.text.isEmpty
                                  ? '?'
                                  : _owners.form.name.text,
                              focused: true,
                            ),
                    ),
                  ),
                  SizedBox(height: compact ? 12 : 24),
                  Text(
                    _owners.form.name.text.trim().isEmpty
                        ? 'New profile'
                        : _owners.form.name.text.trim(),
                    key: const Key('tv-profile-name-preview'),
                    textAlign: TextAlign.center,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: compact ? 8 : 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: colors.primary),
                      color: colors.primary.withValues(alpha: .1),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: compact ? 6 : 8,
                      ),
                      child: Text(
                        _owners.form.role == UserProfileRole.child
                            ? 'Kid'
                            : _owners.form.role.name[0].toUpperCase() +
                                  _owners.form.role.name.substring(1),
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
  Widget _tvAvatarTile({required String keyName, required String label}) {
    final selected =
        _owners.form.pendingAvatarBytes == null &&
        _owners.form.avatarKey == keyName;
    return SizedBox(
      width: 78,
      height: 78,
      child: Tooltip(
        message: label,
        child: editProfileTvActionSurface(
          key: ValueKey('tv-profile-avatar-$keyName'),
          selected: selected,
          onPressed: () => _deps.setState(() {
            _owners.form.avatarKey = keyName;
            _owners.form.pendingAvatarBytes = null;
          }),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ProfileAvatarView(
              profileId: _deps.profile()?.id ?? 'staging-preview',
              avatarKey: keyName,
              role: _owners.form.role,
              name: label,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTvRoleCards() {
    const descriptions = <UserProfileRole, (String, String, IconData)>{
      UserProfileRole.admin: (
        'Admin',
        'Full control',
        Icons.admin_panel_settings,
      ),
      UserProfileRole.member: ('Member', 'No profile management', Icons.group),
      UserProfileRole.child: ('Kid', 'Limited content', Icons.child_care),
    };
    Widget card(UserProfileRole role) => editProfileTvActionSurface(
      key: ValueKey('tv-profile-role-${role.name}'),
      selected: _owners.form.role == role,
      onPressed: () => _sections.selection.setRole(role),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(descriptions[role]!.$3, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    descriptions[role]!.$1,
                    style: Theme.of(_deps.context()).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    descriptions[role]!.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(_deps.context()).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // The side rail leaves the form pane narrow on smaller viewports —
        // three cards abreast stop fitting, so they stack.
        if (constraints.maxWidth < 620) {
          return Column(
            children: [
              for (final role in UserProfileRole.values) ...[
                SizedBox(height: 72, width: double.infinity, child: card(role)),
                if (role != UserProfileRole.child) const SizedBox(height: 10),
              ],
            ],
          );
        }
        return SizedBox(
          height: 84,
          child: Row(
            children: [
              for (final role in UserProfileRole.values) ...[
                Expanded(child: card(role)),
                if (role != UserProfileRole.child) const SizedBox(width: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}
