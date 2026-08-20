import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/desktop_pill_nav.dart';
import 'package:debrify/widgets/desktop_sidebar_nav.dart';
import 'package:debrify/widgets/mobile_classic_nav.dart';
import 'package:debrify/widgets/mobile_floating_nav.dart';
import 'package:debrify/widgets/tv_sidebar_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

UserProfile _profile() => UserProfile(
  id: 'active-profile',
  name: 'Varun',
  role: UserProfileRole.admin,
  policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
  authorizationRevision: 1,
  lifecycle: UserProfileLifecycle.active,
  visibleDataGeneration: 1,
  setupComplete: true,
  pinResetRequired: false,
  hasPin: false,
  lockOnResume: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Widget _theme(Widget child) => MaterialApp(
  home: AppThemeScope(theme: AppThemes.legacy, child: child),
);

void main() {
  testWidgets('desktop rail pins profile after the scrolling destinations', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _theme(
        SizedBox(
          width: DesktopSidebarNav.width,
          height: 600,
          child: DesktopSidebarNav(
            currentIndex: 0,
            entries: const [
              DesktopNavEntry(Icons.home, 'Home', 'main'),
              DesktopNavEntry(Icons.settings, 'Settings', 'system'),
            ],
            onTap: (_) {},
            profile: _profile(),
            onProfileTap: () => opened = true,
          ),
        ),
      ),
    );

    final profile = find.byKey(const ValueKey('desktop-sidebar-profile'));
    expect(profile, findsOneWidget);
    expect(tester.getBottomLeft(profile).dy, greaterThan(550));
    await tester.tap(profile);
    expect(opened, isTrue);
  });

  testWidgets('desktop pill panel keeps profile as its fixed footer', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _theme(
        DesktopPillNav(
          currentIndex: 0,
          entries: const [DesktopNavEntry(Icons.home, 'Home', 'main')],
          onTap: (_) {},
          profile: _profile(),
          onProfileTap: () => opened = true,
        ),
      ),
    );
    await tester.tap(find.byKey(DesktopPillNav.pillKey));
    await tester.pumpAndSettle();

    final profile = find.byKey(const ValueKey('desktop-pill-profile'));
    expect(profile, findsOneWidget);
    await tester.tap(profile);
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('TV profile is the final DPAD destination', (tester) async {
    var opened = false;
    final key = GlobalKey<TvSidebarNavState>();
    await tester.pumpWidget(
      _theme(
        Align(
          alignment: Alignment.centerLeft,
          child: TvSidebarNav(
            key: key,
            navStyle: 'badge',
            currentIndex: 0,
            items: const [
              TvNavItem(Icons.home, 'Home'),
              TvNavItem(Icons.settings, 'Settings'),
            ],
            onTap: (_) {},
            profile: _profile(),
            onProfileTap: () => opened = true,
          ),
        ),
      ),
    );

    key.currentState!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(find.byKey(const ValueKey('tv-sidebar-profile')), findsOneWidget);
    expect(opened, isTrue);
  });

  testWidgets('floating mobile menu puts profile after navigation actions', (
    tester,
  ) async {
    var opened = false;
    await tester.binding.setSurfaceSize(const Size(420, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _theme(
        MobileFloatingNav(
          currentIndex: 0,
          items: const [
            MobileNavItem(Icons.home, 'Home'),
            MobileNavItem(Icons.settings, 'Settings'),
          ],
          onTap: (_) {},
          profile: _profile(),
          onProfileTap: () => opened = true,
        ),
      ),
    );

    await tester.tap(find.text('Menu'));
    await tester.pump(const Duration(milliseconds: 400));
    final profile = find.byKey(const ValueKey('mobile-floating-profile'));
    expect(profile, findsOneWidget);
    expect(
      tester.getTopLeft(profile).dy,
      greaterThan(tester.getTopLeft(find.text('Settings')).dy),
    );
    await tester.tap(profile);
    await tester.pump(const Duration(milliseconds: 300));
    expect(opened, isTrue);
  });

  testWidgets('classic mobile More sheet ends with the profile', (
    tester,
  ) async {
    var opened = false;
    final icons = List<IconData>.filled(20, Icons.circle);
    final titles = List<String>.generate(20, (i) => 'Destination $i');
    titles[MobileClassicNav.homeIndex] = 'Home';
    await tester.binding.setSurfaceSize(const Size(420, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _theme(
        Scaffold(
          bottomNavigationBar: MobileClassicNav(
            currentIndex: MobileClassicNav.homeIndex,
            visibleIndices: const [15, 1, 2, 3, 4],
            barIndices: const [1, 2, 3],
            icons: icons,
            titles: titles,
            onTap: (_) {},
            onBarEdited: (_) {},
            profile: _profile(),
            onProfileTap: () => opened = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    final profile = find.byKey(const ValueKey('mobile-classic-profile'));
    expect(profile, findsOneWidget);
    expect(
      tester.getTopLeft(profile).dy,
      greaterThan(tester.getTopLeft(find.text('Destination 4')).dy),
    );
    await tester.tap(profile);
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });
}
