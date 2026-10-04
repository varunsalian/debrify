import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/widgets/home/row_tag_pill.dart';
import 'package:flutter/material.dart';

/// What a card is, once a shelf stops being a list of TITLES.
///
/// Continue Watching and the catalog are `StremioMeta`; the favourites rails
/// are not. A playlist is a container, not a title — it has no poster of its
/// own, which is why poster OVERRIDES exist — and an IPTV channel's logo is a
/// wide, often transparent mark that a 2:3 crop destroys. Forcing all four
/// through a poster model is how they end up looking wrong in four different
/// ways.
class SpotlightCard {
  final StremioMeta? metadata;
  final bool episodeArtwork;

  /// Poster, channel logo, or a user override. Null draws the placeholder.
  final String? image;

  /// Used when [image] fails to load. Landscape title cards point this at the
  /// portrait poster because synchronously-derived MetaHub backdrops can 404.
  final String? fallbackImage;

  /// Image-download errors obey the same policy as missing metadata artwork.
  String? imageErrorFallback(
    StremioMeta? presented,
    MetadataPreferences preferences,
  ) {
    if (episodeArtwork) {
      return preferences.provider(MetadataCategory.episodeArtwork) !=
                  MetadataPreferences.current &&
              !preferences.fallback
          ? null
          : fallbackImage;
    }
    if (presented == null || identical(presented, metadata))
      return fallbackImage;
    bool selected(MetadataCategory category) =>
        preferences.provider(category) != MetadataPreferences.current;
    final selectedArtwork =
        (shape == SpotlightCardShape.wide &&
            selected(MetadataCategory.backgrounds)) ||
        (shape == SpotlightCardShape.poster &&
            selected(MetadataCategory.posters));
    if (selectedArtwork && !preferences.fallback) return null;
    return selectedArtwork || selected(MetadataCategory.posters)
        ? presented.poster
        : fallbackImage;
  }

  String? imageForPresentation(
    StremioMeta? presented,
    MetadataPreferences preferences,
  ) {
    final changed = presented != null && !identical(presented, metadata);
    bool selected(MetadataCategory category) =>
        preferences.provider(category) != MetadataPreferences.current;
    final primary = !changed || episodeArtwork
        ? image
        : shape == SpotlightCardShape.poster &&
              selected(MetadataCategory.posters)
        ? presented.poster
        : shape == SpotlightCardShape.wide &&
              selected(MetadataCategory.backgrounds)
        ? presented.background
        : image;
    return primary?.trim().isNotEmpty == true
        ? primary
        : imageErrorFallback(presented, preferences);
  }

  final String? coverEmoji;
  final String title;

  /// Item count, "LIVE", a genre — whatever this KIND of thing is identified
  /// by beyond its name.
  final String? subtitle;

  /// IMDb rating (0–10) for TITLE cards, drawn as "★ 8.1" on the caption's
  /// meta line. Null or non-positive draws nothing — catalog list items
  /// frequently omit the rating, and an empty star would read as a zero.
  final double? rating;

  /// 0..100, or null.
  final double? progress;

  final VoidCallback onOpen;
  final VoidCallback? onOptions;
  final SpotlightCardShape shape;
  final bool showCaption;

  /// Title identity for the effective watched marker. Null for channels,
  /// playlists, and other non-title cards.
  final String? watchedImdbId;
  final String? watchedContentType;

  /// Collection GIFs follow the device preference; collection videos need focus.
  final String? collectionGifUrl;
  final String? collectionVideoUrl;

  /// A lightweight, in-card preview for the one card the user is actively
  /// inspecting. It is built only while the card is hovered on pointer
  /// surfaces, or holds DPAD focus on television; resting cards never mount a
  /// player/decoder.
  final WidgetBuilder? previewBuilder;
  final bool focusGlowEnabled;

