import 'package:debrify/features/iptv_settings/models/iptv_settings_phone_section.dart';
import 'package:debrify/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_sections.dart';

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
import 'iptv_settings_root_layout.dart';
import 'iptv_settings_source_edit.dart';
import 'iptv_settings_source_forms.dart';
import 'iptv_settings_source_refresh.dart';
import 'iptv_settings_source_removal.dart';
import 'iptv_settings_source_views.dart';
import 'iptv_settings_two_pane.dart';
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
  sections.recordingViewSlot = IptvSettingsRecordingView((
    recordingOwner: owners.recordingOwner,
    mounted: scope.mounted,
    setState: scope.setState,
    focusOwner: owners.focusOwner,
    pickMaxConcurrent: sections.recordingActions.pickMaxConcurrent,
    requestBatteryExemption: sections.recordingActions.requestBatteryExemption,
    openScheduledRecordings: sections.recordingActions.openScheduledRecordings,
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
  sections.categoryViewsSlot = IptvSettingsCategoryViews((
    context: scope.context,
    hideableSources: () => sections.catalogActions.hideableSources,
    focusOwner: owners.focusOwner,
    sourcesOwner: owners.sourcesOwner,
    openHiddenCategories: sections.catalogActions.openHiddenCategories,
    categoryOrderSources: () => sections.catalogActions.categoryOrderSources,
    openCategoryOrder: sections.catalogActions.openCategoryOrder,
  ));
  sections.listViewsSlot = IptvSettingsListViews((
    context: scope.context,
    customLists: () => sections.listsActions.customLists,
    listNodeAt: sections.listsActions.listNodeAt,
    renameList: sections.listsActions.renameList,
    moveList: sections.listsActions.moveList,
    deleteList: sections.listsActions.deleteList,
    focusOwner: owners.focusOwner,
    createList: sections.listsActions.createList,
  ));
  sections.sourceFormsSlot = IptvSettingsSourceForms((
    inputOwner: owners.inputOwner,
    focusOwner: owners.focusOwner,
    focusAndReveal: sections.focusActions.focusAndReveal,
    addPlaylist: sections.urlAdd.addPlaylist,
    layoutOwner: owners.layoutOwner,
    sourcesOwner: owners.sourcesOwner,
    context: scope.context,
    importFromFile: sections.fileImport.importFromFile,
    addXtreamCodes: sections.xtreamAdd.addXtreamCodes,
  ));
  sections.phoneHubSlot = IptvSettingsPhoneHub((
    hideableSources: () => sections.catalogActions.hideableSources,
    sourcesOwner: owners.sourcesOwner,
    focusOwner: owners.focusOwner,
    enterPhoneSection: (IptvSettingsPhoneSection section) =>
        sections.layoutActions.enterPhoneSection(section),
    preferencesOwner: owners.preferencesOwner,
    pickAutoRefresh: sections.preferencesActions.pickAutoRefresh,
    customLists: () => sections.listsActions.customLists,
    openChannelOrder: sections.catalogActions.openChannelOrder,
    categoryOrderSources: () => sections.catalogActions.categoryOrderSources,
    startupChannelLabel: () => sections.preferencesActions.startupChannelLabel,
    appearanceVisible: scope.appearanceVisible,
    openIptvStylePicker: sections.preferencesActions.openIptvStylePicker,
    openPlayerGuidePicker: sections.preferencesActions.openPlayerGuidePicker,
    recordingOwner: owners.recordingOwner,
  ));
  sections.preferencesViewsSlot = IptvSettingsPreferencesViews((
    preferencesOwner: owners.preferencesOwner,
    setStartupEnabled: sections.preferencesActions.setStartupEnabled,
    lastLiveChannelLabel: () =>
        sections.preferencesActions.lastLiveChannelLabel,
    setStartupMode: sections.preferencesActions.setStartupMode,
    startupChannelLabel: () => sections.preferencesActions.startupChannelLabel,
    focusOwner: owners.focusOwner,
    pickStartupChannel: sections.preferencesActions.pickStartupChannel,
    setTrackContinueWatching:
        sections.preferencesActions.setTrackContinueWatching,
    setChannelPreviewEnabled:
        sections.preferencesActions.setChannelPreviewEnabled,
  ));
  sections.sourceViewsSlot = IptvSettingsSourceViews((
    sourcesOwner: owners.sourcesOwner,
    focusOwner: owners.focusOwner,
    setDefaultPlaylist: sections.sourceRefresh.setDefaultPlaylist,
    refreshPlaylist: sections.sourceRefresh.refreshPlaylist,
    editPlaylist: sections.sourceEdit.editPlaylist,
    removePlaylist: sections.sourceRemoval.removePlaylist,
    context: scope.context,
    inputOwner: owners.inputOwner,
    focusContentAfterTabSwitch:
        sections.focusActions.focusContentAfterTabSwitch,
    buildUrlTabContent: sections.sourceForms.buildUrlTabContent,
    buildFileTabContent: sections.sourceForms.buildFileTabContent,
    buildXcTabContent: sections.sourceForms.buildXcTabContent,
  ));
  sections.twoPaneSlot = IptvSettingsTwoPaneLayout((
    twoPaneKey: scope.twoPaneKey,
    openAddSource: scope.openAddSource,
    sourcesOwner: owners.sourcesOwner,
    preferencesOwner: owners.preferencesOwner,
    pickAutoRefresh: sections.preferencesActions.pickAutoRefresh,
    customLists: () => sections.listsActions.customLists,
    startupChannelLabel: () => sections.preferencesActions.startupChannelLabel,
    lastLiveChannelLabel: () =>
        sections.preferencesActions.lastLiveChannelLabel,
    inputOwner: owners.inputOwner,
    setState: scope.setState,
    buildUrlTabContent: sections.sourceForms.buildUrlTabContent,
    buildFileTabContent: sections.sourceForms.buildFileTabContent,
    buildXcTabContent: sections.sourceForms.buildXcTabContent,
    focusOwner: owners.focusOwner,
    setDefaultPlaylist: sections.sourceRefresh.setDefaultPlaylist,
    refreshPlaylist: sections.sourceRefresh.refreshPlaylist,
    editPlaylist: sections.sourceEdit.editPlaylist,
    removePlaylist: sections.sourceRemoval.removePlaylist,
    createList: sections.listsActions.createList,
    openChannelOrder: sections.catalogActions.openChannelOrder,
    openCategoryOrder: sections.catalogActions.openCategoryOrder,
    openHiddenCategories: sections.catalogActions.openHiddenCategories,
    focusAndReveal: sections.focusActions.focusAndReveal,
    showListActions: sections.listsActions.showListActions,
    setStartupEnabled: sections.preferencesActions.setStartupEnabled,
    setStartupMode: sections.preferencesActions.setStartupMode,
    pickStartupChannel: sections.preferencesActions.pickStartupChannel,
    setChannelPreviewEnabled:
        sections.preferencesActions.setChannelPreviewEnabled,
    setTrackContinueWatching:
        sections.preferencesActions.setTrackContinueWatching,
    appearanceVisible: scope.appearanceVisible,
    setIptvStyle: sections.preferencesActions.setIptvStyle,
    setPlayerGuideStyle: sections.preferencesActions.setPlayerGuideStyle,
    recordingOwner: owners.recordingOwner,
    mounted: scope.mounted,
    openScheduledRecordings: sections.recordingActions.openScheduledRecordings,
    pickMaxConcurrent: sections.recordingActions.pickMaxConcurrent,
    requestBatteryExemption: sections.recordingActions.requestBatteryExemption,
  ));
  sections.layoutActionsSlot = IptvSettingsLayoutActions((
    setState: scope.setState,
    layoutOwner: owners.layoutOwner,
    mounted: scope.mounted,
    focusOwner: owners.focusOwner,
    buildPhoneHub: sections.phoneHub.buildPhoneHub,
    buildSourcesView: sections.sourceViews.buildSourcesView,
    buildListsView: sections.listViews.buildListsView,
    buildCategoryOrderView: sections.categoryViews.buildCategoryOrderView,
    buildHiddenView: sections.categoryViews.buildHiddenView,
    buildStartupView: sections.preferencesViews.buildStartupView,
    buildChannelPreviewView: sections.preferencesViews.buildChannelPreviewView,
    buildContinueWatchingView:
        sections.preferencesViews.buildContinueWatchingView,
    buildRecordingView: sections.recordingView.buildRecordingView,
  ));
  sections.rootLayoutSlot = IptvSettingsRootLayout((
    mounted: scope.mounted,
    setState: scope.setState,
    sourcesOwner: owners.sourcesOwner,
    layoutOwner: owners.layoutOwner,
    enterPhoneSection: sections.layoutActions.enterPhoneSection,
    focusOwner: owners.focusOwner,
    twoPaneKey: scope.twoPaneKey,
    focusAndReveal: sections.focusActions.focusAndReveal,
    inputOwner: owners.inputOwner,
    buildTwoPane: sections.twoPane.buildTwoPane,
    buildSingleColumn: sections.layoutActions.buildSingleColumn,
  ));
  return sections;
}
