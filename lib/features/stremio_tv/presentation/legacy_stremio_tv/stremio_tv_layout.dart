import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_empty_state.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_tuner.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// D2: a move-only extraction cannot split the original build method.
// Exit: a separately reviewed header/channel paint decomposition with goldens.
class StremioTvLayout {
  StremioTvLayout(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;
  StremioTvSections get _sections => _deps.sections;
  // ============================================================================
  // Build
  // ============================================================================

  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = AppThemeScope.of(context);

    return Scaffold(
      // Match the Home board: sit the whole screen on the same cinematic
      // indigo→near-black wash instead of a flat black, so the tuner reads as
      // part of the same app rather than a separate dark surface.
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(gradient: app.home.wash),
        child: _owners.library.loading
            ? _sections.chrome.buildLoadingSkeleton()
            : Column(
                children: [
                  // Premium header bar
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          app.home.bg,
                          app.home.bg.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Collapsible search field
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: _owners.focus.showSearchField
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Focus(
                                    canRequestFocus: false,
                                    skipTraversal: true,
                                    onKeyEvent: _sections
                                        .navigation
                                        .handleSearchBarBack,
                                    child: TvTextField(
                                      controller:
                                          _owners.focus.searchController,
                                      focusNode: _owners.focus.searchFocusNode,
                                      style: TextStyle(color: app.core.tx),
                                      accent: app.youtube.focus,
                                      keyboardGround: app.youtube.keyboardPanel,
                                      keyboardInk: app.core.tx,
                                      keyboardInkOnAccent: app.inkOn(
                                        app.youtube.focus,
                                      ),
                                      onSubmitted: (_) => _owners
                                          .focus
                                          .searchBtnFocusNode
                                          .requestFocus(),
                                      onDownArrow: () => _owners
                                          .focus
                                          .searchBtnFocusNode
                                          .requestFocus(),
                                      onUpArrow: () {
                                        // Search bar is at the top — nothing above
                                      },
                                      onLeftArrow: () =>
                                          MainPageBridge.focusTvSidebar?.call(),
                                      onRightArrow: () {
                                        // Nothing to the right — consume
                                      },
                                      decoration: InputDecoration(
                                        hintText: 'Search channels...',
                                        hintStyle: TextStyle(
                                          color: app.core.tx.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                        prefixIcon: Icon(
                                          Icons.search_rounded,
                                          color: app.core.tx.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                        suffixIcon:
                                            _owners.focus.searchQuery.isNotEmpty
                                            ? IconButton(
                                                icon: Icon(
                                                  Icons.close_rounded,
                                                  color: app.core.tx.withValues(
                                                    alpha: 0.5,
                                                  ),
                                                ),
                                                onPressed: () {
                                                  _owners.focus.searchController
                                                      .clear();
                                                  _deps.setState(() {
                                                    _owners
                                                            .focus
                                                            .showSearchField =
                                                        false;
                                                  });
                                                },
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
                                            color: app.core.tx.withValues(
                                              alpha: 0.15,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                        filled: true,
                                        fillColor: app.core.tx.withValues(
                                          alpha: 0.07,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                      ),
                                      textInputAction: TextInputAction.search,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Search toggle button
                            Focus(
                              focusNode: _owners.focus.searchBtnFocusNode,
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent) {
                                  return KeyEventResult.ignored;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowRight) {
                                  _owners.focus.menuFocusNode.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowLeft) {
                                  MainPageBridge.focusTvSidebar?.call();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowUp) {
                                  if (_owners.focus.showSearchField) {
                                    _owners.focus.searchFocusNode
                                        .requestFocus();
                                  }
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowDown) {
                                  _sections.navigation.focusDialFromHeader();
                                  return KeyEventResult.handled;
                                }
                                if (isActivateKey(event.logicalKey)) {
                                  _deps.setState(() {
                                    _owners.focus.showSearchField =
                                        !_owners.focus.showSearchField;
                                  });
                                  if (_owners.focus.showSearchField) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _owners.focus.searchFocusNode
                                              .requestFocus();
                                        });
                                  }
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: GestureDetector(
                                onTap: () {
                                  _deps.setState(() {
                                    _owners.focus.showSearchField =
                                        !_owners.focus.showSearchField;
                                  });
                                  if (_owners.focus.showSearchField) {
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          _owners.focus.searchFocusNode
                                              .requestFocus();
                                        });
                                  }
                                },
                                child: ListenableBuilder(
                                  listenable: _owners.focus.searchBtnFocusNode,
                                  builder: (context, _) =>
                                      _sections.chrome.headerButton(
                                        focused: _owners
                                            .focus
                                            .searchBtnFocusNode
                                            .hasFocus,
                                        active:
                                            _owners.focus.showSearchField ||
                                            _owners
                                                .focus
                                                .searchQuery
                                                .isNotEmpty,
                                        child: Icon(
                                          Icons.search_rounded,
                                          size: 20,
                                          color:
                                              (_owners
                                                      .focus
                                                      .searchBtnFocusNode
                                                      .hasFocus ||
                                                  _owners
                                                      .focus
                                                      .showSearchField ||
                                                  _owners
                                                      .focus
                                                      .searchQuery
                                                      .isNotEmpty)
                                              ? app.core.tx
                                              : app.core.tx.withValues(
                                                  alpha: 0.5,
                                                ),
                                        ),
                                      ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Options button
                            Focus(
                              focusNode: _owners.focus.menuFocusNode,
                              onKeyEvent: (node, event) {
                                if (event is! KeyDownEvent) {
                                  return KeyEventResult.ignored;
                                }
                                if (_owners.focus.menuController.isOpen) {
                                  if (event.logicalKey ==
                                          LogicalKeyboardKey.escape ||
                                      event.logicalKey ==
                                          LogicalKeyboardKey.goBack) {
                                    _owners.focus.menuController.close();
                                    _owners.focus.menuFocusNode.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowUp) {
                                  if (_owners.focus.showSearchField) {
                                    _owners.focus.searchFocusNode
                                        .requestFocus();
                                  }
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowRight) {
                                  if (_owners
                                      .settings
                                      .availableProviders
                                      .isNotEmpty) {
                                    _owners.focus.providerFocusNode
                                        .requestFocus();
                                  }
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowLeft) {
                                  _owners.focus.searchBtnFocusNode
                                      .requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowDown) {
                                  _sections.navigation.focusDialFromHeader();
                                  return KeyEventResult.handled;
                                }
                                if (isActivateKey(event.logicalKey)) {
                                  _owners.focus.menuController.open();
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              },
                              child: ListenableBuilder(
                                listenable: _owners.focus.menuFocusNode,
                                builder: (context, child) => MenuAnchor(
                                  controller: _owners.focus.menuController,
                                  menuChildren: [
                                    _sections.chrome.topMenuItem(
                                      autofocus: true,
                                      leadingIcon: const Icon(
                                        Icons.shuffle_rounded,
                                      ),
                                      controller: _owners.focus.menuController,
                                      anchorFocusNode:
                                          _owners.focus.menuFocusNode,
                                      closeOnArrowUp: true,
                                      onPressed: () {
                                        _deps.setState(
                                          () => _owners.library.mixSalt =
                                              (_owners.library.mixSalt + 1) %
                                              10,
                                        );
                                      },
                                      label:
                                          'Shuffle (Mix ${_owners.library.mixSalt + 1})',
                                    ),
                                    MenuItemButton(
                                      leadingIcon: const Icon(
                                        Icons.refresh_rounded,
                                      ),
                                      onPressed: _owners.library.refreshing
                                          ? null
                                          : () => _sections.library.refresh(),
                                      child: const Text('Refresh'),
                                    ),
                                    MenuItemButton(
                                      leadingIcon: const Icon(
                                        Icons.tune_rounded,
                                      ),
                                      onPressed: () => _sections.menuActions
                                          .openChannelFilter(),
                                      child: const Text('Filter channels'),
                                    ),
                                    MenuItemButton(
                                      leadingIcon: const Icon(
                                        Icons.settings_rounded,
                                      ),
                                      onPressed: _sections
                                          .settings
                                          .openStremioTvSettings,
                                      child: const Text('Stremio TV Settings'),
                                    ),
                                    SubmenuButton(
                                      focusNode: _owners.focus.submenuFocusNode,
                                      leadingIcon: const Icon(
                                        Icons.playlist_add_rounded,
                                      ),
                                      menuChildren: [
                                        _sections.chrome.submenuItem(
                                          autofocus: true,
                                          icon: Icons.list_rounded,
                                          label: 'Manage',
                                          onPressed: _sections
                                              .menuActions
                                              .openLocalCatalogs,
                                        ),
                                        _sections.chrome.submenuItem(
                                          icon: Icons.file_upload_outlined,
                                          label: 'From File',
                                          onPressed: _sections
                                              .menuActions
                                              .importFromFile,
                                        ),
                                        _sections.chrome.submenuItem(
                                          icon: Icons.link_rounded,
                                          label: 'From URL',
                                          onPressed: _sections
                                              .menuActions
                                              .importFromUrl,
                                        ),
                                        _sections.chrome.submenuItem(
                                          icon: Icons.data_object_rounded,
                                          label: 'Paste JSON',
                                          onPressed: _sections
                                              .menuActions
                                              .importFromJson,
                                        ),
                                        _sections.chrome.submenuItem(
                                          icon: Icons.source_rounded,
                                          label: 'From Repository',
                                          onPressed: _sections
                                              .menuActions
                                              .importFromRepo,
                                        ),
                                        _sections.chrome.submenuItem(
                                          icon: Icons.movie_filter_rounded,
                                          label: 'From Trakt',
                                          onPressed: _sections
                                              .menuActions
                                              .importFromTrakt,
                                        ),
                                        // Hidden for the alpha (kMdblistEnabled)
                                        // and only when connected — no dead import.
                                        if (kMdblistEnabled &&
                                            _owners.settings.mdblistConnected)
                                          _sections.chrome.submenuItem(
                                            icon: Icons
                                                .playlist_add_check_circle_outlined,
                                            label: 'From MDBList',
                                            onPressed: _sections
                                                .menuActions
                                                .importFromMdblist,
                                          ),
                                      ],
                                      child: const Text('Import'),
                                    ),
                                  ],
                                  builder: (context, controller, child) =>
                                      _sections.chrome.headerButton(
                                        focused: _owners
                                            .focus
                                            .menuFocusNode
                                            .hasFocus,
                                        child: Icon(
                                          Icons.more_vert_rounded,
                                          size: 20,
                                          color:
                                              _owners
                                                  .focus
                                                  .menuFocusNode
                                                  .hasFocus
                                              ? app.core.tx
                                              : app.core.tx.withValues(
                                                  alpha: 0.5,
                                                ),
                                        ),
                                        onTap: () {
                                          if (controller.isOpen) {
                                            controller.close();
                                          } else {
                                            controller.open();
                                          }
                                        },
                                      ),
                                ),
                              ),
                            ),
                            if (_owners
                                .settings
                                .availableProviders
                                .isNotEmpty) ...[
                              const SizedBox(width: 10),
                              // Provider selector
                              Focus(
                                focusNode: _owners.focus.providerFocusNode,
                                onKeyEvent: (node, event) {
                                  if (event is! KeyDownEvent) {
                                    return KeyEventResult.ignored;
                                  }
                                  if (_owners
                                      .focus
                                      .providerMenuController
                                      .isOpen) {
                                    if (event.logicalKey ==
                                            LogicalKeyboardKey.escape ||
                                        event.logicalKey ==
                                            LogicalKeyboardKey.goBack) {
                                      _owners.focus.providerMenuController
                                          .close();
                                      _owners.focus.providerFocusNode
                                          .requestFocus();
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowUp) {
                                    if (_owners.focus.showSearchField) {
                                      _owners.focus.searchFocusNode
                                          .requestFocus();
                                    }
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowLeft) {
                                    _owners.focus.menuFocusNode.requestFocus();
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowRight) {
                                    return KeyEventResult.handled;
                                  }
                                  if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowDown) {
                                    _sections.navigation.focusDialFromHeader();
                                    return KeyEventResult.handled;
                                  }
                                  if (isActivateKey(event.logicalKey)) {
                                    _owners.focus.providerMenuController.open();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: ListenableBuilder(
                                  listenable: _owners.focus.providerFocusNode,
                                  builder: (context, child) => MenuAnchor(
                                    controller:
                                        _owners.focus.providerMenuController,
                                    menuChildren: [
                                      _sections.chrome.topMenuItem(
                                        autofocus: true,
                                        leadingIcon: Icon(
                                          _owners.settings.debridProvider ==
                                                  'auto'
                                              ? Icons.check_rounded
                                              : Icons.circle_outlined,
                                        ),
                                        label: _sections.settings
                                            .providerFullLabel('auto'),
                                        onPressed: () => _sections.settings
                                            .setDebridProvider('auto'),
                                        controller: _owners
                                            .focus
                                            .providerMenuController,
                                        anchorFocusNode:
                                            _owners.focus.providerFocusNode,
                                        closeOnArrowUp: true,
                                      ),
                                      ..._owners.settings.availableProviders
                                          .map(
                                            (provider) => MenuItemButton(
                                              leadingIcon: Icon(
                                                _owners
                                                            .settings
                                                            .debridProvider ==
                                                        provider.key
                                                    ? Icons.check_rounded
                                                    : Icons.circle_outlined,
                                              ),
                                              onPressed: () => _sections
                                                  .settings
                                                  .setDebridProvider(
                                                    provider.key,
                                                  ),
                                              child: Text(provider.value),
                                            ),
                                          ),
                                    ],
                                    builder: (context, controller, child) =>
                                        GestureDetector(
                                          onTap: () {
                                            if (controller.isOpen) {
                                              controller.close();
                                            } else {
                                              controller.open();
                                            }
                                          },
                                          child: _sections.chrome.headerButton(
                                            focused: _owners
                                                .focus
                                                .providerFocusNode
                                                .hasFocus,
                                            wide: true,
                                            child: Text(
                                              _sections.settings
                                                  .providerShortLabel(
                                                    _owners
                                                        .settings
                                                        .debridProvider,
                                                  ),
                                              style: TextStyle(
                                                color:
                                                    _owners
                                                        .focus
                                                        .providerFocusNode
                                                        .hasFocus
                                                    ? app.core.tx
                                                    : app.core.tx.withValues(
                                                        alpha: 0.68,
                                                      ),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Channel list
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        if (_owners.library.channels.isEmpty) {
                          return const StremioTvEmptyState();
                        }
                        return ValueListenableBuilder<int>(
                          valueListenable: _owners.library.contentRevision,
                          builder: (context, _, __) {
                            // Computed inside the builder so a revision bump
                            // hands the tuner a fresh snapshot consistent with
                            // the live _channels/_rowFocusNodes it also gets.
                            final filtered =
                                _sections.navigation.filteredChannels;
                            if (filtered.isEmpty &&
                                _owners.focus.searchQuery.isNotEmpty) {
                              return Center(
                                child: Text(
                                  'No channels match "${_owners.focus.searchQuery}"',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            }
                            return StremioTvTuner(
                              controller: _owners.focus.tunerController,
                              channels: filtered,
                              allChannels: _owners.library.channels,
                              rowFocusNodes: _owners.focus.rowFocusNodes,
                              service: _owners.library.service,
                              rotationFor: _sections.library.rotationFor,
                              mixSalt: _owners.library.mixSalt,
                              hideNowPlaying: _owners.settings.hideNowPlaying,
                              autoRefresh: _owners.settings.autoRefresh,
                              isTelevision: _deps.isTelevision(),
                              loadingChannelIds:
                                  _owners.library.loadingChannelIds,
                              ensureLoaded: (channel) {
                                if (!channel.hasItems &&
                                    !_owners.library.loadingChannelIds.contains(
                                      channel.id,
                                    )) {
                                  _sections.library.ensureChannelItemsLoaded(
                                    channel,
                                  );
                                }
                              },
                              onOpenDetail: _sections.actions.openChannelDetail,
                              onPlay: _sections.play.playChannel,
                              // Restore the "max start %" cap on the *displayed*
                              // progress so the bar matches where playback will
                              // actually join (matches the old row's
                              // displayProgress semantics exactly).
                              displayProgress: (channel, rawProgress) {
                                if (_owners.settings.maxStartPercent == 0)
                                  return 0.0;
                                return _sections.resolve.computeStartProgress(
                                      channel.id,
                                      rawProgress,
                                    ) ??
                                    rawProgress;
                              },
                              onToggleFavorite:
                                  _sections.actions.toggleFavorite,
                              onShowGuide: _sections.actions.showGuide,
                              onEditLocal: _sections.actions.editLocalCatalog,
                              onExportLocal:
                                  _sections.actions.copyLocalCatalogJson,
                              onFocusSidebar: () =>
                                  MainPageBridge.focusTvSidebar?.call(),
                              onFocusHeader: () => _owners
                                  .focus
                                  .searchBtnFocusNode
                                  .requestFocus(),
                              onFocusedIndexChanged: (realIndex) {
                                // Bookkeeping only — never read in build(), so
                                // no setState (keeps surfing lag-free) and it
                                // stays current for header↕ navigation even
                                // mid-surf.
                                _owners.focus.focusedIndex = realIndex;
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
