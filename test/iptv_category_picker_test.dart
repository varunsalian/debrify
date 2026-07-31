import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';

/// The guide's category control. It used to be a horizontally scrolling chip
/// row, which a mouse cannot scroll — on desktop every chip past the fold was
/// unreachable, and so were the "More" menu and the Saved filter sitting
/// behind them. It is now a searchable picker.
void main() {
  // Long enough that the old chip row would have overflowed many times over.
  final categories = <String>[
    for (var i = 1; i <= 60; i++) 'Category $i',
    'UK| SPORT ON AIR',
    'DE| DOKU UHD',
  ];

  // The group deliberately does not match any category name: rows render
  // their group, and a collision would make the finders below ambiguous.
  List<IptvChannel> channels() => [
    for (var i = 1; i <= 3; i++)
      IptvChannel(
        channelNumber: i,
        name: 'Channel $i',
        url: 'http://example.com/live/$i.ts',
        group: 'Feeds',
        duration: -1,
      ),
  ];

  Future<void> pumpSheet(WidgetTester tester, {String? selectedCategory}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IptvChannelSheet(
            channels: channels(),
            currentIndex: 0,
            onChannelSelected: (_, __) async {},
            onClose: () {},
            categories: categories,
            selectedCategory: selectedCategory,
            sourceName: 'Test Source',
          ),
        ),
      ),
    );
    // Let the entrance animation settle without waiting on the EPG timers the
    // rows arm, which never resolve under test.
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the filter bar fits without needing to be scrolled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpSheet(tester);

    // The old row rendered a chip per category; the whole point of the picker
    // is that the bar is now a fixed set of controls.
    expect(find.text('Category 1'), findsNothing);
    expect(find.text('Category 60'), findsNothing);
    // Saved used to be pushed off the end of the row by the chips.
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('All'), findsOneWidget); // the category dropdown
  });

  // The bar is a fixed Row now, so it has no scroll to fall back on if the
  // three controls do not fit.
  testWidgets('filter bar does not overflow on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpSheet(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('picker opens, filters as you type, and reports the pick', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpSheet(tester);

    await tester.tap(find.text('All'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Category'), findsOneWidget); // dialog title

    // Reaching a category far down the list is what the old chip row could
    // not do. The list is lazy, so "reachable" means reachable by typing —
    // which is the guarantee that actually matters here.
    await tester.enterText(find.byType(TextField).last, 'category 60');
    await tester.pump();
    expect(find.text('Category 60'), findsOneWidget);
    expect(find.text('Category 1'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'doku');
    await tester.pump();
    expect(find.text('DE| DOKU UHD'), findsOneWidget);
    expect(find.text('Category 1'), findsNothing);

    await tester.tap(find.text('DE| DOKU UHD'));
    await tester.pump(const Duration(milliseconds: 400));

    // Dialog closed and the button now reads the picked category.
    expect(find.text('Category'), findsNothing);
    expect(find.text('DE| DOKU UHD'), findsOneWidget);
  });

  testWidgets('a query matching nothing says so instead of showing an empty list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpSheet(tester);
    await tester.tap(find.text('All'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField).last, 'zzzzz');
    await tester.pump();
    expect(find.textContaining('No category matches'), findsOneWidget);
  });

  // Native treats search as a temporary all-categories context
  // (beginIptvAllCategorySearch). Confining it to the selected category made
  // the obvious search — pick a category, look for a channel in another —
  // silently return nothing.
  testWidgets('search browses every category, then restores the one it left', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final requests = <Map<String, dynamic>>[];
    Future<Map<String, dynamic>?> provider(Map<String, dynamic> request) async {
      requests.add(Map<String, dynamic>.from(request));
      return {
        'sourceId': 'src',
        'sourceName': 'Test Source',
        'contentType': 'live',
        'selectedCategory': request['category'],
        'categories': categories,
        'channels': const <Map<String, dynamic>>[],
        'sources': const <Map<String, dynamic>>[],
      };
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IptvChannelSheet(
            channels: channels(),
            currentIndex: 0,
            onChannelSelected: (_, __) async {},
            onClose: () {},
            categories: categories,
            selectedCategory: 'Category 2',
            sourceName: 'Test Source',
            browseProvider: provider,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // Submit a search from inside a category.
    await tester.enterText(find.byType(TextField).first, 'bbc');
    await tester.pump();
    await tester.tap(find.byTooltip('Search full source'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(requests.last['query'], 'bbc');
    expect(
      requests.last['category'],
      isNull,
      reason: 'search must not be confined to the selected category',
    );

    // Clearing it puts the interrupted category back.
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(requests.last['query'], '');
    expect(requests.last['category'], 'Category 2');
  });

  // A submitted search persists selectedCategory: null to the player while the
  // category it interrupted lives only in sheet state. Closing without
  // restoring it would dispose the only record, reopening the guide on "All"
  // over a category-scoped ring.
  testWidgets('closing during a search restores the parked category', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final contexts = <String?>[];
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IptvChannelSheet(
            channels: channels(),
            currentIndex: 0,
            onChannelSelected: (_, __) async {},
            onClose: () => closed = true,
            categories: categories,
            selectedCategory: 'Category 2',
            sourceName: 'Test Source',
            browseProvider: (request) async => {
              'sourceId': 'src',
              'sourceName': 'Test Source',
              'contentType': 'live',
              'selectedCategory': request['category'],
              'categories': categories,
              'channels': const <Map<String, dynamic>>[],
              'sources': const <Map<String, dynamic>>[],
            },
            onContextChanged: (context) =>
                contexts.add(context.selectedCategory),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField).first, 'bbc');
    await tester.pump();
    await tester.tap(find.byTooltip('Search full source'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(contexts.last, isNull, reason: 'search widened to all categories');

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump(const Duration(milliseconds: 400));

    expect(closed, isTrue);
    expect(
      contexts.last,
      'Category 2',
      reason: 'the interrupted category must survive the close',
    );
  });

  testWidgets('changing source drops the previous source parked category', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IptvChannelSheet(
            channels: channels(),
            currentIndex: 0,
            onChannelSelected: (_, __) async {},
            onClose: () {},
            categories: categories,
            selectedCategory: 'Category 2',
            sourceName: 'Source A',
            sources: const [
              {'id': 'a', 'name': 'Source A'},
              {'id': 'b', 'name': 'Source B'},
            ],
            browseProvider: (request) async {
              requests.add(Map<String, dynamic>.from(request));
              return {
                'sourceId': request['sourceId'],
                'sourceName': request['sourceId'] == 'b'
                    ? 'Source B'
                    : 'Source A',
                'contentType': 'live',
                'selectedCategory': request['category'],
                'categories': categories,
                'channels': const <Map<String, dynamic>>[],
                'sources': const <Map<String, dynamic>>[],
              };
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // Start a search inside Source A's category…
    await tester.enterText(find.byType(TextField).first, 'bbc');
    await tester.pump();
    await tester.tap(find.byTooltip('Search full source'));
    await tester.pump(const Duration(milliseconds: 400));

    // …then switch source and clear the search. The popup is a route, so it
    // needs longer than the sheet's own transitions; assert it actually
    // happened rather than silently testing nothing.
    await tester.tap(find.text('Source A'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Source B'), findsWidgets, reason: 'source menu opened');
    await tester.tap(find.text('Source B').last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      requests.last['sourceId'],
      'b',
      reason: 'the source switch must have issued its own browse',
    );

    await tester.enterText(find.byType(TextField).first, 'x');
    await tester.pump();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      requests.last['category'],
      isNull,
      reason: "Source A's category must not be applied as a filter on B",
    );
  });

  testWidgets('All is always offered so a picked category can be cleared', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpSheet(tester, selectedCategory: 'Category 2');

    await tester.tap(find.text('Category 2'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('All'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('All'), findsOneWidget); // button reset to All
  });
}
