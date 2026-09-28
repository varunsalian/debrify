import 'package:debrify/features/home/presentation/home_art_poster.dart';
import 'package:debrify/features/home/presentation/home_favorite_cell.dart';
import 'package:debrify/features/home/presentation/home_favorite_focus.dart';
import 'package:debrify/features/home/presentation/home_stage_favorite_cards.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final preview in [true, false]) {
    test(
      'IPTV keeps captured action and focus-time metadata, preview=$preview',
      () {
        final node = FocusNode();
        addTearDown(node.dispose);
        final first = IptvChannel(
          name: 'First',
          url: 'https://example.invalid/1',
        );
        var selected = first;
        IptvChannel? opened;
        IptvChannel? live;
        HomeFavoriteFocus? focused;
        var subtitle = 'Before';
        final events = <String>[];
        final cards = HomeStageFavoriteCards(
          nodes: [node],
          column: 0,
          showTitle: false,
          onLeftEdge: () => events.add('sidebar'),
          onUp: () => events.add('up'),
          onDown: () => events.add('down'),
          onDownHold: () => events.add('hold'),
          onFocused: (value, channel) {
            focused = value;
            live = channel;
          },
        );
        final captured = selected;
        final cell =
            cards.iptv(
                  captured,
                  subtitle: () => subtitle,
                  previewLive: preview,
                  onOpen: () => opened = captured,
                )
                as HomeFavoriteCell;
        final poster = cell.child as HomeArtPoster;
        selected = IptvChannel(name: 'Next', url: 'https://example.invalid/2');
        subtitle = 'After';
        poster.onOpen();
        poster.onFocused!();
        expect(opened, same(first));
        expect(opened, isNot(same(selected)));
        expect(focused!.subtitle, 'After');
        expect(live, preview ? same(first) : isNull);
        expect(poster.showTitle, isFalse);
        expect(poster.imageFit, BoxFit.contain);
        expect(poster.focusNode, same(node));
        cell.onLeftEdge();
        cell.onUp();
        cell.onDown();
        cell.onDownHold!();
        expect(events, ['sidebar', 'up', 'down', 'hold']);
      },
    );
  }
}
