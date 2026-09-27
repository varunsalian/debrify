import '../models/home_continuation_layout.dart';

class HomeContinuationLayoutRepository {
  const HomeContinuationLayoutRepository({
    required Future<bool> Function(String provider) readMerged,
  }) : _readMerged = readMerged;

  final Future<bool> Function(String provider) _readMerged;

  Future<HomeContinuationLayout> read() async {
    final flags = await Future.wait([
      _readMerged('local'),
      _readMerged('trakt'),
      _readMerged('simkl'),
      _readMerged('mdblist'),
    ]);
    return HomeContinuationLayout(
      local: flags[0],
      trakt: flags[1],
      simkl: flags[2],
      mdblist: flags[3],
    );
  }
}
