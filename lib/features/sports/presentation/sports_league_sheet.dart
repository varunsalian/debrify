// The Sports & leagues sheet: which catalog leagues the Sports board shows.
//
// Presentation layer. Two panes — sports on the left with how many of their
// leagues are on, the selected sport's "All" switch and league switches on the
// right — over the app-wide [sportsLeagueFilterProvider]; every switch writes
// through that notifier and nothing else. The same sheet opens from the
// board's filter button and from IPTV settings.
//
// Remote: up/down move within a pane, left/right move between the panes,
// Select toggles (or, on a sport, steps into its leagues), Back closes, and
// focus returns to whatever opened the sheet. A phone stacks the panes and
// turns the sports into a horizontal strip.
import 'dart:async';

import 'package:debrify/features/sports/application/sports_board_sports.dart';
import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sports_labels.dart';
import 'sports_league_sheet_rows.dart';
import 'sports_team_crest.dart';

const _tokens = IptvStyleTokens.spotlight;
const _maxWidth = 920.0;
const _maxHeight = 640.0;
const _sportsPaneWidth = 260.0;

/// At least this wide and the panes sit side by side.
const _twoPaneMinWidth = 640.0;

/// Opens the sheet over the nearest root navigator and, once it closes,
/// returns focus to the control that opened it.
Future<void> showSportsLeagueSheet(BuildContext context) async {
  final opener = FocusManager.instance.primaryFocus;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close Sports & leagues',
    barrierColor: const Color(0x9E02060E),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => const SportsLeagueSheet(),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
  // A popped route hands focus to its scope, not to a control; put it back
  // on the opener so the remote resumes where it was.
  if (opener != null && opener.context != null && opener.canRequestFocus) {
    opener.requestFocus();
  }
}

class SportsLeagueSheet extends ConsumerStatefulWidget {
  const SportsLeagueSheet({super.key});

  @override
  ConsumerState<SportsLeagueSheet> createState() => _SportsLeagueSheetState();
}

class _SportsLeagueSheetState extends ConsumerState<SportsLeagueSheet> {
  final List<SportsLeagueGroup> _groups = sportsLeagueGroups(kSportsLeagues);
  late final List<FocusNode> _sportNodes;
  late final List<FocusNode> _allNodes;
  late final Map<String, FocusNode> _leagueNodes;
  int _selected = 0;

