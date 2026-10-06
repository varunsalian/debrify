import 'package:debrify/models/tv_render_quality.dart';

/// One Android TV "Screen Size" choice. [percent] is the share of the panel's
/// native density the UI is laid out at — smaller means a wider logical canvas,
/// so the same layouts draw smaller and more fits on screen. Values must stay in
/// step with `StorageService.kTvUiScaleOptions`; the shipped default is
/// `StorageService.kTvUiScaleDefault`.
///
/// Lives here (not in the TV settings shell) because two surfaces render it:
/// the TV Mode rail row's caption and the Screen Size page itself.
class TvUiScaleChoice {
  final int percent;
  final String title;
  final String subtitle;
  const TvUiScaleChoice(this.percent, this.title, this.subtitle);

  /// "Compact (80%)" — the row caption and the page's selected label.
  String get label => '$title ($percent%)';
}

const List<TvUiScaleChoice> kTvUiScaleChoices = [
  TvUiScaleChoice(100, 'Large', 'The original size — everything bigger'),
  TvUiScaleChoice(90, 'Medium', 'Default — about 10% more fits on screen'),
  TvUiScaleChoice(80, 'Compact', 'About 25% more fits on screen'),
];

/// Caption for [percent], falling back to the raw value if a stored size is
/// ever outside the offered set.
String tvUiScaleLabel(int percent) {
  for (final c in kTvUiScaleChoices) {
    if (c.percent == percent) return c.label;
  }
  return '$percent%';
}

/// One entry in the Android TV "Rendering" picker.
class TvRenderQualityChoice {
  final TvRenderQuality quality;
  final String label;
  final String subtitle;
  const TvRenderQualityChoice(this.quality, this.label, this.subtitle);
}

/// Automatic first: it's the default, and it's the only option that leaves the
/// device-capability call intact. The other two are named for the TRADE, not
/// for the mechanism — nobody browsing settings knows what a render buffer is,
/// but everybody knows which of "sharper" and "smoother" they want right now.
const List<TvRenderQualityChoice> kTvRenderQualityChoices = [
  TvRenderQualityChoice(
    TvRenderQuality.auto,
    'Automatic',
    "Default — Debrify picks based on this TV's graphics",
  ),
  TvRenderQualityChoice(
    TvRenderQuality.sharp,
    'Sharper picture',
    'Draw at the panel\'s full resolution',
  ),
  TvRenderQualityChoice(
    TvRenderQuality.fast,
    'Smoother navigation',
    'Draw at about 720p so scrolling stays fluid — text and art look softer',
  ),
];

/// Caption for [quality] — the settings row's subtitle and the picker's
/// selected label.
String tvRenderQualityLabel(TvRenderQuality quality) {
  for (final c in kTvRenderQualityChoices) {
    if (c.quality == quality) return c.label;
  }
  return 'Automatic';
}
