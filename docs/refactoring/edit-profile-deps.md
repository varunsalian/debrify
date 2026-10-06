# Edit profile dependency and wiring inventory

Execution base R: `f9ffe16d5e7ee9a94402950d7debdb359d1fc8f8`. Application source: `lib/screens/profiles/edit_profile_screen.dart`; 2764 physical lines. 90 manifest leaves, including 81 main-State members (26 fields, two lifecycle methods). This report was generated from the raw analyzer AST, then reviewed against the original. No production moves in step 0.

Every field read/write and live State/widget occurrence below retains its original evaluation site. Lexical `context` parameters/builders and role/resources/engines/features/section locals retain their bindings. Unbound State references alone receive owner/deps qualifiers. Public declarations and comments retain their bytes. `_authorization` remains the State lazy `late` field; deps forwarding is S evidence.

Wiring checklist for every row: construct inert owners/sections once; preserve initializer and lifecycle order; qualify only unbound State members; keep lexical locals/parameters; read widget fields through live closures at the listed sites; preserve callback identity and exact receiver; preserve comments; run checker/reader and relevant R/O cases. Actual destination composition review remains step 0b and creation-step work.

## `_TvProfileSection`

Destination: `lib/features/edit_profile/models/edit_profile_tv_section.dart` `<top-level>._TvProfileSection`; step 1. Original lines 33–33.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `EditProfileScreen`

Destination: `lib/screens/profiles/edit_profile_screen.dart` `<top-level>.EditProfileScreen`; step 0. Original lines 35–88.


Lexical hazards:

- `selected` line 81: lexical, read, binding `decl:member/method1#selected#0`, scope `member/method1/block0/if0`.
- `role` line 83: lexical, read, binding `decl:member/method1#role#0`, scope `member/method1/block0`.

Comments: 16 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EnsureVisibleOnFocus`

Destination: `lib/features/edit_profile/presentation/edit_profile_tv_surfaces.dart` `<top-level>._EnsureVisibleOnFocus`; step 1. Original lines 90–110.


Live State/widget/context sites:

- `context` line 102: lexical, read, binding `decl:member/method1#context#0`, scope `member/method1/closure0/block0`.

Lexical hazards:

- `context` line 102: lexical, read, binding `decl:member/method1#context#0`, scope `member/method1/closure0/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_TvReadOnlyScrollAnchor`

Destination: `lib/features/edit_profile/presentation/edit_profile_tv_surfaces.dart` `<top-level>._TvReadOnlyScrollAnchor`; step 1. Original lines 112–123.


Comments: 3 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_TvReadOnlyScrollAnchorState`

Destination: `lib/features/edit_profile/presentation/edit_profile_tv_surfaces.dart` `<top-level>._TvReadOnlyScrollAnchorState`; step 1. Original lines 125–162.


Live State/widget/context sites:

- `context` line 130: lexical, read, binding `decl:member/method0#context#0`, scope `member/method0/block0`.
- `setState` line 133: lexical, invocation, binding `unbound`, scope `member/method0/block0/closure0/block0/if0`.
- `context` line 136: lexical, read, binding `decl:member/method0#context#0`, scope `member/method0/block0/closure0/block0/if1/block0`.
- `widget` line 158: lexical, read, binding `unbound`, scope `member/method0/block0`.

Lexical hazards:

- `context` line 130: lexical, read, binding `decl:member/method0#context#0`, scope `member/method0/block0`.
- `context` line 136: lexical, read, binding `decl:member/method0#context#0`, scope `member/method0/block0/closure0/block0/if1/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_TvActionSurface`

Destination: `lib/features/edit_profile/presentation/edit_profile_tv_surfaces.dart` `<top-level>._TvActionSurface`; step 1. Original lines 164–184.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_TvActionSurfaceState`

Destination: `lib/features/edit_profile/presentation/edit_profile_tv_surfaces.dart` `<top-level>._TvActionSurfaceState`; step 1. Original lines 186–258.


Live State/widget/context sites:

- `context` line 191: lexical, read, binding `decl:member/method0#context#0`, scope `member/method0/block0`.
- `widget` line 192: lexical, read, binding `unbound`, scope `member/method0/block0`.
- `widget` line 197: lexical, read, binding `unbound`, scope `member/method0/block0/closure0/block0`.
- `widget` line 200: lexical, read, binding `unbound`, scope `member/method0/block0/closure0/block0/if1/block0/if0`.
- `widget` line 212: lexical, read, binding `unbound`, scope `member/method0/block0`.
- `widget` line 231: lexical, read, binding `unbound`, scope `member/method0/block0`.
- `widget` line 232: lexical, read, binding `unbound`, scope `member/method0/block0`.
- `setState` line 234: lexical, invocation, binding `unbound`, scope `member/method0/block0/closure1/block0/if0`.
- `context` line 237: lexical, read, binding `decl:member/method0#context#0`, scope `member/method0/block0/closure1/block0/if1/block0`.
- `widget` line 244: lexical, read, binding `unbound`, scope `member/method0/block0`.
- `widget` line 250: lexical, read, binding `unbound`, scope `member/method0/block0`.

Lexical hazards:

- `context` line 191: lexical, read, binding `decl:member/method0#context#0`, scope `member/method0/block0`.
- `selected` line 192: selector, read, binding `None`, scope `member/method0/block0`.
- `selected` line 212: selector, read, binding `None`, scope `member/method0/block0`.
- `context` line 237: lexical, read, binding `decl:member/method0#context#0`, scope `member/method0/block0/closure1/block0/if1/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_TvAutoLockField`

Destination: `lib/features/edit_profile/presentation/edit_profile_tv_surfaces.dart` `<top-level>._TvAutoLockField`; step 1. Original lines 260–325.


Live State/widget/context sites:

- `context` line 279: lexical, read, binding `decl:member/method1#context#0`, scope `member/method1/closure0/block0`.
- `context` line 290: lexical, read, binding `decl:member/method1/closure0/block0/closure0#context#0`, scope `member/method1/closure0/block0/closure0/for0/closure0`.
- `context` line 296: lexical, read, binding `decl:member/method1#context#0`, scope `member/method1/closure0/block0/if0`.
- `mounted` line 296: selector, read, binding `None`, scope `member/method1/closure0/block0/if0`.
- `context` line 308: lexical, read, binding `decl:member/method1#context#0`, scope `member/method1`.
- `context` line 314: lexical, read, binding `decl:member/method1#context#0`, scope `member/method1`.

Lexical hazards:

- `context` line 279: lexical, read, binding `decl:member/method1#context#0`, scope `member/method1/closure0/block0`.
- `context` line 290: lexical, read, binding `decl:member/method1/closure0/block0/closure0#context#0`, scope `member/method1/closure0/block0/closure0/for0/closure0`.
- `selected` line 296: lexical, read, binding `decl:member/method1/closure0/block0#selected#0`, scope `member/method1/closure0/block0/if0`.
- `context` line 296: lexical, read, binding `decl:member/method1#context#0`, scope `member/method1/closure0/block0/if0`.
- `selected` line 296: lexical, read, binding `decl:member/method1/closure0/block0#selected#0`, scope `member/method1/closure0/block0/if0`.
- `context` line 308: lexical, read, binding `decl:member/method1#context#0`, scope `member/method1`.
- `context` line 314: lexical, read, binding `decl:member/method1#context#0`, scope `member/method1`.

Comments: 1 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_ProfileEditSnapshot`

Destination: `lib/features/edit_profile/models/edit_profile_snapshot.dart` `<top-level>._ProfileEditSnapshot`; step 1. Original lines 327–361.


Comments: 4 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._name`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.name`; step 2. Original lines 364–364.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._pin`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.pin`; step 2. Original lines 365–365.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._role`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.role`; step 2. Original lines 366–366.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._features`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.features`; step 2. Original lines 367–367.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._saving`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.saving`; step 2. Original lines 368–368.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._copyDefaults`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.copyDefaults`; step 2. Original lines 369–369.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._lockOnResume`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.lockOnResume`; step 2. Original lines 370–370.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._inactivityMinutes`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.inactivityMinutes`; step 2. Original lines 371–371.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._avatarKey`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.avatarKey`; step 2. Original lines 372–372.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._tvSection`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_focus_state.dart` `EditProfileTvFocusState.tvSection`; step 2. Original lines 373–373.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._tvTabFocusNodes`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_focus_state.dart` `EditProfileTvFocusState.tvTabFocusNodes`; step 2. Original lines 375–375.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._policyTouched`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.policyTouched`; step 2. Original lines 377–380.


Comments: 3 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._tvContentFocus`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_focus_state.dart` `EditProfileTvFocusState.tvContentFocus`; step 2. Original lines 382–386.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._tvBackFocus`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_focus_state.dart` `EditProfileTvFocusState.tvBackFocus`; step 2. Original lines 387–387.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._tvLastContentFocus`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_focus_state.dart` `EditProfileTvFocusState.tvLastContentFocus`; step 2. Original lines 388–388.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._tvFocusRequest`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_focus_state.dart` `EditProfileTvFocusState.tvFocusRequest`; step 2. Original lines 389–389.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._seedDownloads`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.seedDownloads`; step 2. Original lines 395–395.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._seedRemote`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.seedRemote`; step 2. Original lines 396–396.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._pendingAvatarBytes`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_form_state.dart` `EditProfileFormState.pendingAvatarBytes`; step 2. Original lines 398–401.


Comments: 3 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._resources`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_state.dart` `EditProfileAccessState.resources`; step 2. Original lines 403–403.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._engines`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_state.dart` `EditProfileAccessState.engines`; step 2. Original lines 404–404.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._selectedResources`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_state.dart` `EditProfileAccessState.selectedResources`; step 2. Original lines 405–405.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._selectedEngines`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_state.dart` `EditProfileAccessState.selectedEngines`; step 2. Original lines 406–406.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._resourcePermissions`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_state.dart` `EditProfileAccessState.resourcePermissions`; step 2. Original lines 407–408.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._setupLoadError`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_state.dart` `EditProfileAccessState.setupLoadError`; step 2. Original lines 409–409.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._authorization`

Destination: `lib/screens/profiles/edit_profile_screen.dart` `_EditProfileScreenState._authorization`; step 0. Original lines 410–410.


Live State/widget/context sites:

