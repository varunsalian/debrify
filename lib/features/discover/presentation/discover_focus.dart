import 'package:flutter/widgets.dart';
import '../../../models/stremio_addon.dart';

/// Route-owned Discover source focus and selected-title signal. Embedded panels
/// borrow these resources; selection updates only the detail rail listeners.
class DiscoverFocus {
  final source = FocusNode(debugLabel: 'disc_source');
  final focused = ValueNotifier<StremioMeta?>(null);

  void selectTitle(StremioMeta item) => focused.value = item;

  /// Wait for the new source panel to reattach the shared source node.
  void restoreSource({required bool Function() isCurrent}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isCurrent()) source.requestFocus();
    });
  }

  void dispose() {
    source.dispose();
    focused.dispose();
  }
}
