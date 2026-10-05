import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/screens/debrify_tv/widgets/tv_focusable_button.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DebrifyTvGridLayout {
  final DebrifyTvDependencies _deps;
  DebrifyTvGridLayout(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  // Grid Layout for all devices (responsive)
  Widget buildTvGridLayout(double bottomInset) {
    final app = AppThemeScope.of(_deps.context());
    final tv = app.debrifyTv;
    final searchTerm = _owners.focus.channelSearchTerm.trim().toLowerCase();
    final filteredChannels = searchTerm.isEmpty
        ? _owners.library.channels
        : _owners.library.channels
              .where(
                (channel) => channel.name.toLowerCase().contains(searchTerm),
              )
              .toList();

    final screenWidth = MediaQuery.of(_deps.context()).size.width;
    // Responsive padding: smaller on mobile, larger on TV/tablet
    final horizontalPadding = screenWidth < 600 ? 16.0 : 40.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        24,
        horizontalPadding,
        24 + bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered top controls: Play, Search, and overflow.
          _sections.topBar.buildTopActions(),
          // Search field for TV (only show when toggled)
          if (_owners.focus.showSearchBar) ...[
            const SizedBox(height: 16),
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _sections.topBar.handleChannelSearchBarBack,
              child: TvTextField(
                focusNode: _owners.focus.channelSearchFocusNode,
                controller: _owners.focus.channelSearchController,
                style: TextStyle(color: app.core.tx),
                // Shared TV shell/keyboard chrome — settings.accent, with the
                // keyboard's own panel ground and ink.
                accent: app.settings.accent,
                keyboardGround: app.youtube.keyboardPanel,
                keyboardInk: app.core.tx,
                keyboardInkOnAccent: app.inkOn(app.settings.accent),
                onLeftArrow: () => MainPageBridge.focusTvSidebar?.call(),
                onRightArrow: () {
                  if (_owners.focus.channelSearchController.text.isNotEmpty) {
                    _owners.focus.channelSearchClearFocusNode.requestFocus();
                  }
                },
                onUpArrow: () =>
                    _owners.focus.channelSearchButtonFocusNode.requestFocus(),
                onSubmitted: (_) => _sections.topBar.focusBelowChannelSearch(),
                onDownArrow: _sections.topBar.focusBelowChannelSearch,
                decoration: InputDecoration(
                  hintText: 'Search channels...',
                  hintStyle: TextStyle(
                    color: app.core.tx.withValues(alpha: 0.3),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: app.core.tx.withValues(alpha: 0.35),
                  ),
                  suffixIcon: _owners.focus.channelSearchTerm.isNotEmpty
                      ? Focus(
                          focusNode: _owners.focus.channelSearchClearFocusNode,
                          skipTraversal: true,
                          onKeyEvent: (node, event) {
                            if (event is! KeyDownEvent) {
                              return KeyEventResult.ignored;
                            }
                            final key = event.logicalKey;
                            if (key == LogicalKeyboardKey.arrowLeft) {
                              _owners.focus.channelSearchFocusNode
                                  .requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowRight) {
                              _owners.focus.channelMenuFocusNode.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowUp) {
                              _owners.focus.channelSearchButtonFocusNode
                                  .requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (isActivateKey(key) ||
                                key == LogicalKeyboardKey.space) {
                              _sections.topBar.clearChannelSearchAndRefocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Builder(
                            builder: (context) {
                              final ink = AppThemeScope.of(context).core.tx;
                              final focused = Focus.of(context).hasFocus;
                              return Container(
                                decoration: focused
                                    ? BoxDecoration(
                                        borderRadius: app.shape.br(20),
                                        border: Border.all(
                                          color: ink.withValues(alpha: 0.3),
                                          width: 1.5,
                                        ),
                                      )
                                    : null,
                                child: IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: focused
                                        ? ink
                                        : ink.withValues(alpha: 0.5),
                                  ),
                                  onPressed: _sections
                                      .topBar
                                      .clearChannelSearchAndRefocus,
                                ),
                              );
                            },
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: app.shape.br(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: app.shape.br(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: app.shape.br(14),
                    borderSide: BorderSide(
                      // The search field's focused border is `fillStrong` by
                      // design — see the token's own doc.
                      color: tv.fillStrong,
                      width: 1,
                    ),
                  ),
                  filled: true,
                  fillColor: app.core.tx.withValues(alpha: 0.07),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  _deps.setState(() {
                    _owners.focus.channelSearchTerm = value;
                  });
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Favorite channels section (only shows if there are favorites)
          _sections.cards.buildFavoriteChannelsSection(),
          // "All" section header (only show when there are favorites to distinguish)
          if (_owners.library.favoriteChannelIds.isNotEmpty &&
              filteredChannels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.grid_view_rounded,
                    size: 18,
                    color: app.core.tx.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'All Channels',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: app.core.tx.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          // Channel grid (responsive)
          Expanded(
            child: filteredChannels.isEmpty
                ? _sections.grid._buildTvEmptyState()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // Responsive grid: 2 cols on mobile, 3 on tablet, 4 on TV/desktop
                      final width = constraints.maxWidth;
                      int crossAxisCount;
                      double spacing;
                      double childAspectRatio;

                      if (width < 500) {
                        crossAxisCount = 2;
                        spacing = 12;
                        childAspectRatio = 1.4;
                      } else if (width < 800) {
                        crossAxisCount = 3;
                        spacing = 16;
                        childAspectRatio = 1.45;
                      } else {
                        crossAxisCount = 4;
                        spacing = 24;
                        childAspectRatio = 1.5;
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: childAspectRatio,
                        ),
                        itemCount:
                            filteredChannels.length +
                            1, // +1 for "Add Channel" card
                        itemBuilder: (context, index) {
                          if (index == filteredChannels.length) {
                            // "Add Channel" card at the end
                            return KeyedSubtree(
                              key: const ValueKey('add_channel_card'),
                              child: _sections.cards.buildTvAddChannelCard(),
                            );
                          }
                          final channel = filteredChannels[index];
                          return KeyedSubtree(
                            key: ValueKey('channel_${channel.id}'),
                            child: _sections.cards.buildTvChannelCard(channel),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // TV Empty State
  Widget _buildTvEmptyState() {
    final app = AppThemeScope.of(_deps.context());
    final tv = app.debrifyTv;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tv_rounded, size: 120, color: app.core.tx.withAlpha(51)),
          const SizedBox(height: 24),
          Text(
            'No channels yet',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: tv.textDim,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Import channels or create your first channel to get started',
            style: TextStyle(fontSize: 16, color: tv.textFaint),
          ),
          const SizedBox(height: 32),
          TvFocusableButton(
            onPressed: _sections.actions.handleAddChannel,
            icon: Icons.add_rounded,
            label: 'Add Channel',
            backgroundColor: tv.accent,
            width: 200,
          ),
        ],
      ),
    );
  }
}
