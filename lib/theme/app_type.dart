import 'package:flutter/material.dart';

import '../widgets/detail/theme/detail_theme.dart';

/// A theme's typography, app-wide.
///
/// Nearly every `Text` in the app merges with `DefaultTextStyle`, which
/// resolves to `textTheme.bodyMedium` — so the family flows from one place and
/// per-theme typography is a small change at the adapter rather than a sweep.
/// Only 98 sites name a family explicitly, and those are deliberate (the IPTV
/// premium styles, the details page's own roles).
///
/// The legacy path never sees this class: `AppThemeAdapter.legacy` keeps its
/// verbatim construction, and only `AppThemeAdapter.themed` reads these tokens.
@immutable
class TypeTokens {
  /// Headline/display/title face. Null = Inter, today's face.
  final String? displayFamily;
  final List<String>? displayFallback;

  /// Body/label face. Null = Inter.
  final String? bodyFamily;
  final List<String>? bodyFallback;

  /// The app-wide title scale.
  ///
  /// **Deliberately a different token from [DetailTheme.displayScale]**, not a
  /// second reading of it. The details page uses the raw `displaySize / 23`
  /// (0.78–1.35) because a hero title is a statement a details page is allowed
  /// to make. A settings row is not, and 1.35 on every title overflows a dense
  /// TV row — so this one is damped halfway toward 1 (0.89–1.17).
  ///
  /// `type_metrics_test.dart` is the authority on whether the damping is
  /// enough: if a real face at this scale cannot fit the tightest real
  /// constraint, the factor drops, not the test.
  final double titleScale;

  /// The theme's hero weight and tracking.
  ///
  /// Carried so a site that WANTS the full treatment can ask for it, and
  /// **never applied by [display]**. These are display-page values: Cinemascope
  /// asks for 3.8 letter-spacing and Blueprint for 1.8, which are gorgeous on
  /// one hero title and catastrophic on every label in a settings list —
  /// `type_metrics_test.dart` measured Cinemascope's tracking pushing a
  /// one-line dialog action past its box on the shipped fixtures.
  ///
  /// The app-wide contract is therefore narrower than the details page's:
  /// **the theme owns face and scale; the site keeps its weight, tracking and
  /// case.** That is also the contract the details page states for sites in
  /// `DetailTheme.titleStyle` — this just declines the two overrides it grants
  /// itself as a hero surface.
  final FontWeight? displayWeight;
  final double? displayTracking;

  /// Available to sites that want it; **never applied globally**, for the same
  /// reason. Six themes declare it, and forcing caps on every label reads as
  /// shouting outside a hero.
  final bool displayUpper;

  const TypeTokens({
    this.displayFamily,
    this.displayFallback,
    this.bodyFamily,
    this.bodyFallback,
    required this.titleScale,
    this.displayWeight,
    this.displayTracking,
    required this.displayUpper,
  });

  /// Today's app: Inter everywhere, no scale, no overrides.
  static const TypeTokens legacy = TypeTokens(
    titleScale: 1,
    displayUpper: false,
  );

  factory TypeTokens.fromDetail(DetailTheme core) => TypeTokens(
    displayFamily: core.displayFont.family,
    displayFallback: core.displayFont.fallback,
    bodyFamily: core.bodyFont.family,
    bodyFallback: core.bodyFont.fallback,
    titleScale: 1 + (core.displayScale - 1) * 0.5,
    displayWeight: core.displayWeight,
    displayTracking: core.displayTracking,
    displayUpper: core.displayUpper,
  );

  /// [base] wearing the display face, at [titleScale].
  ///
  /// Face and scale only — see [displayWeight] for why weight and tracking are
  /// carried but not applied. A site that chose `w600` keeps `w600`.
  TextStyle display(TextStyle base) => base.copyWith(
    fontFamily: displayFamily,
    fontFamilyFallback: displayFallback,
    fontSize: base.fontSize == null ? null : base.fontSize! * titleScale,
  );

  /// [base] wearing the body face. Body text is NOT scaled — reading size is
  /// the user's business (Text Brightness and the TV screen-size factor
  /// already speak to it) and a theme has no claim on it.
  TextStyle body(TextStyle base) => base.copyWith(
    fontFamily: bodyFamily,
    fontFamilyFallback: bodyFallback,
  );
}
