/// Whether the dev profile-audit tooling is compiled in at all.
///
/// **Currently `true` by user decision (2026-08-15)** so every local build —
/// including the `--release` tvOS builds this exists to debug — carries the
/// tool without anyone having to remember a `--dart-define`.
///
/// The cost of that choice, stated plainly: CI builds pass no defines either,
/// so a release artifact cut today INCLUDES this tooling. That is the exact
/// "ships by being forgotten" case the flag was introduced to prevent, and it
/// is accepted only because this branch has one user. **Flip the default back
/// to `false` before anything here reaches other people** — or better, run the
/// removal recipe in README.md, which is the real end state.
///
/// Deliberately NOT `kDebugMode`: the device this exists for is an Apple TV,
/// and tvOS builds are `--release`. A debug-only gate would hide the tool on
/// the exact hardware it was written to debug.
///
/// Turn it off for one build without editing this file:
/// ```
/// flutter-tvos build tvos --release \
///   --dart-define=DEBRIFY_PROFILE_AUDIT=false
/// ```
const bool kProfileAudit = bool.fromEnvironment(
  'DEBRIFY_PROFILE_AUDIT',
  defaultValue: true,
);
