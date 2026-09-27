import '../../../models/debrify_tv/channel.dart';
import '../../../models/debrify_tv_channel_record.dart';

typedef HomeTvFavoritesRead = ({
  List<DebrifyTvChannel> channels,
  bool hasFavoriteIds,
});

/// Reads favourites and their channel records in the existing sequence/order.
class HomeTvFavoritesRepository {
  const HomeTvFavoritesRepository({
    required Future<Set<String>> Function() favoriteIds,
    required Future<List<DebrifyTvChannelRecord>> Function() channels,
  }) : _favoriteIds = favoriteIds,
       _channels = channels;

  final Future<Set<String>> Function() _favoriteIds;
  final Future<List<DebrifyTvChannelRecord>> Function() _channels;

  /// Null indicates retirement. Failures propagate to the row's existing
  /// silent-retention policy; an empty favourite set avoids the database read.
  Future<HomeTvFavoritesRead?> read({
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    final ids = await _favoriteIds();
    if (!isCurrent()) return null;
    if (ids.isEmpty) {
      return (channels: const <DebrifyTvChannel>[], hasFavoriteIds: false);
    }
    final records = await _channels();
    if (!isCurrent()) return null;
    return (
      // Database order is authoritative, including ties at channel number zero.
      channels: List<DebrifyTvChannel>.unmodifiable(
        records
            .map(DebrifyTvChannel.fromRecord)
            .where((c) => ids.contains(c.id))
            .map((c) => c.copyWith(keywords: List.unmodifiable(c.keywords))),
      ),
      hasFavoriteIds: true,
    );
  }
}
