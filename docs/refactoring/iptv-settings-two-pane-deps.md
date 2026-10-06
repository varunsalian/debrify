# IPTV settings two-pane — dependency report

Companion to [iptv-settings-two-pane-plan.md](iptv-settings-two-pane-plan.md).
Seeded by Claude at plan time (base `49c53e2e`); execution completes it at
step 0 from the actual AST references (reads of `widget` by property,
State vs lexical `context`, `mounted`, owner fields, statics, tear-offs) and
it is then frozen.

## Frozen member map

| Original (lines) | Destination file | New name |
| --- | --- | --- |
| `iptvAutoRefreshLabel`, `iptvAutoRefreshExplanation`, `IptvAutoRefreshDialog` (13–79) | `presentation/iptv_auto_refresh_dialog.dart` | unchanged |
| `_Dest` family (256–301) | `presentation/iptv_two_pane_destination.dart` | `IptvTwoPaneDest`, `IptvTwoPaneSourceDest`, `IptvTwoPaneAddDest`, `IptvTwoPaneListsDest`, `IptvTwoPaneStartupDest`, `IptvTwoPaneAutoRefreshDest`, `IptvTwoPaneContinueWatchingDest`, `IptvTwoPaneChannelPreviewDest`, `IptvTwoPaneAppearanceDest`, `IptvTwoPanePlayerGuideDest`, `IptvTwoPaneRecordingDest` |
| `_RailHeading`, `_RailEntry`, `_RailEntryState` (1583–1784) | `presentation/iptv_two_pane_rail_entry.dart` | `IptvTwoPaneRailHeading`, `IptvTwoPaneRailEntry`, `IptvTwoPaneRailEntryState` |
| `_PaneHeader`, `_Badge`, `_StatStrip`, `_QuietBanner`, `_RowGroup` (1786–1977) | `presentation/iptv_two_pane_pane_parts.dart` | `IptvTwoPanePaneHeader`, `IptvTwoPaneBadge`, `IptvTwoPaneStatStrip`, `IptvTwoPaneQuietBanner`, `IptvTwoPaneRowGroup` |
| `_PaneRow`, `_PaneRowState` (1979–2119) | `presentation/iptv_two_pane_row.dart` | `IptvTwoPaneRow`, `IptvTwoPaneRowState` |
| `_MethodCard`, `_MethodCardState` (2121–2231) | `presentation/iptv_two_pane_method_card.dart` | `IptvTwoPaneMethodCard`, `IptvTwoPaneMethodCardState` |
| `IptvSettingsTwoPane` (81–254) | `legacy_iptv_settings_two_pane/iptv_settings_two_pane_widget.dart` | unchanged |
| State lifecycle, `focusRail`, `focusAddPane`, `build` | same file, `IptvSettingsTwoPaneState` | unchanged |
| `_panePoolSize`, `_app`, `_dest`, `_railNodes`, `_paneNodes`, `_railScroll`, `_stats`, `_statsSignature` | `legacy_…/iptv_settings_two_pane_owners.dart` | `_panePoolSize` (static, private), `app`, `dest`, `railNodes`, `paneNodes`, `railScroll`, `stats`, `statsSignature` |
| `_initialDest`, `_railCount`, index getters, `_syncRailNodes`, `_syncStats`, `_paneNode`, `_focusRail`, `_selectedRailIndex`, `_destForRail`, `_enterPane`, `_returnToRail` | `legacy_…/iptv_settings_two_pane_navigation.dart` | `initialDest`, `_railCount`, `channelPreviewIndex`…`autoRefreshIndex`, `syncRailNodes`, `syncStats`, `paneNode`, `focusRailAt`, `selectedRailIndex`, `destForRail`, `enterPane`, `returnToRail` |
| `_buildRail`, `_listsSubtitle`, `_iconFor`, `_railSubtitle` | `legacy_…/iptv_settings_two_pane_rail.dart` | `buildRail`, `_listsSubtitle`, `iconFor`, `_railSubtitle` |
| `_buildPane`, `_buildSourcePane`, `_sourceMeta`, `_buildAddPane`, `_chevron` | `legacy_…/iptv_settings_two_pane_panes.dart` | `buildPane`, `_buildSourcePane`, `_sourceMeta`, `_buildAddPane`, `chevron` |
| `_buildListsPane`, `_buildStartupPane` | `legacy_…/iptv_settings_two_pane_list_panes.dart` | `buildListsPane`, `buildStartupPane` |
| `_buildContinueWatchingPane`, `_buildChannelPreviewPane`, `_buildAppearancePane`, `_buildPlayerGuidePane`, `_buildRecordingPane` | `legacy_…/iptv_settings_two_pane_preference_panes.dart` | public `build…Pane` names |

## State-context sites (seed)

- State `context` in moved code: 586 (`_buildRail`), 1120–1122 (`_buildAddPane`) → `_deps.context()`.
- Lexical: 574 (`build` VLB builder, stays in State), 591 (rail VLB builder parameter).
- `mounted`: 479 only (`focusAddPane`, stays in State). No `setState` or `this` in State bodies.

## Wiring checklist

(Execution fills one entry per moved leaf.)
