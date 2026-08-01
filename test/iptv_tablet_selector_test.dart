import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/iptv/iptv_centered_selector.dart';
import 'package:debrify/widgets/iptv/iptv_epg_panel.dart';
import 'package:debrify/widgets/iptv/iptv_results_view.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('large touch tablet layout policy', () {
    bool useLayout({
      TargetPlatform platform = TargetPlatform.android,
      Size size = const Size(1024, 700),
      bool television = false,
      bool web = false,
    }) {
      return IptvResultsViewState.shouldUseTouchTabletTwoPane(
        isTelevision: television,
        isWeb: web,
        platform: platform,
        availableSize: size,
      );
    }

    test('accepts large Android and iOS canvases', () {
      expect(useLayout(), isTrue);
      expect(useLayout(platform: TargetPlatform.iOS), isTrue);
    });

    test('rejects constrained, non-touch, web, and TV layouts', () {
      expect(useLayout(size: const Size(899, 700)), isFalse);
      expect(useLayout(size: const Size(1024, 499)), isFalse);
      expect(useLayout(platform: TargetPlatform.macOS), isFalse);
      expect(useLayout(web: true), isFalse);
      expect(useLayout(television: true), isFalse);
    });
  });

  testWidgets('fixed arrow stays put while a tapped row snaps to center', (
    tester,
  ) async {
    final selections = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 300,
            child: IptvCenteredSelector(
              itemCount: 5,
              itemExtent: 60,
              onSelected: selections.add,
              itemBuilder: (context, index, selected, centerItem) {
                return GestureDetector(
                  key: ValueKey('selector-item-$index'),
                  behavior: HitTestBehavior.opaque,
                  onTap: centerItem,
                  child: Container(
                    key: selected ? ValueKey('selected-item-$index') : null,
                    alignment: Alignment.center,
                    child: Text('Channel $index'),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(selections, [0]);
    expect(find.byKey(const ValueKey('selected-item-0')), findsOneWidget);
    final arrowBefore = tester.getCenter(
      find.byKey(const ValueKey('iptv-tablet-selector-arrow')),
    );
    final arrow = tester.widget<Container>(
      find.byKey(const ValueKey('iptv-tablet-selector-arrow')),
    );
    final arrowDecoration = arrow.decoration! as BoxDecoration;
    expect(arrowDecoration.color, kSeeAllAccent.withValues(alpha: 0.18));
    final arrowIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('iptv-tablet-selector-arrow')),
        matching: find.byIcon(Icons.arrow_right_rounded),
      ),
    );
    expect(arrowIcon.color, kSeeAllAccent2);

    await tester.tap(find.byKey(const ValueKey('selector-item-2')));
    await tester.pumpAndSettle();

    expect(selections.last, 2);
    expect(find.byKey(const ValueKey('selected-item-2')), findsOneWidget);
    expect(
      tester.getCenter(
        find.byKey(const ValueKey('iptv-tablet-selector-arrow')),
      ),
      arrowBefore,
    );
  });

  testWidgets('scroll settling selects only the row beneath the arrow', (
    tester,
  ) async {
    final selections = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 300,
            child: IptvCenteredSelector(
              itemCount: 6,
              itemExtent: 60,
              onSelected: selections.add,
              itemBuilder: (context, index, selected, centerItem) {
                return GestureDetector(
                  onTap: centerItem,
                  child: Center(child: Text('Channel $index')),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.timedDrag(
      find.byKey(const ValueKey('iptv-tablet-centered-list')),
      const Offset(0, -62),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();

    expect(selections, [0, 1]);
  });

  testWidgets('progressive batches preserve the centered channel', (
    tester,
  ) async {
    final selections = <String>[];
    var channels = ['Channel 0', 'Channel 1', 'Channel 2'];
    var selectedIndex = 0;
    Object selectedToken = channels.first;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 300,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return IptvCenteredSelector(
                  key: const ValueKey('stable-progressive-selector'),
                  itemCount: channels.length,
                  itemExtent: 60,
                  initialIndex: selectedIndex,
                  selectionToken: selectedToken,
                  onSelected: (index) {
                    selectedIndex = index;
                    selectedToken = channels[index];
                    selections.add(channels[index]);
                  },
                  itemBuilder: (context, index, selected, centerItem) {
                    return GestureDetector(
                      key: ValueKey('progressive-item-$index'),
                      behavior: HitTestBehavior.opaque,
                      onTap: centerItem,
                      child: Container(
                        key: selected
                            ? ValueKey('progressive-selected-$index')
                            : null,
                        alignment: Alignment.center,
                        child: Text(channels[index]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('progressive-item-2')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('progressive-selected-2')),
      findsOneWidget,
    );

    selections.clear();
    rebuild(() {
      channels = [...channels, 'Channel 3', 'Channel 4'];
    });
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('progressive-selected-2')),
      findsOneWidget,
    );
    expect(selections, isNot(contains('Channel 0')));

    // Once the parent configuration has caught up with the settled row,
    // another cumulative List replacement must be completely selection-free.
    selections.clear();
    rebuild(() {
      channels = [...channels, 'Channel 5'];
    });
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('progressive-selected-2')),
      findsOneWidget,
    );
    expect(selections, isEmpty);
  });

  testWidgets('tablet in-place schedule has an explicit touch back action', (
    tester,
  ) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IptvSchedulePane(
            channel: IptvChannel(
              name: 'News',
              url: 'https://example.com/news.m3u8',
            ),
            isTelevision: false,
            onClose: () => closed = true,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('iptv-schedule-back')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('iptv-schedule-back')));
    expect(closed, isTrue);
  });
}
