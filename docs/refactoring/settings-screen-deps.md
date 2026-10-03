# Settings hub dependency report

Baseline: `17db33f2`, Flutter 3.44.8. Boundaries and references come from
`dev/tool/verbatim_ast.dart.txt` (analyzer 14.3.0); all destinations below are resolved.
Line numbers refer to the untouched baseline, including documentation comments.

## Ownership and dependencies

All sections live for one Settings State, retired by ProfileGate on a profile switch.
The State keeps both focus resources. Updates owns the subscription and task ID;
its cancellation remains after handler unregistration and focus disposal.
Summary scalars (73 fields) move together before actions; initializers are unchanged.
The report enumerates each owner-local reference. Calls to another destination use
typed, deferred deps callbacks; reads are live getters, never construction snapshots.
Framework deps are `setState`, `mounted: () => mounted`, `context: () => context`;
`widget.summaryReadOverrides` is a live getter. Builder contexts keep their parameters.

`backupSummaryLines` and `formatRestoreReport` are pure: only argument fields,
local collections and string formatting. Their application file imports only
`BackupSummary` and `RestoreReport` with `show` from the existing service declaration;
no service operation, Flutter widget or Riverpod dependency is introduced.

The layout receives `String Function() legacyReasonSummary` from the State.
Both large bodies become top-level functions with signature-preserving methods
on SettingsLayout. `buildSpotlightCategory` remains a method tear-off at the shell.
`buildTvLayout` and `buildLayout` go to the named layout composition bridge at step 6;
the State retains the existing TV/non-TV layout choice and focus interaction.

## Top-level declarations

| Declaration | Destination | Step / layer |
| --- | --- | --- |
| `shouldApplyPendingCredentialOverride` | `application/settings_pending_credentials.dart`, re-exported by facade | 1 / application |
| `SettingsScreen` | `lib/screens/settings_screen.dart` | retained / presentation |
| `_SettingsScreenState` | `lib/screens/settings_screen.dart`; constructor wiring completed at step 6 | retained / presentation |
| `_kAdaptiveSettingsCategories` | `presentation/settings_categories.dart` | 1 / presentation |
| `_SettingsLayout` | `presentation/settings_layout.dart` as `SettingsLayout` | 1 / presentation |
| `_SettingsSearchBar` | `presentation/settings_search_bar.dart` as `SettingsSearchBar` | 1 / presentation |
| `_SettingsSearchBarState` | `presentation/settings_search_bar.dart` with same private name | 1 / presentation |

## Complete declaration manifest