  /// Collection art also follows keyboard focus on desktop. Live IPTV keeps
  /// its pointer-only desktop preview policy.
  final bool previewOnKeyboardFocus;

  const SpotlightCard({
    this.metadata,
    this.episodeArtwork = false,
    required this.title,
    required this.onOpen,
    this.image,
    this.fallbackImage,
    this.coverEmoji,
    this.subtitle,
    this.rating,
    this.progress,
    this.onOptions,
    this.shape = SpotlightCardShape.poster,
    this.showCaption = true,
    this.previewBuilder,
    this.collectionGifUrl,
    this.collectionVideoUrl,
    this.focusGlowEnabled = false,
    this.previewOnKeyboardFocus = false,
    this.watchedImdbId,
    this.watchedContentType,
  });
}

/// Aspect and fit, per kind.
enum SpotlightCardShape {
  /// 2:3, art cropped to fill. Titles.
  poster(2 / 3, BoxFit.cover),

  /// Square collection cover, cropped to fill.
  square(1, BoxFit.cover),

  /// 1:1, art CONTAINED on a plate. A channel logo is a mark, not a still:
  /// cropping it to fill cuts the wordmark in half.
  channel(1, BoxFit.contain),

  /// 16:9, cropped. Containers and wide art.
  wide(16 / 9, BoxFit.cover),

  /// 16:9, mark CONTAINED on a plate — a channel tile at the landscape
  /// rail's full card size. The logo is never cropped to fill (that cuts
  /// wordmarks in half); the live preview, which IS 16:9, fills the tile
  /// edge to edge on focus/hover.
  wideChannel(16 / 9, BoxFit.contain);

  const SpotlightCardShape(this.aspect, this.fit);

  /// width ÷ height.
  final double aspect;
  final BoxFit fit;
}

/// One row on the board.
///
/// [progressOf] is what makes Continue Watching possible without the board
/// knowing what Continue Watching IS: a shelf that returns null for every
/// item simply draws no bars.
class SpotlightShelf {
  final String title;
  final List<SpotlightCard> items;

  /// This shelf's focus nodes, owned by the host so focus survives a rebuild.
  /// Carried HERE rather than in a parallel list, because two lists that must
  /// stay the same length eventually will not be.
  final List<FocusNode> nodes;

  /// Opens this row's See-All destination. Null when the row leads nowhere
  /// (the favourites rails browse in place), and the heading then draws no
  /// chevron — the reference's own rule, not an oversight.
  final VoidCallback? onSeeAll;

  /// The row's provenance — the addon or tracker filling it ("Cinemeta",
  /// "Trakt") — worn as a small [RowTagPill] beside the heading on every
  /// device. Null draws no pill (the favourites rails ARE their source).
  final String? tag;

  /// Whether this shelf's cards keep their captions off TV. Catalog rows say
  /// false — the art is the label, and a caption repeating the poster's own
  /// title is the noise the reference never has. Rows whose caption carries
  /// INFORMATION keep true: Continue Watching (which title, how far),
  /// channels (a logo tile without its name is a guess), playlists. TV keeps
  /// captions regardless — this flag is a non-TV presentation choice.
  final bool captions;

  /// Whether the shelf heading, provenance pill and See-All affordance paint.
  /// Collection rows may opt out while their cards remain fully interactive.
  final bool showHeader;

  /// Stable identity for element reuse across board updates. Tracker rows
  /// stream in and FRONT-INSERT above the catalog rows; without identity the
  /// board's list reconciles shelves by position and remounts every shelf
  /// below the insertion point — horizontal scroll offsets reset and every
  /// visible card's texture re-resolves and re-uploads, which a Mali box
  /// renders as a jank burst. Null falls back to positional (no reuse).
  final String? id;

  const SpotlightShelf({
    required this.title,
    required this.items,
    required this.nodes,
    this.onSeeAll,
    this.tag,
    this.captions = true,
    this.showHeader = true,
    this.id,
  });
}
