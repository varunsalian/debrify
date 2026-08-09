import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files inside a still-frozen surface that have been converted to the token
/// layer ahead of their root's classification flip.
///
/// Phase two lands a surface in two parts: preparatory commits that tokenise
/// leaves while the root stays frozen, then one small commit that lifts the
/// boundary and flips `AppSurfaces.tabs`. Without this list the frozen-surface
/// guard below forbids the first part, so the whole surface would have to move
/// in one unreviewable diff — which is exactly what phase one warned against
/// (`APP_THEME_ROLLOUT_PLAN.md:417`).
///
/// A file listed here reads the app theme but is STILL SHADOWED by its root's
/// `LegacyThemeBoundary`, so it resolves to legacy and renders unchanged until
/// the flip. Entries are removed when their surface lands — the list should be
/// empty between surfaces, and a stale entry means a migration was abandoned
/// half-done.
const Set<String> kThemingPrepared = {};

/// Source-level tripwires for the containment rules a type system can't see.
///
/// A hand-maintained allow-list cannot notice the next excluded-screen
/// construction someone adds — these greps can. They are deliberately dumb:
/// a determined evasion will beat them, but the realistic failure (a new
/// call site written by pattern-matching on neighbouring code) will not.
void main() {
  test('VideoPlayerScreen is constructed only where the freeze exists', () {
    const allowed = {
      'lib/screens/video_player_screen.dart', // itself
      'lib/screens/magic_tv_screen.dart', // 12 pushes, all FrozenLegacyPageRoute
      'lib/services/video_player_launcher.dart', // the one shared factory
    };
    final offenders = <String>[];
    for (final file in _libDartFiles()) {
      if (allowed.contains(_rel(file))) continue;
      if (_code(file).contains('VideoPlayerScreen(')) {
        offenders.add(_rel(file));
      }
    }
    expect(offenders, isEmpty,
        reason:
            'VideoPlayerScreen constructed outside the frozen push paths — '
            'route it through pushExcluded/FrozenLegacyPageRoute '
            '(theme/app_surfaces.dart): $offenders');
  });

  test('magic_tv_screen pushes the player only via FrozenLegacyPageRoute', () {
    final source = _code(File('lib/screens/magic_tv_screen.dart'));
    expect(source.contains('MaterialPageRoute'), isFalse,
        reason: 'a raw MaterialPageRoute in magic_tv_screen would push an '
            'excluded screen without the legacy freeze');
  });

  test('video_player_launcher pushes via FrozenLegacyPageRoute', () {
    final source = _code(File('lib/services/video_player_launcher.dart'));
    expect(source.contains('FrozenLegacyPageRoute'), isTrue);
    expect(source.contains('MaterialPageRoute'), isFalse);
  });

  test('frozen tab roots are constructed only by main.dart', () {
    // DebrifyTVScreen / StremioTvScreen / BrowseScreen / PlaylistScreen /
    // DownloadsScreen are tab bodies; main.dart wraps them via the
    // tab-boundary factory. A construction anywhere else bypasses it.
    const roots = {
      'DebrifyTVScreen': 'lib/screens/magic_tv_screen.dart',
      'StremioTvScreen': 'lib/screens/stremio_tv/stremio_tv_screen.dart',
      'BrowseScreen': 'lib/screens/browse_screen.dart',
      'PlaylistScreen': 'lib/screens/playlist_screen.dart',
      'DownloadsScreen': 'lib/screens/downloads_screen.dart',
    };
    final offenders = <String>[];
    for (final file in _libDartFiles()) {
      final rel = _rel(file);
      if (rel == 'lib/main.dart') continue;
      final code = _code(file);
      for (final entry in roots.entries) {
        if (rel == entry.value) continue; // its own defining file
        // Word boundary on the left: `TorboxDownloadsScreen(` must not match
        // the `DownloadsScreen(` guard.
        if (RegExp('(?<![A-Za-z0-9_])${entry.key}\\(').hasMatch(code)) {
          offenders.add('$rel → ${entry.key}(');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'frozen tab root constructed outside main.dart\'s '
            'tab-boundary factory: $offenders');
  });

  test('frozen surfaces never read the app theme', () {
    // The freeze is structural (LegacyThemeBoundary shadows the scope), so a
    // read here would still RESOLVE — to legacy — and look fine today. It
    // would only bite later, when someone moves the widget or lifts the
    // boundary. Cheaper to forbid the read outright.
    // Must cover every file a frozen surface RENDERS, not just its tab root.
    // Fifteen kThemingPrepared entries were previously invisible to this guard
    // because their paths were absent here — the allow-list looked like it was
    // doing work while the guard could not see the files at all.
    const frozen = [
      // Phase two flipped Playlist, Downloads, Debrify TV, Stremio TV, IPTV
      // and YouTube. What remains frozen is PLAYBACK, permanently — it has its
      // own stable theme and does not follow the app palette.
      'lib/screens/video_player_screen.dart',
      'lib/screens/video_player/',
    ];
    final offenders = <String>[];
    for (final file in _libDartFiles()) {
      final rel = _rel(file);
      if (!frozen.any(rel.startsWith)) continue;
      if (kThemingPrepared.contains(rel)) continue;
      if (_code(file).contains('AppThemeScope')) offenders.add(rel);
    }
    expect(offenders, isEmpty,
        reason: 'excluded surfaces must not consume the app theme '
            '(add the file to kThemingPrepared if it is mid-migration): '
            '$offenders');
  });

  test('every kThemingPrepared entry is actually inside a frozen surface', () {
    // Without this, an entry can sit in the allow-list doing nothing because
    // the guard's prefix list never reaches its path — the allow-list appears
    // to be holding a file back while the guard is blind to it. Fifteen
    // entries were in exactly that state.
    const frozen = [
      'lib/widgets/iptv/',
      'lib/screens/iptv/',
      'lib/widgets/youtube/',
      'lib/screens/stremio_tv/',
      'lib/screens/browse_screen.dart',
      'lib/screens/magic_tv_screen.dart',
      'lib/screens/debrify_tv/',
      'lib/screens/playlist_screen.dart',
      'lib/screens/playlist_content_view_screen.dart',
      'lib/services/playlist_player_service.dart',
      'lib/widgets/adaptive_playlist_section.dart',
      'lib/widgets/playlist_grid_card.dart',
      'lib/widgets/tvmaze_search_dialog.dart',
      'lib/screens/downloads_screen.dart',
      'lib/screens/video_player_screen.dart',
      'lib/screens/video_player/',
    ];
    final stray = kThemingPrepared
        .where((f) => !frozen.any(f.startsWith))
        .toList();
    expect(stray, isEmpty,
        reason: 'kThemingPrepared entry outside every frozen prefix, so the '
            'frozen-surface guard cannot see it: $stray');
  });

  test('a themed surface never pushes a frozen child route', () {
    // The inverse of the guard above, and the one that would otherwise ship a
    // half-frozen tab. Flipping a tab's classification does NOT theme the
    // routes it pushes — Navigator.push does not inherit from below, which is
    // why phase one wrapped exclusions at their entry points rather than
    // wrapping the themed side.
    //
    // So a surface that has LEFT the frozen set must not still push
    // FrozenLegacyPageRoute, or its list is themed while its detail is legacy.
    // Two deliberate exceptions, both allow-listed by name:
    //   * playback, which stays outside the app palette permanently (see
    //     plan/APP_THEME_PHASE_TWO_PLAN.md hazard 2);
    //   * a themed surface pushing INTO a frozen surface's own screen, which
    //     is not a leftover but the correct containment — see the sibling test
    //     below, which enforces the other direction.
    const frozenDestinationPushers = {
      'lib/theme/legacy_theme_boundary.dart', // defines it
      'lib/theme/app_surfaces.dart', // the boundary factory that vends it
      'lib/services/video_player_launcher.dart', // the shared player factory
      'lib/screens/magic_tv_screen.dart', // 12 player pushes
      'lib/screens/playlist_screen.dart', // player push
      'lib/screens/downloads_screen.dart', // player push
    };
    const stillFrozen = [
      // Phase two flipped Playlist, Downloads, Debrify TV, Stremio TV, IPTV
      // and YouTube. What remains frozen is PLAYBACK, permanently — it has its
      // own stable theme and does not follow the app palette.
      'lib/screens/video_player_screen.dart',
      'lib/screens/video_player/',
    ];
    final offenders = <String>[];
    for (final file in _libDartFiles()) {
      final rel = _rel(file);
      if (frozenDestinationPushers.contains(rel)) continue;
      if (stillFrozen.any(rel.startsWith)) continue;
      // Both spellings: pushExcluded is the factory wrapper over the route,
      // so searching only for the route class misses half the call sites.
      final code = _code(file);
      if (code.contains('FrozenLegacyPageRoute') ||
          code.contains('pushExcluded')) {
        offenders.add(rel);
      }
    }
    expect(offenders, isEmpty,
        reason: 'a themed surface still pushes a frozen child route — remove '
            'the freeze, or allow-list it if the destination is playback or '
            'another frozen surface\'s screen: $offenders');
  });

  // NOTE: the "frozen surface's child screen is never pushed unwrapped" test
  // lived here. It existed because PlaylistContentViewScreen was wrapped from
  // the Playlist tab and pushed bare from Search, so the same screen resolved
  // two different palettes depending on the route. Phase two themed Playlist,
  // both doors now agree, and playback — the only remaining frozen surface —
  // is already covered by the VideoPlayerScreen guards above.
  //
  // Restore this if a surface is ever frozen again with a pushable child.

  test('the split kept its constants alive for frozen callers', () {
    // The whole point of splitting rather than converting: frozen surfaces go
    // on importing these. Deleting one because "nothing themed uses it any
    // more" would break IPTV/YouTube/Stremio TV.
    for (final entry in {
      'lib/widgets/home/home_theme.dart': ['focusGold', 'chromeAccent', 'bg'],
      'lib/widgets/see_all/see_all_theme.dart': [
        'kSeeAllBg',
        'kSeeAllAccent',
        'kSeeAllPanel',
      ],
    }.entries) {
      final source = _code(File(entry.key));
      for (final symbol in entry.value) {
        // A DECLARATION, not a mention: a bare `contains` stays green when
        // the name survives only in a doc comment or an unrelated reference,
        // which is exactly the state that would break frozen callers.
        final declared = RegExp(
          r'(?:^|\s)(?:static\s+)?const\s+(?:Color\s+)?' +
              RegExp.escape(symbol) +
              r'\s*=',
          multiLine: true,
        );
        expect(declared.hasMatch(source), isTrue,
            reason: '${entry.key} must still DECLARE $symbol — frozen '
                'surfaces import it');
      }
    }
  });

  test('main.dart routes tabs through the boundary factory', () {
    final source = _code(File('lib/main.dart'));
    expect(source.contains('AppSurfaces.wrapTab('), isTrue,
        reason: '_buildPage must route every destination through '
            'AppSurfaces.wrapTab');
  });
}

// ── helpers ────────────────────────────────────────────────────────────────

final String _root = Directory.current.path;

Iterable<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    // Deprecated trees keep dead references; they are not entry points.
    .where((f) => !f.path.contains('/deprecated/'));

String _rel(File f) => f.path.startsWith(_root)
    ? f.path.substring(_root.length + 1)
    : f.path;

/// File text with line comments stripped, so commented-out code (of which the
/// deprecated screens left plenty) can't trip a guard.
String _code(File f) => f
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');
