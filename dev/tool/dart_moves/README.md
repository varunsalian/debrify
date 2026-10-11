# Dart move ownership (video player Phase 1)

`check_dart_moves.py` adds ownership, disjoint class partitions and Git history
to `check_verbatim_moves.py`'s analyzer/scanner. Token comparison and explicit
occurrence-counted edits live in `check_settings_moves.py`; binding, lexical
setter and context checks use the existing shared guards. No second Dart
normalizer or source parser is used.

All invocations require an isolated `--parser-package` beneath
`.dart_tool/vplayer_parser/`. The argument is its `.dart_tool/package_config.json`.
When copying a parser package, delete all copied `*.dill` files. Packages pin
analyzer 14.3.0 through the existing tool-only lockfile; application dependencies
are unchanged. Run heavy checks with `nice -n 19`.

```sh
nice -n 19 python3 dev/tool/check_dart_moves.py --self-test --self-compare-original --parser-package .dart_tool/vplayer_parser/moves/.dart_tool/package_config.json
nice -n 19 python3 dev/tool/check_dart_moves.py --manifest dev/tool/dart_moves/vplayer_p1.json --parser-package .dart_tool/vplayer_parser/current/.dart_tool/package_config.json
```

`vplayer_p1_retained.json` classifies the formatted original R, including every
directive, the State header/closing brace/tail and ordered members. Whole-class
rows own their complete subtrees: the class and every nested member inherit
that one fate; a competing member row is rejected. Leading inter-member
comments belong to the following span. Every scanner token has exactly one
owner, including file tails and comments after the final declaration.

`vplayer_p1.json` is **applied**, with 16 frozen moves into 10 destinations.
It retains the original reviewed draft, changing only its status. The current
checker compares all 893 fates against R, including the two S patches and the
frozen hook scaffolding. Self-tests materialize this same manifest in memory;
no ownership expectations are regenerated from destination bodies.

Each row has exactly one `fate`: `retained`, `moved`, or `patched`. Edits are
scanner token arrays (`before`, `after`, positive exact `count`) scoped to that
row. A patched row also requires a reason and named test. `remove_static: true`
is allowed only for an original static method moved to a top-level function;
the complete signature and body still compare. No implicit receiver, rename,
modifier or warning fix is accepted.

The facade and destinations pin exact directive lists and declaration orders.
Every added declaration, interface, adapter, constructor, field initializer,
structural span and typedef is exhaustively frozen in `scaffolding`. Editing
the reviewed order cannot authorize reordered retained field initializers.

`--at SHA` loads the manifest and every sidecar from SHA and checks that tree.
The ordinary current-tree check additionally derives all earlier destination
paths from applied phase manifests at the current phase's base. Entire files
are frozen, except reviewed exact `earlier_patches` with reason and review.
An omitted phase or missing/extra destination cannot reduce required coverage.

The following shared-guard options are inert for existing manifests:

- `host_property_bindings`: exact `_host.property` paths to originating State
  members, preserving read, setter, compound-assignment and increment roles.
- `live_state_receivers`: live `context`, `mounted` and `setState` forwarding;
  lexical builder contexts and sheet/dialog setters stay lexical.
- `host_owner_identity`: narrowly named State-identity property substitutions;
  moved State methods cannot retain an unsubstituted `this`.
- `occurrence_top_level_members`: explicitly listed parameter-only methods
  projected through the existing parser to match top-level function scopes.

The frozen Host fixture checks these boundaries, including mutations that
also alter declared token edits. The real Phase-1 draft is a separate full-file
positive, and its analyzer probe must compile. Git fixtures cover same-revision
sidecars, wrong revisions, and edits to earlier destinations with an unchanged
facade. Fixture repositories are temporary and live only under authorized
Phase-1 evidence.

Optional trailing commas come from the existing AST visitor. A required
singleton-record comma is never stripped. `vplayer_format_proof.py` reuses the
catalog proof adapter and records inserted/deleted sites, mandatory scanner
tokens (comments/literals included), hashes and idempotence. Formatting-induced
diagnostics are recorded separately by declaration identity and multiplicity.

