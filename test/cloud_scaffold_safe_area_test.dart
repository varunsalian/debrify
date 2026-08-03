import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/widgets/cloud/cloud_theme.dart';

/// The cloud provider pages (Real-Debrid, TorBox, AllDebrid) render their own
/// floating toolbar at the very top of the body and pass no [AppBar] at the
/// list root. A bare Scaffold does not inset its body, so when those pages are
/// PUSHED as their own route (Cloud hub / deep link) the toolbar used to land
/// under the status bar — untappable on iOS, which reserves that strip.
void main() {
  const topInset = 44.0;
  const bottomInset = 34.0;
  const bodyKey = Key('cloud-body');

  Widget host({PreferredSizeWidget? appBar, bool outerSafeArea = false}) {
    final scaffold = CloudScaffold(
      appBar: appBar,
      body: const SizedBox.expand(key: bodyKey),
    );
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
        ),
        child: outerSafeArea ? SafeArea(child: scaffold) : scaffold,
      ),
    );
  }

  testWidgets('pushed route with no AppBar keeps the body clear of the status bar',
      (tester) async {
    await tester.pumpWidget(host());

    expect(tester.getTopLeft(find.byKey(bodyKey)).dy, topInset);
  });

  testWidgets('body still reaches the bottom edge (no double bottom inset)',
      (tester) async {
    await tester.pumpWidget(host());

    // bottom: false — the nav-bar layout in main.dart owns that inset.
    expect(
      tester.getRect(find.byKey(bodyKey)).bottom,
      tester.getRect(find.byType(Scaffold)).bottom,
    );
  });

  testWidgets('an AppBar still provides the top inset itself', (tester) async {
    await tester.pumpWidget(host(appBar: AppBar(title: const Text('x'))));

    // Body sits directly below the AppBar, which is already padded by the
    // status bar — exactly one inset, not two.
    final appBarBottom = tester.getRect(find.byType(AppBar)).bottom;
    expect(tester.getTopLeft(find.byKey(bodyKey)).dy, appBarBottom);
    expect(appBarBottom, topInset + kToolbarHeight);
  });

  testWidgets('no-op inside the bottom-nav tab, where a SafeArea already ran',
      (tester) async {
    await tester.pumpWidget(host(outerSafeArea: true));

    // The outer SafeArea consumed the inset and stripped it from MediaQuery,
    // so the scaffold's own SafeArea adds nothing on top of it.
    expect(
      tester.getTopLeft(find.byKey(bodyKey)).dy,
      tester.getTopLeft(find.byType(Scaffold)).dy,
    );
  });
}
