import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_bindings.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_composition.dart';
import 'package:debrify/features/spotlight_board/presentation/legacy_spotlight_board/spotlight_board_owners.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/debrify_image_cache.dart';
import 'package:debrify/utils/dominant_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SpotlightBoardAmbient {
  final SpotlightBoardDependencies _deps;
  SpotlightBoardAmbient(this._deps);
  SpotlightBoardWidgetView get view => _deps.view;
  SpotlightBoardOwners get _owners => _deps.owners;
  SpotlightBoardSections get _sections => _deps.sections;
  void emitAmbient(String? art, Color? tint) {
    final next = (art: art, tint: tint);
    final sink = view.onAmbient;
    if (identical(sink, _owners.hero.lastAmbientSink) &&
        next == _owners.hero.lastAmbient) {
      return;
    }
    _owners.hero.lastAmbientSink = sink;
    _owners.hero.lastAmbient = next;
    sink?.call(art, tint);
  }

  Future<void> probe() async {
    // The RESOLVED art, not the raw fields — tint and side-flip must be
    // measured on the image actually drawn.
    final gen = ++_owners.hero.probeGen;
    final item = _sections.heroArt.heroItem;
    final url = item == null ? null : _sections.heroArt.heroArt(item);
    if (url == null || url.isEmpty) {
      _sections.ambient.emitAmbient(null, null);
      return;
    }

    // Publish FIRST from cache when we have it. Skipping the publish for a
    // cached URL meant paging A→B→A left B's art and tint on the shell —
    // the cache short-circuited the only code path that told anyone.
    if (_owners.hero.tints.containsKey(url)) {
      _sections.ambient.emitAmbient(url, _owners.hero.tints[url]);
    } else {
      // Update the shell immediately; colour extraction may wait on a decode.
      _sections.ambient.emitAmbient(url, null);
      final tint = await extractDominantColor(
        CachedNetworkImageProvider(
          url,
          cacheManager: DebrifyImageCache.manager,
        ),
      );
      if (!_deps.mounted() || gen != _owners.hero.probeGen) return;
      _deps.setState(() => _sections.ambient.remember(url, tint));
      _sections.ambient.emitAmbient(url, tint);
    }
    unawaited(_sections.ambient.warmNext());
  }

  /// Luminance of the extracted colour stands in for "is the left third busy":
  /// a bright dominant means a bright image, and a bright image is one whose
  /// text side cannot be trusted. A true left-third measurement would be
  /// better and is noted in the plan.
  void remember(String url, Color? tint) {
    _owners.hero.leftThird[url] = tint == null ? 0.0 : tint.computeLuminance();
    _owners.hero.tints[url] = tint;
  }

  /// Resolve the NEXT slide's art while this one is still showing.
  ///
  /// Without this, freezing the side below would mean every slide's FIRST
  /// appearance used the default side, because the probe cannot possibly have
  /// finished by the time the slide is drawn. The cadence gives us seconds of
  /// lead time; one image is a cheap way to spend it.
  Future<void> warmNext() async {
    if (view.hero.length < 2) return;
    final next =
        view.hero[(_sections.heroArt.heroIndex + 1) % view.hero.length];
    final url = _sections.heroArt.heroArt(next);
    if (url == null || url.isEmpty || _owners.hero.tints.containsKey(url)) {
      return;
    }
    final tint = await extractDominantColor(
      CachedNetworkImageProvider(url, cacheManager: DebrifyImageCache.manager),
    );
    if (!_deps.mounted()) return;
    _deps.setState(() => _sections.ambient.remember(url, tint));
  }

  String? get heroAlignmentItemId => _owners.hero.flipFor;

  /// The side the identity sits on, FROZEN for as long as an item is showing.
  ///
  /// This used to read `_leftThird` directly on every build. That map is
  /// filled by an async probe, so a slide appeared with its logo on one side
  /// and then, a second or two later, jumped to the other as the probe landed
  /// — the one thing a title card must never do while someone is reading it.
  ///
  /// Memoised by item id rather than recomputed: a probe that resolves for the
  /// slide currently on screen updates the map for NEXT time, and moves
  /// nothing now. `_warmNext` is what keeps "next time" from being the common
  /// case.
  bool get flip {
    final item = _sections.heroArt.heroItem;
    if (item == null) return false;
    // The missing URL is temporary during provider loading. Do not freeze
    // the default side before the resolved artwork's cached tint is usable.
    if (view.metadataArtworkPending(MetadataCategory.backgrounds)) return false;
    if (_owners.hero.flipFor != item.id) {
      _owners.hero.flipFor = item.id;
      final url = _sections.heroArt.heroArt(item);
      _owners.hero.flipValue =
          url != null &&
          (_owners.hero.leftThird[url] ?? 0) > view.leftThirdBusy;
    }
    return _owners.hero.flipValue;
  }
}