| Original (baseline lines) | Destination file / owner.symbol | Step | Layer |
| --- | --- | --- | --- |
| `shouldApplyPendingCredentialOverride` (173–178) | `lib/features/settings/application/settings_pending_credentials.dart` / `shouldApplyPendingCredentialOverride` | 1 | application |
| `SettingsScreen.SettingsScreen` (181–181) | `lib/screens/settings_screen.dart` / `SettingsScreen.SettingsScreen` | 0 | presentation |
| `SettingsScreen.summaryReadOverrides` (183–184) | `lib/screens/settings_screen.dart` / `SettingsScreen.summaryReadOverrides` | 0 | presentation |
| `SettingsScreen.createState` (186–187) | `lib/screens/settings_screen.dart` / `SettingsScreen.createState` | 0 | presentation |
| `_SettingsScreenState._loading` (191–191) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.loading` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._summaryFailures` (192–192) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.summaryFailures` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._summaryLoadFailed` (193–193) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.summaryLoadFailed` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._summaryUnavailable` (194–194) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.summaryUnavailable` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._isAndroidTv` (195–195) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.isAndroidTv` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._firstCardFocusNode` (198–198) | `lib/screens/settings_screen.dart` / `_SettingsScreenState._firstCardFocusNode` | 0 | presentation |
| `_SettingsScreenState._recordingSearchable` (200–201) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.recordingSearchable` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._isAndroid` (208–208) | `lib/features/settings/presentation/legacy_settings/settings_platform_gates.dart` / `SettingsPlatformGates.isAndroid` | 5 | presentation/legacy_settings |
| `_SettingsScreenState._isTelevision` (209–209) | `lib/features/settings/presentation/legacy_settings/settings_platform_gates.dart` / `SettingsPlatformGates.isTelevision` | 5 | presentation/legacy_settings |
| `_SettingsScreenState._isPhone` (211–214) | `lib/features/settings/presentation/legacy_settings/settings_platform_gates.dart` / `SettingsPlatformGates.isPhone` | 5 | presentation/legacy_settings |
| `_SettingsScreenState._iptvAppearanceSearchable` (216–221) | `lib/features/settings/presentation/legacy_settings/settings_platform_gates.dart` / `SettingsPlatformGates.iptvAppearanceSearchable` | 5 | presentation/legacy_settings |
| `_SettingsScreenState._customPlayerCommandSupported` (223–231) | `lib/features/settings/presentation/legacy_settings/settings_platform_gates.dart` / `SettingsPlatformGates.customPlayerCommandSupported` | 5 | presentation/legacy_settings |
| `_SettingsScreenState._preferredExternalPlayerSupported` (233–240) | `lib/features/settings/presentation/legacy_settings/settings_platform_gates.dart` / `SettingsPlatformGates.preferredExternalPlayerSupported` | 5 | presentation/legacy_settings |
| `_SettingsScreenState._recordingSupported` (242–246) | `lib/features/settings/presentation/legacy_settings/settings_platform_gates.dart` / `SettingsPlatformGates.recordingSupported` | 5 | presentation/legacy_settings |
| `_SettingsScreenState._tvContentFocusHandler` (249–249) | `lib/screens/settings_screen.dart` / `_SettingsScreenState._tvContentFocusHandler` | 0 | presentation |
| `_SettingsScreenState._realDebridConnected` (251–251) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.realDebridConnected` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._realDebridStatus` (252–252) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.realDebridStatus` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._realDebridCaption` (253–253) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.realDebridCaption` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._torboxConnected` (255–255) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.torboxConnected` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._torboxStatus` (256–256) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.torboxStatus` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._torboxCaption` (257–257) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.torboxCaption` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._premiumizeConnected` (259–259) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.premiumizeConnected` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._premiumizeStatus` (260–260) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.premiumizeStatus` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._premiumizeCaption` (261–261) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.premiumizeCaption` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._allDebridConnected` (263–263) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.allDebridConnected` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._allDebridStatus` (264–264) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.allDebridStatus` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._allDebridCaption` (265–265) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.allDebridCaption` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._pikpakConnected` (267–267) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.pikpakConnected` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._pikpakStatus` (268–268) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.pikpakStatus` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._pikpakCaption` (269–269) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.pikpakCaption` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._webDavConnected` (271–271) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.webDavConnected` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._webDavStatus` (272–272) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.webDavStatus` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._webDavCaption` (273–273) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.webDavCaption` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._iptvCredentialsPending` (275–275) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.iptvCredentialsPending` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._traktConnected` (277–277) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.traktConnected` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._traktStatus` (278–278) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.traktStatus` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._traktCaption` (279–279) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.traktCaption` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._simklConnected` (281–281) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.simklConnected` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._simklStatus` (282–282) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.simklStatus` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._simklCaption` (283–283) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.simklCaption` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._mdblistConnected` (285–285) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.mdblistConnected` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._mdblistStatus` (286–286) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.mdblistStatus` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._mdblistCaption` (287–287) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.mdblistCaption` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._indexerManagersConfigured` (289–289) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.indexerManagersConfigured` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._indexerManagersStatus` (290–290) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.indexerManagersStatus` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._indexerManagersCaption` (291–291) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.indexerManagersCaption` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._appVersion` (293–293) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.appVersion` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._currentVersionName` (294–294) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.currentVersionName` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._checkingUpdates` (295–295) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.checkingUpdates` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._updateSubtitle` (296–296) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.updateSubtitle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._updateDownloadSub` (297–297) | `lib/features/settings/presentation/legacy_settings/settings_updates.dart` / `SettingsUpdates._updateDownloadSub` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._updateDownloadTaskId` (298–298) | `lib/features/settings/presentation/legacy_settings/settings_updates.dart` / `SettingsUpdates._updateDownloadTaskId` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._autoUpdateChecksEnabled` (299–299) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.autoUpdateChecksEnabled` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._includeAlphaUpdates` (300–300) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.includeAlphaUpdates` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._diagnosticExportVisible` (301–301) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.diagnosticExportVisible` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._exportingDiagnostics` (302–302) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.exportingDiagnostics` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._tvKeyboardEnabled` (303–303) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.tvKeyboardEnabled` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._tvUiScalePercent` (304–304) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.tvUiScalePercent` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._tvRenderQuality` (305–305) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.tvRenderQuality` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._tvHeroArtworkQuality` (306–306) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.tvHeroArtworkQuality` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._tvHomeStyle` (307–307) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.tvHomeStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._discoverLayout` (308–308) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.discoverLayout` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._tvSidebarStyle` (309–309) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.tvSidebarStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._iptvStyle` (310–310) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.iptvStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._debrifyTvStyle` (311–311) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.debrifyTvStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._playerGuideStyle` (312–312) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.playerGuideStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._playLoaderStyle` (313–313) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.playLoaderStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._tvPlayerControlsStyle` (314–314) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.tvPlayerControlsStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._debrifyTvPlayerStyle` (315–315) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.debrifyTvPlayerStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._playerDockStyle` (316–316) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.playerDockStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._playerDockPalette` (317–317) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.playerDockPalette` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._playerDockSize` (318–318) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.playerDockSize` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._detailPageStyle` (321–321) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.detailPageStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._detailTheme` (322–322) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.detailTheme` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._parentsGuideStyle` (323–323) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.parentsGuideStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._phoneNavStyle` (324–324) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.phoneNavStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._desktopSidebarStyle` (325–325) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.desktopSidebarStyle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._textBrightness` (326–326) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.textBrightness` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._launchAnimation` (327–327) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.launchAnimation` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._downloadLocationSubtitle` (328–328) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.downloadLocationSubtitle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._supportDonation` (329–329) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.supportDonation` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._supportSettingsLabel` (330–330) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.supportSettingsLabel` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._supportSettingsSubtitle` (331–331) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.supportSettingsSubtitle` | 2 | presentation/legacy_settings |
| `_SettingsScreenState.initState` (333–356) | `lib/screens/settings_screen.dart` / `_SettingsScreenState.initState` | 6 | presentation |
| `_SettingsScreenState.dispose` (358–369) | `lib/screens/settings_screen.dart` / `_SettingsScreenState.dispose` | 6 | presentation |
| `_SettingsScreenState._loadSummaries` (371–400) | `lib/features/settings/presentation/legacy_settings/settings_summary_refresh.dart` / `SettingsSummaryRefresh.loadSummaries` | 4 | presentation/legacy_settings |
| `_SettingsScreenState._activeProfileMayExportDiagnostics` (402–419) | `lib/features/settings/presentation/legacy_settings/settings_diagnostics.dart` / `SettingsDiagnostics.activeProfileMayExportDiagnostics` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._loadSummariesForCurrentProfile` (421–1008) | `lib/features/settings/presentation/legacy_settings/settings_summary_loader.dart` / `SettingsSummaryLoader.loadSummariesForCurrentProfile` | 4 | presentation/legacy_settings |
| `_SettingsScreenState._pendingCredentialTypes` (1010–1025) | `lib/features/settings/presentation/legacy_settings/settings_summary_refresh.dart` / `SettingsSummaryRefresh.pendingCredentialTypes` | 4 | presentation/legacy_settings |
| `_SettingsScreenState._loadSupportConfig` (1027–1041) | `lib/features/settings/presentation/legacy_settings/settings_summary_refresh.dart` / `SettingsSummaryRefresh.loadSupportConfig` | 4 | presentation/legacy_settings |
| `_SettingsScreenState._applySupportConfig` (1043–1047) | `lib/features/settings/presentation/legacy_settings/settings_summary_refresh.dart` / `SettingsSummaryRefresh.applySupportConfig` | 4 | presentation/legacy_settings |
| `_SettingsScreenState._openSupportDonation` (1049–1058) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openSupportDonation` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._applyRdUserInfo` (1060–1075) | `lib/features/settings/presentation/legacy_settings/settings_account_captions.dart` / `SettingsAccountCaptions.applyRdUserInfo` | 4 | presentation/legacy_settings |
| `_SettingsScreenState._applyTorboxUserInfo` (1077–1090) | `lib/features/settings/presentation/legacy_settings/settings_account_captions.dart` / `SettingsAccountCaptions.applyTorboxUserInfo` | 4 | presentation/legacy_settings |
| `_SettingsScreenState._applyPremiumizeUserInfo` (1092–1105) | `lib/features/settings/presentation/legacy_settings/settings_account_captions.dart` / `SettingsAccountCaptions.applyPremiumizeUserInfo` | 4 | presentation/legacy_settings |
| `_SettingsScreenState._applyAllDebridUserInfo` (1107–1120) | `lib/features/settings/presentation/legacy_settings/settings_account_captions.dart` / `SettingsAccountCaptions.applyAllDebridUserInfo` | 4 | presentation/legacy_settings |
| `_SettingsScreenState.build` (1122–1158) | `lib/screens/settings_screen.dart` / `_SettingsScreenState.build` | 6 | presentation |
| `_SettingsScreenState._summaryFailureStatus` (1161–1161) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.summaryFailureStatus` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._summaryFailureCaption` (1163–1166) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.summaryFailureCaption` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._rdInfo` (1168–1179) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.rdInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._torboxInfo` (1180–1190) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.torboxInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._premiumizeInfo` (1191–1201) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.premiumizeInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._allDebridInfo` (1202–1212) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.allDebridInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._pikpakInfo` (1213–1223) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.pikpakInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._mediaServerCount` (1224–1224) | `lib/features/settings/presentation/legacy_settings/settings_summaries.dart` / `SettingsSummaries.mediaServerCount` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._mediaServersInfo` (1225–1231) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.mediaServersInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._webDavInfo` (1232–1242) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.webDavInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._iptvInfo` (1243–1257) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.iptvInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._traktInfo` (1258–1268) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.traktInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._simklInfo` (1269–1279) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.simklInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._mdblistInfo` (1280–1290) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.mdblistInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._trackingInfo` (1291–1297) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.trackingInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._indexerManagersInfo` (1298–1310) | `lib/features/settings/presentation/legacy_settings/settings_connections.dart` / `SettingsConnections.indexerManagersInfo` | 2 | presentation/legacy_settings |
| `_SettingsScreenState._buildTvLayout` (1312–1435) | `lib/features/settings/presentation/legacy_settings/settings_layout_composition.dart` / `SettingsLayoutComposition.buildTvLayout` | 6 | presentation/legacy_settings |
| `_SettingsScreenState._buildLayout` (1437–1548) | `lib/features/settings/presentation/legacy_settings/settings_layout_composition.dart` / `SettingsLayoutComposition.buildLayout` | 6 | presentation/legacy_settings |
| `_SettingsScreenState._openSettingsSearch` (1550–1559) | `lib/features/settings/presentation/legacy_settings/settings_search_navigation.dart` / `SettingsSearchNavigation.openSettingsSearch` | 5 | presentation/legacy_settings |
| `_SettingsScreenState._buildSearchIndex` (1561–2937) | `lib/features/settings/presentation/legacy_settings/search_index/settings_search_index.dart` / `SettingsSearchIndex.buildSearchIndex` | 5 | presentation/legacy_settings |
| `_SettingsScreenState._leafSearchEntries` (2939–4968) | `lib/features/settings/presentation/legacy_settings/search_index/settings_search_index.dart` / `SettingsSearchIndex.leafSearchEntries` | 5 | presentation/legacy_settings |
| `_SettingsScreenState._openTorrentSettings` (4970–4976) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openTorrentSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openIndexerManagersSettings` (4978–4995) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openIndexerManagersSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openDebrifyTvSettings` (4997–5001) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openDebrifyTvSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openStremioTvSettings` (5003–5010) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openStremioTvSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openPikPakSettings` (5012–5024) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openPikPakSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openMediaServerSettings` (5026–5031) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openMediaServerSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openWebDavSettings` (5033–5039) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openWebDavSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openTraktSettings` (5041–5049) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openTraktSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openTrackingSettings` (5051–5059) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openTrackingSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openSimklSettings` (5061–5069) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openSimklSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openMdblistSettings` (5071–5079) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openMdblistSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openNavigationSettings` (5081–5149) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openNavigationSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openIptvSettings` (5151–5159) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openIptvSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openIptvChannelOrder` (5161–5165) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openIptvChannelOrder` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openIptvAddSource` (5167–5181) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openIptvAddSource` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openRecordings` (5183–5189) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openRecordings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openMetadataSettings` (5191–5193) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openMetadataSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openBadgesSettings` (5195–5197) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openBadgesSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openCollectionsSettings` (5199–5201) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openCollectionsSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openHomePageSettings` (5203–5209) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openHomePageSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openPlaybackSection` (5211–5220) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openPlaybackSection` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openExternalPlayerSettings` (5222–5228) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openExternalPlayerSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openRemoteControl` (5230–5238) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openRemoteControl` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._switchProfile` (5240–5248) | `lib/features/settings/presentation/legacy_settings/settings_profile_actions.dart` / `SettingsProfileActions.switchProfile` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._mayManageProfiles` (5250–5266) | `lib/features/settings/presentation/legacy_settings/settings_profile_actions.dart` / `SettingsProfileActions.mayManageProfiles` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._profilesDenied` (5268–5273) | `lib/features/settings/presentation/legacy_settings/settings_profile_actions.dart` / `SettingsProfileActions.profilesDenied` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._addProfile` (5275–5286) | `lib/features/settings/presentation/legacy_settings/settings_profile_actions.dart` / `SettingsProfileActions.addProfile` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._editActiveProfile` (5288–5310) | `lib/features/settings/presentation/legacy_settings/settings_profile_actions.dart` / `SettingsProfileActions.editActiveProfile` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openFilterSettings` (5312–5316) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openFilterSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openProviderSettings` (5318–5324) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openProviderSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openQuickPlaySettings` (5326–5330) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openQuickPlaySettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openDiscoverSettings` (5332–5334) | `lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart` / `SettingsPageNavigation.openDiscoverSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openRealDebridSettings` (5336–5348) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openRealDebridSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openTorboxSettings` (5350–5362) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openTorboxSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openPremiumizeSettings` (5364–5376) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openPremiumizeSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openAllDebridSettings` (5378–5390) | `lib/features/settings/presentation/legacy_settings/settings_connection_navigation.dart` / `SettingsConnectionNavigation.openAllDebridSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._focusFirstCard` (5392–5398) | `lib/screens/settings_screen.dart` / `_SettingsScreenState.focusFirstCard` (renamed: borrowed typed focus callback) | 6 | presentation |
| `_SettingsScreenState._ensureProfileFeature` (5400–5424) | `lib/features/settings/presentation/legacy_settings/settings_profile_actions.dart` / `SettingsProfileActions.ensureProfileFeature` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._createProfileBackup` (5426–5427) | `lib/features/settings/presentation/legacy_settings/settings_profile_actions.dart` / `SettingsProfileActions.createProfileBackup` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._restoreProfileBackup` (5429–5437) | `lib/features/settings/presentation/legacy_settings/settings_profile_actions.dart` / `SettingsProfileActions.restoreProfileBackup` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openSyncAndMigrate` (5439–5455) | `lib/features/settings/presentation/legacy_settings/settings_profile_actions.dart` / `SettingsProfileActions.openSyncAndMigrate` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._createBackup` (5457–5721) | `lib/features/settings/presentation/legacy_settings/settings_backup.dart` / `SettingsBackup.createBackup` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._exportDiagnosticLogs` (5723–5789) | `lib/features/settings/presentation/legacy_settings/settings_diagnostics.dart` / `SettingsDiagnostics.exportDiagnosticLogs` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._promptAndDecryptBackup` (5791–5893) | `lib/features/settings/presentation/legacy_settings/settings_restore.dart` / `SettingsRestore.promptAndDecryptBackup` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._restoreBackup` (5895–6130) | `lib/features/settings/presentation/legacy_settings/settings_restore.dart` / `SettingsRestore.restoreBackup` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._backupSummaryLines` (6132–6171) | `lib/features/settings/application/settings_backup_formatting.dart` / `backupSummaryLines` | 3 | application |
| `_SettingsScreenState._formatRestoreReport` (6173–6278) | `lib/features/settings/application/settings_backup_formatting.dart` / `formatRestoreReport` | 3 | application |
| `_SettingsScreenState._downloadLocationSupported` (6283–6284) | `lib/features/settings/presentation/legacy_settings/settings_download_location.dart` / `SettingsDownloadLocation.downloadLocationSupported` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._downloadLocationUsesSaf` (6286–6286) | `lib/features/settings/presentation/legacy_settings/settings_download_location.dart` / `SettingsDownloadLocation.downloadLocationUsesSaf` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._defaultDownloadLocationLabel` (6288–6295) | `lib/features/settings/presentation/legacy_settings/settings_download_location.dart` / `SettingsDownloadLocation.defaultDownloadLocationLabel` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._loadDownloadLocation` (6297–6308) | `lib/features/settings/presentation/legacy_settings/settings_summary_refresh.dart` / `SettingsSummaryRefresh.loadDownloadLocation` | 4 | presentation/legacy_settings |
| `_SettingsScreenState._openDownloadLocationSettings` (6310–6375) | `lib/features/settings/presentation/legacy_settings/settings_download_location.dart` / `SettingsDownloadLocation.openDownloadLocationSettings` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._chooseDownloadFolder` (6377–6398) | `lib/features/settings/presentation/legacy_settings/settings_download_location.dart` / `SettingsDownloadLocation.chooseDownloadFolder` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._chooseDownloadFolderDesktop` (6400–6471) | `lib/features/settings/presentation/legacy_settings/settings_download_location.dart` / `SettingsDownloadLocation.chooseDownloadFolderDesktop` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._resetDownloadFolder` (6473–6492) | `lib/features/settings/presentation/legacy_settings/settings_download_location.dart` / `SettingsDownloadLocation.resetDownloadFolder` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._clearDownloadData` (6494–6522) | `lib/features/settings/presentation/legacy_settings/settings_maintenance.dart` / `SettingsMaintenance.clearDownloadData` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._clearPlaybackData` (6524–6552) | `lib/features/settings/presentation/legacy_settings/settings_maintenance.dart` / `SettingsMaintenance.clearPlaybackData` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._resetAppData` (6554–6729) | `lib/features/settings/presentation/legacy_settings/settings_maintenance.dart` / `SettingsMaintenance.resetAppData` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._checkForAppUpdates` (6731–6773) | `lib/features/settings/presentation/legacy_settings/settings_updates.dart` / `SettingsUpdates.checkForAppUpdates` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._showReleaseDetails` (6775–6934) | `lib/features/settings/presentation/legacy_settings/settings_release_details.dart` / `SettingsReleaseDetails.showReleaseDetails` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._toggleAutoUpdateChecks` (6936–6943) | `lib/features/settings/presentation/legacy_settings/settings_updates.dart` / `SettingsUpdates.toggleAutoUpdateChecks` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._toggleIncludeAlphaUpdates` (6945–6955) | `lib/features/settings/presentation/legacy_settings/settings_updates.dart` / `SettingsUpdates.toggleIncludeAlphaUpdates` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._toggleTvKeyboard` (6957–6962) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.toggleTvKeyboard` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openTvScreenSize` (6964–6975) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openTvScreenSize` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openTvRenderQuality` (6977–6988) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openTvRenderQuality` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openTvHeroArtworkQuality` (6990–6998) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openTvHeroArtworkQuality` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openTvHomeStyle` (7000–7010) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openTvHomeStyle` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openCollectionListStyle` (7012–7015) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openCollectionListStyle` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openDiscoverLayout` (7017–7025) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openDiscoverLayout` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openTvSidebarStyle` (7027–7036) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openTvSidebarStyle` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openDesktopSidebarStyle` (7038–7047) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openDesktopSidebarStyle` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openSidebarCustomization` (7049–7053) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openSidebarCustomization` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openProfileAppearance` (7055–7060) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openProfileAppearance` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openIptvStylePage` (7062–7071) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openIptvStylePage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openDebrifyTvStylePage` (7073–7081) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openDebrifyTvStylePage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openPlayerGuideStylePage` (7083–7092) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openPlayerGuideStylePage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openPlayLoaderStylePage` (7094–7105) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openPlayLoaderStylePage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openTvPlayerControlsStylePage` (7107–7116) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openTvPlayerControlsStylePage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openDebrifyTvPlayerStylePage` (7118–7127) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openDebrifyTvPlayerStylePage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openPlayerDockPage` (7129–7142) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openPlayerDockPage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openDetailPageStylePage` (7144–7153) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openDetailPageStylePage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openDetailThemePage` (7155–7164) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openDetailThemePage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openThemeLab` (7166–7173) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openThemeLab` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openLooksPage` (7175–7182) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openLooksPage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openThemeTokensPage` (7184–7188) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openThemeTokensPage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._themeTokensLabel` (7190–7199) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.themeTokensLabel` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openAppThemePage` (7201–7209) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openAppThemePage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openParentsGuideStylePage` (7211–7219) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openParentsGuideStylePage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openTextBrightnessPage` (7221–7230) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openTextBrightnessPage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openLaunchAnimationPage` (7232–7241) | `lib/features/settings/presentation/legacy_settings/settings_appearance_navigation.dart` / `SettingsAppearanceNavigation.openLaunchAnimationPage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._reloadAppearanceSummaries` (7243–7273) | `lib/features/settings/presentation/legacy_settings/settings_summary_refresh.dart` / `SettingsSummaryRefresh.reloadAppearanceSummaries` | 4 | presentation/legacy_settings |
| `_SettingsScreenState._startAndroidUpdateDownload` (7275–7378) | `lib/features/settings/presentation/legacy_settings/settings_updates.dart` / `SettingsUpdates.startAndroidUpdateDownload` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._ensureInstallPermission` (7380–7393) | `lib/features/settings/presentation/legacy_settings/settings_updates.dart` / `SettingsUpdates.ensureInstallPermission` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._openReleasesPage` (7395–7400) | `lib/features/settings/presentation/legacy_settings/settings_updates.dart` / `SettingsUpdates.openReleasesPage` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._clearUpdateDownloadListener` (7402–7406) | `lib/features/settings/presentation/legacy_settings/settings_updates.dart` / `SettingsUpdates.clearUpdateDownloadListener` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._showSnack` (7408–7413) | `lib/features/settings/presentation/legacy_settings/settings_snacks.dart` / `SettingsSnacks.showSnack` | 3 | presentation/legacy_settings |
| `_SettingsScreenState._tryParseDate` (7415–7421) | `lib/features/settings/presentation/legacy_settings/settings_account_captions.dart` / `SettingsAccountCaptions.tryParseDate` | 4 | presentation/legacy_settings |
| `_SettingsScreenState._formatDate` (7423–7425) | `lib/features/settings/presentation/legacy_settings/settings_account_captions.dart` / `SettingsAccountCaptions.formatDate` | 4 | presentation/legacy_settings |
| `_kAdaptiveSettingsCategories` (7428–7594) | `lib/features/settings/presentation/settings_categories.dart` / `kAdaptiveSettingsCategories` | 1 | presentation |
| `_SettingsLayout.connections` (7597–7597) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.connections` | 1 | presentation |
| `_SettingsLayout.onOpenSearch` (7598–7598) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenSearch` | 1 | presentation |
| `_SettingsLayout.onOpenTorrentSettings` (7599–7599) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenTorrentSettings` | 1 | presentation |
| `_SettingsLayout.onOpenFilterSettings` (7600–7600) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenFilterSettings` | 1 | presentation |
| `_SettingsLayout.onOpenProviderSettings` (7601–7601) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenProviderSettings` | 1 | presentation |
| `_SettingsLayout.onOpenQuickPlaySettings` (7602–7602) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenQuickPlaySettings` | 1 | presentation |
| `_SettingsLayout.onOpenDiscoverSettings` (7603–7603) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenDiscoverSettings` | 1 | presentation |
| `_SettingsLayout.onOpenDebrifyTvSettings` (7604–7604) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenDebrifyTvSettings` | 1 | presentation |
| `_SettingsLayout.onOpenPikPakSettings` (7605–7605) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenPikPakSettings` | 1 | presentation |
| `_SettingsLayout.onOpenHomePageSettings` (7606–7606) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenHomePageSettings` | 1 | presentation |
| `_SettingsLayout.onOpenMetadataSettings` (7607–7607) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenMetadataSettings` | 1 | presentation |
| `_SettingsLayout.onOpenCollectionsSettings` (7608–7608) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenCollectionsSettings` | 1 | presentation |
| `_SettingsLayout.onOpenBadgesSettings` (7609–7609) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenBadgesSettings` | 1 | presentation |
| `_SettingsLayout.onOpenCollectionListStyle` (7610–7610) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenCollectionListStyle` | 1 | presentation |
| `_SettingsLayout.onOpenPlaybackSection` (7611–7611) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenPlaybackSection` | 1 | presentation |
| `_SettingsLayout.onOpenRemoteControl` (7612–7612) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenRemoteControl` | 1 | presentation |
| `_SettingsLayout.showSwitchProfile` (7613–7613) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.showSwitchProfile` | 1 | presentation |
| `_SettingsLayout.onSwitchProfile` (7614–7614) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onSwitchProfile` | 1 | presentation |
| `_SettingsLayout.onAddProfile` (7615–7615) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onAddProfile` | 1 | presentation |
| `_SettingsLayout.onEditProfile` (7616–7616) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onEditProfile` | 1 | presentation |
| `_SettingsLayout.onOpenNavigationSettings` (7617–7617) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenNavigationSettings` | 1 | presentation |
| `_SettingsLayout.isAndroidTv` (7618–7618) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.isAndroidTv` | 1 | presentation |
| `_SettingsLayout.onClearDownloads` (7619–7619) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onClearDownloads` | 1 | presentation |
| `_SettingsLayout.onClearPlayback` (7620–7620) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onClearPlayback` | 1 | presentation |
| `_SettingsLayout.onOpenDownloadLocation` (7622–7622) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenDownloadLocation` | 1 | presentation |
| `_SettingsLayout.downloadLocationSubtitle` (7623–7623) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.downloadLocationSubtitle` | 1 | presentation |
| `_SettingsLayout.onCreateBackup` (7624–7624) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onCreateBackup` | 1 | presentation |
| `_SettingsLayout.onRestoreBackup` (7625–7625) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onRestoreBackup` | 1 | presentation |
| `_SettingsLayout.onOpenSyncAndMigrate` (7626–7626) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenSyncAndMigrate` | 1 | presentation |
| `_SettingsLayout.onExportDiagnosticLogs` (7627–7627) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onExportDiagnosticLogs` | 1 | presentation |
| `_SettingsLayout.onDangerAction` (7628–7628) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onDangerAction` | 1 | presentation |
| `_SettingsLayout.appVersion` (7629–7629) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.appVersion` | 1 | presentation |
| `_SettingsLayout.onCheckForUpdates` (7630–7630) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onCheckForUpdates` | 1 | presentation |
| `_SettingsLayout.updateSubtitle` (7631–7631) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.updateSubtitle` | 1 | presentation |
| `_SettingsLayout.checkingUpdates` (7632–7632) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.checkingUpdates` | 1 | presentation |
| `_SettingsLayout.autoUpdateChecksEnabled` (7633–7633) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.autoUpdateChecksEnabled` | 1 | presentation |
| `_SettingsLayout.onToggleAutoUpdateChecks` (7634–7634) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onToggleAutoUpdateChecks` | 1 | presentation |
| `_SettingsLayout.includeAlphaUpdates` (7635–7635) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.includeAlphaUpdates` | 1 | presentation |
| `_SettingsLayout.onToggleIncludeAlphaUpdates` (7636–7636) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onToggleIncludeAlphaUpdates` | 1 | presentation |
| `_SettingsLayout.tvKeyboardEnabled` (7637–7637) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.tvKeyboardEnabled` | 1 | presentation |
| `_SettingsLayout.onToggleTvKeyboard` (7638–7638) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onToggleTvKeyboard` | 1 | presentation |
| `_SettingsLayout.showSupportDonation` (7639–7639) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.showSupportDonation` | 1 | presentation |
| `_SettingsLayout.supportDonationLabel` (7640–7640) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.supportDonationLabel` | 1 | presentation |
| `_SettingsLayout.supportDonationSubtitle` (7641–7641) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.supportDonationSubtitle` | 1 | presentation |
| `_SettingsLayout.onOpenSupportDonation` (7642–7642) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenSupportDonation` | 1 | presentation |
| `_SettingsLayout.onOpenRecordings` (7644–7644) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenRecordings` | 1 | presentation |
| `_SettingsLayout.onOpenIptvSettings` (7645–7645) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenIptvSettings` | 1 | presentation |
| `_SettingsLayout.showIptvAppearance` (7649–7649) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.showIptvAppearance` | 1 | presentation |
| `_SettingsLayout.debrifyTvStyleLabel` (7650–7650) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.debrifyTvStyleLabel` | 1 | presentation |
| `_SettingsLayout.onOpenDebrifyTvStyle` (7651–7651) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenDebrifyTvStyle` | 1 | presentation |
| `_SettingsLayout.textBrightnessLabel` (7652–7652) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.textBrightnessLabel` | 1 | presentation |
| `_SettingsLayout.onOpenTextBrightness` (7653–7653) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenTextBrightness` | 1 | presentation |
| `_SettingsLayout.launchAnimationLabel` (7654–7654) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.launchAnimationLabel` | 1 | presentation |
| `_SettingsLayout.onOpenLaunchAnimation` (7655–7655) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenLaunchAnimation` | 1 | presentation |
| `_SettingsLayout.iptvStyleLabel` (7656–7656) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.iptvStyleLabel` | 1 | presentation |
| `_SettingsLayout.onOpenIptvStyle` (7657–7657) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenIptvStyle` | 1 | presentation |
| `_SettingsLayout.playerGuideStyleLabel` (7658–7658) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.playerGuideStyleLabel` | 1 | presentation |
| `_SettingsLayout.onOpenPlayerGuideStyle` (7659–7659) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenPlayerGuideStyle` | 1 | presentation |
| `_SettingsLayout.playLoaderStyleLabel` (7660–7660) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.playLoaderStyleLabel` | 1 | presentation |
| `_SettingsLayout.onOpenPlayLoaderStyle` (7661–7661) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenPlayLoaderStyle` | 1 | presentation |
| `_SettingsLayout.playerDockLabel` (7662–7662) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.playerDockLabel` | 1 | presentation |
| `_SettingsLayout.onOpenPlayerDock` (7663–7663) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenPlayerDock` | 1 | presentation |
| `_SettingsLayout.detailPageStyleLabel` (7664–7664) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.detailPageStyleLabel` | 1 | presentation |
| `_SettingsLayout.onOpenDetailPageStyle` (7665–7665) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenDetailPageStyle` | 1 | presentation |
| `_SettingsLayout.appThemeLabel` (7666–7666) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.appThemeLabel` | 1 | presentation |
| `_SettingsLayout.onOpenLooks` (7667–7667) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenLooks` | 1 | presentation |
| `_SettingsLayout.onOpenThemeTokens` (7668–7668) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenThemeTokens` | 1 | presentation |
| `_SettingsLayout.themeTokensLabel` (7669–7669) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.themeTokensLabel` | 1 | presentation |
| `_SettingsLayout.onOpenThemeLab` (7671–7675) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenThemeLab` | 1 | presentation |
| `_SettingsLayout.onOpenAppTheme` (7676–7676) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenAppTheme` | 1 | presentation |
| `_SettingsLayout.detailThemeLabel` (7678–7684) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.detailThemeLabel` | 1 | presentation |
| `_SettingsLayout.onOpenDetailTheme` (7685–7685) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenDetailTheme` | 1 | presentation |
| `_SettingsLayout.parentsGuideStyleLabel` (7686–7686) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.parentsGuideStyleLabel` | 1 | presentation |
| `_SettingsLayout.onOpenParentsGuideStyle` (7687–7687) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenParentsGuideStyle` | 1 | presentation |
| `_SettingsLayout.phoneNavStyleLabel` (7688–7688) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.phoneNavStyleLabel` | 1 | presentation |
| `_SettingsLayout.desktopSidebarStyleLabel` (7689–7689) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.desktopSidebarStyleLabel` | 1 | presentation |
| `_SettingsLayout.onOpenDesktopSidebarStyle` (7690–7690) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenDesktopSidebarStyle` | 1 | presentation |
| `_SettingsLayout.profileAppearanceLabel` (7691–7691) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.profileAppearanceLabel` | 1 | presentation |
| `_SettingsLayout.onOpenProfileAppearance` (7692–7692) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.onOpenProfileAppearance` | 1 | presentation |
| `_SettingsLayout._SettingsLayout` (7694–7774) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.SettingsLayout` | 1 | presentation |
| `_SettingsLayout._providerConnections` (7776–7786) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.providerConnections` | 1 | presentation |
| `_SettingsLayout._trackerServices` (7788–7792) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.trackerServices` | 1 | presentation |
| `_SettingsLayout._showsLargeCollectionStyles` (7794–7796) | `lib/features/settings/presentation/settings_layout.dart` / `SettingsLayout.showsLargeCollectionStyles` | 1 | presentation |
| `_SettingsLayout._buildSpotlight` (7798–7839) | `lib/features/settings/presentation/settings_spotlight_layout.dart` / `buildSpotlightLayout` | 1 | presentation |
| `_SettingsLayout._buildConnectionGrid` (7841–7867) | `lib/features/settings/presentation/settings_connection_grid.dart` / `buildConnectionGrid` | 1 | presentation |
| `_SettingsLayout._buildSpotlightCategory` (7869–8275) | `lib/features/settings/presentation/settings_spotlight_category.dart` / `buildSpotlightCategory` | 1 | presentation |
| `_SettingsLayout.build` (8277–8688) | `lib/features/settings/presentation/settings_classic_layout.dart` / `buildClassicSettingsLayout` | 1 | presentation |
| `_SettingsSearchBar.onTap` (8695–8695) | `lib/features/settings/presentation/settings_search_bar.dart` / `SettingsSearchBar.onTap` | 1 | presentation |
| `_SettingsSearchBar._SettingsSearchBar` (8696–8696) | `lib/features/settings/presentation/settings_search_bar.dart` / `SettingsSearchBar.SettingsSearchBar` | 1 | presentation |
| `_SettingsSearchBar.createState` (8698–8699) | `lib/features/settings/presentation/settings_search_bar.dart` / `SettingsSearchBar.createState` | 1 | presentation |
| `_SettingsSearchBarState._node` (8703–8703) | `lib/features/settings/presentation/settings_search_bar.dart` / `_SettingsSearchBarState._node` | 1 | presentation |
| `_SettingsSearchBarState._hovered` (8704–8704) | `lib/features/settings/presentation/settings_search_bar.dart` / `_SettingsSearchBarState._hovered` | 1 | presentation |
| `_SettingsSearchBarState._focused` (8706–8708) | `lib/features/settings/presentation/settings_search_bar.dart` / `_SettingsSearchBarState._focused` | 1 | presentation |
| `_SettingsSearchBarState.dispose` (8710–8714) | `lib/features/settings/presentation/settings_search_bar.dart` / `_SettingsSearchBarState.dispose` | 1 | presentation |
| `_SettingsSearchBarState.build` (8716–8756) | `lib/features/settings/presentation/settings_search_bar.dart` / `_SettingsSearchBarState.build` | 1 | presentation |

