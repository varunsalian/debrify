# Recordings ORIGINAL text and visual contracts

Frozen by AST from `R=49c53e2e`. The feature-owned visitor accounts for **134 string expressions**, including adjacent strings, interpolation branches and implicit constructors: **104 visible (93 B / 11 S)** and **30 internal**. No string is silently omitted. The machine inventory is [`recordings_text_inventory.json`](../../dev/tool/recordings_text_inventory.json); `recordings_text_inventory.py --self-test --parser-package <isolated-copy>` checks the real inventory and rejects omissions, altered templates/properties, unclassified text, source-contract substitution and unjustified S rows.

B assertions inspect the mounted ORIGINAL page through public widgets and services. Golden text blocks do not establish text identity or styles. Each Text assertion compares maxLines, overflow, textAlign, fontSize, fontWeight, colour (including alpha), letterSpacing, height and fontFeatures, including null/default values. Expected values are frozen constants; behaviour tests never read source or invoke the reader.

| String class | B | S |
| --- | ---: | ---: |
| android_banners | 0 | 5 |
| byte_duration_elapsed | 12 | 0 |
| countdown | 6 | 0 |
| day_labels | 11 | 0 |
| dialogs | 23 | 0 |
| headers_chips | 6 | 0 |
| hints_footers | 3 | 1 |
| pickers | 4 | 0 |
| row_templates | 7 | 0 |
| snackbars | 10 | 5 |
| titles | 2 | 0 |
| titles_buttons | 6 | 0 |
| tooltips | 3 | 0 |

**Text properties:** 42 AST sites, **34 B / 8 S**. **Focus:** seven B cases (filled/danger HubButton, HubIconButton, RowIconButton, ScheduleRow, LibraryRow, Thumb highlight) / two S cases (plain HubButton and AlarmBanner). Both states are checked for backgrounds, borders/widths/radii and icon/text colours; row circle/countdown and Thumb gradient/play decorations are included. The two HubButton filled callers share a body; the empty-DVR caller’s Text is also checked.

## Every visible string literal / template

IDs retain member and AST ordinal; the JSON retains exact source, decoded value where constant, physical line, test file/name and assertion marker. Templates are asserted through complete rendered examples, with all nested conditional alternatives covered. Dynamic provider metadata is passed through reachable desktop entries; Android library-channel metadata remains the earlier documented S boundary.

