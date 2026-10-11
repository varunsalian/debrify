import 'package:debrify/models/iptv_playlist.dart';

/// One page of a live IPTV category, as the browse provider returns it.
///
/// [offset] is the page's absolute position inside [category] and [total] is
/// how many channels that category holds — the pair that tells the end of a
/// loaded window apart from the end of the category itself.
class VpIptvZapPage {
  final List<IptvChannel> channels;
  final int offset;
  final int total;
  final String? sourceId;
  final String? category;
  final List<String> categories;

  const VpIptvZapPage({
    required this.channels,
    required this.offset,
    required this.total,
    required this.sourceId,
    required this.category,
    required this.categories,
  });
}
