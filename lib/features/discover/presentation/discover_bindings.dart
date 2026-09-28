import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/discover_card_settings_controller.dart';
import '../application/discover_layout_controller.dart';
import '../application/discover_source_controller.dart';
import '../models/discover_card_settings.dart';
import '../models/discover_source_state.dart';

/// Keeps the three route-specific Discover providers alive until the host's
/// ordered teardown. Controllers remain the sole owners of application state.
class DiscoverBindings {
  DiscoverBindings(WidgetRef ref, DiscoverSourceSession session) {
    final layoutSession = (
      owner: session.owner,
      viewIdentity: session.viewIdentity,
    );
    _cards = ref.listenManual(
      discoverCardSettingsProvider(layoutSession),
      (_, _) {},
    );
    cards = ref.read(discoverCardSettingsProvider(layoutSession).notifier);
    _layout = ref.listenManual(
      discoverLayoutProvider(layoutSession),
      (_, _) {},
    );
    layout = ref.read(discoverLayoutProvider(layoutSession).notifier);
    _source = ref.listenManual(discoverSourceProvider(session), (_, _) {});
    source = ref.read(discoverSourceProvider(session).notifier);
  }

  late final ProviderSubscription<DiscoverCardSettings> _cards;
  late final ProviderSubscription<String> _layout;
  late final ProviderSubscription<DiscoverSourceState> _source;
  late final DiscoverCardSettingsController cards;
  late final DiscoverLayoutController layout;
  late final DiscoverSourceController source;

  void close() {
    _cards.close();
    _layout.close();
    _source.close();
  }
}