## Every section read, write, call and tear-off

A field listed in both columns is read and written. Method references which are
not invocations are tear-offs. Each cross-section target is resolved in the manifest.
Constructor parameter declarations and named argument labels are excluded.

### `SettingsScreen`

| Member | Reads | Writes | Calls (→ step/destination) | Tear-offs (→ step/destination) |
| --- | --- | --- | --- | --- |
| `SettingsScreen` | — | — | — | — |
| `summaryReadOverrides` | — | — | — | — |
| `createState` | — | — | — | — |
### `_SettingsScreenState`

| Member | Reads | Writes | Calls (→ step/destination) | Tear-offs (→ step/destination) |
| --- | --- | --- | --- | --- |
| `_loading` | — | — | — | — |
| `_summaryFailures` | — | — | — | — |
| `_summaryLoadFailed` | — | — | — | — |
| `_summaryUnavailable` | — | — | — | — |
| `_isAndroidTv` | — | — | — | — |
| `_firstCardFocusNode` | — | — | — | — |
| `_recordingSearchable` | — | — | — | — |
| `_isAndroid` | — | — | — | — |
| `_isTelevision` | — | — | — | — |
| `_isPhone` | — | — | — | — |
| `_iptvAppearanceSearchable` | — | — | — | — |
| `_customPlayerCommandSupported` | — | — | — | — |
| `_preferredExternalPlayerSupported` | — | — | — | — |
| `_recordingSupported` | `_recordingSearchable` | — | — | — |
| `_tvContentFocusHandler` | — | — | — | — |
| `_realDebridConnected` | — | — | — | — |
| `_realDebridStatus` | — | — | — | — |
| `_realDebridCaption` | — | — | — | — |
| `_torboxConnected` | — | — | — | — |
| `_torboxStatus` | — | — | — | — |
| `_torboxCaption` | — | — | — | — |
| `_premiumizeConnected` | — | — | — | — |
| `_premiumizeStatus` | — | — | — | — |
| `_premiumizeCaption` | — | — | — | — |
| `_allDebridConnected` | — | — | — | — |
| `_allDebridStatus` | — | — | — | — |
| `_allDebridCaption` | — | — | — | — |
| `_pikpakConnected` | — | — | — | — |
| `_pikpakStatus` | — | — | — | — |
| `_pikpakCaption` | — | — | — | — |
| `_webDavConnected` | — | — | — | — |
| `_webDavStatus` | — | — | — | — |
| `_webDavCaption` | — | — | — | — |
| `_iptvCredentialsPending` | — | — | — | — |
| `_traktConnected` | — | — | — | — |
| `_traktStatus` | — | — | — | — |
| `_traktCaption` | — | — | — | — |
| `_simklConnected` | — | — | — | — |
| `_simklStatus` | — | — | — | — |
| `_simklCaption` | — | — | — | — |
| `_mdblistConnected` | — | — | — | — |
| `_mdblistStatus` | — | — | — | — |
| `_mdblistCaption` | — | — | — | — |
| `_indexerManagersConfigured` | — | — | — | — |
| `_indexerManagersStatus` | — | — | — | — |
| `_indexerManagersCaption` | — | — | — | — |
| `_appVersion` | — | — | — | — |
| `_currentVersionName` | — | — | — | — |
| `_checkingUpdates` | — | — | — | — |
| `_updateSubtitle` | — | — | — | — |
| `_updateDownloadSub` | — | — | — | — |
| `_updateDownloadTaskId` | — | — | — | — |
| `_autoUpdateChecksEnabled` | — | — | — | — |
| `_includeAlphaUpdates` | — | — | — | — |
| `_diagnosticExportVisible` | — | — | — | — |
| `_exportingDiagnostics` | — | — | — | — |
| `_tvKeyboardEnabled` | — | — | — | — |
| `_tvUiScalePercent` | — | — | — | — |
| `_tvRenderQuality` | — | — | — | — |
| `_tvHeroArtworkQuality` | — | — | — | — |
| `_tvHomeStyle` | — | — | — | — |
| `_discoverLayout` | — | — | — | — |
| `_tvSidebarStyle` | — | — | — | — |
| `_iptvStyle` | — | — | — | — |
| `_debrifyTvStyle` | — | — | — | — |
| `_playerGuideStyle` | — | — | — | — |
| `_playLoaderStyle` | — | — | — | — |
| `_tvPlayerControlsStyle` | — | — | — | — |
| `_debrifyTvPlayerStyle` | — | — | — | — |
| `_playerDockStyle` | — | — | — | — |
| `_playerDockPalette` | — | — | — | — |
| `_playerDockSize` | — | — | — | — |
| `_detailPageStyle` | — | — | — | — |
| `_detailTheme` | — | — | — | — |
| `_parentsGuideStyle` | — | — | — | — |
| `_phoneNavStyle` | — | — | — | — |
| `_desktopSidebarStyle` | — | — | — | — |
| `_textBrightness` | — | — | — | — |
| `_launchAnimation` | — | — | — | — |
| `_downloadLocationSubtitle` | — | — | — | — |
| `_supportDonation` | — | — | — | — |
| `_supportSettingsLabel` | — | — | — | — |
| `_supportSettingsSubtitle` | — | — | — | — |
| `initState` | `_firstCardFocusNode`, `_tvContentFocusHandler` | `_recordingSearchable`, `_tvContentFocusHandler` | `_loadDownloadLocation` → 4/settings_summary_refresh, `_loadSummaries` → 4/settings_summary_refresh, `_loadSupportConfig` → 4/settings_summary_refresh, `initState` → 6/settings_screen | — |
| `dispose` | `_firstCardFocusNode`, `_tvContentFocusHandler`, `_updateDownloadSub` | `_tvContentFocusHandler` | `dispose` → 6/settings_screen | — |
| `_loadSummaries` | — | `_loading`, `_summaryLoadFailed` | `_loadSummariesForCurrentProfile` → 4/settings_summary_loader | — |
| `_activeProfileMayExportDiagnostics` | — | — | — | — |
| `_loadSummariesForCurrentProfile` | `_debrifyTvPlayerStyle`, `_debrifyTvStyle`, `_desktopSidebarStyle`, `_detailPageStyle`, `_detailTheme`, `_discoverLayout`, `_iptvStyle`, `_launchAnimation`, `_parentsGuideStyle`, `_phoneNavStyle`, `_playLoaderStyle`, `_playerDockPalette`, `_playerDockSize`, `_playerDockStyle`, `_playerGuideStyle`, `_summaryFailures`, `_summaryUnavailable`, `_textBrightness`, `_tvHeroArtworkQuality`, `_tvHomeStyle`, `_tvKeyboardEnabled`, `_tvPlayerControlsStyle`, `_tvRenderQuality`, `_tvSidebarStyle`, `_tvUiScalePercent` | `_allDebridCaption`, `_allDebridConnected`, `_allDebridStatus`, `_appVersion`, `_autoUpdateChecksEnabled`, `_currentVersionName`, `_debrifyTvPlayerStyle`, `_debrifyTvStyle`, `_desktopSidebarStyle`, `_detailPageStyle`, `_detailTheme`, `_diagnosticExportVisible`, `_discoverLayout`, `_includeAlphaUpdates`, `_indexerManagersCaption`, `_indexerManagersConfigured`, `_indexerManagersStatus`, `_iptvCredentialsPending`, `_iptvStyle`, `_isAndroidTv`, `_launchAnimation`, `_loading`, `_mdblistCaption`, `_mdblistConnected`, `_mdblistStatus`, `_mediaServerCount`, `_parentsGuideStyle`, `_phoneNavStyle`, `_pikpakCaption`, `_pikpakConnected`, `_pikpakStatus`, `_playLoaderStyle`, `_playerDockPalette`, `_playerDockSize`, `_playerDockStyle`, `_playerGuideStyle`, `_premiumizeCaption`, `_premiumizeConnected`, `_premiumizeStatus`, `_realDebridCaption`, `_realDebridConnected`, `_realDebridStatus`, `_simklCaption`, `_simklConnected`, `_simklStatus`, `_summaryFailures`, `_summaryLoadFailed`, `_summaryUnavailable`, `_textBrightness`, `_torboxCaption`, `_torboxConnected`, `_torboxStatus`, `_traktCaption`, `_traktConnected`, `_traktStatus`, `_tvHeroArtworkQuality`, `_tvHomeStyle`, `_tvKeyboardEnabled`, `_tvPlayerControlsStyle`, `_tvRenderQuality`, `_tvSidebarStyle`, `_tvUiScalePercent`, `_webDavCaption`, `_webDavConnected`, `_webDavStatus` | `_activeProfileMayExportDiagnostics` → 3/settings_diagnostics, `_applyAllDebridUserInfo` → 4/settings_account_captions, `_applyPremiumizeUserInfo` → 4/settings_account_captions, `_applyRdUserInfo` → 4/settings_account_captions, `_applyTorboxUserInfo` → 4/settings_account_captions, `_pendingCredentialTypes` → 4/settings_summary_refresh | — |
| `_pendingCredentialTypes` | — | — | — | — |
| `_loadSupportConfig` | — | — | `_applySupportConfig` → 4/settings_summary_refresh | — |
| `_applySupportConfig` | — | `_supportDonation`, `_supportSettingsLabel`, `_supportSettingsSubtitle` | — | — |
| `_openSupportDonation` | `_supportDonation`, `_supportSettingsLabel` | — | — | — |
| `_applyRdUserInfo` | — | `_realDebridCaption`, `_realDebridStatus` | `_formatDate` → 4/settings_account_captions, `_tryParseDate` → 4/settings_account_captions | — |
| `_applyTorboxUserInfo` | — | `_torboxCaption`, `_torboxStatus` | `_formatDate` → 4/settings_account_captions | — |
| `_applyPremiumizeUserInfo` | — | `_premiumizeCaption`, `_premiumizeStatus` | `_formatDate` → 4/settings_account_captions | — |
| `_applyAllDebridUserInfo` | — | `_allDebridCaption`, `_allDebridStatus` | `_formatDate` → 4/settings_account_captions | — |
| `build` | `_isAndroidTv`, `_loading`, `_summaryFailures`, `_summaryLoadFailed` | — | `_buildLayout` → 6/settings_layout_composition, `_buildTvLayout` → 6/settings_layout_composition | — |
| `_summaryFailureStatus` | — | — | — | — |
| `_summaryFailureCaption` | `_summaryUnavailable` | — | — | — |
| `_rdInfo` | `_realDebridCaption`, `_realDebridConnected`, `_realDebridStatus`, `_summaryFailures` | — | `_summaryFailureCaption` → 2/settings_connections, `_summaryFailureStatus` → 2/settings_connections | `_openRealDebridSettings` → 3/settings_connection_navigation |
| `_torboxInfo` | `_summaryFailures`, `_torboxCaption`, `_torboxConnected`, `_torboxStatus` | — | `_summaryFailureCaption` → 2/settings_connections, `_summaryFailureStatus` → 2/settings_connections | `_openTorboxSettings` → 3/settings_connection_navigation |
| `_premiumizeInfo` | `_premiumizeCaption`, `_premiumizeConnected`, `_premiumizeStatus`, `_summaryFailures` | — | `_summaryFailureCaption` → 2/settings_connections, `_summaryFailureStatus` → 2/settings_connections | `_openPremiumizeSettings` → 3/settings_connection_navigation |
| `_allDebridInfo` | `_allDebridCaption`, `_allDebridConnected`, `_allDebridStatus`, `_summaryFailures` | — | `_summaryFailureCaption` → 2/settings_connections, `_summaryFailureStatus` → 2/settings_connections | `_openAllDebridSettings` → 3/settings_connection_navigation |
| `_pikpakInfo` | `_pikpakCaption`, `_pikpakConnected`, `_pikpakStatus`, `_summaryFailures` | — | `_summaryFailureCaption` → 2/settings_connections, `_summaryFailureStatus` → 2/settings_connections | `_openPikPakSettings` → 3/settings_connection_navigation |
| `_mediaServerCount` | — | — | — | — |
| `_mediaServersInfo` | `_mediaServerCount`, `_summaryFailures` | — | — | `_openMediaServerSettings` → 3/settings_connection_navigation |
| `_webDavInfo` | `_summaryFailures`, `_webDavCaption`, `_webDavConnected`, `_webDavStatus` | — | `_summaryFailureCaption` → 2/settings_connections, `_summaryFailureStatus` → 2/settings_connections | `_openWebDavSettings` → 3/settings_connection_navigation |
| `_iptvInfo` | `_iptvCredentialsPending`, `_summaryFailures` | — | `_summaryFailureCaption` → 2/settings_connections, `_summaryFailureStatus` → 2/settings_connections | `_openIptvSettings` → 3/settings_connection_navigation |
| `_traktInfo` | `_summaryFailures`, `_traktCaption`, `_traktConnected`, `_traktStatus` | — | `_summaryFailureCaption` → 2/settings_connections, `_summaryFailureStatus` → 2/settings_connections | `_openTraktSettings` → 3/settings_connection_navigation |
| `_simklInfo` | `_simklCaption`, `_simklConnected`, `_simklStatus`, `_summaryFailures` | — | `_summaryFailureCaption` → 2/settings_connections, `_summaryFailureStatus` → 2/settings_connections | `_openSimklSettings` → 3/settings_connection_navigation |
| `_mdblistInfo` | `_mdblistCaption`, `_mdblistConnected`, `_mdblistStatus`, `_summaryFailures` | — | `_summaryFailureCaption` → 2/settings_connections, `_summaryFailureStatus` → 2/settings_connections | `_openMdblistSettings` → 3/settings_connection_navigation |
| `_trackingInfo` | — | — | — | `_openTrackingSettings` → 3/settings_connection_navigation |
| `_indexerManagersInfo` | `_indexerManagersCaption`, `_indexerManagersConfigured`, `_indexerManagersStatus`, `_summaryFailures` | — | `_summaryFailureCaption` → 2/settings_connections, `_summaryFailureStatus` → 2/settings_connections | `_openIndexerManagersSettings` → 3/settings_connection_navigation |
| `_buildTvLayout` | `_appVersion`, `_autoUpdateChecksEnabled`, `_checkingUpdates`, `_debrifyTvPlayerStyle`, `_debrifyTvStyle`, `_detailPageStyle`, `_detailTheme`, `_diagnosticExportVisible`, `_discoverLayout`, `_downloadLocationSubtitle`, `_firstCardFocusNode`, `_includeAlphaUpdates`, `_iptvStyle`, `_launchAnimation`, `_parentsGuideStyle`, `_playLoaderStyle`, `_playerGuideStyle`, `_supportDonation`, `_supportSettingsLabel`, `_supportSettingsSubtitle`, `_textBrightness`, `_tvHeroArtworkQuality`, `_tvHomeStyle`, `_tvKeyboardEnabled`, `_tvPlayerControlsStyle`, `_tvRenderQuality`, `_tvSidebarStyle`, `_tvUiScalePercent`, `_updateSubtitle` | — | — | `_addProfile` → 3/settings_profile_actions, `_allDebridInfo` → 2/settings_connections, `_checkForAppUpdates` → 3/settings_updates, `_clearDownloadData` → 3/settings_maintenance, `_clearPlaybackData` → 3/settings_maintenance, `_createBackup` → 3/settings_backup, `_downloadLocationSupported` → 3/settings_download_location, `_editActiveProfile` → 3/settings_profile_actions, `_exportDiagnosticLogs` → 3/settings_diagnostics, `_indexerManagersInfo` → 2/settings_connections, `_iptvInfo` → 2/settings_connections, `_mdblistInfo` → 2/settings_connections, `_mediaServersInfo` → 2/settings_connections, `_openAppThemePage` → 3/settings_appearance_navigation, `_openBadgesSettings` → 3/settings_page_navigation, `_openCollectionListStyle` → 3/settings_appearance_navigation, `_openCollectionsSettings` → 3/settings_page_navigation, `_openDebrifyTvPlayerStylePage` → 3/settings_appearance_navigation, `_openDebrifyTvSettings` → 3/settings_connection_navigation, `_openDebrifyTvStylePage` → 3/settings_appearance_navigation, `_openDetailPageStylePage` → 3/settings_appearance_navigation, `_openDetailThemePage` → 3/settings_appearance_navigation, `_openDiscoverLayout` → 3/settings_appearance_navigation, `_openDiscoverSettings` → 3/settings_page_navigation, `_openDownloadLocationSettings` → 3/settings_download_location, `_openFilterSettings` → 3/settings_page_navigation, `_openHomePageSettings` → 3/settings_page_navigation, `_openIptvSettings` → 3/settings_connection_navigation, `_openIptvStylePage` → 3/settings_appearance_navigation, `_openLaunchAnimationPage` → 3/settings_appearance_navigation, `_openLooksPage` → 3/settings_appearance_navigation, `_openMetadataSettings` → 3/settings_page_navigation, `_openParentsGuideStylePage` → 3/settings_appearance_navigation, `_openPlayLoaderStylePage` → 3/settings_appearance_navigation, `_openPlaybackSection` → 3/settings_page_navigation, `_openPlayerGuideStylePage` → 3/settings_appearance_navigation, `_openProfileAppearance` → 3/settings_appearance_navigation, `_openProviderSettings` → 3/settings_page_navigation, `_openQuickPlaySettings` → 3/settings_page_navigation, `_openRecordings` → 3/settings_page_navigation, `_openRemoteControl` → 3/settings_page_navigation, `_openSettingsSearch` → 5/settings_search_navigation, `_openSupportDonation` → 3/settings_page_navigation, `_openSyncAndMigrate` → 3/settings_profile_actions, `_openTextBrightnessPage` → 3/settings_appearance_navigation, `_openThemeLab` → 3/settings_appearance_navigation, `_openThemeTokensPage` → 3/settings_appearance_navigation, `_openTorrentSettings` → 3/settings_connection_navigation, `_openTvHeroArtworkQuality` → 3/settings_appearance_navigation, `_openTvHomeStyle` → 3/settings_appearance_navigation, `_openTvPlayerControlsStylePage` → 3/settings_appearance_navigation, `_openTvRenderQuality` → 3/settings_appearance_navigation, `_openTvScreenSize` → 3/settings_appearance_navigation, `_openTvSidebarStyle` → 3/settings_appearance_navigation, `_pikpakInfo` → 2/settings_connections, `_premiumizeInfo` → 2/settings_connections, `_rdInfo` → 2/settings_connections, `_resetAppData` → 3/settings_maintenance, `_restoreBackup` → 3/settings_restore, `_simklInfo` → 2/settings_connections, `_switchProfile` → 3/settings_profile_actions, `_themeTokensLabel` → 3/settings_appearance_navigation, `_toggleAutoUpdateChecks` → 3/settings_updates, `_toggleIncludeAlphaUpdates` → 3/settings_updates, `_toggleTvKeyboard` → 3/settings_appearance_navigation, `_torboxInfo` → 2/settings_connections, `_trackingInfo` → 2/settings_connections, `_traktInfo` → 2/settings_connections, `_webDavInfo` → 2/settings_connections |
| `_buildLayout` | `_appVersion`, `_autoUpdateChecksEnabled`, `_checkingUpdates`, `_debrifyTvStyle`, `_desktopSidebarStyle`, `_detailPageStyle`, `_detailTheme`, `_diagnosticExportVisible`, `_downloadLocationSubtitle`, `_firstCardFocusNode`, `_includeAlphaUpdates`, `_iptvStyle`, `_isAndroidTv`, `_launchAnimation`, `_parentsGuideStyle`, `_phoneNavStyle`, `_playLoaderStyle`, `_playerDockPalette`, `_playerDockSize`, `_playerDockStyle`, `_playerGuideStyle`, `_supportDonation`, `_supportSettingsLabel`, `_supportSettingsSubtitle`, `_textBrightness`, `_tvKeyboardEnabled`, `_updateSubtitle` | — | — | `_addProfile` → 3/settings_profile_actions, `_allDebridInfo` → 2/settings_connections, `_checkForAppUpdates` → 3/settings_updates, `_clearDownloadData` → 3/settings_maintenance, `_clearPlaybackData` → 3/settings_maintenance, `_createBackup` → 3/settings_backup, `_downloadLocationSupported` → 3/settings_download_location, `_editActiveProfile` → 3/settings_profile_actions, `_exportDiagnosticLogs` → 3/settings_diagnostics, `_indexerManagersInfo` → 2/settings_connections, `_iptvAppearanceSearchable` → 5/settings_platform_gates, `_iptvInfo` → 2/settings_connections, `_mdblistInfo` → 2/settings_connections, `_mediaServersInfo` → 2/settings_connections, `_openAppThemePage` → 3/settings_appearance_navigation, `_openBadgesSettings` → 3/settings_page_navigation, `_openCollectionListStyle` → 3/settings_appearance_navigation, `_openCollectionsSettings` → 3/settings_page_navigation, `_openDebrifyTvSettings` → 3/settings_connection_navigation, `_openDebrifyTvStylePage` → 3/settings_appearance_navigation, `_openDesktopSidebarStyle` → 3/settings_appearance_navigation, `_openDetailPageStylePage` → 3/settings_appearance_navigation, `_openDetailThemePage` → 3/settings_appearance_navigation, `_openDiscoverSettings` → 3/settings_page_navigation, `_openDownloadLocationSettings` → 3/settings_download_location, `_openFilterSettings` → 3/settings_page_navigation, `_openHomePageSettings` → 3/settings_page_navigation, `_openIptvSettings` → 3/settings_connection_navigation, `_openIptvStylePage` → 3/settings_appearance_navigation, `_openLaunchAnimationPage` → 3/settings_appearance_navigation, `_openLooksPage` → 3/settings_appearance_navigation, `_openMetadataSettings` → 3/settings_page_navigation, `_openNavigationSettings` → 3/settings_connection_navigation, `_openParentsGuideStylePage` → 3/settings_appearance_navigation, `_openPikPakSettings` → 3/settings_connection_navigation, `_openPlayLoaderStylePage` → 3/settings_appearance_navigation, `_openPlaybackSection` → 3/settings_page_navigation, `_openPlayerDockPage` → 3/settings_appearance_navigation, `_openPlayerGuideStylePage` → 3/settings_appearance_navigation, `_openProfileAppearance` → 3/settings_appearance_navigation, `_openProviderSettings` → 3/settings_page_navigation, `_openQuickPlaySettings` → 3/settings_page_navigation, `_openRecordings` → 3/settings_page_navigation, `_openRemoteControl` → 3/settings_page_navigation, `_openSettingsSearch` → 5/settings_search_navigation, `_openSupportDonation` → 3/settings_page_navigation, `_openSyncAndMigrate` → 3/settings_profile_actions, `_openTextBrightnessPage` → 3/settings_appearance_navigation, `_openThemeLab` → 3/settings_appearance_navigation, `_openThemeTokensPage` → 3/settings_appearance_navigation, `_openTorrentSettings` → 3/settings_connection_navigation, `_pikpakInfo` → 2/settings_connections, `_premiumizeInfo` → 2/settings_connections, `_rdInfo` → 2/settings_connections, `_resetAppData` → 3/settings_maintenance, `_restoreBackup` → 3/settings_restore, `_simklInfo` → 2/settings_connections, `_switchProfile` → 3/settings_profile_actions, `_themeTokensLabel` → 3/settings_appearance_navigation, `_toggleAutoUpdateChecks` → 3/settings_updates, `_toggleIncludeAlphaUpdates` → 3/settings_updates, `_toggleTvKeyboard` → 3/settings_appearance_navigation, `_torboxInfo` → 2/settings_connections, `_trackingInfo` → 2/settings_connections, `_traktInfo` → 2/settings_connections, `_webDavInfo` → 2/settings_connections |
| `_openSettingsSearch` | — | — | `_buildSearchIndex` → 5/settings_search_index | — |
| `_buildSearchIndex` | `_autoUpdateChecksEnabled`, `_debrifyTvPlayerStyle`, `_debrifyTvStyle`, `_desktopSidebarStyle`, `_detailPageStyle`, `_diagnosticExportVisible`, `_discoverLayout`, `_downloadLocationSubtitle`, `_includeAlphaUpdates`, `_iptvStyle`, `_isAndroidTv`, `_launchAnimation`, `_parentsGuideStyle`, `_playLoaderStyle`, `_playerDockPalette`, `_playerDockSize`, `_playerDockStyle`, `_playerGuideStyle`, `_supportDonation`, `_supportSettingsLabel`, `_supportSettingsSubtitle`, `_textBrightness`, `_tvHeroArtworkQuality`, `_tvHomeStyle`, `_tvKeyboardEnabled`, `_tvPlayerControlsStyle`, `_tvRenderQuality`, `_tvSidebarStyle`, `_tvUiScalePercent`, `_updateSubtitle` | — | `_leafSearchEntries` → 5/settings_search_index | `_addProfile` → 3/settings_profile_actions, `_allDebridInfo` → 2/settings_connections, `_checkForAppUpdates` → 3/settings_updates, `_clearDownloadData` → 3/settings_maintenance, `_clearPlaybackData` → 3/settings_maintenance, `_createBackup` → 3/settings_backup, `_downloadLocationSupported` → 3/settings_download_location, `_editActiveProfile` → 3/settings_profile_actions, `_exportDiagnosticLogs` → 3/settings_diagnostics, `_indexerManagersInfo` → 2/settings_connections, `_iptvAppearanceSearchable` → 5/settings_platform_gates, `_iptvInfo` → 2/settings_connections, `_isAndroid` → 5/settings_platform_gates, `_isTelevision` → 5/settings_platform_gates, `_leafSearchEntries` → 5/settings_search_index, `_mdblistInfo` → 2/settings_connections, `_mediaServersInfo` → 2/settings_connections, `_openBadgesSettings` → 3/settings_page_navigation, `_openCollectionListStyle` → 3/settings_appearance_navigation, `_openCollectionsSettings` → 3/settings_page_navigation, `_openDebrifyTvPlayerStylePage` → 3/settings_appearance_navigation, `_openDebrifyTvSettings` → 3/settings_connection_navigation, `_openDebrifyTvStylePage` → 3/settings_appearance_navigation, `_openDesktopSidebarStyle` → 3/settings_appearance_navigation, `_openDetailPageStylePage` → 3/settings_appearance_navigation, `_openDiscoverLayout` → 3/settings_appearance_navigation, `_openDiscoverSettings` → 3/settings_page_navigation, `_openDownloadLocationSettings` → 3/settings_download_location, `_openExternalPlayerSettings` → 3/settings_page_navigation, `_openFilterSettings` → 3/settings_page_navigation, `_openHomePageSettings` → 3/settings_page_navigation, `_openIptvSettings` → 3/settings_connection_navigation, `_openIptvStylePage` → 3/settings_appearance_navigation, `_openLaunchAnimationPage` → 3/settings_appearance_navigation, `_openLooksPage` → 3/settings_appearance_navigation, `_openMetadataSettings` → 3/settings_page_navigation, `_openNavigationSettings` → 3/settings_connection_navigation, `_openParentsGuideStylePage` → 3/settings_appearance_navigation, `_openPlayLoaderStylePage` → 3/settings_appearance_navigation, `_openPlayerDockPage` → 3/settings_appearance_navigation, `_openPlayerGuideStylePage` → 3/settings_appearance_navigation, `_openProfileAppearance` → 3/settings_appearance_navigation, `_openProviderSettings` → 3/settings_page_navigation, `_openQuickPlaySettings` → 3/settings_page_navigation, `_openRecordings` → 3/settings_page_navigation, `_openRemoteControl` → 3/settings_page_navigation, `_openStremioTvSettings` → 3/settings_connection_navigation, `_openSupportDonation` → 3/settings_page_navigation, `_openSyncAndMigrate` → 3/settings_profile_actions, `_openTextBrightnessPage` → 3/settings_appearance_navigation, `_openThemeTokensPage` → 3/settings_appearance_navigation, `_openTorrentSettings` → 3/settings_connection_navigation, `_openTvHeroArtworkQuality` → 3/settings_appearance_navigation, `_openTvHomeStyle` → 3/settings_appearance_navigation, `_openTvPlayerControlsStylePage` → 3/settings_appearance_navigation, `_openTvRenderQuality` → 3/settings_appearance_navigation, `_openTvScreenSize` → 3/settings_appearance_navigation, `_openTvSidebarStyle` → 3/settings_appearance_navigation, `_pikpakInfo` → 2/settings_connections, `_premiumizeInfo` → 2/settings_connections, `_rdInfo` → 2/settings_connections, `_resetAppData` → 3/settings_maintenance, `_restoreBackup` → 3/settings_restore, `_simklInfo` → 2/settings_connections, `_switchProfile` → 3/settings_profile_actions, `_themeTokensLabel` → 3/settings_appearance_navigation, `_toggleAutoUpdateChecks` → 3/settings_updates, `_toggleIncludeAlphaUpdates` → 3/settings_updates, `_toggleTvKeyboard` → 3/settings_appearance_navigation, `_torboxInfo` → 2/settings_connections, `_trackingInfo` → 2/settings_connections, `_traktInfo` → 2/settings_connections, `_webDavInfo` → 2/settings_connections |
| `_leafSearchEntries` | `_recordingSearchable` | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_openPlaybackSection` → 3/settings_page_navigation | `_customPlayerCommandSupported` → 5/settings_platform_gates, `_isAndroid` → 5/settings_platform_gates, `_isPhone` → 5/settings_platform_gates, `_isTelevision` → 5/settings_platform_gates, `_openAllDebridSettings` → 3/settings_connection_navigation, `_openDebrifyTvSettings` → 3/settings_connection_navigation, `_openExternalPlayerSettings` → 3/settings_page_navigation, `_openFilterSettings` → 3/settings_page_navigation, `_openHomePageSettings` → 3/settings_page_navigation, `_openIndexerManagersSettings` → 3/settings_connection_navigation, `_openIptvAddSource` → 3/settings_connection_navigation, `_openIptvChannelOrder` → 3/settings_connection_navigation, `_openIptvSettings` → 3/settings_connection_navigation, `_openLaunchAnimationPage` → 3/settings_appearance_navigation, `_openMdblistSettings` → 3/settings_connection_navigation, `_openPikPakSettings` → 3/settings_connection_navigation, `_openPremiumizeSettings` → 3/settings_connection_navigation, `_openProfileAppearance` → 3/settings_appearance_navigation, `_openProviderSettings` → 3/settings_page_navigation, `_openQuickPlaySettings` → 3/settings_page_navigation, `_openRealDebridSettings` → 3/settings_connection_navigation, `_openRecordings` → 3/settings_page_navigation, `_openRemoteControl` → 3/settings_page_navigation, `_openSidebarCustomization` → 3/settings_appearance_navigation, `_openSimklSettings` → 3/settings_connection_navigation, `_openStremioTvSettings` → 3/settings_connection_navigation, `_openThemeTokensPage` → 3/settings_appearance_navigation, `_openTorboxSettings` → 3/settings_connection_navigation, `_openTorrentSettings` → 3/settings_connection_navigation, `_openTrackingSettings` → 3/settings_connection_navigation, `_openTraktSettings` → 3/settings_connection_navigation, `_openWebDavSettings` → 3/settings_connection_navigation, `_preferredExternalPlayerSupported` → 5/settings_platform_gates, `_recordingSupported` → 5/settings_platform_gates, `_switchProfile` → 3/settings_profile_actions |
| `_openTorrentSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions | — |
| `_openIndexerManagersSettings` | — | `_indexerManagersCaption`, `_indexerManagersConfigured`, `_indexerManagersStatus` | `_ensureProfileFeature` → 3/settings_profile_actions | — |
| `_openDebrifyTvSettings` | — | — | — | — |
| `_openStremioTvSettings` | — | — | — | — |
| `_openPikPakSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_focusFirstCard` → 6/settings_screen, `_loadSummaries` → 4/settings_summary_refresh | — |
| `_openMediaServerSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_loadSummaries` → 4/settings_summary_refresh | — |
| `_openWebDavSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_loadSummaries` → 4/settings_summary_refresh | — |
| `_openTraktSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_loadSummaries` → 4/settings_summary_refresh | — |
| `_openTrackingSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions | — |
| `_openSimklSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_loadSummaries` → 4/settings_summary_refresh | — |
| `_openMdblistSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_loadSummaries` → 4/settings_summary_refresh | — |
| `_openNavigationSettings` | — | `_phoneNavStyle` | — | — |
| `_openIptvSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_reloadAppearanceSummaries` → 4/settings_summary_refresh | — |
| `_openIptvChannelOrder` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions | — |
| `_openIptvAddSource` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_reloadAppearanceSummaries` → 4/settings_summary_refresh | — |
| `_openRecordings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions | — |
| `_openMetadataSettings` | — | — | — | — |
| `_openBadgesSettings` | — | — | — | — |
| `_openCollectionsSettings` | — | — | — | — |
| `_openHomePageSettings` | — | — | `_reloadAppearanceSummaries` → 4/settings_summary_refresh | — |
| `_openPlaybackSection` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_reloadAppearanceSummaries` → 4/settings_summary_refresh | — |
| `_openExternalPlayerSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_reloadAppearanceSummaries` → 4/settings_summary_refresh | — |
| `_openRemoteControl` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions | — |
| `_switchProfile` | — | `_diagnosticExportVisible` | `_activeProfileMayExportDiagnostics` → 3/settings_diagnostics | — |
| `_mayManageProfiles` | — | — | — | — |
| `_profilesDenied` | — | — | — | — |
| `_addProfile` | — | — | `_mayManageProfiles` → 3/settings_profile_actions, `_profilesDenied` → 3/settings_profile_actions | — |
| `_editActiveProfile` | — | — | `_mayManageProfiles` → 3/settings_profile_actions, `_profilesDenied` → 3/settings_profile_actions | — |
| `_openFilterSettings` | — | — | — | — |
| `_openProviderSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions | — |
| `_openQuickPlaySettings` | — | — | — | — |
| `_openDiscoverSettings` | — | — | — | — |
| `_openRealDebridSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_focusFirstCard` → 6/settings_screen, `_loadSummaries` → 4/settings_summary_refresh | — |
| `_openTorboxSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_focusFirstCard` → 6/settings_screen, `_loadSummaries` → 4/settings_summary_refresh | — |
| `_openPremiumizeSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_focusFirstCard` → 6/settings_screen, `_loadSummaries` → 4/settings_summary_refresh | — |
| `_openAllDebridSettings` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions, `_focusFirstCard` → 6/settings_screen, `_loadSummaries` → 4/settings_summary_refresh | — |
| `_focusFirstCard` | `_firstCardFocusNode` | — | — | — |
| `_ensureProfileFeature` | — | — | — | — |
| `_createProfileBackup` | — | — | — | — |
| `_restoreProfileBackup` | — | — | `_loadSummaries` → 4/settings_summary_refresh | — |
| `_openSyncAndMigrate` | — | — | `_ensureProfileFeature` → 3/settings_profile_actions | — |
| `_createBackup` | — | — | `_backupSummaryLines` → 3/settings_backup_formatting, `_createProfileBackup` → 3/settings_profile_actions, `dispose` → 6/settings_screen | — |
| `_exportDiagnosticLogs` | `_exportingDiagnostics` | `_diagnosticExportVisible`, `_exportingDiagnostics` | `_activeProfileMayExportDiagnostics` → 3/settings_diagnostics | — |
| `_promptAndDecryptBackup` | — | — | `dispose` → 6/settings_screen | — |
| `_restoreBackup` | — | — | `_backupSummaryLines` → 3/settings_backup_formatting, `_formatRestoreReport` → 3/settings_backup_formatting, `_loadSummaries` → 4/settings_summary_refresh, `_promptAndDecryptBackup` → 3/settings_restore, `_restoreProfileBackup` → 3/settings_profile_actions | — |
| `_backupSummaryLines` | — | — | — | — |
| `_formatRestoreReport` | — | — | — | — |
| `_downloadLocationSupported` | — | — | — | — |
| `_downloadLocationUsesSaf` | — | — | — | — |
| `_defaultDownloadLocationLabel` | — | — | — | `_downloadLocationUsesSaf` → 3/settings_download_location |
| `_loadDownloadLocation` | — | `_downloadLocationSubtitle` | — | `_defaultDownloadLocationLabel` → 3/settings_download_location, `_downloadLocationSupported` → 3/settings_download_location, `_downloadLocationUsesSaf` → 3/settings_download_location |
| `_openDownloadLocationSettings` | `_downloadLocationSubtitle` | — | `_chooseDownloadFolder` → 3/settings_download_location, `_resetDownloadFolder` → 3/settings_download_location | `_defaultDownloadLocationLabel` → 3/settings_download_location, `_downloadLocationUsesSaf` → 3/settings_download_location |
| `_chooseDownloadFolder` | — | — | `_chooseDownloadFolderDesktop` → 3/settings_download_location, `_loadDownloadLocation` → 4/settings_summary_refresh | `_downloadLocationUsesSaf` → 3/settings_download_location |
| `_chooseDownloadFolderDesktop` | — | — | `_loadDownloadLocation` → 4/settings_summary_refresh | — |
| `_resetDownloadFolder` | — | — | `_loadDownloadLocation` → 4/settings_summary_refresh | `_defaultDownloadLocationLabel` → 3/settings_download_location, `_downloadLocationUsesSaf` → 3/settings_download_location |
| `_clearDownloadData` | — | — | — | — |
| `_clearPlaybackData` | — | — | — | — |
| `_resetAppData` | — | — | `_loadSummaries` → 4/settings_summary_refresh, `dispose` → 6/settings_screen | — |
| `_checkForAppUpdates` | `_checkingUpdates`, `_currentVersionName`, `_includeAlphaUpdates` | `_checkingUpdates`, `_updateSubtitle` | `_ensureProfileFeature` → 3/settings_profile_actions, `_showReleaseDetails` → 3/settings_release_details, `_showSnack` → 3/settings_snacks | — |
| `_showReleaseDetails` | `_appVersion` | — | `_openReleasesPage` → 3/settings_updates, `_startAndroidUpdateDownload` → 3/settings_updates | — |
| `_toggleAutoUpdateChecks` | — | `_autoUpdateChecksEnabled` | `_ensureProfileFeature` → 3/settings_profile_actions | — |
| `_toggleIncludeAlphaUpdates` | — | `_includeAlphaUpdates`, `_updateSubtitle` | `_ensureProfileFeature` → 3/settings_profile_actions | — |
| `_toggleTvKeyboard` | — | `_tvKeyboardEnabled` | — | — |
| `_openTvScreenSize` | — | `_tvUiScalePercent` | — | — |
| `_openTvRenderQuality` | — | `_tvRenderQuality` | — | `_openTvScreenSize` → 3/settings_appearance_navigation |
| `_openTvHeroArtworkQuality` | — | `_tvHeroArtworkQuality` | — | — |
| `_openTvHomeStyle` | — | `_tvHomeStyle` | — | — |
| `_openCollectionListStyle` | — | — | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_openDiscoverLayout` | — | `_discoverLayout` | — | — |
| `_openTvSidebarStyle` | — | `_tvSidebarStyle` | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_openDesktopSidebarStyle` | — | `_desktopSidebarStyle` | — | — |
| `_openSidebarCustomization` | — | — | — | — |
| `_openProfileAppearance` | — | — | — | — |
| `_openIptvStylePage` | — | `_iptvStyle` | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_openDebrifyTvStylePage` | — | `_debrifyTvStyle` | — | — |
| `_openPlayerGuideStylePage` | — | `_playerGuideStyle` | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_openPlayLoaderStylePage` | — | `_playLoaderStyle` | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_openTvPlayerControlsStylePage` | — | `_tvPlayerControlsStyle` | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_openDebrifyTvPlayerStylePage` | — | `_debrifyTvPlayerStyle` | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_openPlayerDockPage` | — | `_playerDockPalette`, `_playerDockSize`, `_playerDockStyle` | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_openDetailPageStylePage` | — | `_detailPageStyle` | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_openDetailThemePage` | — | `_detailTheme` | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_openThemeLab` | — | — | — | — |
| `_openLooksPage` | — | — | — | — |
| `_openThemeTokensPage` | — | — | — | — |
| `_themeTokensLabel` | — | — | — | — |
| `_openAppThemePage` | — | `_detailTheme` | — | — |
| `_openParentsGuideStylePage` | — | `_parentsGuideStyle` | — | — |
| `_openTextBrightnessPage` | — | `_textBrightness` | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_openLaunchAnimationPage` | — | `_launchAnimation` | — | `_openTvHomeStyle` → 3/settings_appearance_navigation |
| `_reloadAppearanceSummaries` | — | `_debrifyTvPlayerStyle`, `_debrifyTvStyle`, `_iptvStyle`, `_playLoaderStyle`, `_playerDockPalette`, `_playerDockSize`, `_playerDockStyle`, `_playerGuideStyle`, `_tvHomeStyle`, `_tvPlayerControlsStyle` | — | `_loadSummaries` → 4/settings_summary_refresh |
| `_startAndroidUpdateDownload` | `_updateDownloadSub`, `_updateDownloadTaskId` | `_updateDownloadSub`, `_updateDownloadTaskId`, `_updateSubtitle` | `_clearUpdateDownloadListener` → 3/settings_updates, `_ensureInstallPermission` → 3/settings_updates, `_openReleasesPage` → 3/settings_updates, `_showSnack` → 3/settings_snacks | — |
| `_ensureInstallPermission` | — | — | `_showSnack` → 3/settings_snacks | — |
| `_openReleasesPage` | — | — | `_showSnack` → 3/settings_snacks | — |
| `_clearUpdateDownloadListener` | `_updateDownloadSub` | `_updateDownloadSub`, `_updateDownloadTaskId` | — | — |
| `_showSnack` | — | — | — | — |
| `_tryParseDate` | — | — | — | — |
| `_formatDate` | — | — | — | — |
### `_SettingsLayout`

