import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/theme/app_surfaces.dart';

/// The containment plan's first gate: every destination index has an explicit
/// themed/frozen entry. A new tab added without classifying it here fails the
/// build instead of silently changing colour (and until classified it renders
/// FROZEN — the safe failure).
void main() {
  test('classification covers exactly 0..tabCount-1', () {
    expect(AppSurfaces.tabs.length, AppSurfaces.tabCount);
    for (var i = 0; i < AppSurfaces.tabCount; i++) {
      expect(AppSurfaces.tabs.containsKey(i), isTrue,
          reason: 'tab index $i has no themed/frozen classification');
    }
  });

  test('unmapped indices fail safe to frozen', () {
    expect(AppSurfaces.kindForTab(AppSurfaces.tabCount), SurfaceKind.frozen);
    expect(AppSurfaces.kindForTab(-1), SurfaceKind.frozen);
  });

  test('the frozen set is exactly the plan\'s exclusion list', () {
    final frozen = <int>[
      for (final e in AppSurfaces.tabs.entries)
        if (e.value == SurfaceKind.frozen) e.key,
    ]..sort();
    // 0 inert slot, 1 Playlist (deferred), 2 Downloads (deferred),
    // 3 Debrify TV, 9 Stremio TV, 13 IPTV, 14 YouTube.
    // Phase two flipped 1/2/3/9/13/14 (Playlist, Downloads, Debrify TV,
    // Stremio TV, IPTV, YouTube). Index 0 is the inert deprecated-Home slot
    // and stays frozen — it is unreachable, not deferred, so the end state is
    // [0] rather than empty. Playback is excluded at its ENTRY POINTS rather
    // than by tab, so it does not appear here.
    expect(frozen, [0]);
  });

  test('tabCount matches the registry length in main.dart', () {
    // _titles is private to main.dart; pin its length by source. If a tab is
    // added there, this fails until AppSurfaces.tabs classifies it.
    final source = _readMainDart();
    final listBody = RegExp(
      r'final List<String> _titles = \[(.*?)\];',
      dotAll: true,
    ).firstMatch(source);
    expect(listBody, isNotNull,
        reason: 'could not locate _titles registry in lib/main.dart');
    // Count top-level string literals — every entry starts with a quote at
    // line start after whitespace.
    final entries = RegExp(r"^\s*'", multiLine: true)
        .allMatches(listBody!.group(1)!)
        .length;
    expect(entries, AppSurfaces.tabCount,
        reason:
            'main.dart\'s _titles has $entries entries but AppSurfaces.tabCount '
            'is ${AppSurfaces.tabCount} — classify the new destination');
  });
}

String _readMainDart() {
  // Tests run with CWD at the package root.
  return io.File('lib/main.dart').readAsStringSync();
}
