import 'package:flutter_test/flutter_test.dart';

import '../../../../support/iptv_results_source.dart';

void main() {
  String member(String name) =>
      iptvOriginalMember('IptvResultsViewState.$name');

  void ordered(String source, List<String> markers) {
    var previous = -1;
    for (final marker in markers) {
      final at = source.indexOf(marker, previous + 1);
      expect(at, greaterThan(previous), reason: 'Missing/reordered: $marker');
      previous = at;
    }
  }

  test('preview floor, native plane and chip retain their paint order', () {
    final stage = member('_buildPreviewStage');
    ordered(stage, [
      'Stack(',
      '_IptvStageFloor(',
      'HeroTrailerBackdrop(',
      '_IptvStageChip(',
    ]);
    expect(stage, contains('borderRadius: BorderRadius.circular(8)'));
    expect(stage, contains('httpHeaders: ch.playbackHeaders'));
    expect(stage, isNot(contains('child: Opacity(')));
    expect(stage, isNot(contains('child: ColoredBox(')));
    expect(member('_buildCockpitStage'), contains('RepaintBoundary('));
  });

  test('landing seed is armed once and disarmed at both present sites', () {
    final load = member('_loadPlaylistInner');
    ordered(load, [
      '_categoryManuallyChosen = false',
      '_landingSeedArmed = true',
    ]);
    for (final name in ['_presentCatalog', '_presentDbCatalog']) {
      final present = member(name);
      ordered(present, ['_landingCategory(', '_landingSeedArmed = false']);
    }
  });

  test('unchanged digest keeps re-pinning before selected-category repair', () {
    final refresh = member('_applyDbCatalogRefresh');
    ordered(refresh, [
      'fresh.contentDigest == old.contentDigest',
      '!numberingAdded',
      'all.repin(fresh)',
      'filtered.repin(fresh)',
      'if (selectedVanished) _applyFilters()',
      '// Real change.',
    ]);
    expect(refresh, contains('if (_revalidateSuperseded('));
  });

  test(
    'changed digest repairs the same index, attached fallback, then filter',
    () {
      final refresh = member('_applyDbCatalogRefresh');
      ordered(refresh, [
        'final oldFilteredIndex',
        '_applyFilters();',
        'WidgetsBinding.instance.addPostFrameCallback',
        'final focusLost',
        'oldFilteredIndex.clamp',
        'if (_rowAttached(candidate))',
        'for (final entry in _cardFocusNodes.entries)',
        '(target ?? _playlistFilterFocusNode).requestFocus()',
      ]);
      expect(
        refresh.substring(refresh.indexOf('final focusLost')),
        isNot(contains('indexOfInstance(focusedChannel)')),
      );
    },
  );

  test('launcher uses resident instances and materializes its SQL window', () {
    final play = member('_playChannelInner');
    final resident = member('_residentDbRow');
    ordered(resident, [
      'await _adoptStartupCategoryValue(channel.group)',
      'final list = _filteredChannels',
      'beforePosition: entry.position',
      'final row = list[index]',
      'return row',
    ]);
    expect(member('_resolveStartupRow'), contains('_residentDbRow('));
    expect(play, contains('source.effectiveSnapshot.page('));
    expect(play, contains('VideoPlayerLauncher.push('));
    expect(play, contains('iptvBrowseProvider: _providePlayerIptvBrowse'));
    final catchup = member('_playCatchup');
    expect(catchup, contains('IptvChannel('));
    expect(catchup, contains('VideoPlayerLauncher.push('));
    expect(member('_playerChannelWithOrigin'), contains('attributes:'));
  });

  test(
    'catalog loading rejects stale tickets and keeps deferred cleanup unconditional',
    () {
      final load = member('_loadPlaylistInner');
      expect(load, contains('if (!mounted || ticket != _loadTicket) return;'));
      final start = load.indexOf('final outgoingNodes');
      final end = load.indexOf('if (contentHadFocus)', start);
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final cleanup = load.substring(start, end);
      ordered(cleanup, [
        '_cardFocusNodes.clear()',
        '_detachedRows.clear()',
        'WidgetsBinding.instance.addPostFrameCallback',
        'node.dispose()',
      ]);
      expect(cleanup, isNot(contains('if (!mounted) return')));
    },
  );

  test(
    'startup settings chain and cancellation keep their pre-launch guards',
    () {
      ordered(member('initState'), [
        '_loadSettings().then',
        'mounted && _settingsError == null',
        '_maybeRunStartupLaunch()',
      ]);
      final startup = member('_maybeRunStartupLaunch');
      ordered(startup, [
        '_resolveStartupRow(',
        '_scrollAndFocusStartupRow(',
        '_playChannel(',
      ]);
      expect(startup, contains('_startupAttempt'));
    },
  );

  test('lazy catalog and stage reads retain their original boundaries', () {
    final list = member('_makeDbList');
    expect(list, contains('instanceCache: _instanceCacheFor(snap)'));
    expect(list, contains('onPageLoaded:'));
    final stage = member('_buildCockpitStage');
    expect(stage, contains('ValueListenableBuilder<IptvChannel?>('));
    expect(stage, contains('valueListenable: _previewShown'));
    final content = member('_buildContent');
    expect(content, contains('itemBuilder:'));
    expect(content, contains('_focusNodeFor(channel)'));
    expect(content, contains('onDetached:'));
  });

  test(
    'lifecycle keeps observer, listener, timers and child-resource order',
    () {
      ordered(member('dispose'), [
        'revision.removeListener',
        '_sourceCountsDebounce?.cancel()',
        '_androidRecStateDebounce?.cancel()',
        'schedulesRevision.removeListener',
        'removeObserver(this)',
        '_searchDebounce?.cancel()',
        '_contentTypeDebounce?.cancel()',
        '_loadTicker?.cancel()',
        '_maintenanceChipTimer?.cancel()',
        '_chipShowTimer?.cancel()',
        '_chipHideTimer?.cancel()',
        '_scrollController.dispose()',
        '_previewShown.dispose()',
        '_previewStreamUrl.dispose()',
        'node.dispose()',
        'super.dispose()',
      ]);
      for (final owner in ['_IptvStageFloorState', '_IptvStageChipState']) {
        ordered(iptvOriginalMember('$owner.dispose'), [
          '_ctrl.dispose()',
          'super.dispose()',
        ]);
      }
      ordered(
        iptvOriginalMember('_SpotlightCategoryPickerDialogState.dispose'),
        [
          '_scrollController.dispose()',
          '_selectedFocusNode.dispose()',
          'super.dispose()',
        ],
      );
    },
  );
}
