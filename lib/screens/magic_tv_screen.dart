import 'dart:async';

import 'package:debrify/features/debrify_tv/application/debrify_tv_random_start.dart';
import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/models/debrify_tv_kinds.dart';
import 'package:debrify/features/debrify_tv/presentation/debrify_tv_choice_chip.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/debrify_tv/channel.dart';
import '../models/torrent_filter_state.dart';
import '../services/analytics_service.dart';
import '../services/android_tv_player_bridge.dart';
import '../services/main_page_bridge.dart';
import '../theme/app_theme_scope.dart';
import '../utils/debrify_tv_filters.dart';
import '../utils/tv_keys.dart';
import '../widgets/tv_text_field.dart';
import 'debrify_tv/dialogs/spotlight_dialog.dart';
import 'debrify_tv/layouts/spotlight_layout.dart';
import 'debrify_tv/widgets/random_start_slider.dart';
import 'debrify_tv/widgets/switch_row.dart';
import 'debrify_tv/widgets/tv_focusable_button.dart';
import 'debrify_tv/widgets/tv_focusable_card.dart';

class DebrifyTVScreen extends StatefulWidget {
  const DebrifyTVScreen({super.key});

  @override
  State<DebrifyTVScreen> createState() => _DebrifyTVScreenState();
}

