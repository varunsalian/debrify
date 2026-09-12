import 'dart:convert';
import 'package:debrify/widgets/trakt_calendar_day_sheet.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/screens/trakt_calendar_screen.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/trakt/trakt_calendar_service.dart';
import 'package:debrify/widgets/calendar_display_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final layout in [
    (name: 'desktop', size: const Size(1200, 900), tv: false),
    (name: 'phone', size: const Size(390, 844), tv: false),
    (name: 'TV', size: const Size(1280, 720), tv: true),
  ]) {
    testWidgets(
      '${layout.name}: today-first calendar with saved time format and sheet',
      (tester) async {
        SecretVault.debugReset(deviceIdOverride: 'calendar-test');
        SharedPreferences.setMockInitialValues({});
        ProfileRuntime.debugReset();
        ProfileRuntime.initializeLegacy();
        TraktCalendarService.instance.invalidate();
        addTearDown(() {
          ProfileRuntime.debugReset();
          TraktCalendarService.instance.invalidate();
        });
        await tester.runAsync(
          () => StorageService.setTraktSession(
            accessToken: 'test',
            refreshToken: 'test',
            expiryMs: 9000000000000,
          ),
        );
        PlatformUtil.debugSetTvOS(layout.tv);
        addTearDown(() => PlatformUtil.debugSetTvOS(null));
        await tester.binding.setSurfaceSize(layout.size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final now = DateTime.now();
        Map<String, Object> entry(int day, String title) => {
          'first_aired': DateTime(
            now.year,
            now.month,
            day,
            17,
            5,
          ).toUtc().toIso8601String(),
          'episode': {'season': 1, 'number': 1},
          'show': {
            'title': title,
            'ids': <String, Object>{'trakt': day},
          },
        };
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode([
              if (now.day > 1) entry(now.day - 1, 'Earlier episode'),
              entry(now.day, 'Today episode'),
            ]),
            200,
          ),
        );
        await http.runWithClient(() async {
          await tester.runAsync(() async {
            await tester.pumpWidget(
              const MaterialApp(home: TraktCalendarScreen()),
            );
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pumpAndSettle();
          expect(find.text('Today episode'), findsOneWidget);
          expect(find.text('Earlier episode'), findsNothing);
          await tester.tap(
            find.byType(DropdownButtonFormField<CalendarTimeFormat>),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('12-hour').last);
          await tester.pumpAndSettle();
          expect(find.text('5:05 PM'), findsOneWidget);
          expect(
            (await ProfilePreferences.instance()).getString(
              'calendar_time_format',
            ),
            'twelveHour',
          );
          await tester.ensureVisible(find.text('Today episode'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Today episode'));
          await tester.pumpAndSettle();
          expect(find.byType(TraktCalendarDaySheet), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(TraktCalendarDaySheet),
              matching: find.textContaining('5:05 PM'),
            ),
            findsOneWidget,
          );
          Navigator.of(tester.element(find.text('Today episode').last)).pop();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Show earlier days'));
          await tester.pumpAndSettle();
          if (now.day > 1) expect(find.text('Earlier episode'), findsOneWidget);
          expect(find.text('From today'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await tester.pumpWidget(
              const MaterialApp(home: TraktCalendarScreen()),
            );
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.pumpAndSettle();
          expect(find.text('5:05 PM'), findsOneWidget);
          expect(find.text('Earlier episode'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        }, () => client);
      },
    );
  }
}
