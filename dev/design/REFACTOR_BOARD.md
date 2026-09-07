  # Refactor board

## Current roadmap — September 6, merged production main 52e8da5b

**Overall estimate: approximately 75%.** Architectural judgment, not a measured checklist percentage. Open PRs are not completed work. This checklist preserves the same six outcomes; historical evidence follows below.

### God-file line counts — original → merged main

- **Search:** 19,070 → **6,102** (12,968 fewer)
- **Player:** 16,278 → **11,539** (4,739 fewer)
- **Magic TV:** 10,716 → **3,322** (7,394 fewer)
- **Storage:** 9,963 → **1,741** (8,222 fewer)
- **Settings:** 7,905 → **2,908** (4,997 fewer)

Physical lines, not whole-project deletions. Last full gate: **31e360f6 PASSED**; its forwarder ledger was Storage204 / Search133 / Player161 / Magic23 / Settings0. #222/#223/#224 are included in this gate. Forbidden imports: **77 → 56 on merged main**, including #217/#218. No baseline increase.

### Do next — actual execution order

- [x] **Merge #225 shared rail labels and #226 Atrium text ownership.** Both independently reviewed and all three CI jobs passed. Search now6,102;353 lines remain against the stage target.
- [ ] **Finish metadata PR #227.** Author and independent35-case runs passed; candidate analyzer430/449 and layering53. Updating its branch with merged #226, preserving tested payloads; require final union review and fresh exact-head CI before merge.
- [ ] **Run the next integrated gate after #227 merges.** Counter2 since full31e360; the next production merge triggers full actual-main verification and builds.
- [ ] **Verify the Home overlay origin test.** Four-case draft corrected after static-only theme API failure; first behavioral run authorized. This work earns zero seven-stage target credit.
- [ ] **Prepare IPTV behavior tests.** Six-test/eight-scenario scope, real SQLite and actual series navigation. No runtime yet; successful native movie launch remains an unresolved production-move constraint.

### 1. Finish Search stage layouts and final shared composition — OPEN

- [x] Merge standalone Discover, Spotlight, Tonight, Deck, Mosaic, Promenade and Canvas work; shared BoardCell and favourites #203.
- [x] Diagnose and fix Atrium overflow in #216; independent geometry tests and CI passed.
- [x] Pin Atrium navigation on the fixed original path: three cases passed before the move.
- [x] **Merge seventh public stage in #219.** Merged13cd4029 after independent28 checks and exact CI passed. Its seven explicit callbacks remain; +60 host/+35 production lines are growth, not extraction credit.
- [x] **Finish Sources route/library ownership.** #220 makes the existing owner a standalone library and redirects two consumers, preserving seven original behavior pins. Host-16/production+12; no 2,775-line extraction or stage-target credit.
- [x] **Resolve the oversized hero part in #222.** Merged9e809c97 after independent136PASS/one existing known failure and allCI passed. Retained part947, passive owner1060; host+1/production+15, zero638-target credit.
- [ ] **Close final shared-composition and original rebuild obligations with evidence.** Retained callback inventories are not automatically unused forwarders. Preserve accepted Mosaic focus/prefetch policy.
- [ ] **Reconcile the existing 1,400-line stage target.** Recorded1,047 leaves /353 short remains explicit after Canvas #224 (146), rail-label #225 (80), and Atrium text #226 (59). Do not count already-external part lines, wrapper growth or the overflow fix toward it.

### 2. Complete player decoder/state/UI separation — OPEN

- [x] Merge terminal seam #190, diagnostic ownership #193, presentation #201 and transport #205; retain existing overlay/guide pins.
- [ ] **Obtain a fully passing tracker origin pin before moving tracker ownership.** Real selected21s resume was observed, but the final test still failed on an initial-resume delayed Future/fake-clock cleanup obligation. No green-pin credit. Four failures and attribution are retained in NOTES.
- [ ] **Resolve remaining cohesive decoder/state/UI ownership.** Propose exact ownership boundaries and actual origin entry before code changes; no new callback bag.
- [ ] **Disposition renderer and scrub evidence gaps under existing criteria.** Renderer attempts remain held. Scrub's eleven invalidation transitions make an isolated helper move insufficient; retention is explicit, not completion of the broader player outcome.

### 3. Finish storage business-logic ownership and eligible temporary facade removal — OPEN, MAJOR MILESTONE ACCEPTED

- [x] Reach the host-size target and extract domain owners with key-compatible origin/restore evidence.
- [x] Merge eligible routing/forwarder retirements through #215.
- [x] Accept the bounded extraction/key-compatibility/eligible-Q2 milestone at full gatebc017.
- [ ] **Resolve separately deferred native/render ownership evidence.** Six policy methods42 lines plus debug3 remain deferred; this is distinct from nine already-owned native-sensitive forwarding APIs.
- [ ] **Close strict Storage acceptance only against its existing contract.** Five coordinators74 lines and battery/fixed14 lines are already accepted retentions, not newly assigned cleanup. Native-sensitive retirement requires its named evidence.

Finite pre-S2 fixtures are not proof of every pre-refactor backup. Indexer export, adult held lookup, Android-positive and lifetime gaps remain recorded. No more tiny forwarding batches are assigned merely to lower line counts.

### 4. Finish M1-7 genuine common-flow dedup and dependency cleanup — COMPLETE

- [x] Meet the provider-leaf target:627 lines versus under800.
- [x] Merge common programmes and captured-provider operations; remove the two cached-entry wrappers.
- [x] Pass independent88-case verification and integrated gatee78d100e.
- [x] Record finite Windowed/UI retention decisions. No new zero-callback or autonomous-provider requirement.

### 5. Q-phase dependency/rule cleanup, compatibility expiry and upstream contribution work — OPEN

- [x] Complete canonical-rule migration #188 and provider guide #192.
- [x] Merge neutral PlaylistEntry owner #217:15 forbidden imports removed, old import compatibility preserved.
- [x] **Merge shared focus-wrapper owner #218:** six additional forbidden imports removed and verified.
- [ ] **Close remaining strict Q1 dependencies through separately owned lanes.** Main currently56. Ceiling77/no-growth is not strict zero-violation acceptance. Do not loosen the checker or hide dependencies behind exports.
- [ ] **Finish compatibility expiry accounting.** Distinguish still-used exports and accepted/native-sensitive APIs from genuinely obsolete facades; do not delete all aliases blindly.
- [x] Prepare and independently verify the two-commit upstream catalog candidate locally,24 tests before/after/independent.
- [x] **Honor user decision: keep upstream contribution local.** Publication is intentionally parked, not awaiting an answer. Do not publish or repeatedly ask. This is not an upstream-merged contribution claim.

### 6. Final integrated acceptance of completed architecture — PENDING

- [x] Pass the latest completed intermediate gate31e360f6:6,174 tests passed /12 exact known exceptions /2 skips; goldens21 known; native first pair, Windows and ARM64 passed; analyzer431/449; layering56 at that gate.
- [ ] Finish or explicitly disposition the remaining contractual outcomes above without quietly changing their meaning.
- [ ] Run final integrated acceptance on the resulting actual main and record exact source/artifact hashes, complete failures, dependency count and god-file/forwarder ledger.
- [ ] Report final accepted outcomes and retained debt. Prior phone/TV acceptance stays historical; do not label it new-build device proof. Manual smoke does not block authorized progress.

### Who owns the next action

- **Cicero:** reviews Home overlay origin results; #226 independent and CI acceptance complete.
- **Locke:** runs the corrected Home overlay origin test, stopping on any failure.
- **Confucius:** updates #227 against merged #226, then continues IPTV test preparation.
- **Arendt:** checks #227 union evidence and IPTV fixture design.
- **Parent:** #226 merged; counter2 since full31e360. Next production merge triggers integrated gate. No user blocker.

### Update rules for this checklist

Check off an item only when its stated result is achieved. Update its owner/blocker when it changes; retain these six outcome names. Record merged work separately from prepared/reviewed PRs. Keep original/current god lines visible. After each merge explain the actual benefit and remaining work; preserve detailed evidence in the history below.
### Latest completed milestones

- **#226 merged52e8da5b:** all three CI jobs passed on exacte415 head; independent129PASS/one exact known sidebar failure, scoped4 inherited/full431449zeroNew/layer56 unchanged. Search6161→6102 (-59), existing Atrium owner+80, whole production+21. Stage credit988→1047 of1400,353 remaining. Two whole-widget callbacks replaced by local text composition and a live title reader; callables7→6 but leaf inputs10→14, so no overall interface-size reduction claimed. Did we make a difference? Yes: Atrium now owns its text composition. Is more needed? Yes:353-line stage shortfall and broader Search/Player/Storage/Q acceptance remain open. Counter2; no new-device proof.

- **#225 merged d282889d:** shared rail-label composition now belongs to stage owners; exact ff526635 head independently accepted and all three CI checks passed (run34071413658). Origin8PASS before move; author and independent production suites each132PASS/one exact known sidebar failure, not raw green. Search6241→6161 (-80); whole production+9. Stage credit908→988 of1400;412 remain. Counter1 since full31e360. Other god counts remain Storage1741/Player11539/Magic3322/Settings2908; forwarder ledger is the last full-gate measurement, not rerun here. Did we make a difference? Yes: shared label composition leaves the host and one opaque callback is removed. Is more needed? Yes: Atrium and remaining shared composition, plus Player/Storage/Q acceptance stay open.

- **Full31e360f6 gate PASSED:**6174PASS/12exactknown/2skip;goldens21known/configured2retries/actualhelpers0/no unexpected or unused. NativeFIRSTPAIRPASS; analyzer431/449zeroNew/Python55/layer56→56delta0cap77. AST204/133/161/23/0 unchangedidentities; physical1741/6241/11539/3322/2908. WindowsZIPf7a60321172ef1ac23eaa927693ce58ab42f5a3405de6ded3d669bfd2fb34cef; ARM64APK2ffa8838347adb6bf980c97eb1363b6d9d64c162b68604b48d1d493e86d8e2b1, ABIverified/exactheadmanifests. Counterreset0; no newdevice/completearchitecture claim. Did we make a difference? Integrated Hero/keyword/Canvas changes pass the established gate; remainingSearch492 and metadata/Player/Q obligations stay open.

- #224 merged **31e360f6**, exact7ff528 unionaccepted/allCIpassed/independent120PASS+one exactknownsidebar failure. Canvas owns tabs/height with live resolver; Search6387→6241 (-146physical=129span+17other), wholeproduction+3. Credit146 against existing638shortfall: remaining492, strictoutcomeOPEN. Shapeallowance162/floor490 unchanged and negativeprobe caught. Did we make a difference? Actual layout ownership moved into the existing stage; no netdeletion or completeSearch claim. Thirdmerge triggers exact31e360fullgate; newdeviceproof absent.

- #223 merged **161637b1**, exact9cde unionaccepted/independent88PASS/allCIgreen. Keyword child still rebuilds once while redundant host rebuild is removed; other live focus/mode/filter behavior preserved. Source8originPASS and first4/4fixture failures retained; naturalstartup/Discoverlatedefault gaps explicit. Host6388→6387/production-7/zero638credit. Did we make a difference? One whole-host notification edge is removed, not relocated. Canvas layout preparation addresses next substantive slice; counter2 sinced7cd.

- #222 merged **9e809c97**, exacte5cb independent136PASS/one exactknownsidebar failure, sourceunionaccepted/allCIpassed. Hero part1993→947, independentowner1060,16inputs0callbacks, preservedmemo/nativeboundaries. Host6387→6388/production+15/Leaves0; shapeallowance162 unchanged with3negativeprobes caught. Did we make a difference? Passive hero ownership no longer depends on the host library; keyword dual notification and638shortfall remain OPEN. Counter1 sinced7cd. Keywordorigin68d5678casesgreen awaitingreadonlyreview; renderer seam9add6green, hostadmissionred beforefallback on clientconstruction.

- **Full d7cdffb7 gate PASSED:**6155PASS/12exactknown/2skip;goldens21known/configured2retries/no unexpected or unused/helper0; nativeFIRSTPAIRPASS. Analyzer431/449zeroNew/Python55/layer56→56+0/-0 cap77. AST204/133/161/23/0 identitydelta0/0; physical1741/6387/11539/3322/2908. WindowsZIP ad63f723085b5bce97b20038893b3d1ab584920be64fcedeba6e993524db177a; ARM64APK0f04d940552d70af6aa315aedd69aac2a0791bec070dfba56cec018032f9552f. ABI verified; exact source/tree manifests. Counterreset0. Did we make a difference? Three integrated slices pass the established safety gate; final architecture and new-device acceptance are not claimed.

- #221 merged **d7cdffb7**, exacta691/treecad540 independent26PASS and union accepted, allCI passed. Author initial24PASS2ERROR fixture guard conflict retained; one expectSync correction yielded26PASS. Analyzer431 unchanged/scoped61 unchanged/layer56 unchanged. Production+98/host+4, Leaves0. Did we make a difference? Resume verification jobs now have explicit cancellation and retirement ownership; full player separation remains open. Third merge triggers frozen d7cd full gate; no new device proof.

