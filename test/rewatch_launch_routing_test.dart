import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'support/lib_source.dart';

const _catalogScreen = 'lib/screens/catalog_item_detail_screen.dart';
const _catalogAction =
    'lib/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_primary_action.dart';
const _mergedScreen = 'lib/screens/merged_series_detail_screen.dart';
const _mergedDetail =
    'lib/features/merged_detail/presentation/legacy_merged_detail';

void main() {
  test(
    'both detail screens refresh completion on mutations and unsubscribe',
    () {
      for (final (screen, state, loader, owner, generation) in [
        (
          _catalogScreen,
          '_CatalogItemDetailScreenState',
          '_p.loadLocalMovieFinished',
          (_catalogAction, 'CatalogDetailPrimaryAction'),
          'generation == movieCompletionGeneration',
        ),
        (
          _mergedScreen,
          '_MergedDetailScreenState',
          '_ta.loadLocalMovieFinished',
          (
            '$_mergedDetail/merged_detail_tracking_actions.dart',
            'MergedDetailTrackingActions',
          ),
          'generation == _k.movieCompletionGeneration',
        ),
      ]) {
        final init = libMember(screen, 'initState', owner: state);
        final dispose = libMember(screen, 'dispose', owner: state);
        for (final notifier in [
          'MovieProgressStorage.movieFinishedRevision',
          'MdblistService.instance.watchedRevision',
        ]) {
          expect(
            completionListenerSite(init, notifier, 'addListener', loader),
            isTrue,
            reason: '$state.initState $notifier',
          );
          expect(
            completionListenerSite(dispose, notifier, 'removeListener', loader),
            isTrue,
            reason: '$state.dispose $notifier',
          );
        }
        expect(
          libMember(owner.$1, 'loadLocalMovieFinished', owner: owner.$2),
          contains(generation),
        );
      }
    },
  );
  test('shared detail screens require restart capability before resetting', () {
    final catalog = libJoined(
      libSourceSet(
        files: [_catalogScreen],
        directories: ['lib/features/catalog_detail'],
      ),
    );
    final primary = libMember(
      _catalogAction,
      'playPrimary',
      owner: 'CatalogDetailPrimaryAction',
    );
    expect(primary, contains('if (restart == null'));
    expect(primary, contains('await resetProgressForRewatch'));
    expect(
      primary.indexOf('if (restart == null'),
      lessThan(primary.indexOf('await resetProgressForRewatch')),
    );
    expect(primary, contains('restart();'));
    // Rewatch never falls back to plain Play through a null-coalesced callback.
    expect(catalog, isNot(contains(RegExp(r'onRewatch(?:\(\))?\s*\?\?'))));
    final merged = libJoined(
      libSourceSet(files: [_mergedScreen], directories: [_mergedDetail]),
    );
    final rewatch = libMember(
      '$_mergedDetail/merged_detail_playback_actions.dart',
      'rewatchTitle',
      owner: 'MergedDetailPlaybackActions',
    );
    expect(
      rewatch.indexOf('if (restart == null) return;'),
      lessThan(rewatch.indexOf('await resetProgressForRewatch')),
    );
    expect(rewatch, isNot(contains('onResume')));
    for (final screen in [catalog, merged]) {
      expect(
        screen,
        contains(
          "_deps.onRewatch() == null && resolvedPrimaryLabel == 'Rewatch'",
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

// Bound to one lifecycle method body. Only whitespace and one optional
// formatter comma are accepted at the call site.
bool completionListenerSite(
  String body,
  String notifier,
  String operation,
  String loader,
) {
  final expression = notifier.split('.').map(RegExp.escape).join(r'\s*\.\s*');
  return RegExp(
    r'^\s*' +
        expression +
        r'\s*\.\s*' +
        RegExp.escape(operation) +
        r'\s*\(\s*' +
        loader.split('.').map(RegExp.escape).join(r'\s*\.\s*') +
        r'\s*,?\s*\)',
    multiLine: true,
  ).hasMatch(body);
}
