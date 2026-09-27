import '../../../models/iptv_playlist.dart';

typedef HomeIptvListMeta = ({String id, String title, bool isFavorites});

/// Accepted data for an opted-in row; focus resources belong to presentation.
class HomeIptvList {
  HomeIptvList({
    required this.listId,
    required this.title,
    required List<IptvChannel> channels,
  }) : channels = List.unmodifiable(channels);

  final String listId;
  final String title;
  final List<IptvChannel> channels;
}
