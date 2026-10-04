import 'package:debrify/features/iptv_settings/models/iptv_settings_phone_section.dart';

class IptvSettingsLayoutOwner {
  /// True while the wide rail+pane layout is mounted. Read by the DPAD
  /// hand-offs that target the single-column layout's playlist tiles — those
  /// nodes exist but are attached to nothing here, and requesting focus on an
  /// unattached node silently strands DPAD.
  bool twoPaneActive = false;

  /// Where the narrow layout is (see [IptvSettingsPhoneSection]). The wide layout never
  /// reads it and forces it back to [IptvSettingsPhoneSection.hub] so a resize can't
  /// strand back-handling in a sub-view that no longer renders.
  IptvSettingsPhoneSection phoneSection = IptvSettingsPhoneSection.hub;
}
