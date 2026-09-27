import '../../../models/stremio_addon.dart';

/// Existing preference formats and addon service remain adapter concerns.
class DiscoverSourceRepository {
  const DiscoverSourceRepository({
    required this.readDefault,
    required this.readLast,
    required this.readAddons,
    required this.writeLast,
  });

  /// Null denotes the existing remember-last preference.
  final Future<String?> Function() readDefault;
  final Future<String> Function() readLast;
  final Future<List<StremioAddon>> Function() readAddons;
  final Future<void> Function(String source, bool Function() isCurrent)
  writeLast;

  Future<String> readLanding() async {
    final values = await Future.wait([readDefault(), readLast()]);
    return values[0] ?? values[1]!;
  }
}
