import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    const frozen = [
      'lib/widgets/iptv/',
      'lib/widgets/youtube/',
      'lib/screens/stremio_tv/',
      'lib/screens/browse_screen.dart',
      'lib/screens/magic_tv_screen.dart',
      'lib/screens/playlist_screen.dart',
      'lib/screens/downloads_screen.dart',
      'lib/screens/video_player_screen.dart',
      'lib/screens/video_player/',
    ];
    final offenders = <String>[];
    for (final file in _libDartFiles()) {
      final rel = _rel(file);
      if (!frozen.any(rel.startsWith)) continue;
      if (_code(file).contains('AppThemeScope')) offenders.add(rel);
    }
    expect(offenders, isEmpty,
        reason: 'excluded surfaces must not consume the app theme: $offenders');
  });

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
