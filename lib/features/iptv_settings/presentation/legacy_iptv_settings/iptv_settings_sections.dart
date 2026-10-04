import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_focus_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_input_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_layout_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_preferences_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_owner.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sources_owner.dart';
import 'package:debrify/screens/settings/iptv_settings_two_pane.dart';
import 'package:flutter/material.dart';

import 'iptv_settings_catalog_actions.dart';
import 'iptv_settings_category_views.dart';
import 'iptv_settings_feedback.dart';
import 'iptv_settings_file_import.dart';
import 'iptv_settings_focus_actions.dart';
import 'iptv_settings_layout_actions.dart';
import 'iptv_settings_list_views.dart';
import 'iptv_settings_lists_actions.dart';
import 'iptv_settings_load_settings.dart';
import 'iptv_settings_phone_hub.dart';
import 'iptv_settings_preferences_actions.dart';
import 'iptv_settings_preferences_views.dart';
import 'iptv_settings_profile_actions.dart';
import 'iptv_settings_recording_actions.dart';
import 'iptv_settings_recording_view.dart';
import 'iptv_settings_source_edit.dart';
import 'iptv_settings_source_forms.dart';
import 'iptv_settings_source_refresh.dart';
import 'iptv_settings_source_removal.dart';
import 'iptv_settings_source_views.dart';
import 'iptv_settings_two_pane.dart';
import 'iptv_settings_url_add.dart';
import 'iptv_settings_xtream_add.dart';

typedef IptvSettingsScope = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  GlobalKey<IptvSettingsTwoPaneState> twoPaneKey,
  bool Function() openAddSource,
  BuildContext Function() context,
  bool Function() appearanceVisible,
});

typedef IptvSettingsOwners = ({
  IptvSettingsFocusOwner focusOwner,
  IptvSettingsInputOwner inputOwner,
  IptvSettingsSourcesOwner sourcesOwner,
  IptvSettingsPreferencesOwner preferencesOwner,
  IptvSettingsRecordingOwner recordingOwner,
  IptvSettingsLayoutOwner layoutOwner,
});

class IptvSettingsSections {
  IptvSettingsProfileActions? profileActionsSlot;
  IptvSettingsProfileActions get profileActions => profileActionsSlot!;
  IptvSettingsFocusActions? focusActionsSlot;
  IptvSettingsFocusActions get focusActions => focusActionsSlot!;
  IptvSettingsLoadSettings? loadSettingsSlot;
  IptvSettingsLoadSettings get loadSettings => loadSettingsSlot!;
  IptvSettingsUrlAdd? urlAddSlot;
  IptvSettingsUrlAdd get urlAdd => urlAddSlot!;
  IptvSettingsFileImport? fileImportSlot;
  IptvSettingsFileImport get fileImport => fileImportSlot!;
  IptvSettingsXtreamAdd? xtreamAddSlot;
  IptvSettingsXtreamAdd get xtreamAdd => xtreamAddSlot!;
  IptvSettingsSourceRemoval? sourceRemovalSlot;
  IptvSettingsSourceRemoval get sourceRemoval => sourceRemovalSlot!;
  IptvSettingsSourceRefresh? sourceRefreshSlot;
  IptvSettingsSourceRefresh get sourceRefresh => sourceRefreshSlot!;
  IptvSettingsFeedback? feedbackSlot;
  IptvSettingsFeedback get feedback => feedbackSlot!;
  IptvSettingsSourceEdit? sourceEditSlot;
  IptvSettingsSourceEdit get sourceEdit => sourceEditSlot!;
  IptvSettingsPreferencesActions? preferencesActionsSlot;
  IptvSettingsPreferencesActions get preferencesActions =>
      preferencesActionsSlot!;
  IptvSettingsCatalogActions? catalogActionsSlot;
  IptvSettingsCatalogActions get catalogActions => catalogActionsSlot!;
  IptvSettingsListsActions? listsActionsSlot;
  IptvSettingsListsActions get listsActions => listsActionsSlot!;
  IptvSettingsRecordingActions? recordingActionsSlot;
  IptvSettingsRecordingActions get recordingActions => recordingActionsSlot!;
  IptvSettingsLayoutActions? layoutActionsSlot;
  IptvSettingsLayoutActions get layoutActions => layoutActionsSlot!;
  IptvSettingsCategoryViews? categoryViewsSlot;
  IptvSettingsCategoryViews get categoryViews => categoryViewsSlot!;
  IptvSettingsListViews? listViewsSlot;
  IptvSettingsListViews get listViews => listViewsSlot!;
  IptvSettingsSourceViews? sourceViewsSlot;
  IptvSettingsSourceViews get sourceViews => sourceViewsSlot!;
  IptvSettingsSourceForms? sourceFormsSlot;
  IptvSettingsSourceForms get sourceForms => sourceFormsSlot!;
  IptvSettingsTwoPaneLayout? twoPaneSlot;
  IptvSettingsTwoPaneLayout get twoPane => twoPaneSlot!;
  IptvSettingsPhoneHub? phoneHubSlot;
  IptvSettingsPhoneHub get phoneHub => phoneHubSlot!;
  IptvSettingsPreferencesViews? preferencesViewsSlot;
  IptvSettingsPreferencesViews get preferencesViews => preferencesViewsSlot!;
  IptvSettingsRecordingView? recordingViewSlot;
  IptvSettingsRecordingView get recordingView => recordingViewSlot!;
}
