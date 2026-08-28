import 'package:flutter/foundation.dart';

import 'storage_service.dart';

/// Which look the play → resolve loader wears (Settings → Appearance → Play
/// Loader).
///
/// [marquee] is the default: a full-bleed backdrop with the title's logo art,
/// the meta line the detail page already fetched, and the four resolve stages
/// collapsed into a segmented rail. [classic] is the poster-and-checklist card
/// this loader shipped with.
///
/// Read synchronously from [cached] — [PipelineLoadingOverlay.show] is called
/// from a synchronous play path and cannot await a preference. The default is
/// the shipped default, so an unwarmed read is only ever wrong for someone who
/// explicitly chose Classic; [warm] runs at startup and on profile switch.
abstract final class PlayLoaderStyleController {
  static const String marquee = 'marquee';
  static const String classic = 'classic';
  static const String defaultStyle = marquee;

  /// Picker metadata, in display order.
  static const List<({String id, String label, String blurb})> options = [
    (
      id: marquee,
      label: 'Marquee',
      blurb: 'Full-bleed backdrop, title logo, stages on a segmented rail',
    ),
    (
      id: classic,
      label: 'Classic',
      blurb: 'Poster card with the stage checklist — the original look',
    ),
  ];

  static const Set<String> valid = {marquee, classic};

  static String labelFor(String id) =>
      options.firstWhere((o) => o.id == id, orElse: () => options.first).label;

  /// Synchronous mirror for the play path. Never read a stale value as truth
  /// for anything but presentation.
  static String cached = defaultStyle;

  /// Load the stored choice. Swallows storage failures: a cosmetic pref must
  /// never keep a play (or the app) from starting, and [cached] already holds
  /// the safe default.
  static Future<void> warm() async {
    try {
      cached = await StorageService.getPlayLoaderStyle();
    } catch (e) {
      debugPrint('PlayLoaderStyle: warm failed, staying $cached: $e');
    }
  }

  /// Publish first, then persist — same reasoning as the text-brightness
  /// controller: rapid re-selections must apply in tap order, and a failed
  /// write costs only stickiness across restart.
  static Future<void> select(String style) async {
    final normalized = valid.contains(style) ? style : defaultStyle;
    cached = normalized;
    try {
      await StorageService.setPlayLoaderStyle(normalized);
    } catch (e) {
      debugPrint('PlayLoaderStyle: write failed for $normalized: $e');
    }
  }
}