class _DebrifyTVScreenState extends State<DebrifyTVScreen> {
  final DebrifyTvOwners _owners = DebrifyTvOwners();
  DebrifyTvSections? _composition;
  DebrifyTvSections get _sections => _composition ??= DebrifyTvSections(
    DebrifyTvDependencies(
      owners: _owners,
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      buildTvGridLayout: buildTvGridLayout,
      showQuickPlayDialog: showQuickPlayDialog,
      showGlobalSettingsDialog: showGlobalSettingsDialog,
    ),
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('magic_tv');
    _owners.focus.channelSearchFocusNode = FocusNode(
      debugLabel: 'DebrifyTVChannelSearch',
    );
    _sections.settings.loadSettings();
    _sections.library
        .loadChannels(); // also warms the Spotlight rail health, once per reload
    _sections.library.loadFavoriteChannels();

    // Register watch channel handler for external calls (e.g., from home screen)
    MainPageBridge.watchDebrifyTvChannel = _sections.library.watchChannelById;
    MainPageBridge.registerDebrifyTvLibraryListener(
      _sections.library.handleSyncedDebrifyTvLibraryChanged,
    );

    // Register TV sidebar focus handler (tab index 3 = Debrify TV)
    _owners.focus.tvContentFocusHandler = () {
      _owners.focus.quickPlayFocusNode.requestFocus();
    };
    MainPageBridge.registerTvContentFocusHandler(
      3,
      _owners.focus.tvContentFocusHandler!,
    );

    // Check for pending auto-play from home screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sections.library.checkPendingAutoPlay();
    });
  }

  @override
  void dispose() {
    _owners.stage.spotlightStatsDebounce?.cancel();
    // Clear watch channel handler
    MainPageBridge.watchDebrifyTvChannel = null;
    MainPageBridge.unregisterDebrifyTvLibraryListener(
      _sections.library.handleSyncedDebrifyTvLibraryChanged,
    );
    if (_owners.focus.tvContentFocusHandler != null) {
      MainPageBridge.unregisterTvContentFocusHandler(
        3,
        _owners.focus.tvContentFocusHandler!,
      );
    }
    // Ensure prefetch loop is stopped if this screen is disposed mid-run
    _owners.prefetch.prefetchStopRequested = true;
    _sections.prefetch.stopPrefetch();
    // Clean up dialog state to avoid dangling context references
    _owners.progress.progressSheetContext = null;
    _owners.progress.progressOpen = false;
    _owners.progress.progress.dispose();
    _owners.library.keywordsController.dispose();
    _owners.focus.channelSearchController.dispose();
    _owners.focus.channelSearchFocusNode.dispose();
    _owners.focus.quickPlayFocusNode.dispose();
    _owners.focus.channelSearchButtonFocusNode.dispose();
    _owners.focus.channelSearchClearFocusNode.dispose();
    _owners.focus.channelMenuFocusNode.dispose();
    AndroidTvPlayerBridge.clearTorboxProvider();
    super.dispose();
  }

  /// Back/Escape ladder for the channel search bar: clear text first, then
  /// close the bar. Sits on an ancestor Focus of the search field so it runs
  /// when the TvTextField shell lets the key bubble.
  KeyEventResult handleChannelSearchBarBack(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_owners.focus.channelSearchController.text.isNotEmpty) {
        _owners.focus.channelSearchController.clear();
        setState(() {
          _owners.focus.channelSearchTerm = '';
        });
        // Clearing unmounts the suffix ✕ — if IT held focus, focus would be
        // stranded; parking on the field covers both cases.
        _owners.focus.channelSearchFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (_owners.focus.showSearchBar) {
        setState(() {
          _owners.focus.showSearchBar = false;
        });
        _owners.focus.channelSearchButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Quality + size pickers for Debrify TV playback. One shared setting for
  /// both channels and quick play, so the same feed rules apply wherever you
  /// start watching. Nothing selected in a row = that facet is off.
  Widget tvFilterChips({StateSetter? dialogSetState}) {
    void applyFilters(DebrifyTvFilters next) {
      setState(() => _owners.settings.tvFilters = next);
      // "At your quality" is computed WITH the filter; stale memos would
      // keep the old filter's count while playback uses the new one.
      _sections.stage.invalidateSpotlightStats();
      dialogSetState?.call(() {});
    }

    void toggleQuality(QualityTier quality) {
      final next = Set<QualityTier>.from(_owners.settings.tvFilters.qualities);
      if (!next.remove(quality)) next.add(quality);
      applyFilters(
        DebrifyTvFilters(
          qualities: next,
          sizes: _owners.settings.tvFilters.sizes,
        ),
      );
      unawaited(
        DebrifyTvStorage.setDebrifyTvFilterQualities(
          next.map((e) => e.name).toList(),
        ),
      );
    }

    void toggleSize(SizeBucket bucket) {
      final next = Set<SizeBucket>.from(_owners.settings.tvFilters.sizes);
      if (!next.remove(bucket)) next.add(bucket);
      applyFilters(
        DebrifyTvFilters(
          qualities: _owners.settings.tvFilters.qualities,
          sizes: next,
        ),
      );
      unawaited(
        DebrifyTvStorage.setDebrifyTvFilterSizes(
          next.map((e) => e.name).toList(),
        ),
      );
    }

    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: AppThemeScope.of(context).debrifyTv.textMeta,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Playback filters',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          'Applies to channels and quick play. If nothing matches, Debrify TV '
          'plays what it can rather than showing an empty channel.',
          style: labelStyle,
        ),
        const SizedBox(height: 10),
        Text('Quality', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final quality in QualityTier.values)
              debrifyTvChoiceChip(
                label: DebrifyTvFilters.qualityLabel(quality),
                selected: _owners.settings.tvFilters.qualities.contains(
                  quality,
                ),
                enabled: !_owners.session.isBusy,
                onPressed: () => toggleQuality(quality),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('File size (per episode/movie)', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final bucket in SizeBucket.values)
              debrifyTvChoiceChip(
                label: DebrifyTvFilters.sizeLabel(bucket),
                selected: _owners.settings.tvFilters.sizes.contains(bucket),
                enabled: !_owners.session.isBusy,
                onPressed: () => toggleSize(bucket),
              ),
          ],
        ),
      ],
    );
  }

  Widget providerChoiceChips(
    DebrifyTvSettingsScope scope, {
    StateSetter? dialogSetState,
  }) {
    final bool isQuickScope = scope == DebrifyTvSettingsScope.quickPlay;
    final String currentProvider = isQuickScope
        ? _owners.settings.quickProvider
        : _owners.settings.provider;

    void handleSelection(String value) {
      if (!_sections.settings.isProviderSelectable(value)) {
        return;
      }
      if (isQuickScope) {
        if (_owners.settings.quickProvider == value) {
          return;
        }
        setState(() {
          _owners.settings.quickProvider = value;
        });
        dialogSetState?.call(() {});
        return;
      }

      if (_owners.settings.provider == value) {
        return;
      }
      setState(() {
        _owners.settings.provider = value;
      });
      dialogSetState?.call(() {});
      unawaited(DebrifyTvStorage.saveDebrifyTvProvider(value));
    }

    Widget providerChip({
      required String value,
      required String label,
      required bool available,
      required String unavailableMessage,
    }) {
      return Tooltip(
        message: available ? 'Use $label for Debrify TV' : unavailableMessage,
        child: debrifyTvChoiceChip(
          label: label,
          selected: currentProvider == value,
          enabled: available && !_owners.session.isBusy,
          onPressed: () => handleSelection(value),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        providerChip(
          value: DebrifyTvConstants.providerRealDebrid,
          label: 'Real Debrid',
          available: _owners.settings.rdAvailable,
          unavailableMessage:
              'Enable Real Debrid and add an API key in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerTorbox,
          label: 'Torbox',
          available: _owners.settings.torboxAvailable,
          unavailableMessage: 'Enable Torbox and add an API key in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerPikPak,
          label: 'PikPak',
          available: _owners.settings.pikpakAvailable,
          unavailableMessage: 'Log in to PikPak in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerPremiumize,
          label: 'Premiumize',
          available: _owners.settings.premiumizeAvailable,
          unavailableMessage:
              'Enable Premiumize and add an API key in Settings.',
        ),
        providerChip(
          value: DebrifyTvConstants.providerAllDebrid,
          label: 'AllDebrid',
          available: _owners.settings.allDebridAvailable,
          unavailableMessage:
              'Enable AllDebrid and add an API key in Settings.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    if (_owners.library.debrifyTvStyle == 'spotlight') {
      return SpotlightLayout(
        view: _sections.stage.buildSpotlightView(),
        bottomInset: bottomInset,
        entryFocusNode: _owners.focus.quickPlayFocusNode,
      );
    }
    // The historical layout, byte-identical under `grid` — the branch calls
    // it unchanged, never a re-implementation.
    return _sections.legacy.buildTvGridLayout(bottomInset);
  }

  void _toggleChannelSearchBar() {
    setState(() {
      _owners.focus.showSearchBar = !_owners.focus.showSearchBar;
      if (_owners.focus.showSearchBar) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _owners.focus.channelSearchFocusNode.requestFocus();
          }
        });
      } else {
        _owners.focus.channelSearchController.clear();
        _owners.focus.channelSearchTerm = '';
      }
    });
  }

  void clearChannelSearchAndRefocus() {
    _owners.focus.channelSearchController.clear();
    setState(() {
      _owners.focus.channelSearchTerm = '';
    });
    _owners.focus.channelSearchFocusNode.requestFocus();
  }

  void focusBelowChannelSearch() {
    final fieldContext = _owners.focus.channelSearchFocusNode.context;
    if (fieldContext != null) {
      FocusScope.of(fieldContext).nextFocus();
    }
  }

  void _handleTopMenuAction(DebrifyTvTopMenuAction action) {
    switch (action) {
      case DebrifyTvTopMenuAction.import:
        _sections.channelImport.handleImportChannels();
        break;
      case DebrifyTvTopMenuAction.export:
        _sections.channelExport.handleExportChannels();
        break;
      case DebrifyTvTopMenuAction.add:
        _sections.actions.handleAddChannel();
        break;
      case DebrifyTvTopMenuAction.deleteAll:
        _sections.actions.handleDeleteAllChannels();
        break;
      case DebrifyTvTopMenuAction.settings:
        showGlobalSettingsDialog();
        break;
    }
  }

  Widget _buildTopActionButton({
    required FocusNode focusNode,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required Color activeColor,

    /// Defaults to the surface's resting control fill (`controlBg`). Nullable
    /// rather than a const default because a token is not a constant.
    Color? inactiveColor,
    bool isActive = false,
    FocusNode? leftFocusNode,
    FocusNode? rightFocusNode,
    bool leftToSidebar = false,
    bool upToSearch = false,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (key == LogicalKeyboardKey.arrowLeft) {
          if (leftToSidebar) {
            MainPageBridge.focusTvSidebar?.call();
          } else {
            leftFocusNode?.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          rightFocusNode?.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (upToSearch && _owners.focus.showSearchBar) {
            _owners.focus.channelSearchFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          onPressed?.call();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final app = AppThemeScope.of(context);
          final tv = app.debrifyTv;
          final disabled = onPressed == null;
          final focused = focusNode.hasFocus;
          final highlighted = !disabled && (focused || isActive);

          return Tooltip(
            message: tooltip,
            child: GestureDetector(
              onTap: onPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  // LEFT LITERAL: the disabled greys. No role holds
                  // `Colors.grey` / grey-at-0.3, and a disabled tone is not
                  // one of this surface's fills.
                  color: disabled
                      ? Colors.grey.withValues(alpha: 0.3)
                      : (focused
                            ? activeColor
                            : (inactiveColor ?? tv.controlBg)),
                  borderRadius: app.shape.br(20),
                  border: focused && !disabled
                      ? Border.all(
                          color: tv.focusRing.withValues(alpha: 0.6),
                          width: 2,
                        )
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: disabled
                      ? Colors.grey
                      : (highlighted
                            ? app.core.tx
                            : app.core.tx.withValues(alpha: 0.5)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopMenuButton() {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final itemStyle = ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? tv.textFaint
            : states.contains(WidgetState.focused)
            ? app.inkOn(app.core.tx)
            : tv.textDim,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? app.core.tx
            : Colors.transparent,
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: app.shape.br(12)),
      ),
    );
    return Focus(
      focusNode: _owners.focus.channelMenuFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;

        if (_owners.focus.channelMenuController.isOpen) {
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack) {
            _owners.focus.channelMenuController.close();
            _owners.focus.channelMenuFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        if (key == LogicalKeyboardKey.arrowLeft) {
          _owners.focus.channelSearchButtonFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          if (_owners.focus.showSearchBar) {
            _owners.focus.channelSearchFocusNode.requestFocus();
          }
          return KeyEventResult.handled;
        }
        if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
          _owners.focus.channelMenuController.open();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _owners.focus.channelMenuFocusNode,
        builder: (context, _) => MenuAnchor(
          controller: _owners.focus.channelMenuController,
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(tv.noticeBg),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(18),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: app.shape.br(18),
                side: BorderSide(color: tv.hairline),
              ),
            ),
          ),
          menuChildren: [
            MenuItemButton(
              autofocus: true,
              style: itemStyle,
              leadingIcon: const Icon(Icons.cloud_download_rounded),
              onPressed: _owners.session.isBusy
                  ? null
                  : () => _handleTopMenuAction(DebrifyTvTopMenuAction.import),
              child: const Text('Import'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.folder_zip_rounded),
              onPressed:
                  _owners.session.isBusy || _owners.library.channels.isEmpty
                  ? null
                  : () => _handleTopMenuAction(DebrifyTvTopMenuAction.export),
              child: const Text('Export Channels'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.add_rounded),
              onPressed: _owners.session.isBusy
                  ? null
                  : () => _handleTopMenuAction(DebrifyTvTopMenuAction.add),
              child: const Text('Add Channel'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.delete_outline_rounded),
              onPressed:
                  _owners.session.isBusy || _owners.library.channels.isEmpty
                  ? null
                  : () =>
                        _handleTopMenuAction(DebrifyTvTopMenuAction.deleteAll),
              child: const Text('Delete All'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.settings_rounded),
              onPressed: () =>
                  _handleTopMenuAction(DebrifyTvTopMenuAction.settings),
              child: const Text('Settings'),
            ),
          ],
          builder: (context, controller, child) {
            final focused = _owners.focus.channelMenuFocusNode.hasFocus;

            return Tooltip(
              message: 'Options',
              child: GestureDetector(
                onTap: () {
                  if (controller.isOpen) {
                    controller.close();
                  } else {
                    controller.open();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: focused ? tv.fillStrong : tv.controlBg,
                    borderRadius: app.shape.br(20),
                    border: focused
                        ? Border.all(
                            color: tv.focusRing.withValues(alpha: 0.6),
                            width: 2,
                          )
                        : null,
                  ),
                  child: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: focused
                        ? app.core.tx
                        : app.core.tx.withValues(alpha: 0.5),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget buildTopActions() {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTopActionButton(
          focusNode: _owners.focus.quickPlayFocusNode,
          icon: Icons.play_arrow_rounded,
          tooltip: 'Play',
          onPressed: _owners.session.isBusy ? null : showQuickPlayDialog,
          activeColor: tv.fillStrong,
          leftToSidebar: true,
          rightFocusNode: _owners.focus.channelSearchButtonFocusNode,
        ),
        const SizedBox(width: 10),
        _buildTopActionButton(
          focusNode: _owners.focus.channelSearchButtonFocusNode,
          icon: Icons.search_rounded,
          tooltip: _owners.focus.showSearchBar
              ? 'Close search'
              : 'Search channels',
          onPressed: _toggleChannelSearchBar,
          activeColor: tv.fillStrong,
          isActive:
              _owners.focus.showSearchBar ||
              _owners.focus.channelSearchTerm.isNotEmpty,
          leftFocusNode: _owners.focus.quickPlayFocusNode,
          rightFocusNode: _owners.focus.channelMenuFocusNode,
          upToSearch: true,
        ),
        const SizedBox(width: 10),
        _buildTopMenuButton(),
      ],
    );
  }

  // Grid Layout for all devices (responsive)
  Widget buildTvGridLayout(double bottomInset) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final searchTerm = _owners.focus.channelSearchTerm.trim().toLowerCase();
    final filteredChannels = searchTerm.isEmpty
        ? _owners.library.channels
        : _owners.library.channels
              .where(
                (channel) => channel.name.toLowerCase().contains(searchTerm),
              )
              .toList();

    final screenWidth = MediaQuery.of(context).size.width;
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
          buildTopActions(),
          // Search field for TV (only show when toggled)
          if (_owners.focus.showSearchBar) ...[
            const SizedBox(height: 16),
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: handleChannelSearchBarBack,
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
                onSubmitted: (_) => focusBelowChannelSearch(),
                onDownArrow: focusBelowChannelSearch,
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
                              clearChannelSearchAndRefocus();
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
                                  onPressed: clearChannelSearchAndRefocus,
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
                  setState(() {
                    _owners.focus.channelSearchTerm = value;
                  });
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Favorite channels section (only shows if there are favorites)
          buildFavoriteChannelsSection(),
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
                ? _buildTvEmptyState()
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
                              child: buildTvAddChannelCard(),
                            );
                          }
                          final channel = filteredChannels[index];
                          return KeyedSubtree(
                            key: ValueKey('channel_${channel.id}'),
                            child: buildTvChannelCard(channel),
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
    final app = AppThemeScope.of(context);
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

  // Favorite Channels Section (horizontal row)
  Widget buildFavoriteChannelsSection() {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    // Get favorite channels from the channels list
    final favoriteChannels = _owners.library.channels
        .where(
          (channel) => _owners.library.favoriteChannelIds.contains(channel.id),
        )
        .toList();

    // Don't show if no favorites
    if (favoriteChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.star_rounded,
                size: 18,
                color: tv.favorite.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                'Favorites',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: app.core.tx.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Horizontal scrolling favorites
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: favoriteChannels.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final channel = favoriteChannels[index];
              return _buildFavoriteChannelCard(channel);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // Favorite Channel Card (compact horizontal card)
  Widget _buildFavoriteChannelCard(DebrifyTvChannel channel) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    return SizedBox(
      width: 160,
      height: 100,
      child: TvFocusableCard(
        onPressed: () => _sections.channelWatch.watchChannel(channel),
        onLongPress: () => showTvChannelOptionsMenu(channel),
        child: Stack(
          children: [
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Channel number badge (smaller)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tv.accent,
                      borderRadius: app.shape.br(6),
                    ),
                    child: Text(
                      'CH ${channel.channelNumber > 0 ? channel.channelNumber : _owners.library.channels.indexOf(channel) + 1}',
                      style: TextStyle(
                        color: app.inkOn(tv.accent),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Channel name
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      channel.name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: app.core.tx,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Star indicator
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.star_rounded,
                size: 14,
                color: tv.favorite,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TV Channel Card (Grid item)
  Widget buildTvChannelCard(DebrifyTvChannel channel) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final isFavorited = _owners.library.favoriteChannelIds.contains(channel.id);

    return TvFocusableCard(
      onPressed: () {
        _sections.channelWatch.watchChannel(channel);
      },
      onLongPress: () {
        showTvChannelOptionsMenu(channel);
      },
      showLongPressHint:
          _owners.settings.isAndroidTv, // Only show hint on Android TV
      child: Stack(
        children: [
          // Favorite star indicator (top-left)
          if (isFavorited)
            Positioned(
              top: 6,
              left: 6,
              child: Icon(
                Icons.star_rounded,
                size: 20,
                color: tv.favorite,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          // Main card content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Channel number badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: tv.accent,
                    borderRadius: app.shape.br(8),
                  ),
                  child: Text(
                    'CH ${channel.channelNumber > 0 ? channel.channelNumber : _owners.library.channels.indexOf(channel) + 1}',
                    style: TextStyle(
                      color: app.inkOn(tv.accent),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Channel name - centered
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    channel.name.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: app.core.tx,
                      height: 1.2,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 3-dot menu for non-Android TV devices
          if (!_owners.settings.isAndroidTv)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: app.shape.br(6),
                ),
                child: PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    // Sits on the black plate above, so it takes glass ink.
                    color: app.onGlass.withValues(alpha: 0.9),
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: 'Options',
                  color: tv.noticeBg,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: app.shape.br(18),
                    side: BorderSide(color: tv.hairline),
                  ),
                  onSelected: (value) {
                    if (value == 'favorite') {
                      _sections.library.toggleChannelFavorite(channel);
                    } else if (value == 'edit') {
                      _sections.actions.handleEditChannel(channel);
                    } else if (value == 'share') {
                      _sections.share.handleShareChannelAsMagnet(channel);
                    } else if (value == 'delete') {
                      _sections.actions.handleDeleteChannel(channel);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'favorite',
                      child: Row(
                        children: [
                          Icon(
                            isFavorited
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 18,
                            color: tv.favorite,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isFavorited
                                ? 'Remove Favorite'
                                : 'Add to Favorites',
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.share_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Share Channel'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // TV Channel Options Menu (Edit/Delete)
  Future<void> showTvChannelOptionsMenu(DebrifyTvChannel channel) async {
    final isFavorited = _owners.library.favoriteChannelIds.contains(channel.id);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return DebrifyTvSpotlightDialog(
          eyebrow:
              'Channel actions · ${channel.channelNumber.toString().padLeft(2, '0')}',
          title: channel.name,
          subtitle: 'Manage this channel without leaving the current view.',
          icon: Icons.tune_rounded,
          maxWidth: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DebrifyTvDialogOptionCard(
                autofocus: true,
                icon: isFavorited
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                title: isFavorited ? 'Remove pin' : 'Pin channel',
                subtitle: isFavorited
                    ? 'Return this channel to the main list.'
                    : 'Keep this channel at the top of the rail.',
                tag: isFavorited ? 'Pinned' : 'Pin',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _sections.library.toggleChannelFavorite(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.edit_rounded,
                title: 'Edit channel',
                subtitle: 'Change its name, keywords, or content filter.',
                tag: 'Edit',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _sections.actions.handleEditChannel(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.share_rounded,
                title: 'Share channel',
                subtitle: 'Create a portable Debrify link for this pool.',
                tag: 'Link',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _sections.share.handleShareChannelAsMagnet(channel);
                },
              ),
              const SizedBox(height: 10),
              DebrifyTvDialogOptionCard(
                icon: Icons.delete_outline_rounded,
                title: 'Delete channel',
                subtitle: 'Remove this channel and its cached title pool.',
                tag: 'Careful',
                danger: true,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _sections.actions.handleDeleteChannel(channel);
                },
              ),
            ],
          ),
          actions: [
            DebrifyTvDialogButton(
              label: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  // TV "Add Channel" Card
  Widget buildTvAddChannelCard() {
    final tv = AppThemeScope.of(context).debrifyTv;
    return TvFocusableCard(
      onPressed: _sections.actions.handleAddChannel,
      child: SizedBox(
        height: double.infinity, // Ensures consistent height
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: tv.fillWeak,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, size: 32, color: tv.textDim),
            ),
            const SizedBox(height: 12),
            Text(
              'Add Channel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: tv.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSettingsCard({
    required DebrifyTvSettingsScope scope,
    required bool includeNsfwToggle,
    required String title,
    StateSetter? dialogSetState,
  }) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final bool isQuickScope = scope == DebrifyTvSettingsScope.quickPlay;

    final bool startRandom = isQuickScope
        ? _owners.settings.quickStartRandom
        : _owners.settings.startRandom;
    void setStartRandom(bool value) {
      setState(() {
        if (isQuickScope) {
          _owners.settings.quickStartRandom = value;
        } else {
          _owners.settings.startRandom = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvStartRandom(value));
      }
    }

    final int randomStartPercent = isQuickScope
        ? _owners.settings.quickRandomStartPercent
        : _owners.settings.randomStartPercent;
    void setRandomStartPercent(int value) {
      setState(() {
        if (isQuickScope) {
          _owners.settings.quickRandomStartPercent = value;
        } else {
          _owners.settings.randomStartPercent = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvRandomStartPercent(value));
      }
    }

    final bool showChannelName = isQuickScope
        ? _owners.settings.quickShowChannelName
        : _owners.settings.showChannelName;
    void setShowChannelName(bool value) {
      setState(() {
        if (isQuickScope) {
          _owners.settings.quickShowChannelName = value;
        } else {
          _owners.settings.showChannelName = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvShowChannelName(value));
      }
    }

    final bool showVideoTitle = isQuickScope
        ? _owners.settings.quickShowVideoTitle
        : _owners.settings.showVideoTitle;
    void setShowVideoTitle(bool value) {
      setState(() {
        if (isQuickScope) {
          _owners.settings.quickShowVideoTitle = value;
        } else {
          _owners.settings.showVideoTitle = value;
        }
      });
      dialogSetState?.call(() {});
      if (!isQuickScope) {
        unawaited(DebrifyTvStorage.saveDebrifyTvShowVideoTitle(value));
      }
    }

    // Hardcoded to false - no longer changeable
    const bool hideOptions = false;
    void setHideOptions(bool value) {
      // No-op: hideOptions is now hardcoded to false
      // Keep function for compatibility but it doesn't do anything
    }

    // Hardcoded to false - no longer changeable
    const bool hideBackButton = false;
    void setHideBackButton(bool value) {
      // No-op: hideBackButton is now hardcoded to false
      // Keep function for compatibility but it doesn't do anything
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Container(
        decoration: BoxDecoration(
          color: tv.fillWeak.withValues(alpha: .55),
          borderRadius: app.shape.br(20),
          border: Border.all(color: tv.hairline, width: 1),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: tv.textFaint,
                    fontFamily: 'JetBrainsMono',
                    fontSize: 9,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Content provider',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            providerChoiceChips(scope, dialogSetState: dialogSetState),
            const SizedBox(height: 16),
            SwitchRow(
              title: 'Start from random timestamp',
              subtitle: 'Each Debrify TV video starts at a random point',
              value: startRandom,
              onChanged: (v) => setStartRandom(v),
            ),
            if (startRandom) ...[
              const SizedBox(height: 8),
              RandomStartSlider(
                value: randomStartPercent,
                isAndroidTv: _owners.settings.isAndroidTv,
                onChanged: (next) => setRandomStartPercent(next),
                onChangeEnd: isQuickScope
                    ? null
                    : (next) =>
                          DebrifyTvStorage.saveDebrifyTvRandomStartPercent(
                            next,
                          ),
              ),
            ],
            // Removed Hide all options and Hide back button settings
            // These are now hardcoded to false (visible by default)
            if (includeNsfwToggle && isQuickScope) ...[
              const SizedBox(height: 8),
              SwitchRow(
                title: 'Avoid NSFW content',
                subtitle: _owners.settings.viewerForcesNsfw
                    ? 'Always on for this profile'
                    : 'Filter adult/inappropriate torrents • Best effort, not 100% accurate',
                value:
                    _owners.settings.viewerForcesNsfw ||
                    _owners.settings.quickAvoidNsfw,
                onChanged: (v) {
                  // Role-locked: a child session cannot loosen it.
                  if (_owners.settings.viewerForcesNsfw) return;
                  setState(() {
                    _owners.settings.quickAvoidNsfw = v;
                  });
                  dialogSetState?.call(() {});
                },
              ),
            ],
            const SizedBox(height: 16),
            // Kept LAST (above Reset) on purpose: these are ~14 focusable
            // chips, and placing them higher would push every existing switch
            // that many extra D-pad presses away on TV.
            tvFilterChips(dialogSetState: dialogSetState),
            const SizedBox(height: 16),
            DebrifyTvDialogButton(
              expand: true,
              icon: Icons.restore_rounded,
              label: 'Reset to defaults',
              onPressed: () async {
                final defaultProvider = _sections.settings
                    .determineDefaultProvider(
                      null,
                      _owners.settings.rdAvailable,
                      _owners.settings.torboxAvailable,
                      _owners.settings.pikpakAvailable,
                      _owners.settings.premiumizeAvailable,
                      _owners.settings.allDebridAvailable,
                    );

                setState(() {
                  if (isQuickScope) {
                    _owners.settings.quickStartRandom = true;
                    _owners.settings.quickRandomStartPercent =
                        randomStartPercentDefault;
                    _owners.settings.quickHideSeekbar = true;
                    _owners.settings.quickShowChannelName = true;
                    _owners.settings.quickShowVideoTitle = true;
                    _owners.settings.quickHideOptions =
                        false; // Hardcoded to false
                    _owners.settings.quickHideBackButton =
                        false; // Hardcoded to false
                    _owners.settings.quickAvoidNsfw = true;
                    _owners.settings.quickProvider = defaultProvider;
                  } else {
                    _owners.settings.startRandom = true;
                    _owners.settings.randomStartPercent =
                        randomStartPercentDefault;
                    _owners.settings.hideSeekbar = true;
                    _owners.settings.showChannelName = true;
                    _owners.settings.showVideoTitle = true;
                    _owners.settings.hideOptions = false; // Hardcoded to false
                    _owners.settings.hideBackButton =
                        false; // Hardcoded to false
                    _owners.settings.provider = defaultProvider;
                  }
                  // Playback filters are shared by both scopes, so reset
                  // them from either one.
                  _owners.settings.tvFilters = const DebrifyTvFilters.empty();
                });
                _sections.stage.invalidateSpotlightStats();
                dialogSetState?.call(() {});

                await DebrifyTvStorage.setDebrifyTvFilterQualities(const []);
                await DebrifyTvStorage.setDebrifyTvFilterSizes(const []);

                if (!isQuickScope) {
                  await DebrifyTvStorage.saveDebrifyTvStartRandom(true);
                  await DebrifyTvStorage.saveDebrifyTvHideSeekbar(true);
                  await DebrifyTvStorage.saveDebrifyTvShowChannelName(true);
                  await DebrifyTvStorage.saveDebrifyTvShowVideoTitle(true);
                  // No longer saving hideOptions and hideBackButton - they're hardcoded to false
                  await DebrifyTvStorage.saveDebrifyTvProvider(defaultProvider);
                }

                if (!mounted) {
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Reset to defaults successful'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showQuickPlayDialog() async {
    if (_owners.session.isBusy) {
      return;
    }

    bool avoidNsfw = _owners.settings.quickAvoidNsfw;
    String? error;
    // Create a separate controller for Quick Play to avoid sharing state with edit dialog
    final TextEditingController controller = TextEditingController();
    final FocusNode keywordFocusNode = FocusNode(
      debugLabel: 'QuickPlayKeywordsField',
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final app = AppThemeScope.of(context);
            return DebrifyTvSpotlightDialog(
              eyebrow: 'Quick play · no channel needed',
              title: 'Play anything',
              subtitle:
                  'Enter up to ${_owners.settings.quickPlayMaxKeywords} search terms. Nothing is saved when playback ends.',
              icon: Icons.play_arrow_rounded,
              maxWidth: 680,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TvTextField(
                    controller: controller,
                    autofocus: true,
                    focusNode: keywordFocusNode,
                    textInputAction: TextInputAction.search,
                    // Shared TV shell/keyboard chrome — settings.accent,
                    // with the keyboard's own panel ground and ink.
                    accent: app.settings.accent,
                    keyboardGround: app.youtube.keyboardPanel,
                    keyboardInk: app.core.tx,
                    keyboardInkOnAccent: app.inkOn(app.settings.accent),
                    decoration: const InputDecoration(
                      labelText: 'Keywords',
                      hintText: 'Comma separated keywords',
                    ),
                    onDownArrow: () {
                      final ctx = keywordFocusNode.context;
                      if (ctx != null) {
                        FocusScope.of(ctx).nextFocus();
                      }
                    },
                    onUpArrow: () {
                      final ctx = keywordFocusNode.context;
                      if (ctx != null) {
                        FocusScope.of(ctx).previousFocus();
                      }
                    },
                    onChanged: (_) {
                      if (error != null) {
                        setDialogState(() => error = null);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchRow(
                    title: 'Avoid NSFW content',
                    subtitle: _owners.settings.viewerForcesNsfw
                        ? 'Always on for this profile'
                        : 'Best-effort filter while searching',
                    value: _owners.settings.viewerForcesNsfw || avoidNsfw,
                    onChanged: (value) {
                      // Role-locked: a child session cannot loosen it.
                      if (_owners.settings.viewerForcesNsfw) return;
                      setDialogState(() => avoidNsfw = value);
                    },
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
              actions: [
                DebrifyTvDialogButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                DebrifyTvDialogButton(
                  label: 'Play now',
                  icon: Icons.play_arrow_rounded,
                  tone: DebrifyTvDialogButtonTone.primary,
                  onPressed: () async {
                    final keywords = controller.text.trim();
                    if (keywords.isEmpty) {
                      setDialogState(
                        () => error = 'Enter one or more keywords to continue.',
                      );
                      return;
                    }

                    if (mounted) {
                      setState(() {
                        _owners.settings.quickStartRandom =
                            _owners.settings.startRandom;
                        _owners.settings.quickRandomStartPercent =
                            _owners.settings.randomStartPercent;
                        _owners.settings.quickHideSeekbar =
                            _owners.settings.hideSeekbar;
                        _owners.settings.quickShowChannelName =
                            _owners.settings.showChannelName;
                        _owners.settings.quickShowVideoTitle =
                            _owners.settings.showVideoTitle;
                        _owners.settings.quickHideOptions =
                            false; // Always false now
                        _owners.settings.quickHideBackButton =
                            false; // Always false now
                        _owners.settings.quickAvoidNsfw = avoidNsfw;
                        _owners.settings.quickProvider =
                            _owners.settings.provider;
                      });
                      // Copy keywords from Quick Play controller to main controller for _watch()
                      _owners.library.keywordsController.text = keywords;
                    }

                    Navigator.of(dialogContext).pop();
                    // Wait for frames to ensure UI has updated and touch events are processed
                    await Future.delayed(const Duration(milliseconds: 100));
                    await WidgetsBinding.instance.endOfFrame;
                    await WidgetsBinding.instance.endOfFrame;
                    if (mounted) {
                      await _sections.quickPlay.watch();
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );

    keywordFocusNode.dispose();
    controller.dispose();
  }

  Future<void> showGlobalSettingsDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return DebrifyTvSpotlightDialog(
              eyebrow: 'Debrify TV · applies to every channel',
              title: 'Channel playback',
              subtitle:
                  'Choose the provider, filters, and starting behavior used when a channel tunes.',
              icon: Icons.settings_rounded,
              maxWidth: 920,
              maxHeightFactor: .94,
              child: buildSettingsCard(
                scope: DebrifyTvSettingsScope.channels,
                includeNsfwToggle: false,
                title: 'Playback rules',
                dialogSetState: setDialogState,
              ),
              actions: [
                DebrifyTvDialogButton(
                  autofocus: true,
                  label: 'Done',
                  icon: Icons.check_rounded,
                  tone: DebrifyTvDialogButtonTone.primary,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