- #220 merged **9d4cf518**, exacta2e4 independent union accepted and allCI passed. Independent145PASS/one existing known shape failure retained. Search6403→6387; production+12, zero stage-target credit. Did we make a difference? Sources owns its standalone library and two consumers no longer import the host. Hero/final composition remain open. Counter2 sinceb6a.

- #219 merged **13cd4029**, exact56ff944d, independent28PASS/unionaccepted/allCIgreen afterb6agate. Allsevenstages nowpublicwidgets; Atrium actualLayoutBuilder/measurement ownership with7retainedcallbacks. Host+60whole+35 ZERO250credit; strictfinalcomposition/638target remainopen. Did we make a difference? Last stage/privatehostpart dependency removed; growth countedhonestly. Counter1sinceb6a. #220 independent145PASS+1existingknownshapeFAIL/docsaccepted nowintegratesmain, no rawgreenclaim.


- **Fullb6a71b0e gate PASSED:**6118PASS/12exactknown/2skip;goldens21known/configured2retries/actualhelpers0/unexpected0unused0. NativefirstpairPASS;431/449zeroNew/Python55/layer62→56+0/-6 ceiling77unchanged. SameAST204/133/161/23/0 unchangedidentities. ZIP31805c61ea9c6b41ee2bcd830dcea06d3dda56ebd7ea635a715d07cfa6dd89d3; ARM64APK0c4d75cd06496d617b4c835693624baa429b534d7737ac83f5a9812aafcc1aa7. Initialwrongnegative-probeflag preserved/corrected; generatednewlineonlyowncheckoutnoise restored; no source/baselinechange. Counterreset0; #219integration released and Sources5case checkpoint runtimeclear. No finalarchitecture/deviceclaim.


- #218 merged **b6a71b0e**, exact94645fe5, independent22PASS/unionaccepted/allCIgreen. ActualcombinedQ1 77→56,+0/-21; thisPR6edges, production+1compat export, no god-linecredit. Did we make a difference? Sharedwidget no longer belongs to a screen layer; strictQ1 remainsopen. Third216217218 triggersfullb6a gate withCicero. Sourcesfirst3originPASS pendingreadonlyreview; icons/subtitle held on compatibility/guardcost, no newparser/runtime. #219 waits gate.


- #217 merged **94c38b32**, exactdb6f19fd, independent24PASS/exact20payloadunion/allthreeCIgreen. PlaylistEntry70lineclass now neutral/importfree; oldexport sameidentity and15consumerimports redirect. MeasuredQ1 imports77→62 with15removed0added; production+1compatibilityexport, ZEROgodlinecredit. Did we make a difference? Fifteen forbiddendependencies removed withoutbusinesslogicchanges; strictQ1 remainsOPEN. Counter2sincebc017. #218 nowintegratesmain; #219 independent28PASSawaitsCI/queue and willremainafterthirdmergegate.


- #216 separateAtrium BUGFIX merged **6aad838a**, exact5dcb1fc8, independent6PASS/allthreeCIgreen/cleanunion. Actualtextmeasurement matcheswallbudget; sharedDeck/Tonight helper unchanged. Intentionalthreshold/earliertitleread deltas preserved, originalred andinitial5/1 fixturefailure retained. Host+50/prod+60 ZEROextractioncredit. Did we make a difference? The attributedoverflow blocker is corrected, but Atrium extraction is notcompleted. Counter1sincebc017. #217 independent24PASS/allCIgreen nowintegratesmain; #218 independent22PASSfrozenbehind217. Upstream stayslocalperuser.


- **Fullbc017 gate PASSED:**6095PASS/12exactknown/2skip;goldens21exactknown/configured2retries/actualhelpers0/unexpected0unused0;raw failures retained. Nativeoriginal/currentFIRSTPAIRPASS,analyzer431/449zeroNew/Python55/layer77+0-0. AST204/133/161/23/0:42Storage removed0added, others unchanged;legacySearch60 separate. Windows162.7s68files ZIPefb4ad80c919716a9fda0e362b2deeaed30a486b9c6ab1c13c46667720982f9e; ARM64APK05d2a54ad4e6527db77472032ff59ed5761783b84201078b5fcb7e3b6ad9e3c7. Generatedowncheckout line-ending noise verified/restored, finalclean. Counter0; Storage extracted/key-compatible and eligibleQ2 milestone ACCEPTED after independentcontractreview; strictoutcome3 remainsOPEN. No device or finalarchitecture claim.


- #215 merged **bc017b87**, exactf03ddf1c, independent87PASS/maincontained/allthreeCIgreen. NineRemoteforwards removed; host-19/prod-16/all8-2, one actualrolepicker dependency removed. Native/network/lifecycle/auth unchanged. Did we make a difference? Existingowner routing reducescoupling; no positivepairing/native or strictclosure claim. Third213214215 triggers fullactual-main bc017gate withCicero; Locke boundedcontractualcloseout packet assigned.


- #214 merged **719e96ed**, exacte8aaf4c6, independent90PASS/exactunion/allthreeCIgreen. EightDeviceMaintenanceforwards removed; host-17/prod-15/all7-1, one actual SupportRemoteConfigService dependency removed. Owner/global/native/auth/cache unchanged. Did we make a difference? Direct maintenance ownership replaces a needless service dependency; remaining ownership/native obligations stayopen. Counter2since98ca; Locke closeout inventory and Cicero six-outcome evidence audit assigned.


- #213 merged **03b125ef**, exact862bca0f, independent161PASS/maincontained/allthreeCIgreen. AppStyle25forwards removed andfive realhostdependencies eliminated; host-25/prod-18/all27includingREADME+4, notwhole-project deletion. Protected40/cache/reset unchanged. Did we make a difference? Application appearance callers now reach existingowner directly; strictownership/nativeclosure remainsopen. #214 independent90PASSawaitsmainunion/freshCI. Firstproductionmerge since98ca gate.


- **Full98cae882 gate PASSED:** nativeoriginal/current FIRSTPAIRPASS;6095PASS/12exactknown/2skip;goldens21exactknown/configured2retries/helpers0/unexpected0unused0;analyzer431/449zeroNew/Python55/layer77+0-0. Windows160.2s68files ZIP567bd402931127b21129198870a958bba463aa3a6eb6a43700a2278833612025; ARM64APK173f055b4e2ed85035aca1fff54abfefcd913dfb68f675740e23eb19bf30c3f1. AST Storage246/Search133/Player161/Magic23/Settings0:115Storage removals, zero additions; other identities unchanged. LegacySearch60 separate. No new device smoke or finalarchitecture closure claim. Counter reset0; AppStyle bounded origin preparation released.


- #212 merged **98cae882**, exact1779088, independent180PASS, exact42-file integration union and allthree CI checks green. Tracking46facades removed; host-51/whole-production-41,14livehostdependencies removed. Actualold-export tick fixture accepted; initial432 analyzer unusedimport failure recorded and corrected to431 without behavior rerun. Did we make a difference? Tracking callers reach their existing domain owner directly; native/auth/coordinator exceptions remain. Third210/211/212 merge triggers fullactual-main gate98cae with AST ledger; Cicero assigned, Locke read-only closeout inventory assigned.


- #211 merged **55f44442**, exact2e894429, independent221PASS, exact50-file integration union and allthree CI checks green. Home37facades removed; host-74/whole-production-64, fourlivehostdependencies removed. Actualpre-refactor Home21-entry fixture retained; no native-sensitive closure claim. Did we make a difference? Callers use the Home owner directly; Tracking #212 remains to integrate. Second production merge since9ae gate.


- #210 merged **2f995724**, exact ab2977f6, independent208PASS and all three CI checks green. Thirty-two Debrify TV forwarders removed; host-69/whole-production-66. Did we make a difference? Existing domain ownership now reaches callers directly. More remains: Home #211 and Tracking #212 are independently accepted but unmerged, native-sensitive obligations stay open.
- **Full 9ae5395a gate PASS WITH NOTE:** 6093PASS/12 exact known/2skip; goldens21 known, no unexpected or unused allowances; analyzer431/449, Python55, layering77. Windows and ARM64 builds passed. Original native attempt exited79 with incomplete test; one isolated origin retry passed, current build passed first try. Cause remains unknown. AST forwarders Storage361/Search133/Player161/Magic23/Settings0 at this gate, before #210. ZIP a9b7fe39ddaac7e17d55c3bb40b78d8c1979fc9f45948392462389f29b64b0a1; APK 0c7c4bd9024be5688db12c6a2b1285767f9ab5eca1b5174aad83317433713eee. No fresh device proof.

- #209 merged **9ae5395a**, exactdeb1, independent108PASS/final16payloadunion/allCIgreen. StremioTV32facades retired;host-70/whole-68/sixlivehostedgesremoved;fourhistoricalcommentrefs notlivecredit. Did we make a difference? Directprefsownership reducescoupling withoutauth/playbackchanges; strict/nativeobligations stayopen. Third207/208/209 triggersfull9aegate. #210independent208PASSnowintegratesmain; #211independent221PASSdepends210. Trackingcandidateheldforhome_tick_sources oldrestoregap, no newproduct.

- #208 merged **4b33d4b2**, exact662d, independent123PASS/exactmainunion/bothCIallgreen. Social31facades retired;host/whole-58/sevenconsumerhostedgesremoved, credential/adult/keys unchanged. Did we make a difference? Directdomainrouting removesrealdependencies; strictownership/nativeexceptions remain. #209 independent108PASSawaitsmainintegration; #210 independent208PASSdepends209. Home37candidate heldforfive-file actualold-export fixture21entries; no productiongrant. Two productionmerges since896, nexttriggersgate.

- #207 merged **3a7ecfdb**, exactf8d1ed8, independent277PASS/allCIgreen/exactmainunion. EighteenQuickPlayfacades retired;host-42/whole-37/two consumerhostdependencies removed. Did we make a difference? Actualcallers now useexistingdomainowner, reducingforwarding instead ofmovinglogicagain; remainingfacades/nativeexceptions stayopen. #208 independent123PASSawaitsmainintegration, #209independent108PASSdepends208; DebrifyTV32facadeproposalorigin208PASSunderreview.

- **Full896a168d gate PASSED:**6093PASS/12exactknown/2skip;goldens21known/configuredretries/helpers0/unexpected0unused0; nativefirstpairPASS;431/449zeroNew/Python55/layer77;Windows+ARM64PASS. SameAST442/133/161/23/0, Storage+17 exact14scalar+1adult+2Indexer; no rebaseline. ZIP700af490c819495b48c7425e966841f68817bf8edbbd1d04e06cae0ba70236ac; APK902c007fd207fc71812628ce93e456ac9d06f7b2202f1b79b2a6440df9f18b50. No freshmanual/device proof.

- #199 merged **896a168d**, exact91640c5c, independent60PASS/finalunion+twoauthorizedunusedimports/freshallCIgreen. Indexer compatibility mapping belongs to one owner; canonicalresourceauthority unchanged. Latestmain host-66 includingtwoimportremovals; originalslicehost-64/whole+29 remainsseparate. Did we make a difference? Real ownership with rawlegacy/canonical quirks pinned; no exportresource/nativeclosure claim. Prior1f049 native600sUNKNOWN thensameheadretryPASS preserved; final916nativepassedfresh. Third204/206/199 merge triggersfull896gate. AllthreeformerlypendingstoragePRs merged; remainingretentions requirefinalexplicitaccounting.

- #206 merged **f2beabf2**, exact367bf307, independent44PASS/exactunion/allCIgreen. Three identical adult-preference helpers now delegate to one compatibility implementation; stricterguard bytes unchanged. Host-13/whole-22/threeforwarders6decl. Did we make a difference? Genuine duplication removed with actualpublicbehavior pins; heldlookup/native gaps stayexplicit. #199 nowreconciles latestmain oncebeforefreshCI; its mergewilltriggerfullgate. Upstreamlocalcatalog56ad independently24PASS, unpublished/zero forkcompletioncredit.

- Fullgate9a2cbb67 PASSED:5981PASS/12known/2skip;goldens21known/configuredretries/helpers0/unexpected0unused0; nativefirstpairPASS;431/449zeroNew/Python55/layer77;Windows+ARM64PASS. Forwarders425/133/161/23/0. ZIP10a39e4448788ab00067e57fa70d46510f6436a549e515ac38f317ff4226f820; APKecb3e9c52ac57eb77ae095b4aa557ff3620b2568cd1a7d775289a0dc34d786c6. No newmanualsmoke.

- #204 merged **f8839dc9**, exact6a953, independent185PASS plus5corrected-adversarialtests/allCIgreen/currentunion. Fourteen scalar methods now belong to three existing owners; host-30/whole+51/14facades retained. Did we make a difference? Domain ownership/7-key old-export coverage improved; native/coordinator/remainingauthority stayexplicit. #206 needsoneimportunion beforefreshCI; #199 attempt2nativePASS(initial600sUNKNOWN retained) needsadditiveowner/sweepintegration, preferablyafter206. Upstreamcatalog test-only24PASS is separatefeasibility, no externalPR/productcredit.