- `widget` line 410: lexical, read, binding `unbound`, scope `member`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState.initState`

Destination: `lib/screens/profiles/edit_profile_screen.dart` `_EditProfileScreenState.initState`; step 0. Original lines 412–438.

- `_avatarKey`: write line 434 [lexical; unbound; member/block0]
- `_features`: write line 427 [lexical; unbound; member/block0]; read line 430 [lexical; unbound; member/block0]; read line 431 [lexical; unbound; member/block0]
- `_inactivityMinutes`: write line 433 [lexical; unbound; member/block0]
- `_loadSetupOptions`: invocation line 437 [lexical; unbound; member/block0]
- `_lockOnResume`: write line 432 [lexical; unbound; member/block0]
- `_name`: write line 421 [lexical; unbound; member/block0]
- `_role`: write line 422 [lexical; unbound; member/block0]; read line 428 [lexical; unbound; member/block0]
- `_seedDownloads`: write line 430 [lexical; unbound; member/block0]
- `_seedRemote`: write line 431 [lexical; unbound; member/block0]
- `_tvTabFocusNodes`: write line 415 [lexical; unbound; member/block0]

Live State/widget/context sites:

- `widget` line 420: lexical, read, binding `unbound`, scope `member/block0`.

Lexical hazards:

- `section` line 417: lexical, read, binding `decl:member/block0/for0#section#0`, scope `member/block0/for0`.
- `role` line 422: selector, read, binding `None`, scope `member/block0`.
- `role` line 436: selector, read, binding `None`, scope `member/block0`.

Comments: 4 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._loadSetupOptions`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_setup_options.dart` `EditProfileSetupOptions.loadSetupOptions`; step 2. Original lines 440–495.

- `_authorization`: read line 442 [lexical; unbound; member/block0/block0]; read line 450 [lexical; unbound; member/block0/block0]; read line 469 [lexical; unbound; member/block0/block0]
- `_engines`: write line 473 [lexical; unbound; member/block0/block0/closure0/block0]
- `_resourcePermissions`: read line 477 [lexical; unbound; member/block0/block0/closure0/block0]
- `_resources`: write line 472 [lexical; unbound; member/block0/block0/closure0/block0]
- `_selectedEngines`: read line 480 [lexical; unbound; member/block0/block0/closure0/block0]
- `_selectedResources`: read line 474 [lexical; unbound; member/block0/block0/closure0/block0]
- `_setupLoadError`: write line 489 [lexical; unbound; member/block0/block0/closure0/block0]; write line 493 [lexical; unbound; member/block0/catch0/block0/closure0]
- `_validateManagingAdmin`: invocation line 469 [lexical; unbound; member/block0/block0]

Live State/widget/context sites:

- `widget` line 442: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 443: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 444: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 446: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 448: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 451: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 456: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 459: lexical, read, binding `unbound`, scope `member/block0/block0/if0/block0/for0/block0`.
- `mounted` line 470: lexical, read, binding `unbound`, scope `member/block0/block0/if1`.
- `setState` line 471: lexical, invocation, binding `unbound`, scope `member/block0/block0`.
- `widget` line 483: lexical, read, binding `unbound`, scope `member/block0/block0/closure0/block0`.
- `mounted` line 492: lexical, read, binding `unbound`, scope `member/block0/catch0/block0/if0`.
- `setState` line 493: lexical, invocation, binding `unbound`, scope `member/block0/catch0/block0`.

Lexical hazards:

- `resources` line 458: lexical, read, binding `decl:member/block0/block0#resources#0`, scope `member/block0/block0/if0/block0/for0`.
- `selectedResources` line 461: lexical, read, binding `decl:member/block0/block0#selectedResources#0`, scope `member/block0/block0/if0/block0/for0/block0/if0/block0`.
- `resourcePermissions` line 462: lexical, read, binding `decl:member/block0/block0#resourcePermissions#0`, scope `member/block0/block0/if0/block0/for0/block0/if0/block0`.
- `resources` line 472: lexical, read, binding `decl:member/block0/block0#resources#0`, scope `member/block0/block0/closure0/block0`.
- `engines` line 473: lexical, read, binding `decl:member/block0/block0#engines#0`, scope `member/block0/block0/closure0/block0`.
- `selectedResources` line 476: lexical, read, binding `decl:member/block0/block0#selectedResources#0`, scope `member/block0/block0/closure0/block0`.
- `resourcePermissions` line 479: lexical, read, binding `decl:member/block0/block0#resourcePermissions#0`, scope `member/block0/block0/closure0/block0`.
- `engines` line 484: lexical, read, binding `decl:member/block0/block0#engines#0`, scope `member/block0/block0/closure0/block0`.
- `engines` line 485: lexical, read, binding `decl:member/block0/block0#engines#0`, scope `member/block0/block0/closure0/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._loadResources`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_setup_options.dart` `EditProfileSetupOptions.loadResources`; step 2. Original lines 497–510.

- `_authorization`: read line 499 [lexical; unbound; member/block0/block0]
- `_resources`: write line 503 [lexical; unbound; member/block0/block0/closure0/block0]
- `_setupLoadError`: write line 504 [lexical; unbound; member/block0/block0/closure0/block0]; write line 508 [lexical; unbound; member/block0/catch0/block0/closure0]

Live State/widget/context sites:

- `widget` line 499: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 500: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `mounted` line 501: lexical, read, binding `unbound`, scope `member/block0/block0/if0`.
- `setState` line 502: lexical, invocation, binding `unbound`, scope `member/block0/block0`.
- `mounted` line 507: lexical, read, binding `unbound`, scope `member/block0/catch0/block0/if0`.
- `setState` line 508: lexical, invocation, binding `unbound`, scope `member/block0/catch0/block0`.

Lexical hazards:

- `resources` line 503: lexical, read, binding `decl:member/block0/block0#resources#0`, scope `member/block0/block0/closure0/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._transferOwnership`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_admin_actions.dart` `EditProfileAdminActions.transferOwnership`; step 3. Original lines 512–564.

- `_authorization`: read line 515 [lexical; unbound; member/block0]; write line 550 [lexical; unbound; member/block0/block0]
- `_loadResources`: invocation line 553 [lexical; unbound; member/block0/block0]
- `_refreshSameManagingAdmin`: invocation line 550 [lexical; unbound; member/block0/block0]
- `_validateManagingAdmin`: invocation line 516 [lexical; unbound; member/block0]; invocation line 541 [lexical; unbound; member/block0/block0]

Live State/widget/context sites:

- `widget` line 513: lexical, read, binding `unbound`, scope `member/block0`.
- `mounted` line 517: lexical, read, binding `unbound`, scope `member/block0/if1`.
- `context` line 519: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 529: lexical, read, binding `decl:member/block0/closure0#context#0`, scope `member/block0/closure0/closure0`.
- `context` line 533: lexical, read, binding `decl:member/block0/closure0#context#0`, scope `member/block0/closure0/closure1`.
- `widget` line 543: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `mounted` line 554: lexical, read, binding `unbound`, scope `member/block0/block0/if0`.
- `context` line 555: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `mounted` line 559: lexical, read, binding `unbound`, scope `member/block0/catch0/block0/if0`.
- `context` line 560: lexical, read, binding `unbound`, scope `member/block0/catch0/block0`.

Lexical hazards:

- `context` line 519: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 529: lexical, read, binding `decl:member/block0/closure0#context#0`, scope `member/block0/closure0/closure0`.
- `context` line 533: lexical, read, binding `decl:member/block0/closure0#context#0`, scope `member/block0/closure0/closure1`.
- `context` line 555: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `context` line 560: lexical, read, binding `unbound`, scope `member/block0/catch0/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState.dispose`

Destination: `lib/screens/profiles/edit_profile_screen.dart` `_EditProfileScreenState.dispose`; step 0. Original lines 566–578.

- `_name`: read line 573 [lexical; unbound; member/block0]
- `_pin`: read line 574 [lexical; unbound; member/block0]
- `_tvBackFocus`: read line 572 [lexical; unbound; member/block0]
- `_tvContentFocus`: read line 571 [lexical; unbound; member/block0]
- `_tvTabFocusNodes`: read line 568 [lexical; unbound; member/block0/for0]

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._setRole`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_selection.dart` `EditProfileSelection.setRole`; step 2. Original lines 580–599.

- `_features`: write line 589 [lexical; unbound; member/block0/closure0/block0]; read line 596 [lexical; unbound; member/block0/closure0/block0]; read line 597 [lexical; unbound; member/block0/closure0/block0]
- `_role`: write line 583 [lexical; unbound; member/block0/closure0/block0]
- `_saving`: read line 581 [lexical; unbound; member/block0/if0]
- `_seedDownloads`: write line 596 [lexical; unbound; member/block0/closure0/block0]
- `_seedRemote`: write line 597 [lexical; unbound; member/block0/closure0/block0]

Live State/widget/context sites:

- `setState` line 582: lexical, invocation, binding `unbound`, scope `member/block0`.
- `widget` line 588: lexical, read, binding `unbound`, scope `member/block0/closure0/block0`.

Lexical hazards:

- `role` line 583: lexical, read, binding `decl:member#role#0`, scope `member/block0/closure0/block0`.
- `role` line 590: selector, read, binding `None`, scope `member/block0/closure0/block0`.
- `role` line 590: lexical, read, binding `decl:member#role#0`, scope `member/block0/closure0/block0`.
- `role` line 592: lexical, read, binding `decl:member#role#0`, scope `member/block0/closure0/block0`.

Comments: 6 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._pickAvatarImage`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_avatar_picker.dart` `EditProfileAvatarPicker.pickAvatarImage`; step 3. Original lines 601–642.

- `_pendingAvatarBytes`: write line 623 [lexical; unbound; member/block0/block0/closure0]
- `_readPickedBytes`: invocation line 620 [lexical; unbound; member/block0/block0]
- `_saving`: read line 602 [lexical; unbound; member/block0/if0]; read line 622 [lexical; unbound; member/block0/block0/if2]

Live State/widget/context sites:

- `mounted` line 622: lexical, read, binding `unbound`, scope `member/block0/block0/if2`.
- `setState` line 623: lexical, invocation, binding `unbound`, scope `member/block0/block0`.
- `mounted` line 625: lexical, read, binding `unbound`, scope `member/block0/catch0/block0/if0`.
- `context` line 627: lexical, read, binding `unbound`, scope `member/block0/catch0/block0`.
- `mounted` line 630: lexical, read, binding `unbound`, scope `member/block0/catch1/block0/if0`.
- `context` line 631: lexical, read, binding `unbound`, scope `member/block0/catch1/block0`.
- `mounted` line 635: lexical, read, binding `unbound`, scope `member/block0/catch2/block0/if0`.
- `context` line 636: lexical, read, binding `unbound`, scope `member/block0/catch2/block0`.

