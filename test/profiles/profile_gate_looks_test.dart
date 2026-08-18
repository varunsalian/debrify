import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/profiles/profile_gate_looks.dart';
import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three new gate looks share one contract: tiles are the only focus
/// stops, OK/tap-on-focused activates, Manage renders only when permitted,
/// and every look survives both a wide and a narrow surface.
void main() {
  final now = DateTime.utc(2026, 8, 17);

  UserProfile profile(
    String id,
    String name,
    UserProfileRole role, {
    bool hasPin = false,
  }) => UserProfile(
    id: id,
    name: name,
    avatarKey: 'art:aurora',
    role: role,
    policy: ProfilePolicy.allAllowedFor(role),
    authorizationRevision: 1,
    lifecycle: UserProfileLifecycle.active,
    visibleDataGeneration: 1,
    setupComplete: true,
    pinResetRequired: false,
    hasPin: hasPin,
    lockOnResume: false,
    createdAt: now,
    updatedAt: now,
  );

  late List<UserProfile> household;

  setUp(() {
    household = [
      profile('p1', 'Meera', UserProfileRole.admin, hasPin: true),
      profile('p2', 'Kiran', UserProfileRole.child),
    ];
  });

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(1000, 700),
    double textScale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: screen,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('style registry', () {
    test('marquee is the default and labels resolve', () {
      expect(ProfileGateStyle.defaultStyle, ProfileGateStyle.marquee);
      expect(ProfileGateStyle.labelFor(ProfileGateStyle.theater), 'Theater');
      expect(ProfileGateStyle.labelFor(ProfileGateStyle.row), 'Row');
      expect(
        ProfileGateStyle.options.map((o) => o.id),
        containsAll(<String>[
          ProfileGateStyle.theater,
          ProfileGateStyle.marquee,
          ProfileGateStyle.row,
          ProfileGateStyle.wall,
          ProfileGateStyle.classic,
        ]),
      );
    });

    test('unknown stored ids fall back to the default label', () {
      expect(ProfileGateStyle.labelFor('style-from-the-future'), 'Marquee');
    });
  });

  group('Theater', () {
    testWidgets('focus drives the marquee and OK opens the profile', (
      tester,
    ) async {
      UserProfile? selected;
      await pump(
        tester,
        ProfileTheaterGateScreen(
          profiles: household,
          onSelected: (p) => selected = p,
          onManage: () {},
        ),
      );

      // First orb autofocuses; the marquee wears its name.
      expect(find.text('Meera'), findsWidgets);
      expect(find.text('ADMIN · PIN'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('KID'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selected?.id, 'p2');
    });

    testWidgets('Manage orb appears only when permitted, and opens', (
      tester,
    ) async {
      var managed = false;
      await pump(
        tester,
        ProfileTheaterGateScreen(
          profiles: household,
          onSelected: (_) {},
          onManage: () => managed = true,
        ),
      );
      expect(find.text('Manage'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Manage profiles'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(managed, isTrue);
    });

    testWidgets('no Manage affordance without permission', (tester) async {
      await pump(
        tester,
        ProfileTheaterGateScreen(
          profiles: household,
          onSelected: (_) {},
          onManage: null,
        ),
      );
      expect(find.text('Manage'), findsNothing);
    });

    testWidgets('narrow surface renders without overflow', (tester) async {
      await pump(
        tester,
        ProfileTheaterGateScreen(
          profiles: household,
          onSelected: (_) {},
          onManage: () {},
        ),
        size: const Size(360, 740),
      );
      expect(find.text('Meera'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a big household at accessibility text scale scrolls, never overflows',
      (tester) async {
        // Theater is the DEFAULT: 8 profiles on a small phone at 1.5x text
        // used to blow through the Spacer column (review P1 2026-08-17).
        final big = [
          for (var i = 0; i < 8; i++)
            profile('big-$i', 'Person $i', UserProfileRole.member),
        ];
        await pump(
          tester,
          ProfileTheaterGateScreen(
            profiles: big,
            onSelected: (_) {},
            onManage: () {},
          ),
          size: const Size(320, 568),
          textScale: 1.5,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('roster shrink re-bounds the remembered focus', (tester) async {
      final key = GlobalKey();
      Future<void> pumpWith(List<UserProfile> profiles) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ProfileTheaterGateScreen(
              key: key,
              profiles: profiles,
              onSelected: (_) {},
              onManage: null,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
      }

      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpWith(household);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Kiran'), findsWidgets);

      // Kiran is deleted; the marquee must fall back to a real profile, not
      // announce Manage (which isn't even offered here).
      await pumpWith([household.first]);
      expect(find.text('Meera'), findsWidgets);
      expect(find.text('Manage profiles'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Row', () {
    testWidgets('tap on the focused plate opens the profile', (tester) async {
      UserProfile? selected;
      await pump(
        tester,
        ProfileRowGateScreen(
          profiles: household,
          onSelected: (p) => selected = p,
          onManage: () {},
        ),
      );

      // Meera autofocuses, so the first tap activates directly.
      await tester.tap(find.text('Meera'));
      await tester.pump();
      expect(selected?.id, 'p1');

      // Kiran is unfocused: first tap focuses, second activates.
      selected = null;
      await tester.tap(find.text('Kiran'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, isNull);
      await tester.tap(find.text('Kiran'));
      await tester.pump();
      expect(selected?.id, 'p2');
    });

    testWidgets('narrow surface wraps without overflow', (tester) async {
      await pump(
        tester,
        ProfileRowGateScreen(
          profiles: household,
          onSelected: (_) {},
          onManage: () {},
        ),
        size: const Size(360, 740),
      );
      expect(find.text('Kiran'), findsOneWidget);
      expect(find.text('Manage'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Marquee', () {
    testWidgets('rail focus recasts the stage; Continue opens it', (
      tester,
    ) async {
      UserProfile? selected;
      await pump(
        tester,
        ProfileMarqueeGateScreen(
          profiles: household,
          onSelected: (p) => selected = p,
          onManage: () {},
        ),
      );

      expect(find.text('Continue as Meera'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Continue as Kiran'), findsOneWidget);

      // The pill is a touch echo of OK — tapping it opens the FOCUSED
      // profile.
      await tester.tap(find.text('Continue as Kiran'));
      await tester.pump();
      expect(selected?.id, 'p2');
    });

    testWidgets('manage focus turns the stage into the household panel', (
      tester,
    ) async {
      var managed = false;
      await pump(
        tester,
        ProfileMarqueeGateScreen(
          profiles: household,
          onSelected: (_) {},
          onManage: () => managed = true,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Manage profiles'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(managed, isTrue);
    });

    testWidgets('narrow surface stacks without overflow', (tester) async {
      await pump(
        tester,
        ProfileMarqueeGateScreen(
          profiles: household,
          onSelected: (_) {},
          onManage: () {},
        ),
        size: const Size(360, 740),
      );
      expect(find.text('Continue as Meera'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('portrait tablets keep the stage stacked and focus-safe', (
      tester,
    ) async {
      await pump(
        tester,
        ProfileMarqueeGateScreen(
          profiles: household,
          onSelected: (_) {},
          onManage: () {},
        ),
        // This is wide enough for the old width-only breakpoint, but it is
        // still a portrait surface and needs the vertical composition.
        size: const Size(744, 1024),
      );

      final scroller = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroller.scrollDirection, Axis.vertical);
      expect(scroller.clipBehavior, Clip.none);
      expect(find.text('Continue as Meera'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a TV-width rail scrolls a big household', (tester) async {
      final big = [
        for (var i = 0; i < 12; i++)
          profile('big-$i', 'Person $i', UserProfileRole.member),
      ];
      await pump(
        tester,
        ProfileMarqueeGateScreen(
          profiles: big,
          onSelected: (_) {},
          onManage: () {},
        ),
        size: const Size(960, 540),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