- #203 merged **9a2cbb67**, exactbfb4, independent135PASS/1known plus6path-correctiontests, finalCIallgreen. Shared favourite builder/public primitives remove realFavRow host dependency; host-248/whole+45/fourlazycapabilities. Did we make a difference? Yes: six consumers share one owner; Atrium remains held, Search stage target still638short. CI stale-source-reader failure preserved and narrowlycorrected. Thirdproductionmerge triggersfull9a2gate.

- #192 provider guide merged **d621d936**, exact94932, independentfulltext+two-prose-correctionreview/allCIgreen. Fourcredential surfaces/defaultprovider exceptions documented accurately. Documentation only, no god-line orproductioncounter credit. #204/#206 exactCI nowgreen but heldnextgate; #199 native timeout stillunresolved.

- #205 merged **91325ed4**, exactbff3, independent46PASS/finalunion/allCIgreen. Transport visibility timer/latch/menu state has an owner; host-80/whole+53/fourlazycapabilities and fourborrowedresources. Did we make a difference? Real timer/rearm ownership with publiccontrol pins; full input/scrub/renderer scope staysopen. #203 path-only sourceguard correction awaitsCI; #204 one staleadversarialowner expectation correction authorized; #206 independent44PASS/unionaccepted awaitingCI. Nextproductionmerge triggersfullgate.

- **Full gate42d71343 PASSED:**5938PASS/12exactknown/2skip;goldens21known/configuredretries/helpers0/unexpected0/unused0; nativefirstpairPASS,431/449zero new,Python55,layer77;Windows/ARM64PASS. Forwarders417/133/161/23/0, catalog+2/receiver changes explicit. ZIP33775d136b885649c18ecd2d6db20d6bc1612061b0ca2d300f11b949cb6eb469; APKa7055535e0c863e8d0963d4e34353b02142a54784a804a7def0f5b27796fcd16. No newmanualsmoke.

- #202 merged **6085242c**, exactb26b, independent98PASS/finalfixtureunion/allCIgreen. Device-maintenance owner preserves four global keys and exclusionfixture behavior; host-31/whole+38/eightfacades. Did we make a difference? Yes: support/update preference policy has one owner; remainingadult/scalar/native obligations stayopen. #203 CI tests failed bothruns, Ampere diagnosing; no blindretry. #204/#205 review queued, #199 native timeout unresolved.

- #201 merged **42d71343**, exact74c179, independent44PASS/allCIgreen/cleanexactunion. Speed/aspect/prior-hold and HUD ownership transferred with actual UI/resume consumers; host-124/whole+57/fiveeffectcapabilities. Did we make a difference? Yes: temporary versus persisted speed and aspect state have one owner; renderer, tracker and wider UI obligations remain. Third merge197/200/201 triggers fullactual42d713 gate; workers continue isolated work, no fresh device smoke claimed.

- #200 merged **ab0e7b02**, exact11223, independent121PASS/1knownsidebar and allCIgreen. Canvas actual stage boundary removed; host+33/whole+52,19 direct plus9 existing nested operations retained. Did we make a difference? Yes: six stages now have real widgets; Atrium remains held and final composition open. #203 favourite independent135PASS/1known accepted; integrating newmain beforefreshCI. #201 independently44PASS; transportjointorigin2PASS before authorized limited coordinator move. #202 finalunion/reviewCI pending; scalar batch implementation underway. No fullSearch closure claimed.

- **Full gate9fd6c24f PASSED:** 5906 passes/12 exact known failures/2 skips; goldens21 known with configured retries, helpers0/unexpected0/unused0. Native firstpairPASS; analyzer431/449 zero new; Python55; layer77 unchanged; Windows/ARM64 buildsPASS. Forwarders Storage415/Search133/Player161/Magic23/Settings0; Storage+4 keyboard accessors explicitly counted. No fresh manual smoke. ZIP SHA5ae464f5f54c5c531a7b1a5ab2f93ece983b3672d7533cd808fff23d5cfba6eb; APK987468971513aac4133e2cab451938b850781218d6142d6052ec67f852a56222.

- #197 merged **618659a5**, exact83b6, independent88PASS/finalunion/allCIgreen. Catalog preference owner preserves raw-key/order/restore behavior; host-25/whole+21/twofacades retained. Did we make a difference? Real ownership with old-export proof; scalar/device/indexer and remaining authority still open. #199 native600s timeout remains held with unknown cause. #200/#201/#202 independently accepted pending CI/integration; #203 favourite review queued.

- #198 merged **9fd6c24f**, exact reviewed3641057, both CI runs fully passed. Actual Promenade stage boundary extracted, independent117PASS/1knownsidebar; host+38/whole+49,20bindings retained. Did we make a difference? Yes: another stage is independent of the host library; Canvas/Atrium/final composition remain. Third production merge triggers full integrated gate. #197 CI green held for gate; #199 native CI failed and is under log diagnosis, no blind retry. #201 player independent44PASS; #202 device review queued/running; #200 integration follows merged198.

- #194 merged **c60f3f1f**, exact reviewed bede8cf, all three CI checks passed. Keyboard preferences use AppStylePrefs with one cache and unchanged reset/migration behavior. Independent 101 tests passed; host -37, whole production +13; compatibility cache accessors retained. Did we make a difference? Yes: ownership is explicit with old-export fixtures; broader storage and native warmup remain. #197 needs an additive fixture/registry union; #199 import conflict must be resolved to start CI. Next production merge triggers a full gate.

- #196 merged **7f3e55bb**, exact reviewed head d11a39f, after all CI passed. Actual Mosaic stage boundary removed; host +11, whole production +45, 17 bindings retained. Independent 114 passed /1 exact known sidebar failure. Did we make a difference? Yes: a real stage no longer depends on the host library; cell ownership and final Search composition remain. #198 must reconcile its merged dependency before landing.

- **Full gate dcdc8385 PASS:** 5,870 passed /12 exact known failures /2 skipped; goldens21 exact known failures with existing configured retries. Actual helpers exit0, unexpected0/unused0; raw failures retained, not pixel-green. Native original/current first pair passed; analyzer431/449 zero errors/new; Python55; layering77/77 unchanged. Windows and ARM64 builds passed. Report: `debrify-c0-post-193-195-191-gate/.dart_tool/main-gate/REPORT.md`. ZIP SHA256 `f1359ee4ec8c715c6fde7f0800802b5ec31661359ba6eba866f5e65aa2105c0b`; APK `bc66beda3ed7d037baeac19205bb6adf95df5c05b9db9d9bf5b96198a486b7bf`. No fresh device/manual smoke claimed.


- #191 mergeddcdc8385 exacte522 after independent113PASS/allCIgreen and final10blob/CODEMAPunion. FourAmbientfacades retired,52callerreceivers directowner, hostminus15/wholeminus10; enumexportcompat retained. Did we make a difference? Callers use actualowner with unchangedarguments/order; Storage stillhasidentifiedpolicygroups, notclosed.

- #195 mergedac221c4b exactcb3 after independent122PASS/1knownsidebar, allCIgreen/10ownedblob+CODEMAPunion. ActualDeckStateextension removed, sharedpublicvisuals owner; hostminus23 wholeplus105.22bindings/twolazynativeconstructors retained,4stagepartsleft. Did we make a difference? Removed private stage/library dependency with actualconsumer evidence; remainingstages/composition stillopen.

- #193 merged a749842f exact2e0a after independent34PASS, exactbody/mainunion and allCIgreen. Diagnostic timer/token/params/signature ownership extracted; host minus191, wholeproduction plus61 (priorseam+43 separate). Six live capabilities and host renderer/generation remain. Did we make a difference? Real diagnostic state leaves host with pinned async quirks; full renderer/recreation remains open.

- Full gate334145c6 PASS:5868success/12exactknown/2skip, goldens21known/configuredretries, rawfailuresretained/helpers0/unexpected0/unused0. NativefirstpairPASS, analyzer431/4490new,Python55,layer77/77. WindowsZIP SHA5cf0d9c642e2d8099e2d2a41150db5c462b317c6b7aeec5106357afcebfbff2e; ARM64 SHA4d8b2479cde1379177857e85bc11d08192628a685497529421e4ce29d543e241. AST415/133/161/23/0 (legacySearch60); single-line143/117/112/12/0 unchanged. No new manual/device proof.

- #189 merged334145c6 exactb6 after independent107PASS/1exactknownsidebarfailure, allCIgreen and final5blob/CODEMAP union review. SharedDeck/Tonight cell owner removes71host lines, wholeproduction plus49; tenliveoperations and labeladapter retained. Did we make a difference? Two consumers share actual cell policy; wholeDeck/sharedvisual work remains, no stage-target closure.

- #190 merged e9e182bd exactc73 after independent production1case plus read-only six-case test delta (author7PASS), final3blob union and allCIgreen. Three synchronous terminal operations preserve original defaults/order; wholeproduction plus43/host plus1, no decoder extraction. Did we make a difference? Actual host timing/error/generation behavior is testable before193 movement; no native/Android proof claimed.

- Full gate e78d100e PASS:5824success/12known/2skip, goldens21known with configuredretries, helpers0/unexpected0/unused0, rawfailures retained. Analyzer431/4490new,Python55,layer77/77,nativefirstpairPASS. WindowsZIP SHA03faf3871a40cceaa74dd96cb8447f131ab18e4716aca435d8767dd5aad223fc; ARM64 SHA1a54aca15061b55807386c3a5897809c85afda16fc36f19397033e88ed5119d4. SameAST total/single: Storage411/143,Search133/117,Player161/112,Magic23/12,Settings0/0. Gate includes186184185188; no fresh device smoke claimed.
- #187 merged6e7d97b2 exact9a46 after independent113 and finalunion/allCIgreen: Ambient owner preserves four-key restore behavior and enum compatibility. Host minus69 including docs; wholeproduction plus32; fourfacades retained pending191. Did we make a difference? Explicit domain ownership with old-export evidence; Storage outcome remains open.

- #185 merged e78d100e exact3b02 after independent106 and accepted main union/allCI green: seven download facades retired, host minus18/whole production minus17. Did we make a difference? Actual callers use the download preference owner; native transport unchanged, wider storage work remains.
- #188 canonical engineering rules merged before185, exactcad2 parent-reviewed/allCI green. Ten rules and six safety bullets preserved, editor pointers retain triggers. Q3 consolidation delivered; not whole Q-phase closure. God lines unchanged by188.

- #184 merged64a10b59 exact562869 after independent106 tests and final integration acceptance/allCI green. Download destination preference owner preserves three profile keys and actual pre-refactor exclusion fixture. Host minus21, whole production plus40, seven facades retained. Did we make a difference? Preference ownership is explicit with restore evidence; caller retirement185 is next, no native SAF/permission proof claimed.

- #186 merged93c966cc exact301325: independent88 cases and final union review, allCI green. Three captured-key operations at ten consumers now use typed provider capabilities, preserving captured keys/live timing. Whole production plus26, host zero reduction, provider leaves627. Did we make a difference? Yes: actual provider calls follow the contract; integrated acceptance remains, not another autonomy framework.

- Full gate a6bc820b PASS: generic5794 passes/12 known failures/2 skips, goldens21 known errors after configured retries; helpers0, unexpected0/unused0. Analyzer431/449 zeroerrors/new, layering77/77, Python55, strict original/current native first-pairPASS. Windows181.8s and ARM64132.1s passed. No fresh device smoke. Same AST forwarders Storage411/143, Search133/117, Player161/112, Magic23/12, Settings0/0; Settings physical2903 corrects prior stale2901.
- Gate artifacts: Windows ZIP SHA256 7f14dd42cc545eca3a5e40b829088e6a569d47b0180cbca50a3bcae6e7df7671; ARM64 APK 457d7ffdde2bb797fb73d033e264acc72e9a19fccc0e49615e0d178acbfcccf1. Full report in debrify-c0-post-181-182-next-gate/.dart_tool/main-gate/REPORT.md.

- #183 merged a6bc820b exactddef53de: independent156 passes and allCI green; eleven history/watchlist facades retired. Storage host minus27, whole production minus22. Did we make a difference? Real callers use domain owners directly; more storage ownership and eligible facade retirement remains.

- #182 merged56788ddb exactdf41 after independent199PASS and allCIaccepted. Native attempt1 hung600s without assertion; one authorized same-head/runtime/test retry passed both origin/current. Cause remains UNKNOWN, original evidence retained; not first-pass green. Host−20/wholeproduction−19, ten facades retired. Did we make a difference? Actual callers now use the existing owner directly; remaining storage/Q-phase work stays open.


