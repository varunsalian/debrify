import 'package:flutter/material.dart';

import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../services/storage_service.dart';

/// One selectable row: a live channel saved in Favourites or a custom list.
///
/// [playlistId] is the ORIGIN provider, not the list it was picked from. The
/// same URL can be saved from two different providers (the membership store
/// keys origins by `(listId, url)` for exactly that reason), so a URL alone
/// cannot say which account should replay it — picking the wrong one would boot
/// the channel under someone else's credentials.
class IptvStartupChannelChoice {
  final String url;
  final String name;
  final String? playlistId;
  final int? channelNumber;
  final String? group;
  final String? logoUrl;
  final Map<String, String> httpHeaders;

  /// Which list this row was shown under — display only, never identity.
  final String listName;

  const IptvStartupChannelChoice({
    required this.url,
    required this.name,
    required this.playlistId,
    required this.channelNumber,
    required this.group,
    required this.logoUrl,
    required this.httpHeaders,
    required this.listName,
  });

  /// Identity is provider + URL. Two rows for the same URL under different
  /// providers are genuinely different choices and must both remain pickable.
  Object get identity => (playlistId ?? '', url);
}

/// Pick a live channel to boot into, from Favourites and the user's lists.
///
/// Deliberately NOT a picker over the provider catalog: that can hold 50k rows,
/// and a startup channel is something the user has already decided matters —
/// which is what starring it means. Returns null if dismissed.
Future<IptvStartupChannelChoice?> showIptvStartupChannelPicker(
  BuildContext context,
) async {
  final lists = await StorageService.getIptvLists();
  final snapshot = await StorageService.getIptvMembershipSnapshot();
  final choices = <IptvStartupChannelChoice>[];
  final seen = <Object>{};

  for (final list in lists) {
    final channels = await StorageService.getIptvListChannels(list.id);
    channels.forEach((url, meta) {
      final contentType = meta['contentType'] as String?;
      final duration = (meta['duration'] as num?)?.toInt();
      // Mirrors IptvChannel.isLive — VOD and series can't be startup channels
      // (no live edge to tune to, and resume semantics don't apply).
      final isLive = contentType != null
          ? contentType == 'live'
          : (duration == null || duration == -1);
      if (!isLive) return;

      // Origin recorded per (list, url); the metadata's own playlistId is the
      // fallback for rows saved before origins were tracked.
      final origin =
          snapshot.origins[(list.id, url)] ?? meta['playlistId'] as String?;
      final choice = IptvStartupChannelChoice(
        url: url,
        name: (meta['name'] as String?)?.trim().isNotEmpty == true
            ? meta['name'] as String
            : url,
        playlistId: origin,
        channelNumber: (meta['channelNumber'] as num?)?.toInt(),
        group: meta['group'] as String?,
        logoUrl: meta['logoUrl'] as String?,
        httpHeaders: StorageService.iptvFavoriteHeaders(meta),
        listName: list.name,
      );
      // The same channel starred AND in a list appears once; a duplicate URL
      // from a different provider is a distinct row and survives.
      if (seen.add(choice.identity)) choices.add(choice);
    });
  }

  choices.sort((a, b) {
    final an = a.channelNumber;
    final bn = b.channelNumber;
    if (an != null && bn != null && an != bn) return an.compareTo(bn);
    if (an != null && bn == null) return -1;
    if (an == null && bn != null) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  if (!context.mounted) return null;
  return showDialog<IptvStartupChannelChoice>(
    context: context,
    builder: (context) => _StartupChannelDialog(choices: choices, lists: lists),
  );
}

class _StartupChannelDialog extends StatelessWidget {
  final List<IptvStartupChannelChoice> choices;
  final List<IptvListMeta> lists;

  const _StartupChannelDialog({required this.choices, required this.lists});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Startup channel'),
      content: SizedBox(
        width: 420,
        child: choices.isEmpty
            ? const Text(
                'No live channels saved yet.\n\n'
                'Hold OK (or long-press) a channel on the IPTV page to star it '
                'or add it to a list, then pick it here.',
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: choices.length,
                itemBuilder: (context, index) {
                  final choice = choices[index];
                  final number = choice.channelNumber;
                  return ListTile(
                    autofocus: index == 0,
                    leading: number != null
                        ? SizedBox(
                            width: 44,
                            child: Text(
                              'CH $number',
                              style: const TextStyle(fontSize: 11),
                            ),
                          )
                        : const Icon(Icons.live_tv_rounded, size: 20),
                    title: Text(
                      choice.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        choice.listName,
                        if (choice.group != null && choice.group!.isNotEmpty)
                          choice.group!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(choice),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
