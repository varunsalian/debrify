import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/profile_avatar.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_avatar_policy.dart';
import 'package:debrify/widgets/profiles/profile_art.dart';
import 'package:debrify/widgets/profiles/profile_avatar_view.dart';
import 'package:flutter/material.dart';

class EditProfilePhoneParts {
  final EditProfileDependencies _deps;
  EditProfilePhoneParts(this._deps);
  EditProfileOwners get _owners => _deps.owners;
  EditProfileSections get _sections => _deps.sections();
  Widget buildAvatarSection() {
    final pending = _owners.form.pendingAvatarBytes;
    final userImages = ProfileAvatarPolicy.userImagesSupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 84,
                height: 84,
                child: pending != null
                    ? Image.memory(
                        pending,
                        fit: BoxFit.cover,
                        cacheWidth: 168,
                        cacheHeight: 168,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xFF31435F),
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      )
                    : ProfileAvatarView(
                        // A brand-new profile has no id yet; any safe id maps
                        // to a nonexistent directory and the view falls back.
                        profileId: _deps.profile()?.id ?? 'staging-preview',
                        avatarKey: _owners.form.avatarKey,
                        role: _owners.form.role,
                        name: _owners.form.name.text.isEmpty
                            ? '?'
                            : _owners.form.name.text,
                        focused: true,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (userImages)
                    OutlinedButton.icon(
                      onPressed: _owners.form.saving
                          ? null
                          : _sections.avatar.pickAvatarImage,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text(
                        'Choose image or GIF (this device only)',
                      ),
                    ),
                  if (pending != null)
                    TextButton.icon(
                      onPressed: _owners.form.saving
                          ? null
                          : () => _deps.setState(
                              () => _owners.form.pendingAvatarBytes = null,
                            ),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Discard picked image'),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final art in ProfileArtRegistry.all)
              _sections.phoneParts._artTile(
                key: 'art:${art.id}',
                tooltip: art.label,
                child: ProfileAvatarView(
                  profileId: _deps.profile()?.id ?? 'staging-preview',
                  avatarKey: 'art:${art.id}',
                  role: _owners.form.role,
                  name: art.label,
                ),
              ),
            for (final iconKey in ProfileAvatar.legacyIconIds)
              _sections.phoneParts._artTile(
                key: iconKey,
                tooltip: iconKey,
                child: ProfileAvatarView(
                  profileId: _deps.profile()?.id ?? 'staging-preview',
                  avatarKey: iconKey,
                  role: _owners.form.role,
                  name: iconKey,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _artTile({
    required String key,
    required String tooltip,
    required Widget child,
  }) {
    final selected =
        _owners.form.pendingAvatarBytes == null &&
        _owners.form.avatarKey == key;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _owners.form.saving
            ? null
            : () => _deps.setState(() {
                _owners.form.avatarKey = key;
                _owners.form.pendingAvatarBytes = null;
              }),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              width: 2.5,
              color: selected
                  ? Theme.of(_deps.context()).colorScheme.primary
                  : Colors.transparent,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }

  Widget buildRoleCards() {
    const descriptions = <UserProfileRole, (String, String)>{
      UserProfileRole.admin: (
        'Admin',
        'Full control, including profiles and connections',
      ),
      UserProfileRole.member: ('Member', 'Everything except managing profiles'),
      UserProfileRole.child: ('Kid', 'Limited features, no adult content'),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 560;
        final cards = [
          for (final role in UserProfileRole.values)
            _sections.phoneParts._roleCard(
              role,
              descriptions[role]!.$1,
              descriptions[role]!.$2,
              horizontal,
            ),
        ];
        return horizontal
            ? Row(children: [for (final card in cards) Expanded(child: card)])
            : Column(children: cards);
      },
    );
  }

  Widget _roleCard(
    UserProfileRole role,
    String title,
    String description,
    bool horizontal,
  ) {
    final selected = _owners.form.role == role;
    final colors = Theme.of(_deps.context()).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        right: horizontal ? 8 : 0,
        bottom: horizontal ? 0 : 8,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _owners.form.saving
            ? null
            : () => _sections.selection.setRole(role),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? colors.primaryContainer
                : colors.surfaceContainerHighest.withValues(alpha: .45),
            border: Border.all(
              width: 2,
              color: selected ? colors.primary : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(_deps.context()).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(_deps.context()).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    _deps.context(),
                  ).colorScheme.onSurface.withValues(alpha: .7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
