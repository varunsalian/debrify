import '../../../models/home_collection.dart';

/// Read-only collection access. The existing store owns profile resolution,
/// parsing and worker-isolate hashing; this adapter adds no cache or retries.
class HomeCollectionsRepository {
  const HomeCollectionsRepository({
    required Future<List<HomeCollection>> Function() read,
    required this.signature,
    required this.onReadFailure,
  }) : _read = read;

  final Future<List<HomeCollection>> Function() _read;
  final Future<String> Function(List<HomeCollection>) signature;
  final void Function() onReadFailure;

  Future<List<HomeCollection>> read() async {
    try {
      // Preserve legacy model identities; callers borrow a read-only container.
      return List.unmodifiable(await _read());
    } catch (_) {
      onReadFailure();
      return const [];
    }
  }
}
