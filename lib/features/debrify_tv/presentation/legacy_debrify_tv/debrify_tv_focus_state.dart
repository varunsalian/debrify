import 'package:flutter/material.dart';

class DebrifyTvFocusState {
  final TextEditingController channelSearchController = TextEditingController();
  String channelSearchTerm = '';
  bool showSearchBar = false;
  late final FocusNode channelSearchFocusNode;
  final FocusNode quickPlayFocusNode = FocusNode(
    debugLabel: 'DebrifyTVQuickPlay',
  );
  final FocusNode channelSearchButtonFocusNode = FocusNode(
    debugLabel: 'DebrifyTVChannelSearchButton',
  );
  final FocusNode channelSearchClearFocusNode = FocusNode(
    debugLabel: 'DebrifyTVChannelSearchClear',
  );
  final FocusNode channelMenuFocusNode = FocusNode(
    debugLabel: 'DebrifyTVChannelMenu',
  );
  final MenuController channelMenuController = MenuController();
  // TV content focus handler (stored for proper unregistration)
  VoidCallback? tvContentFocusHandler;
}