Lexical hazards:

- `context` line 627: lexical, read, binding `unbound`, scope `member/block0/catch0/block0`.
- `context` line 631: lexical, read, binding `unbound`, scope `member/block0/catch1/block0`.
- `context` line 636: lexical, read, binding `unbound`, scope `member/block0/catch2/block0`.

Comments: 2 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._readPickedBytes`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_avatar_picker.dart` `EditProfileAvatarPicker._readPickedBytes`; step 3. Original lines 644–670.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._showRecoveryCode`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_save.dart` `EditProfileSave._showRecoveryCode`; step 3. Original lines 672–711.


Live State/widget/context sites:

- `context` line 676: lexical, read, binding `unbound`, scope `member/block0`.

Lexical hazards:

- `context` line 676: lexical, read, binding `unbound`, scope `member/block0`.
- `dialogContext` line 705: lexical, read, binding `decl:member/block0/closure0#dialogContext#0`, scope `member/block0/closure0/closure0`.

Comments: 2 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._save`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_save.dart` `EditProfileSave.save`; step 3. Original lines 713–982.

- `_applyEngineAssignments`: invocation line 848 [lexical; unbound; member/block0/block0/if1/block0/block0/closure0/block0]; invocation line 937 [lexical; unbound; member/block0/block0/if1/block1]
- `_applyResourceGrants`: invocation line 843 [lexical; unbound; member/block0/block0/if1/block0/block0/closure0/block0]; invocation line 932 [lexical; unbound; member/block0/block0/if1/block1]
- `_authorization`: read line 783 [lexical; unbound; member/block0/block0]; write line 943 [lexical; unbound; member/block0/block0]
- `_avatarKey`: read line 762 [lexical; unbound; member/block0]; write line 945 [lexical; unbound; member/block0/block0]
- `_copyDefaults`: read line 759 [lexical; unbound; member/block0]
- `_engines`: read line 715 [lexical; unbound; member/block0/if1]
- `_features`: read line 731 [lexical; unbound; member/block0]; read line 737 [lexical; unbound; member/block0]; read line 738 [lexical; unbound; member/block0]; write line 946 [lexical; unbound; member/block0/block0]; read line 947 [lexical; unbound; member/block0/block0]; read line 948 [lexical; unbound; member/block0/block0]
- `_inactivityMinutes`: read line 761 [lexical; unbound; member/block0]
- `_lockOnResume`: read line 760 [lexical; unbound; member/block0]
- `_name`: read line 714 [lexical; unbound; member/block0/if0]; read line 755 [lexical; unbound; member/block0]
- `_pendingAvatarBytes`: read line 763 [lexical; unbound; member/block0]; write line 950 [lexical; unbound; member/block0/block0]
- `_pin`: read line 723 [lexical; unbound; member/block0/if2]; read line 723 [lexical; unbound; member/block0/if2]; read line 756 [lexical; unbound; member/block0]; read line 951 [lexical; unbound; member/block0/block0]
- `_policyTouched`: read line 793 [lexical; unbound; member/block0/block0]; write line 949 [lexical; unbound; member/block0/block0]
- `_refreshSameManagingAdmin`: invocation line 840 [lexical; unbound; member/block0/block0/if1/block0/block0/closure0/block0]; invocation line 919 [lexical; unbound; member/block0/block0/if1/block1]; invocation line 928 [lexical; unbound; member/block0/block0/if1/block1/if0/block0]
- `_resourcePermissions`: read line 767 [lexical; unbound; member/block0/for1]
- `_resources`: read line 715 [lexical; unbound; member/block0/if1]; read-write line 764 [lexical; unbound; member/block0]
- `_restoreTvSaveFocus`: invocation line 968 [lexical; unbound; member/block0/catch0/block0]; invocation line 977 [lexical; unbound; member/block0/catch1/block0]
- `_role`: read line 752 [lexical; unbound; member/block0/for0/if0]; read line 757 [lexical; unbound; member/block0]
- `_saving`: read line 714 [lexical; unbound; member/block0/if0]; write line 772 [lexical; unbound; member/block0/closure0]; write line 967 [lexical; unbound; member/block0/catch0/block0/closure0]; write line 976 [lexical; unbound; member/block0/catch1/block0/closure0]
- `_seedDownloads`: read line 740 [lexical; unbound; member/block0]; write line 947 [lexical; unbound; member/block0/block0]
- `_seedRemote`: read line 744 [lexical; unbound; member/block0]; write line 948 [lexical; unbound; member/block0/block0]
- `_selectedEngines`: read line 770 [lexical; unbound; member/block0]
- `_selectedResources`: read line 765 [lexical; unbound; member/block0]
- `_setupLoadError`: read line 715 [lexical; unbound; member/block0/if1]; read line 718 [lexical; unbound; member/block0/if1/block0]
- `_showRecoveryCode`: invocation line 960 [lexical; unbound; member/block0/block0/if4/block0]
- `_validateManagingAdmin`: invocation line 784 [lexical; unbound; member/block0/block0]

Live State/widget/context sites:

- `context` line 716: lexical, read, binding `unbound`, scope `member/block0/if1/block0`.
- `context` line 724: lexical, read, binding `unbound`, scope `member/block0/if2/block0`.
- `setState` line 772: lexical, invocation, binding `unbound`, scope `member/block0`.
- `widget` line 788: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 794: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 794: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 796: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 799: lexical, read, binding `unbound`, scope `member/block0/block0/if1/block0`.
- `widget` line 822: lexical, read, binding `unbound`, scope `member/block0/block0/if1/block0/block0/closure0/block0/if1/block0`.
- `widget` line 828: lexical, read, binding `unbound`, scope `member/block0/block0/if1/block0/block0/closure0/block0`.
- `widget` line 872: lexical, read, binding `unbound`, scope `member/block0/block0/if1/block0/catch0/block0`.
- `widget` line 890: lexical, read, binding `unbound`, scope `member/block0/block0/if1/block1`.
- `widget` line 895: lexical, read, binding `unbound`, scope `member/block0/block0/if1/block1/closure0/block0`.
- `widget` line 910: lexical, read, binding `unbound`, scope `member/block0/block0/if1/block1/closure1/block0`.
- `widget` line 923: lexical, read, binding `unbound`, scope `member/block0/block0/if1/block1/if0/block0`.
- `mounted` line 944: lexical, read, binding `unbound`, scope `member/block0/block0/if2`.
- `widget` line 955: lexical, read, binding `unbound`, scope `member/block0/block0/if3`.
- `mounted` line 961: lexical, read, binding `unbound`, scope `member/block0/block0/if4/block0/if0`.
- `mounted` line 963: lexical, read, binding `unbound`, scope `member/block0/block0/if5`.
- `context` line 964: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `mounted` line 966: lexical, read, binding `unbound`, scope `member/block0/catch0/block0/if0`.
- `setState` line 967: lexical, invocation, binding `unbound`, scope `member/block0/catch0/block0`.
- `context` line 972: lexical, read, binding `unbound`, scope `member/block0/catch0/block0`.
- `mounted` line 975: lexical, read, binding `unbound`, scope `member/block0/catch1/block0/if0`.
- `setState` line 976: lexical, invocation, binding `unbound`, scope `member/block0/catch1/block0`.
- `context` line 978: lexical, read, binding `unbound`, scope `member/block0/catch1/block0`.

Lexical hazards:

- `context` line 716: lexical, read, binding `unbound`, scope `member/block0/if1/block0`.
- `context` line 724: lexical, read, binding `unbound`, scope `member/block0/if2/block0`.
- `role` line 786: selector, read, binding `None`, scope `member/block0/block0`.
- `features` line 787: selector, read, binding `None`, scope `member/block0/block0`.
- `role` line 794: selector, read, binding `None`, scope `member/block0/block0`.
- `role` line 794: selector, read, binding `None`, scope `member/block0/block0`.
- `role` line 803: selector, read, binding `None`, scope `member/block0/block0/if1/block0`.
- `role` line 899: selector, read, binding `None`, scope `member/block0/block0/if1/block1/closure0/block0`.
- `role` line 913: selector, read, binding `None`, scope `member/block0/block0/if1/block1/closure1/block0`.
- `role` line 913: selector, read, binding `None`, scope `member/block0/block0/if1/block1/closure1/block0`.
- `context` line 964: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `context` line 972: lexical, read, binding `unbound`, scope `member/block0/catch0/block0`.
- `context` line 978: lexical, read, binding `unbound`, scope `member/block0/catch1/block0`.

Comments: 22 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._restoreTvSaveFocus`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_navigation.dart` `EditProfileTvNavigation.restoreTvSaveFocus`; step 3. Original lines 984–993.

- `_saving`: read line 989 [lexical; unbound; member/block0/closure0/block0/if0]
- `_tvTabFocusNodes`: read line 990 [lexical; unbound; member/block0/closure0/block0/if0/block0]

Live State/widget/context sites:

- `mounted` line 989: lexical, read, binding `unbound`, scope `member/block0/closure0/block0/if0`.
- `context` line 989: lexical, read, binding `unbound`, scope `member/block0/closure0/block0/if0`.

Lexical hazards:

- `context` line 989: lexical, read, binding `unbound`, scope `member/block0/closure0/block0/if0`.

Comments: 2 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._applyResourceGrants`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_grants.dart` `EditProfileGrants.applyResourceGrants`; step 3. Original lines 995–1053.

- `_defaultResourcePermissions`: invocation line 1013 [lexical; unbound; member/block0/for0/block0]
- `_refreshSameManagingAdmin`: invocation line 1036 [lexical; unbound; member/block0/for0/block0/if0/block0]; invocation line 1047 [lexical; unbound; member/block0/for0/block0/if0/if0/block0]

Live State/widget/context sites:

- `widget` line 1002: lexical, read, binding `unbound`, scope `member/block0`.
- `widget` line 1006: lexical, read, binding `unbound`, scope `member/block0/for0/block0`.
- `widget` line 1021: lexical, read, binding `unbound`, scope `member/block0/for0/block0`.

