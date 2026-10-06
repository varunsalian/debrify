# Recordings dependency and contract inventory

Verified against `49c53e2e` using the pinned analyzer AST and the provided facts file. Nothing moves at Step 0. Destinations below are registrations for later steps.

The facts file is `/private/tmp/claude-501/-Users-varunbsalian-Documents-Projects-debrify/6bba10c1-952f-461d-8d19-fbfb81b20e57/scratchpad/rec/facts.md`. Its responsibility inventory agrees with the source. Two descriptive counts need correction: the file has **16 imports**, and the main State has **30 method declarations (5 getters and 25 non-getter methods)** plus 14 fields (12 instance, 2 static). It is 2,129 physical lines, with 14 private widgets and seven widget States. The original file is formatter-clean.

The manifest has 72 declaration leaves. Attached documentation travels with its declaration; the header comment stays in the facade. Ten free-standing banners are pinned separately by offsets and anchors in the config. The public widget stays byte-identical. Original source, raw hash, callback tokens and composition tokens are frozen in the feature sidecars.

## Declarations, attached docs and destinations

| Original leaf | Original lines | Step | Destination | Attached docs |
| --- | --- | --- | --- | --- |
| `_kBg` | 30–30 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_layout.dart::_kBg` | none |
| `_kCard` | 31–31 | 1 | `lib/features/recordings/presentation/recordings_hub_live_card.dart::_kCard` | none |
| `_kRec` | 32–32 | 1 | `lib/features/recordings/presentation/recordings_hub_tokens.dart::kRecordingsHubRec` | none |
| `_kGold` | 33–33 | 1 | `lib/features/recordings/presentation/recordings_hub_tokens.dart::kRecordingsHubGold` | none |
| `_kAccent` | 34–34 | 1 | `lib/features/recordings/presentation/recordings_hub_tokens.dart::kRecordingsHubAccent` | none |
| `_kDialogRowPadding` | 36–37 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_scheduling.dart::_kDialogRowPadding` | travels verbatim (1 doc tokens) |
| `RecordingsPage` | 39–44 | 0 | `lib/screens/settings/recordings_page.dart::RecordingsPage` | none |
| `_RecordingsPageState._live` | 48–48 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::live` | none |
| `_RecordingsPageState._schedules` | 49–49 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::schedules` | none |
| `_RecordingsPageState._library` | 50–50 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::library` | none |
| `_RecordingsPageState._loading` | 51–51 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::loading` | none |
| `_RecordingsPageState._exactAlarms` | 52–52 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::exactAlarms` | none |
| `_RecordingsPageState._now` | 54–56 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::now` | travels verbatim (2 doc tokens) |
| `_RecordingsPageState._ticker` | 57–57 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::ticker` | none |
| `_RecordingsPageState._poll` | 59–62 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::poll` | travels verbatim (3 doc tokens) |
| `_RecordingsPageState._appVisible` | 64–68 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::appVisible` | travels verbatim (4 doc tokens) |
| `_RecordingsPageState._batteryExempt` | 70–74 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::batteryExempt` | travels verbatim (4 doc tokens) |
| `_RecordingsPageState._batteryNudgeDismissedAtMs` | 75–75 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::batteryNudgeDismissedAtMs` | none |
| `_RecordingsPageState._batteryNudgeDismissedPref` | 76–77 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart::RecordingsHubData::batteryNudgeDismissedPref` | none |
| `_RecordingsPageState._firstLibraryFocus` | 79–85 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart::RecordingsHubOwners::firstLibraryFocus` | travels verbatim (4 doc tokens) |
| `_RecordingsPageState._isAndroid` | 87–87 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart::RecordingsHubData::isAndroid` | none |
| `_RecordingsPageState._desktop` | 88–88 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart::RecordingsHubData::desktop` | none |
| `_RecordingsPageState._desktopCaptures` | 90–91 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart::RecordingsHubData::desktopCaptures` | none |
| `_RecordingsPageState._anythingLive` | 93–93 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart::RecordingsHubData::_anythingLive` | none |
| `_RecordingsPageState.initState` | 95–111 | 0 | `lib/screens/settings/recordings_page.dart::_RecordingsPageState::initState` | none |
| `_RecordingsPageState.dispose` | 113–125 | 0 | `lib/screens/settings/recordings_page.dart::_RecordingsPageState::dispose` | none |
| `_RecordingsPageState.didChangeAppLifecycleState` | 127–144 | 0 | `lib/screens/settings/recordings_page.dart::_RecordingsPageState::didChangeAppLifecycleState` | none |
| `_RecordingsPageState._onRevision` | 146–148 | 0 | `lib/screens/settings/recordings_page.dart::_RecordingsPageState::_onRevision` | none |
| `_RecordingsPageState._showBatteryNudge` | 150–158 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart::RecordingsHubData::showBatteryNudge` | none |
| `_RecordingsPageState._dismissBatteryNudge` | 160–168 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart::RecordingsHubData::dismissBatteryNudge` | none |
| `_RecordingsPageState._loadAll` | 170–214 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart::RecordingsHubData::loadAll` | none |
| `_RecordingsPageState._syncTimers` | 216–240 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart::RecordingsHubData::_syncTimers` | none |
| `_RecordingsPageState._pollLive` | 242–272 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart::RecordingsHubData::_pollLive` | travels verbatim (3 doc tokens) |
| `_RecordingsPageState._stopAndroid` | 276–286 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_actions.dart::RecordingsHubActions::stopAndroid` | none |
| `_RecordingsPageState._stopDesktop` | 288–301 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_actions.dart::RecordingsHubActions::stopDesktop` | none |
| `_RecordingsPageState._cancelSchedule` | 303–333 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_actions.dart::RecordingsHubActions::cancelSchedule` | none |
| `_RecordingsPageState._play` | 335–349 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_actions.dart::RecordingsHubActions::play` | none |
| `_RecordingsPageState._delete` | 351–385 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_actions.dart::RecordingsHubActions::delete` | none |
| `_RecordingsPageState._openFolder` | 387–404 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_actions.dart::RecordingsHubActions::openFolder` | none |
| `_RecordingsPageState._createManualSchedule` | 406–536 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_scheduling.dart::RecordingsHubScheduling::createManualSchedule` | travels verbatim (3 doc tokens) |
| `_RecordingsPageState._pickTime` | 538–557 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_scheduling.dart::RecordingsHubScheduling::_pickTime` | travels verbatim (3 doc tokens) |
| `_RecordingsPageState._askRecordingLength` | 559–664 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_scheduling.dart::RecordingsHubScheduling::_askRecordingLength` | travels verbatim (4 doc tokens) |
| `_RecordingsPageState._fmtBytes` | 668–677 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_format.dart::RecordingsHubFormat::fmtBytes` | none |
| `_RecordingsPageState._fmtElapsed` | 679–684 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_format.dart::RecordingsHubFormat::fmtElapsed` | none |
| `_RecordingsPageState._fmtCountdown` | 686–693 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_format.dart::RecordingsHubFormat::fmtCountdown` | none |
| `_RecordingsPageState._fmtDuration` | 695–701 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_format.dart::RecordingsHubFormat::fmtDuration` | none |
| `_RecordingsPageState._clock` | 703–705 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_format.dart::RecordingsHubFormat::clock` | none |
| `_RecordingsPageState._dayLabel` | 707–716 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_format.dart::RecordingsHubFormat::dayLabel` | none |
| `_RecordingsPageState._stampSuffix` | 718–720 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_format.dart::RecordingsHubFormat::_stampSuffix` | none |
| `_RecordingsPageState._displayFor` | 722–759 | 2 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_format.dart::RecordingsHubFormat::displayFor` | travels verbatim (4 doc tokens) |
| `_RecordingsPageState.build` | 763–972 | 3 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_layout.dart::RecordingsHubLayout::build` | none |
| `_HubBar` | 977–1026 | 1 | `lib/features/recordings/presentation/recordings_hub_chrome.dart::_HubBar` | travels verbatim (2 doc tokens) |
| `_SectionHeader` | 1030–1085 | 1 | `lib/features/recordings/presentation/recordings_hub_chrome.dart::_SectionHeader` | none |
| `_EmptyHint` | 1087–1110 | 1 | `lib/features/recordings/presentation/recordings_hub_chrome.dart::_EmptyHint` | none |
| `_LiveCard` | 1114–1203 | 1 | `lib/features/recordings/presentation/recordings_hub_live_card.dart::_LiveCard` | none |
| `_RecDot` | 1205–1212 | 1 | `lib/features/recordings/presentation/recordings_hub_live_card.dart::_RecDot` | travels verbatim (2 doc tokens) |
| `_RecDotState` | 1214–1253 | 1 | `lib/features/recordings/presentation/recordings_hub_live_card.dart::_RecDotState` | none |
| `_ScheduleRow` | 1257–1276 | 1 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_schedule_row.dart::_ScheduleRow` | none |
| `_ScheduleRowState` | 1278–1419 | 1 | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_schedule_row.dart::_ScheduleRowState` | travels verbatim (6 doc tokens) |
| `_LibraryRow` | 1423–1444 | 1 | `lib/features/recordings/presentation/recordings_hub_library_row.dart::_LibraryRow` | none |
| `_LibraryRowState` | 1446–1552 | 1 | `lib/features/recordings/presentation/recordings_hub_library_row.dart::_LibraryRowState` | travels verbatim (6 doc tokens) |
| `_Thumb` | 1554–1599 | 1 | `lib/features/recordings/presentation/recordings_hub_library_row.dart::_Thumb` | none |
| `_EmptyDvr` | 1603–1684 | 1 | `lib/features/recordings/presentation/recordings_hub_empty_states.dart::_EmptyDvr` | none |
| `_BatteryBanner` | 1686–1755 | 1 | `lib/features/recordings/presentation/recordings_hub_empty_states.dart::_BatteryBanner` | travels verbatim (3 doc tokens) |
| `_AlarmBanner` | 1757–1763 | 1 | `lib/features/recordings/presentation/recordings_hub_empty_states.dart::_AlarmBanner` | none |
| `_AlarmBannerState` | 1765–1847 | 1 | `lib/features/recordings/presentation/recordings_hub_empty_states.dart::_AlarmBannerState` | travels verbatim (6 doc tokens) |
| `_HubButton` | 1851–1877 | 1 | `lib/features/recordings/presentation/recordings_hub_buttons.dart::_HubButton` | travels verbatim (4 doc tokens) |
| `_HubButtonState` | 1879–1964 | 1 | `lib/features/recordings/presentation/recordings_hub_buttons.dart::_HubButtonState` | travels verbatim (6 doc tokens) |
| `_HubIconButton` | 1966–1985 | 1 | `lib/features/recordings/presentation/recordings_hub_buttons.dart::_HubIconButton` | travels verbatim (3 doc tokens) |
| `_HubIconButtonState` | 1987–2054 | 1 | `lib/features/recordings/presentation/recordings_hub_buttons.dart::_HubIconButtonState` | travels verbatim (6 doc tokens) |
| `_RowIconButton` | 2056–2068 | 1 | `lib/features/recordings/presentation/recordings_hub_buttons.dart::_RowIconButton` | none |
| `_RowIconButtonState` | 2070–2129 | 1 | `lib/features/recordings/presentation/recordings_hub_buttons.dart::_RowIconButtonState` | travels verbatim (6 doc tokens) |