- #180 history owner merged95c93: host−44, whole production+34, five facades retained. Actual old-export restore evidence and independent87 cases passed.
- Full gate95c93 PASSED: generic5,789 passes/12 known failures/2 skips; goldens21 known errors after configured retries. Both helpers0, no unexpected or unused failure allowances. Not pixel-green.
- Gate pinned analyzer431/449, zero errors/new issues; layering77→77; Python55 passed; originalbc46/current native pair passed first try. Initial wrong-PATH analyzer output retained separately and corrected using pinned SDK; no baseline edit.
- Windows226.2s/68files and ARM64171.9s builds passed. ZIP SHA256b96b7a4bd0b98a4f9de799ef3242bebf18a150d3c49c0113ad0566d10f1d729f; APK80811b556495c20078920091643b91cbcde5bc236d89737bd3bed7d1479e8cb5. No fresh manual/device smoke claimed.
- #181 BoardCell mergedc7a332bd exact932 after independent140 passes plus the exact known sidebar failure, final integration review and all3CI green. Shared renderer owns card state/shuttle; 669 declaration lines relocated, whole production+17, zero host-file reduction. Did we make a difference? Removed private host-library access at real consumers; remaining stage navigation/composition is still open.
- Production merge counter: **3 since completed gate896a168d** (#207, #208, #209). Full gate9ae5395a assigned; further production merges held. Docs192 does not increment the counter.

### Forwarders at the latest full gate9fd6c24f

- Storage415/143 single-line; Search133/117; Player161/112; Magic23/12; Settings0/0. Legacy Search60 separate. Storage+4 is keyboard accessors added in194, no classifier change.

### Decisions, limits and recovery

- Green actual-origin evidence before move, one combined PR/final review cycle. No duplicate independent test-only reruns, whole-god-file formatting, persistence changes or baseline inflation.
- Parent alone edits BOARD/NOTES. CODEMAP serialized. Only exact scoped worker files may change.
- Git incident: sharedconfig/FETCH_HEAD and newQ2worktree index/sample files contained NULs. User authorized recovery. Damaged files preserved under .git/recovery-20260906-001041; affected worktree quarantined. Minimal config reconstructed, not original branch settings restored; use explicit remote/branch. Git connectivity and gate tracked-file scans passed; cause unknown.
- PR112/109/56 remain parked. Future unresponsive playback fallback remains future-only. No disk/power/startup-performance changes.
- No defensible whole-project hours/quota estimate. Bounded lane estimates are provisional; unestimated work is not zero.

## Prior checkpoints and retained evidence


Updated 2026-09-05 after main `d5f8dc4b` (CW merge `e478635e`). Orchestrator owns this board and NOTES. Binding contracts: [original plan](REFACTOR_PLAN.md), [Phase 2 correction](REFACTOR_PLAN_PHASE2.md), and latest explicit user decisions below. Historical snapshots remain in Git history; they are not current assignments.

## Historical roadmap (superseded by current roadmap above)

### Active worker dispatch — latest
- Wegener: Tonight exact extraction boundary after green origin pins; implementation grant next.
- Ampere: remaining RD/AD/PikPak watch-flow programme scope on frozen175; no overlapping production edits.
- Locke: next remaining application/device storage-policy scope on frozen174; no overlapping production edits.
- Cicero: verify174/175 merge unions/order and prepare next required integrated gate; run only after third production merge.
- PR174 and175 independently accepted; tests/goldens still running, native checks passed. Existing PR heads stay frozen.
### Working now
- User authorized continued extraction without manual smoke. Temporary automatic-sleep prevention verified: helper PID3412, expires 2026-09-05 16:43 UTC; permanent power settings unchanged.
- [ ] **Cicero — native CI plan:** CW automated mini-gate complete; final114 independent19case verification complete. Planning mandatory native runtime CI for draft116, no workflow edits yet.
- [ ] **Wegener — keyword update audit:** keyword pin complete ee9de82b; opening corrective PR, then G1'-5 favourites rows assigned on refactor/g1-5-favourites-rows. Ampere independently reviews pin.
- [ ] **Ampere — player origin proof:** native audio mount/dispose, identify cancel and disposal checkpoint write proven oldest/current with mutation. Draft116 open; native CI/analyzer dependency unresolved. keyword independent review assigned, then M1-3 assigned on refactor/m1-3-provider-watch-flows; exact file locks due before edits. No full V1 closure.
- [ ] **Locke — storage fixtures (#114):** 141/141 admitted keys and28/28 exclusions complete; all5 dynamic families finitely sampled (21keys). Exact final `3e30de17` independent19case review passed; merged c5f022de; final CI passed. S2-6 origin characterization assigned on refactor/s2-6-playback-progress-store; 114 merged; extraction authorized after green origin pins. Forecast1750–1950 net vs2300 target; no padding, deficit recorded below.

### Next, in order
- [x] Finish current merged-code automated mini-gate.
- [ ] Manual smoke explicitly deferred by user at 09:44 UTC September 5: proceed with eligible lanes without it. Automated gates remain mandatory; no manual pass claimed (SHIELD unavailable).
- [x] #114 merged c5f022de: independent19 tests and exact-head test/goldens passed. Dynamic families are finite samples, never exhaustive suffix coverage.
- [ ] Resolve remaining origin-test debt and keyword audit without speculative fixes or expanding native scope.
- [x] Map upstream strategy before more divergence: upstream `db440a8d`, fork at `0d4ca1a2` was 385 ahead/0 behind. Existing upstream PRs #55 then #54 then #56 must refresh/test sequentially; pairwise conflicts identified. No bulk fork submission or upstream messages sent.
- [ ] Resume eligible sequential slices only after their gates: Search G1'-5..9, Player V1-6..10, Magic TV M1-3..6, Storage S2-6..7.
- [ ] Q1 layering enforcement; Q2 remove expired forwarders and migrate callers; Q3 engineering-rule consolidation.

### Completed this correction round
- [x] #108 Windows source guards: 21 independently reproduced tests, clean analysis.
- [x] #111 M1 dependency correction: seven invalid imports removed; 65 targeted and 40 pre-move tests independently reproduced.
- [x] #110 Windows analyzer launcher + upstream Flutter pin + restored layering ceiling 77. Full corrective suite and both native builds passed.
- [x] #113 roadmap/decisions merged; board updates now committed directly to main, docs only.
- [x] #115 M1 retrospective proof: nine live origin/current tests, mutation-sensitive. Does not retroactively satisfy pin-before-move chronology.
- [x] #96 CW integration: independent disposal/rebuild tests, compatible merged-main layering, exact-head test/goldens green. #104/#105/#107 closed as duplicates; their patches are preserved in #96.
- [x] SDK/JDK installed outside repository; Android license explicitly accepted. No persistent global PATH changes.

### Blocked or parked
- [ ] SHIELD smoke: hardware unavailable. Phone testing is not a substitute pass.
- [ ] Current merged-build manual smoke deferred by explicit user decision; no longer blocks extraction. No manual pass claimed.
- [ ] Remaining V1 origin behavior coverage: real player test feasibility underway; source scans/copied bodies do not clear it.
- [x] #114 coverage review and CI complete; merged.
- **Parked:** #112 backup decoder (feature scope creep), #109 test kit (outside assigned lane), #56 Qwen helper (Phase 3). No product work on #112.

## Exclusive active ownership

| Work | Status | Branch / checkout | Owner | Writable scope | Next dependency |
|---|---|---|---|---|---|
| Current G1 mini-gate | automated complete; manual deferred | detached `e478635e`, `debrify-c0-g1-main-gate` | Cicero | no tracked edits; verification/artifacts only | tests/builds, then device smoke |
| Keyword duplicate-update audit | in-progress | current main / read-only | Wegener | no edits assigned | evidence before any correction |
| V1 origin-host proof | in-progress | `refactor/v1-origin-host-pin` | Ampere | new `test/video_player_origin_behavior_test.dart` only | bounded native-audio feasibility, no production seams |
| S2 origin restore fixtures | in-progress | `codex/storage-origin-restore-fixture` | Locke | `test/storage_origin_restore_fixture_test.dart`, `test/fixtures/storage_origin_restore/**` | final domain, independent review and CI |
| Orchestration | in-progress | `codex/orchestrator-gate3` synced to main | parent | BOARD + NOTES only | respond to worker events; merge verified results |

No worker starts another lane independently. Workers report completion/blockers directly; parent handles review, decisions and reassignment. Hourly fallback only; no worker polling timers. Corrective wave width: four workers.

## Gate evidence

| Gate | Exact source | Analyzer / layering | Full suite | Windows / Android | Status |
|---|---|---|---|---|---|
| Gate 3 user audit | `843d631b`, Windows Flutter 3.47.2 | 471 issues, zero errors; layering 84 unique | 5143 pass / 37 fail (33 baseline + 4 Windows guards) | user reported both pass | accepted with notes, historical report |
| Corrective integration | `0abc4c8`, tree identical to #110 `8bd40543`; Flutter 3.44.8 | 454 issues, zero new against unchanged 470-entry baseline; layering 77, delta zero vs #72 | 5168 pass / 33 exact allowlisted / 2 skip; zero unexpected or unused | Windows pass 127.4s; ARM64 APK pass 384.8s | automated gate passed; not current CW/manual proof |
| CW merge check | #96 `3961eee5`; merged tree `fd9b5b6` | 77/ceiling77; no added analyzer allowance, one location relocation | independent 3 disposal/rebuild tests pass; targeted worker evidence + exact-head CI test/goldens pass | prior builds do not cover this new tree | merge conditions passed |
| Current CW mini-gate | actual merged main `e478635e`, tree `fd9b5b6` |454/no new;77layering,no delta |5199pass/33exactallowlisted/2skip,zero unexpected/unused |Windows pass130.4s;Android ARM64 pass97.5s | manual smoke pending |

Flutter follows upstream: **3.44.8**, verified upstream workflow blob `2a48503bcf470fef4affcc606182c90444855511`. Separate local SDK used; no automatic golden regeneration or diagnostic rebaseline. Layering ceiling is **77** from #72, not historical 90. Current analyzer baseline has 470 entries; historical 466 diagnostic count is not its replacement.

## Size and debt accounting

| God file | Original board baseline | Phase 2 baseline | Current after #96 | Phase 2 target |
|---|---:|---:|---:|---:|
| search_screen.dart | 19070 | 17039 | 11376 | 7500 |
| video_player_screen.dart | 16278 | 15771 | 11926 | 9500 |
| magic_tv_screen.dart | 10716 | 10752 | 8369 | 4500 |
| storage_service.dart | 9963 | 9634 | 6282 | 2800 |
| settings_screen.dart | 7905 | 3107 | 2899 | 3000 |

Host Leaves are not repository shrinkage. #96 Leaves 1732; production/test/scaffold accounting belongs in its PR. #100/#102 screen-layer relocations earn no second extraction credit: V1-1 666, V1-2 527, V1-3 943, V1-4 704, V1-5 1008 are historical host reductions, not proof of pure logic separation.

Shortfalls: S2-1 869, S2-2 325, S2-3 533 assigned S2-7; avoid counting later slices twice. V1-2 shortfall173 remains subject to explicit accounting; a later lane exceeding its own target by43 does not alone prove173 cleared. Temporary forwarders: G1'-9, S2-7, and final Q2 caller migration/removal before Phase3 completion. M1 inherited63physical/34nonblank adapter lines retained for correction: dialog hooks M1-5; full seam review/removal M1-6. #96 duplicate-listener allegation disproven; required host listener retained. #90 keyword allegation is a separate live audit.

## Budget

- **16 extraction slices remain:** Search5, Player5, MagicTV4, Storage2; plus **3 Phase3 lane groups**. Q2 can require several area PRs.
- Additional work: current mini-gate, S2 fixture completion, bounded V1/M1 evidence and upstream/device validation. Planning range roughly **4–7 corrective/validation work packages**, not guaranteed PR or time counts.
- Account snapshot 2026-09-05: **26% used /74% remaining weekly quota**. Account-wide, not project-only. No measured per-task tokens or reliable quota-per-lane estimate; refresh after three-slice gates. No credit redemption authorized.
- Fixture estimate initially8–14focused hours; completed-domain checkpoints roughly4–9minutes each, not linear estimates for conditional/family work. Track actual checkpoints rather than invent a completion date.
- #96 disposal cap completed: deterministic guard mutation plus one final SDK verification passed. No further pin-design attempts authorized.
- V1 probes hard-capped by assignment; stop on unavailable seams rather than widen. Every PR retains **Did we make a difference?** and **Is there more we could do?**.

## Decisions and history

Aim to contribute upstream, not a permanent fork. Upstream refresh ordering precedes further contribution publication. Scope exclusions and preserved quirks are in [REFACTOR_NOTES.md](REFACTOR_NOTES.md). Historical lane rows and old gate snapshots are available in Git history; they must not override this current board. Phase0/Phase1 registries and corrective follow-ups merged; old G1/G3/G5 work was superseded by the binding Phase2 plan. New lane assignments must use its exact owned files and gates.

## Latest assignment decisions — 2026-09-05 09:44 UTC

Manual smoke is deferred by explicit user instruction; continue eligible work. C0 owns native CI116; Wegener owns G1'-5 host/favourites files after corrective pin PR; Ampere reviews keyword pin then owns M1-3 watch-flow files; Locke owns S2-6 storage files;114 merged. Workers must confirm exact paths before edits. Shared CODEMAP edits require serialized ownership. No ownership of each other's host files.

S2-6 functional scope retained, forecast1750–1950 net against original2300:350–550 potential deficit is outstanding debt pending exact overlap accounting and clearing slice S2-7/Q2; no automatic target waiver or double credit for already-extracted TV/reset code. Origin pins proceed now. Manual testing remains unproven.

### Merge114 — 2026-09-05
Exact head3e30de17 verified CI test/goldens SUCCESS; independent19case reproduction passed. Merged c5f022de. Difference: real pre-refactor export/current restore compatibility pins for141 named keys,28 exclusions and finite5family samples. More: conditional/dynamic domains remain finite and each new storage slice must pin its own behavior. S2-6 unblocked; other active lanes share no changed production files with114. God counts unchanged from current table (test/fixture-only merge).

S2-6 ownership extension: Locke exclusively owns test/storage_key_sweep_test.dart import/store-discovery/exact-alias additions; assertions must not weaken. CODEMAP storage-routing rows exclusively locked to Locke until commit/release. Current extraction reports1867 net Leaves,433 uncredited deficit. Independent review still required. C0 authorized fast-forward PR116 to24dc0dcb; native Linux execution required before merge.


G1'-5 destination decision approved: lib/screens/search/fav_rows_controller.dart and fav_row.dart retain Flutter/focus ownership in screen layer; no new service-layer UI dependency. Wegener starts real-origin pins now; CODEMAP waits only at completion (Locke owns current lock). C0 independent S2-6 checkpoint review assigned while native CI116 executes. PR117 test passed, goldens pending; independent keyword review complete. Awake helper3412 verified running.


S2-6 draft PR118 published, frozen609b823550034d58b58dc00127be2067c4ee50e7. C0 independent review active; Locke holding branch stable. Worker reports104core+120consumer+9sweep+12allowlist passes,cleananalysis,77layering; not parent gate credit until reproduced.1867Leaves/433uncredited debt. All67bodydiffs and70method inventory included in PR. CODEMAP lock released. M1-3 quickwatch835line mapping accepted in scope; origin21cases green, sensitivity/pincommit precede move.


PR117 merged a0569745 exactee9de82b after independent live-host pin1pass/cleananalysis and CItest/goldensSUCCESS. Difference: tested selection notification coalesces to1host+1child,noextra-frame build; no duplicate-child fix warranted. More: does not cover every asynchronous sequence or prove both listeners necessary. God-file counts unchanged (test-only). G1'-5 neighbouring search lane should integrate before final gate; no production overlap. PR118 independent reproduction complete,CIpending; no merge yet.


M1-3 decision: Ampere owns narrow cloud_magic_tv_unlock_pin_test.dart host+sixflow inventory/exactcaptured-keyalias update; preserve assertions, no broad exemptions, source checks supplemental only. Tenentrywrappers+100physical typedbinding retained for credential timing;reviewM1-5,expiryreview/removalM1-6. Reported3070net pendingfinalaudit (3226grossminus156). CODEMAP MagicTV rows exclusively locked to Ampere untilcommit/release. Baselinegrowth forbidden; C0 only location reconciliation with evidence.


MERGED1188ecc6323 and116532fd360: exactheadCIgreen; S2 independent104/120/9/12checks+analysis/bodycomparison passed.116origin/current Linuxnative1each no skips, parent runner5tests passed. Difference: playbackstorage logic extracted with frozenkeys, mandatorynative origin/current gate added. More:433storageLeavesdebt, fullvideo readiness/manualsmoke unproven. Current godcounts search11376,player11926,magic8369,storage4415,settings2899 versus original19070/16278/10716/9963/7905. S2-7 readiness/originpins assignedLocke; exactstorelocks beforeedits. M1/G1 active branches must integrate newnativeCI beforefinalgate. C0 owns M1baseline mapping. Remaining extraction slices15 (S2-6merged).


S2-7 Locke owns exact app_style_prefs.dart and home_prefs.dart phasedhooks plusstoragehost/neworigin test; preserve interleaving/capturedprefs. Productmove waits concrete API/net review: actualmigration~72lines cannot meet400; no scopepadding or433debt doublecredit. M1-3 C0 baseline decision approved470to454:13exactseverity/code/message locationmatches,16observeddisappeared. Fullanalyzer454to438.12asynccontext warnings hidden through bindings are NOT asyncsafety improvement. C0 baselineonly commit then119integration/nativeCI.


119 corrected headf8bd6ce44 independent review inprogress; exact newCI required.20guard adversarialcases plus62lane passed worker, no production/baseline relaxation. Locke residual audit complete1565above storage target=783explicit+782other; proposed followons recordedNOTES, not assigned before automatedmini-gate. C0 will run actualmergedmain fullgate after119merge. CODEMAPfree.


119merged9958dd1e afterexactf8bd6ce4 all3CIgreen+independent82pass. Difference:3070hostlines removed into typedproviderwatchflows; capturedkey/cancel quirks pinned. More:thinbindings+wrappers retained expiryM1-6, contextdiagnosticvisibility notasyncsafety proof. Godmagic8369to5299 vsoriginal10716; othercurrentcounts unchanged. Fullautomatedgate nowactive, manualdeferred.


## Automated gate passed — actualmain9958dd1e, treee6b0e8a1
Pinned3.44.8/JDK21: generic5263pass/12exactknownfailures/2skip;goldens21exactknownerrors after2retries;0new/unused. Nativeorigin/current1each0skip. Analyzer438/454,0errors/0new;Python55;layering77delta0. Windows167.1s/Android113.2s buildsPASS. Evidence C:/Users/hunth/debrify/debrify-c0-main-9958-gate/.dart_tool/main-gate/gate-summary.json. Manualdeferred NOTpassed. M1-4productmove nowauthorized;C0V1-6readiness/originpins assigned onrefactor/v1-6-decoder-diagnostics. Exactpaths/seamsbeforeedits.


M1-4 draft122 head91dadec1 (move6d296c59,pin8efdeaba) independentLockereview/CIpending.780net reported815-35;7wrappersreviewM1-5/expiryM1-6. ActualAndroidpositive remainsunproven; keytestholdskeythroughprepare, exactcooldowncapturetiming sourcepreserved nottested. CommittedLFpin400162d5 exact6origin/currentpass; earlier79eCRLFhashsuperseded. CODEMAPreleasedAmpere. G15 integrated96cd6acc/docsa069b13e; docslockreleased,publicationpendingworkerreport. V16purediagnostics direction approved hostUIrecreationretained;450targetmaymiss, no directoryrelocationfornumbers. C0testonlynativevideo feasibility45min; productionIOseamneeds exactdecision.


PR121merged1274476d exact96cd6acc afterLocke187/origin9/body52+C0integration12pass/all3CIgreen. Difference:favourites/focus ownership extracted,1363net (search11376to10013). More:runtimeedgegaps+remainingsearch2513above7500target; no purelogiccreditforUIcontroller. Godcurrentsearch10013/player11926/magic5299/storage4365/settings2899; originals19070/16278/10716/9963/7905. WegenerG1'-6hero assigned freshrefactor/g1-6-hero-presenter,target550,originpinsbeforemove. V16pausednativefixture,nofailedscaffoldmerge.122independentreviewPASS/nativeCIpassed,otherspending. Slice1since9958fullgate.


122merged2bbd9f6d and123397398d5 afterexactall3CIgreen+independent107/47checks/originbodyproofs. Difference:780MagicTV+732searchhostLeaves, dedicatedchannel/hero ownership. More:Androidpositive unproven,7channelwrappersM1-6/21heroaliasesG1'-8 expiry; fullnextgateactiveactual397398d5. Currentcounts9281/11926/4519/4365/2899 vsoriginal19070/16278/10716/9963/7905. No manualpassclaim.


## Full automated gate passed: actualmain397398d5/tree65c50171
Generic5283pass/12exacthistorical/2skip;goldens21exacthistorical after2retries;no unexpected/unused. Native1origin+1current/0skip. Analyzer438/454no new;Python55;layer77normalpass+delta0 firstparent/premerge. Windows158.1s/Android104.2s PASS. Evidence C:/Users/hunth/debrify/debrify-c0-main-3973-gate/.dart_tool/main-gate/gate-summary.json; manualdeferred,video readinessunproven. M15productwaitsgreenpin+typeddesignonly. G17origin6realcases/62suiteindependentlyPASS; standalonecontract stillrequired. C0availableindependentreview, V16paused.


124wordingcorrection merged afterexact192626d6all3CIgreen+C0sixpins/difftruthreview. Difference: evidence accuratelylimitsdesktophostcoverage, no behaviorchange orhostLeaves. More:Androidhosttrue/bridge/onFinished stillunproven.125reviewaccepted currentcaller semantics,CIpending.126C0review124PASS/9origin/body3 passed; baseline56df5520 minimalprovenancerepair suppliedowner forfreshCI. M15apartial448/202remaining; M15bactualstateownershipproposal only, nocallbackbag.


125merged afterexact99c12bb6all3CIgreen+independent76/8origin/currentcallerreview. Difference:purewatchlist read/partition sharedwithoutFavUIdependency;0hostLeaves/0Discover750credit. More:extraasync/allocationdelta andsharedholdorderinggapexplicit. WegenernextnarrowDiscoverdata/sessionproposal assigned;126waitingtest/goldens,nativePASS exact6c5380d7. No userwait.


126mergedc35c41c1 exact6c5380d7all3CIgreen+C0independentreview/integration. Difference:editor/sharedchip448hostLeaves,Addhelper/chip1000limit actualoriginpin;settingsremain202target. More:pendingSAVE dedupguardunproven,11linefacadeM1-6expiry,remainingstateownershipnowassigned. Currentgod9281/11926/4071/4365/2899 vsoriginal19070/16278/10716/9963/7905. Secondproductionprerequisite since397gate(125,126);nextafterG17bfullgate.


127mergedce73f802 correctedc1674faa all3CIgreen+Locke81/sourceconditionalreview: empty/allinvalidsyncmapclear restored, nonemptyextraasyncboundary remainsdeclared.128merged04264596 all3CIgreen+independentmetadata4rowaudit/16tests;454count/identitymultisetunchanged. Difference: Discoverbounddata prerequisite now preservesemptytiming; historicalanalyzerprovenance repaired. More:0Discover750credit, realaction/lifecycleowner stillneeded. Lockefullactual04264596gateassigned afterthirdprod125126127; C0129review+approved9relocations/2visibilityremovals pendingintegration. Currentgodsearch9268/player11926/magic4071/storage4365/settings2899;13boundhostlinesno750credit.


## Full automated gate PASS actual04264596/treef88985eb
Generic5307pass/12exactknown/2skip;goldens21exactknown;0unexpected/unused,rawfalse/effective0 unchangedallowlist. Strictnative1+1/0skip;analyzer438/454no new;layer77delta0;Python55;Windows+AndroidbuildsPASS. Evidence C:/Users/hunth/debrify/debrify-locke-main-0426-gate/.dart_tool/main-gate/REPORT.md. Manualdeferred,no nativepositiveclaim. G17clifecycleproductreleasedaftergreen2539fc5c;C0originreviewactive.129integrated24ba72f3 CIpending/reviewpassed. No userwait.



#130 merged5232013a exactcf38a3e7: lifecycle owns presentation resources and cleanup; 143 net host lines, production net+1. Difference: explicit resource lifetime with actual-origin pins; more: 14 aliases/focus forwarder expire realG17/Q2, Discover still not standalone. First production slice since full04264596gate. #129 correction4ab8e1c independent review/newCI pending; exact new renderer added to shape inventory,490floor unchanged. G17d only test/discover_playback_selection_origin_test.dart writable; routefactory/IOseam decision required before product edits.

129merged78be96c1 exact4ab8e1c afterall3CIgreen+independentreview. Difference:18settingsfields nowowned bystate, renderer extracted,412hostLeaves; combinedM15=860. More:18aliases/realUIboundaries remain expiryM1-6/Q2, noAndroidpositive proof. Secondproductionmerge since04264596gate; nextthirdproductionrequiresfullgate. C0shapehardening authorized2testfilesonly; M16neworigin-test-only feasibility; Locke G17d20caseindependentreview. No userwait.

G17d scope decision: Wegener exclusively owns two terminal testing hooks in video_player_launcher.dart (existing route widget builder only) and external_player_service.dart (Windows explorer.exe Process.run only), plus discover_playback_selection_origin_test.dart. Independent design approved; preserve real routing/persistence/bridge/lifecycle and default behavior. Separate seam/pin commit before any move; no TPS/host/bridge edits. Windows-only process evidence explicitly limited, no native proof. M16 race/failure origin pins active; Locke independent origin review next. C0 owns shape test/oneallowlist identity; scopes disjoint.


M16 move authorized after independent ac667f9d fourteen-test origin proof: exact host/new queue_prefetcher service/provider_watch_flow interface import only. Two source-inventory tests may add exact destination path without weaker assertions. Real queue/set/settings identity, request timing, late completion and failure rotation preserved. No alias/dead-slot cleanup in this move. Estimate228 code/declaration net vs230 target, physical255 includes27oldcomments/separators; actual audit required. CODEMAP not yet locked. Third production merge since04264596 triggers full integrated gate. G17d terminal proof3b36abd4 under Locke independent review; no selection move yet.


131mergedc6a3de16 exacte767b980 all3CIgreen+independent8effectiveorigin/currentmutationcases. Difference: per-file shape failures and separateexisting-sidebar cap stopnewviolations beingmasked byhistoricalaggregateallowance. Oneallowanceidentity migrated, no growth/floorchange/productLeaves. C0availableM16review/nextfullgate. Currentgod9126/11926/3659/4365/2899 vsoriginal19070/16278/10716/9963/7905. G17d55independentPASS, fixturefinallyhardening+latestmainintegration beforedraft; no selectionmove. Nextproductionmerge triggersfullgate, includingtestingseams iftheymergefirst.


132mergedabc74484 exact57a07bb8 afterindependent55/defaults/cleanupreview+all3CIgreen. Difference: terminal IO hooks enable real Discover playback orchestration pins; no nativeexecution/hostLeavesclaim. SixWindows-only cases explicit. Thirdproductionslice since04264596: C0 fullactualabc74484 gate assigned after133deltaaudit, manualdeferred. 133integrated67a0f5c9 finalreview/CI pending, mergehelduntilfullgatepasses; no nextproductlane. Godcountsunchanged9126/11926/3659/4365/2899.


## Full automated gate PASS abc74484/tree37dc3fa5
Generic5404pass/12exactknown/2skip;goldens21exactknown after2configuredretries;no unexpected/unused. Native1+1/0skip;analyzer436/452no new;layer77delta0;Python55. Windows+ARM64buildsPASS withchecksums in debrify-c0-main-abc7-gate/.dart_tool/main-gate/REPORT.md andgate-manifest.json. Manualdeferred NOTpassed. 133onlygoldenCIpending exact67a0f5c9; allothermergeconditionspassed. G17e selectionartorigin test-only authorizednewbranch; no productmove, no extraIOhooks. Locke architecture review, C0gatecompleteavailable.

133mergedb3d06549 exact67a0f5c9 afterindependent135/body/state/integration/all3CIgreen andfullabc744gate. Difference: QueuePrefetcher owns backgroundlockedpreparation/state/sharedADresult, preservinglatecompletion/failuretail andlistidentity. 256physicalhostLeaves,228code/declarationnet(two-short230),wholeproduction+51. No expirycleanupcredit. Firstproductionafterabc744gate. Ampereexpiryclosureproposalread-only; LockeG17e58origin/reviseddesignreview; Wegenerpin828de2ce frozen/noownermove. God9126/11926/3403/4365/2899 versusoriginal19070/16278/10716/9963/7905. No userwait.

G17e revised bounded owner move authorized after independent828de2ce58originPASS. Exact newselection_playback_owner/searchhostdeclaredhunks/partSourcesfactory only. Host retains async listener lifecycle and empty-browse entry guard before context; resolver stayshost. Owner futures returned directly, route lookup/read timing preserved. Two substantive adapters >10lines explicitly accepted untilrealG17/Q2; legalowner-to-legacy-library cycle is debt, ZERO750standalonecredit. No otherproductionseams/lifecycle/actions authorized. CODEMAPnotyetlocked.


M16 expiry A+B authorized onrefactor/m1-6-expiry: host plusprovider_watch_flow fiveunusedslots only. Existingactualorigin suites reproducedgreen before removal; twoauditablecommits sixforwards/deadslots then18mechanicalaliases. Forecast72host includes34aliaslines, plus42binding, NOTqueue133credit. Preserveallwrites/tearofftiming, two write-onlyfields. Retain11livecallbacks/editor/settingsUIboundaries asQ2compositiondebt; no fullM1closure. CODEMAPwaitserializedgrant. G17e scopesdisjoint.


135mergedf75fa016 exactaf4ac9e7 all3CIgreen+independent135/34/body/integrationreview. Difference:114productionlinesremoved (72hostincludes34aliases+42binding); samecallback/writebehavior. More:11livecallbacks/UIcompositiondebt, nofullM1closure. Currentgods9033/11926/3331/4365/2899. C0fullgateactive; threeotherworkersread-onlynextscope preparation toavoididleCIwaits. PhoneinstallstillwaitingADBconnectiononly.

Fullf75fa016gatePASS recorded: evidence debrify-c0-main-f75f-gate/.dart_tool/main-gate/REPORT.md. APK SHAa4ba9de8c1e46e11b377d9fc693c08f57aadd7d9b89fe7c8236e559e2b555830 verified thenADBinstall-r SUCCESS. Covers135; usermanualtestnotclaimed. G17fcontentoriginpins andfivefilterlegacyfixturepins active separatetests; C0M1compositiondesignreviewread-only; no broadproductionrelease.

## Gate 4 — user-reported Windows run
| Gate | Exact source / environment | Analyzer / layering | Tests | Build / smoke | Forwarders |
|---|---|---|---|---|---|
| Gate 4, user report | c86ea5f2; Windows Flutter3.47.2 | 453 issues,0errors;77/77,+0/-0 |5413pass/34fail:33known + native origin test missing LIBMPV_LIBRARY_PATH |Windows build PASS and launched, user-reported |All five god-file counts being independently inventoried; user preliminary storage148/search31, not yet verified |
This is distinct from pinned3.44.8 f75fa016 automated gate. Native plain-test skip when env absent assigned C0, required native runner must remain strict.

## New lane M1-7 — watch-flow deduplication
Status: design/readiness; owner Ampere after current independent fixture review. Target five provider watch-flow files combined below800 lines, consolidating through ProviderWatchFlow and CloudProviderPort capabilities. Current size/normalization overlap and exact owned paths must be verified before product assignment. Provider quirks require origin pins; no blanket normalized-equivalence assumption. MagicTV host-size target remains provisional until this lane merges. Parent owns board; plan files unchanged.

## Phone feedback
User reports "the apk worked great" after successful ADB installation of verified f75fa016 build (through#135), preserving data. Record successful user-reported phone testing; exact feature checklist not supplied, no SHIELD/TV or exhaustive compatibility claim. Refactor continues.

## Manual smoke acceptance — f75fa016
PASSED by explicit user instruction, based on successful phone testing of the installed verified APK and user acceptance of TV behavior. This supersedes earlier pending/deferred manual-smoke entries for this build. Direct SHIELD/TV hardware testing was not performed; no such execution is claimed.

## Forwarder ledger — required in subsequent gate rows
Criterion: AST single-operation delegation to another owner; methods/getters/setters counted separately, including multiline declarations and player reverse-host bridges. Excludes computed arguments, constructed callbacks, guards and lifecycle logic. One-line formatting alone is not the debt definition. Exact symbol inventory/reproducer: C:/Users/hunth/debrify/forwarder-ledger/REPORT.md, ledger.csv and scan.dart. No automatic deletion of live compatibility surfaces is authorized.
| Gate / source | Storage M/G/S | Search M/G/S | Player M/G/S | MagicTV M/G/S | Settings M/G/S |
|---|---|---|---|---|---|
| Gate4 c86ea5f2 |540/23/18=581|19/72/5=96|27/111/23=161|19/24/24=67|0/0/0=0|
| Current e3ee9b7c, same five-file blobs as f75fa016 gate |540/23/18=581|19/72/5=96|27/111/23=161|13/8/6=27|0/0/0=0|
Physical single-line declaration subset at current: storage147/search83/player112/Magic12/settings0. User preliminary148/31 not reproduced; original counting command unavailable. Historical unmeasured gate counts must remain unmeasured, never retroactively guessed. Q2 targets must account for stable public API/caller migration, not indiscriminate removal. Every new gate report includes this inventory at its exact source.

137merged5b4b2c4b exact793e6d63 independent169/audit/docs+all3CIgreen. Difference:4quickdispatchdependencies narrowed toProviderWatchFlow,7sharedcallbacksremain;14host/12productionnetremoved, earlier sideeffectfreeleafallocation declared. Firstproductionsincef75gate. 136nativeCIfailedrun33984264411C0diagnosisassigned;no merge.138/139goldenspendingwithotherchecksPASS;139WindowsAVrecordedseparately. G17gpresentationmoveactive;M17originadversarialactive;filterstoredesignapprovedbutproductionafter138merge. Currentgods9033/11926/3317/4365/2899. Manualf75useracceptancePASSED.

138merged7e6cf5c5 exact18356 afterindependent144/validrestoremutations/provenance+all3CIgreen: separatefivefilterJSON compatibility domain,0Leaves.139mergedfb5ccc4f exact465ef1 afterindependentunset/invalid/strictness/source+exactLinuxnative/test/goldensPASS: plainmissing-env nativecase skipswithreason, invalid/requiredrunnerstillfails. Windows configuredpair AV remainsNOTgreen/no claimfixed. Both test-only source changes; production countsincef75 remainsone(#137).
Locke filterstore production RELEASED exact3prod+keysweep; helperasyncboundary documented, capturedfilterprefs/providerseparatephase preserved. Ampere M17 firstshared58lineTB/PP accumulator production authorized afterindependent6origin/mutations; exactcommon/TB/PP scope, no newasync/guards/cancelpolicy. Wegener presentation move+exactunusedaliases/shapeinventoryupdates authorized;136 integratesnewmain139 forfreshstrictCI, oldorigin600shangnotfixed/overridden. C0 availableindependentreview. No overlappingfiles exceptserializedCODEMAP.

141mergedf24c5a2c/142merged7f00f969 afterindependentreviews+exactall3CI. Difference:5filterownerrawencoding/resetpreserved(-44host,+57production),2quicksearchduplicateshared(-30total,five2448/common1341). More:10newfaçadesQ2/783explicitstoragedebtunchanged/M17targetnotclosed. Fullactual7f00gateC0active afterthreeprod137141142, includeexactforwarderledger.140CItestfailedheldWegenerdiagnosis. Currentgod9033/11926/3317/4321/2899. No userblocker.

## Full gate — actual 7f00f969
| Source | Automated tests | Analyzer / layering | Builds | Forwarders total/single physical line (storage/search/player/Magic/settings) | Manual |
|---|---|---|---|---|---|
|7f00f969, Flutter3.44.8 Windows|5442pass/12exactknown/2skip;goldens21exactknown after2retries;0unexpected/unused;strictnative1+1 unskipped;Python55|436/452no new;77/77,+0/-0|Windows andARM64 PASS,checksummed|591/147;96/83;161/112;23/12;0/0|Prior f75 acceptance retained; this new build not separately reported |
Exact report/commands/artifact/forwarder inventories: C:/Users/hunth/debrify/debrify-c0-main-7f00-gate/.dart_tool/main-gate/REPORT.md. Raw known-failure reports retained, not pixel-green claim. No baseline or power changes.
Cursor dedup product released after independent16origin+4sensitiveprobes+design andfullgate; exactcommon/TB/PMonly, verbatimfourlooporder/livecandidate references.140 corrected d1fe delta review/freshCI remainsrequired beforemerge. Playlist-progress fixture/origin work active separately.

### Coordination refresh after #140
- #140 merged17f0550a after exactd1fe review and test/goldens/native SUCCESS. Did we make a difference?419 host lines moved into typed presentation units; production grows37 lines, so this is relocation and clearer ownership, not net simplification. More remains: Discover content/actions and standalone dispatch.
- Review ownership: Cicero cursor1d5; Wegener playlistb53. Author scope remains unchanged. Ampere alone holds the minimal CODEMAP lock; Locke has none. #140 touches neighbouring Search presentation; no overlap with active storage/watch-flow bodies, but final PR integration must include latest main.
- Current merged sizes vs baseline: Search8614/19070; Player11926/16278; MagicTV3317/10716; Storage4321/9963; Settings2899/7905. Cursor49-net claim remains unmerged pending review. Playlist checkpoint has zero production Leaves.

### V1-7 test-only sequencing decision
Cicero assigned refactor/v1-7-speed-origin-pin: existing test/native/video_player_origin_behavior_test.dart only, real Controls/menu/player/persisted-speed pin with identical bytes on bc46/current required native runner. Explicit exception permits characterization while V1-6 decoder proof is paused; no product, runner, CI, SDK or CODEMAP edits, no decoder or V1-7 completion claim. One bounded implementation attempt; report evidence/blocker rather than repeated native retries. Cursor144 final53184 independentPASS; exact-head CI running. Playlist143 b53 independent review in progress; product219-line move remains held.


### Follow-on ownership after independent checkpoints
- Locke: released separate refactor/s2-playlist-progress-owner based greenb53; only219-line StorageService builder and existing playback_progress_store.dart owner; unchanged reader bridge/callers/keys. Origin143 remains frozen awaitingCI; product cannot merge before143. Forecast215host reduction/+5total, not credited until merge. CODEMAP not granted.
- Ampere: separate refactor/m1-7-captured-unlock-pins, NEW test/magic_tv_captured_unlock_origin_test.dart only;45-minute first batch actual host captured-key wire observations and missing RD PreferVideos path. No production/seams; stop with explicit debt if path inaccessible. Cursor144 remains frozen53184 and independently passed, CI pending.
- Wegener:30-minute read-only next Discover watchlist/focus/CW/bound origin-pin feasibility, no edits or general re-inventory. Cicero: test-only player-speed pin as above. No user dependency.


- Wegener follow-on: refactor/g1-home-watchlist-focus-pin, NEW test/home_watchlist_refresh_focus_origin_test.dart only;30-minute real Home public-control characterization attempt, no production seams. Discover full Fav adapter retained by decision; private node/independent-await gaps remain explicit in NOTES. No user action required.


### Independent review correction — PR145 held
Wegener reproduced the speed native pair but identified a disposal-proof gap: autosave during virtual pumping could prewrite the final checkpoint. C0 is tightening the real persisted-position assertion immediately before unmount, same test-only scope, one corrective pair. No app regression observed; old passing run does not establish unchanged disposal sensitivity. PR145 cannot merge until corrected independent review and fresh exact-head CI. Other work continues:146 independently passed awaiting143 dependency;147 independently passed awaitingCI;148 independent review plus bounded captured-key sensitivity experiment in separate worktree. No user blocker.


### #143 merged — playlist compatibility checkpoint
Exactb53 independent81/scopedanalysis and all3CI passed; test-only143 merged. Real old-export/current-restore/builder proof includes derived marker distinction; zero production Leaves. Did we make a difference? Yes, compatibility safety improved; more remains:146 actual owner extraction and Q2 facade removal. Locke retargeting146 to main and integrating; Cicero finaldelta reviewer after145 correction.144 test/nativepassed, goldenspending. God sizes remain Search8614/19070,Player11926/16278,Magic3317/10716,Storage4321/9963,Settings2899/7905. No user blocker.


### #144 merged — actual watch-flow deduplication
Exact53184 independently reviewed191pass/analyzer436452/layer77 and all3CIgreen; cursor144 merged. Four cache-window loops share one owner with original timing/cancel behavior. Did we make a difference?49 fewer physical production lines; fiveflows2352/common1388, total3740. More remains: below800 target not reached. God hosts unchanged8614/11926/3317/4321/2899 against19070/16278/10716/9963/7905. This is secondproductionmerge since7f00gate;146 next thenfullgate.
- Active: Ampere cached-player originpins (newtestonly); Locke146 integration/nextstorageproposal; Cicero finalgateprepared/146review complete; Wegener boundedtimer-origin feasibility.145corrected4ef independentpairpassed, freshCIpending;147/148independentlypassed awaitinggoldens. No user blocker. LatestCODEMAP rowunion must preserve144 when146 merges.

### #147 and #148 merged — finite safety improvements
Both exact heads2d2ce8e/d21814c independently reproduced and all3CIpassed.147 proves Home focus before bound completion, not Discover/independent-await.148 proves10actualcaptured-key paths including successful PreferVideos; removed-key mutant actualwirekill only, changed-key mutation confounded and not counted. Did we make a difference?Yes, observable compatibility pins improve safety; more remains as explicitly limited above. Zero production Leaves; godcounts unchanged8614/11926/3317/4321/2899 vs19070/16278/10716/9963/7905.146awaitinggoldens thenfullgate;145correctedreviewpassed awaitinggoldens;149reviewpassed awaitingCI. C0repairpin review,Lockerepairtest publication,WegenerQ2live-sessionpin,Amperepresentationmap ready heldfullgate. No user action needed.


### #146 merged; full gate dispatched
Actualmaina443395b92c31b42eef9780cdb0feddb32655814. Exact724 independent117/analyzer/layer/finalunionPASS, complete exact-head CIrun33988787257 all3SUCCESS (duplicateoldergoldenstillrunning, not used). Did we make a difference?219-line playlist body belongs to PlaybackProgressStore,215 fewer host lines; wholeproduction+5,one4-line facade expiresQ2. More remains:1306host target deficit and caller migration. Godcounts8614/11926/3317/4106/2899 vs19070/16278/10716/9963/7905.
Cicero fullgate IN_PROGRESS exacta443: fullgeneric/goldensverdict,analyzer,layer,nativepair,Python,Windows/ARM64 builds and all5forwarderledger. No nextproductionrelease untilpass; no newmanualsmokeclaimed. Locke repairfixture tests,Ampere Q2pinreview,Wegener Q2pinpublication; presentation26net proposalready awaitinggate. No user blocker.

### #145 corrected native pin merged
Exact4ef87c96 independent corrected origin/current pair and freshall3CIpassed; P2autosave/disposal gap fixed. Did we make a difference?Real speed selection/persistence proof plus explicit pre-unmount checkpoint inequality protects disposal evidence. More remains: decoder/sleep/aspect not proved. TestonlyzeroLeaves; godcounts unchanged8614/11926/3317/4106/2899 vs19070/16278/10716/9963/7905. Fullgate stillexacta443 (does not include145test),generic5499/12known/2skip,analyzer436452/layer77/Python55/native/Windows161.4s/ARM64111.8s passed; goldenspending. Forwarders a443 total/singleline:storage592/147,search85/72,player161/112,Magic23/12,settings0/0. Workers follow-ons remain testonly/prepared pendinggate, no user blocker.


### Full integrated gate a443 — PASS
| Source | Tests and diagnostics | Builds | Forwarders total/single physical line | Result |
|---|---|---|---|---|
| a443395b92c31b42eef9780cdb0feddb32655814 treee3b4fc72787f29632ba6ee3152027f907120b773 |5499pass/12exactknown/2skip;goldens21exactknown after2configuredretries;0unexpected/unused;analyzer436/452 exact16unused;layer77delta0;Python55;nativebc46/current1+1unskipped |Windows161.4s68files ZIPaa8f78686910b08dcf5be17d8cecbcf8783627d10de7a320a5dd1462a086052b;ARM64111.8s APK44cd64d9b3330b632422cf922e728d3c3520f1d9e45e553bf3a2240136c37c45 |Storage592/147;Search85/72;Player161/112;MagicTV23/12;Settings0/0 |AutomatedPASS against unchangedbaselines; rawgeneric/goldensfalse disclosed. No newmanualsmoke/install; a443 excludes later145test |
Report: C:/Users/hunth/debrify/debrify-c0-next-main-gate/.dart_tool/main-gate/REPORT.md. Did we make a difference?Verified integrated presentation/storage/cache changes with no unexpected regressions; more remains: knownfailures, forwardingdebt and unfinished architecture. Godcounts8614/11926/3317/4106/2899 vs19070/16278/10716/9963/7905.
### Released after a443 gate
- Ampere after152review: refactor/m1-7-cached-player-presentation, ONLYcommon+TB/PM/PP cachedpresentation4files,26net prepared patch,149pin prerequisite beforemerge. No CODEMAP untilgrant.
- Wegener: refactor/q2-iptv-launch-view-removal, ONLYcontroller+2testfiles exactprepared18net/7forwarder removal,151prerequisite beforemerge. No host/native/CODEMAP.
- Cicero independentproductreviews asheadsfreeze; Locke repairmapping read-only pending152independentfixture proof. No user blocker. Productionmergecounter resets0 aftera443gate.

### #149/#150/#151 origin pins merged
Exact3e594/cf6de/494 independently reproduced and eachall3CIpassed.149threeactualcachedpresentationoptionscases,15013newrepairfailurecases,151threeactualIPTVlive-sessioncases. Did we make a difference?Safetyproofs precede changes; zero production Leaves. More remains:livebuildertiming/repairinterleavings/nativeIPTV notclaimed. Godsizes8614/11926/3317/4106/2899 vs19070/16278/10716/9963/7905 unchanged.
### Current scoped releases
Ampere cachedpresentation product4files plus explicit4sourceguardcountadaptations (PP/PM/TB2to1/common2to3, alladversarialchecksretained). Wegener153Q2productreviewPASS checkinglatestunion/CI; C0independentreviews. Locke repair-owner released exact8methods/4registryrows and approved6privatebridge+3obsoletealiaslines; forecast258host/+31whole,7facades, existingquirks unchanged, no mergebefore152fixture. No CODEMAP locks granted yet for newproducts. No user blocker; a443fullgatepassed, productioncounter0.


### #152 repair fixtures merged
Exact41f8 independent89twice/scopedanalysis/actualkeytype mutants andall3CIpassed. Did we make a difference?PreS2export/currentrestore/actualrepair proof, distinct5/7/7packages sevenkeyunion with derivedmarker separate. More remains: finiteinterleavings/profilequirks are not fixed or exhaustivelyproved. ZeroLeaves; gods8614/11926/3317/4106/2899 vs19070/16278/10716/9963/7905 unchanged.
Currentproducts:153Q2 independentPASS awaitinggoldens;154presentation194independentPASS awaitingCI;155repair productPASS/docsunionreview ongoing/CI.155scope additionallyapproved4exactownedSetexpectedkeys+oneunusedjson_isolateimport;259host/+30whole, no allowance. AllCODEMAPlocksreleased. No user blocker. Nextfullgate afterthese3productionmerges; counter0.


### #153 merged; firstproduction sincea443gate
Exact349 independent30/scoped/full436452/layer77/union andall3CIpassed. Did we make a difference?Removed18productionlines and7forwardinggetters/class/allocation, preserved live session reads. More remains:otherforwarders/nativepagebehavior. Zero godhostLeaves; counts8614/11926/3317/4106/2899 vs19070/16278/10716/9963/7905 unchanged.154/155reviewed awaitingCI; nextfullgate afterbothmerge. No user blocker.
### Timer pin bounded stop
Wegener oneauthorizedsecondphase attempt failed equallybc46/current beforelongclock: public15min selection yieldedarmed0. No greencommit/no appregressionclaim, trackedtestrestored. Retainhosttimers; timer-onlygrowthhelper rejected. No furtherattemptauthorized. Scope remains read-onlynextQ2candidate whileproductCIruns.


### #155 merged; fullgate f486 dispatched
Exact882aef39 product/docs/actualunion independentlyPASS andall3CIgreen. Actualmergef4862238612bbfaa51631d51c3f760bbb5edcb86. Did we make a difference?259fewer hostlines (3847), repairlogic reunitedwithstore; wholeproduction+30/sevenfacades remainQ2, not259netdeletion. More remains:1047hostgap/knownprofilequirks. Gods8614/11926/3317/3847/2899 vs19070/16278/10716/9963/7905.
Cicero fullgate f486IN_PROGRESS allchecks/builds/forwarders. Metadataorigin156reviewPASSawaitCI; fixture d735independentreview; productmappingread-only. Captured-key standalone+36proposal DEFERRED after independentreview: no typedconsumer/deletion, follow-on RDlookup foundno coherent equivalentqueueblock. No implementation/no user blocker. Nextproductionhelduntilf486gatepasses.

### Full gate f486 — PASS
| Source | Tests/diagnostics | Builds | Forwarders total/single physical line | Result |
|---|---|---|---|---|
|f4862238612bbfaa51631d51c3f760bbb5edcb86 treeecfd6559cd22a65791dcda24e2e90baa9825e5ed|5526pass/12exactknown/2skip;goldens21exactknown after2configuredretries;0unexpected/unused;436/452same16unused;layer77delta0;Python55;nativebc46/currentcorrected1451+1unskipped|Windows164.4s68files ZIP4b8ffa5fcc19b5115e57b04181cea17b558b4f60c5e2aca9158f21e96e8d05c5;ARM64108.8s APKdfc6c0235d16d4c35aed6c7d14627af4021bb3d5c43ac1c60df973dc88ca794c|Storage596/147;Search85/72;Player161/112;Magic23/12;Settings0/0|AutomatedPASS unchangedbaselines/rawgenericandgoldensfalse;no newmanualsmoke/install|
Report C:/Users/hunth/debrify/debrify-c0-post-153-155-gate/.dart_tool/main-gate/REPORT.md. Did we make a difference?Integrated3changes verified withoutnewregressions; more remains knownfailures/dependencyandforwardingdebt. Gods8614/11926/3317/3847/2899 vs19070/16278/10716/9963/7905.
Metadataowner released refactor/s2-playlist-metadata-owner, onlyhost214lineblock+2unusedaliases/existingstore11bodies, tenfacades; prerequisite156157mustmergebeforeproduct. C0independentreviewer. CODEMAPnotgrantedyet. Counterreset0. No user blocker.

### #156 merged
Exactbd10 independent17/33/scopedPASS andall3CIgreen. Did we make a difference?Realmetadataidentifier/JSON/type/errorquirks pinned; more remains157fixture+owner. ZeroLeaves/gods8614/11926/3317/3847/2899 vs19070/16278/10716/9963/7905 unchanged. Metadataownerf4 independentreview now,181host/+44whole forecastactualpending; CODEMAPminimal lockLocke granted.157awaitgoldens. C0review;Amperedeepwatchcontractdesign;WegenerstandaloneDiscoverdesign; no user blocker.


### #157 merged
Exactd735 independent91twice/scoped/keytypepostrestoremutants andall3CIgreen. Did we make a difference?Two physicalmetadataStringkeys restoreexactlyfromoldexport andactualAPIs; more remains158owner+Q2callers. ZeroLeaves/gods8614/11926/3317/3847/2899 vs19070/16278/10716/9963/7905 unchanged.158product/docsPASS latestunion/CIpending;allCODEMAPlocksreleased. Wegenercontentrefreshoriginpin newtestonly underway;Amperewatchcontractdesign;C0review. No user blocker.


### #158/#159 merged
158exact381 independent17+91+18/scoped/full436452/layer77/finalunion/all3CIpassed. Did we make a difference?Metadataowner co-locates actualkey/CRUD/identity logic,181fewer hostlines (3666),wholeproduction+44/10facadesQ2. More remains866gap=783historical+83other, notnet181deletion.159exact99b independent29/all3CIgreen protectsactualreturnrefresh/latebounddisposal,zeroLeaves; +52ownerproposalDEFERRED untilconcretestandalonecompositionadoption. Gods8614/11926/3317/3666/2899 vs19070/16278/10716/9963/7905. Productioncounter1sincef486.
CurrentWindowednext origin3197reviewC0/mapAmpere/read-onlyriskWegener; Locke boundedstorage residualclassification. No user blocker,allCODEMAPlocksreleased.

### #160 merged / Windowed product held
160exact3197 independent24/scoped/all3CIpassed. Did we make a difference?Eightlaterrefillcases improvefiniteproof; more remainsquickdequeue/reentrant/cast/nativegaps,zeroLeaves.163productfrozen121/docs7638 draft:19net/202leaf,24retainedbindingsQ2expiry; exact5prod+1inventorypath authorized. CItestfailedpendingverifiedcast-diagnostic relocation; no addedallowance/baselinewritegrantedyet,C0review. Gods8614/11926/3317/3666/2899 vs19070/16278/10716/9963/7905 unchanged.
Watchlistownerreleased3prod+keysweep,161162prerequisite; debugannotationonly movedstorefield removal explicitlyapproved,hostcompat annotationsretained. No CODEMAPlocksheld. No user blocker.


### #161 merged; Windowed baseline relocation authorized
161exact74d independent40/scoped/provenance/all3CIpassed. Did we make a difference?17actualWatchlistcases protectduplicates/cap/errorquirks; more remains162fixture/164owner. ZeroLeaves/gods8614/11926/3317/3666/2899 vs19070/16278/10716/9963/7905 unchanged.
163C0independentlyverified436diagnosticmultisetidentical. AuthorizedONLY tool/analyze_baseline.json diagnostics[5] path/line/column oldTBmetadata572:46(actual466) toWindowed192:44;452entries/allotherfieldsunchanged. Ampere separate10329297/final63889 appliesrelocation, no extraallowance/castfix; freshCIpending/fullreview.164Watchlistownerreviewpending/e006+docs2dda;allCODEMAPlocksreleased. No user blocker.


### #162 merged / products reviewed
162exact819 independent105/scoped/actualpackagekeytype mutants/all3CIpassed. Did we make a difference?OldWatchlistStringrestore/readcanonicalizationwithoutpersist verified; more remains164owner/Q2callers,zeroLeaves. Gods8614/11926/3317/3666/2899 vs19070/16278/10716/9963/7905 unchanged.163final638 independentPASS withexact1baselineentryrelocation/no extraallowance,readyfreshCI;164product/docsWegenerPASS latestunionpending. Nextfullgate after163164(158alreadyone). No user blocker,allCODEMAPlocksreleased.


### #163 merged
Exact63889 independent218executions/202distinct/scopedinherited7/full436452/layer77/finalmapping/CIall3passed. Did we make a difference?Fournextclosures consolidateinto2deliberatelydistinctprogrammes;19netprod/202leaf,newowner217/model13 fullycharged. Fiveflows2081/common1384/newowner217;below800unfinished/24bindingsQ2retained. Warningbaselineoneentryrelocatedonly,452countunchanged. More remainsreentrancy/cast/nativefinitegaps andqueuedependencies. Godhostsunchanged8614/11926/3317/3666/2899 vs19070/16278/10716/9963/7905.164all3CIgreen finalpost163unionreviewthenmerge/fullgate. No user blocker.


### #164 merged; c1ca fullgate dispatched
Exact2dda independent40/105/11/full436452/layer77/finalpost163union andall3CIgreen. Actualmergec1cae4c7c6ba3973d529466e72b86bf9677a3be3. Did we make a difference?Watchlistcontenthascoherentowner,168hostlinesremoved3498;wholeprod+87/eightfacades+capdebugcompat remain. More remains698targetgap:83otherclosed,85explicitlychargedagainsthistoric783once. Gods8614/11926/3317/3498/2899 vs19070/16278/10716/9963/7905.
C0fullgateactualc1caIN_PROGRESS after158163164; allchecks/builds/forwarderledger required. No nextproductionreleaseuntilpass. Userpercentageanswer65engineeringestimate/52percenthostshrinkage, notacceptancecompletion. No user blocker/allCODEMAPlocksreleased.

### Progress reporting correction
User correctly challenged unchanged65% repeatedover6hours. Estimatewithdrawn, not replaced by anotherunsupportednumber. Future reports must name closed acceptancecriteria and outstanding architectural outcomes; hostshrinkage/testcounts are evidence, notoverallcompletion. Priorpercentageentries are historical and superseded. Prioritize completing coherent architecture over creating more smallPRs.

## Merge165 — September5
Exact reviewed97db merged as79547771. All3CIchecks passed; independent495focusedpass; generic5593pass/12known/2skip, goldens21known, analyzer436/452 and layering77 unchanged.223facades retired, host665lines fewer, wholeproduction592lines fewer.33targetshortfall and97residual members remain open. Pin-before-move preserved in merge history. One batched board commit for this merge; no new manual smoke claim. Active follow-ons: M1 shared admission and board runtime, independent reviewers assigned. No user blockers; parked112/109/56 unchanged.

## Merges166 and167 — September6
Both exact reviewed heads41bf90c8 and6c0fc23 passed test/goldens/native CI and merged sequentially into58864c1d.166 removes135 production lines through four-provider shared admission/search (five leaves1782/common1551; targetopen).167 removes266 host lines but adds106 wholeproduction lines; actualnavigation/paging/deferred-focus ownership removes threeFavhostdependencies, not standaloneDiscover completion. Combined net29 production lines removed; architectural and relocation accounting remain separate. Godcounts Search6551/19070,Player11928/16278,Magic3318/10716,Storage2538/9963,Settings2901/7905. Threeproduction merges sincec1ca trigger full integrated gate at58864c1d (Cicero), now running withallfiveforwarderledger. Active Discover composition(Wegener) and QuickPlay policy origin/restorefixtures(Locke); no newmergebeforegate. No userblocker/performance scope added. One batched board commit for these merges.

## Corrective merge169
Test-only fixture correction4ea3520a mergedb19cd9e9 after8author tests/cleananalysis andall3CIchecks. No independenttest-onlyrerun, production/allowances unchanged. Actualmain genericrerun assignedC0; prior58864 build/native evidence retains exactsource labels. PR168 HomeDown duplicate-request assertion failedCI and is underboundeddiagnostic review; notwaived. Godfiles unchanged8349/11928/3318/2833/2901 versus originals19070/16278/10716/9963/7905. Did we make a difference: fixed provenUTC/local testfixture error, noappbehaviorchange. More remains: Discovercutover,168CIresolution and architectureoutcomes above.

## Merge168 and worker redispatch
PR168 exact84f47688 merged42de469f afterall3freshCIpassed, productionindependentlyaccepted11d4 unchanged and narrowboardfixtureisolation verified. Storage2833->2712 (-121), wholeproduction+69,12facades29lines retained. Sizegoal2800met; strictlogicownership remainsopen. Simklcorrectedb19generic5604success/12known/2skip; prior58864build/nativeevidence explicitlycarriedunchanged. Counter1production sinceclosedgate. C0checks170newmainunion;Wegener170integration andnextplannedstage scope;Ampere nextcoherentM1programme scope;Locke nextremainingstorageowner scope. Allnewscopesread-onlyuntilboundedgrant, nooverlap. Godcounts8349/11928/3318/2712/2901 vs19070/16278/10716/9963/7905. No userblockers; roadmapbatchonceformerge.

## Merge170
Exactd603 all3CIpassed andindependentreviewaccepted; merged7a22ca10. StandaloneDiscover usesrealsharedsession/actions withoutlegacyState; originalnonTVfocus restoredandpinned; sourceguards followactualrouting. Host8349->7053(-1296), wholeproduction+589;112retainedforwarders383lines(+36byclassifier) andtwoauditedlint exceptions remain explicitdebt. No performanceclaim. Count2productions sinceclosedb19gate, nextproductionmerge triggersfullgate. Workers: Spotlightstage(Wegener),VR171CIready(Locke),sharedquickprogramme(Ampere),review/gateC0;Locke independentlyreviewsquickprogramme. Godcurrent7053/11928/3318/2712/2901 vs19070/16278/10716/9963/7905. No userblockers. Didwemakeadifference: actualstandaloneDiscover+sharedownership, notnetdeletion. More: stages/player/storage/watch/Qoutcomes.

## Merge171 and integrated gate
VR171 exact1923 all3CIgreen/independent180tests accepted merged2ecd173d. Host2712->2678(-34),wholeproduction+40,11facades22 retained, scalarsettingsownershiponly. This isthirdproduction sinceclosedb19 (168170171); C0 fullgate2ecd triggered, nextmergesheld. Spotlight91a282 independentreviewAmpere andCODEMAPWegener;172reviewacceptedawaitCI/gate;Lockeavailable. Currentgod7053/11928/3318/2678/2901 vs19070/16278/10716/9963/7905. No userdecision/blocker; userfuturefallback request remainsfutureonly. Difference: VRkeysoneexistingowner/rawcompatpins;morebusinesslogic/facaderetirementremain.

## Gate2ecd accepted with note; merge172
Fullgate2ecd:5677success/12known/2skip zero new/unused;goldens21known effectivepass;analyzer436/452,layer77+0/-0,Python55,Windows161.4s/ARM6496.7s pass. Originalnativebc46pass/currentexit79 incomplete withoutassertion; oneauthorizedcontrolledcurrentrerunpassed6.56s samebytes/runtime afterbuilds, firstfailure retained ROOTCAUSEUNPROVEN. Gateacceptedwithreliabilitynote, notfirstpassclean. Ledgercurrent-knownowners storage416/143,search133/117,player161/112,Magic23/12,settings0; searchsameclassifierbackrun58864=105 vsoldclassifier82, no silentbaselinechange. PR172 exactfa1 all3CIpassed/independent227nongoldenpass merged21477e89,101netprodremoved,fivewatchleaves1498/common1551/new183,targetopen. Counter1sincegate.173heldtwo sourcepublictype tests likelymovedneutraldeclarations,ownertriage; no waivedassertions. Godfiles7053/11928/3318/2678/2901 vs19070/16278/10716/9963/7905 unchangedthismerge. No userblocker. Difference: completeTB/PMquickcontinuation shared;moreproviderflows remain.

## Merge173 and immediate follow-on assignments
173exact2cef all3CIpassed/independent66tests+correctiondeltaaccepted merged3347ef1d. Spotlightrealwidget+assembly/neutralFavtypes,host7053->6830(-223),wholeproduction+92,oneof7stagescomplete—not1400target. Sourcepinsactualneutraldefinitions/export tested, no weakenedassertions. Counter2since2ecd (172173). Wegener nextcoherentstage scope+originpins;AmperecachedflowawaitsC0exactbaselinecommit andpreparesindependentonboardingreview;C0finishesbaseline451mapping;Lockeonboarding2bodymoveactive. No workerneedsuserinput. Godcurrent6830/11928/3318/2678/2901 vs19070/16278/10716/9963/7905. Differenceactualwidget/dependencycut;remaining6stages/couplingstayopen.

## Merge174 and immediate gate
Exactf31ab5d4 independent86PASS/all3CIgreen merged730b18fa. Onboarding2bodies preserved,host2678->2609(-69),whole+18/twofacades4; exclusion/restorequirk retained. Thirdproduction172173174 since2ecd triggersfullgate730b18C0 nowrunning;baseline452 (175notmerged).175exact0f9a allCIgreen+reviewacceptedheldonlygate. ActiveTonightproductionWegener,cachedlockedpinsAmpere,remoteexclusionLocke,fullgateC0. God6830/11928/3318/2609/2901 vs19070/16278/10716/9963/7905. No userblocker. Difference setupauthority separatedwithrealtests;morestorageandarchitecture remain.