Lexical hazards:

- `resources` line 1000: selector, read, binding `None`, scope `member/block0`.
- `resources` line 1005: lexical, read, binding `decl:member/block0#resources#0`, scope `member/block0/for0`.
- `selectedResources` line 1010: selector, read, binding `None`, scope `member/block0/for0/block0`.
- `resourcePermissions` line 1012: selector, read, binding `None`, scope `member/block0/for0/block0`.
- `role` line 1013: selector, read, binding `None`, scope `member/block0/for0/block0`.
- `features` line 1013: selector, read, binding `None`, scope `member/block0/for0/block0`.
- `selected` line 1026: lexical, read, binding `decl:member/block0/for0/block0#selected#0`, scope `member/block0/for0/block0/if0`.
- `selected` line 1039: lexical, read, binding `decl:member/block0/for0/block0#selected#0`, scope `member/block0/for0/block0/if0/if0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._applyEngineAssignments`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_grants.dart` `EditProfileGrants.applyEngineAssignments`; step 3. Original lines 1055–1063.


Live State/widget/context sites:

- `widget` line 1059: lexical, read, binding `unbound`, scope `member`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._defaultResourcePermissions`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_selection.dart` `EditProfileSelection.defaultResourcePermissions`; step 2. Original lines 1065–1076.

- `_features`: read line 1070 [lexical; unbound; member/if0]; read line 1071 [lexical; unbound; member/if0]; read line 1074 [lexical; unbound; member/if1]

Lexical hazards:

- `features` line 1070: lexical, read, binding `decl:member#features#0`, scope `member/if0`.
- `features` line 1071: lexical, read, binding `decl:member#features#0`, scope `member/if0`.
- `role` line 1073: lexical, read, binding `decl:member#role#0`, scope `member/if1`.
- `features` line 1074: lexical, read, binding `decl:member#features#0`, scope `member/if1`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._validateManagingAdmin`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_admin_guard.dart` `EditProfileAdminGuard.validateManagingAdmin`; step 2. Original lines 1078–1086.


Live State/widget/context sites:

- `context` line 1081: lexical, read, binding `decl:member#context#0`, scope `member/block0`.
- `widget` line 1081: lexical, read, binding `unbound`, scope `member/block0`.

Lexical hazards:

- `context` line 1081: lexical, read, binding `decl:member#context#0`, scope `member/block0`.
- `role` line 1082: selector, read, binding `None`, scope `member/block0/if0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._refreshSameManagingAdmin`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_admin_guard.dart` `EditProfileAdminGuard.refreshSameManagingAdmin`; step 2. Original lines 1088–1099.

- `_validateManagingAdmin`: invocation line 1097 [lexical; unbound; member/block0]

Live State/widget/context sites:

- `widget` line 1092: lexical, read, binding `unbound`, scope `member/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._selectResource`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_selection.dart` `EditProfileSelection.selectResource`; step 2. Original lines 1101–1120.

- `_defaultResourcePermissions`: invocation line 1118 [lexical; unbound; member/block0/closure0]
- `_resourcePermissions`: read line 1111 [lexical; unbound; member/block0/if0/block0/for0/block0/if0/block0]; read line 1116 [lexical; unbound; member/block0]
- `_resources`: read-write line 1107 [lexical; unbound; member/block0/if0/block0/for0]
- `_role`: read line 1118 [lexical; unbound; member/block0/closure0]
- `_selectedResources`: read line 1110 [lexical; unbound; member/block0/if0/block0/for0/block0/if0/block0]; read line 1115 [lexical; unbound; member/block0]

Comments: 3 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._deselectResource`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_selection.dart` `EditProfileSelection.deselectResource`; step 2. Original lines 1122–1124.

- `_selectedResources`: read line 1123 [lexical; unbound; member/block0]

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._editableIn`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_selection.dart` `EditProfileSelection.editableIn`; step 2. Original lines 1126–1129.


Live State/widget/context sites:

- `widget` line 1129: lexical, read, binding `unbound`, scope `member/closure0`.

Comments: 2 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._showDiagnostics`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_admin_actions.dart` `EditProfileAdminActions.showDiagnostics`; step 3. Original lines 1131–1157.


Live State/widget/context sites:

- `widget` line 1132: lexical, read, binding `unbound`, scope `member/block0`.
- `mounted` line 1133: lexical, read, binding `unbound`, scope `member/block0/if0`.
- `context` line 1135: lexical, read, binding `unbound`, scope `member/block0`.
- `mounted` line 1146: selector, read, binding `None`, scope `member/block0/closure0/closure0/block0/if0`.

Lexical hazards:

- `context` line 1135: lexical, read, binding `unbound`, scope `member/block0`.
- `dialogContext` line 1146: lexical, read, binding `decl:member/block0/closure0#dialogContext#0`, scope `member/block0/closure0/closure0/block0/if0`.
- `dialogContext` line 1146: lexical, read, binding `decl:member/block0/closure0#dialogContext#0`, scope `member/block0/closure0/closure0/block0/if0`.
- `dialogContext` line 1151: lexical, read, binding `decl:member/block0/closure0#dialogContext#0`, scope `member/block0/closure0/closure1`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._sectionLabel`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_phone_form.dart` `EditProfilePhoneForm._sectionLabel`; step 5. Original lines 1161–1170.


Live State/widget/context sites:

- `context` line 1165: lexical, read, binding `unbound`, scope `member`.
- `context` line 1167: lexical, read, binding `unbound`, scope `member`.

Lexical hazards:

- `context` line 1165: lexical, read, binding `unbound`, scope `member`.
- `context` line 1167: lexical, read, binding `unbound`, scope `member`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState.build`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_phone_form.dart` `EditProfilePhoneForm.build`; step 5. Original lines 1172–1330.

- `_buildAvatarSection`: invocation line 1205 [lexical; unbound; member/block0]
- `_buildConnectionGroups`: invocation line 1310 [lexical; unbound; member/block0/if5/if0]
- `_buildEngineGroup`: invocation line 1309 [lexical; unbound; member/block0/if5/if0]
- `_buildRoleCards`: invocation line 1225 [lexical; unbound; member/block0]
- `_buildTvEditor`: invocation line 1174 [lexical; unbound; member/block0/if0]
- `_copyDefaults`: read line 1217 [lexical; unbound; member/block0/if2]; write line 1222 [lexical; unbound; member/block0/if2/closure0/closure0]
- `_engines`: read line 1306 [lexical; unbound; member/block0/if5/if0]
- `_featureLabel`: invocation line 1235 [lexical; unbound; member/block0/if3/for0]
- `_features`: read line 1231 [lexical; unbound; member/block0/if3/for0]; read line 1233 [lexical; unbound; member/block0/if3/for0]; read line 1239 [lexical; unbound; member/block0/if3/for0/closure0/block0/closure0/block0/if0/block0]; read line 1241 [lexical; unbound; member/block0/if3/for0/closure0/block0/closure0/block0/if0/block1]
- `_inactivityMinutes`: read line 1278 [lexical; unbound; member/block0]; write line 1294 [lexical; unbound; member/block0/closure2/closure0]
- `_loadSetupOptions`: read line 1302 [lexical; unbound; member/block0/if5]
- `_lockOnResume`: read line 1273 [lexical; unbound; member/block0]; write line 1275 [lexical; unbound; member/block0/closure1/closure0]
- `_name`: read line 1208 [lexical; unbound; member/block0]
- `_pin`: read line 1249 [lexical; unbound; member/block0]
- `_removePinAsAdmin`: read line 1267 [lexical; unbound; member/block0/if4]
- `_role`: read line 1179 [lexical; unbound; member/block0/closure0]; read line 1234 [lexical; unbound; member/block0/if3/for0]
- `_save`: read line 1190 [lexical; unbound; member/block0]
- `_saving`: read line 1182 [lexical; unbound; member/block0]; read line 1190 [lexical; unbound; member/block0]; read line 1196 [lexical; unbound; member/block0]; read line 1197 [lexical; unbound; member/block0]; read line 1199 [lexical; unbound; member/block0]; read line 1203 [lexical; unbound; member/block0/if1]; read line 1267 [lexical; unbound; member/block0/if4]
- `_sectionLabel`: invocation line 1204 [lexical; unbound; member/block0]; invocation line 1206 [lexical; unbound; member/block0]; invocation line 1224 [lexical; unbound; member/block0]; invocation line 1247 [lexical; unbound; member/block0]; invocation line 1296 [lexical; unbound; member/block0]; invocation line 1313 [lexical; unbound; member/block0/if6]
- `_setupLoadError`: read line 1297 [lexical; unbound; member/block0/if5]; read-write line 1300 [lexical; unbound; member/block0/if5]
- `_showDiagnostics`: read line 1320 [lexical; unbound; member/block0/if6]

Live State/widget/context sites:

- `context` line 1174: lexical, read, binding `decl:member#context#0`, scope `member/block0/if0`.
- `widget` line 1186: lexical, read, binding `unbound`, scope `member/block0`.
- `widget` line 1215: lexical, read, binding `unbound`, scope `member/block0/if2`.
- `setState` line 1222: lexical, invocation, binding `unbound`, scope `member/block0/if2/closure0`.
- `setState` line 1237: lexical, invocation, binding `unbound`, scope `member/block0/if3/for0/closure0/block0`.
- `widget` line 1257: lexical, read, binding `unbound`, scope `member/block0`.
- `widget` line 1262: lexical, read, binding `unbound`, scope `member/block0/if4`.
- `widget` line 1263: lexical, read, binding `unbound`, scope `member/block0/if4`.
- `setState` line 1275: lexical, invocation, binding `unbound`, scope `member/block0/closure1`.
- `setState` line 1294: lexical, invocation, binding `unbound`, scope `member/block0/closure2`.
- `widget` line 1312: lexical, read, binding `unbound`, scope `member/block0/if6`.

Lexical hazards:

- `context` line 1174: lexical, read, binding `decl:member#context#0`, scope `member/block0/if0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildTvEditor`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_editor.dart` `EditProfileTvEditor.buildTvEditor`; step 4. Original lines 1332–1440.

- `_buildTvAccessSection`: invocation line 1421 [lexical; unbound; member/block0/pattern3]
- `_buildTvDataSection`: invocation line 1423 [lexical; unbound; member/block0/pattern4]
- `_buildTvLockSection`: invocation line 1419 [lexical; unbound; member/block0/pattern2]
- `_buildTvPagesSection`: invocation line 1417 [lexical; unbound; member/block0/pattern1]
- `_buildTvProfileSection`: invocation line 1415 [lexical; unbound; member/block0/pattern0]
- `_buildTvSectionRail`: invocation line 1386 [lexical; unbound; member/block0]
- `_moveTvContent`: invocation line 1405 [lexical; unbound; member/block0/closure2/block0]
- `_saving`: read line 1335 [lexical; unbound; member/block0]; read line 1356 [lexical; unbound; member/block0]; read line 1373 [lexical; unbound; member/block0]; read line 1374 [lexical; unbound; member/block0]; read line 1376 [lexical; unbound; member/block0]; read line 1381 [lexical; unbound; member/block0/if0]
- `_tvBackFocus`: read line 1352 [lexical; unbound; member/block0]
- `_tvContentFocus`: read line 1390 [lexical; unbound; member/block0]
- `_tvDirection`: invocation line 1343 [lexical; unbound; member/block0/closure0/block0]; invocation line 1401 [lexical; unbound; member/block0/closure2/block0]
- `_tvSection`: read line 1347 [lexical; unbound; member/block0/closure0/block0/if1/block0]; read line 1412 [lexical; unbound; member/block0]; read line 1413 [lexical; unbound; member/block0]
- `_tvTabFocusNodes`: read line 1347 [lexical; unbound; member/block0/closure0/block0/if1/block0]

Live State/widget/context sites:

- `context` line 1333: lexical, read, binding `decl:member#context#0`, scope `member/block0`.
- `context` line 1339: lexical, read, binding `decl:member#context#0`, scope `member/block0`.
- `context` line 1354: lexical, read, binding `decl:member#context#0`, scope `member/block0`.
- `context` line 1358: lexical, read, binding `decl:member#context#0`, scope `member/block0/closure1`.
- `widget` line 1364: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 1366: lexical, read, binding `decl:member#context#0`, scope `member/block0`.
- `context` line 1394: selector, read, binding `None`, scope `member/block0/closure2/block0/if0`.

Lexical hazards:

- `context` line 1333: lexical, read, binding `decl:member#context#0`, scope `member/block0`.
- `context` line 1339: lexical, read, binding `decl:member#context#0`, scope `member/block0`.
- `context` line 1354: lexical, read, binding `decl:member#context#0`, scope `member/block0`.
- `context` line 1358: lexical, read, binding `decl:member#context#0`, scope `member/block0/closure1`.
- `context` line 1366: lexical, read, binding `decl:member#context#0`, scope `member/block0`.
- `context` line 1394: selector, read, binding `None`, scope `member/block0/closure2/block0/if0`.

Comments: 4 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildTvSectionRail`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_editor.dart` `EditProfileTvEditor._buildTvSectionRail`; step 4. Original lines 1442–1532.

- `_focusTvContent`: invocation line 1509 [lexical; unbound; member/block0/closure0/for0/closure0/block0]
- `_handleTvRailKey`: invocation line 1464 [lexical; unbound; member/block0/function0/closure0/closure0]
- `_save`: read line 1519 [lexical; unbound; member/block0/closure0]
- `_saving`: read line 1519 [lexical; unbound; member/block0/closure0]; read line 1522 [lexical; unbound; member/block0/closure0]
- `_selectTvSection`: invocation line 1507 [lexical; unbound; member/block0/closure0/for0/closure0/block0]
- `_tvSection`: read line 1504 [lexical; unbound; member/block0/closure0/for0]
- `_tvTabFocusNodes`: read line 1463 [lexical; unbound; member/block0/function0/closure0]; read line 1508 [lexical; unbound; member/block0/closure0/for0/closure0/block0]

Live State/widget/context sites:

- `context` line 1477: lexical, read, binding `unbound`, scope `member/block0/function1/closure0`.

Lexical hazards:

- `selected` line 1461: lexical, read, binding `decl:member/block0/function0/closure0#selected#0`, scope `member/block0/function0/closure0`.
- `context` line 1477: lexical, read, binding `unbound`, scope `member/block0/function1/closure0`.

Comments: 1 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._tvDirection`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_navigation.dart` `EditProfileTvNavigation.tvDirection`; step 3. Original lines 1534–1543.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._handleTvRailKey`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_navigation.dart` `EditProfileTvNavigation.handleTvRailKey`; step 3. Original lines 1545–1573.

- `_focusTvContent`: invocation line 1556 [lexical; unbound; member/block0/pattern1]
- `_selectTvSection`: invocation line 1554 [lexical; unbound; member/block0/pattern1/if0/block0]; invocation line 1567 [lexical; unbound; member/block0/pattern3/if0/block1/if0/block0]
- `_tvBackFocus`: read line 1563 [lexical; unbound; member/block0/pattern3/if0/block0]
- `_tvDirection`: invocation line 1546 [lexical; unbound; member/block0]
- `_tvFocusRequest`: read-write line 1550 [lexical; unbound; member/block0/pattern0]; read-write line 1559 [lexical; unbound; member/block0/pattern3]
- `_tvTabFocusNodes`: read line 1561 [lexical; unbound; member/block0/pattern3]; read line 1569 [lexical; unbound; member/block0/pattern3/if0/block1]

Live State/widget/context sites:

- `context` line 1562: lexical, read, binding `unbound`, scope `member/block0/pattern3/if0`.

Lexical hazards:

- `context` line 1562: lexical, read, binding `unbound`, scope `member/block0/pattern3/if0`.

Comments: 1 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._selectTvSection`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_navigation.dart` `EditProfileTvNavigation.selectTvSection`; step 3. Original lines 1575–1580.

- `_tvFocusRequest`: read-write line 1578 [lexical; unbound; member/block0]
- `_tvLastContentFocus`: write line 1577 [lexical; unbound; member/block0]
- `_tvSection`: read line 1576 [lexical; unbound; member/block0/if0]; write line 1579 [lexical; unbound; member/block0/closure0]

Live State/widget/context sites:

- `setState` line 1579: lexical, invocation, binding `unbound`, scope `member/block0`.

Lexical hazards:

- `section` line 1576: lexical, read, binding `decl:member#section#0`, scope `member/block0/if0`.
- `section` line 1579: lexical, read, binding `decl:member#section#0`, scope `member/block0/closure0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._tvContentStops`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_navigation.dart` `EditProfileTvNavigation._tvContentStops`; step 3. Original lines 1582–1584.

- `_tvContentFocus`: read line 1582 [lexical; unbound; member]

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._requestTvContentFocus`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_navigation.dart` `EditProfileTvNavigation._requestTvContentFocus`; step 3. Original lines 1586–1594.

- `_tvLastContentFocus`: write line 1587 [lexical; unbound; member/block0]

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._focusTvContent`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_navigation.dart` `EditProfileTvNavigation.focusTvContent`; step 3. Original lines 1596–1623.

- `_requestTvContentFocus`: invocation line 1613 [lexical; unbound; member/block0/closure0/block0/if2/block0]; invocation line 1620 [lexical; unbound; member/block0/closure0/block0]
- `_saving`: read line 1597 [lexical; unbound; member/block0/if0]; read line 1604 [lexical; unbound; member/block0/closure0/block0/if0]
- `_tvContentStops`: read line 1610 [lexical; unbound; member/block0/closure0/block0]
- `_tvFocusRequest`: read-write line 1599 [lexical; unbound; member/block0]; read line 1606 [lexical; unbound; member/block0/closure0/block0/if0]
- `_tvLastContentFocus`: read line 1612 [lexical; unbound; member/block0/closure0/block0/if2]; read-write line 1613 [lexical; unbound; member/block0/closure0/block0/if2/block0]
- `_tvSection`: read line 1598 [lexical; unbound; member/block0]; read line 1605 [lexical; unbound; member/block0/closure0/block0/if0]

Live State/widget/context sites:

- `mounted` line 1603: lexical, read, binding `unbound`, scope `member/block0/closure0/block0/if0`.
- `context` line 1607: lexical, read, binding `unbound`, scope `member/block0/closure0/block0/if0`.

Lexical hazards:

- `section` line 1605: lexical, read, binding `decl:member/block0#section#0`, scope `member/block0/closure0/block0/if0`.
- `context` line 1607: lexical, read, binding `unbound`, scope `member/block0/closure0/block0/if0`.

Comments: 3 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._returnToTvRail`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_navigation.dart` `EditProfileTvNavigation.returnToTvRail`; step 3. Original lines 1625–1630.

- `_tvContentStops`: read line 1628 [lexical; unbound; member/block0/if0]
- `_tvFocusRequest`: read-write line 1626 [lexical; unbound; member/block0]
- `_tvLastContentFocus`: write line 1628 [lexical; unbound; member/block0/if0]
- `_tvSection`: read line 1629 [lexical; unbound; member/block0]
- `_tvTabFocusNodes`: read line 1629 [lexical; unbound; member/block0]

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._moveTvContent`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_navigation.dart` `EditProfileTvNavigation.moveTvContent`; step 3. Original lines 1632–1670.

- `_requestTvContentFocus`: invocation line 1665 [lexical; unbound; member/block0/if1/block0]
- `_returnToTvRail`: invocation line 1667 [lexical; unbound; member/block0/if1/if0/block0]
- `_tvContentFocus`: read line 1634 [lexical; unbound; member/block0/if0]
- `_tvContentStops`: read line 1642 [lexical; unbound; member/block0]

Comments: 3 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildTvPagesSection`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_panes.dart` `EditProfileTvPanes.buildTvPagesSection`; step 4. Original lines 1672–1811.

- `_features`: read line 1674 [lexical; unbound; member/block0/function0/closure0]; read line 1679 [lexical; unbound; member/block0/function1/closure0/block0/closure0/block0/if0]; read line 1679 [lexical; unbound; member/block0/function1/closure0/block0/closure0/block0/if0]
- `_policyTouched`: write line 1678 [lexical; unbound; member/block0/function1/closure0/block0/closure0/block0]
- `_role`: read line 1674 [lexical; unbound; member/block0/function0/closure0]
- `_saving`: read line 1676 [lexical; unbound; member/block0/function1/closure0/block0/if0]
- `_tvPanel`: invocation line 1743 [lexical; unbound; member/block0]