## Banner leaves

| Anchor | Destination | Original text |
| --- | --- | --- |
| `_RecordingsPageState._stopAndroid` | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_actions.dart` | `// ── Actions ───────────────────────────────────────────────────────────────` |
| `_RecordingsPageState._fmtBytes` | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_format.dart` | `// ── Formatting ────────────────────────────────────────────────────────────` |
| `_RecordingsPageState.build` | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_layout.dart` | `// ── Build ─────────────────────────────────────────────────────────────────` |
| `_HubBar` | `lib/features/recordings/presentation/recordings_hub_chrome.dart` | `// ── Top bar ─────────────────────────────────────────────────────────────────` |
| `_SectionHeader` | `lib/features/recordings/presentation/recordings_hub_chrome.dart` | `// ── Sections ────────────────────────────────────────────────────────────────` |
| `_LiveCard` | `lib/features/recordings/presentation/recordings_hub_live_card.dart` | `// ── Recording-now card ──────────────────────────────────────────────────────` |
| `_ScheduleRow` | `lib/features/recordings/presentation/legacy_recordings/recordings_hub_schedule_row.dart` | `// ── Scheduled row ───────────────────────────────────────────────────────────` |
| `_LibraryRow` | `lib/features/recordings/presentation/recordings_hub_library_row.dart` | `// ── Library row ─────────────────────────────────────────────────────────────` |
| `_EmptyDvr` | `lib/features/recordings/presentation/recordings_hub_empty_states.dart` | `// ── Empty state ─────────────────────────────────────────────────────────────` |
| `_HubButton` | `lib/features/recordings/presentation/recordings_hub_buttons.dart` | `// ── Buttons ─────────────────────────────────────────────────────────────────` |

## Renames, aliases and receiver qualifications

All 261 changed identifier occurrences are listed by original line and column. This list is derived from the occurrence binder, not a text replacement rule. Local bindings and named labels stay lexical. Twelve typedef aliases immediately follow their private owner class; an owner file keeps private spellings. Three shared colours are manifest renames; the other constants travel whole with their only user.

