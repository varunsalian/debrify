import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/tv_keys.dart';

/// One action row in [showDebridActionSheet].
class DebridActionItem {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;
  const DebridActionItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    required this.onTap,
  });
}

/// The app's standard "Added to `<provider>`" post-add chooser — a glass card
/// with the provider's gradient icon, the torrent name, and DPAD-navigable
/// action tiles. Mirrors Home's per-provider post-add sheets so the Search tab
/// looks identical. Each action pops the sheet first, then runs.
Future<void> showDebridActionSheet(
  BuildContext context, {
  required String providerLabel,
  required String torrentName,
  required List<Color> gradient,
  required IconData providerIcon,
  required String subtitle,
  required List<DebridActionItem> actions,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          color: const Color(0xFF0F172A),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(providerIcon, color: Colors.white),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            torrentName,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              ...actions.asMap().entries.map(
                    (e) => DebridActionTile(
                      icon: e.value.icon,
                      color: e.value.color,
                      title: e.value.title,
                      subtitle: e.value.subtitle,
                      enabled: e.value.enabled,
                      autofocus: e.key == 0,
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        if (e.value.enabled) e.value.onTap();
                      },
                    ),
                  ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A styled action tile matching Home's `_DebridActionTile` (icon chip + title
/// + subtitle, focus highlight, DPAD-select on key-up).
class DebridActionTile extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final bool autofocus;

  const DebridActionTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  State<DebridActionTile> createState() => _DebridActionTileState();
}

class _DebridActionTileState extends State<DebridActionTile> {
  bool _focused = false;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!isActivateKey(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) return KeyEventResult.handled;
    if (event is KeyUpEvent) {
      if (widget.enabled) widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.35,
      child: Focus(
        autofocus: widget.autofocus,
        canRequestFocus: widget.enabled,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _focused
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.color
                        .withValues(alpha: _focused ? 0.25 : 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
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
