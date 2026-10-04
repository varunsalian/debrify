import 'package:flutter/material.dart';

class IptvSettingsFocusOwner {
  final FocusNode backButtonFocusNode = FocusNode(
    debugLabel: 'iptv-back-button',
  );
  final FocusNode nameInputFocusNode = FocusNode(debugLabel: 'iptv-name-input');
  final FocusNode urlInputFocusNode = FocusNode(debugLabel: 'iptv-url-input');
  final FocusNode epgUrlInputFocusNode = FocusNode(
    debugLabel: 'iptv-epg-url-input',
  );
  final FocusNode addButtonFocusNode = FocusNode(debugLabel: 'iptv-add-button');
  final FocusNode importFileButtonFocusNode = FocusNode(
    debugLabel: 'iptv-import-file-button',
  );
  final FocusNode xcNameFocusNode = FocusNode(debugLabel: 'iptv-xc-name');
  final FocusNode xcServerFocusNode = FocusNode(debugLabel: 'iptv-xc-server');
  final FocusNode xcUsernameFocusNode = FocusNode(
    debugLabel: 'iptv-xc-username',
  );
  final FocusNode xcPasswordFocusNode = FocusNode(
    debugLabel: 'iptv-xc-password',
  );
  final FocusNode xcLoginButtonFocusNode = FocusNode(
    debugLabel: 'iptv-xc-login-button',
  );

  // Tab focus nodes
  final FocusNode urlTabFocusNode = FocusNode(debugLabel: 'iptv-url-tab');
  final FocusNode fileTabFocusNode = FocusNode(debugLabel: 'iptv-file-tab');
  final FocusNode xcTabFocusNode = FocusNode(debugLabel: 'iptv-xc-tab');

  // Focus nodes for playlist items (3 per item: star + refresh + delete)
  final List<FocusNode> playlistFocusNodes = [];

  /// Focus nodes for the Lists section — its OWN array rather than an
  /// extension of [playlistFocusNodes], whose every index is `row * 4`
  /// arithmetic that a second section would silently break.
  /// 4 per list: rename + move-up + move-down + delete.
  final List<FocusNode> listFocusNodes = [];
  final FocusNode createListFocusNode = FocusNode(
    debugLabel: 'iptv-create-list',
  );

  /// Focus nodes for the Hidden-categories section — one per catalog-backed
  /// source. Its own array for the same reason [listFocusNodes] is: the
  /// arrays above are index arithmetic that a third section would break.
  final List<FocusNode> hiddenFocusNodes = [];
  final FocusNode scheduledRecordingsFocusNode = FocusNode(
    debugLabel: 'iptv-scheduled-recordings',
  );
  final FocusNode maxConcurrentFocusNode = FocusNode(
    debugLabel: 'iptv-max-concurrent',
  );
  final FocusNode batteryFocusNode = FocusNode(
    debugLabel: 'iptv-battery-exemption',
  );
  final FocusNode startupChannelFocusNode = FocusNode(
    debugLabel: 'iptv-startup-channel',
  );

  /// The hub's first row (Sources) — DOWN from the back button and the
  /// narrow TV entry both land here, mirroring how the old single column
  /// landed on the add-form tabs.
  final FocusNode hubSourcesFocusNode = FocusNode(
    debugLabel: 'iptv-hub-sources',
  );

  /// Non-focusable marker around whichever narrow view is showing — the
  /// picker pages' idiom: section transitions unmount the focused row, so
  /// DPAD re-seeds on the new view's first traversal descendant.
  final FocusNode phoneViewMarker = FocusNode(
    debugLabel: 'iptv-phone-view',
    skipTraversal: true,
    canRequestFocus: false,
  );
}