| Line:column | Leaf | Original | Planned physical spelling | Binding / role |
| --- | --- | --- | --- | --- |
| 32:7 | `_kRec` | `_kRec` | `kRecordingsHubRec` | declaration / name |
| 33:7 | `_kGold` | `_kGold` | `kRecordingsHubGold` | declaration / name |
| 34:7 | `_kAccent` | `_kAccent` | `kRecordingsHubAccent` | declaration / name |
| 48:29 | `_RecordingsPageState._live` | `_live` | `live` | declaration / name |
| 49:28 | `_RecordingsPageState._schedules` | `_schedules` | `schedules` | declaration / name |
| 50:31 | `_RecordingsPageState._library` | `_library` | `library` | declaration / name |
| 51:8 | `_RecordingsPageState._loading` | `_loading` | `loading` | declaration / name |
| 52:8 | `_RecordingsPageState._exactAlarms` | `_exactAlarms` | `exactAlarms` | declaration / name |
| 56:33 | `_RecordingsPageState._now` | `_now` | `now` | declaration / name |
| 57:10 | `_RecordingsPageState._ticker` | `_ticker` | `ticker` | declaration / name |
| 62:10 | `_RecordingsPageState._poll` | `_poll` | `poll` | declaration / name |
| 68:8 | `_RecordingsPageState._appVisible` | `_appVisible` | `appVisible` | declaration / name |
| 74:8 | `_RecordingsPageState._batteryExempt` | `_batteryExempt` | `batteryExempt` | declaration / name |
| 75:7 | `_RecordingsPageState._batteryNudgeDismissedAtMs` | `_batteryNudgeDismissedAtMs` | `batteryNudgeDismissedAtMs` | declaration / name |
| 76:23 | `_RecordingsPageState._batteryNudgeDismissedPref` | `_batteryNudgeDismissedPref` | `batteryNudgeDismissedPref` | declaration / name |
| 83:19 | `_RecordingsPageState._firstLibraryFocus` | `_firstLibraryFocus` | `firstLibraryFocus` | declaration / name |
| 87:12 | `_RecordingsPageState._isAndroid` | `_isAndroid` | `isAndroid` | declaration / name |
| 88:12 | `_RecordingsPageState._desktop` | `_desktop` | `desktop` | declaration / name |
| 90:37 | `_RecordingsPageState._desktopCaptures` | `_desktopCaptures` | `desktopCaptures` | declaration / name |
| 91:7 | `_RecordingsPageState._desktopCaptures` | `_desktop` | `desktop` | unbound / lexical |
| 93:29 | `_RecordingsPageState._anythingLive` | `_live` | `_owners.live` | unbound / lexical |
| 93:49 | `_RecordingsPageState._anythingLive` | `_desktopCaptures` | `desktopCaptures` | unbound / lexical |
| 100:9 | `_RecordingsPageState.initState` | `_desktop` | `_sections.data.desktop` | unbound / lexical |
| 103:15 | `_RecordingsPageState.initState` | `_loadAll` | `_sections.data.loadAll` | unbound / lexical |
| 107:33 | `_RecordingsPageState.initState` | `_batteryNudgeDismissedPref` | `RecordingsHubData.batteryNudgeDismissedPref` | unbound / lexical |
| 108:37 | `_RecordingsPageState.initState` | `_batteryNudgeDismissedAtMs` | `_owners.batteryNudgeDismissedAtMs` | unbound / lexical |
| 117:9 | `_RecordingsPageState.dispose` | `_desktop` | `_sections.data.desktop` | unbound / lexical |
| 120:5 | `_RecordingsPageState.dispose` | `_ticker` | `_owners.ticker` | unbound / lexical |
| 121:5 | `_RecordingsPageState.dispose` | `_poll` | `_owners.poll` | unbound / lexical |
| 122:5 | `_RecordingsPageState.dispose` | `_now` | `_owners.now` | unbound / lexical |
| 123:5 | `_RecordingsPageState.dispose` | `_firstLibraryFocus` | `_owners.firstLibraryFocus` | unbound / lexical |
| 130:7 | `_RecordingsPageState.didChangeAppLifecycleState` | `_appVisible` | `_owners.appVisible` | unbound / lexical |
| 132:17 | `_RecordingsPageState.didChangeAppLifecycleState` | `_loadAll` | `_sections.data.loadAll` | unbound / lexical |
| 138:7 | `_RecordingsPageState.didChangeAppLifecycleState` | `_appVisible` | `_owners.appVisible` | unbound / lexical |
| 139:7 | `_RecordingsPageState.didChangeAppLifecycleState` | `_ticker` | `_owners.ticker` | unbound / lexical |
| 140:7 | `_RecordingsPageState.didChangeAppLifecycleState` | `_ticker` | `_owners.ticker` | unbound / lexical |
| 141:7 | `_RecordingsPageState.didChangeAppLifecycleState` | `_poll` | `_owners.poll` | unbound / lexical |
| 142:7 | `_RecordingsPageState.didChangeAppLifecycleState` | `_poll` | `_owners.poll` | unbound / lexical |
| 147:28 | `_RecordingsPageState._onRevision` | `_loadAll` | `_sections.data.loadAll` | unbound / lexical |
| 150:12 | `_RecordingsPageState._showBatteryNudge` | `_showBatteryNudge` | `showBatteryNudge` | declaration / name |
| 151:7 | `_RecordingsPageState._showBatteryNudge` | `_isAndroid` | `isAndroid` | unbound / lexical |
| 153:8 | `_RecordingsPageState._showBatteryNudge` | `_batteryExempt` | `_owners.batteryExempt` | unbound / lexical |
| 154:7 | `_RecordingsPageState._showBatteryNudge` | `_library` | `_owners.library` | unbound / lexical |
| 157:53 | `_RecordingsPageState._showBatteryNudge` | `_batteryNudgeDismissedAtMs` | `_owners.batteryNudgeDismissedAtMs` | unbound / lexical |
| 160:8 | `_RecordingsPageState._dismissBatteryNudge` | `_dismissBatteryNudge` | `dismissBatteryNudge` | declaration / name |
| 162:5 | `_RecordingsPageState._dismissBatteryNudge` | `setState` | `_deps.setState` | unbound / lexical |
| 162:20 | `_RecordingsPageState._dismissBatteryNudge` | `_batteryNudgeDismissedAtMs` | `_owners.batteryNudgeDismissedAtMs` | unbound / lexical |
| 165:33 | `_RecordingsPageState._dismissBatteryNudge` | `_batteryNudgeDismissedPref` | `batteryNudgeDismissedPref` | unbound / lexical |
| 170:16 | `_RecordingsPageState._loadAll` | `_loadAll` | `loadAll` | declaration / name |
| 172:7 | `_RecordingsPageState._loadAll` | `_isAndroid` | `isAndroid` | unbound / lexical |
| 175:7 | `_RecordingsPageState._loadAll` | `_desktop` | `desktop` | unbound / lexical |
| 181:14 | `_RecordingsPageState._loadAll` | `_isAndroid` | `isAndroid` | unbound / lexical |
| 184:7 | `_RecordingsPageState._loadAll` | `_isAndroid` | `isAndroid` | unbound / lexical |
| 187:7 | `_RecordingsPageState._loadAll` | `_isAndroid` | `isAndroid` | unbound / lexical |
| 190:7 | `_RecordingsPageState._loadAll` | `_isAndroid` | `isAndroid` | unbound / lexical |
| 194:10 | `_RecordingsPageState._loadAll` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 203:13 | `_RecordingsPageState._loadAll` | `_displayFor` | `_sections.format.displayFor` | unbound / lexical |
| 203:49 | `_RecordingsPageState._loadAll` | `_displayFor` | `_sections.format.displayFor` | unbound / lexical |
| 205:5 | `_RecordingsPageState._loadAll` | `setState` | `_deps.setState` | unbound / lexical |
| 206:7 | `_RecordingsPageState._loadAll` | `_live` | `_owners.live` | unbound / lexical |
| 207:7 | `_RecordingsPageState._loadAll` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 208:7 | `_RecordingsPageState._loadAll` | `_library` | `_owners.library` | unbound / lexical |
| 209:7 | `_RecordingsPageState._loadAll` | `_exactAlarms` | `_owners.exactAlarms` | unbound / lexical |
| 210:7 | `_RecordingsPageState._loadAll` | `_batteryExempt` | `_owners.batteryExempt` | unbound / lexical |
| 211:7 | `_RecordingsPageState._loadAll` | `_loading` | `_owners.loading` | unbound / lexical |
| 217:10 | `_RecordingsPageState._syncTimers` | `_appVisible` | `_owners.appVisible` | unbound / lexical |
| 218:39 | `_RecordingsPageState._syncTimers` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 219:21 | `_RecordingsPageState._syncTimers` | `_ticker` | `_owners.ticker` | unbound / lexical |
| 220:7 | `_RecordingsPageState._syncTimers` | `_ticker` | `_owners.ticker` | unbound / lexical |
| 221:9 | `_RecordingsPageState._syncTimers` | `_now` | `_owners.now` | unbound / lexical |
| 223:29 | `_RecordingsPageState._syncTimers` | `_ticker` | `_owners.ticker` | unbound / lexical |
| 224:7 | `_RecordingsPageState._syncTimers` | `_ticker` | `_owners.ticker` | unbound / lexical |
| 225:7 | `_RecordingsPageState._syncTimers` | `_ticker` | `_owners.ticker` | unbound / lexical |
| 232:5 | `_RecordingsPageState._syncTimers` | `_poll` | `_owners.poll` | unbound / lexical |
| 233:5 | `_RecordingsPageState._syncTimers` | `_poll` | `_owners.poll` | unbound / lexical |
| 234:9 | `_RecordingsPageState._syncTimers` | `_isAndroid` | `isAndroid` | unbound / lexical |
| 234:24 | `_RecordingsPageState._syncTimers` | `_live` | `_owners.live` | unbound / lexical |
| 234:44 | `_RecordingsPageState._syncTimers` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 235:7 | `_RecordingsPageState._syncTimers` | `_poll` | `_owners.poll` | unbound / lexical |
| 236:27 | `_RecordingsPageState._syncTimers` | `_live` | `_owners.live` | unbound / lexical |
| 246:10 | `_RecordingsPageState._pollLive` | `_isAndroid` | `isAndroid` | unbound / lexical |
| 251:10 | `_RecordingsPageState._pollLive` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 258:53 | `_RecordingsPageState._pollLive` | `_live` | `_owners.live` | unbound / lexical |
| 259:9 | `_RecordingsPageState._pollLive` | `_live` | `_owners.live` | unbound / lexical |
| 260:29 | `_RecordingsPageState._pollLive` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 261:9 | `_RecordingsPageState._pollLive` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 263:13 | `_RecordingsPageState._pollLive` | `_loadAll` | `loadAll` | unbound / lexical |
| 268:5 | `_RecordingsPageState._pollLive` | `setState` | `_deps.setState` | unbound / lexical |
| 269:7 | `_RecordingsPageState._pollLive` | `_live` | `_owners.live` | unbound / lexical |
| 270:7 | `_RecordingsPageState._pollLive` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 276:16 | `_RecordingsPageState._stopAndroid` | `_stopAndroid` | `stopAndroid` | declaration / name |
| 278:10 | `_RecordingsPageState._stopAndroid` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 279:26 | `_RecordingsPageState._stopAndroid` | `context` | `_deps.context()` | unbound / lexical |
| 285:9 | `_RecordingsPageState._stopAndroid` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 285:24 | `_RecordingsPageState._stopAndroid` | `_loadAll` | `_sections.data.loadAll` | unbound / lexical |
| 288:16 | `_RecordingsPageState._stopDesktop` | `_stopDesktop` | `stopDesktop` | declaration / name |
| 290:10 | `_RecordingsPageState._stopDesktop` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 291:26 | `_RecordingsPageState._stopDesktop` | `context` | `_deps.context()` | unbound / lexical |
| 295:37 | `_RecordingsPageState._stopDesktop` | `_fmtBytes` | `_sections.format.fmtBytes` | unbound / lexical |
| 300:11 | `_RecordingsPageState._stopDesktop` | `_loadAll` | `_sections.data.loadAll` | unbound / lexical |
| 303:16 | `_RecordingsPageState._cancelSchedule` | `_cancelSchedule` | `cancelSchedule` | declaration / name |
| 305:16 | `_RecordingsPageState._cancelSchedule` | `context` | `_deps.context()` | unbound / lexical |
| 326:31 | `_RecordingsPageState._cancelSchedule` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 327:9 | `_RecordingsPageState._cancelSchedule` | `_desktop` | `_sections.data.desktop` | unbound / lexical |
| 335:16 | `_RecordingsPageState._play` | `_play` | `play` | declaration / name |
| 336:21 | `_RecordingsPageState._play` | `_displayFor` | `_sections.format.displayFor` | unbound / lexical |
| 338:7 | `_RecordingsPageState._play` | `context` | `_deps.context()` | unbound / lexical |
| 346:32 | `_RecordingsPageState._play` | `_isAndroid` | `_sections.data.isAndroid` | unbound / lexical |
| 351:16 | `_RecordingsPageState._delete` | `_delete` | `delete` | declaration / name |
| 352:21 | `_RecordingsPageState._delete` | `_displayFor` | `_sections.format.displayFor` | unbound / lexical |
| 354:16 | `_RecordingsPageState._delete` | `context` | `_deps.context()` | unbound / lexical |
| 358:32 | `_RecordingsPageState._delete` | `_fmtBytes` | `_sections.format.fmtBytes` | unbound / lexical |
| 369:65 | `_RecordingsPageState._delete` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 374:31 | `_RecordingsPageState._delete` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 375:16 | `_RecordingsPageState._delete` | `_isAndroid` | `_sections.data.isAndroid` | unbound / lexical |
| 378:10 | `_RecordingsPageState._delete` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 380:28 | `_RecordingsPageState._delete` | `context` | `_deps.context()` | unbound / lexical |
| 384:11 | `_RecordingsPageState._delete` | `_loadAll` | `_sections.data.loadAll` | unbound / lexical |
| 387:16 | `_RecordingsPageState._openFolder` | `_openFolder` | `openFolder` | declaration / name |
| 399:12 | `_RecordingsPageState._openFolder` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 401:9 | `_RecordingsPageState._openFolder` | `context` | `_deps.context()` | unbound / lexical |
| 409:16 | `_RecordingsPageState._createManualSchedule` | `_createManualSchedule` | `createManualSchedule` | declaration / name |
| 410:10 | `_RecordingsPageState._createManualSchedule` | `_desktop` | `_sections.data.desktop` | unbound / lexical |
| 411:12 | `_RecordingsPageState._createManualSchedule` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 412:28 | `_RecordingsPageState._createManualSchedule` | `context` | `_deps.context()` | unbound / lexical |
| 419:10 | `_RecordingsPageState._createManualSchedule` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 421:7 | `_RecordingsPageState._createManualSchedule` | `context` | `_deps.context()` | unbound / lexical |
| 424:28 | `_RecordingsPageState._createManualSchedule` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 427:28 | `_RecordingsPageState._createManualSchedule` | `context` | `_deps.context()` | unbound / lexical |
| 442:16 | `_RecordingsPageState._createManualSchedule` | `context` | `_deps.context()` | unbound / lexical |
| 448:26 | `_RecordingsPageState._createManualSchedule` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 454:26 | `_RecordingsPageState._createManualSchedule` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 467:30 | `_RecordingsPageState._createManualSchedule` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 473:7 | `_RecordingsPageState._createManualSchedule` | `context` | `_deps.context()` | unbound / lexical |
| 481:10 | `_RecordingsPageState._createManualSchedule` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 483:20 | `_RecordingsPageState._createManualSchedule` | `_desktop` | `_sections.data.desktop` | unbound / lexical |
| 504:10 | `_RecordingsPageState._createManualSchedule` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 506:28 | `_RecordingsPageState._createManualSchedule` | `context` | `_deps.context()` | unbound / lexical |
| 533:7 | `_RecordingsPageState._createManualSchedule` | `context` | `_deps.context()` | unbound / lexical |
| 535:11 | `_RecordingsPageState._createManualSchedule` | `_loadAll` | `_sections.data.loadAll` | unbound / lexical |
| 547:18 | `_RecordingsPageState._pickTime` | `context` | `_deps.context()` | unbound / lexical |
| 553:16 | `_RecordingsPageState._pickTime` | `context` | `_deps.context()` | unbound / lexical |
| 566:16 | `_RecordingsPageState._askRecordingLength` | `context` | `_deps.context()` | unbound / lexical |
| 597:28 | `_RecordingsPageState._askRecordingLength` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 604:29 | `_RecordingsPageState._askRecordingLength` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 636:18 | `_RecordingsPageState._askRecordingLength` | `context` | `_deps.context()` | unbound / lexical |
| 661:33 | `_RecordingsPageState._askRecordingLength` | `mounted` | `_deps.mounted()` | unbound / lexical |
| 668:10 | `_RecordingsPageState._fmtBytes` | `_fmtBytes` | `fmtBytes` | declaration / name |
| 679:10 | `_RecordingsPageState._fmtElapsed` | `_fmtElapsed` | `fmtElapsed` | declaration / name |
| 686:10 | `_RecordingsPageState._fmtCountdown` | `_fmtCountdown` | `fmtCountdown` | declaration / name |
| 695:10 | `_RecordingsPageState._fmtDuration` | `_fmtDuration` | `fmtDuration` | declaration / name |
| 703:10 | `_RecordingsPageState._clock` | `_clock` | `clock` | declaration / name |
| 703:53 | `_RecordingsPageState._clock` | `context` | `_deps.context()` | unbound / lexical |
| 707:10 | `_RecordingsPageState._dayLabel` | `_dayLabel` | `dayLabel` | declaration / name |
| 727:3 | `_RecordingsPageState._displayFor` | `_displayFor` | `displayFor` | declaration / name |
| 765:29 | `_RecordingsPageState.build` | `_desktopCaptures` | `_sections.data.desktopCaptures` | unbound / lexical |
| 766:23 | `_RecordingsPageState.build` | `_live` | `_owners.live` | unbound / lexical |
| 767:24 | `_RecordingsPageState.build` | `_library` | `_owners.library` | unbound / lexical |
| 769:10 | `_RecordingsPageState.build` | `_loading` | `_owners.loading` | unbound / lexical |
| 769:40 | `_RecordingsPageState.build` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 769:62 | `_RecordingsPageState.build` | `_library` | `_owners.library` | unbound / lexical |
| 776:13 | `_RecordingsPageState.build` | `_HubBar` | `RecordingsHubHubBar` | type alias / token |
| 778:43 | `_RecordingsPageState.build` | `_createManualSchedule` | `_sections.scheduling.createManualSchedule` | unbound / lexical |
| 783:21 | `_RecordingsPageState.build` | `_desktop` | `_sections.data.desktop` | unbound / lexical |
| 784:25 | `_RecordingsPageState.build` | `_isAndroid` | `_sections.data.isAndroid` | unbound / lexical |
| 784:40 | `_RecordingsPageState.build` | `_exactAlarms` | `_owners.exactAlarms` | unbound / lexical |
| 786:23 | `_RecordingsPageState.build` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 787:23 | `_RecordingsPageState.build` | `_library` | `_owners.library` | unbound / lexical |
| 788:27 | `_RecordingsPageState.build` | `_firstLibraryFocus` | `_owners.firstLibraryFocus` | unbound / lexical |
| 792:22 | `_RecordingsPageState.build` | `_loading` | `_owners.loading` | unbound / lexical |
| 794:63 | `_RecordingsPageState.build` | `_kAccent` | `kRecordingsHubAccent` | unbound / lexical |
| 797:21 | `_RecordingsPageState.build` | `_EmptyDvr` | `RecordingsHubEmptyDvr` | type alias / token |
| 798:51 | `_RecordingsPageState.build` | `_createManualSchedule` | `_sections.scheduling.createManualSchedule` | unbound / lexical |
| 799:40 | `_RecordingsPageState.build` | `_isAndroid` | `_sections.data.isAndroid` | unbound / lexical |
| 799:55 | `_RecordingsPageState.build` | `_exactAlarms` | `_owners.exactAlarms` | unbound / lexical |
| 807:29 | `_RecordingsPageState.build` | `_isAndroid` | `_sections.data.isAndroid` | unbound / lexical |
| 807:44 | `_RecordingsPageState.build` | `_exactAlarms` | `_owners.exactAlarms` | unbound / lexical |
| 808:27 | `_RecordingsPageState.build` | `_AlarmBanner` | `RecordingsHubAlarmBanner` | type alias / token |
| 815:29 | `_RecordingsPageState.build` | `_showBatteryNudge` | `_sections.data.showBatteryNudge` | unbound / lexical |
| 816:27 | `_RecordingsPageState.build` | `_BatteryBanner` | `RecordingsHubBatteryBanner` | type alias / token |
| 820:40 | `_RecordingsPageState.build` | `_dismissBatteryNudge` | `_sections.data.dismissBatteryNudge` | unbound / lexical |
| 825:27 | `_RecordingsPageState.build` | `_SectionHeader` | `RecordingsHubSectionHeader` | type alias / token |
| 828:40 | `_RecordingsPageState.build` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 831:29 | `_RecordingsPageState.build` | `_LiveCard` | `RecordingsHubLiveCard` | type alias / token |
| 834:36 | `_RecordingsPageState.build` | `_now` | `_owners.now` | unbound / lexical |
| 836:41 | `_RecordingsPageState.build` | `_fmtBytes` | `_sections.format.fmtBytes` | unbound / lexical |
| 837:43 | `_RecordingsPageState.build` | `_fmtElapsed` | `_sections.format.fmtElapsed` | unbound / lexical |
| 839:55 | `_RecordingsPageState.build` | `_stopDesktop` | `_sections.actions.stopDesktop` | unbound / lexical |
| 841:50 | `_RecordingsPageState.build` | `_live` | `_owners.live` | unbound / lexical |
| 842:29 | `_RecordingsPageState.build` | `_LiveCard` | `RecordingsHubLiveCard` | type alias / token |
| 849:36 | `_RecordingsPageState.build` | `_now` | `_owners.now` | unbound / lexical |
| 851:41 | `_RecordingsPageState.build` | `_fmtBytes` | `_sections.format.fmtBytes` | unbound / lexical |
| 852:43 | `_RecordingsPageState.build` | `_fmtElapsed` | `_sections.format.fmtElapsed` | unbound / lexical |
| 857:55 | `_RecordingsPageState.build` | `_stopAndroid` | `_sections.actions.stopAndroid` | unbound / lexical |
| 861:25 | `_RecordingsPageState.build` | `_SectionHeader` | `RecordingsHubSectionHeader` | type alias / token |
| 863:33 | `_RecordingsPageState.build` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 865:36 | `_RecordingsPageState.build` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 866:38 | `_RecordingsPageState.build` | `_kAccent` | `kRecordingsHubAccent` | unbound / lexical |
| 868:29 | `_RecordingsPageState.build` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 869:33 | `_RecordingsPageState.build` | `_EmptyHint` | `RecordingsHubEmptyHint` | type alias / token |
| 876:55 | `_RecordingsPageState.build` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 877:29 | `_RecordingsPageState.build` | `_ScheduleRow` | `RecordingsHubScheduleRow` | type alias / token |
| 879:36 | `_RecordingsPageState.build` | `_now` | `_owners.now` | unbound / lexical |
| 881:38 | `_RecordingsPageState.build` | `_dayLabel` | `_sections.format.dayLabel` | unbound / lexical |
| 882:38 | `_RecordingsPageState.build` | `_clock` | `_sections.format.clock` | unbound / lexical |
| 883:38 | `_RecordingsPageState.build` | `_clock` | `_sections.format.clock` | unbound / lexical |
| 884:45 | `_RecordingsPageState.build` | `_fmtCountdown` | `_sections.format.fmtCountdown` | unbound / lexical |
| 890:45 | `_RecordingsPageState.build` | `_cancelSchedule` | `_sections.actions.cancelSchedule` | unbound / lexical |
| 893:25 | `_RecordingsPageState.build` | `_SectionHeader` | `RecordingsHubSectionHeader` | type alias / token |
| 895:33 | `_RecordingsPageState.build` | `_library` | `_owners.library` | unbound / lexical |
| 897:36 | `_RecordingsPageState.build` | `_library` | `_owners.library` | unbound / lexical |
| 897:57 | `_RecordingsPageState.build` | `_fmtBytes` | `_sections.format.fmtBytes` | unbound / lexical |
| 899:35 | `_RecordingsPageState.build` | `_desktop` | `_sections.data.desktop` | unbound / lexical |
| 900:33 | `_RecordingsPageState.build` | `_HubIconButton` | `RecordingsHubHubIconButton` | type alias / token |
| 903:62 | `_RecordingsPageState.build` | `_openFolder` | `_sections.actions.openFolder` | unbound / lexical |
| 904:43 | `_RecordingsPageState.build` | `_library` | `_owners.library` | unbound / lexical |
| 906:47 | `_RecordingsPageState.build` | `_firstLibraryFocus` | `_owners.firstLibraryFocus` | unbound / lexical |
| 910:29 | `_RecordingsPageState.build` | `_library` | `_owners.library` | unbound / lexical |
| 911:33 | `_RecordingsPageState.build` | `_EmptyHint` | `RecordingsHubEmptyHint` | type alias / token |
| 919:52 | `_RecordingsPageState.build` | `_library` | `_owners.library` | unbound / lexical |
| 922:49 | `_RecordingsPageState.build` | `_displayFor` | `_sections.format.displayFor` | unbound / lexical |
| 923:40 | `_RecordingsPageState.build` | `_LibraryRow` | `RecordingsHubLibraryRow` | type alias / token |
| 924:55 | `_RecordingsPageState.build` | `_firstLibraryFocus` | `_owners.firstLibraryFocus` | unbound / lexical |
| 931:40 | `_RecordingsPageState.build` | `_dayLabel` | `_sections.format.dayLabel` | unbound / lexical |
| 932:44 | `_RecordingsPageState.build` | `_clock` | `_sections.format.clock` | unbound / lexical |
| 933:37 | `_RecordingsPageState.build` | `_fmtBytes` | `_sections.format.fmtBytes` | unbound / lexical |
| 935:39 | `_RecordingsPageState.build` | `_fmtDuration` | `_sections.format.fmtDuration` | unbound / lexical |
| 944:39 | `_RecordingsPageState.build` | `_schedules` | `_owners.schedules` | unbound / lexical |
| 946:59 | `_RecordingsPageState.build` | `_play` | `_sections.actions.play` | unbound / lexical |
| 947:61 | `_RecordingsPageState.build` | `_delete` | `_sections.actions.delete` | unbound / lexical |
| 953:27 | `_RecordingsPageState.build` | `_desktop` | `_sections.data.desktop` | unbound / lexical |
| 997:11 | `_HubBar` | `_HubIconButton` | `RecordingsHubHubIconButton` | type alias / token |
| 1003:64 | `_HubBar` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1015:11 | `_HubBar` | `_HubButton` | `RecordingsHubHubButton` | type alias / token |
| 1143:35 | `_LiveCard` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1146:20 | `_LiveCard` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1180:32 | `_LiveCard` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1192:11 | `_LiveCard` | `_HubButton` | `RecordingsHubHubButton` | type alias / token |
| 1243:16 | `_RecDotState` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1245:28 | `_RecDotState` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1322:33 | `_ScheduleRowState` | `_kGold` | `kRecordingsHubGold` | unbound / lexical |
| 1334:28 | `_ScheduleRowState` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1341:28 | `_ScheduleRowState` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1390:41 | `_ScheduleRowState` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1390:49 | `_ScheduleRowState` | `_kAccent` | `kRecordingsHubAccent` | unbound / lexical |
| 1398:42 | `_ScheduleRowState` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1474:29 | `_LibraryRowState` | `_kGold` | `kRecordingsHubGold` | unbound / lexical |
| 1542:11 | `_LibraryRowState` | `_RowIconButton` | `RecordingsHubRowIconButton` | type alias / token |
| 1585:23 | `_Thumb` | `_kGold` | `kRecordingsHubGold` | unbound / lexical |
| 1630:24 | `_EmptyDvr` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1637:24 | `_EmptyDvr` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1673:18 | `_EmptyDvr` | `_HubButton` | `RecordingsHubHubButton` | type alias / token |
| 1699:16 | `_BatteryBanner` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1701:35 | `_BatteryBanner` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1804:21 | `_AlarmBannerState` | `_kGold` | `kRecordingsHubGold` | unbound / lexical |
| 1901:14 | `_HubButtonState` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 1904:14 | `_HubButtonState` | `_kAccent` | `kRecordingsHubAccent` | unbound / lexical |
| 1941:33 | `_HubButtonState` | `_kGold` | `kRecordingsHubGold` | unbound / lexical |
| 2040:35 | `_HubIconButtonState` | `_kGold` | `kRecordingsHubGold` | unbound / lexical |
| 2109:21 | `_RowIconButtonState` | `_kRec` | `kRecordingsHubRec` | unbound / lexical |
| 2113:35 | `_RowIconButtonState` | `_kGold` | `kRecordingsHubGold` | unbound / lexical |

