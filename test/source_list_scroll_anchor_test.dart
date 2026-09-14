import 'dart:async';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:debrify/models/stream_badge_rules.dart';
import 'package:debrify/services/stream_badge_matcher.dart';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/source_list_scroll_anchor.dart';
import 'package:debrify/widgets/source_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  ]) {
    testWidgets('late source badge layout respects $mode viewport ownership', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
            theme: AppThemes.legacy,
            child: Scaffold(
              body: Column(
                children: [
                  Focus(focusNode: outside, child: const SizedBox(height: 40)),
                  Expanded(
                    child: SourceListScrollAnchor(
                      child: ListView.builder(
                        controller: scroll,
                        scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
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
      nodes[5].requestFocus();
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
      var selected = 5;
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
        for (var i = 0; i < 15; i++)
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
        for (final pending in matcher.requests.values.toList()) {
          pending.complete(
            StreamBadgeMatchResult(StreamBadgeMatchStatus.resolved, badges),
          );
        }
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
        if (mode == 'idle' || mode == 'image') {
          expect(afterTop, closeTo(beforeTop, 1));
        } else {
          final render = tester.renderObject(row);
          final target = RenderAbstractViewport.of(render)
              .getOffsetToReveal(render, 0.3)
              .offset
              .clamp(
                scroll.position.minScrollExtent,
                scroll.position.maxScrollExtent,
              );
          expect(scroll.offset, closeTo(target, 1));
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
