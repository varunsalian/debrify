/// Result returned when user selects or creates a channel
class ChannelPickerResult {
  final String channelId;
  final String channelName;
  final bool isNewChannel;

  const ChannelPickerResult({
    required this.channelId,
    required this.channelName,
    required this.isNewChannel,
  });
}

class DebrifyTvChannelAddException implements Exception {
  const DebrifyTvChannelAddException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DebrifyTvChannelAddResult {
  const DebrifyTvChannelAddResult({
    required this.channelId,
    required this.channelName,
    required this.isNewChannel,
    required this.totalCount,
    required this.addedCount,
    required this.updatedCount,
  });

  final String channelId;
  final String channelName;
  final bool isNewChannel;
  final int totalCount;
  final int addedCount;
  final int updatedCount;

  String get successMessage {
    final noun = totalCount == 1 ? '1 torrent' : '$totalCount torrents';
    if (isNewChannel) {
      return 'Channel "$channelName" created with $noun';
    }
    if (addedCount == 0) {
      final updatedNoun = updatedCount == 1
          ? 'Torrent'
          : '$updatedCount torrents';
      return '$updatedNoun updated in "$channelName"';
    }
    return '$noun added to "$channelName"';
  }
}