## State UI-boundary occurrences

| Line | Leaf | Name | Binding | Physical spelling |
| --- | --- | --- | --- | --- |
| 106 | `_RecordingsPageState.initState` | `mounted` | unbound / lexical | `mounted` |
| 108 | `_RecordingsPageState.initState` | `setState` | unbound / lexical | `setState` |
| 147 | `_RecordingsPageState._onRevision` | `mounted` | unbound / lexical | `mounted` |
| 162 | `_RecordingsPageState._dismissBatteryNudge` | `setState` | unbound / lexical | `_deps.setState` |
| 194 | `_RecordingsPageState._loadAll` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 205 | `_RecordingsPageState._loadAll` | `setState` | unbound / lexical | `_deps.setState` |
| 251 | `_RecordingsPageState._pollLive` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 268 | `_RecordingsPageState._pollLive` | `setState` | unbound / lexical | `_deps.setState` |
| 278 | `_RecordingsPageState._stopAndroid` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 279 | `_RecordingsPageState._stopAndroid` | `context` | unbound / lexical | `_deps.context()` |
| 285 | `_RecordingsPageState._stopAndroid` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 290 | `_RecordingsPageState._stopDesktop` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 291 | `_RecordingsPageState._stopDesktop` | `context` | unbound / lexical | `_deps.context()` |
| 305 | `_RecordingsPageState._cancelSchedule` | `context` | unbound / lexical | `_deps.context()` |
| 326 | `_RecordingsPageState._cancelSchedule` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 338 | `_RecordingsPageState._play` | `context` | unbound / lexical | `_deps.context()` |
| 354 | `_RecordingsPageState._delete` | `context` | unbound / lexical | `_deps.context()` |
| 374 | `_RecordingsPageState._delete` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 378 | `_RecordingsPageState._delete` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 380 | `_RecordingsPageState._delete` | `context` | unbound / lexical | `_deps.context()` |
| 399 | `_RecordingsPageState._openFolder` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 401 | `_RecordingsPageState._openFolder` | `context` | unbound / lexical | `_deps.context()` |
| 411 | `_RecordingsPageState._createManualSchedule` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 412 | `_RecordingsPageState._createManualSchedule` | `context` | unbound / lexical | `_deps.context()` |
| 419 | `_RecordingsPageState._createManualSchedule` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 421 | `_RecordingsPageState._createManualSchedule` | `context` | unbound / lexical | `_deps.context()` |
| 424 | `_RecordingsPageState._createManualSchedule` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 427 | `_RecordingsPageState._createManualSchedule` | `context` | unbound / lexical | `_deps.context()` |
| 442 | `_RecordingsPageState._createManualSchedule` | `context` | unbound / lexical | `_deps.context()` |
| 448 | `_RecordingsPageState._createManualSchedule` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 454 | `_RecordingsPageState._createManualSchedule` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 467 | `_RecordingsPageState._createManualSchedule` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 473 | `_RecordingsPageState._createManualSchedule` | `context` | unbound / lexical | `_deps.context()` |
| 481 | `_RecordingsPageState._createManualSchedule` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 504 | `_RecordingsPageState._createManualSchedule` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 506 | `_RecordingsPageState._createManualSchedule` | `context` | unbound / lexical | `_deps.context()` |
| 533 | `_RecordingsPageState._createManualSchedule` | `context` | unbound / lexical | `_deps.context()` |
| 547 | `_RecordingsPageState._pickTime` | `context` | unbound / lexical | `_deps.context()` |
| 553 | `_RecordingsPageState._pickTime` | `context` | unbound / lexical | `_deps.context()` |
| 566 | `_RecordingsPageState._askRecordingLength` | `context` | unbound / lexical | `_deps.context()` |
| 597 | `_RecordingsPageState._askRecordingLength` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 604 | `_RecordingsPageState._askRecordingLength` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 636 | `_RecordingsPageState._askRecordingLength` | `context` | unbound / lexical | `_deps.context()` |
| 661 | `_RecordingsPageState._askRecordingLength` | `mounted` | unbound / lexical | `_deps.mounted()` |
| 703 | `_RecordingsPageState._clock` | `context` | unbound / lexical | `_deps.context()` |
| 777 | `_RecordingsPageState.build` | `context` | decl:member#context#0 / lexical | `context` |

