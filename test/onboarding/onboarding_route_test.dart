import 'package:debrify/services/remote_control/remote_command_router.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/remote_control/remote_session.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/initial_setup_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('show pushes an opaque route and restores parent focus on pop', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PlatformUtil.debugSetAndroidTvCached(false);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    final parentFocus = FocusScopeNode();
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusScope(
            node: parentFocus,
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () async =>
                    result = await InitialSetupFlow.show(context),
                child: const Text('Open onboarding'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open onboarding'));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.byType(InitialSetupFlow)));
    expect(route, isA<PageRouteBuilder<bool>>());
    expect(route!.opaque, isTrue);
    expect(parentFocus.canRequestFocus, isFalse);
    await tester.scrollUntilVisible(
      find.text("Skip — I'll do this later"),
      100,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text("Skip — I'll do this later"));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(parentFocus.canRequestFocus, isTrue);
    expect(await StorageService.isInitialSetupComplete(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    parentFocus.dispose();
  });

  testWidgets('remote config complete safely replaces the onboarding stack', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PlatformUtil.debugSetAndroidTvCached(false);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    final navigatorKey = GlobalKey<NavigatorState>();
    RemoteCommandRouter().setRestartCallback(() {
      navigatorKey.currentState!.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Restarted')),
        ),
        (_) => false,
      );
    });

    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const _OnboardingCaller()),
    );
    await tester.tap(find.text('Open onboarding'));
    await tester.pumpAndSettle();
    expect(find.byType(InitialSetupFlow), findsOneWidget);

    // `complete` is only honored after authorized config work over an
    // authorized transport (the unsolicited-restart DoS gate). Stand in for
    // the config packets a real transfer sends first, and dispatch with the
    // authorized context a paired session produces.
    RemoteCommandRouter().debugMarkAuthorizedConfigActivity();
    RemoteCommandRouter().dispatchCommand(
      RemoteAction.config,
      ConfigCommand.complete,
      null,
      context: const RemoteCommandContext(encrypted: true, authorized: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pumpAndSettle();

    expect(find.text('Restarted'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(await StorageService.isInitialSetupComplete(), isTrue);
  });
}

class _OnboardingCaller extends StatefulWidget {
  const _OnboardingCaller();

  @override
  State<_OnboardingCaller> createState() => _OnboardingCallerState();
}

class _OnboardingCallerState extends State<_OnboardingCaller> {
  Future<void> _open() async {
    await InitialSetupFlow.show(context);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FilledButton(onPressed: _open, child: const Text('Open onboarding')),
  );
}
