import 'dart:async';

import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/screens/video_player/widgets/spotlight_dialog.dart';
import 'package:flutter/material.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/identify_title_driver.dart';
import 'support/trakt_transport.dart';
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  TraktTestTransport.install();
  for (final width in [600.0, 720.0, 940.0, 1600.0]) {
    testWidgets(
      'identify sheet width $width keeps panel geometry tiles and spinner appearance',
      (t) async {
        final d = IdentifyTitleDriver(t);
        await d.setupIdentity();
        final gate = Completer<http.Response>();
        d.catalog = (_) => gate.future;
        d.metas = [
          {
            ...IdentifyTitleDriver.identityMeta('First poster'),
            'releaseInfo': '2024',
            'poster': 'https://image.test/invalid.png',
          },
          IdentifyTitleDriver.identityMeta('Second fallback', id: 'tt1200003'),
        ];
        try {
          await d.mountIdentity();
          t.view.physicalSize = Size(width, 800);
          final action = d.start(await d.menu());
          await d.f.until(t, () => d.catalogQueries.isNotEmpty);
          expect(find.text('FIX THE TITLE'), findsOneWidget);
          final area = find
              .ancestor(
                of: find.text('FIX THE TITLE'),
                matching: find.byType(SafeArea),
              )
              .first;
          final panel = find
              .ancestor(of: area, matching: find.byType(Container))
              .first;
          final container = t.widget<Container>(panel);
          expect(
            container.constraints!.maxWidth,
            width < 720 ? width : (width * .46).clamp(430, 560),
          );
          final decoration = container.decoration! as BoxDecoration;
          expect(
            decoration.color,
            const Color(0xFF101012).withValues(alpha: .86),
          );
          expect((decoration.border! as Border).left.width, .75);
          expect(
            (decoration.border! as Border).left.color,
            Colors.white.withValues(alpha: .14),
          );
          expect(t.widget<SafeArea>(area).left, isFalse);

          final route = ModalRoute.of(t.element(find.text('FIX THE TITLE')))!;
          expect(route.transitionDuration, const Duration(milliseconds: 280));
          expect(route.barrierDismissible, isTrue);
          expect(route.barrierLabel, 'dismiss');
          expect(route.barrierColor, Colors.black.withValues(alpha: .45));
          final fade = t.widget<FadeTransition>(
            find
                .ancestor(
                  of: find.text('FIX THE TITLE'),
                  matching: find.byType(FadeTransition),
                )
                .first,
          );
          expect((fade.opacity as CurvedAnimation).curve, Curves.easeOutCubic);
          final slide = t.widget<SlideTransition>(
            find
                .ancestor(
                  of: find.text('FIX THE TITLE'),
                  matching: find.byType(SlideTransition),
                )
                .first,
          );
          expect(slide.position.value.dy, 0);
          expect(
            slide.position.value.dx,
            closeTo(.12 * (1 - fade.opacity.value), .000001),
          );
          final header = t.widget<Text>(find.text('FIX THE TITLE'));
          expect(header.style!.fontSize, 11);
          expect(header.style!.fontWeight, FontWeight.w600);
          expect(header.style!.letterSpacing, 1.8);
          expect(header.style!.color, Colors.white.withValues(alpha: .42));
          final spinnerFinder = find.descendant(
            of: area,
            matching: find.byType(CircularProgressIndicator),
          );
          expect(spinnerFinder, findsOneWidget);
          final spinner = t.widget<CircularProgressIndicator>(spinnerFinder);
          expect(spinner.strokeWidth, 2);
          expect(spinner.color, Colors.white.withValues(alpha: .6));
          expect(t.getSize(spinnerFinder), const Size(22, 22));
          final field = d.searchField;
          expect(
            t
                .widget<Padding>(
                  find
                      .ancestor(
                        of: find.byWidget(field),
                        matching: find.byType(Padding),
                      )
                      .first,
                )
                .padding,
            const EdgeInsets.fromLTRB(24, 8, 24, 12),
          );
          expect(
            t
                .widget<Padding>(
                  find
                      .ancestor(
                        of: find.text('FIX THE TITLE'),
                        matching: find.byType(Padding),
                      )
                      .first,
                )
                .padding,
            const EdgeInsets.fromLTRB(24, 24, 14, 0),
          );

          expect(field.style!.color, Colors.white);
          expect(field.textInputAction, TextInputAction.search);
          expect(
            field.decoration!.hintStyle!.color,
            Colors.white.withValues(alpha: .42),
          );
          expect(field.decoration!.filled, isTrue);
          expect(
            field.decoration!.fillColor,
            Colors.white.withValues(alpha: .08),
          );
          final border = field.decoration!.border! as OutlineInputBorder;
          expect(border.borderRadius, BorderRadius.circular(12));
          expect(border.borderSide, BorderSide.none);
          expect(
            (field.decoration!.prefixIcon! as Icon).icon,
            Icons.search_rounded,
          );
          expect(
            (field.decoration!.prefixIcon! as Icon).color,
            Colors.white.withValues(alpha: .5),
          );
          gate.complete(d.response(d.metas));
          await d.found('First poster');
          final tile = find
              .ancestor(
                of: find.text('First poster'),
                matching: find.byType(InkWell),
              )
              .first;
          final second = find
              .ancestor(
                of: find.text('Second fallback'),
                matching: find.byType(InkWell),
              )
              .first;
          expect(
            t.widget<InkWell>(tile).focusNode?.debugLabel,
            'identify-title-first-result',
          );
          expect(t.widget<InkWell>(second).focusNode, isNull);
          expect(
            t
                .widget<Padding>(
                  find
                      .descendant(of: tile, matching: find.byType(Padding))
                      .first,
                )
                .padding,
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          );
          final name = t.widget<Text>(find.text('First poster'));
          expect(name.maxLines, 2);
          expect(name.overflow, TextOverflow.ellipsis);
          expect(name.style!.color, Colors.white);
          expect(name.style!.fontSize, 15);
          expect(name.style!.fontWeight, FontWeight.w600);
          final meta = t.widget<Text>(
            find.text('Movie | 2024 | Identity fixture'),
          );
          expect(meta.maxLines, 1);
          expect(meta.overflow, TextOverflow.ellipsis);
          expect(meta.style!.fontSize, 12);
          expect(meta.style!.color, Colors.white.withValues(alpha: .58));
          final clip = t.widget<ClipRRect>(
            find.descendant(of: tile, matching: find.byType(ClipRRect)),
          );
          expect(clip.borderRadius, BorderRadius.circular(6));
          final poster = t.widget<Container>(
            find.descendant(of: tile, matching: find.byType(Container)).first,
          );
          expect(poster.constraints!.maxWidth, 46);
          expect(poster.constraints!.maxHeight, 68);
          expect(poster.color, Colors.white.withValues(alpha: .08));
          expect(
            find.descendant(of: tile, matching: find.byType(Image)),
            findsOneWidget,
          );
          final image = t.widget<Image>(
            find.descendant(of: tile, matching: find.byType(Image)),
          );
          expect(image.fit, BoxFit.cover);
          final failedPoster = find.descendant(
            of: tile,
            matching: find.byIcon(Icons.movie_creation_outlined),
          );
          await d.f.until(t, () => failedPoster.evaluate().isNotEmpty);
          expect(
            t.widget<Icon>(failedPoster).color,
            Colors.white.withValues(alpha: .45),
          );
          final posterRect = t.getRect(
            find.descendant(of: tile, matching: find.byType(ClipRRect)),
          );
          final nameRect = t.getRect(find.text('First poster'));
          final metaRect = t.getRect(
            find.text('Movie | 2024 | Identity fixture'),
          );
          expect(nameRect.left - posterRect.right, 14);
          expect(metaRect.top - nameRect.bottom, 4);
          expect(
            t
                .widgetList<SizedBox>(
                  find.descendant(of: tile, matching: find.byType(SizedBox)),
                )
                .map((box) => box.width),
            contains(8),
          );

          expect(
            (image.image as NetworkImage).url,
            'https://image.test/invalid.png',
          );
          final fallback = t.widget<Icon>(
            find.descendant(
              of: second,
              matching: find.byIcon(Icons.movie_creation_outlined),
            ),
          );
          expect(fallback.color, Colors.white.withValues(alpha: .45));
          final chevron = t.widget<Icon>(
            find.descendant(
              of: tile,
              matching: find.byIcon(Icons.chevron_right_rounded),
            ),
          );
          expect(chevron.color, Colors.white.withValues(alpha: .5));
          final list = t.widget<ListView>(
            find.descendant(of: area, matching: find.byType(ListView)),
          );
          expect(list.padding, const EdgeInsets.only(bottom: 20));
          expect(
            find.descendant(of: area, matching: find.byType(Divider)),
            findsOneWidget,
          );
          final divider = t.widget<Divider>(
            find.descendant(of: area, matching: find.byType(Divider)).first,
          );
          expect(divider.height, 1);
          expect(divider.color, Colors.white.withValues(alpha: .06));
          await d.dismiss();
          expect(await d.f.finish(t, action), isNull);
        } finally {
          if (!gate.isCompleted) gate.complete(d.response([]));
          if (d.f.navigator.currentState?.canPop() ?? false) {
            await d.dismiss();
          }
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'identify TV panel and episode dialog retain solid Apply autofocus anchor',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      PlatformUtil.debugSetAndroidTvCached(true);
      d.metas = [
        IdentifyTitleDriver.identityMeta('Needs episode', type: 'series'),
      ];
      try {
        await d.mountIdentity();
        final pending = d.start(await d.menu());
        await d.found('Needs episode');
        final panel = t.widget<Container>(
          find
              .ancestor(
                of: find.text('FIX THE TITLE'),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(
          (panel.decoration as BoxDecoration).color,
          const Color(0xF5101012),
        );
        await t.tap(find.text('Needs episode'));
        await d.found('Which episode?');
        expect(find.text('Apply'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SpotlightDialogCard),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.style?.color == SpotlightDialogCard.statusRed,
            ),
          ),
          findsNothing,
        );
        // Use the real TV key: the solid action owns autofocus and validates.
        await d.f.key(t, LogicalKeyboardKey.enter);
        expect(find.text('Enter a valid season and episode.'), findsOneWidget);
        final fields = t
            .widgetList<TvTextField>(find.byType(TvTextField))
            .where(
              (field) =>
                  ['Season', 'Episode'].contains(field.decoration?.labelText),
            )
            .toList();
        expect(fields, hasLength(2));
        for (final field in fields) {
          expect(field.keyboardType, TextInputType.number);
          expect(field.style?.color, Colors.white);
          expect(
            field.decoration?.labelStyle?.color,
            Colors.white.withValues(alpha: .62),
          );
        }
        final fieldsRow = t.widget<Row>(
          find
              .ancestor(
                of: find.byWidget(fields.first),
                matching: find.byType(Row),
              )
              .first,
        );
        expect((fieldsRow.children[1] as SizedBox).width, 12);
        final errorColumn = t.widget<Column>(
          find
              .ancestor(
                of: find.text('Enter a valid season and episode.'),
                matching: find.byType(Column),
              )
              .first,
        );
        expect((errorColumn.children[1] as SizedBox).height, 12);
        final error = t.widget<Text>(
          find.text('Enter a valid season and episode.'),
        );
        expect(error.style?.color, SpotlightDialogCard.statusRed);
        expect(error.style?.fontSize, 12);
        await t.tap(find.text('Cancel'));
        expect(await d.f.finish(t, pending), isNull);
      } finally {
        await removeFixture(d);
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
}
