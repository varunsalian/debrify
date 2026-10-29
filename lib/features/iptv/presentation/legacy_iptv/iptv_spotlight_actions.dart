import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;
import 'package:debrify/utils/tv_keys.dart'
    show TvHeldKeyGuard, isActivateOrSpaceKey;
import 'package:debrify/widgets/iptv/multi_view_launcher.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef IptvSpotlightActionsDeps = ({
  IptvMembershipState membershipState,
  BuildContext Function() context,
  List<IptvListMeta> Function() customLists,
  bool Function() mounted,
  Future<void> Function(IptvChannel channel) openListPicker,
  void Function(IptvChannel channel) openSchedulePane,
  Future<void> Function(IptvChannel channel) playChannel,
  ({String label, IconData icon, VoidCallback action})? Function(
    IptvChannel channel,
  )
  spotlightRecordAction,
  Future<void> Function(IptvChannel channel, bool isFavorited) toggleFavorite,
});

class IptvSpotlightActions {
  final IptvSpotlightActionsDeps _deps;
  final IptvMembershipState _membershipState;

  IptvSpotlightActions(this._deps) : _membershipState = _deps.membershipState;

  List<IptvListMeta> get _customLists => _deps.customLists();

  Future<void> showSpotlightChannelActions(
    IptvChannel channel, {
    EpgProgramme? programme,
  }) async {
    final t = IptvStyleTokens.spotlight;
    final rawRecord = _deps.spotlightRecordAction(channel);
    final record =
        programme == null ||
            programme.airsAt(DateTime.now()) ||
            rawRecord?.label == 'Stop'
        ? rawRecord
        : null;
    final canSave = channel.contentType != 'series';
    final isFavorited = _membershipState.favoriteUrls.contains(channel.url);
    final hostContext = _deps.context();
    final multiView = MultiViewLauncher.eligible(channel);
    final inMultiView =
        multiView && MultiViewLauncher.contains(hostContext, channel);
    final multiViewCount = multiView ? MultiViewLauncher.count(hostContext) : 0;
    await showDialog<void>(
      context: _deps.context(),
      barrierColor: Colors.black.withValues(alpha: 0.68),
      builder: (dialogContext) {
        void closeThen(VoidCallback action) {
          Navigator.of(dialogContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_deps.mounted()) action();
          });
        }

        Widget actionTile({
          required IconData icon,
          required String label,
          required VoidCallback onPressed,
          Color? color,
          bool autofocus = false,
        }) {
          final ink = color ?? t.fg;
          return ListTile(
            autofocus: autofocus,
            leading: Icon(icon, color: ink),
            title: Text(label, style: TextStyle(color: ink)),
            onTap: () => closeThen(onPressed),
          );
        }

        var first = true;
        Widget nextTile({
          required IconData icon,
          required String label,
          required VoidCallback onPressed,
          Color? color,
        }) {
          final tile = actionTile(
            icon: icon,
            label: label,
            onPressed: onPressed,
            color: color,
            autofocus: first,
          );
          first = false;
          return tile;
        }

        return TvHeldKeyGuard(
          child: SimpleDialog(
            backgroundColor: t.panel,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: t.hairline2),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.fg, fontWeight: FontWeight.w800),
                  ),
                ),
                CloseButton(onPressed: () => Navigator.of(dialogContext).pop()),
              ],
            ),
            children: [
              if (record != null)
                nextTile(
                  icon: record.icon,
                  label: record.label,
                  color: record.label == 'Stop' ? t.rec : null,
                  onPressed: record.action,
                ),
              if (canSave)
                nextTile(
                  icon: isFavorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: isFavorited
                      ? 'Remove from Favorites'
                      : 'Add to Favorites',
                  color: isFavorited ? t.accent : null,
                  onPressed: () =>
                      unawaited(_deps.toggleFavorite(channel, !isFavorited)),
                ),
              if (canSave && _customLists.isNotEmpty)
                nextTile(
                  icon: Icons.bookmark_add_outlined,
                  label: 'Save to list',
                  onPressed: () => unawaited(_deps.openListPicker(channel)),
                ),
              if (IptvEpgService.isEpgCapable(channel))
                nextTile(
                  icon: Icons.calendar_month_rounded,
                  label: 'Full guide',
                  onPressed: () => _deps.openSchedulePane(channel),
                ),
              if (multiView)
                nextTile(
                  icon: inMultiView
                      ? Icons.grid_off_rounded
                      : Icons.grid_view_rounded,
                  label: inMultiView
                      ? 'Remove from multi-view'
                      : 'Add to multi-view',
                  onPressed: () => inMultiView
                      ? MultiViewLauncher.remove(_deps.context(), channel)
                      : MultiViewLauncher.add(
                          _deps.context(),
                          channel,
                          play: _deps.playChannel,
                        ),
                ),
              if (multiViewCount > 0)
                nextTile(
                  icon: Icons.window_rounded,
                  label: 'Open multi-view ($multiViewCount)',
                  onPressed: () => unawaited(
                    MultiViewLauncher.open(
                      _deps.context(),
                      play: _deps.playChannel,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  WidgetStateProperty<BorderSide?> get spotlightFocusBorder =>
      WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.focused)
              ? IptvStyleTokens.spotlight.accent
              : Colors.transparent,
          width: 3,
        ),
      );

  Widget spotlightActivation(VoidCallback action, Widget child) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (!isActivateOrSpaceKey(event.logicalKey)) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent) action();
      return KeyEventResult.handled;
    },
    child: child,
  );

  Widget spotlightIconAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool selected = false,
  }) {
    final t = IptvStyleTokens.spotlight;
    return spotlightActivation(
      onPressed,
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        style:
            IconButton.styleFrom(
              foregroundColor: selected ? t.accent : t.fgMid,
              backgroundColor: selected ? t.selectedTint : t.focusTint,
              side: BorderSide(color: selected ? t.accent : t.hairline2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? t.focusFill
                    : selected
                    ? t.selectedTint
                    : t.focusTint,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? t.focusInk
                    : selected
                    ? t.accent
                    : t.fgMid,
              ),
            ),
        icon: Icon(icon, size: 18),
      ),
    );
  }
}
