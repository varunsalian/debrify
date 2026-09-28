import 'package:flutter/material.dart';
import '../models/debrify_tv_channel_action.dart';
import '../models/rd_torrent.dart';
import '../models/torrent.dart';
import '../models/torbox_torrent.dart';
import 'channel_picker_dialog.dart';
import '../services/debrify_tv_channel_actions.dart';
import '../services/profiles/profile_session_memory.dart';
export '../models/debrify_tv_channel_action.dart';

/// Legacy presentation bridge; channel data and persistence belong to actions.
class DebrifyTvChannelAddBridge {
  const DebrifyTvChannelAddBridge._();
  static Future<DebrifyTvChannelAddResult?> addTorrentsToChannel(
    BuildContext context, {
    required List<Torrent> torrents,
    required String searchKeyword,
    ProfileSessionOwner? owner,
    bool Function()? canContinue,
  }) async {
    final actions = DebrifyTvChannelActions(
      owner: owner ?? ProfileSessionMemory.captureOwner(),
      canContinue: () => context.mounted && (canContinue?.call() ?? true),
    );
    if (!actions.isCurrent) return null;
    final trimmedKeyword = searchKeyword.trim();
    final filteredTorrents = DebrifyTvChannelActions.prepare(torrents);
    final pickerResult = await showDialog<ChannelPickerResult>(
      context: context,
      builder: (ctx) => ChannelPickerDialog(
        searchKeyword: trimmedKeyword,
        loadChannels: actions.loadChannels,
        createChannel: (name, active) =>
            actions.createChannel(name, trimmedKeyword, canContinue: active),
        canContinue: () => actions.isCurrent,
      ),
    );
    if (pickerResult == null || !actions.isCurrent) return null;
    try {
      return await actions.add(pickerResult, filteredTorrents, trimmedKeyword);
    } catch (_) {
      if (!actions.isCurrent) return null;
      rethrow;
    }
  }

  static Torrent fromRealDebridTorrent(RDTorrent torrent) =>
      DebrifyTvChannelActions.fromRealDebridTorrent(torrent);
  static Torrent fromTorboxTorrent(TorboxTorrent torrent) =>
      DebrifyTvChannelActions.fromTorboxTorrent(torrent);
}
