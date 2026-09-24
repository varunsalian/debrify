import 'dart:async';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/stream_badge_rules.dart';
import 'package:debrify/services/stream_badge_matcher.dart';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/source_list_scroll_anchor.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedMatcher extends StreamBadgeMatcher {
  _DelayedMatcher()
    : super([
        StreamBadgeRuleset(
          groups: const [],
          rules: [
            StreamBadgeRule(
              id: 'test',
              groupId: 'test',
              name: 'test',
              pattern: 'Movie',
            ),
          ],
        ),
      ]);
  final requests = <String, Completer<StreamBadgeMatchResult>>{};
  @override
  Future<StreamBadgeMatchResult> matchResultFor({
    required String name,
    String? description,
  }) => (requests[name] ??= Completer<StreamBadgeMatchResult>()).future;
}

void main() {
  for (final mode in [
    'idle',
    'moving',
    'manual',
    'focus-outside',
    'rapid',
    'image',
    'focused-growth',
    'focused-visible',
    'focused-oversized',
    'focused-spotlight',
    'focused-reversal',
  ]) {
    testWidgets('late source badge layout respects $mode viewport ownership', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PlatformUtil.debugSetAndroidTvCached(true);
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
      final svc = StreamBadgesService.instance;
      svc.resetProfileScope();
      addTearDown(svc.resetProfileScope);
      final matcher = _DelayedMatcher();
      svc.matcher.value = matcher;
      final imageReady = Completer<ImageInfo>();
      const imageUrl = 'https://example.invalid/delayed-wide-badge.png';
      if (mode == 'image') {
        final provider = ResizeImage.resizeIfNeeded(
          null,
          66,
          const CachedNetworkImageProvider(imageUrl),
        );
        final key = await provider.obtainKey(ImageConfiguration.empty);
        PaintingBinding.instance.imageCache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(imageReady.future),
        );
        addTearDown(() {
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
        });
      }
      final nodes = List.generate(30, (_) => FocusNode());
      final outside = FocusNode();
      final scroll = ScrollController();
      addTearDown(() {
        for (final node in nodes) {
          node.dispose();
        }
        outside.dispose();
        scroll.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AppThemeScope(
            theme: mode == 'focused-spotlight'
                ? AppThemes.byId('spotlight')
                : AppThemes.legacy,
            child: Scaffold(
              body: Column(
                children: [
                  Focus(focusNode: outside, child: const SizedBox(height: 40)),
                  Expanded(
                    child: SourceListScrollAnchor(
                      child: ListView.builder(
                        controller: scroll,
                        // ignore: deprecated_member_use
                        cacheExtent: 1200,
                        itemCount: nodes.length,
                        itemBuilder: (_, i) => SourceRow(
                          listIndex: i,
                          title: 'Movie $i',
                          subtitle: 'metadata',
                          badgeName: 'Movie $i',
                          focusNode: nodes[i],
                          onTap: () {},
                          isTelevision: true,
                          showPlayPill: true,
                          cinemaLayout: mode == 'focused-spotlight',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final focusedOnly = mode.startsWith('focused-');
      var selected = focusedOnly && mode != 'focused-visible' ? 7 : 5;
      nodes[selected].requestFocus();
      await tester.pumpAndSettle();
      if (mode == 'image') {
        final badges = [
          for (var i = 0; i < 15; i++)
            StreamBadgeRule(
              id: '$i',
              groupId: 'test',
              name: 'X',
              pattern: 'Movie',
              imageUrl: imageUrl,
            ),
        ];
        for (final pending in matcher.requests.values.toList()) {
          pending.complete(
            StreamBadgeMatchResult(StreamBadgeMatchStatus.resolved, badges),
          );
        }
        await tester.pumpAndSettle();
      }
      if (mode == 'moving' || mode == 'rapid') {
        nodes[6].requestFocus();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        selected = 6;
        if (mode == 'rapid') {
          nodes[7].requestFocus();
          await tester.pump();
          selected = 7;
        }
      } else if (mode == 'manual') {
        await tester.drag(find.byType(ListView), const Offset(0, -160));
        await tester.pumpAndSettle();
      } else if (mode == 'focus-outside') {
        outside.requestFocus();
        await tester.pumpAndSettle();
      }
      final beforeOffset = scroll.offset;
      final beforeTop = tester.getTopLeft(find.text('Movie $selected')).dy;
      final badges = [
        for (var i = 0; i < (mode == 'focused-oversized' ? 100 : 15); i++)
          StreamBadgeRule(
            id: '$i',
            groupId: 'test',
            name: 'Long badge $i',
            pattern: 'Movie',
          ),
      ];
      if (mode == 'image') {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 500, 100),
          Paint()..color = Colors.white,
        );
        final picture = recorder.endRecording();
        final image = await tester.runAsync(() => picture.toImage(500, 100));
        picture.dispose();
        imageReady.complete(ImageInfo(image: image!));
      } else {
        final pendingMatches = focusedOnly
            ? [matcher.requests['Movie $selected']!]
            : matcher.requests.values.toList();
        for (final pending in pendingMatches) {
          pending.complete(
            StreamBadgeMatchResult(StreamBadgeMatchStatus.resolved, badges),
          );
        }
      }
      if (mode == 'focused-reversal') {
        // Let the growth queue its correction, then change selection before
        // that correction runs. It must not pull focus back to the old row.
        await tester.pump();
        selected = 6;
        nodes[selected].requestFocus();
      }
      await tester.pumpAndSettle();
      if (mode == 'manual' || mode == 'focus-outside') {
        expect(scroll.offset, closeTo(beforeOffset, 1));
      } else {
        expect(nodes[selected].hasFocus, true);
        final row = find.byWidgetPredicate(
          (w) => w is SourceRow && w.listIndex == selected,
        );
        expect(row, findsOneWidget);
        final afterTop = tester.getTopLeft(find.text('Movie $selected')).dy;
        expect(afterTop, greaterThan(40));
        expect(afterTop, lessThan(700));
        if (mode == 'focused-growth' || mode == 'focused-spotlight') {
          expect(tester.getBottomRight(row).dy, lessThanOrEqualTo(800));
          expect(scroll.offset, greaterThan(beforeOffset));
        } else if (mode == 'focused-visible') {
          expect(scroll.offset, closeTo(beforeOffset, 0.01));
        } else if (mode == 'focused-oversized') {
          expect(tester.getTopLeft(row).dy, closeTo(40, 1));
        }
        if (mode == 'idle' || mode == 'image') {
          expect(afterTop, closeTo(beforeTop, 1));
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('TV focus only scrolls when a source leaves the viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final nodes = List.generate(30, (_) => FocusNode());
    final scroll = ScrollController();
    addTearDown(() {
      for (final node in nodes) {
        node.dispose();
      }
      scroll.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: Scaffold(
            body: SourceListScrollAnchor(
              child: ListView.builder(
                controller: scroll,
                itemCount: nodes.length,
                itemBuilder: (_, i) => SizedBox(
                  height: i == 8 ? 900 : 100,
                  child: SourceRow(
                    listIndex: i,
                    title: 'Source $i',
                    subtitle: 'metadata',
                    focusNode: nodes[i],
                    onTap: () {},
                    isTelevision: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      nodes[i].requestFocus();
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
    }
    nodes[8].requestFocus();
    await tester.pumpAndSettle();
    // A badge-heavy card can be taller than the viewport. Show its top.
    expect(scroll.offset, closeTo(800, 1));
    nodes[7].requestFocus();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Source 7')).dy,
      greaterThanOrEqualTo(0),
    );
  });
  for (final oversized in [false, true]) {
    testWidgets(
      oversized
          ? 'top-aligned tall first row stays at top on focus and refocus'
          : 'reversing to a visible row cancels the old scroll',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final nodes = List.generate(20, (_) => FocusNode());
        final outside = FocusNode();
        final scroll = ScrollController();
        addTearDown(() {
          for (final node in nodes) {
            node.dispose();
          }
          outside.dispose();
          scroll.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: AppThemeScope(
              theme: AppThemes.legacy,
              child: Scaffold(
                body: Column(
                  children: [
                    Focus(focusNode: outside, child: const SizedBox.shrink()),
                    Expanded(
                      child: SourceListScrollAnchor(
                        child: ListView.builder(
                          controller: scroll,
                          // ignore: deprecated_member_use
                          cacheExtent: 1200,
                          itemCount: nodes.length,
                          itemBuilder: (_, i) => SizedBox(
                            height: oversized && i == 0 ? 900 : 100,
                            child: SourceRow(
                              listIndex: i,
                              title: 'Row $i',
                              subtitle: '',
                              focusNode: nodes[i],
                              onTap: () {},
                              isTelevision: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        if (oversized) {
          for (var i = 0; i < 2; i++) {
            nodes.first.requestFocus();
            await tester.pumpAndSettle();
            expect(scroll.offset, 0);
            outside.requestFocus();
            await tester.pumpAndSettle();
          }
        } else {
          nodes[6].requestFocus();
          await tester.pumpAndSettle();
          nodes[8].requestFocus();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 16));
          expect(scroll.position.isScrollingNotifier.value, isTrue);
          nodes[6].requestFocus();
          await tester.pump();
          final stoppedAt = scroll.offset;
          expect(scroll.position.isScrollingNotifier.value, isFalse);
          await tester.pumpAndSettle();
          expect(scroll.offset, closeTo(stoppedAt, 0.01));
          expect(nodes[6].hasFocus, isTrue);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
