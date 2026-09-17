import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'both detail screens refresh completion on mutations and unsubscribe',
    () {
      for (final path in [
        'catalog_item_detail_screen',
        'merged_series_detail_screen',
      ]) {
        final source = File('lib/screens/$path.dart').readAsStringSync();
        for (final notifier in [
          'StorageService.movieFinishedRevision',
          'MdblistService.instance.watchedRevision',
        ]) {
          expect(
            source,
            contains('$notifier.addListener(_loadLocalMovieFinished)'),
          );
          expect(
            source,
            contains('$notifier.removeListener(_loadLocalMovieFinished)'),
          );
        }
        expect(source, contains('generation == _movieCompletionGeneration'));
      }
    },
  );
  test('shared detail screens require restart capability before resetting', () {
    final catalog = File(
      'lib/screens/catalog_item_detail_screen.dart',
    ).readAsStringSync();
    final action = catalog.substring(
      catalog.indexOf('Future<void> _playPrimary()'),
    );
    expect(
      action.indexOf('if (restart == null'),
      lessThan(action.indexOf('await resetProgressForRewatch')),
    );
    expect(action, contains('restart();'));
    expect(action, isNot(contains('(widget.onRewatch ?? widget.onPlay)()')));
    final merged = File(
      'lib/screens/merged_series_detail_screen.dart',
    ).readAsStringSync();
    final rewatch = merged.substring(
      merged.indexOf('Future<void> _rewatchTitle()'),
      merged.indexOf('void _browsePrimarySources()'),
    );
    expect(
      rewatch.indexOf('if (restart == null) return;'),
      lessThan(rewatch.indexOf('await resetProgressForRewatch')),
    );
    expect(rewatch, isNot(contains('widget.onResume')));
    for (final screen in [catalog, merged]) {
      expect(
        screen,
        contains(
          "widget.onRewatch == null && _resolvedPrimaryLabel == 'Rewatch'",
        ),
      );
    }
  });
  test('rewatch exits before cached tracker reconciliation, even for S1E1', () {
    final source = File('lib/screens/search_screen.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _onCatalogPlay(');
    final branch = source.indexOf('if (startFromBeginning)', start);
    final end = source.indexOf('\n      }', branch);
    final launch = source.substring(branch, end);
    expect(launch, contains('await launch(AdvancedSearchSelection('));
    expect(launch, contains("season: item.type == 'series' ? 1 : null"));
    expect(launch, contains("episode: item.type == 'series' ? 1 : null"));
    for (final tracker in ['trakt', 'simkl', 'mdblist']) {
      expect(launch, contains('${tracker}ProgressPercent: 0'));
    }
    expect(launch, contains('return;'));
    expect(
      branch,
      lessThan(source.indexOf('await _reconcileSeriesResume(', start)),
    );
    expect(RegExp('startFromBeginning: true').allMatches(source).length, 2);
  });
}