| Member | Reads | Writes | Calls (→ step/destination) | Tear-offs (→ step/destination) |
| --- | --- | --- | --- | --- |
| `connections` | — | — | — | — |
| `onOpenSearch` | — | — | — | — |
| `onOpenTorrentSettings` | — | — | — | — |
| `onOpenFilterSettings` | — | — | — | — |
| `onOpenProviderSettings` | — | — | — | — |
| `onOpenQuickPlaySettings` | — | — | — | — |
| `onOpenDiscoverSettings` | — | — | — | — |
| `onOpenDebrifyTvSettings` | — | — | — | — |
| `onOpenPikPakSettings` | — | — | — | — |
| `onOpenHomePageSettings` | — | — | — | — |
| `onOpenMetadataSettings` | — | — | — | — |
| `onOpenCollectionsSettings` | — | — | — | — |
| `onOpenBadgesSettings` | — | — | — | — |
| `onOpenCollectionListStyle` | — | — | — | — |
| `onOpenPlaybackSection` | — | — | — | — |
| `onOpenRemoteControl` | — | — | — | — |
| `showSwitchProfile` | — | — | — | — |
| `onSwitchProfile` | — | — | — | — |
| `onAddProfile` | — | — | — | — |
| `onEditProfile` | — | — | — | — |
| `onOpenNavigationSettings` | — | — | — | — |
| `isAndroidTv` | — | — | — | — |
| `onClearDownloads` | — | — | — | — |
| `onClearPlayback` | — | — | — | — |
| `onOpenDownloadLocation` | — | — | — | — |
| `downloadLocationSubtitle` | — | — | — | — |
| `onCreateBackup` | — | — | — | — |
| `onRestoreBackup` | — | — | — | — |
| `onOpenSyncAndMigrate` | — | — | — | — |
| `onExportDiagnosticLogs` | — | — | — | — |
| `onDangerAction` | — | — | — | — |
| `appVersion` | — | — | — | — |
| `onCheckForUpdates` | — | — | — | — |
| `updateSubtitle` | — | — | — | — |
| `checkingUpdates` | — | — | — | — |
| `autoUpdateChecksEnabled` | — | — | — | — |
| `onToggleAutoUpdateChecks` | — | — | — | — |
| `includeAlphaUpdates` | — | — | — | — |
| `onToggleIncludeAlphaUpdates` | — | — | — | — |
| `tvKeyboardEnabled` | — | — | — | — |
| `onToggleTvKeyboard` | — | — | — | — |
| `showSupportDonation` | — | — | — | — |
| `supportDonationLabel` | — | — | — | — |
| `supportDonationSubtitle` | — | — | — | — |
| `onOpenSupportDonation` | — | — | — | — |
| `onOpenRecordings` | — | — | — | — |
| `onOpenIptvSettings` | — | — | — | — |
| `showIptvAppearance` | — | — | — | — |
| `debrifyTvStyleLabel` | — | — | — | — |
| `onOpenDebrifyTvStyle` | — | — | — | — |
| `textBrightnessLabel` | — | — | — | — |
| `onOpenTextBrightness` | — | — | — | — |
| `launchAnimationLabel` | — | — | — | — |
| `onOpenLaunchAnimation` | — | — | — | — |
| `iptvStyleLabel` | — | — | — | — |
| `onOpenIptvStyle` | — | — | — | — |
| `playerGuideStyleLabel` | — | — | — | — |
| `onOpenPlayerGuideStyle` | — | — | — | — |
| `playLoaderStyleLabel` | — | — | — | — |
| `onOpenPlayLoaderStyle` | — | — | — | — |
| `playerDockLabel` | — | — | — | — |
| `onOpenPlayerDock` | — | — | — | — |
| `detailPageStyleLabel` | — | — | — | — |
| `onOpenDetailPageStyle` | — | — | — | — |
| `appThemeLabel` | — | — | — | — |
| `onOpenLooks` | — | — | — | — |
| `onOpenThemeTokens` | — | — | — | — |
| `themeTokensLabel` | — | — | — | — |
| `onOpenThemeLab` | `detailThemeLabel` | — | — | — |
| `onOpenAppTheme` | — | — | — | — |
| `detailThemeLabel` | — | — | — | — |
| `onOpenDetailTheme` | — | — | — | — |
| `parentsGuideStyleLabel` | — | — | — | — |
| `onOpenParentsGuideStyle` | — | — | — | — |
| `phoneNavStyleLabel` | — | — | — | — |
| `desktopSidebarStyleLabel` | — | — | — | — |
| `onOpenDesktopSidebarStyle` | — | — | — | — |
| `profileAppearanceLabel` | — | — | — | — |
| `onOpenProfileAppearance` | — | — | — | — |
| `_SettingsLayout` | — | — | — | — |
| `_providerConnections` | `connections` | — | — | — |
| `_trackerServices` | `connections` | — | — | — |
| `_showsLargeCollectionStyles` | — | — | — | — |
| `_buildSpotlight` | `onOpenSearch` | — | — | `_buildSpotlightCategory` → 1/settings_spotlight_category, `_providerConnections` → 1/settings_layout |
| `_buildConnectionGrid` | — | — | — | — |
| `_buildSpotlightCategory` | `appVersion`, `autoUpdateChecksEnabled`, `checkingUpdates`, `connections`, `debrifyTvStyleLabel`, `desktopSidebarStyleLabel`, `detailPageStyleLabel`, `downloadLocationSubtitle`, `includeAlphaUpdates`, `iptvStyleLabel`, `launchAnimationLabel`, `onAddProfile`, `onCheckForUpdates`, `onClearDownloads`, `onClearPlayback`, `onCreateBackup`, `onDangerAction`, `onEditProfile`, `onExportDiagnosticLogs`, `onOpenBadgesSettings`, `onOpenCollectionListStyle`, `onOpenCollectionsSettings`, `onOpenDebrifyTvSettings`, `onOpenDebrifyTvStyle`, `onOpenDesktopSidebarStyle`, `onOpenDetailPageStyle`, `onOpenDiscoverSettings`, `onOpenDownloadLocation`, `onOpenFilterSettings`, `onOpenHomePageSettings`, `onOpenIptvSettings`, `onOpenIptvStyle`, `onOpenLaunchAnimation`, `onOpenLooks`, `onOpenMetadataSettings`, `onOpenNavigationSettings`, `onOpenParentsGuideStyle`, `onOpenPlayLoaderStyle`, `onOpenPlayerDock`, `onOpenPlayerGuideStyle`, `onOpenProfileAppearance`, `onOpenProviderSettings`, `onOpenQuickPlaySettings`, `onOpenRecordings`, `onOpenSupportDonation`, `onOpenSyncAndMigrate`, `onOpenTextBrightness`, `onOpenThemeTokens`, `onOpenTorrentSettings`, `onRestoreBackup`, `onSwitchProfile`, `onToggleAutoUpdateChecks`, `onToggleIncludeAlphaUpdates`, `parentsGuideStyleLabel`, `phoneNavStyleLabel`, `playLoaderStyleLabel`, `playerDockLabel`, `playerGuideStyleLabel`, `profileAppearanceLabel`, `showIptvAppearance`, `showSupportDonation`, `showSwitchProfile`, `supportDonationLabel`, `supportDonationSubtitle`, `textBrightnessLabel`, `themeTokensLabel`, `updateSubtitle` | `onExportDiagnosticLogs`, `onOpenDownloadLocation` | `_buildConnectionGrid` → 1/settings_connection_grid, `_showsLargeCollectionStyles` → 1/settings_layout | `_providerConnections` → 1/settings_layout, `_trackerServices` → 1/settings_layout |
| `build` | `appVersion`, `autoUpdateChecksEnabled`, `checkingUpdates`, `connections`, `debrifyTvStyleLabel`, `desktopSidebarStyleLabel`, `detailPageStyleLabel`, `downloadLocationSubtitle`, `includeAlphaUpdates`, `iptvStyleLabel`, `isAndroidTv`, `launchAnimationLabel`, `onAddProfile`, `onCheckForUpdates`, `onClearDownloads`, `onClearPlayback`, `onCreateBackup`, `onDangerAction`, `onEditProfile`, `onExportDiagnosticLogs`, `onOpenBadgesSettings`, `onOpenCollectionListStyle`, `onOpenCollectionsSettings`, `onOpenDebrifyTvSettings`, `onOpenDebrifyTvStyle`, `onOpenDesktopSidebarStyle`, `onOpenDetailPageStyle`, `onOpenDiscoverSettings`, `onOpenDownloadLocation`, `onOpenFilterSettings`, `onOpenHomePageSettings`, `onOpenIptvSettings`, `onOpenIptvStyle`, `onOpenLaunchAnimation`, `onOpenLooks`, `onOpenMetadataSettings`, `onOpenNavigationSettings`, `onOpenParentsGuideStyle`, `onOpenPlayLoaderStyle`, `onOpenPlayerDock`, `onOpenPlayerGuideStyle`, `onOpenProfileAppearance`, `onOpenProviderSettings`, `onOpenQuickPlaySettings`, `onOpenRecordings`, `onOpenSearch`, `onOpenSupportDonation`, `onOpenSyncAndMigrate`, `onOpenTextBrightness`, `onOpenThemeTokens`, `onOpenTorrentSettings`, `onRestoreBackup`, `onSwitchProfile`, `onToggleAutoUpdateChecks`, `onToggleIncludeAlphaUpdates`, `onToggleTvKeyboard`, `parentsGuideStyleLabel`, `phoneNavStyleLabel`, `playLoaderStyleLabel`, `playerDockLabel`, `playerGuideStyleLabel`, `profileAppearanceLabel`, `showIptvAppearance`, `showSupportDonation`, `showSwitchProfile`, `supportDonationLabel`, `supportDonationSubtitle`, `textBrightnessLabel`, `themeTokensLabel`, `tvKeyboardEnabled`, `updateSubtitle` | `onExportDiagnosticLogs`, `onOpenDownloadLocation` | `_buildSpotlight` → 1/settings_spotlight_layout, `_showsLargeCollectionStyles` → 1/settings_layout | — |
### `_SettingsSearchBar`

