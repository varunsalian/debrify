import 'package:debrify/features/iptv_settings/models/iptv_settings_phone_section.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_owner.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

typedef IptvSettingsLayoutActionsDeps = ({
  void Function(VoidCallback) setState,
  IptvSettingsLayoutOwner layoutOwner,
  bool Function() mounted,
  IptvSettingsFocusOwner focusOwner,
  Widget Function() buildPhoneHub,
  Widget Function() buildSourcesView,
  Widget Function() buildListsView,
  Widget Function() buildCategoryOrderView,
  Widget Function() buildHiddenView,
  Widget Function() buildStartupView,
  Widget Function() buildChannelPreviewView,
  Widget Function() buildContinueWatchingView,
  Widget Function() buildRecordingView,
});

class IptvSettingsLayoutActions {
  IptvSettingsLayoutActions(this._deps);
  final IptvSettingsLayoutActionsDeps _deps;

  /// Switch the narrow layout's view. On TV-class input the old view's
  /// focused row is about to unmount, which would strand DPAD on the bare
  /// FocusScope — hand it to the new view's first control instead. Touch
  /// keeps its no-focus-ring behavior (the guard below never fires there).
  void enterPhoneSection(IptvSettingsPhoneSection section) {
    _deps.setState(() => _deps.layoutOwner.phoneSection = section);
    if (!PlatformUtil.isAndroidTvCached) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted() || _deps.layoutOwner.twoPaneActive) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary is! FocusScopeNode) return;
      _deps.focusOwner.phoneViewMarker.traversalDescendants.firstOrNull
          ?.requestFocus();
    });
  }

  Widget buildSingleColumn() {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Focus(
        focusNode: _deps.focusOwner.phoneViewMarker,
        canRequestFocus: false,
        skipTraversal: true,
        child: switch (_deps.layoutOwner.phoneSection) {
          IptvSettingsPhoneSection.hub => _deps.buildPhoneHub(),
          IptvSettingsPhoneSection.sources => _deps.buildSourcesView(),
          IptvSettingsPhoneSection.lists => _deps.buildListsView(),
          IptvSettingsPhoneSection.categoryOrder =>
            _deps.buildCategoryOrderView(),
          IptvSettingsPhoneSection.hidden => _deps.buildHiddenView(),
          IptvSettingsPhoneSection.startup => _deps.buildStartupView(),
          IptvSettingsPhoneSection.channelPreview =>
            _deps.buildChannelPreviewView(),
          IptvSettingsPhoneSection.continueWatching =>
            _deps.buildContinueWatchingView(),
          IptvSettingsPhoneSection.recording => _deps.buildRecordingView(),
        },
      ),
    );
  }
}
