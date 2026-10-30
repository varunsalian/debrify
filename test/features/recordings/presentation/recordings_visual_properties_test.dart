import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';
import '../../../support/recordings_visual_assertions.dart';
import 'recordings_text_inventory_test.dart' show scheduleHint, desktopFooter;

const rec = Color(0xFFF43F5E);
const gold = Color(0xFFF5C042);
const accent = Color(0xFF8A5CFF);

void main() {
  testWidgets('empty DVR and hub title Text properties', (t) async {
    await recordingsCase(t, (f) async {
      await f.mount(t);
      recordingTextProperties(
        t,
        find.text('Recordings'),
        color: Colors.white,
        size: 19,
        weight: FontWeight.w800,
        spacing: 0.2,
        reason: 'HubBar title Text properties',
      );
      recordingTextProperties(
        t,
        find.text('Your DVR is empty'),
        color: Colors.white,
        size: 18,
        weight: FontWeight.w800,
        reason: 'EmptyDvr title Text properties',
      );
      // Found by its words: the network share's status row can sit above it.
      recordingTextProperties(
        t,
        find.descendant(
          of: recordingsType('_EmptyDvr'),
          matching: find.textContaining('Record what'),
        ),
        color: Colors.white.withValues(alpha: 0.5),
        size: 13,
        height: 1.5,
        align: TextAlign.center,
        reason: 'EmptyDvr explanation Text properties',
      );
      recordingTextProperties(
        t,
        find.text('Schedule a recording'),
        color: const Color(0xFFD9CBFF),
        size: 12.5,
        weight: FontWeight.w800,
        reason: 'EmptyDvr Schedule button Text properties',
      );
    });
  });

  testWidgets('populated widgets every Text site has explicit properties', (
    t,
  ) async {
    await recordingsCase(t, (f) async {
      f.television = true;
      final capture = await t.runAsync(f.capture);
      final start = DateTime.now().add(const Duration(days: 3));
      await f.seedSchedules([
        f.schedule('style', start: start, title: 'Programme'),
      ]);
      await t.runAsync(() => f.file('Library.ts'));
      await f.mount(t);
      f.clock(t).value = capture!.startedAt.add(const Duration(seconds: 3));
      await t.pump();
      for (final (label, chip, color) in [
        ('RECORDING NOW', '1 LIVE', rec),
        ('SCHEDULED', '1 UPCOMING', accent),
        ('LIBRARY', '1 · 1 KB', Colors.white.withValues(alpha: 0.55)),
      ]) {
        recordingTextProperties(
          t,
          find.text(label),
          color: Colors.white.withValues(alpha: 0.38),
          size: 11,
          weight: FontWeight.w800,
          spacing: 1.6,
          reason: 'SectionHeader label Text properties',
        );
        recordingTextProperties(
          t,
          find.text(chip),
          color: color,
          size: 10,
          weight: FontWeight.w800,
          spacing: 0.6,
          figures: true,
          reason: 'SectionHeader chip Text properties',
        );
      }
      recordingTextProperties(
        t,
        find.text('Live 0'),
        color: Colors.white,
        size: 14.5,
        weight: FontWeight.w700,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        reason: 'LiveCard title Text properties',
      );
      recordingTextProperties(
        t,
        recordingText(recordingsType('_LiveCard'), '00:03 · 188 B'),
        color: rec.withValues(alpha: 0.9),
        size: 12.5,
        weight: FontWeight.w700,
        figures: true,
        reason: 'LiveCard elapsed Text properties',
      );
      final schedule = find.descendant(
        of: recordingsType('_ScheduleRow'),
        matching: find.byType(Text),
      );
      recordingTextProperties(
        t,
        schedule.at(0),
        color: Colors.white,
        size: 13.5,
        weight: FontWeight.w700,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        reason: 'ScheduleRow title Text properties',
      );
      recordingTextProperties(
        t,
        schedule.at(1),
        color: Colors.white.withValues(alpha: 0.5),
        size: 11.5,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        reason: 'ScheduleRow subtitle Text properties',
      );
      recordingTextProperties(
        t,
        schedule.at(2),
        color: const Color(0xFFB9A5FF),
        size: 10.5,
        weight: FontWeight.w800,
        figures: true,
        reason: 'ScheduleRow upcoming countdown Text properties',
      );
      f.clock(t).value = start.add(const Duration(seconds: 1));
      await t.pump();
      recordingTextProperties(
        t,
        recordingText(recordingsType('_ScheduleRow'), 'due'),
        color: rec,
        size: 10.5,
        weight: FontWeight.w800,
        figures: true,
        reason: 'ScheduleRow due countdown Text properties',
      );
      final library = find.descendant(
        of: recordingsType('_LibraryRow'),
        matching: find.byType(Text),
      );
      recordingTextProperties(
        t,
        find.text('Library'),
        color: Colors.white,
        size: 13.5,
        weight: FontWeight.w700,
        height: 1.2,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        reason: 'LibraryRow title Text properties',
      );
      // The imported monogram owns its own Text. Select the row's subtitle by
      // its verbatim value rather than depending on that external subtree.
      final dynamic row = t.widget(recordingsType('_LibraryRow'));
      recordingTextProperties(
        t,
        recordingText(recordingsType('_LibraryRow'), row.subtitle as String),
        color: Colors.white.withValues(alpha: 0.5),
        size: 11.5,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        figures: true,
        reason: 'LibraryRow subtitle Text properties',
      );
      expect(library.evaluate(), isNotEmpty);
      recordingTextProperties(
        t,
        find.text(desktopFooter),
        color: Colors.white.withValues(alpha: 0.3),
        size: 11,
        align: TextAlign.center,
        reason: 'Layout footer Text properties',
      );
    });
  });

  testWidgets('empty hint Text properties', (t) async {
    await recordingsCase(t, (f) async {
      await t.runAsync(() => f.file('Only.ts'));
      await f.mount(t);
      recordingTextProperties(
        t,
        find.text(scheduleHint),
        color: Colors.white.withValues(alpha: 0.45),
        size: 12.5,
        height: 1.45,
        reason: 'EmptyHint Text properties',
      );
    });
  });

  for (final kind in [
    'filled',
    'danger',
    'hub icon',
    'row icon',
    'schedule',
    'library and thumb',
  ]) {
    testWidgets('$kind both focus states pin decoration icon and text', (
      t,
    ) async {
      await recordingsCase(t, (f) async {
        f.television = true;
        if (kind == 'danger') {
          await t.runAsync(f.capture);
        }
        if (kind == 'schedule') {
          await f.seedSchedules([f.schedule('focus')]);
        }
        if (kind == 'row icon' || kind == 'library and thumb') {
          await t.runAsync(() => f.file('Focus.ts'));
        }
        await f.mount(t);
        final Finder target = switch (kind) {
          'filled' => find.ancestor(
            of: find.text('Schedule'),
            matching: recordingsType('_HubButton'),
          ),
          'danger' => find.ancestor(
            of: find.text('Stop'),
            matching: recordingsType('_HubButton'),
          ),
          'hub icon' => recordingsType('_HubIconButton').first,
          'row icon' => recordingsType('_RowIconButton'),
          'schedule' => recordingsType('_ScheduleRow'),
          _ => recordingsType('_LibraryRow'),
        };
        final parking = kind == 'hub icon'
            ? f
                  .focus(
                    t,
                    find.ancestor(
                      of: find.text('Schedule'),
                      matching: recordingsType('_HubButton'),
                    ),
                  )
                  .focusNode!
            : f.focus(t, recordingsType('_HubIconButton').first).focusNode!;
        for (final focused in [false, true]) {
          (focused ? f.focus(t, target).focusNode! : parking).requestFocus();
          await f.settle(t);
          expect(
            f.focus(t, target).focusNode!.hasFocus,
            focused,
            reason: 'focus property scene has requested state',
          );
          final border = focused ? gold : Colors.transparent;
          final icons = t
              .widgetList<Icon>(
                find.descendant(of: target, matching: find.byType(Icon)),
              )
              .toList();
          if (kind == 'filled' || kind == 'danger') {
            final danger = kind == 'danger';
            final fg = danger
                ? const Color(0xFFFF8CA3)
                : const Color(0xFFD9CBFF);
            recordingBorder(
              t,
              target,
              fill: (danger ? rec : accent).withValues(
                alpha: danger
                    ? (focused ? 0.32 : 0.16)
                    : (focused ? 0.42 : 0.22),
              ),
              border: border,
              width: 1.8,
              radius: 10,
              reason: 'HubButton $kind focus decoration',
            );
            expect(
              [icons.single.color, icons.single.size],
              [fg, 17.0],
              reason: 'HubButton $kind focus icon',
            );
            recordingTextProperties(
              t,
              recordingText(target, danger ? 'Stop' : 'Schedule'),
              color: fg,
              size: 12.5,
              weight: FontWeight.w800,
              reason: 'HubButton $kind focus Text properties',
            );
          } else if (kind == 'hub icon') {
            recordingBorder(
              t,
              target,
              fill: Colors.white.withValues(alpha: focused ? 0.12 : 0.05),
              border: border,
              width: 1.8,
              radius: 10,
              reason: 'HubIconButton focus decoration',
            );
            expect(
              [icons.single.color, icons.single.size],
              [Colors.white.withValues(alpha: 0.8), 18.0],
              reason: 'HubIconButton focus icon',
            );
          } else if (kind == 'row icon') {
            recordingBorder(
              t,
              target,
              fill: focused ? rec.withValues(alpha: 0.2) : Colors.transparent,
              border: border,
              width: 1.8,
              radius: 9,
              reason: 'RowIconButton focus decoration',
            );
            expect(
              [icons.single.color, icons.single.size],
              [
                focused
                    ? const Color(0xFFFF8CA3)
                    : Colors.white.withValues(alpha: 0.4),
                17.0,
              ],
              reason: 'RowIconButton focused and unfocused icon colour',
            );
          } else {
            recordingBorder(
              t,
              target,
              fill: Colors.white.withValues(alpha: focused ? 0.07 : 0.035),
              border: focused ? gold : Colors.white.withValues(alpha: 0.06),
              width: focused ? 1.8 : 1,
              radius: 12,
              reason: '$kind focus decoration',
            );
            if (kind == 'schedule') {
              final containers = t
                  .widgetList<Container>(
                    find.descendant(
                      of: target,
                      matching: find.byType(Container),
                    ),
                  )
                  .toList();
              final circle = containers[1].decoration! as BoxDecoration;
              expect(
                [circle.shape, circle.border],
                [
                  BoxShape.circle,
                  Border.all(color: rec.withValues(alpha: 0.8), width: 2),
                ],
                reason: 'ScheduleRow both focus recording circle',
              );
              final chip = containers.last.decoration! as BoxDecoration;
              expect(
                [chip.color, chip.borderRadius],
                [accent.withValues(alpha: 0.14), BorderRadius.circular(6)],
                reason: 'ScheduleRow both focus countdown decoration',
              );
              expect(
                icons.first.color,
                rec,
                reason: 'ScheduleRow focus recording icon',
              );
              expect(
                icons.last.color,
                Colors.white.withValues(alpha: focused ? 0.8 : 0.35),
                reason: 'ScheduleRow focus cancel icon',
              );
              final texts = find.descendant(
                of: target,
                matching: find.byType(Text),
              );
              recordingTextProperties(
                t,
                texts.at(0),
                color: Colors.white,
                size: 13.5,
                weight: FontWeight.w700,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                reason: 'ScheduleRow both focus title Text properties',
              );
              recordingTextProperties(
                t,
                texts.at(1),
                color: Colors.white.withValues(alpha: 0.5),
                size: 11.5,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                reason: 'ScheduleRow both focus subtitle Text properties',
              );
            } else {
              recordingTextProperties(
                t,
                find.text('Focus'),
                color: Colors.white,
                size: 13.5,
                weight: FontWeight.w700,
                height: 1.2,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                reason: 'LibraryRow both focus title Text properties',
              );
              final dynamic row = t.widget(target);
              recordingTextProperties(
                t,
                recordingText(target, row.subtitle as String),
                color: Colors.white.withValues(alpha: 0.5),
                size: 11.5,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                figures: true,
                reason: 'LibraryRow both focus subtitle Text properties',
              );
              final thumb = recordingsType('_Thumb');
              final containers = t
                  .widgetList<Container>(
                    find.descendant(
                      of: thumb,
                      matching: find.byType(Container),
                    ),
                  )
                  .toList();
              final outer = containers.first.decoration! as BoxDecoration;
              expect(
                outer.gradient,
                const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1F3D), Color(0xFF0C0F22)],
                ),
                reason: 'Thumb both highlight gradient',
              );
              expect(
                outer.borderRadius,
                BorderRadius.circular(8),
                reason: 'Thumb both highlight radius',
              );
              final play = containers.last.decoration! as BoxDecoration;
              expect(
                [play.color, play.shape, play.border],
                [
                  focused ? gold : Colors.black.withValues(alpha: 0.55),
                  BoxShape.circle,
                  null,
                ],
                reason: 'Thumb highlighted and unhighlighted play fill',
              );
              final icon = t.widget<Icon>(
                find.descendant(of: thumb, matching: find.byType(Icon)),
              );
              expect(
                [icon.color, icon.size],
                [focused ? Colors.black : Colors.white, 14.0],
                reason: 'Thumb highlighted and unhighlighted play icon',
              );
            }
          }
        }
      });
    });
  }
}