| AST identity | Literal / interpolation template | Contract / covering test or reason |
| --- | --- | --- |
| `string:_RecordingsPageState._stopAndroid:0` | Stopping — saving recording… | S — Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `string:_RecordingsPageState._stopDesktop:0` | 'Recording saved (${_fmtBytes(bytes)})' | B — desktop Stop outcome; `Stop snackbar matches captured byte outcome` |
| `string:_RecordingsPageState._stopDesktop:1` | Recording stopped — nothing was captured | B — desktop Stop outcome; `Stop snackbar matches captured byte outcome` |
| `string:_RecordingsPageState._cancelSchedule:0` | Cancel recording? | B — cancel and delete dialog complete verbatim text and Text properties; `cancel dialog verbatim inventory:` |
| `string:_RecordingsPageState._cancelSchedule:1` | '${schedule.programmeTitle} — ${schedule.channelName}' | B — cancel dialog content uses title dash channel or channel alone; `cancel content uses title em dash channel` |
| `string:_RecordingsPageState._cancelSchedule:2` | Keep | B — cancel and delete dialog complete verbatim text and Text properties; `cancel dialog verbatim inventory:` |
| `string:_RecordingsPageState._cancelSchedule:3` | Cancel recording | B — cancel and delete dialog complete verbatim text and Text properties; `cancel dialog verbatim inventory:` |
| `string:_RecordingsPageState._delete:0` | Delete recording? | B — cancel and delete dialog complete verbatim text and Text properties; `delete dialog verbatim inventory:` |
| `string:_RecordingsPageState._delete:1` | '${display.title} (${_fmtBytes(entry.bytes)}) will be removed '           'from this device.' | B — cancel and delete dialog complete verbatim text and Text properties; `delete dialog verbatim inventory:` |
| `string:_RecordingsPageState._delete:2` | Keep | B — cancel and delete dialog complete verbatim text and Text properties; `delete dialog verbatim inventory:` |
| `string:_RecordingsPageState._delete:3` | Delete | B — cancel and delete dialog complete verbatim text and Text properties; `delete dialog verbatim inventory:` |
| `string:_RecordingsPageState._delete:4` | Couldn't delete the recording | B — active capture refuses delete and failure still reloads; `active-capture deletion reports refusal` |
| `string:_RecordingsPageState._openFolder:3` | 'Recordings folder: ${dir.path}' | S — Process.run is not interceptable without a production seam; no desktop application is launched to force its exception fallback. |
| `string:_RecordingsPageState._createManualSchedule:0` | Storage access is needed to save recordings | S — Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `string:_RecordingsPageState._createManualSchedule:1` | Record which channel? | B — manual picker title invalid channel and duplicate result verbatim; `channel picker title verbatim` |
| `string:_RecordingsPageState._createManualSchedule:2` | This channel can't be scheduled — recording needs a direct TS or Xtream stream | B — manual picker title invalid channel and duplicate result verbatim; `unschedulable channel snackbar verbatim` |
| `string:_RecordingsPageState._createManualSchedule:3` | Recording date | B — desktop manual pickers pin dates times and no preset autofocus; `date picker help text is Recording date` |
| `string:_RecordingsPageState._createManualSchedule:4` | Start time | B — desktop manual pickers pin dates times and no preset autofocus; `date picker help text is Recording date` |
| `string:_RecordingsPageState._createManualSchedule:8` | Allow "Alarms & reminders" for Debrify to schedule recordings | S — DesktopScheduleService cannot return Android exact_alarms_required; the settings action belongs to that native result branch. |
| `string:_RecordingsPageState._createManualSchedule:9` | Settings | S — DesktopScheduleService cannot return Android exact_alarms_required; the settings action belongs to that native result branch. |
| `string:_RecordingsPageState._createManualSchedule:10` | Recording starts in a few seconds | B — past start clamps to captured now and writes immediate schedule; `immediate schedule reports immediate result` |
| `string:_RecordingsPageState._createManualSchedule:11` | Recording scheduled | B — manual preset persists empty programme headers and exact duration; `scheduled result snackbar verbatim` |
| `string:_RecordingsPageState._createManualSchedule:13` | Already scheduled at that time | B — manual picker title invalid channel and duplicate result verbatim; `duplicate result snackbar verbatim` |
| `string:_RecordingsPageState._createManualSchedule:15` | Would exceed the simultaneous-recordings limit — raise it in IPTV settings or pick another slot | B — hidden owner capacity backstop reports overlap result; `backend overlap retains original result message` |
| `string:_RecordingsPageState._createManualSchedule:17` | That time has already passed | B — manual next-minute end and removed source result text; `bad-time result snackbar verbatim` |
| `string:_RecordingsPageState._createManualSchedule:18` | Couldn't schedule recording | B — manual next-minute end and removed source result text; `removed-source result snackbar verbatim` |
| `string:_RecordingsPageState._askRecordingLength:0` | Record for how long? | B — long recording full content all interpolation branches and buttons; `length title verbatim` |
| `string:_RecordingsPageState._askRecordingLength:1` | 5 minutes (test) | B — long recording full content all interpolation branches and buttons; `length title verbatim` |
| `string:_RecordingsPageState._askRecordingLength:2` | 30 minutes | B — long recording full content all interpolation branches and buttons; `length title verbatim` |
| `string:_RecordingsPageState._askRecordingLength:3` | 1 hour | B — long recording full content all interpolation branches and buttons; `length title verbatim` |
| `string:_RecordingsPageState._askRecordingLength:4` | 2 hours | B — long recording full content all interpolation branches and buttons; `length title verbatim` |
| `string:_RecordingsPageState._askRecordingLength:5` | 3 hours | B — long recording full content all interpolation branches and buttons; `length title verbatim` |
| `string:_RecordingsPageState._askRecordingLength:6` | Pick end time… | B — long recording full content all interpolation branches and buttons; `length title verbatim` |
| `string:_RecordingsPageState._askRecordingLength:7` | End time | B — desktop manual pickers pin dates times and no preset autofocus; `end picker starts one hour after chosen start` |
| `string:_RecordingsPageState._askRecordingLength:8` | That's a long recording | B — long recording full content all interpolation branches and buttons; `long recording content verbatim:` |
| `string:_RecordingsPageState._askRecordingLength:9` | 'Recording would run ${hours}h'             '${minutes > 0 ? ' ${minutes}m' : ''}, '             'ending ${TimeOfDay.fromDateTime(end).format(dialogContext)}'             '${end.day != start.day ? ' the next day' : ''}.' | B — long recording full content all interpolation branches and buttons; `long recording content verbatim:` |
| `string:_RecordingsPageState._askRecordingLength:10` | ' ${minutes}m' | B — long recording full content all interpolation branches and buttons; `long recording content verbatim:` |
| `string:_RecordingsPageState._askRecordingLength:11` |  | B — long recording full content all interpolation branches and buttons; `long recording content verbatim:` |
| `string:_RecordingsPageState._askRecordingLength:12` |  the next day | B — long recording full content all interpolation branches and buttons; `long recording content verbatim:` |
| `string:_RecordingsPageState._askRecordingLength:13` |  | B — long recording full content all interpolation branches and buttons; `long recording content verbatim:` |
| `string:_RecordingsPageState._askRecordingLength:14` | Cancel | B — long recording full content all interpolation branches and buttons; `long recording content verbatim:` |
| `string:_RecordingsPageState._askRecordingLength:15` | Record | B — long recording full content all interpolation branches and buttons; `long recording content verbatim:` |
| `string:_RecordingsPageState._fmtBytes:0` | '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB' | B — byte and duration templates are verbatim in rendered subtitles; `formatted library subtitle verbatim:` |
| `string:_RecordingsPageState._fmtBytes:1` | '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB' | B — byte and duration templates are verbatim in rendered subtitles; `formatted library subtitle verbatim:` |
| `string:_RecordingsPageState._fmtBytes:2` | '${(bytes / 1024).toStringAsFixed(0)} KB' | B — byte and duration templates are verbatim in rendered subtitles; `formatted library subtitle verbatim:` |
| `string:_RecordingsPageState._fmtBytes:3` | '$bytes B' | B — byte and duration templates are verbatim in rendered subtitles; `formatted library subtitle verbatim:` |
| `string:_RecordingsPageState._fmtElapsed:0` | 0 | B — populated DVR verbatim headers chips footer and live text; `elapsed hour template verbatim` |
| `string:_RecordingsPageState._fmtElapsed:1` | 0 | B — populated DVR verbatim headers chips footer and live text; `elapsed hour template verbatim` |
| `string:_RecordingsPageState._fmtElapsed:2` | '$h:$m:$s' | B — populated DVR verbatim headers chips footer and live text; `elapsed hour template verbatim` |
| `string:_RecordingsPageState._fmtElapsed:3` | '$m:$s' | B — populated DVR verbatim headers chips footer and live text; `elapsed hour template verbatim` |
| `string:_RecordingsPageState._fmtCountdown:0` | starting… | B — countdown renders second minute hour and day boundaries; `countdown boundary` |
| `string:_RecordingsPageState._fmtCountdown:1` | 'in ${untilStart.inMinutes}m' | B — countdown renders second minute hour and day boundaries; `countdown boundary` |
| `string:_RecordingsPageState._fmtCountdown:2` | 'in ${h}h' | B — countdown renders second minute hour and day boundaries; `countdown boundary` |
| `string:_RecordingsPageState._fmtCountdown:3` | 'in ${h}h ${m}m' | B — countdown renders second minute hour and day boundaries; `countdown boundary` |
| `string:_RecordingsPageState._fmtCountdown:4` | 'in ${untilStart.inDays}d ${h.remainder(24)}h' | B — countdown renders second minute hour and day boundaries; `countdown boundary` |
| `string:_RecordingsPageState._fmtDuration:0` | '${d.inSeconds}s' | B — byte and duration templates are verbatim in rendered subtitles; `formatted library subtitle verbatim:` |
| `string:_RecordingsPageState._fmtDuration:1` | '${d.inMinutes} min' | B — byte and duration templates are verbatim in rendered subtitles; `formatted library subtitle verbatim:` |
| `string:_RecordingsPageState._fmtDuration:2` | '${d.inHours}h' | B — byte and duration templates are verbatim in rendered subtitles; `formatted library subtitle verbatim:` |
| `string:_RecordingsPageState._fmtDuration:3` | '${d.inHours}h ${m}m' | B — byte and duration templates are verbatim in rendered subtitles; `formatted library subtitle verbatim:` |
| `string:_RecordingsPageState._dayLabel:0` | Today | B — Today label and exact whole-hour library duration; `Today library label verbatim` |
| `string:_RecordingsPageState._dayLabel:1` | Tomorrow | B — relative day and channel prefix templates are verbatim in both row kinds; `relative library subtitle verbatim:` |
| `string:_RecordingsPageState._dayLabel:2` | Yesterday | B — relative day and channel prefix templates are verbatim in both row kinds; `relative library subtitle verbatim:` |
| `string:_RecordingsPageState._dayLabel:3` | Mon | B — each nonrelative weekday and day month appears in both row kinds; `nonrelative schedule weekday d/m verbatim:` |
| `string:_RecordingsPageState._dayLabel:4` | Tue | B — each nonrelative weekday and day month appears in both row kinds; `nonrelative schedule weekday d/m verbatim:` |
| `string:_RecordingsPageState._dayLabel:5` | Wed | B — each nonrelative weekday and day month appears in both row kinds; `nonrelative schedule weekday d/m verbatim:` |
| `string:_RecordingsPageState._dayLabel:6` | Thu | B — each nonrelative weekday and day month appears in both row kinds; `nonrelative schedule weekday d/m verbatim:` |
| `string:_RecordingsPageState._dayLabel:7` | Fri | B — each nonrelative weekday and day month appears in both row kinds; `nonrelative schedule weekday d/m verbatim:` |
| `string:_RecordingsPageState._dayLabel:8` | Sat | B — each nonrelative weekday and day month appears in both row kinds; `nonrelative schedule weekday d/m verbatim:` |
| `string:_RecordingsPageState._dayLabel:9` | Sun | B — each nonrelative weekday and day month appears in both row kinds; `nonrelative schedule weekday d/m verbatim:` |
| `string:_RecordingsPageState._dayLabel:10` | '${weekdays[d.weekday - 1]} ${d.day}/${d.month}' | B — each nonrelative weekday and day month appears in both row kinds; `nonrelative schedule weekday d/m verbatim:` |
| `string:_RecordingsPageState._displayFor:2` |   | B — populated DVR verbatim headers chips footer and live text; `populated DVR verbatim text:` |
| `string:_RecordingsPageState._displayFor:3` | Recording | B — relative day and channel prefix templates are verbatim in both row kinds; `fallback library title verbatim` |
| `string:_RecordingsPageState.build:0` | RECORDING NOW | B — populated DVR verbatim headers chips footer and live text; `populated DVR verbatim text:` |
| `string:_RecordingsPageState.build:1` | '$liveCount LIVE' | B — populated DVR verbatim headers chips footer and live text; `populated DVR verbatim text:` |
| `string:_RecordingsPageState.build:2` | SCHEDULED | B — populated DVR verbatim headers chips footer and live text; `populated DVR verbatim text:` |
| `string:_RecordingsPageState.build:3` | '${_schedules.length} UPCOMING' | B — populated DVR verbatim headers chips footer and live text; `populated DVR verbatim text:` |
| `string:_RecordingsPageState.build:4` | Nothing scheduled — pick an upcoming programme in a channel's TV guide, or press Schedule above. | B — empty zones retain both full hints and desktop footer; `library hint verbatim inventory` |
| `string:_RecordingsPageState.build:5` | '${_dayLabel(DateTime.fromMillisecondsSinceEpoch(schedule.startMs))} · '                                   '${_clock(schedule.startMs)} – '                                   '${_clock(schedule.endMs)}' | B — each nonrelative weekday and day month appears in both row kinds; `nonrelative schedule weekday d/m verbatim:` |
| `string:_RecordingsPageState.build:6` | LIBRARY | B — populated DVR verbatim headers chips footer and live text; `populated DVR verbatim text:` |
| `string:_RecordingsPageState.build:7` | '${_library.length} · ${_fmtBytes(totalBytes)}' | B — populated DVR verbatim headers chips footer and live text; `populated DVR verbatim text:` |
| `string:_RecordingsPageState.build:8` | Show in folder | B — populated DVR verbatim headers chips footer and live text; `folder tooltip verbatim` |
| `string:_RecordingsPageState.build:9` | No recordings yet. Focus a live channel and press Record, or schedule one — finished recordings appear here, ready to play. | B — empty zones retain both full hints and desktop footer; `library hint verbatim inventory` |
| `string:_RecordingsPageState.build:10` | '${_dayLabel(display.recordedAt)} '                                         '${_clock(display.recordedAt.millisecondsSinceEpoch)}' | B — each nonrelative weekday and day month appears in both row kinds; `nonrelative schedule weekday d/m verbatim:` |
| `string:_RecordingsPageState.build:11` |  ·  | B — each nonrelative weekday and day month appears in both row kinds; `nonrelative schedule weekday d/m verbatim:` |
| `string:_RecordingsPageState.build:12` | Recordings run while Debrify is open and the computer is awake · saved in Downloads/Debrify/Recordings | B — empty zones retain both full hints and desktop footer; `desktop footer verbatim inventory` |
| `string:_RecordingsPageState.build:13` | Recordings run even with the app closed · saved in Downloads/Debrify/Recordings | S — Non-desktop footer requires Android/iOS/tvOS runtime; macOS and Linux both have the desktop capability. No host-platform seam in ORIGINAL. |
| `string:_HubBar.build:0` | Back | B — empty DVR verbatim chrome hints buttons and tooltip; `Back tooltip verbatim` |
| `string:_HubBar.build:1` | Recordings | B — empty DVR verbatim chrome hints buttons and tooltip; `empty DVR verbatim text:` |
| `string:_HubBar.build:2` | Schedule | B — empty DVR verbatim chrome hints buttons and tooltip; `empty DVR verbatim text:` |
| `string:_LiveCard.build:0` | '${fmtElapsed(elapsed.isNegative ? Duration.zero : elapsed)}'                       '${bytes > 0 ? ' · ${fmtBytes(bytes)}' : ''}' | B — populated DVR verbatim headers chips footer and live text; `populated DVR verbatim text:` |
| `string:_LiveCard.build:1` | ' · ${fmtBytes(bytes)}' | B — populated DVR verbatim headers chips footer and live text; `populated DVR verbatim text:` |
| `string:_LiveCard.build:2` |  | B — zero-byte live elapsed has no byte separator; `zero-byte live elapsed verbatim without separator` |
| `string:_LiveCard.build:3` | Stop | B — populated DVR verbatim headers chips footer and live text; `populated DVR verbatim text:` |
| `string:_ScheduleRowState.build:0` | '${s.channelName} · ${widget.timeText}' | B — relative day and channel prefix templates are verbatim in both row kinds; `relative titled schedule subtitle verbatim:` |
| `string:_ScheduleRowState.build:1` | due | B — countdown renders second minute hour and day boundaries; `past schedule is due` |
| `string:_LibraryRowState.build:0` | Delete recording | B — populated DVR verbatim headers chips footer and live text; `delete tooltip verbatim` |
| `string:_EmptyDvr.build:0` | Your DVR is empty | B — empty DVR verbatim chrome hints buttons and tooltip; `empty DVR verbatim text:` |
| `string:_EmptyDvr.build:1` | Record what's on now with the Record button on any live channel, set a recording from a programme guide, or schedule a channel and time yourself. | B — empty DVR verbatim chrome hints buttons and tooltip; `empty DVR verbatim text:` |
| `string:_EmptyDvr.build:2` | Schedule a recording | B — empty DVR verbatim chrome hints buttons and tooltip; `empty DVR verbatim text:` |
| `string:_BatteryBanner.build:0` | A recording stopped early | S — Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `string:_BatteryBanner.build:1` | The phone likely put Debrify to sleep mid-capture. Tap to exclude Debrify from battery optimization so long recordings run to the end. | S — Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `string:_BatteryBanner.build:2` | Dismiss | S — Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `string:_AlarmBannerState.build:0` | Exact alarms are off | S — Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `string:_AlarmBannerState.build:1` | Scheduled recordings can't start until "Alarms & reminders" is allowed. Tap to open system settings. | S — Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |

