import 'package:debrify/features/iptv_settings/models/iptv_settings_phone_section.dart';
import 'package:debrify/features/iptv_settings/presentation/iptv_settings_back_button.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart';
import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsRootLayoutDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  IptvSettingsSourcesOwner sourcesOwner,
  IptvSettingsLayoutOwner layoutOwner,
  void Function(IptvSettingsPhoneSection section) enterPhoneSection,
  IptvSettingsFocusOwner focusOwner,
  GlobalKey<IptvSettingsTwoPaneState> twoPaneKey,
  void Function(FocusNode node) focusAndReveal,
  IptvSettingsInputOwner inputOwner,
  Widget Function() buildTwoPane,
  Widget Function() buildSingleColumn,
});

class IptvSettingsRootLayout {
  IptvSettingsRootLayout(this._deps);
  final IptvSettingsRootLayoutDeps _deps;

  Widget build(BuildContext context) {
    if (_deps.sourcesOwner.loading) {
      return SettingsPageScaffold(
        title: 'IPTV Playlists',
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      // Sub-views pop back to the hub, not off the page — both the system
      // back and the AppBar back go through maybePop, so one gesture
      // contract covers both. The wide layout always sits on `hub` (the
      // LayoutBuilder below forces it), so it pops normally.
      canPop: _deps.layoutOwner.phoneSection == IptvSettingsPhoneSection.hub,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_deps.mounted()) return;
        _deps.enterPhoneSection(IptvSettingsPhoneSection.hub);
      },
      child: SettingsPageScaffold(
        title: switch (_deps.layoutOwner.phoneSection) {
          IptvSettingsPhoneSection.hub => 'IPTV Playlists',
          IptvSettingsPhoneSection.sources => 'Sources',
          IptvSettingsPhoneSection.lists => 'Channel Lists',
          IptvSettingsPhoneSection.categoryOrder => 'Category Order',
          IptvSettingsPhoneSection.hidden => 'Hidden Categories',
          IptvSettingsPhoneSection.startup => 'Startup',
          IptvSettingsPhoneSection.channelPreview => 'Channel Preview',
          IptvSettingsPhoneSection.continueWatching => 'Continue Watching',
          IptvSettingsPhoneSection.recording => 'Recording',
        },
        leading: IptvSettingsBackButton(
          focusNode: _deps.focusOwner.backButtonFocusNode,
          // Two-pane hands DOWN to the rail; the single column lands on the
          // currently-selected tab, not always the first one — but only the
          // Sources sub-view mounts the tabs at all; everywhere else default
          // traversal owns DOWN.
          onDownArrow: () {
            if (_deps.layoutOwner.twoPaneActive) {
              _deps.twoPaneKey.currentState?.focusRail();
              return;
            }
            if (_deps.layoutOwner.phoneSection !=
                IptvSettingsPhoneSection.sources) {
              // The back button swallows DOWN whenever a handler exists, so
              // hand focus somewhere real: whichever view is up, its first
              // focusable row (on the hub that's the Sources row).
              _deps.focusOwner.phoneViewMarker.traversalDescendants.firstOrNull
                  ?.requestFocus();
              return;
            }
            _deps.focusAndReveal(switch (_deps.inputOwner.tabController.index) {
              1 => _deps.focusOwner.fileTabFocusNode,
              2 => _deps.focusOwner.xcTabFocusNode,
              _ => _deps.focusOwner.urlTabFocusNode,
            });
          },
        ),
        // TV and desktop get the rail + detail layout; phones and narrow
        // windows keep the single column, which is the only thing that fits.
        body: LayoutBuilder(
          builder: (context, c) {
            final twoPane = c.maxWidth >= 900 && c.maxHeight >= 420;
            // Assigned synchronously, and it has to be: _buildSingleColumn
            // reads this flag *in this same pass* to decide whether the add
            // forms' DOWN key should hand off to the playlist tiles. Deferring
            // it to a post-frame meant the just-narrowed layout was built with
            // the wide layout's answer, and nothing scheduled a rebuild to
            // correct it — so DOWN stayed broken until some unrelated
            // setState. Safe because no rebuild is needed: the only other
            // readers are key handlers, which run on user input, never during
            // layout.
            _deps.layoutOwner.twoPaneActive = twoPane;
            // The wide layout renders no sub-views, so a resize mid-sub-view
            // must land back on the hub. Unlike _twoPaneActive this one IS
            // read by widgets built before this LayoutBuilder runs (the
            // PopScope's canPop and the scaffold title), so a bare field
            // assignment would leave them stale indefinitely — schedule a
            // rebuild for them.
            if (twoPane &&
                _deps.layoutOwner.phoneSection !=
                    IptvSettingsPhoneSection.hub) {
              _deps.layoutOwner.phoneSection = IptvSettingsPhoneSection.hub;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_deps.mounted()) _deps.setState(() {});
              });
            }
            return twoPane ? _deps.buildTwoPane() : _deps.buildSingleColumn();
          },
        ),
      ),
    );
  }
}
