import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sections.dart';

import 'iptv_settings_catalog_actions.dart';
import 'iptv_settings_feedback.dart';
import 'iptv_settings_file_import.dart';
import 'iptv_settings_focus_actions.dart';
import 'iptv_settings_lists_actions.dart';
import 'iptv_settings_load_settings.dart';
import 'iptv_settings_preferences_actions.dart';
import 'iptv_settings_profile_actions.dart';
import 'iptv_settings_recording_actions.dart';
import 'iptv_settings_source_edit.dart';
import 'iptv_settings_source_refresh.dart';
import 'iptv_settings_source_removal.dart';
import 'iptv_settings_url_add.dart';
import 'iptv_settings_xtream_add.dart';

IptvSettingsSections createIptvSettingsSections(
  IptvSettingsScope scope,
  IptvSettingsOwners owners,
) {
  final sections = IptvSettingsSections();
  sections.profileActionsSlot = IptvSettingsProfileActions((
    mounted: scope.mounted,
  ));
  sections.focusActionsSlot = IptvSettingsFocusActions((
    mounted: scope.mounted,
    sourcesOwner: owners.sourcesOwner,
    focusOwner: owners.focusOwner,
    customLists: () => sections.listsActions.customLists,
    hideableSources: () => sections.catalogActions.hideableSources,
  ));
  sections.feedbackSlot = IptvSettingsFeedback((
    mounted: scope.mounted,
    context: scope.context,
  ));
  sections.recordingActionsSlot = IptvSettingsRecordingActions((
    recordingOwner: owners.recordingOwner,
    context: scope.context,
    mounted: scope.mounted,
    setState: scope.setState,
  ));
  sections.urlAddSlot = IptvSettingsUrlAdd((
    runProfileAction: sections.profileActions.runProfileAction,
    inputOwner: owners.inputOwner,
    showSnackBar: sections.feedback.showSnackBar,
    sourcesOwner: owners.sourcesOwner,
    setState: scope.setState,
    mounted: scope.mounted,
    ensureFocusNodes: sections.focusActions.ensureFocusNodes,
  ));
  sections.fileImportSlot = IptvSettingsFileImport((
    runProfileAction: sections.profileActions.runProfileAction,
    showSnackBar: sections.feedback.showSnackBar,
    mounted: scope.mounted,
    context: scope.context,
    sourcesOwner: owners.sourcesOwner,
    setState: scope.setState,
    ensureFocusNodes: sections.focusActions.ensureFocusNodes,
  ));
  sections.xtreamAddSlot = IptvSettingsXtreamAdd((
    runProfileAction: sections.profileActions.runProfileAction,
    inputOwner: owners.inputOwner,
    showSnackBar: sections.feedback.showSnackBar,
    sourcesOwner: owners.sourcesOwner,
    setState: scope.setState,
    mounted: scope.mounted,
    ensureFocusNodes: sections.focusActions.ensureFocusNodes,
  ));
  sections.sourceRefreshSlot = IptvSettingsSourceRefresh((
    runProfileAction: sections.profileActions.runProfileAction,
    mounted: scope.mounted,
    setState: scope.setState,
    sourcesOwner: owners.sourcesOwner,
    showSnackBar: sections.feedback.showSnackBar,
  ));
  sections.preferencesActionsSlot = IptvSettingsPreferencesActions((
    runProfileAction: sections.profileActions.runProfileAction,
    context: scope.context,
    preferencesOwner: owners.preferencesOwner,
    mounted: scope.mounted,
    setState: scope.setState,
  ));
  sections.catalogActionsSlot = IptvSettingsCatalogActions((
    sourcesOwner: owners.sourcesOwner,
    context: scope.context,
    mounted: scope.mounted,
    setState: scope.setState,
    showSnackBar: sections.feedback.showSnackBar,
  ));
  sections.listsActionsSlot = IptvSettingsListsActions((
    sourcesOwner: owners.sourcesOwner,
    mounted: scope.mounted,
    setState: scope.setState,
    ensureFocusNodes: sections.focusActions.ensureFocusNodes,
    runProfileAction: sections.profileActions.runProfileAction,
    context: scope.context,
    showSnackBar: sections.feedback.showSnackBar,
    focusOwner: owners.focusOwner,
    focusAndReveal: sections.focusActions.focusAndReveal,
  ));
  sections.loadSettingsSlot = IptvSettingsLoadSettings((
    mounted: scope.mounted,
    setState: scope.setState,
    sourcesOwner: owners.sourcesOwner,
    preferencesOwner: owners.preferencesOwner,
    recordingOwner: owners.recordingOwner,
    ensureFocusNodes: sections.focusActions.ensureFocusNodes,
    reloadHiddenCounts: sections.catalogActions.reloadHiddenCounts,
    twoPaneKey: scope.twoPaneKey,
    openAddSource: scope.openAddSource,
    layoutOwner: owners.layoutOwner,
    focusOwner: owners.focusOwner,
  ));
  sections.sourceRemovalSlot = IptvSettingsSourceRemoval((
    mounted: scope.mounted,
    showSnackBar: sections.feedback.showSnackBar,
    context: scope.context,
    sourcesOwner: owners.sourcesOwner,
    catalogOwnerReferencesFor:
        sections.catalogActions.catalogOwnerReferencesFor,
    catalogKeysFor: sections.catalogActions.catalogKeysFor,
    setState: scope.setState,
    ensureFocusNodes: sections.focusActions.ensureFocusNodes,
    focusOwner: owners.focusOwner,
    focusAndReveal: sections.focusActions.focusAndReveal,
    inputOwner: owners.inputOwner,
  ));
  sections.sourceEditSlot = IptvSettingsSourceEdit((
    runProfileAction: sections.profileActions.runProfileAction,
    context: scope.context,
    sourcesOwner: owners.sourcesOwner,
    mounted: scope.mounted,
    showSnackBar: sections.feedback.showSnackBar,
    catalogKeysFor: sections.catalogActions.catalogKeysFor,
    catalogOwnerReferencesFor:
        sections.catalogActions.catalogOwnerReferencesFor,
    setState: scope.setState,
  ));
  return sections;
}
