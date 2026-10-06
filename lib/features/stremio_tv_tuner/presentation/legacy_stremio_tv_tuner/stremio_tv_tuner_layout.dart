import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_dependencies.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_owners.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_sections.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/legacy_stremio_tv_tuner/stremio_tv_tuner_widget_view.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/stremio_tv_tuner_dial_card.dart';
import 'package:debrify/features/stremio_tv_tuner/presentation/stremio_tv_tuner_stage.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class StremioTvTunerLayout {
  final StremioTvTunerDependencies _deps;
  StremioTvTunerLayout(this._deps);
  StremioTvTunerWidgetView get widget => _deps.view;
  StremioTvTunerOwners get _owners => _deps.owners;
  StremioTvTunerSections get _sections => _deps.sections();

  // --- Wide: Stage + Dial -------------------------------------------------

  Widget buildWide() {
    final app = AppThemeScope.of(_deps.context());
    final dial = widget.channels
        .where((c) => _sections.channels.nodeFor(c) != null)
        .toList();
    assert(
      dial.length == widget.channels.length,
      'Dial dropped ${widget.channels.length - dial.length} channel(s) with '
      'no focus node — channels must be a subset of allChannels.',
    );

    return Column(
      children: [
        Expanded(
          // No ValueKey remount on channel change: the Stage persists and
          // animates its content in place (text cascade, continuous Ken Burns
          // breathe) — the Home hero's model — instead of hard-swapping the
          // whole subtree every surf step. The ValueListenableBuilder scopes
          // a surf step's rebuild to the Stage alone.
          child: ValueListenableBuilder<String?>(
            valueListenable: _owners.activeId,
            builder: (context, activeId, _) {
              final active = _sections.channels.channelById(activeId);
              if (active == null) return const SizedBox.shrink();
              widget.ensureLoaded(active);
              final np = _sections.channels.nowPlaying(active);
              final stage = StremioTvTunerStage(
                channel: active,
                ident: _sections.channels.identFor(active),
                nowPlaying: np,
                nextPlaying: _sections.channels.nextPlaying(active),
                displayProgress: _sections.channels.displayProgress(active, np),
                hideNowPlaying: widget.hideNowPlaying,
                isTelevision: widget.isTelevision,
                loading: widget.loadingChannelIds.contains(active.id),
              );
              // Touch: the hero is the biggest target on screen and, until
              // now, the only inert one — tapping it plays what it is showing,
              // long-press opens the same quick actions as a dial card. TV and
              // desktop keep playing from the dial (OK / click), where focus
              // already lives.
              if (!_sections.dial.touchDial) return stage;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onPlay(active),
                onLongPress: () => _sections.sheets.openActions(active),
                child: stage,
              );
            },
          ),
        ),
        // Dial area
        Container(
          height: 240,
          decoration: BoxDecoration(
            // Indigo-tinted wash (was flat black) so the dial shelf melts into
            // the Home page background instead of reading as a separate panel.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                app.home.bg.withValues(alpha: 0.0),
                app.home.bg.withValues(alpha: 0.72),
              ],
            ),
            border: Border(
              top: BorderSide(color: app.stremioTv.hairline, width: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 14),
            // Desktop can't move DPAD focus to auto-scroll and a vertical mouse
            // wheel doesn't pan a horizontal list, so translate the wheel to a
            // horizontal offset; ScrollConfiguration also enables mouse/trackpad
            // drag. Touch and DPAD focus-scroll are unaffected.
            child: Listener(
              onPointerSignal: (signal) {
                if (signal is! PointerScrollEvent) return;
                if (!_owners.dialScroll.hasClients) return;
                // Only translate a VERTICAL wheel: a horizontal Scrollable
                // already applies horizontal (dx) deltas itself, so handling
                // those here too would double-scroll a trackpad swipe.
                final dy = signal.scrollDelta.dy;
                if (dy == 0) return;
                final target = (_owners.dialScroll.offset + dy).clamp(
                  0.0,
                  _owners.dialScroll.position.maxScrollExtent,
                );
                _owners.dialScroll.jumpTo(target);
              },
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(_deps.context()).copyWith(
                  dragDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                  },
                ),
                // Touch: settle onto the nearest card when the fling stops, so
                // the dial always comes to rest on the channel the Stage above
                // is showing.
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.depth == 0 && n is ScrollEndNotification)
                      _sections.dial.snapDial();
                    return false;
                  },
                  // The centre padding (touch only) is a function of the dial's
                  // own width, so it has to be measured here rather than from
                  // the page constraints.
                  child: LayoutBuilder(
                    builder: (context, dialConstraints) => ListView.builder(
                      controller: _owners.dialScroll,
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(
                        horizontal: _sections.dial.dialLeadingPadFor(
                          dialConstraints.maxWidth,
                        ),
                      ),
                      itemCount: dial.length,
                      itemBuilder: (context, i) {
                        final channel = dial[i];
                        widget.ensureLoaded(channel);
                        final node = _sections.channels.nodeFor(channel)!;
                        final np = _sections.channels.nowPlaying(channel);
                        return StremioTvTunerDialCard(
                          key: ValueKey(channel.id),
                          channel: channel,
                          ident: _sections.channels.identFor(channel),
                          focusNode: node,
                          nowPlaying: np,
                          displayProgress: _sections.channels.displayProgress(
                            channel,
                            np,
                          ),
                          hideNowPlaying: widget.hideNowPlaying,
                          loading: widget.loadingChannelIds.contains(
                            channel.id,
                          ),
                          isTelevision: widget.isTelevision,
                          // Touch only: the centred card wears the gold ring so
                          // the selection is visible before you scroll. Null on
                          // TV / desktop keeps the cards independent of the
                          // active id, so surfing never re-runs them.
                          centredId: _sections.dial.touchDial
                              ? _owners.centredId
                              : null,
                          touchSelect: _sections.dial.touchDial,
                          onFocused: () =>
                              _sections.channels.setActive(channel),
                          onSelect: () => widget.onPlay(channel),
                          onLongPress: () =>
                              _sections.sheets.openActions(channel),
                          onLeft: () => _sections.channels.surf(channel, i, -1),
                          onRight: () => _sections.channels.surf(channel, i, 1),
                          onUp: widget.onFocusHeader,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Narrow: full-screen vertical channel pager -------------------------

  Widget buildNarrow() {
    return PageView.builder(
      controller: _owners.pageController,
      scrollDirection: Axis.vertical,
      itemCount: widget.channels.length,
      onPageChanged: (i) {
        final c = widget.channels[i];
        widget.ensureLoaded(c);
        if (i + 1 < widget.channels.length) {
          widget.ensureLoaded(widget.channels[i + 1]);
        }
        _sections.channels.setActive(c);
      },
      itemBuilder: (context, i) {
        final channel = widget.channels[i];
        widget.ensureLoaded(channel);
        final np = _sections.channels.nowPlaying(channel);
        return GestureDetector(
          onTap: () => widget.onPlay(channel),
          onLongPress: () => _sections.sheets.openActions(channel),
          child: StremioTvTunerStage(
            channel: channel,
            ident: _sections.channels.identFor(channel),
            nowPlaying: np,
            nextPlaying: _sections.channels.nextPlaying(channel),
            displayProgress: _sections.channels.displayProgress(channel, np),
            hideNowPlaying: widget.hideNowPlaying,
            isTelevision: widget.isTelevision,
            loading: widget.loadingChannelIds.contains(channel.id),
            onOpenList: _sections.sheets.openChannelList,
            onOpenDetail: () => widget.onOpenDetail(channel),
          ),
        );
      },
    );
  }
}
