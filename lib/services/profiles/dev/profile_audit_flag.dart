/// Whether the dev profile-audit tooling is compiled in at all.
///
/// **`false` — the tool does not ship.** It defaulted to `true` for one day
/// (2026-08-15) so local `--release` tvOS builds carried it without a
/// `--dart-define`, and was flipped back the same day once alpha became real.
/// An alpha is a release to other people, and CI passes no defines, so leaving
/// it on would have put a raw key/value browser in front of testers — the exact
/// "ships by being forgotten" case this flag exists to prevent.
///
/// A build without the opt-in has neither the entry point nor the code behind
/// it: `kProfileAudit` is a compile-time const, so the tree-shaker drops the
/// screen and the report entirely.
///
/// Deliberately NOT `kDebugMode`: the device this exists for is an Apple TV,
/// and tvOS builds are `--release`. A debug-only gate would hide the tool on
/// the exact hardware it was written to debug.
///
/// Turn it on for one build without editing this file:
/// ```
/// flutter-tvos build tvos --release \
///   --dart-define=DEBRIFY_PROFILE_AUDIT=true
/// ```
///
/// The real end state is the removal recipe in README.md; this flag only keeps
/// the tooling cheap to carry until then.
const bool kProfileAudit = bool.fromEnvironment(
  'DEBRIFY_PROFILE_AUDIT',
  defaultValue: false,
);