Live State/widget/context sites:

- `setState` line 1677: lexical, invocation, binding `unbound`, scope `member/block0/function1/closure0/block0`.
- `context` line 1687: lexical, read, binding `unbound`, scope `member/block0/function2/closure0`.
- `context` line 1689: lexical, read, binding `unbound`, scope `member/block0/function2/closure0`.
- `context` line 1710: lexical, read, binding `unbound`, scope `member/block0/function3/closure0/block0`.
- `context` line 1716: lexical, read, binding `unbound`, scope `member/block0/function3/closure0/block0`.
- `context` line 1728: lexical, read, binding `unbound`, scope `member/block0/function3/closure0/block0`.
- `context` line 1730: lexical, read, binding `unbound`, scope `member/block0/function3/closure0/block0`.
- `context` line 1751: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 1759: lexical, read, binding `unbound`, scope `member/block0`.

Lexical hazards:

- `context` line 1687: lexical, read, binding `unbound`, scope `member/block0/function2/closure0`.
- `context` line 1689: lexical, read, binding `unbound`, scope `member/block0/function2/closure0`.
- `context` line 1710: lexical, read, binding `unbound`, scope `member/block0/function3/closure0/block0`.
- `context` line 1716: lexical, read, binding `unbound`, scope `member/block0/function3/closure0/block0`.
- `context` line 1728: lexical, read, binding `unbound`, scope `member/block0/function3/closure0/block0`.
- `context` line 1730: lexical, read, binding `unbound`, scope `member/block0/function3/closure0/block0`.
- `context` line 1751: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 1759: lexical, read, binding `unbound`, scope `member/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildTvProfileSection`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_profile_pane.dart` `EditProfileTvProfilePane.buildTvProfileSection`; step 4. Original lines 1813–1916.

- `_buildTvProfilePreview`: invocation line 1818 [lexical; unbound; member/block0]
- `_buildTvRoleCards`: invocation line 1895 [lexical; unbound; member/block0]
- `_copyDefaults`: read line 1900 [lexical; unbound; member/block0/if2]; write line 1905 [lexical; unbound; member/block0/if2/closure0/closure0]
- `_moveTvContent`: invocation line 1883 [lexical; unbound; member/block0/closure0]; invocation line 1884 [lexical; unbound; member/block0/closure1]; invocation line 1885 [lexical; unbound; member/block0/closure2]
- `_name`: read line 1880 [lexical; unbound; member/block0]
- `_pendingAvatarBytes`: read line 1849 [lexical; unbound; member/block0/if1]; write line 1856 [lexical; unbound; member/block0/if1/closure0/closure0]
- `_pickAvatarImage`: read line 1840 [lexical; unbound; member/block0/if0]
- `_returnToTvRail`: read line 1881 [lexical; unbound; member/block0]
- `_saving`: read line 1840 [lexical; unbound; member/block0/if0]; read line 1854 [lexical; unbound; member/block0/if1]
- `_tvAvatarTile`: invocation line 1867 [lexical; unbound; member/block0/for0]; invocation line 1872 [lexical; unbound; member/block0/for1]
- `_tvPanel`: invocation line 1821 [lexical; unbound; member/block0]

Live State/widget/context sites:

- `context` line 1814: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 1834: lexical, read, binding `unbound`, scope `member/block0`.
- `setState` line 1856: lexical, invocation, binding `unbound`, scope `member/block0/if1/closure0`.
- `context` line 1876: lexical, read, binding `unbound`, scope `member/block0`.
- `setState` line 1886: lexical, invocation, binding `unbound`, scope `member/block0/closure3`.
- `context` line 1893: lexical, read, binding `unbound`, scope `member/block0`.
- `widget` line 1896: lexical, read, binding `unbound`, scope `member/block0/if2`.
- `setState` line 1905: lexical, invocation, binding `unbound`, scope `member/block0/if2/closure0`.

Lexical hazards:

- `context` line 1814: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 1834: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 1876: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 1893: lexical, read, binding `unbound`, scope `member/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildTvProfilePreview`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_profile_pane.dart` `EditProfileTvProfilePane._buildTvProfilePreview`; step 4. Original lines 1918–1983.

- `_avatarKey`: read line 1937 [lexical; unbound; member/closure0/block0]
- `_name`: read line 1939 [lexical; unbound; member/closure0/block0]; read line 1939 [lexical; unbound; member/closure0/block0]; read line 1946 [lexical; unbound; member/closure0/block0]; read line 1946 [lexical; unbound; member/closure0/block0]
- `_pendingAvatarBytes`: read line 1933 [lexical; unbound; member/closure0/block0]; read-write line 1934 [lexical; unbound; member/closure0/block0]
- `_role`: read line 1938 [lexical; unbound; member/closure0/block0]; read line 1968 [lexical; unbound; member/closure0/block0]; read line 1970 [lexical; unbound; member/closure0/block0]; read line 1970 [lexical; unbound; member/closure0/block0]
- `_tvPanel`: invocation line 1918 [lexical; unbound; member]

Live State/widget/context sites:

- `widget` line 1936: lexical, read, binding `unbound`, scope `member/closure0/block0`.
- `context` line 1951: lexical, read, binding `decl:member/closure0#context#0`, scope `member/closure0/block0`.

Lexical hazards:

- `context` line 1951: lexical, read, binding `decl:member/closure0#context#0`, scope `member/closure0/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._tvAvatarTile`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_profile_pane.dart` `EditProfileTvProfilePane._tvAvatarTile`; step 4. Original lines 1985–2011.

- `_avatarKey`: read line 1986 [lexical; unbound; member/block0]; write line 1996 [lexical; unbound; member/block0/closure0/closure0/block0]
- `_pendingAvatarBytes`: read line 1986 [lexical; unbound; member/block0]; write line 1997 [lexical; unbound; member/block0/closure0/closure0/block0]
- `_role`: read line 2004 [lexical; unbound; member/block0]

Live State/widget/context sites:

- `setState` line 1995: lexical, invocation, binding `unbound`, scope `member/block0/closure0`.
- `widget` line 2002: lexical, read, binding `unbound`, scope `member/block0`.

Lexical hazards:

- `selected` line 1994: lexical, read, binding `decl:member/block0#selected#0`, scope `member/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildTvRoleCards`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_profile_pane.dart` `EditProfileTvProfilePane._buildTvRoleCards`; step 4. Original lines 2013–2085.

- `_role`: read line 2025 [lexical; unbound; member/block0/function0/closure0]
- `_setRole`: invocation line 2026 [lexical; unbound; member/block0/function0/closure0/closure0]

Live State/widget/context sites:

- `context` line 2041: lexical, read, binding `unbound`, scope `member/block0/function0/closure0`.
- `context` line 2049: lexical, read, binding `unbound`, scope `member/block0/function0/closure0`.

Lexical hazards:

- `role` line 2024: lexical, read, binding `decl:member/block0/function0/closure0#role#0`, scope `member/block0/function0/closure0`.
- `role` line 2025: lexical, read, binding `decl:member/block0/function0/closure0#role#0`, scope `member/block0/function0/closure0`.
- `role` line 2026: lexical, read, binding `decl:member/block0/function0/closure0#role#0`, scope `member/block0/function0/closure0/closure0`.
- `role` line 2031: lexical, read, binding `decl:member/block0/function0/closure0#role#0`, scope `member/block0/function0/closure0`.
- `role` line 2040: lexical, read, binding `decl:member/block0/function0/closure0#role#0`, scope `member/block0/function0/closure0`.
- `context` line 2041: lexical, read, binding `unbound`, scope `member/block0/function0/closure0`.
- `role` line 2046: lexical, read, binding `decl:member/block0/function0/closure0#role#0`, scope `member/block0/function0/closure0`.
- `context` line 2049: lexical, read, binding `unbound`, scope `member/block0/function0/closure0`.
- `role` line 2066: lexical, read, binding `decl:member/block0/closure0/block0/if0/block0/for0#role#0`, scope `member/block0/closure0/block0/if0/block0/for0`.
- `role` line 2067: lexical, read, binding `decl:member/block0/closure0/block0/if0/block0/for0#role#0`, scope `member/block0/closure0/block0/if0/block0/for0/if0`.
- `role` line 2077: lexical, read, binding `decl:member/block0/closure0/block0/for0#role#0`, scope `member/block0/closure0/block0/for0`.
- `role` line 2078: lexical, read, binding `decl:member/block0/closure0/block0/for0#role#0`, scope `member/block0/closure0/block0/for0/if0`.

Comments: 2 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildTvLockSection`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_panes.dart` `EditProfileTvPanes.buildTvLockSection`; step 4. Original lines 2087–2167.

- `_inactivityMinutes`: read line 2158 [lexical; unbound; member]; write line 2160 [lexical; unbound; member/closure4/closure0]
- `_lockOnResume`: read line 2144 [lexical; unbound; member]; write line 2147 [lexical; unbound; member/closure3/closure0]
- `_moveTvContent`: invocation line 2112 [lexical; unbound; member/closure0]; invocation line 2113 [lexical; unbound; member/closure1]; invocation line 2114 [lexical; unbound; member/closure2]
- `_pin`: read line 2110 [lexical; unbound; member]
- `_removePinAsAdmin`: read line 2132 [lexical; unbound; member/if0]
- `_returnToTvRail`: read line 2111 [lexical; unbound; member]
- `_saving`: read line 2132 [lexical; unbound; member/if0]
- `_tvPanel`: invocation line 2090 [lexical; unbound; member]

Live State/widget/context sites:

- `context` line 2098: lexical, read, binding `unbound`, scope `member`.
- `context` line 2105: lexical, read, binding `unbound`, scope `member`.
- `widget` line 2122: lexical, read, binding `unbound`, scope `member`.
- `widget` line 2127: lexical, read, binding `unbound`, scope `member/if0`.
- `widget` line 2128: lexical, read, binding `unbound`, scope `member/if0`.
- `setState` line 2147: lexical, invocation, binding `unbound`, scope `member/closure3`.
- `context` line 2152: lexical, read, binding `unbound`, scope `member`.
- `setState` line 2160: lexical, invocation, binding `unbound`, scope `member/closure4`.

Lexical hazards:

- `context` line 2098: lexical, read, binding `unbound`, scope `member`.
- `context` line 2105: lexical, read, binding `unbound`, scope `member`.
- `context` line 2152: lexical, read, binding `unbound`, scope `member`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildTvAccessSection`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_panes.dart` `EditProfileTvPanes.buildTvAccessSection`; step 4. Original lines 2169–2212.

- `_buildConnectionGroups`: invocation line 2205 [lexical; unbound; member/if0/if0]
- `_buildEngineGroup`: invocation line 2204 [lexical; unbound; member/if0/if0]
- `_engines`: read line 2201 [lexical; unbound; member/if0/if0]
- `_loadSetupOptions`: read line 2196 [lexical; unbound; member/if0]
- `_setupLoadError`: read line 2190 [lexical; unbound; member/if0]; read-write line 2194 [lexical; unbound; member/if0]
- `_tvPanel`: invocation line 2172 [lexical; unbound; member]

Live State/widget/context sites:

- `context` line 2180: lexical, read, binding `unbound`, scope `member`.
- `context` line 2187: lexical, read, binding `unbound`, scope `member`.

Lexical hazards:

- `context` line 2180: lexical, read, binding `unbound`, scope `member`.
- `context` line 2187: lexical, read, binding `unbound`, scope `member`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildTvDataSection`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_panes.dart` `EditProfileTvPanes.buildTvDataSection`; step 4. Original lines 2214–2274.

- `_showDiagnostics`: read line 2241 [lexical; unbound; member/if0]
- `_tvPanel`: invocation line 2217 [lexical; unbound; member]

Live State/widget/context sites:

- `context` line 2225: lexical, read, binding `unbound`, scope `member`.
- `widget` line 2231: lexical, read, binding `unbound`, scope `member`.
- `context` line 2234: lexical, read, binding `unbound`, scope `member`.
- `widget` line 2237: lexical, read, binding `unbound`, scope `member/if0`.
- `context` line 2255: lexical, read, binding `unbound`, scope `member/if0`.

Lexical hazards:

- `context` line 2225: lexical, read, binding `unbound`, scope `member`.
- `context` line 2234: lexical, read, binding `unbound`, scope `member`.
- `context` line 2255: lexical, read, binding `unbound`, scope `member/if0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._tvPanel`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_tv_panes.dart` `EditProfileTvPanes.tvPanel`; step 4. Original lines 2276–2288.


Live State/widget/context sites:

- `context` line 2277: lexical, read, binding `unbound`, scope `member`.
- `context` line 2282: lexical, read, binding `unbound`, scope `member`.

Lexical hazards:

- `context` line 2277: lexical, read, binding `unbound`, scope `member`.
- `context` line 2282: lexical, read, binding `unbound`, scope `member`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._removePinAsAdmin`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_admin_actions.dart` `EditProfileAdminActions.removePinAsAdmin`; step 3. Original lines 2290–2292.

- `_removePinAsAdminLocally`: invocation line 2291 [lexical; unbound; member/block0]

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._removePinAsAdminLocally`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_admin_actions.dart` `EditProfileAdminActions._removePinAsAdminLocally`; step 3. Original lines 2294–2315.

- `_authorization`: read line 2296 [lexical; unbound; member/block0/block0]; write line 2302 [lexical; unbound; member/block0/block0]
- `_refreshSameManagingAdmin`: invocation line 2302 [lexical; unbound; member/block0/block0]
- `_validateManagingAdmin`: invocation line 2297 [lexical; unbound; member/block0/block0]

Live State/widget/context sites:

- `widget` line 2298: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `widget` line 2300: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `mounted` line 2305: lexical, read, binding `unbound`, scope `member/block0/block0/if0`.
- `context` line 2307: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `mounted` line 2310: lexical, read, binding `unbound`, scope `member/block0/catch0/block0/if0`.
- `context` line 2311: lexical, read, binding `unbound`, scope `member/block0/catch0/block0`.

Lexical hazards:

- `context` line 2307: lexical, read, binding `unbound`, scope `member/block0/block0`.
- `context` line 2311: lexical, read, binding `unbound`, scope `member/block0/catch0/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildAvatarSection`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_phone_parts.dart` `EditProfilePhoneParts.buildAvatarSection`; step 5. Original lines 2317–2411.

- `_artTile`: invocation line 2386 [lexical; unbound; member/block0/for0]; invocation line 2397 [lexical; unbound; member/block0/for1]
- `_avatarKey`: read line 2346 [lexical; unbound; member/block0]
- `_name`: read line 2348 [lexical; unbound; member/block0]; read line 2348 [lexical; unbound; member/block0]
- `_pendingAvatarBytes`: read line 2318 [lexical; unbound; member/block0]; write line 2371 [lexical; unbound; member/block0/if1/closure0/closure0]
- `_pickAvatarImage`: read line 2361 [lexical; unbound; member/block0/if0]
- `_role`: read line 2347 [lexical; unbound; member/block0]; read line 2392 [lexical; unbound; member/block0/for0]; read line 2403 [lexical; unbound; member/block0/for1]
- `_saving`: read line 2361 [lexical; unbound; member/block0/if0]; read line 2369 [lexical; unbound; member/block0/if1]

Live State/widget/context sites:

- `widget` line 2345: lexical, read, binding `unbound`, scope `member/block0`.
- `setState` line 2371: lexical, invocation, binding `unbound`, scope `member/block0/if1/closure0`.
- `widget` line 2390: lexical, read, binding `unbound`, scope `member/block0/for0`.
- `widget` line 2401: lexical, read, binding `unbound`, scope `member/block0/for1`.

Comments: 2 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._artTile`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_phone_parts.dart` `EditProfilePhoneParts._artTile`; step 5. Original lines 2413–2446.

- `_avatarKey`: read line 2418 [lexical; unbound; member/block0]; write line 2426 [lexical; unbound; member/block0/closure0/closure0/block0]
- `_pendingAvatarBytes`: read line 2418 [lexical; unbound; member/block0]; write line 2427 [lexical; unbound; member/block0/closure0/closure0/block0]
- `_saving`: read line 2423 [lexical; unbound; member/block0]

Live State/widget/context sites:

- `setState` line 2425: lexical, invocation, binding `unbound`, scope `member/block0/closure0`.
- `context` line 2437: lexical, read, binding `unbound`, scope `member/block0`.

Lexical hazards:

- `selected` line 2436: lexical, read, binding `decl:member/block0#selected#0`, scope `member/block0`.
- `context` line 2437: lexical, read, binding `unbound`, scope `member/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildRoleCards`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_phone_parts.dart` `EditProfilePhoneParts.buildRoleCards`; step 5. Original lines 2448–2474.

- `_roleCard`: invocation line 2462 [lexical; unbound; member/block0/closure0/block0/for0]

Lexical hazards:

- `role` line 2463: lexical, read, binding `decl:member/block0/closure0/block0/for0#role#0`, scope `member/block0/closure0/block0/for0`.
- `role` line 2464: lexical, read, binding `decl:member/block0/closure0/block0/for0#role#0`, scope `member/block0/closure0/block0/for0`.
- `role` line 2465: lexical, read, binding `decl:member/block0/closure0/block0/for0#role#0`, scope `member/block0/closure0/block0/for0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._roleCard`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_phone_parts.dart` `EditProfilePhoneParts._roleCard`; step 5. Original lines 2476–2522.

- `_role`: read line 2482 [lexical; unbound; member/block0]
- `_saving`: read line 2491 [lexical; unbound; member/block0]
- `_setRole`: invocation line 2491 [lexical; unbound; member/block0/closure0]

Live State/widget/context sites:

- `context` line 2483: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 2507: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 2511: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 2513: lexical, read, binding `unbound`, scope `member/block0`.

Lexical hazards:

- `role` line 2482: lexical, read, binding `decl:member#role#0`, scope `member/block0`.
- `context` line 2483: lexical, read, binding `unbound`, scope `member/block0`.
- `role` line 2491: lexical, read, binding `decl:member#role#0`, scope `member/block0/closure0`.
- `selected` line 2496: lexical, read, binding `decl:member/block0#selected#0`, scope `member/block0`.
- `selected` line 2501: lexical, read, binding `decl:member/block0#selected#0`, scope `member/block0`.
- `context` line 2507: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 2511: lexical, read, binding `unbound`, scope `member/block0`.
- `context` line 2513: lexical, read, binding `unbound`, scope `member/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildEngineGroup`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_rows.dart` `EditProfileAccessRows.buildEngineGroup`; step 4. Original lines 2524–2586.

- `_authorization`: read line 2526 [lexical; unbound; member/block0]
- `_engines`: read-write line 2525 [lexical; unbound; member/block0]
- `_groupHeader`: invocation line 2530 [lexical; unbound; member/block0]
- `_selectedEngines`: read line 2532 [lexical; unbound; member/block0]; read line 2537 [lexical; unbound; member/block0/closure0/closure0]; read line 2543 [lexical; unbound; member/block0/closure1]; read line 2565 [lexical; unbound; member/block0/if0/for0]; read line 2577 [lexical; unbound; member/block0/if0/for0/closure0/closure0/block0/if0/block0]; read line 2579 [lexical; unbound; member/block0/if0/for0/closure0/closure0/block0/if0/block1]
- `_tvAccessFocusRow`: invocation line 2561 [lexical; unbound; member/block0/if0/for0]

Live State/widget/context sites:

- `widget` line 2526: lexical, read, binding `unbound`, scope `member/block0`.
- `setState` line 2536: lexical, invocation, binding `unbound`, scope `member/block0/closure0`.
- `setState` line 2543: lexical, invocation, binding `unbound`, scope `member/block0/closure1`.
- `context` line 2549: lexical, read, binding `unbound`, scope `member/block0`.
- `widget` line 2569: lexical, read, binding `unbound`, scope `member/block0/if0/for0`.
- `setState` line 2575: lexical, invocation, binding `unbound`, scope `member/block0/if0/for0/closure0`.

Lexical hazards:

- `engines` line 2533: lexical, read, binding `decl:member/block0#engines#0`, scope `member/block0`.
- `engines` line 2534: lexical, read, binding `decl:member/block0#engines#0`, scope `member/block0`.
- `engines` line 2538: lexical, read, binding `decl:member/block0#engines#0`, scope `member/block0/closure0/closure0`.
- `engines` line 2541: lexical, read, binding `decl:member/block0#engines#0`, scope `member/block0`.
- `context` line 2549: lexical, read, binding `unbound`, scope `member/block0`.
- `engines` line 2551: lexical, read, binding `decl:member/block0#engines#0`, scope `member/block0/if0`.
- `engines` line 2560: lexical, read, binding `decl:member/block0#engines#0`, scope `member/block0/if0/for0`.
- `selected` line 2576: lexical, read, binding `decl:member/block0/if0/for0/closure0#selected#0`, scope `member/block0/if0/for0/closure0/closure0/block0/if0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._tvAccessFocusRow`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_rows.dart` `EditProfileAccessRows._tvAccessFocusRow`; step 4. Original lines 2588–2597.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._accessGroups`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_rows.dart` `EditProfileAccessRows.accessGroups`; step 4. Original lines 2599–2632.


Comments: 2 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._buildConnectionGroups`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_rows.dart` `EditProfileAccessRows.buildConnectionGroups`; step 4. Original lines 2634–2663.

- `_accessGroups`: read line 2641 [lexical; unbound; member/block0/for0/block0]; read line 2654 [lexical; unbound; member/block0/for1]
- `_connectionGroup`: invocation line 2656 [lexical; unbound; member/block0/for1/block0/if0]; invocation line 2660 [lexical; unbound; member/block0/if1/block0]
- `_resources`: read line 2635 [lexical; unbound; member/block0]

Live State/widget/context sites:

- `context` line 2651: lexical, read, binding `unbound`, scope `member/block0`.

Lexical hazards:

- `resources` line 2636: lexical, read, binding `decl:member/block0#resources#0`, scope `member/block0/if0`.
- `resources` line 2636: lexical, read, binding `decl:member/block0#resources#0`, scope `member/block0/if0`.
- `resources` line 2638: lexical, read, binding `decl:member/block0#resources#0`, scope `member/block0/for0`.
- `context` line 2651: lexical, read, binding `unbound`, scope `member/block0`.

