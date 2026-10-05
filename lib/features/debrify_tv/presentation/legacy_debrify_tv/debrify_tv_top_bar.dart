import 'package:debrify/features/debrify_tv/models/debrify_tv_kinds.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DebrifyTvTopBar {
  final DebrifyTvDependencies _deps;
  DebrifyTvTopBar(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

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
        _deps.setState(() {
          _owners.focus.channelSearchTerm = '';
        });
        // Clearing unmounts the suffix ✕ — if IT held focus, focus would be
        // stranded; parking on the field covers both cases.
        _owners.focus.channelSearchFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (_owners.focus.showSearchBar) {
        _deps.setState(() {
          _owners.focus.showSearchBar = false;
        });
        _owners.focus.channelSearchButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _toggleChannelSearchBar() {
    _deps.setState(() {
      _owners.focus.showSearchBar = !_owners.focus.showSearchBar;
      if (_owners.focus.showSearchBar) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_deps.mounted()) {
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
    _deps.setState(() {
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
        _sections.dialogs.showGlobalSettingsDialog();
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
    final app = AppThemeScope.of(_deps.context());
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
                  : () => _sections.topBar._handleTopMenuAction(
                      DebrifyTvTopMenuAction.import,
                    ),
              child: const Text('Import'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.folder_zip_rounded),
              onPressed:
                  _owners.session.isBusy || _owners.library.channels.isEmpty
                  ? null
                  : () => _sections.topBar._handleTopMenuAction(
                      DebrifyTvTopMenuAction.export,
                    ),
              child: const Text('Export Channels'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.add_rounded),
              onPressed: _owners.session.isBusy
                  ? null
                  : () => _sections.topBar._handleTopMenuAction(
                      DebrifyTvTopMenuAction.add,
                    ),
              child: const Text('Add Channel'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.delete_outline_rounded),
              onPressed:
                  _owners.session.isBusy || _owners.library.channels.isEmpty
                  ? null
                  : () => _sections.topBar._handleTopMenuAction(
                      DebrifyTvTopMenuAction.deleteAll,
                    ),
              child: const Text('Delete All'),
            ),
            MenuItemButton(
              style: itemStyle,
              leadingIcon: const Icon(Icons.settings_rounded),
              onPressed: () => _sections.topBar._handleTopMenuAction(
                DebrifyTvTopMenuAction.settings,
              ),
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
    final app = AppThemeScope.of(_deps.context());
    final tv = app.debrifyTv;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _sections.topBar._buildTopActionButton(
          focusNode: _owners.focus.quickPlayFocusNode,
          icon: Icons.play_arrow_rounded,
          tooltip: 'Play',
          onPressed: _owners.session.isBusy
              ? null
              : _sections.dialogs.showQuickPlayDialog,
          activeColor: tv.fillStrong,
          leftToSidebar: true,
          rightFocusNode: _owners.focus.channelSearchButtonFocusNode,
        ),
        const SizedBox(width: 10),
        _sections.topBar._buildTopActionButton(
          focusNode: _owners.focus.channelSearchButtonFocusNode,
          icon: Icons.search_rounded,
          tooltip: _owners.focus.showSearchBar
              ? 'Close search'
              : 'Search channels',
          onPressed: _sections.topBar._toggleChannelSearchBar,
          activeColor: tv.fillStrong,
          isActive:
              _owners.focus.showSearchBar ||
              _owners.focus.channelSearchTerm.isNotEmpty,
          leftFocusNode: _owners.focus.quickPlayFocusNode,
          rightFocusNode: _owners.focus.channelMenuFocusNode,
          upToSearch: true,
        ),
        const SizedBox(width: 10),
        _sections.topBar._buildTopMenuButton(),
      ],
    );
  }
}
