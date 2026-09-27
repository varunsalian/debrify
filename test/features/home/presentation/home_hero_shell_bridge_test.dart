import 'package:debrify/features/home/presentation/home_hero_shell_bridge.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RouteEvents with RouteAware {
  final events = <String>[];
  @override
  void didPush() => events.add('push');
  @override
  void didPushNext() => events.add('covered');
  @override
  void didPopNext() => events.add('returned');
}

void main() {
  tearDown(() {
    MainPageBridge.notifyContentPlaybackStopped();
    MainPageBridge.tvChromeDim.value = 0;
    MainPageBridge.tvHeroTint.value = null;
    MainPageBridge.tvAmbientArt.value = null;
    MainPageBridge.tvStageLightsOff.value = false;
  });

  testWidgets(
    'disposing one binding detaches only its listeners and keyboard',
    (tester) async {
      final takeover = ValueNotifier(0.0);
      final showing = ValueNotifier(false);
      addTearDown(takeover.dispose);
      addTearDown(showing.dispose);
      final events = <String>[];
      HomeHeroShellBridge bind(String id) => HomeHeroShellBridge(
        takeover: takeover,
        showing: showing,
        onSidebarFocus: (focused) => events.add('$id:sidebar:$focused'),
        onChromeDim: () => events.add('$id:dim'),
        onLightsOff: () => events.add('$id:lights'),
        onContentLaunch: () => events.add('$id:launch'),
        onKey: (event) {
          if (event is KeyDownEvent) events.add('$id:key');
          return false;
        },
        routeAware: _RouteEvents(),
      );
      final first = bind('first');
      final second = bind('second');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Future<void> notify() async {
        takeover.value += .1;
        showing.value = !showing.value;
        MainPageBridge.notifyTvSidebarFocusChanged(true);
        MainPageBridge.notifyPlayerLaunching();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      }

      await notify();
      expect(events, [
        'first:dim',
        'second:dim',
        'first:lights',
        'second:lights',
        'first:sidebar:true',
        'second:sidebar:true',
        'first:launch',
        'second:launch',
        'first:key',
        'second:key',
      ]);
      events.clear();
      first.dispose();
      first.dispose();
      await notify();
      expect(events, [
        'second:dim',
        'second:lights',
        'second:sidebar:true',
        'second:launch',
        'second:key',
      ]);
      events.clear();
      second.dispose();
      await notify();
      expect(events, isEmpty);
      // Both borrowed notifiers remained usable after either owner detached.
    },
  );

  testWidgets('route registration is unique and retires with its owner', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final observer = RouteObserver<PageRoute<dynamic>>();
    final routeEvents = _RouteEvents();
    final signal = ValueNotifier(false);
    addTearDown(signal.dispose);
    late PageRoute<dynamic> homeRoute;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) {
            homeRoute = ModalRoute.of(context)! as PageRoute<dynamic>;
            return const SizedBox();
          },
        ),
      ),
    );
    final binding = HomeHeroShellBridge(
      takeover: signal,
      showing: signal,
      onSidebarFocus: (_) {},
      onChromeDim: () {},
      onLightsOff: () {},
      onContentLaunch: () {},
      onKey: (_) => false,
      routeAware: routeEvents,
      routeObserver: observer,
    );
    addTearDown(binding.dispose);
    binding.bindRoute(homeRoute);
    binding.bindRoute(homeRoute);
    expect(routeEvents.events, ['push']);
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(routeEvents.events, ['push', 'covered', 'returned']);
    binding.dispose();
    binding.bindRoute(homeRoute);
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const SizedBox()),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(routeEvents.events, ['push', 'covered', 'returned']);
  });

  for (final wasActive in [false, true]) {
    testWidgets(
      'shell resets stay conditional and post-frame (active=$wasActive)',
      (tester) async {
        final signal = ValueNotifier(false);
        addTearDown(signal.dispose);
        final binding = HomeHeroShellBridge(
          takeover: signal,
          showing: signal,
          onSidebarFocus: (_) {},
          onChromeDim: () {},
          onLightsOff: () {},
          onContentLaunch: () {},
          onKey: (_) => false,
          routeAware: _RouteEvents(),
        );
        void activate() {
          MainPageBridge.tvChromeDim.value = .7;
          MainPageBridge.tvHeroTint.value = const Color(0xFF123456);
          MainPageBridge.tvAmbientArt.value = 'art';
          MainPageBridge.tvStageLightsOff.value = true;
        }

        if (wasActive) activate();
        binding.dispose();
        if (!wasActive) activate();
        expect(MainPageBridge.tvChromeDim.value, .7);
        expect(MainPageBridge.tvHeroTint.value, isNotNull);
        expect(MainPageBridge.tvAmbientArt.value, 'art');
        expect(MainPageBridge.tvStageLightsOff.value, isTrue);
        tester.binding.scheduleFrame();
        await tester.pump();
        expect(MainPageBridge.tvChromeDim.value, wasActive ? 0 : .7);
        expect(
          MainPageBridge.tvHeroTint.value,
          wasActive ? null : const Color(0xFF123456),
        );
        expect(MainPageBridge.tvAmbientArt.value, wasActive ? null : 'art');
        expect(MainPageBridge.tvStageLightsOff.value, !wasActive);
      },
    );
  }
}