  /// Opened from a remote or keyboard: start with a focused sport so the
  /// arrows have a target. Opened by touch, nothing is lit until tapped.
  final bool _keyboardOpened =
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    _sportNodes = [
      for (final (index, group) in _groups.indexed)
        FocusNode(debugLabel: 'sports-sheet-${group.sport.name}')
          ..addListener(() => _onSportFocus(index)),
    ];
    _allNodes = [
      for (final group in _groups)
        FocusNode(debugLabel: 'sports-sheet-all-${group.sport.name}'),
    ];
    _leagueNodes = {
      for (final league in kSportsLeagues)
        league.id: FocusNode(debugLabel: 'sports-sheet-${league.id}'),
    };
  }

  @override
  void dispose() {
    for (final node in [..._sportNodes, ..._allNodes, ..._leagueNodes.values]) {
      node.dispose();
    }
    super.dispose();
  }

  /// Moving through the sports shows each one's leagues.
  void _onSportFocus(int index) {
    if (_sportNodes[index].hasFocus && _selected != index && mounted) {
      setState(() => _selected = index);
    }
  }

  void _pickSport(int index) {
    final fromRemote = _sportNodes[index].hasFocus;
    setState(() => _selected = index);
    // Select on a sport steps into its leagues; a tap only shows them.
    if (fromRemote) _focusLeagues();
  }

  void _focusLeagues() {
    final node = _allNodes[_selected];
    if (node.context != null) {
      node.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _allNodes[_selected].requestFocus();
    });
  }

  KeyEventResult _onPaneKey(KeyEvent event, {required bool sportsPane}) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (sportsPane && key == LogicalKeyboardKey.arrowRight) {
      _focusLeagues();
      return KeyEventResult.handled;
    }
    if (!sportsPane && key == LogicalKeyboardKey.arrowLeft) {
      _sportNodes[_selected].requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Runs one write; a failed write is logged and the sheet keeps showing
  /// the notifier's state, which never moved for it.
  void _write(Future<void> Function(SportsLeagueFilterNotifier notifier) run) {
    final notifier = ref.read(sportsLeagueFilterProvider.notifier);
    unawaited(
      run(notifier).catchError((Object error) {
        debugPrint('Sports: saving league choices failed: $error');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sportsLeagueFilterProvider);
    final filter = async.value ?? const SportsLeagueFilter();
    return LayoutBuilder(
      builder: (context, constraints) => _sheet(
        filter,
        failed: async.hasError && !async.hasValue,
        width: (constraints.maxWidth - 32).clamp(0.0, _maxWidth),
        height: (constraints.maxHeight * 0.92).clamp(0.0, _maxHeight),
      ),
    );
  }

  Widget _sheet(
    SportsLeagueFilter filter, {
    required bool failed,
    required double width,
    required double height,
  }) {
    final twoPane = width >= _twoPaneMinWidth;
    return Center(
      child: SizedBox(
        key: const ValueKey('sports-league-sheet'),
        width: width,
        height: height,
        child: Material(
          color: _tokens.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: _tokens.hairline2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _header(),
              _rule(),
              Expanded(
                child: twoPane
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: _sportsPaneWidth,
                            child: _pane(sportsPane: true, _sportsList(filter)),
                          ),
                          Container(width: 1, color: _tokens.hairline),
                          Expanded(
                            child: _pane(sportsPane: false, _leagues(filter)),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          SizedBox(height: 60, child: _sportsStrip(filter)),
                          _rule(),
                          Expanded(child: _leagues(filter)),
                        ],
                      ),
              ),
              _rule(),
              _footer(filter, failed: failed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pane(Widget child, {required bool sportsPane}) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) => _onPaneKey(event, sportsPane: sportsPane),
    child: FocusTraversalGroup(child: child),
  );

  Widget _rule() => Container(height: 1, color: _tokens.hairline);

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: sportsLabelText(
                  'Sports & leagues',
                  _tokens.fg,
                  size: 17,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              sportsLabelText(
                'Choose what shows on the Sports board. Also in Settings › '
                'IPTV.',
                _tokens.fgDim,
                size: 12.5,
                maxLines: 2,
                ellipsize: true,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SportsSheetButton(
          key: const ValueKey('sports-sheet-close'),
          label: 'Close',
          icon: Icons.close_rounded,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );

  int _onCount(SportsLeagueGroup group, SportsLeagueFilter filter) =>
      group.leagues.where(filter.isEnabled).length;

  Widget _sportsList(SportsLeagueFilter filter) => ListView(
    padding: const EdgeInsets.all(8),
    children: [
      for (final (index, group) in _groups.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _sportRow(index, group, filter, compact: false),
        ),
    ],
  );

  Widget _sportsStrip(SportsLeagueFilter filter) => ListView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    children: [
      for (final (index, group) in _groups.indexed) ...[
        if (index > 0) const SizedBox(width: 8),
        _sportRow(index, group, filter, compact: true),
      ],
    ],
  );

  Widget _sportRow(
    int index,
    SportsLeagueGroup group,
    SportsLeagueFilter filter, {
    required bool compact,
  }) => SportsSheetSportRow(
    key: ValueKey('sports-sheet-sport-${group.sport.name}'),
    sport: group.sport,
    on: _onCount(group, filter),
    total: group.leagues.length,
    selected: index == _selected,
    focusNode: _sportNodes[index],
    autofocus: _keyboardOpened && index == _selected,
    compact: compact,
    onPressed: () => _pickSport(index),
  );

  Widget _leagues(SportsLeagueFilter filter) {
    final group = _groups[_selected];
    final name = sportsKindName(group.sport);
    final allOn = group.leagues.every(filter.isEnabled);
    return ListView(
      key: ValueKey('sports-sheet-leagues-${group.sport.name}'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      children: [
        SportsSheetSwitchRow(
          key: ValueKey('sports-sheet-all-${group.sport.name}'),
          title: 'All ${name.toLowerCase()}',
          subtitle:
              '${group.leagues.length} '
              '${group.leagues.length == 1 ? 'league' : 'leagues'}',
          value: allOn,
          focusNode: _allNodes[_selected],
          onToggle: () => _write((n) => n.setSport(group.sport, !allOn)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
          child: sportsLabelText(
            'LEAGUES',
            _tokens.fgDim,
            size: 11,
            weight: FontWeight.w700,
            tracking: 1.3,
          ),
        ),
        for (final (index, league) in group.leagues.indexed) ...[
          if (index > 0) Container(height: 1, color: _tokens.hairline),
          SportsSheetSwitchRow(
            key: ValueKey('sports-sheet-league-${league.id}'),
            title: league.name,
            subtitle: sportsLeagueDescription(league.id),
            value: filter.isEnabled(league),
            focusNode: _leagueNodes[league.id]!,
            onToggle: () =>
                _write((n) => n.setLeague(league, !filter.isEnabled(league))),
          ),
        ],
      ],
    );
  }

  Widget _footer(SportsLeagueFilter filter, {required bool failed}) {
    final on = enabledSportsLeagues(kSportsLeagues, filter).length;
    final summary = failed
        ? "Couldn't load your choices; showing the defaults."
        : '$on of ${kSportsLeagues.length} leagues on';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          sportsLabelText(
            summary,
            failed ? _tokens.rec : _tokens.fgDim,
            size: 12.5,
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SportsSheetButton(
                key: const ValueKey('sports-sheet-reset'),
                label: 'Reset to defaults',
                onPressed: () => _write((n) => n.reset()),
              ),
              SportsSheetButton(
                key: const ValueKey('sports-sheet-done'),
                label: 'Done',
                primary: true,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
