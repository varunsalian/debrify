# Detail showcase dependency and wiring inventory

Original application reference R: `1165b624` (format-only). Every row is a whole declaration including docs and, separately, every State. All 69 remain in the original at step 0. This inventory is fixed before production extraction.

## Wiring checklist

| Declaration | Destination | Cross-file private reads (alias) | State reads | Wiring |
| --- | --- | --- | --- | --- |
| `ShowcaseMetrics` | `showcase_metrics.dart` | none | none | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseMetricsScope` | `showcase_metrics.dart` | none | none | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `kShowcaseGutter` | `showcase_metrics.dart` | none | none | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `_ink` | `showcase_style.dart` | none | none | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `_slotFill` | `showcase_style.dart` | none | none | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `_plateFill` | `showcase_style.dart` | none | none | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `_ambientBed` | `showcase_grounds.dart` | none | none | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_t` | `showcase_style.dart` | none | none | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `_activate` | `showcase_style.dart` | none | none | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `_keepVisible` | `showcase_style.dart` | none | context | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `_Hover` | `showcase_style.dart` | none | none | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `_HoverState` | `showcase_style.dart` | none | widget, context | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseAmbient` | `showcase_grounds.dart` | none | context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseBackdropScrim` | `showcase_grounds.dart` | none | context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseStickyLogo` | `showcase_grounds.dart` | _t → st | context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseIdentity` | `showcase_identity.dart` | _t → st; _LogoOrTitle → SLogoOrTitle; _ExpandableSynopsis → SExpandableSynopsis; _Chip → SChip; _MetaLine → SMetaLine; _HonorsLine → SHonorsLine; _TechLine → STechLine; _Primary → SPrimary; _Circle → SCircle | context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_LogoOrTitle` | `showcase_identity_readouts.dart` | _ink → sInk | context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_ExpandableSynopsis` | `showcase_identity_readouts.dart` | none | none | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_ExpandableSynopsisState` | `showcase_identity_readouts.dart` | _t → st | widget, context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_Chip` | `showcase_identity_readouts.dart` | _t → st | context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_MetaLine` | `showcase_identity_readouts.dart` | _t → st | context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_TrackerMark` | `showcase_identity_readouts.dart` | _ink → sInk | context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_RatingBox` | `showcase_identity_readouts.dart` | _ink → sInk; _t → st | context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_hasHonors` | `showcase_identity.dart` | none | none | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_HonorsLine` | `showcase_identity_readouts.dart` | _ink → sInk; _t → st | context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_TechLine` | `showcase_identity_readouts.dart` | _t → st | context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_Primary` | `showcase_identity_actions.dart` | none | none | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_PrimaryState` | `showcase_identity_actions.dart` | _ink → sInk; _activate → sActivate | widget, context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_Circle` | `showcase_identity_actions.dart` | none | none | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `_CircleState` | `showcase_identity_actions.dart` | _ink → sInk; _activate → sActivate; _keepVisible → sKeepVisible | widget, context | Wired step 2; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseSeasons` | `showcase_seasons.dart` | none | context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_SeasonDropdown` | `showcase_seasons.dart` | none | none | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_SeasonDropdownState` | `showcase_seasons.dart` | _ink → sInk; _t → st; _activate → sActivate | widget, context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_SeasonPill` | `showcase_seasons.dart` | none | none | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_SeasonPillState` | `showcase_seasons.dart` | _ink → sInk; _t → st; _activate → sActivate; _keepVisible → sKeepVisible | widget, context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseEpisodeCell` | `showcase_episodes.dart` | _ink → sInk; _slotFill → sSlotFill; _t → st | context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseEpisodeCardCompact` | `showcase_episodes.dart` | _ink → sInk; _slotFill → sSlotFill; _t → st | context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_KebabButton` | `showcase_episodes.dart` | none | context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_Badge` | `showcase_episodes.dart` | _t → st | context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseCast` | `showcase_cast.dart` | _Band → SBand | context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_CastTile` | `showcase_cast.dart` | none | none | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_CastTileState` | `showcase_cast.dart` | _t → st; _activate → sActivate; _keepVisible → sKeepVisible; _Hover → SHover | widget, context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseSources` | `showcase_sources.dart` | _Band → SBand | context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_SourceCard` | `showcase_sources.dart` | none | none | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_SourceCardState` | `showcase_sources.dart` | _ink → sInk; _t → st; _activate → sActivate; _keepVisible → sKeepVisible; _Hover → SHover | widget, context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseRecs` | `showcase_recs.dart` | _Band → SBand | context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_Poster` | `showcase_recs.dart` | none | none | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_PosterState` | `showcase_recs.dart` | _slotFill → sSlotFill; _activate → sActivate; _keepVisible → sKeepVisible; _Hover → SHover | widget, context | Wired step 3; production via unchanged facade, owner-local spelling, same callback objects |
| `_plainOf` | `showcase_guide.dart` | none | none | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_spoilersOf` | `showcase_guide.dart` | none | none | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_severityLevel` | `showcase_guide.dart` | none | none | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_SeverityMark` | `showcase_guide.dart` | _ink → sInk; _t → st | context | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseGuide` | `showcase_guide.dart` | none | none | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_ShowcaseGuideState` | `showcase_guide.dart` | _ink → sInk; _t → st; _activate → sActivate; _Band → SBand | widget, context | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_GuideCard` | `showcase_guide.dart` | none | none | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_GuideCardState` | `showcase_guide.dart` | _ink → sInk; _t → st; _activate → sActivate; _keepVisible → sKeepVisible; _Hover → SHover | widget, context | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseUniverse` | `showcase_universe.dart` | _Band → SBand | context | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_UniverseCard` | `showcase_universe.dart` | none | none | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_UniverseCardState` | `showcase_universe.dart` | _slotFill → sSlotFill; _t → st; _activate → sActivate; _keepVisible → sKeepVisible; _Hover → SHover | widget, context | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseDidYouKnow` | `showcase_did_you_know.dart` | _Band → SBand | context | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_DykCard` | `showcase_did_you_know.dart` | none | none | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_DykCardState` | `showcase_did_you_know.dart` | _ink → sInk; _t → st; _keepVisible → sKeepVisible; _Hover → SHover | widget, context | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_DykMoreCard` | `showcase_did_you_know.dart` | none | none | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_DykMoreCardState` | `showcase_did_you_know.dart` | _ink → sInk; _t → st; _keepVisible → sKeepVisible; _Hover → SHover | widget, context | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_Band` | `showcase_style.dart` | none | context | Wired step 1; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseBandNote` | `showcase_notes.dart` | _t → st | context | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_RetryChip` | `showcase_notes.dart` | none | none | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `_RetryChipState` | `showcase_notes.dart` | _ink → sInk; _activate → sActivate | widget, context | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |
| `ShowcaseDetails` | `showcase_notes.dart` | _t → st | context | Wired step 4; production via unchanged facade, owner-local spelling, same callback objects |

## Frozen aliases

| Private | Alias | Owner | Pin |
| --- | --- | --- | --- |
| `_ink` | `sInk` | `showcase_style.dart` | `const sInk = _ink;` |
| `_t` | `st` | `showcase_style.dart` | `const st = _t;` |
| `_activate` | `sActivate` | `showcase_style.dart` | `const sActivate = _activate;` |
| `_keepVisible` | `sKeepVisible` | `showcase_style.dart` | `const sKeepVisible = _keepVisible;` |
| `_slotFill` | `sSlotFill` | `showcase_style.dart` | `const sSlotFill = _slotFill;` |
| `_Hover` | `SHover` | `showcase_style.dart` | `typedef SHover = _Hover;` + `showcaseHoverConstructor = _Hover.new` |
| `_Band` | `SBand` | `showcase_style.dart` | `typedef SBand = _Band;` + `showcaseBandConstructor = _Band.new` |
| `_LogoOrTitle` | `SLogoOrTitle` | `showcase_identity_readouts.dart` | `typedef SLogoOrTitle = _LogoOrTitle;` + `showcaseLogoOrTitleConstructor = _LogoOrTitle.new` |
| `_ExpandableSynopsis` | `SExpandableSynopsis` | `showcase_identity_readouts.dart` | `typedef SExpandableSynopsis = _ExpandableSynopsis;` + `showcaseExpandableSynopsisConstructor = _ExpandableSynopsis.new` |
| `_Chip` | `SChip` | `showcase_identity_readouts.dart` | `typedef SChip = _Chip;` + `showcaseChipConstructor = _Chip.new` |
| `_MetaLine` | `SMetaLine` | `showcase_identity_readouts.dart` | `typedef SMetaLine = _MetaLine;` + `showcaseMetaLineConstructor = _MetaLine.new` |
| `_HonorsLine` | `SHonorsLine` | `showcase_identity_readouts.dart` | `typedef SHonorsLine = _HonorsLine;` + `showcaseHonorsLineConstructor = _HonorsLine.new` |
| `_TechLine` | `STechLine` | `showcase_identity_readouts.dart` | `typedef STechLine = _TechLine;` + `showcaseTechLineConstructor = _TechLine.new` |
| `_Primary` | `SPrimary` | `showcase_identity_actions.dart` | `typedef SPrimary = _Primary;` + `showcasePrimaryConstructor = _Primary.new` |
| `_Circle` | `SCircle` | `showcase_identity_actions.dart` | `typedef SCircle = _Circle;` + `showcaseCircleConstructor = _Circle.new`; `showcaseCircleMarkConstructor = _Circle.mark` |

Names preserve original identifier length; probe formatting adds no body comma or brace. Alias config entries are staged only when the owning production file exists. Runtime classes and const constructors retain private names. Guide is one cohesive 474-line probe file; fallback not used.

## Type/cache imports, exact show lists

- `showcase_grounds.dart`: `package:debrify/services/debrify_image_cache.dart` show `DebrifyImageCache`. No service method calls; cache manager only.
- `showcase_identity_readouts.dart`: `package:debrify/services/debrify_image_cache.dart` show `DebrifyImageCache`. No service method calls; cache manager only.
- `showcase_episodes.dart`: `package:debrify/services/debrify_image_cache.dart` show `DebrifyImageCache`. No service method calls; cache manager only.
- `showcase_episodes.dart`: `package:debrify/services/trakt/trakt_episode_model.dart` show `TraktEpisode`. No service method calls; cache manager only.
- `showcase_cast.dart`: `package:debrify/services/debrify_image_cache.dart` show `DebrifyImageCache`. No service method calls; cache manager only.
- `showcase_cast.dart`: `package:debrify/services/imdb_enrichment_service.dart` show `CastMember`. No service method calls; cache manager only.
- `showcase_sources.dart`: `package:debrify/services/series_source_service.dart` show `SeriesSource`. No service method calls; cache manager only.
- `showcase_recs.dart`: `package:debrify/services/debrify_image_cache.dart` show `DebrifyImageCache`. No service method calls; cache manager only.
- `showcase_guide.dart`: `package:debrify/services/imdb_parents_guide_service.dart` show `ParentsGuideResult, ParentsGuideCategory, ParentsGuideItem`. No service method calls; cache manager only.
- `showcase_universe.dart`: `package:debrify/services/debrify_image_cache.dart` show `DebrifyImageCache`. No service method calls; cache manager only.
- `showcase_universe.dart`: `package:debrify/services/imdb_enrichment_service.dart` show `UniverseTitle`. No service method calls; cache manager only.
- `showcase_did_you_know.dart`: `package:debrify/services/imdb_enrichment_service.dart` show `DidYouKnowEntry`. No service method calls; cache manager only.

## Comment fragments and local ownership

- `// ── grounds ────────────────────────────────────────────────────────────────` → `showcase_grounds.dart` before `ShowcaseAmbient`; byte-identical.
- `// ── identity ───────────────────────────────────────────────────────────────` → `showcase_identity.dart` before `ShowcaseIdentity`; byte-identical.
- `// ── seasons ────────────────────────────────────────────────────────────────` → `showcase_seasons.dart` before `ShowcaseSeasons`; byte-identical.
- `// ── episodes ───────────────────────────────────────────────────────────────` → `showcase_episodes.dart` before `ShowcaseEpisodeCell`; byte-identical.
- `// ── cast ───────────────────────────────────────────────────────────────────` → `showcase_cast.dart` before `ShowcaseCast`; byte-identical.
- `// ── sources ────────────────────────────────────────────────────────────────` → `showcase_sources.dart` before `ShowcaseSources`; byte-identical.
- `// ── more like this ─────────────────────────────────────────────────────────` → `showcase_recs.dart` before `ShowcaseRecs`; byte-identical.
- `// ── parents guide ──────────────────────────────────────────────────────────` → `showcase_guide.dart` before `_plainOf`; byte-identical.
- `// ── universe ───────────────────────────────────────────────────────────────` → `showcase_universe.dart` before `ShowcaseUniverse`; byte-identical.
- `// ── did you know ───────────────────────────────────────────────────────────` → `showcase_did_you_know.dart` before `ShowcaseDidYouKnow`; byte-identical.
- `// ── shared band chrome ─────────────────────────────────────────────────────` → `showcase_style.dart` before `_Band`; byte-identical.

All declaration docs and body comments travel with their declaration; immutable cross-file mentions retain `_t`, `_ink`, `_keepVisible`, `_SeverityMark`, `_Poster`, `EpisodesPanel._enrichEpisodeRatings` and `DetailShowcase`. `_ambientBed` stays private with grounds, `_hasHonors` with identity; card implementations and paired States stay band-local. Three lifecycle methods remain verbatim inside their whole States. No owned resources, State `mounted` read, data operation or callback rebinding is introduced.

## Reviewed production callers

- `detail_layout_showcase.dart`: all public parts through unchanged facade; supplies borrowed nodes, model and live callbacks.
- `showcase_availability.dart`: `ShowcaseMetrics.of` through unchanged facade.
- Four direct test importers and merged detail through `DetailShowcase` remain unchanged.
- Per-entry completion verification: manifest comparison, owner-aware alias checks, strict identity comparison, focused original characterization, shape total 18, theme measurement, unchanged imports at callers. Actual per-entry completion remains pending each creation step.
