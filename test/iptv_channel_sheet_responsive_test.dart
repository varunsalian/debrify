import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final channels = [
    IptvChannel(
      channelNumber: 101,
      name: 'Sky Sports Main Event',
      url: 'https://example.com/main.m3u8',
      group: 'Sports',
      contentType: 'live',
    ),
    IptvChannel(
      channelNumber: 102,
      name: 'Sky Sports News',
      url: 'https://example.com/news.m3u8',
      group: 'Sports',
      contentType: 'live',
    ),
  ];

  Future<void> pumpGuide(
    WidgetTester tester, {
    required Size size,
    Future<void> Function(List<IptvChannel>, int)? onSelected,
    Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
    browseProvider,
    ValueChanged<IptvGuideContext>? onContextChanged,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IptvChannelSheet(
            channels: channels,
            currentIndex: 0,
            categories: const ['Sports', 'News'],
            sourceId: 'source-1',
            sourceName: 'My IPTV',
            browseProvider: browseProvider,
            onContextChanged: onContextChanged,
            onChannelSelected: onSelected ?? (_, __) async {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  test('launcher preserves IPTV guide catalog context for Flutter player', () {
    Future<Map<String, dynamic>?> browse(Map<String, dynamic> _) async => null;
    final screen = VideoPlayerLaunchArgs(
      videoUrl: channels.first.url,
      title: channels.first.name,
      iptvChannels: channels,
      iptvStartIndex: 0,
      iptvCategories: const ['Sports', 'News'],
      iptvSourceId: 'source-1',
      iptvSourceName: 'My IPTV',
      iptvSelectedCategory: 'Sports',
      iptvContentType: 'live',
      iptvSources: const [
        {'id': 'source-1', 'name': 'My IPTV'},
      ],
      iptvBrowseProvider: browse,
    ).toWidget();

    expect(screen.iptvCategories, const ['Sports', 'News']);
    expect(screen.iptvSourceId, 'source-1');
    expect(screen.iptvSourceName, 'My IPTV');
    expect(screen.iptvSelectedCategory, 'Sports');
    expect(screen.iptvBrowseProvider, same(browse));
  });

  testWidgets('compact layout exposes explicit touch schedule action', (
    tester,
  ) async {
    await pumpGuide(tester, size: const Size(390, 844));

    expect(find.byKey(const ValueKey('iptv-guide-compact')), findsOneWidget);
    expect(find.byTooltip('Programme guide'), findsWidgets);

    await tester.tap(find.byTooltip('Programme guide').first);
    await tester.pump();

    expect(find.text('Programme Guide'), findsOneWidget);
    expect(find.byTooltip('Back to channels'), findsOneWidget);
  });

  testWidgets('large layout shows channels and schedule side by side', (
    tester,
  ) async {
    await pumpGuide(tester, size: const Size(1400, 900));

    expect(find.byKey(const ValueKey('iptv-guide-wide')), findsOneWidget);
    expect(find.text('Live TV Guide'), findsOneWidget);
    expect(find.text('Sky Sports Main Event'), findsWidgets);
    expect(find.byTooltip('Programme guide'), findsWidgets);
  });

  testWidgets('tablet layout keeps a readable single-pane guide', (
    tester,
  ) async {
    await pumpGuide(tester, size: const Size(900, 700));

    expect(find.byKey(const ValueKey('iptv-guide-compact')), findsOneWidget);
    expect(find.text('Live TV Guide'), findsOneWidget);
    expect(find.byTooltip('Programme guide'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a channel adopts the visible guide list', (
    tester,
  ) async {
    List<IptvChannel>? selectedChannels;
    int? selectedIndex;
    await pumpGuide(
      tester,
      size: const Size(390, 844),
      onSelected: (visible, index) async {
        selectedChannels = visible;
        selectedIndex = index;
      },
    );

    await tester.tap(
      find.byKey(const ValueKey('iptv-channel-https://example.com/news.m3u8')),
    );
    await tester.pump();

    expect(selectedChannels, hasLength(2));
    expect(selectedIndex, 1);
  });

  testWidgets('search action uses the full-catalog browse provider', (
    tester,
  ) async {
    Map<String, dynamic>? request;
    await pumpGuide(
      tester,
      size: const Size(390, 844),
      browseProvider: (args) async {
        request = args;
        return {
          'sourceId': 'source-1',
          'sourceName': 'My IPTV',
          'contentType': 'live',
          'channels': [
            {
              'channelNumber': 102,
              'name': 'Sky Sports News',
              'url': 'https://example.com/news.m3u8',
              'group': 'Sports',
              'contentType': 'live',
            },
          ],
          'categories': ['Sports', 'News'],
        };
      },
    );

    await tester.enterText(find.byType(TextField), 'news');
    await tester.tap(find.byTooltip('Search full source'));
    await tester.pump();

    expect(request?['query'], 'news');
    expect(request?['sourceId'], 'source-1');
    expect(find.text('1 of 1 channels'), findsOneWidget);
  });

  testWidgets('browsed catalog context survives closing and reopening', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    var visibleChannels = List<IptvChannel>.from(channels);
    var currentIndex = 0;
    var guideOpen = true;
    IptvGuideContext? persistedContext;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setHarnessState) {
            return Scaffold(
              body: guideOpen
                  ? IptvChannelSheet(
                      channels: visibleChannels,
                      currentIndex: currentIndex,
                      categories:
                          persistedContext?.categories ??
                          const ['Sports', 'News'],
                      sourceId: persistedContext == null
                          ? 'source-1'
                          : persistedContext!.sourceId,
                      sourceName: persistedContext?.sourceName ?? 'My IPTV',
                      selectedCategory: persistedContext == null
                          ? 'Sports'
                          : persistedContext!.selectedCategory,
                      contentType: persistedContext?.contentType ?? 'live',
                      browseProvider: (_) async => {
                        'sourceId': 'source-2',
                        'sourceName': 'Second IPTV',
                        'selectedCategory': 'Movies',
                        'contentType': 'vod',
                        'categories': ['Movies', 'Documentaries'],
                        'channels': [
                          {
                            'name': 'Movie One',
                            'url': 'https://example.com/movie-one.mp4',
                            'group': 'Movies',
                            'contentType': 'vod',
                          },
                        ],
                      },
                      onContextChanged: (next) {
                        setHarnessState(() => persistedContext = next);
                      },
                      onChannelSelected: (nextChannels, nextIndex) async {
                        setHarnessState(() {
                          visibleChannels = nextChannels;
                          currentIndex = nextIndex;
                          guideOpen = false;
                        });
                      },
                      onClose: () => setHarnessState(() => guideOpen = false),
                    )
                  : Center(
                      child: TextButton(
                        key: const ValueKey('reopen-guide'),
                        onPressed: () =>
                            setHarnessState(() => guideOpen = true),
                        child: const Text('Reopen guide'),
                      ),
                    ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField), 'movie');
    await tester.tap(find.byTooltip('Search full source'));
    await tester.pump();

    await tester.tap(
      find.byKey(
        const ValueKey('iptv-channel-https://example.com/movie-one.mp4'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reopen-guide')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Second IPTV'), findsOneWidget);
    expect(find.text('Movies'), findsWidgets);
    expect(persistedContext?.sourceId, 'source-2');
    expect(persistedContext?.selectedCategory, 'Movies');
    expect(persistedContext?.contentType, 'vod');
    expect(persistedContext?.categories, const ['Movies', 'Documentaries']);
  });

  test('catch-up request gate strands superseded and cancelled lookups', () {
    final gate = IptvCatchupRequestGate();

    final first = gate.begin();
    final second = gate.begin();
    expect(gate.isCurrent(first), isFalse);
    expect(gate.isCurrent(second), isTrue);

    expect(gate.cancel(), isTrue);
    expect(gate.isCurrent(second), isFalse);
    expect(gate.complete(second), isFalse);
  });
}
