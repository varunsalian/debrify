import 'package:debrify/models/debrify_tv_channel_record.dart';

DebrifyTvChannelRecord channel(String id, {List<String>? keywords}) =>
    DebrifyTvChannelRecord(
      channelId: id,
      name: 'Channel $id',
      keywords: keywords ?? ['query $id'],
      avoidNsfw: true,
      channelNumber: 0,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026, 2),
    );
