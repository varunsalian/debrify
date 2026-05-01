import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a picker dialog for adding a new bound source.
///
/// Options:
/// - Torrent Search (always shown, in SEARCH section)
/// - Local File / Folder (only if [onLocal] is non-null, in LOCAL section)
/// - Disabled Local File / Folder (only if [localDisabledReason] is non-null)
/// - Real-Debrid (only if [onRealDebrid] is non-null, in CLOUD section)
/// - TorBox (only if [onTorbox] is non-null, in CLOUD section)
///
/// If [onLocal], [onRealDebrid], and [onTorbox] are null, callers may skip
/// showing this dialog and call [onTorrentSearch] directly.
Future<void> showAddSourcePickerDialog(
  BuildContext context, {
  required VoidCallback onTorrentSearch,
  VoidCallback? onLocal,
  String? localDisabledReason,
  VoidCallback? onRealDebrid,
  VoidCallback? onTorbox,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: const [
                    Icon(
                      Icons.add_link_rounded,
                      color: Color(0xFF60A5FA),
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Add Source',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // SEARCH section
                const _SectionHeader(
                  title: 'SEARCH',
                  subtitle: 'Find new torrents from scrapers',
                ),
                const SizedBox(height: 8),
                _SourceOption(
                  icon: Icons.search_rounded,
                  iconColor: const Color(0xFFFBBF24),
                  label: 'Torrent Search',
                  autofocus: true,
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    onTorrentSearch();
                  },
                ),

                if (onLocal != null || localDisabledReason != null) ...[
                  const SizedBox(height: 16),
                  const _SectionHeader(
                    title: 'LOCAL',
                    subtitle: 'Use files on this device',
                  ),
                  const SizedBox(height: 8),
                  _SourceOption(
                    icon: Icons.folder_open_rounded,
                    iconColor: const Color(0xFF60A5FA),
                    label: 'Local File or Folder',
                    subtitle: localDisabledReason,
                    onTap: onLocal == null
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop();
                            onLocal();
                          },
                  ),
                ],

                // CLOUD section (only if at least one provider enabled)
                if (onRealDebrid != null || onTorbox != null) ...[
                  const SizedBox(height: 16),
                  const _SectionHeader(
                    title: 'CLOUD',
                    subtitle:
                        'Pick an already downloaded source from your cloud',
                  ),
                  const SizedBox(height: 8),
                  if (onRealDebrid != null)
                    _SourceOption(
                      icon: Icons.cloud,
                      iconColor: const Color(0xFF22C55E),
                      label: 'Real-Debrid',
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        onRealDebrid();
                      },
                    ),
                  if (onTorbox != null) ...[
                    const SizedBox(height: 8),
                    _SourceOption(
                      icon: Icons.cloud,
                      iconColor: const Color(0xFF7C3AED),
                      label: 'TorBox',
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        onTorbox();
                      },
                    ),
                  ],
                ],

                const SizedBox(height: 12),
                // Cancel button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }
}

class _SourceOption extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final bool autofocus;
  final VoidCallback? onTap;

  const _SourceOption({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.autofocus = false,
  });

  @override
  State<_SourceOption> createState() => _SourceOptionState();
}

class _SourceOptionState extends State<_SourceOption> {
  late final FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'source-option-${widget.label}');
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _isFocused = _focusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final iconColor = enabled ? widget.iconColor : Colors.white30;
    final textColor = enabled ? Colors.white : Colors.white38;
    return Focus(
      focusNode: _focusNode,
      autofocus: enabled && widget.autofocus,
      canRequestFocus: enabled,
      onKeyEvent: (node, event) {
        if (enabled &&
            event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: _isFocused
                ? widget.iconColor.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isFocused
                  ? widget.iconColor
                  : Colors.white.withValues(alpha: 0.1),
              width: _isFocused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: iconColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle!,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: enabled ? Colors.white38 : Colors.white24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