## Every Text call site

Both const instance creations and implicit invocations are collected. The machine inventory freezes each AST data expression and all explicit named properties, including its complete TextStyle. B tests check rendered widget properties; Android/process exceptions retain exact source protection.

| AST identity | Contract | Property assertion |
| --- | --- | --- |
| `Text:_RecordingsPageState._stopAndroid:0` | S | Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `Text:_RecordingsPageState._stopDesktop:0` | B | desktop Stop outcome; `desktop Stop snackbar Text properties` |
| `Text:_RecordingsPageState._cancelSchedule:0` | B | cancel and delete dialog complete verbatim text and Text properties; `cancel dialog Text properties:` |
| `Text:_RecordingsPageState._cancelSchedule:1` | B | cancel and delete dialog complete verbatim text and Text properties; `cancel dialog Text properties:` |
| `Text:_RecordingsPageState._cancelSchedule:2` | B | cancel and delete dialog complete verbatim text and Text properties; `cancel dialog Text properties:` |
| `Text:_RecordingsPageState._cancelSchedule:3` | B | cancel and delete dialog complete verbatim text and Text properties; `cancel dialog Text properties:` |
| `Text:_RecordingsPageState._delete:0` | B | cancel and delete dialog complete verbatim text and Text properties; `delete dialog Text properties:` |
| `Text:_RecordingsPageState._delete:1` | B | cancel and delete dialog complete verbatim text and Text properties; `delete dialog Text properties:` |
| `Text:_RecordingsPageState._delete:2` | B | cancel and delete dialog complete verbatim text and Text properties; `delete dialog Text properties:` |
| `Text:_RecordingsPageState._delete:3` | B | cancel and delete dialog complete verbatim text and Text properties; `delete dialog Text properties:` |
| `Text:_RecordingsPageState._delete:4` | B | active capture refuses delete and failure still reloads; `delete failure snackbar Text properties` |
| `Text:_RecordingsPageState._openFolder:0` | S | Process.run is not interceptable without a production seam; no desktop application is launched to force its exception fallback. |
| `Text:_RecordingsPageState._createManualSchedule:0` | S | Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `Text:_RecordingsPageState._createManualSchedule:1` | B | manual picker title invalid channel and duplicate result verbatim; `manual result snackbar Text properties` |
| `Text:_RecordingsPageState._createManualSchedule:2` | S | Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `Text:_RecordingsPageState._createManualSchedule:3` | B | manual picker title invalid channel and duplicate result verbatim; `manual result snackbar Text properties` |
| `Text:_RecordingsPageState._askRecordingLength:0` | B | long recording full content all interpolation branches and buttons; `length dialog Text properties:` |
| `Text:_RecordingsPageState._askRecordingLength:1` | B | long recording full content all interpolation branches and buttons; `length dialog Text properties:` |
| `Text:_RecordingsPageState._askRecordingLength:2` | B | long recording full content all interpolation branches and buttons; `length dialog Text properties:` |
| `Text:_RecordingsPageState._askRecordingLength:3` | B | long recording full content all interpolation branches and buttons; `long dialog Text properties:` |
| `Text:_RecordingsPageState._askRecordingLength:4` | B | long recording full content all interpolation branches and buttons; `long dialog Text properties:` |
| `Text:_RecordingsPageState._askRecordingLength:5` | B | long recording full content all interpolation branches and buttons; `long dialog Text properties:` |
| `Text:_RecordingsPageState._askRecordingLength:6` | B | long recording full content all interpolation branches and buttons; `long dialog Text properties:` |
| `Text:_RecordingsPageState.build:0` | B | populated widgets every Text site has explicit properties; `Layout footer Text properties` |
| `Text:_HubBar.build:0` | B | empty DVR and hub title Text properties; `HubBar title Text properties` |
| `Text:_SectionHeader.build:0` | B | populated widgets every Text site has explicit properties; `SectionHeader label Text properties` |
| `Text:_SectionHeader.build:1` | B | populated widgets every Text site has explicit properties; `SectionHeader chip Text properties` |
| `Text:_EmptyHint.build:0` | B | empty hint Text properties; `EmptyHint Text properties` |
| `Text:_LiveCard.build:0` | B | populated widgets every Text site has explicit properties; `LiveCard title Text properties` |
| `Text:_LiveCard.build:1` | B | populated widgets every Text site has explicit properties; `LiveCard elapsed Text properties` |
| `Text:_ScheduleRowState.build:0` | B | populated widgets every Text site has explicit properties; `ScheduleRow title Text properties` |
| `Text:_ScheduleRowState.build:1` | B | populated widgets every Text site has explicit properties; `ScheduleRow subtitle Text properties` |
| `Text:_ScheduleRowState.build:2` | B | populated widgets every Text site has explicit properties; `ScheduleRow upcoming countdown Text properties` |
| `Text:_LibraryRowState.build:0` | B | populated widgets every Text site has explicit properties; `LibraryRow title Text properties` |
| `Text:_LibraryRowState.build:1` | B | populated widgets every Text site has explicit properties; `LibraryRow subtitle Text properties` |
| `Text:_EmptyDvr.build:0` | B | empty DVR and hub title Text properties; `EmptyDvr title Text properties` |
| `Text:_EmptyDvr.build:1` | B | empty DVR and hub title Text properties; `EmptyDvr explanation Text properties` |
| `Text:_BatteryBanner.build:0` | S | Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `Text:_BatteryBanner.build:1` | S | Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `Text:_AlarmBannerState.build:0` | S | Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `Text:_AlarmBannerState.build:1` | S | Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |
| `Text:_HubButtonState.build:0` | B | both focus states pin decoration icon and text; `focus Text properties` |

