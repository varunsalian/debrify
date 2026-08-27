import 'descriptor.dart';
import 'provider.dart';

/// The debrid providers this build has, already wired.
///
/// An instance rather than a static table: a provider that takes its
/// dependencies through its constructor cannot live in a `const` map, and
/// making the map `const` was what forced every adapter to reach for a global
/// instead. Composition builds one of these and hands it down.
///
/// Adding a provider is an implementation plus one line where the graph is
/// assembled — not an edit here.
class DebridRegistry {
  final Map<String, DebridProvider> _byId;

  /// [providers] in the order pickers and settings should list them.
  DebridRegistry(List<DebridProvider> providers)
    : _byId = {
        for (final provider in providers) provider.descriptor.id: provider,
      };

  /// Registration order.
  List<DebridProvider> get all => _byId.values.toList(growable: false);

  /// The provider for any spelling of its id, or null when the id names no
  /// provider (`none`, `auto`, `webdav`, a local binding, an addon stream).
  DebridProvider? find(String? rawId) {
    final id = DebridProviderIds.normalize(rawId);
    return id == null ? null : _byId[id];
  }

  /// Providers whose credentials are present, in registration order.
  Future<List<DebridProvider>> configured() async {
    final found = <DebridProvider>[];
    for (final provider in all) {
      if (await provider.isConfigured()) found.add(provider);
    }
    return found;
  }
}