| Member | Reads | Writes | Calls (→ step/destination) | Tear-offs (→ step/destination) |
| --- | --- | --- | --- | --- |
| `onTap` | — | — | — | — |
| `_SettingsSearchBar` | — | — | — | — |
| `createState` | — | — | — | — |
### `_SettingsSearchBarState`

| Member | Reads | Writes | Calls (→ step/destination) | Tear-offs (→ step/destination) |
| --- | --- | --- | --- | --- |
| `_node` | — | — | — | — |
| `_hovered` | — | — | — | — |
| `_focused` | `_node` | — | — | — |
| `dispose` | `_node` | — | `dispose` → 1/settings_search_bar | — |
| `build` | `_hovered`, `_node` | `_hovered` | — | `_focused` → 1/settings_search_bar |

## Every callback / local function

This includes builder closures and immediate mapping closures so deferred entries
cannot be missed. The syntax parent and body line range identify the exact closure.
Guards are retained in each callback at their original position.

| Owner.member | Callback lines | AST parent | Parameters | Owner references in callback |
| --- | --- | --- | --- | --- |
| `_SettingsScreenState.initState` | 344–348 | `ArgumentListImpl` | `support` | `_recordingSearchable`, `mounted`, `setState` |
| `_SettingsScreenState.initState` | 346–346 | `ArgumentListImpl` | `` | `_recordingSearchable` |
| `_SettingsScreenState.initState` | 352–354 | `AssignmentExpressionImpl` | `` | `_firstCardFocusNode` |
| `_SettingsScreenState._loadSummaries` | 397–397 | `ArgumentListImpl` | `` | `_loading` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 427–459 | `NamedArgumentImpl` | `label, error` | `_summaryFailures`, `_summaryUnavailable`, `mounted` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 464–464 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 469–469 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 474–474 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 477–477 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 480–480 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 483–483 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 484–484 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 485–485 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 488–488 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 498–498 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 503–503 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 508–508 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 513–513 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 518–518 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 521–521 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 522–522 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 525–525 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 530–530 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 535–535 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 540–540 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 545–545 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 550–550 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 555–555 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 560–560 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 565–565 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 570–570 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 575–575 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 580–580 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 585–585 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 590–590 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 595–595 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 600–600 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 605–605 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 610–610 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 615–615 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 620–620 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 625–625 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 630–630 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 635–635 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 640–640 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 645–645 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 650–650 | `ArgumentListImpl` | `` | `_activeProfileMayExportDiagnostics` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 655–655 | `ArgumentListImpl` | `` | `_pendingCredentialTypes` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 660–660 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 665–665 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 668–668 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 843–855 | `FunctionDeclarationImpl` | `types, ownCredentialPresent, apply` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 867–871 | `ArgumentListImpl` | `` | `_realDebridCaption`, `_realDebridConnected`, `_realDebridStatus` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 872–876 | `ArgumentListImpl` | `` | `_torboxCaption`, `_torboxConnected`, `_torboxStatus` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 877–881 | `ArgumentListImpl` | `` | `_premiumizeCaption`, `_premiumizeConnected`, `_premiumizeStatus` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 882–886 | `ArgumentListImpl` | `` | `_allDebridCaption`, `_allDebridConnected`, `_allDebridStatus` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 887–891 | `ArgumentListImpl` | `` | `_pikpakCaption`, `_pikpakConnected`, `_pikpakStatus` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 895–899 | `ArgumentListImpl` | `` | `_webDavCaption`, `_webDavConnected`, `_webDavStatus` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 901–905 | `ArgumentListImpl` | `` | `_traktCaption`, `_traktConnected`, `_traktStatus` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 906–910 | `ArgumentListImpl` | `` | `_simklCaption`, `_simklConnected`, `_simklStatus` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 911–915 | `ArgumentListImpl` | `` | `_mdblistCaption`, `_mdblistConnected`, `_mdblistStatus` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 919–923 | `ArgumentListImpl` | `` | `_indexerManagersCaption`, `_indexerManagersConfigured`, `_indexerManagersStatus` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 966–966 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 970–976 | `ArgumentListImpl` | `_` | `_applyRdUserInfo`, `mounted`, `setState` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 974–974 | `ArgumentListImpl` | `` | `_applyRdUserInfo` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 980–986 | `ArgumentListImpl` | `_` | `_applyTorboxUserInfo`, `mounted`, `setState` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 984–984 | `ArgumentListImpl` | `` | `_applyTorboxUserInfo` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 990–996 | `ArgumentListImpl` | `_` | `_applyPremiumizeUserInfo`, `mounted`, `setState` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 994–994 | `ArgumentListImpl` | `` | `_applyPremiumizeUserInfo` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 1000–1006 | `ArgumentListImpl` | `_` | `_applyAllDebridUserInfo`, `mounted`, `setState` |
| `_SettingsScreenState._loadSummariesForCurrentProfile` | 1004–1004 | `ArgumentListImpl` | `` | `_applyAllDebridUserInfo` |
| `_SettingsScreenState._pendingCredentialTypes` | 1022–1022 | `ArgumentListImpl` | `resource` | — |
| `_SettingsScreenState._pendingCredentialTypes` | 1023–1023 | `ArgumentListImpl` | `resource` | — |
| `_SettingsScreenState._loadSupportConfig` | 1031–1033 | `ArgumentListImpl` | `` | `_applySupportConfig` |
| `_SettingsScreenState._loadSupportConfig` | 1038–1040 | `ArgumentListImpl` | `` | `_applySupportConfig` |
| `_SettingsScreenState._openSettingsSearch` | 1558–1558 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._buildSearchIndex` | 1575–1588 | `FunctionDeclarationImpl` | `info, keywords, category` | — |
| `_SettingsScreenState._buildSearchIndex` | 1590–1605 | `FunctionDeclarationImpl` | `c, category, onTap, keywords, subtitle, destructive` | — |
| `_SettingsScreenState._buildSearchIndex` | 1607–1609 | `FunctionDeclarationImpl` | `values` | — |
| `_SettingsScreenState._buildSearchIndex` | 1953–1953 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 1981–1981 | `ArgumentListImpl` | `ident` | — |
| `_SettingsScreenState._buildSearchIndex` | 2008–2008 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2050–2050 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2078–2078 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2106–2106 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2127–2127 | `ArgumentListImpl` | `option` | — |
| `_SettingsScreenState._buildSearchIndex` | 2160–2160 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2185–2185 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2210–2210 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2240–2240 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2261–2261 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2290–2290 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2315–2315 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2344–2344 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2372–2372 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2403–2403 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2404–2404 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2405–2405 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2451–2451 | `ArgumentListImpl` | `look` | — |
| `_SettingsScreenState._buildSearchIndex` | 2476–2476 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2514–2514 | `ArgumentListImpl` | `choice` | — |
| `_SettingsScreenState._buildSearchIndex` | 2676–2676 | `NamedArgumentImpl` | `` | — |
| `_SettingsScreenState._buildSearchIndex` | 2758–2758 | `NamedArgumentImpl` | `` | `_tvKeyboardEnabled` |
| `_SettingsScreenState._buildSearchIndex` | 2876–2876 | `NamedArgumentImpl` | `` | `_autoUpdateChecksEnabled` |
| `_SettingsScreenState._buildSearchIndex` | 2885–2885 | `NamedArgumentImpl` | `` | `_includeAlphaUpdates` |
| `_SettingsScreenState._buildSearchIndex` | 2909–2909 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._buildSearchIndex` | 2915–2915 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._buildSearchIndex` | 2921–2921 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._leafSearchEntries` | 3005–3020 | `FunctionDeclarationImpl` | `page, title, subtitle, keywords, onTap` | — |
| `_SettingsScreenState._leafSearchEntries` | 3022–3024 | `FunctionDeclarationImpl` | `values` | — |
| `_SettingsScreenState._leafSearchEntries` | 3026–3051 | `FunctionDeclarationImpl` | `` | — |
| `_SettingsScreenState._leafSearchEntries` | 3030–3030 | `ArgumentListImpl` | `player` | — |
| `_SettingsScreenState._leafSearchEntries` | 3035–3035 | `ArgumentListImpl` | `player` | — |
| `_SettingsScreenState._leafSearchEntries` | 3040–3040 | `ArgumentListImpl` | `player` | — |
| `_SettingsScreenState._leafSearchEntries` | 3046–3046 | `ArgumentListImpl` | `player` | — |
| `_SettingsScreenState._leafSearchEntries` | 3047–3047 | `ArgumentListImpl` | `player` | — |
| `_SettingsScreenState._leafSearchEntries` | 3990–3990 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4004–4010 | `NamedArgumentImpl` | `` | `_ensureProfileFeature`, `context`, `mounted` |
| `_SettingsScreenState._leafSearchEntries` | 4026–4026 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4039–4039 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4046–4046 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4062–4062 | `ArgumentListImpl` | `option` | — |
| `_SettingsScreenState._leafSearchEntries` | 4063–4063 | `ArgumentListImpl` | `option` | — |
| `_SettingsScreenState._leafSearchEntries` | 4064–4064 | `ArgumentListImpl` | `option` | — |
| `_SettingsScreenState._leafSearchEntries` | 4066–4066 | `ArgumentListImpl` | `option` | — |
| `_SettingsScreenState._leafSearchEntries` | 4069–4069 | `ArgumentListImpl` | `option` | — |
| `_SettingsScreenState._leafSearchEntries` | 4072–4072 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4096–4096 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4114–4114 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4128–4128 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4143–4143 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4164–4164 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4172–4172 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4188–4188 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4203–4203 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4218–4218 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4235–4235 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4251–4251 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4268–4268 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4283–4283 | `ArgumentListImpl` | `mode` | — |
| `_SettingsScreenState._leafSearchEntries` | 4286–4286 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4307–4307 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4323–4323 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4339–4339 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4354–4354 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4370–4370 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4386–4386 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._leafSearchEntries` | 4411–4411 | `NamedArgumentImpl` | `` | `_openPlaybackSection` |
| `_SettingsScreenState._openTorrentSettings` | 4975–4975 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openIndexerManagersSettings` | 4988–4994 | `ArgumentListImpl` | `` | `_indexerManagersCaption`, `_indexerManagersConfigured`, `_indexerManagersStatus` |
| `_SettingsScreenState._openDebrifyTvSettings` | 5000–5000 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openStremioTvSettings` | 5009–5009 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openTrackingSettings` | 5058–5058 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openNavigationSettings` | 5092–5142 | `NamedArgumentImpl` | `dialogContext` | — |
| `_SettingsScreenState._openNavigationSettings` | 5093–5117 | `FunctionDeclarationImpl` | `icon, title, subtitle, value` | — |
| `_SettingsScreenState._openNavigationSettings` | 5115–5115 | `NamedArgumentImpl` | `` | — |
| `_SettingsScreenState._openNavigationSettings` | 5147–5147 | `ArgumentListImpl` | `` | `_phoneNavStyle` |
| `_SettingsScreenState._openRemoteControl` | 5235–5235 | `NamedArgumentImpl` | `_` | — |
| `_SettingsScreenState._openRemoteControl` | 5237–5237 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._switchProfile` | 5247–5247 | `ArgumentListImpl` | `` | `_diagnosticExportVisible` |
| `_SettingsScreenState._addProfile` | 5285–5285 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._editActiveProfile` | 5309–5309 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openFilterSettings` | 5315–5315 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openProviderSettings` | 5323–5323 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openQuickPlaySettings` | 5329–5329 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._focusFirstCard` | 5393–5397 | `ArgumentListImpl` | `_` | `_firstCardFocusNode`, `mounted` |
| `_SettingsScreenState._restoreProfileBackup` | 5432–5435 | `NamedArgumentImpl` | `` | `_loadSummaries` |
| `_SettingsScreenState._createBackup` | 5499–5617 | `NamedArgumentImpl` | `context` | `_backupSummaryLines`, `context` |
| `_SettingsScreenState._createBackup` | 5500–5616 | `NamedArgumentImpl` | `context, setDialogState` | `_backupSummaryLines`, `context` |
| `_SettingsScreenState._createBackup` | 5516–5516 | `ArgumentListImpl` | `line` | — |
| `_SettingsScreenState._createBackup` | 5544–5545 | `NamedArgumentImpl` | `v` | — |
| `_SettingsScreenState._createBackup` | 5545–5545 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._createBackup` | 5552–5552 | `NamedArgumentImpl` | `v` | — |
| `_SettingsScreenState._createBackup` | 5552–5552 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._createBackup` | 5565–5565 | `NamedArgumentImpl` | `_` | — |
| `_SettingsScreenState._createBackup` | 5565–5565 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._createBackup` | 5566–5566 | `NamedArgumentImpl` | `_` | — |
| `_SettingsScreenState._createBackup` | 5578–5578 | `NamedArgumentImpl` | `_` | — |
| `_SettingsScreenState._createBackup` | 5578–5578 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._createBackup` | 5579–5581 | `NamedArgumentImpl` | `_` | `context` |
| `_SettingsScreenState._createBackup` | 5605–5605 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._createBackup` | 5610–5610 | `ConditionalExpressionImpl` | `` | `context` |
| `_SettingsScreenState._createBackup` | 5661–5676 | `NamedArgumentImpl` | `_` | — |
| `_SettingsScreenState._exportDiagnosticLogs` | 5727–5727 | `ArgumentListImpl` | `` | `_diagnosticExportVisible` |
| `_SettingsScreenState._exportDiagnosticLogs` | 5736–5736 | `ArgumentListImpl` | `` | `_exportingDiagnostics` |
| `_SettingsScreenState._exportDiagnosticLogs` | 5787–5787 | `ArgumentListImpl` | `` | `_exportingDiagnostics` |
| `_SettingsScreenState._promptAndDecryptBackup` | 5803–5843 | `NamedArgumentImpl` | `context` | `context` |
| `_SettingsScreenState._promptAndDecryptBackup` | 5804–5842 | `NamedArgumentImpl` | `context, setDialogState` | `context` |
| `_SettingsScreenState._promptAndDecryptBackup` | 5828–5828 | `NamedArgumentImpl` | `value` | `context` |
| `_SettingsScreenState._promptAndDecryptBackup` | 5834–5834 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._promptAndDecryptBackup` | 5838–5838 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._promptAndDecryptBackup` | 5855–5870 | `NamedArgumentImpl` | `_` | — |
| `_SettingsScreenState._restoreBackup` | 5995–6061 | `NamedArgumentImpl` | `context` | `_backupSummaryLines`, `context` |
| `_SettingsScreenState._restoreBackup` | 6014–6014 | `ArgumentListImpl` | `line` | — |
| `_SettingsScreenState._restoreBackup` | 6053–6053 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._restoreBackup` | 6057–6057 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._restoreBackup` | 6072–6087 | `NamedArgumentImpl` | `_` | — |
| `_SettingsScreenState._loadDownloadLocation` | 6303–6307 | `ArgumentListImpl` | `` | `_defaultDownloadLocationLabel`, `_downloadLocationSubtitle` |
| `_SettingsScreenState._openDownloadLocationSettings` | 6321–6373 | `NamedArgumentImpl` | `ctx` | `_chooseDownloadFolder`, `_defaultDownloadLocationLabel`, `_downloadLocationSubtitle`, `_downloadLocationUsesSaf`, `_resetDownloadFolder` |
| `_SettingsScreenState._openDownloadLocationSettings` | 6352–6355 | `NamedArgumentImpl` | `` | `_chooseDownloadFolder` |
| `_SettingsScreenState._openDownloadLocationSettings` | 6364–6367 | `NamedArgumentImpl` | `` | `_resetDownloadFolder` |
| `_SettingsScreenState._clearDownloadData` | 6497–6512 | `NamedArgumentImpl` | `context` | `context` |
| `_SettingsScreenState._clearDownloadData` | 6504–6504 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._clearDownloadData` | 6508–6508 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._clearPlaybackData` | 6527–6542 | `NamedArgumentImpl` | `context` | `context` |
| `_SettingsScreenState._clearPlaybackData` | 6534–6534 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._clearPlaybackData` | 6538–6538 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._resetAppData` | 6571–6593 | `NamedArgumentImpl` | `context` | `context` |
| `_SettingsScreenState._resetAppData` | 6580–6580 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._resetAppData` | 6585–6585 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._resetAppData` | 6589–6589 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsScreenState._resetAppData` | 6607–6648 | `NamedArgumentImpl` | `dialogContext` | — |
| `_SettingsScreenState._resetAppData` | 6608–6647 | `NamedArgumentImpl` | `context, setDialogState` | — |
| `_SettingsScreenState._resetAppData` | 6626–6626 | `NamedArgumentImpl` | `_` | — |
| `_SettingsScreenState._resetAppData` | 6626–6626 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._resetAppData` | 6627–6631 | `NamedArgumentImpl` | `_` | — |
| `_SettingsScreenState._resetAppData` | 6637–6637 | `NamedArgumentImpl` | `` | — |
| `_SettingsScreenState._resetAppData` | 6642–6642 | `ConditionalExpressionImpl` | `` | — |
| `_SettingsScreenState._checkForAppUpdates` | 6738–6741 | `ArgumentListImpl` | `` | `_checkingUpdates`, `_updateSubtitle` |
| `_SettingsScreenState._checkForAppUpdates` | 6749–6754 | `ArgumentListImpl` | `` | `_checkingUpdates`, `_updateSubtitle` |
| `_SettingsScreenState._checkForAppUpdates` | 6759–6762 | `ArgumentListImpl` | `` | `_checkingUpdates`, `_updateSubtitle` |
| `_SettingsScreenState._checkForAppUpdates` | 6767–6770 | `ArgumentListImpl` | `` | `_checkingUpdates`, `_updateSubtitle` |
| `_SettingsScreenState._showReleaseDetails` | 6802–6932 | `NamedArgumentImpl` | `sheetContext` | `_appVersion`, `_openReleasesPage`, `_startAndroidUpdateDownload` |
| `_SettingsScreenState._showReleaseDetails` | 6889–6898 | `NamedArgumentImpl` | `text, href, title` | — |
| `_SettingsScreenState._showReleaseDetails` | 6910–6913 | `NamedArgumentImpl` | `` | `_startAndroidUpdateDownload` |
| `_SettingsScreenState._showReleaseDetails` | 6918–6921 | `NamedArgumentImpl` | `` | `_openReleasesPage` |
| `_SettingsScreenState._toggleAutoUpdateChecks` | 6939–6941 | `ArgumentListImpl` | `` | `_autoUpdateChecksEnabled` |
| `_SettingsScreenState._toggleIncludeAlphaUpdates` | 6948–6953 | `ArgumentListImpl` | `` | `_includeAlphaUpdates`, `_updateSubtitle` |
| `_SettingsScreenState._toggleTvKeyboard` | 6958–6960 | `ArgumentListImpl` | `` | `_tvKeyboardEnabled` |
| `_SettingsScreenState._openTvScreenSize` | 6972–6974 | `ArgumentListImpl` | `` | `_tvUiScalePercent` |
| `_SettingsScreenState._openTvRenderQuality` | 6985–6987 | `ArgumentListImpl` | `` | `_tvRenderQuality` |
| `_SettingsScreenState._openTvHeroArtworkQuality` | 6995–6997 | `ArgumentListImpl` | `` | `_tvHeroArtworkQuality` |
| `_SettingsScreenState._openTvHomeStyle` | 7007–7009 | `ArgumentListImpl` | `` | `_tvHomeStyle` |
| `_SettingsScreenState._openDiscoverLayout` | 7022–7024 | `ArgumentListImpl` | `` | `_discoverLayout` |
| `_SettingsScreenState._openTvSidebarStyle` | 7033–7035 | `ArgumentListImpl` | `` | `_tvSidebarStyle` |
| `_SettingsScreenState._openDesktopSidebarStyle` | 7044–7046 | `ArgumentListImpl` | `` | `_desktopSidebarStyle` |
| `_SettingsScreenState._openSidebarCustomization` | 7052–7052 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openProfileAppearance` | 7059–7059 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openIptvStylePage` | 7068–7070 | `ArgumentListImpl` | `` | `_iptvStyle` |
| `_SettingsScreenState._openDebrifyTvStylePage` | 7078–7080 | `ArgumentListImpl` | `` | `_debrifyTvStyle` |
| `_SettingsScreenState._openPlayerGuideStylePage` | 7089–7091 | `ArgumentListImpl` | `` | `_playerGuideStyle` |
| `_SettingsScreenState._openPlayLoaderStylePage` | 7102–7104 | `ArgumentListImpl` | `` | `_playLoaderStyle` |
| `_SettingsScreenState._openTvPlayerControlsStylePage` | 7113–7115 | `ArgumentListImpl` | `` | `_tvPlayerControlsStyle` |
| `_SettingsScreenState._openDebrifyTvPlayerStylePage` | 7124–7126 | `ArgumentListImpl` | `` | `_debrifyTvPlayerStyle` |
| `_SettingsScreenState._openPlayerDockPage` | 7137–7141 | `ArgumentListImpl` | `` | `_playerDockPalette`, `_playerDockSize`, `_playerDockStyle` |
| `_SettingsScreenState._openDetailPageStylePage` | 7150–7152 | `ArgumentListImpl` | `` | `_detailPageStyle` |
| `_SettingsScreenState._openDetailThemePage` | 7161–7163 | `ArgumentListImpl` | `` | `_detailTheme` |
| `_SettingsScreenState._openThemeLab` | 7172–7172 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openLooksPage` | 7181–7181 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openThemeTokensPage` | 7187–7187 | `ArgumentListImpl` | `` | — |
| `_SettingsScreenState._openAppThemePage` | 7206–7208 | `ArgumentListImpl` | `` | `_detailTheme` |
| `_SettingsScreenState._openParentsGuideStylePage` | 7216–7218 | `ArgumentListImpl` | `` | `_parentsGuideStyle` |
| `_SettingsScreenState._openTextBrightnessPage` | 7227–7229 | `ArgumentListImpl` | `` | `_textBrightness` |
| `_SettingsScreenState._openLaunchAnimationPage` | 7238–7240 | `ArgumentListImpl` | `` | `_launchAnimation` |
| `_SettingsScreenState._reloadAppearanceSummaries` | 7261–7272 | `ArgumentListImpl` | `` | `_debrifyTvPlayerStyle`, `_debrifyTvStyle`, `_iptvStyle`, `_playLoaderStyle`, `_playerDockPalette`, `_playerDockSize`, `_playerDockStyle`, `_playerGuideStyle`, `_tvHomeStyle`, `_tvPlayerControlsStyle` |
| `_SettingsScreenState._startAndroidUpdateDownload` | 7298–7300 | `ArgumentListImpl` | `` | `_updateSubtitle` |
| `_SettingsScreenState._startAndroidUpdateDownload` | 7323–7325 | `ArgumentListImpl` | `` | `_updateSubtitle` |
| `_SettingsScreenState._startAndroidUpdateDownload` | 7332–7373 | `ArgumentListImpl` | `event` | `_clearUpdateDownloadListener`, `_showSnack`, `_updateDownloadTaskId`, `_updateSubtitle`, `mounted`, `setState` |
| `_SettingsScreenState._startAndroidUpdateDownload` | 7359–7361 | `ArgumentListImpl` | `` | `_updateSubtitle` |
| `_SettingsScreenState._startAndroidUpdateDownload` | 7368–7370 | `ArgumentListImpl` | `` | `_updateSubtitle` |
| `_SettingsLayout._buildSpotlight` | 7835–7835 | `NamedArgumentImpl` | `` | — |
| `_SettingsLayout._buildConnectionGrid` | 7847–7865 | `NamedArgumentImpl` | `context, constraints` | — |
| `_SettingsLayout._buildSpotlightCategory` | 8041–8041 | `NamedArgumentImpl` | `` | `onOpenPlaybackSection` |
| `_SettingsLayout._buildSpotlightCategory` | 8098–8098 | `NamedArgumentImpl` | `` | `onOpenRemoteControl` |
| `_SettingsLayout._buildSpotlightCategory` | 8127–8127 | `NamedArgumentImpl` | `` | `context` |
| `_SettingsLayout._buildSpotlightCategory` | 8246–8246 | `NamedArgumentImpl` | `` | — |
| `_SettingsLayout._buildSpotlightCategory` | 8250–8250 | `NamedArgumentImpl` | `` | — |
| `_SettingsLayout._buildSpotlightCategory` | 8254–8254 | `NamedArgumentImpl` | `` | — |
| `_SettingsLayout.build` | 8474–8474 | `NamedArgumentImpl` | `` | `onOpenPlaybackSection` |
| `_SettingsLayout.build` | 8540–8540 | `NamedArgumentImpl` | `` | `onOpenRemoteControl` |
| `_SettingsLayout.build` | 8651–8651 | `NamedArgumentImpl` | `` | — |
| `_SettingsLayout.build` | 8655–8655 | `NamedArgumentImpl` | `` | — |
| `_SettingsLayout.build` | 8659–8659 | `NamedArgumentImpl` | `` | — |
| `_SettingsSearchBarState.build` | 8727–8727 | `NamedArgumentImpl` | `_` | `setState` |
| `_SettingsSearchBarState.build` | 8727–8727 | `ArgumentListImpl` | `` | — |
| `_SettingsSearchBarState.build` | 8728–8728 | `NamedArgumentImpl` | `h` | `_hovered`, `setState` |
| `_SettingsSearchBarState.build` | 8728–8728 | `ArgumentListImpl` | `` | `_hovered` |