## Focus variants

| Widget / variant | Contract | Covering test / reason |
| --- | --- | --- |
| _HubButtonState / filled | B | filled both focus states pin decoration icon and text |
| _HubButtonState / danger | B | danger both focus states pin decoration icon and text |
| _HubIconButtonState / hub icon | B | hub icon both focus states pin decoration icon and text |
| _RowIconButtonState / row icon | B | row icon both focus states pin decoration icon and text |
| _ScheduleRowState / schedule | B | schedule both focus states pin decoration icon and text |
| _LibraryRowState / library and thumb | B | library and thumb both focus states pin decoration icon and text |
| _Thumb / thumb highlight | B | library and thumb both focus states pin decoration icon and text |
| _HubButtonState / plain | S | All three original _HubButton call sites explicitly select filled:true or danger:true. No caller renders the plain branch; AST call inventory proves this without a production seam. |
| _AlarmBannerState / alarm | S | Android dart:io branch cannot be reached on a macOS/Linux Flutter test host; target-platform/cached-TV overrides do not change Platform.isAndroid. |

The plain variant is structurally unreachable: AST inventory finds exactly three original `_HubButton` calls, each explicitly `filled: true` or `danger: true`. The inventory checker rejects a future caller becoming plain until the S classification is replaced by executable coverage. Native alarm/battery branches depend on `dart:io Platform.isAndroid`, not Flutter target overrides. The folder fallback would require launching a real application to force `Process.run` failure. Bad-time and removed-source backend results are reachable and asserted verbatim; only the Android/process/platform text exceptions remain S. The accepted `_RecDot` controller-bound S case remains unchanged.

The 30 internal expressions are individually classified with reasons in the JSON (imports, preference/debug identities, process executable names, backend discriminators and filename parsing inputs). They are not user-visible text and are not counted as S.
