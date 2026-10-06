import 'package:debrify/features/edit_profile/models/edit_profile_tv_section.dart';
import 'package:debrify/features/edit_profile/presentation/edit_profile_tv_surfaces.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';

class EditProfileTvEditor {
  final EditProfileDependencies _deps;
  EditProfileTvEditor(this._deps);
  EditProfileOwners get _owners => _deps.owners;
  EditProfileSections get _sections => _deps.sections();
  Widget buildTvEditor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_owners.form.saving,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          leading: Navigator.of(context).canPop()
              ? Focus(
                  canRequestFocus: false,
                  onKeyEvent: (_, event) {
                    final direction = _sections.tvNav.tvDirection(event);
                    if (direction == null) return KeyEventResult.ignored;
                    if (direction == TraversalDirection.down ||
                        direction == TraversalDirection.right) {
                      _owners.tv.tvTabFocusNodes[_owners.tv.tvSection.index]
                          .requestFocus();
                    }
                    return KeyEventResult.handled;
                  },
                  child: IconButton(
                    focusNode: _owners.tv.tvBackFocus,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: _owners.form.saving
                        ? null
                        : () => Navigator.maybePop(context),
                    icon: const BackButtonIcon(),
                  ),
                )
              : null,
          title: Text(
            _deps.profile() == null ? 'Create profile' : 'Edit profile',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        body: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Focus(
            descendantsAreFocusable: !_owners.form.saving,
            descendantsAreTraversable: !_owners.form.saving,
            child: AbsorbPointer(
              absorbing: _owners.form.saving,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 32, 24),
                child: Column(
                  children: [
                    if (_owners.form.saving) const LinearProgressIndicator(),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sections.tvEditor._buildTvSectionRail(colors),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Focus(
                              focusNode: _owners.tv.tvContentFocus,
                              onKeyEvent: (_, event) {
                                // Let text editing and the TV keyboard consume
                                // caret keys; field edge callbacks own exits.
                                if (FocusManager.instance.primaryFocus?.context
                                        ?.findAncestorWidgetOfExactType<
                                          EditableText
                                        >() !=
                                    null) {
                                  return KeyEventResult.ignored;
                                }
                                final direction = _sections.tvNav.tvDirection(
                                  event,
                                );
                                if (direction == null) {
                                  return KeyEventResult.ignored;
                                }
                                _sections.tvNav.moveTvContent(direction);
                                return KeyEventResult.handled;
                              },
                              // OK enters the pane on key-down; its remaining
                              // repeats must not activate a stock form control.
                              child: TvHeldKeyGuard(
                                child: KeyedSubtree(
                                  key: ValueKey(_owners.tv.tvSection),
                                  child: switch (_owners.tv.tvSection) {
                                    EditProfileTvSection.profile =>
                                      _sections.tvProfile
                                          .buildTvProfileSection(),
                                    EditProfileTvSection.pages =>
                                      _sections.tvPanes.buildTvPagesSection(),
                                    EditProfileTvSection.lock =>
                                      _sections.tvPanes.buildTvLockSection(),
                                    EditProfileTvSection.access =>
                                      _sections.tvPanes.buildTvAccessSection(),
                                    EditProfileTvSection.data =>
                                      _sections.tvPanes.buildTvDataSection(),
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTvSectionRail(ColorScheme colors) {
    const tabs = <(EditProfileTvSection, IconData, String)>[
      (EditProfileTvSection.profile, Icons.person_rounded, 'PROFILE'),
      (EditProfileTvSection.pages, Icons.grid_view_rounded, 'PAGES'),
      (EditProfileTvSection.access, Icons.group_rounded, 'ACCESS'),
      (EditProfileTvSection.lock, Icons.lock_rounded, 'LOCK'),
      (EditProfileTvSection.data, Icons.shield_rounded, 'DATA'),
    ];
    final saveIndex = tabs.length;
    Widget railItem({
      required int index,
      required Widget child,
      required VoidCallback? onPressed,
      Key? key,
      bool selected = false,
    }) => SizedBox(
      height: 56,
      child: editProfileTvActionSurface(
        key: key,
        selected: selected,
        autofocus: index == 0,
        focusNode: _owners.tv.tvTabFocusNodes[index],
        onKeyEvent: (_, event) => _sections.tvNav.handleTvRailKey(index, event),
        onPressed: onPressed,
        child: child,
      ),
    );
    Widget railLabel(IconData icon, String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Text(
            label,
            style: Theme.of(_deps.context()).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
    return Container(
      width: 200,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .45)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  for (var index = 0; index < tabs.length; index++) ...[
                    railItem(
                      index: index,
                      key: ValueKey('tv-profile-tab-${tabs[index].$1.name}'),
                      selected: _owners.tv.tvSection == tabs[index].$1,
                      // Up/down previews sections; OK or a click enters the pane.
                      onPressed: () {
                        _sections.tvNav.selectTvSection(tabs[index].$1);
                        _owners.tv.tvTabFocusNodes[index].requestFocus();
                        _sections.tvNav.focusTvContent();
                      },
                      child: railLabel(tabs[index].$2, tabs[index].$3),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Spacer(),
                  railItem(
                    index: saveIndex,
                    key: const ValueKey('tv-profile-save'),
                    onPressed: _owners.form.saving ? null : _sections.save.save,
                    child: railLabel(
                      Icons.check_rounded,
                      _owners.form.saving ? 'SAVING…' : 'SAVE',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