State `context` and `mounted` become live getters only in moved State members; local Builder and dialog contexts remain lexical. `setState` remains the original tear-off through `_deps.setState`. Constructor parameter labels, record type fields, and callback local variables are not owners fields. In particular `_dismissBatteryNudge` local `now` is distinct from the `ValueNotifier` owners field, `_loadAll` locals `live`/`schedules`/`library` are distinct from assignments, and named widget argument `now:` is a label. Static preference access uses the class receiver `RecordingsHubData`, never an instance.

## Callback envelopes and playback

The 72 exact callback/push sites are enumerated by member, call occurrence and argument in `dev/tool/recordings_callback_sites.json`, with ORIGINAL and step-1/2/3 physical token sequences. These include wrapped `unawaited` arrows, `bytesOf` closures, conditional DOWN closures, lexical `pop(d)`, dialog results, timers, the DevicePreferences chain and Builder callbacks. The validator compares tokens and occurrence counts before canonicalization. Each site has an independent checker/reader negative, plus compile-valid wrapper and receiver mutations.

The nullable compatibility parameter `suppressTrackerAutoSync` defaults to null at the constructor boundary and becomes false through `suppressTrackerAutoSync ?? suppressTraktAutoSync`; the ledger records that effective field default. The deprecated `suppressTraktAutoSync` parameter itself defaults to false. Both are launcher-only.

