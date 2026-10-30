import 'package:debrify/features/recordings/presentation/recordings_hub_tokens.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The network share at a glance, at the top of the Recordings page: where
/// recordings go now, or an invitation to set one up. One press opens the
/// share's settings.
class RecordingsHubShareStatus extends StatefulWidget {
  const RecordingsHubShareStatus({
    super.key,
    required this.address,
    required this.recordsDirect,
    required this.onOpen,
    this.autofocus = false,
  });

  /// `\\host\share\folder`; null when no share is set up.
  final String? address;
  final bool recordsDirect;
  final VoidCallback onOpen;
  final bool autofocus;

  @override
  State<RecordingsHubShareStatus> createState() =>
      _RecordingsHubShareStatusState();
}

class _RecordingsHubShareStatusState extends State<RecordingsHubShareStatus> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'recordings_share_status');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final address = widget.address;
    final focused = _focusNode.hasFocus;
    final title = address == null
        ? 'Save recordings to a network share'
        : widget.recordsDirect
        ? 'Recording to your network share'
        : 'Copying recordings to your network share';
    final subtitle =
        address ?? 'A NAS or another computer (SMB) — nothing kept here';
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onOpen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        button: true,
        label: '$title. $subtitle',
        excludeSemantics: true,
        onTap: widget.onOpen,
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.07)
                  : kRecordingsHubAccent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: focused
                    ? kRecordingsHubGold
                    : kRecordingsHubAccent.withValues(alpha: 0.25),
                width: focused ? 1.8 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  address == null ? Icons.dns_outlined : Icons.lan_rounded,
                  size: 20,
                  color: kRecordingsHubAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  address == null ? 'Set up' : 'Change',
                  style: TextStyle(
                    color: focused ? kRecordingsHubGold : kRecordingsHubAccent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