## Size decisions

Destinations use 500 lines by default. Summary loader has the named ≤800 cap
(588-line original method). Classic layout has the named ≤800 cap (412-line
original body). Spotlight category is 407 lines before imports and qualifiers,
so its 500-line cap is expected to fit. Layout class is 279 lines after removing
the two large bodies, before moving the grid and spotlight helpers.
Backup (265), restore/decryption (340), diagnostics (86), maintenance (234),
download location (~200), update actions (~296 without release details), and
release details (160) have distinct files to keep their responsibilities and caps.
Search preamble has its own fresh builder; slices are specified separately in
`dev/tool/settings_partitions.json`, including the approved cut at line 4166.

## Host order evidence

The macOS fixture is recorded from the real builders using the test accessor.
Linux differs in `(Data & Backup, Download Location)`; both are desktop hosts.
Other host checks affect keyword labels, not `(category, title)` pairs.
The Linux expected list includes that whole entry at the baseline position;
Ubuntu CI must execute it before the gate is considered passed.

## Additional test-only declaration

`settingsScreenTestAccess` is the single visibleForTesting accessor added in step 0.
It returns production index and leaf builder tear-offs and the real snack helper.
It neither changes initialization nor injects alternate settings implementations.
Its exact syntax is registered by the settings move check. No production code calls it.

## External tear-offs retained at their existing owners

| Member | Tear-off | Existing dependency |
| --- | --- | --- |
| `shouldApplyPendingCredentialOverride` | `providerTypes.contains` | `Set<ConnectionResourceType>` predicate |
| `_SettingsLayout._buildSpotlight` | `settingsConnectionNeedsAttention` | `screens/settings/settings_spotlight_shell.dart` |
| `_SettingsLayout._buildSpotlight` | `settingsConnectionIsReady` | `screens/settings/settings_spotlight_shell.dart` |

The complete member table above includes every owner-local method tear-off.
Callback-valued layout fields retain their declared types and are passed through
unchanged; their reads are in that same table. No external callable is moved.
