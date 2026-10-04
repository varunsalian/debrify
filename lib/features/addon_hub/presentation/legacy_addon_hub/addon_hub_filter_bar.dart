import 'package:debrify/features/addon_hub/models/addon_hub_kinds.dart';
import 'package:debrify/features/addon_hub/presentation/addon_hub_action_button.dart';
import 'package:debrify/features/addon_hub/presentation/legacy_addon_hub/addon_hub_navigation_state.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AddonHubFilterBarDeps = ({
  AddonHubNavigationState navigationState,
  void Function(AddonHubKind) selectKind,
  void Function(AddonHubSource) selectSource,
  void Function(VoidCallback) setState,
  void Function() toggleSearch,
  Future<void> Function() addByUrl,
  Future<void> Function() showActionsMenu,
  Future<void> Function() importEngineFromFile,
  Future<void> Function() loadEngines,
  void Function() focusFirstRow,
  BuildContext Function() context,
});

class AddonHubFilterBar {
  AddonHubFilterBar(this._deps);
  final AddonHubFilterBarDeps _deps;

  Widget buildFilterBar() {
    final isAddon = _deps.navigationState.kind == AddonHubKind.addons;
    return LayoutBuilder(
      builder: (context, c) {
        // Phone-width: the labelled dropdowns + buttons wrap into four ragged
        // rows that eat half the screen. Compose a compact three-row bar
        // instead (labels dropped — the values are self-explanatory) and keep
        // the free-flowing Wrap for wide layouts.
        final narrow = c.maxWidth < 480;

        final manageDd = StremioDropdown<AddonHubKind>(
          // Stremio addons and torrent engines are separate features — the
          // first dropdown picks which one is being managed.
          label: narrow ? null : 'Manage',
          value: _deps.navigationState.kind,
          focusNode: _deps.navigationState.kindFocus,
          isTelevision: _deps.navigationState.isTv,
          options: const [
            StremioDropdownOption(AddonHubKind.addons, 'Stremio Addons'),
            StremioDropdownOption(AddonHubKind.engines, 'Torrent Engines'),
          ],
          onSelected: _deps.selectKind,
        );
        final sourceDd = StremioDropdown<AddonHubSource>(
          label: narrow ? null : 'Source',
          value: _deps.navigationState.source,
          focusNode: _deps.navigationState.sourceFocus,
          isTelevision: _deps.navigationState.isTv,
          options: const [
            StremioDropdownOption(AddonHubSource.installed, 'Installed'),
            StremioDropdownOption(AddonHubSource.official, 'Official'),
            StremioDropdownOption(AddonHubSource.community, 'Community'),
          ],
          onSelected: _deps.selectSource,
        );
        final typeDd = StremioDropdown<String>(
          label: narrow ? null : 'Type',
          value: _deps.navigationState.typeFilter,
          focusNode: _deps.navigationState.typeFocus,
          isTelevision: _deps.navigationState.isTv,
          options: const [
            StremioDropdownOption('', 'All'),
            StremioDropdownOption('movie', 'Movies'),
            StremioDropdownOption('series', 'Series'),
            StremioDropdownOption('channel', 'Channels'),
            StremioDropdownOption('tv', 'TV'),
            StremioDropdownOption('anime', 'Anime'),
          ],
          onSelected: (v) =>
              _deps.setState(() => _deps.navigationState.typeFilter = v),
        );
        final searchBtn = AddonHubHubActionButton(
          focusNode: _deps.navigationState.searchBtnFocus,
          icon: Icons.search_rounded,
          onTap: _deps.toggleSearch,
        );
        final addBtn = AddonHubHubActionButton(
          focusNode: _deps.navigationState.addFocus,
          icon: Icons.add_rounded,
          label: 'Add addon',
          primary: true,
          expand: narrow,
          onTap: _deps.addByUrl,
        );
        final moreBtn = AddonHubHubActionButton(
          focusNode: _deps.navigationState.moreFocus,
          icon: Icons.more_horiz_rounded,
          onTap: _deps.showActionsMenu,
        );
        final importBtn = AddonHubHubActionButton(
          icon: Icons.file_upload_outlined,
          label: 'Import YAML',
          primary: true,
          expand: narrow,
          onTap: _deps.importEngineFromFile,
        );
        final refreshBtn = AddonHubHubActionButton(
          icon: Icons.refresh_rounded,
          onTap: _deps.loadEngines,
        );

        final Widget controls;
        if (narrow) {
          controls = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Row 1: what's being managed + overflow / refresh.
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: manageDd,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (isAddon) moreBtn else refreshBtn,
                ],
              ),
              const SizedBox(height: 10),
              if (isAddon) ...[
                // Row 2: the filters + search toggle.
                Row(
                  children: [
                    sourceDd,
                    const SizedBox(width: 10),
                    typeDd,
                    const Spacer(),
                    searchBtn,
                  ],
                ),
                const SizedBox(height: 10),
                // Row 3: the primary action gets the full width.
                addBtn,
              ] else
                importBtn,
            ],
          );
        } else {
          controls = Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              manageDd,
              if (isAddon) ...[
                sourceDd,
                typeDd,
                searchBtn,
                addBtn,
                moreBtn,
              ] else ...[
                importBtn,
                refreshBtn,
              ],
            ],
          );
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            narrow ? 16 : 24,
            6,
            narrow ? 16 : 24,
            12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // DOWN from any filter-bar control goes deterministically to the
              // search field (when open) or the first list row — geometric
              // traversal's direction-history would otherwise return to whatever
              // row the user last came from.
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                    return KeyEventResult.ignored;
                  }
                  if (event.logicalKey != LogicalKeyboardKey.arrowDown) {
                    return KeyEventResult.ignored;
                  }
                  if (_deps.navigationState.searchOpen ||
                      _deps.navigationState.search.isNotEmpty) {
                    _deps.navigationState.searchFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  _deps.focusFirstRow();
                  return KeyEventResult.handled;
                },
                child: controls,
              ),
              if (isAddon &&
                  (_deps.navigationState.searchOpen ||
                      _deps.navigationState.search.isNotEmpty)) ...[
                const SizedBox(height: 10),
                buildSearchField(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget buildSearchField() {
    // DPAD exits are routed by TvTextField itself: down to the first list row,
    // up to the search button.
    final app = AppThemeScope.of(_deps.context());
    return Container(
      decoration: BoxDecoration(
        color: app.seeAll.panel,
        borderRadius: app.shape.br(11),
        border: Border.all(color: app.seeAll.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 18,
            color: app.fade(app.core.tx, 0.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TvTextField(
              controller: _deps.navigationState.searchController,
              focusNode: _deps.navigationState.searchFocus,
              style: const TextStyle(fontSize: 13),
              cursorColor: app.seeAll.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search addons',
                hintStyle: TextStyle(color: app.fade(app.core.tx, 0.35)),
              ),
              onSubmitted: (_) => _deps.focusFirstRow(),
              onDownArrow: _deps.focusFirstRow,
              onUpArrow: () =>
                  _deps.navigationState.searchBtnFocus.requestFocus(),
            ),
          ),
          GestureDetector(
            onTap: () => _deps.setState(() {
              _deps.navigationState.searchController.clear();
              _deps.navigationState.searchOpen = false;
            }),
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: app.fade(app.core.tx, 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