The single `_play` handoff supplies `videoUrl`, `title`, `showVideoTitle`, `disableExternalPlayer` in that order. `dev/tool/recordings_handoff_ledger.json` classifies every launch parameter; the typed engine-free observer checks all observable defaults, and the macOS external-default case proves launcher-only `disableExternalPlayer: false`. The Android value is S. The return observer is discharged by cover/resume and its 30-second fake deadline before fixture reset.

## Data, native and playback touchpoints

| Owner / operation | Contract | Classification |
| --- | --- | --- |
| `_loadAll` | Five futures in original order: live query, schedules, library, exact alarms, battery; one mounted check and one setState; ascending schedules, descending display stamp | Desktop B; Android S |
| `_pollLive`, `_syncTimers` | Native light query; ID membership; 3 s live / 15 s scheduled; no rearm for identical membership | S: dart:io Android unavailable |
| `_stopDesktop` | Await capture stop, select snackbar by actual bytes, reload | B: real local HTTP capture, nonzero and zero |
| `_stopAndroid` | Native stop, 1.2 s finalization delay, mounted-gated reload | S: Android unavailable |
| `_cancelSchedule`, `_delete` | Dialog safety focus and results; profile-owned cancel; actual filesystem delete/refusal and reload | Desktop B; native branch S |
| `_openFolder` | Create directory, open/explorer/xdg-open argv, fallback text | S: no safe Process.run interception |
| `_createManualSchedule` | Real public picker navigation, window and capacity policy, captured profile/authorization fields, real preference writes and result text | Desktop B; native readiness/exact-alarm/null-after-schedulable S |
| `_dismissBatteryNudge` | Device-wide preference; private Android dismissal value | Page S; separate DevicePreferences round-trip B |
| `_play` | Original launcher and settings policy; no engine mounts in tests | Desktop B; Android external-disable S |

