import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_list_panes.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_navigation.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_owners.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_panes.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_preference_panes.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_rail.dart';
import 'package:debrify/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart';
import 'package:flutter/material.dart';

class IptvSettingsTwoPaneDependencies {
  final IptvSettingsTwoPane Function() widget;
  final BuildContext Function() context;
  final IptvSettingsTwoPaneOwners owners;
  final IptvSettingsTwoPaneSections Function() sections;
  IptvSettingsTwoPaneDependencies({
    required this.widget,
    required this.context,
    required this.owners,
    required this.sections,
  });
}

class IptvSettingsTwoPaneSections {
  late final IptvSettingsTwoPaneNavigation navigation;
  late final IptvSettingsTwoPaneRail rail;
  late final IptvSettingsTwoPanePanes panes;
  late final IptvSettingsTwoPaneListPanes listPanes;
  late final IptvSettingsTwoPanePreferencePanes preferencePanes;
  IptvSettingsTwoPaneSections(IptvSettingsTwoPaneDependencies deps) {
    navigation = IptvSettingsTwoPaneNavigation(deps);
    rail = IptvSettingsTwoPaneRail(deps);
    panes = IptvSettingsTwoPanePanes(deps);
    listPanes = IptvSettingsTwoPaneListPanes(deps);
    preferencePanes = IptvSettingsTwoPanePreferencePanes(deps);
  }
}