Comments: 1 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._connectionGroup`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_rows.dart` `EditProfileAccessRows._connectionGroup`; step 4. Original lines 2665–2684.

- `_connectionRow`: invocation line 2682 [lexical; unbound; member/block0/for0]
- `_deselectResource`: read line 2680 [lexical; unbound; member/block0/closure2/closure0]
- `_editableIn`: invocation line 2669 [lexical; unbound; member/block0]
- `_groupHeader`: invocation line 2671 [lexical; unbound; member/block0]
- `_selectResource`: read line 2677 [lexical; unbound; member/block0/closure1/closure0]
- `_selectedResources`: read line 2667 [lexical; unbound; member/block0/closure0]

Live State/widget/context sites:

- `setState` line 2677: lexical, invocation, binding `unbound`, scope `member/block0/closure1`.
- `setState` line 2680: lexical, invocation, binding `unbound`, scope `member/block0/closure2`.

Lexical hazards:

- `selected` line 2673: lexical, read, binding `decl:member/block0#selected#0`, scope `member/block0`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._groupHeader`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_rows.dart` `EditProfileAccessRows._groupHeader`; step 4. Original lines 2686–2713.


Live State/widget/context sites:

- `context` line 2696: lexical, read, binding `unbound`, scope `member`.
- `context` line 2700: lexical, read, binding `unbound`, scope `member`.
- `context` line 2702: lexical, read, binding `unbound`, scope `member`.

Lexical hazards:

- `context` line 2696: lexical, read, binding `unbound`, scope `member`.
- `selected` line 2699: lexical, read, binding `decl:member#selected#0`, scope `member`.
- `context` line 2700: lexical, read, binding `unbound`, scope `member`.
- `context` line 2702: lexical, read, binding `unbound`, scope `member`.

Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._connectionRow`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_access_rows.dart` `EditProfileAccessRows._connectionRow`; step 4. Original lines 2715–2755.

- `_deselectResource`: invocation line 2743 [lexical; unbound; member/block0/closure1/closure0/block0/if0/block1]
- `_features`: read line 2731 [lexical; unbound; member/block0]
- `_role`: read line 2730 [lexical; unbound; member/block0]
- `_selectResource`: invocation line 2741 [lexical; unbound; member/block0/closure1/closure0/block0/if0/block0]
- `_selectedResources`: read line 2722 [lexical; unbound; member/block0]
- `_transferOwnership`: invocation line 2734 [lexical; unbound; member/block0/closure0]
- `_tvAccessFocusRow`: invocation line 2718 [lexical; unbound; member/block0]

Live State/widget/context sites:

- `widget` line 2716: lexical, read, binding `unbound`, scope `member/block0`.
- `widget` line 2728: lexical, read, binding `unbound`, scope `member/block0`.
- `widget` line 2729: lexical, read, binding `unbound`, scope `member/block0`.
- `setState` line 2739: lexical, invocation, binding `unbound`, scope `member/block0/closure1`.

Lexical hazards:

- `selected` line 2740: lexical, read, binding `decl:member/block0/closure1#selected#0`, scope `member/block0/closure1/closure0/block0/if0`.

Comments: 5 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.

## `_EditProfileScreenState._featureLabel`

Destination: `lib/features/edit_profile/presentation/legacy_edit_profile/edit_profile_phone_form.dart` `EditProfilePhoneForm._featureLabel`; step 5. Original lines 2757–2763.


Comments: 0 AST tokens; exact text pinned by the original leaf and original-comment check. Wiring review: destination/owner and original dependencies inventoried; actual creation-step receiver review pending.


## Cross-owner calls at R

Derived from unbound original AST occurrences; record fields and top-level types are included. These are the dependencies to wire before each row moves. The 0b compiling composition remains pending.

| Source owner | Reads/calls into |
| --- | --- |
| access | adminActions, facade, owners.access, owners.form, selection, surface |
| adminActions | admin, facade, setup |
| avatar | owners.form |
| facade | model, owners.form, owners.tv, setup |
| grants | admin, selection |
| owners.tv | model |
| phone | access, adminActions, facade, owners.access, owners.form, phoneParts, save, setup, tvEditor |
| phoneParts | avatar, owners.form, selection |
| save | admin, facade, grants, model, owners.access, owners.form, tvNav |
| selection | owners.access, owners.form |
| setup | admin, facade, owners.access |
| tvEditor | model, owners.form, owners.tv, save, surface, tvNav, tvPanes, tvProfile |
| tvNav | model, owners.form, owners.tv |
| tvPanes | access, adminActions, owners.access, owners.form, setup, surface, tvNav |
| tvProfile | avatar, owners.form, selection, surface, tvNav, tvPanes |

## Internal members of whole leaves

These remain inside their whole-class manifest leaves; no member may be duplicated or omitted.

- `EditProfileScreen.registry` (FieldDeclarationImpl).
- `EditProfileScreen.pins` (FieldDeclarationImpl).
- `EditProfileScreen.authorization` (FieldDeclarationImpl).
- `EditProfileScreen.profile` (FieldDeclarationImpl).
- `EditProfileScreen.setupOptionsLoader` (FieldDeclarationImpl).
- `EditProfileScreen.EditProfileScreen` (ConstructorDeclarationImpl).
- `EditProfileScreen.showFeaturePolicyControls` (FieldDeclarationImpl).
- `EditProfileScreen.policyFor` (MethodDeclarationImpl).
- `EditProfileScreen.createState` (MethodDeclarationImpl).
- `_EnsureVisibleOnFocus._EnsureVisibleOnFocus` (ConstructorDeclarationImpl).
- `_EnsureVisibleOnFocus.child` (FieldDeclarationImpl).
- `_EnsureVisibleOnFocus.build` (MethodDeclarationImpl).
- `_TvReadOnlyScrollAnchor._TvReadOnlyScrollAnchor` (ConstructorDeclarationImpl).
- `_TvReadOnlyScrollAnchor.child` (FieldDeclarationImpl).
- `_TvReadOnlyScrollAnchor.createState` (MethodDeclarationImpl).
- `_TvReadOnlyScrollAnchorState._focused` (FieldDeclarationImpl).
- `_TvReadOnlyScrollAnchorState.build` (MethodDeclarationImpl).
- `_TvActionSurface._TvActionSurface` (ConstructorDeclarationImpl).
- `_TvActionSurface.child` (FieldDeclarationImpl).
- `_TvActionSurface.onPressed` (FieldDeclarationImpl).
- `_TvActionSurface.selected` (FieldDeclarationImpl).
- `_TvActionSurface.autofocus` (FieldDeclarationImpl).
- `_TvActionSurface.focusNode` (FieldDeclarationImpl).
- `_TvActionSurface.onKeyEvent` (FieldDeclarationImpl).
- `_TvActionSurface.createState` (MethodDeclarationImpl).
- `_TvActionSurfaceState._focused` (FieldDeclarationImpl).
- `_TvActionSurfaceState.build` (MethodDeclarationImpl).
- `_TvAutoLockField._TvAutoLockField` (ConstructorDeclarationImpl).
- `_TvAutoLockField.value` (FieldDeclarationImpl).
- `_TvAutoLockField.onChanged` (FieldDeclarationImpl).
- `_TvAutoLockField._labels` (FieldDeclarationImpl).
- `_TvAutoLockField.build` (MethodDeclarationImpl).
- `_ProfileEditSnapshot.name` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.pin` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.role` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.features` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.copyDefaults` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.lockOnResume` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.inactivityMinutes` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.avatarKey` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.pendingAvatarBytes` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.resources` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.selectedResources` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.resourcePermissions` (FieldDeclarationImpl).
- `_ProfileEditSnapshot.selectedEngines` (FieldDeclarationImpl).
- `_ProfileEditSnapshot._ProfileEditSnapshot` (ConstructorDeclarationImpl).

## Source-text and visual inventories

The editor is outside the shape and theme manifests and is not a PRIMARY light-ink surface. The shape-test regex counts 13 literal sites; the broader `circular(` search counts 14 because one conditional radius is outside that regex. No surface registration changes occur at step 0.

The only exact editor-file source reader is `profile_source_guard_test.dart`; its expectation strings are unchanged. Global profile preference/database/SQL sweeps, stale-runtime reset-cache discovery, theme sweeps, and storage references also see the editor. Each editor leaf has zero raw preference opens, fixed TV/IPTV database names, SQL upserts, VACUUM INTO, or StorageService references. Their identical syntax-fixture destinations retain those zero counts. The full concrete inventory and original counts are in `source-text-and-surface-inventory.json` under the common evidence directory.
