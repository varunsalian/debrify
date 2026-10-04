import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/detail_showcase_source.dart';

const showcasePublicNames = {
  'ShowcaseMetrics',
  'ShowcaseMetricsScope',
  'kShowcaseGutter',
  'ShowcaseAmbient',
  'ShowcaseBackdropScrim',
  'ShowcaseStickyLogo',
  'ShowcaseIdentity',
  'ShowcaseSeasons',
  'ShowcaseEpisodeCell',
  'ShowcaseEpisodeCardCompact',
  'ShowcaseCast',
  'ShowcaseSources',
  'ShowcaseRecs',
  'ShowcaseGuide',
  'ShowcaseUniverse',
  'ShowcaseDidYouKnow',
  'ShowcaseBandNote',
  'ShowcaseDetails',
};

void main() {
  test('facade exported namespace is exactly the original eighteen names', () {
    final source = File(showcaseFacade).readAsStringSync();
    final declarations =
        RegExp(r'^(?:class|const double) (\w+)', multiLine: true)
            .allMatches(source)
            .map((m) => m[1]!)
            .where((n) => !n.startsWith('_'))
            .toList();
    final exported =
        RegExp(
              r"^export '[^']+'\s+show\s+([^;]+);",
              multiLine: true,
              dotAll: true,
            )
            .allMatches(source)
            .expand((m) => m[1]!.split(',').map((n) => n.trim()))
            .toList();
    final names = [...declarations, ...exported];
    expect(names.toSet(), showcasePublicNames);
    expect(names, hasLength(18));
    for (final name in showcasePublicNames) {
      expect(showcaseDeclaration(name), contains(name));
    }
    if (showcaseComplete) {
      expect(declarations, isEmpty);
      expect(
        source
            .replaceAll(
              RegExp(r"export '[^']+'\s+show\s+[^;]+;", dotAll: true),
              '',
            )
            .trim(),
        isEmpty,
      );
    }
  });
}
