import 'package:debrify/features/discover/presentation/discover_preview.dart';
import 'package:debrify/features/discover/presentation/discover_shell_bridge.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shell detaches listeners without clearing a newer route slot', (
    tester,
  ) async {
    final preview = DiscoverPreview(isCurrent: () => true);
    var loads = 0;
    void oldCards() {}
    void oldLayout() {}
    void newCards() {}
    void newLayout() {}
    final bridge = DiscoverShellBridge(
      readPreview: () => preview,
      isTelevision: true,
      onCardSettings: oldCards,
      onLayout: oldLayout,
      loadLayout: () async => loads++,
    );
    expect(loads, 1);
    expect(MainPageBridge.discoverLayoutChanged, oldLayout);
    preview.takeover.value = .6;
    expect(MainPageBridge.tvChromeDim.value, .6);
    MainPageBridge.discoverCardSettingsChanged = newCards;
    MainPageBridge.discoverLayoutChanged = newLayout;
    bridge.dispose();
    expect(MainPageBridge.discoverCardSettingsChanged, newCards);
    expect(MainPageBridge.discoverLayoutChanged, newLayout);
    preview.takeover.value = .9;
    expect(MainPageBridge.tvChromeDim.value, .6);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(MainPageBridge.tvChromeDim.value, 0);
    preview.dispose();
    MainPageBridge.discoverCardSettingsChanged = null;
    MainPageBridge.discoverLayoutChanged = null;
  });
}