`check_vplayer_analyzer.py` compares severity, rule, original enclosing
declaration and message, **with counts and infos**. Its frozen inventory takes
the maximum per identity across unformatted root, formatted root, strict
formatted original and the reviewed rename probe. Destination directive
diagnostics also pin their file, so one file cannot spend another's allowance.
It does not replace the
global analyzer allowlist. Surviving warnings enter that allowlist when their
production file is created.

CI is enabled in the **Step-1 commit creating the first
`lib/features/video_player/**` file**. That commit:

1. Register `video_player` and its exact legacy bridge in
   `check_search_architecture.py`, prohibit facade back-imports, enforce pure
   application/model imports, and register any exact compatibility exceptions.
2. Add the facade to the explicit format/analyze lists in `checks.yml` (new
   destinations are already inside `lib/features`), and add warning entries.
3. Enable this checker self-test/current-tree check and analyzer comparator,
   using isolated CI parser packages and `fetch-depth: 0`; run historical
   manifests against their corresponding revisions.
4. Register each new characterization file in `ci_behavior_tests.txt` and
   the test-only seam flag in its test/CI commands.

S is frozen separately in `vplayer_p1_seam.json`: two patched declarations,
three interception patches, the hook class frozen as a whole, and its foundation
import substitution. The applied Phase-1 manifest includes the same scaffold and
patches. Feature move/analyzer/boundary CI starts in this first production-file
commit.

Harness commands must pass `--dart-define=DEBRIFY_VP_TEST_HOOKS=true`, including
full-suite evidence runs and the curated CI behaviour command. Ordinary debug
installation is checked by running the seam guard test without that flag too.
Run `nice -n 19 python3 dev/tool/vplayer_seam_proof.py --self-test
--parser-package .dart_tool/vplayer_parser/<isolated>/.dart_tool/package_config.json`.

Step 0 harness support and characterization commands (application stays at S):

```sh
nice -n 19 flutter test --no-pub --dart-define=DEBRIFY_VP_TEST_HOOKS=true test/features/video_player
nice -n 19 python3 dev/tool/suite_evidence.py run vplayer/p1/step0-suite --no-pub --dart-define=DEBRIFY_VP_TEST_HOOKS=true
```

`vp_source_reader.dart` invokes `vplayer_source_reader.py` with an isolated
parser. The Python reader validates the latest applied manifest and its
history-derived destinations before returning current text; missing current
ownership never falls back to Git text. Its real Phase-1 virtual fixture chains
a second relocation and rejects current-body drift and missing/duplicate fates.
`vplayer_parameter_proof.py` records lexical analyzer binding evidence and the
exact approved application import lists. Its compilation companion is the
strict-feature top-level rename probe from T; helper bodies are unchanged at S.

All characterization files are registered now in `ci_behavior_tests.txt`;
feature move/analyzer/import CI is enabled with Step 1's first production
`lib/features/video_player/models/` file.

Step 1 activates the frozen `vplayer_p1.json` (16 moves, 10 destinations).
Its creation commit enables architecture, ownership/history and scoped analyzer
CI, with the facade in format/analyze paths and full checkout history. The
source reader validates the live moved hash declaration and its S→P1 chain.

Phase 2 Step T freezes `vplayer_p2.json` as **draft**, base `31a347ad2`.
`draft_vplayer_sleep_moves.py --base 31a347ad2 --parser-package <isolated>
--probe <git-common-dir>/refactor-evidence/vplayer/p2/<directory>` materializes
and compares the complete split solely in evidence. It covers all 889 spans,
12 moved declarations and 14 retained reference occurrences. The per-field
`owner_scoped_bare_fields` opt-in accepts unbound bare accesses only in the
field's exact destination file/class; lexical capture, other owners and Host
forwarding still fail. Existing configurations retain mandatory qualification.
The real P2 configuration and binding-only negatives run in the shared self-test.

The **P2 production creation commit** must switch current-tree/self-test CI
and analyzer selection to P2, keep P1 `--at 31a347ad2`, extend theme paths,
and retarget EOF's sleep anchor through the validating reader with an explicit
non-negative assertion. P1 diagnostic mappings are preserved in the P2 inventory.
Do not enable the draft against the original facade.