Profiles remain owned by existing services: schedules/captures are profile-owned; the dismissal preference is device-wide. The fixture uses initialized legacy runtime or the existing committed two-profile fixture, and waits for captures/artifact writes before resetting the registry. No repository, service, player, native bridge or production seam changes.

## Resource construction and disposal

| Resource | Owner and construction | Release / borrowing |
| --- | --- | --- |
| `_now` | State construction, ValueNotifier | Dispose after both timers; borrowed by scoped builders |
| `_firstLibraryFocus` | State construction, original debug label | State disposes after notifier; row never disposes injected node |
| `_ticker` / `_poll` | `_syncTimers`, at most one ticker, Android poll replaced in order | Pause/hidden cancel and null; State dispose cancels before notifier |
| Binding observer + two revisions | State init after super, binding first then schedule revision then desktop revision | Dispose removes binding then both revisions, desktop guard preserved |
| `_RecDotState` controller | Non-TV init, 900 ms, bounds .35–1, repeat reverse | Controller dispose before super |
| Focusable row/button/banner own node | Lazy per widget State | Dispose only owned node before super |
| Fixture capture/server | Public desktop start, real HttpServer | Await stop and artifact drain, then server close, DB/registry reset and directory deletion |

Facade dispose order is binding observer → schedule listener → desktop listener → ticker → poll → notifier → borrowed first-library focus → super. This order is pinned as one AST leaf. Revision listener registration and removal are B: counted reloads prove effect, and protected `ChangeNotifier.hasListeners` observations prove presence while mounted and restoration to each notifier's pre-mount baseline after disposal. Each unregister call has its own ORIGINAL mutation proof. The Step 0 inert-callback probe was insufficient and is superseded by Step 0b.

## B/S proof inventory and source exceptions

Every mutation is named in `dev/tool/recordings_original_mutations.json`; B runs whole behavioural files and must fail its named assertion. S runs only the source-contract file and is reported separately. Simulated-move checker and reader rejections form the third report. Tests, harness, ledger and PNG bytes are frozen per mutation run.

| S row | Reason |
| --- | --- |
| `android_platform` | dart:io host stays macOS/Linux; Flutter target override does not make the native branch reachable |
| `poll_cadences` | Android native poll never arms on either test host |
| `membership` | Android native task membership path is unreachable on test hosts |
| `folder_process` | Process.run cannot be intercepted without a production seam and the fixture must not open Finder |
| `folder_fallback` | Process.run platform exception transport cannot be induced safely without opening a real desktop application |
| `exact_alarm_result` | desktop service cannot return Android exact-alarm rejection |
| `battery_private` | page dismissal and banner are Android-only; device preference round-trip is covered separately |
| `channel_metadata` | desktop listLibrary always supplies null channelName |
| `stored_duration` | desktop listLibrary always supplies null durationMs |
| `dormant_record_url` | isSchedulableUrl already requires a non-null engineRecordableUrl |
| `dispose_order` | resource and listener teardown order cannot be observed at all public boundaries; verbatim AST leaf pins ordering |
| `android_live_autofocus` | Android live entries never load on macOS/Linux; the desktop-first Stop rule is B, and the Android fallback additionally requires no desktop captures |
| `rec_dot_parameters` | controller numeric parameters are pinned structurally; TV static-vs-animation is separately behavioural |
| `focus_debug` | debug label is diagnostic metadata, not user-observable rendering |
| `handoff_android` | Android true is unreachable on desktop; desktop false is proven through external transport |
| `calendar_dst` | fixed test process timezone has no DST transition; calendar-vs-24-hour distinction needs a host zone different from the pinned protocol |
| All 22 mounted occurrences | Every lexical occurrence gets an independent S mutant. Not every asynchronous point can be suspended/unmounted at the public boundary without a production seam. The held initial load is independently B. |

Calendar-day versus 24-hour rollover is S on this pinned host timezone: ordinary next-day rollover and long-confirmation behaviour remain B. No Android reachability is invented with a Flutter target override.

## Shape, theme and strict inventory

The original radius aggregate is 12, with zero shape token calls. The new feature inventory test counts facade plus destinations and is additive to the existing 488-radius floor. The theme surface and strict diagnostic identities are frozen in `dev/tool/recordings_inventory.json`; no shape/theme production registrations activate at Step 0. The strict rename/alias receiver probe changes only syntax ownership, dependency wiring and imports in a throwaway R copy. Its baseline uses the per-identity maximum of original and probe diagnostics, including zero original key/private-type lint counts. Full compiling-composition measurement is reserved for Step 0b.

## Provided facts snapshot

The supplied inventory is preserved here for traceability. The AST-verified corrections at the top of this report supersede its descriptive counts.

```text
# recordings_page.dart — facts inventory (base 49c53e2e, 2,129 lines, dart-format clean)

Verify, don't trust. Line numbers are at base.

## Declarations
| Lines | Declaration |
| --- | --- |
| 1–18 | 18 imports (dart:async, dart:io, foundation kIsWeb, material, services; services: desktop_recording_service, desktop_schedule_service, live_recording_service, profiles/profile_preferences (DevicePreferences), video_player_launcher; utils: platform_util, tv_keys; widgets: recording_limit_dialogs, tv_time_picker, iptv/iptv_stage_panel show IptvMonogram, iptv/iptv_startup_channel_picker) |
| 20–28 | file header comment (DVR front door, 3 zones, 1 s notifier note) |
| 30–34 | `_kBg`, `_kCard`, `_kRec`, `_kGold`, `_kAccent` (Color consts) |
| 36–37 | doc + `_kDialogRowPadding` |
| 39–44 | `RecordingsPage` (public, const ctor, only public symbol) |
| 46–973 | `_RecordingsPageState with WidgetsBindingObserver` |
| 975–1026 | banner `// ── Top bar ──`, `_HubBar` |
| 1028–1110 | banner `// ── Sections ──`, `_SectionHeader`, `_EmptyHint` |
| 1112–1203 | banner, `_LiveCard` |
| 1205–1253 | doc, `_RecDot` + `_RecDotState` (SingleTickerProviderStateMixin; 900 ms 0.35–1.0 repeat reverse; none on TV) |
| 1255–1419 | banner, `_ScheduleRow` + State (field type `ScheduledRecording` from services/live_recording_service.dart) |
| 1421–1552 | banner, `_LibraryRow` + State (optional injected focusNode; own node lazily) |
| 1554–1599 | `_Thumb` (IptvMonogram) |
| 1601–1684 | banner, `_EmptyDvr` |
| 1686–1755 | doc, `_BatteryBanner` |
| 1757–1847 | `_AlarmBanner` + State |
| 1849–1964 | banner `// ── Buttons ──`, `_HubButton` + State (onDown redirect + repeat swallow) |
| 1966–2054 | `_HubIconButton` + State (onDown redirect + repeat swallow) |
| 2056–2129 | `_RowIconButton` + State |

