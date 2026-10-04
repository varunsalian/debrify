import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'support/merged_detail_source.dart';
import 'support/catalog_detail_source.dart';

void main() {
  test(
    'both detail screens refresh completion on mutations and unsubscribe',
    () {
      for (final path in [
        'catalog_item_detail_screen',
        'merged_series_detail_screen',
      ]) {
        final source = path == 'merged_series_detail_screen'
            ? mergedDetailSource()
            : catalogDetailSource();
        for (final notifier in [
          'MovieProgressStorage.movieFinishedRevision',
          'MdblistService.instance.watchedRevision',
        ]) {
          if (path == 'merged_series_detail_screen') {
            expect(
              mergedCompletionListenerSite(
                source,
                'initState',
                notifier,
                'addListener',
              ),
              isTrue,
            );
            expect(
              mergedCompletionListenerSite(
                source,
                'dispose',
                notifier,
                'removeListener',
              ),
              isTrue,
            );
          } else {
            expect(
              catalogCompletionListenerSite(
                source,
                'initState',
                notifier,
                'addListener',
              ),
              isTrue,
            );
            expect(
              catalogCompletionListenerSite(
                source,
                'dispose',
                notifier,
                'removeListener',
              ),
              isTrue,
            );
          }
        }
        expect(source, contains('generation == _movieCompletionGeneration'));
      }
    },
  );
  test('shared detail screens require restart capability before resetting', () {
    final catalog = catalogDetailSource();
    final primary = catalogOriginalMember(
      '_CatalogItemDetailScreenState._playPrimary',
    );
    expect(primary, contains('if (restart == null'));
    expect(primary, contains('await resetProgressForRewatch'));
    final action = catalog.substring(
      catalog.indexOf('Future<void> _playPrimary()'),
    );
    expect(
      action.indexOf('if (restart == null'),
      lessThan(action.indexOf('await resetProgressForRewatch')),
    );
    expect(action, contains('restart();'));
    expect(action, isNot(contains('(widget.onRewatch ?? widget.onPlay)()')));
    final merged = mergedDetailSource();
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
    final detail = File(
      'lib/features/home/presentation/home_detail_presentation.dart',
    ).readAsStringSync();
    final source = File(
      'lib/features/home/data/home_catalog_playback_resolver.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<HomeCatalogPlaybackTarget?> resolve(');
    final branch = source.indexOf('if (startFromBeginning)', start);
    final end = source.indexOf('\n    }', branch);
    final launch = source.substring(branch, end);
    expect(launch, contains('return HomeCatalogPlaybackTarget.play('));
    expect(launch, contains("season: item.type == 'series' ? 1 : null"));
    expect(launch, contains("episode: item.type == 'series' ? 1 : null"));
    for (final tracker in ['trakt', 'simkl', 'mdblist']) {
      expect(launch, contains('${tracker}ProgressPercent: 0'));
    }
    expect(launch, contains('AdvancedSearchSelection('));
    expect(
      branch,
      lessThan(source.indexOf('await seriesResume.resolve(', start)),
    );
    expect(RegExp('startFromBeginning: true').allMatches(detail).length, 2);
  });
}

// Bound to the main State declaration and its owning lifecycle method. Only
// whitespace and one optional formatter comma are accepted at the call site.
bool mergedCompletionListenerSite(
  String source,
  String declaration,
  String notifier,
  String operation,
) {
  final stateStart = source.indexOf('class _MergedDetailScreenState ');
  if (stateStart < 0) return false;
  final tail = source.substring(stateStart);
  final stateEnd = RegExp(r'^}', multiLine: true).firstMatch(tail);
  if (stateEnd == null) return false;
  final state = tail.substring(0, stateEnd.end);
  final start = RegExp(
    r'^  void ' + RegExp.escape(declaration) + r'\(\)\s*\{',
    multiLine: true,
  ).firstMatch(state);
  if (start == null) return false;
  final end = RegExp(
    r'^  }',
    multiLine: true,
  ).firstMatch(state.substring(start.end));
  if (end == null) return false;
  final body = state.substring(start.start, start.end + end.end);
  final expression = notifier.split('.').map(RegExp.escape).join(r'\s*\.\s*');
  return RegExp(
    r'^\s*' +
        expression +
        r'\s*\.\s*' +
        RegExp.escape(operation) +
        r'\s*\(\s*_loadLocalMovieFinished\s*,?\s*\)',
    multiLine: true,
  ).hasMatch(body);
}
