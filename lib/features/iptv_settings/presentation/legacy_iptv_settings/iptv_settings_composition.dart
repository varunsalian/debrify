import 'iptv_settings_feedback.dart';
import 'iptv_settings_file_import.dart';
import 'iptv_settings_focus_actions.dart';
import 'iptv_settings_load_settings.dart';
import 'iptv_settings_profile_actions.dart';
import 'iptv_settings_sections.dart';
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
    customLists: scope.customLists,
    hideableSources: scope.hideableSources,
  ));
  sections.feedbackSlot = IptvSettingsFeedback((
    mounted: scope.mounted,
    context: scope.context,
  ));
  sections.loadSettingsSlot = IptvSettingsLoadSettings((
    mounted: scope.mounted,
    setState: scope.setState,
    sourcesOwner: owners.sourcesOwner,
    preferencesOwner: owners.preferencesOwner,
    recordingOwner: owners.recordingOwner,
    ensureFocusNodes: sections.focusActions.ensureFocusNodes,
    reloadHiddenCounts: scope.reloadHiddenCounts,
    twoPaneKey: scope.twoPaneKey,
    openAddSource: scope.openAddSource,
    layoutOwner: owners.layoutOwner,
    focusOwner: owners.focusOwner,
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
  sections.sourceRemovalSlot = IptvSettingsSourceRemoval((
    mounted: scope.mounted,
    showSnackBar: sections.feedback.showSnackBar,
    context: scope.context,
    sourcesOwner: owners.sourcesOwner,
    catalogOwnerReferencesFor: scope.catalogOwnerReferencesFor,
    catalogKeysFor: scope.catalogKeysFor,
    setState: scope.setState,
    ensureFocusNodes: sections.focusActions.ensureFocusNodes,
    focusOwner: owners.focusOwner,
    focusAndReveal: sections.focusActions.focusAndReveal,
    inputOwner: owners.inputOwner,
  ));
  sections.sourceRefreshSlot = IptvSettingsSourceRefresh((
    runProfileAction: sections.profileActions.runProfileAction,
    mounted: scope.mounted,
    setState: scope.setState,
    sourcesOwner: owners.sourcesOwner,
    showSnackBar: sections.feedback.showSnackBar,
  ));
  sections.sourceEditSlot = IptvSettingsSourceEdit((
    runProfileAction: sections.profileActions.runProfileAction,
    context: scope.context,
    sourcesOwner: owners.sourcesOwner,
    mounted: scope.mounted,
    showSnackBar: sections.feedback.showSnackBar,
    catalogKeysFor: scope.catalogKeysFor,
    catalogOwnerReferencesFor: scope.catalogOwnerReferencesFor,
    setState: scope.setState,
  ));
  return sections;
}