## State members (46–973)
Fields (12 instance + 2 static): `_live` 48, `_schedules` 49, `_library` 50, `_loading` 51, `_exactAlarms` 52, `_now` 56 (final ValueNotifier<DateTime>(DateTime.now()), owned, disposed), `_ticker` 57, `_poll` 62, `_appVisible` 68, `_batteryExempt` 74, `_batteryNudgeDismissedAtMs` 75, static const `_batteryNudgeDismissedPref` 76–77, `_firstLibraryFocus` 83–85 (final FocusNode debugLabel 'recordings_first_library_row', owned, disposed), static final `_stampSuffix` 718–720 (RegExp).
Getters: `_isAndroid` 87 (`!kIsWeb && Platform.isAndroid`), `_desktop` 88 (`DesktopScheduleService.instance.isSupported`), `_desktopCaptures` 90, `_anythingLive` 93, `_showBatteryNudge` 150–158.
Methods: initState 95–111, dispose 113–125, didChangeAppLifecycleState 127–144, `_onRevision` 146–148, `_dismissBatteryNudge` 160–168, `_loadAll` 170–214, `_syncTimers` 216–240, `_pollLive` 242–272 (doc), banner 274, `_stopAndroid` 276–286, `_stopDesktop` 288–301, `_cancelSchedule` 303–333, `_play` 335–349, `_delete` 351–385, `_openFolder` 387–404, `_createManualSchedule` 406–536 (doc), `_pickTime` 538–557 (doc), `_askRecordingLength` 559–664 (doc), banner 666, `_fmtBytes` 668, `_fmtElapsed` 679, `_fmtCountdown` 686, `_fmtDuration` 695, `_clock` 703 (reads State context), `_dayLabel` 707, `_stampSuffix` 718, `_displayFor` 722–759 (doc), banner 761, build 763–972.

Field reference lines: _live 48 93 206 234 236 258 259 269 766 841; _schedules 49 207 218 234 260 261 270 769 786 863 865 868 876 944; _library 50 154 208 767 769 787 895 897 904 910 919; _loading 51 211 769 792; _exactAlarms 52 209 784 799 807; _now 56 122 221 834 849 879; _ticker 57 120 139 140 219–225; _poll 62 121 141 142 232 233 235; _appVisible 68 130 138 217; _batteryExempt 74 153 210; _batteryNudgeDismissedAtMs 75 108 157 162; _batteryNudgeDismissedPref 76 107 165; _firstLibraryFocus 83 123 788 906 924; _stampSuffix 718 732.
Getter refs: _isAndroid 151 172 181 184 187 190 234 246 346 375 784 799 807; _desktop 91 100 117 175 327 410 483 783 899 953; _desktopCaptures 93 765; _anythingLive 218; _showBatteryNudge 815.
Token refs: _kBg 772 (build only); _kCard 1141 (_LiveCard only); _kRec 369 (_delete) 828 (build) 1003 1143 1146 1180 1243 1245 1334 1341 1390 1398 1630 1637 1699 1701 1901 2109; _kGold 1322 1474 1585 1804 1941 2040 2113; _kAccent 794 866 (build) 1390 1904; _kDialogRowPadding 581 587 (_askRecordingLength only).

State `context` (non-lexical): 279 291 305 338 354 380 401 412 421 427 442 473 506 533 547 553 566 636 703. Lexical: 764 (build param), 777 (`Navigator.of(context)` inside build → build param), 921 (Builder param); `dialogContext` builder params 306 355 567 637 (642 lexical).
`mounted`: 106 (initState) 147 (_onRevision) 194 251 278 285 290 326 374 378 399 411 419 424 448 454 467 481 504 597 604 661.
`setState`: 108 (initState) 162 205 268. No shadowed setState.

Shadowing hazards after dropping underscores: locals `live`/`schedules`/`library` in `_loadAll` (195/198/200) and `_pollLive` (252/255); local `now` in `_dismissBatteryNudge` 161, `_createManualSchedule` 440, `_dayLabel` 708 (field `_now` → `now`); named-argument labels `now:` at 834/849/879 are labels, not references.

## Cross-class private use (widgets)
_HubButton ← _HubBar, _LiveCard, _EmptyDvr; _HubIconButton ← _HubBar, build; _RowIconButton ← _LibraryRow; _RecDot ← _LiveCard; _Thumb ← _LibraryRow; _AlarmBanner ← _EmptyDvr, build; build uses _HubBar, _EmptyDvr, _AlarmBanner, _BatteryBanner, _SectionHeader, _LiveCard, _EmptyHint, _ScheduleRow, _HubIconButton, _LibraryRow.

## Callbacks / identity
addObserver/removeObserver(this) 98/115; schedulesRevision add/remove(_onRevision) 99/116; desktop revision add/remove(_onRevision) 101/118; build: `onDismiss: _dismissBatteryNudge` 820; `fmtBytes: _fmtBytes` 836/851; `fmtElapsed: _fmtElapsed` 837/852; `fmtCountdown: _fmtCountdown` 884; closures onBack/onSchedule/onScheduleDown/onOpenAlarmSettings/onTap/onFix/onStop/onCancel/onPressed/onDown/onPlay/onDelete; Timer.periodic closures 220, 235–238.

## Touchpoints
Playback: one `VideoPlayerLauncher.push(context, VideoPlayerLaunchArgs(videoUrl: entry.uri, title: display.title, showVideoTitle: true, disableExternalPlayer: _isAndroid))` at 337–348.
Native/services: LiveRecordingService (MethodChannel `_channel`, static `schedulesRevision`): query, listSchedules, queryLibrary, exactAlarmsGranted, isIgnoringBatteryOptimizations, stop, cancelSchedule, deleteRecordingFile, ensureEngineReady, isSchedulableUrl, engineRecordableUrl, schedule, openExactAlarmSettings, requestIgnoreBatteryOptimizations. DesktopRecordingService (instance.captures, instance.revision, listLibrary, recordingsDir, deleteRecordingFile, capture.stop). DesktopScheduleService (instance.isSupported, list, cancel, add). DevicePreferences (device-wide prefs: get/set 'recording_battery_nudge_dismissed_at'). Process.run open/explorer/xdg-open. ensureRecordingCapacity (deliberate import cycle with widgets/recording_limit_dialogs.dart). showIptvStartupChannelPicker, showTvTimePicker, showDatePicker/showTimePicker.
Profile: page captures no profile. Desktop captures (`captures`) and schedules (`list`) are filtered by ProfileRuntime owner inside the services; `cancel` throws StateError for another profile's schedule without manageProfiles; Android store/library are device-wide (native). Battery-nudge pref is device-wide.
Platform reachability in tests: `_isAndroid` uses dart:io `Platform.isAndroid` → false on macOS/Linux test hosts (not overridable) → every Android-only branch is unreachable behaviourally. `_desktop` = isSupported = macOS/Windows/Linux → true on test hosts.

## Importers (all `const RecordingsPage()`)
lib/features/settings/presentation/legacy_settings/settings_page_navigation.dart:12/52; lib/features/iptv_settings/presentation/legacy_iptv_settings/iptv_settings_recording_actions.dart:2/34; lib/features/iptv/presentation/legacy_iptv/iptv_recording_support.dart:6/77; lib/widgets/recording_limit_dialogs.dart:5/130 (cycle). No test imports the file. dev/tool/iptv_settings_context_exceptions.json:1386 names RecordingsPage (iptv_settings config; unaffected).

## Registrations
file_size_baseline.txt:36 `2129 lib/screens/settings/recordings_page.dart`. Not in kShapeResidue/kExtractedShapeResidue (unswept; 0 app.shape tokens; bare radii present). theme_surface_manifest.txt:6 `settings` line covers lib/screens/settings/*.dart (this file is in the measured surface).

## Dead members
None found by reading (every private is referenced). Verify with analyzer.

```


Step 0b closes the independent ORIGINAL review with 13 additional behavioural identities. `recordings_review_closure_test.dart` pins both notifier registrations/disposals; ignored inactive lifecycle; live-only ticker and negative elapsed; focused/unfocused Stop fill and the live-card background/border; exact scheduled-empty, cancel and delete text; date initial/first/last/help values; Material and remote TV start/end pickers; one-hour end default; TV-only length autofocus; and live/schedule/library autofocus precedence. Two captures prove first-desktop-only Stop autofocus. The Android live Stop fallback is S because `_loadAll` never loads native entries on either host; its distinct mutation removes `desktopCaptures.isEmpty` and is reported separately.

`occurrence_field_bindings.mandatory_qualification` is explicitly `true`. Its opt-in `mandatory_qualification_classes` lists the owners and all five frozen section classes: the unchanged private `_LiveCard` owns a different field named `now`, and the shared unbound-name scan otherwise falsely rejects this original widget. Original-to-destination occurrence alignment and the recordings validator still cover every State field reference, including the facade. The real-config negative makes the renamed section read `now.value` bare, and requires the shared `Bare owner field reference` guard in addition to checker/reader rejection. No new state/field-class or occurrence-substitution mechanisms are used.
