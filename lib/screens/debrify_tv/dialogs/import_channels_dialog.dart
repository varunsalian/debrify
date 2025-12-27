import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Import mode selection for channels
enum ImportChannelsMode { device, url, community }

/// Dialog for selecting import mode with DPAD support and awesome TV-optimized UI
class ImportChannelsDialog extends StatefulWidget {
  final bool isAndroidTv;

  const ImportChannelsDialog({required this.isAndroidTv});

  @override
  State<ImportChannelsDialog> createState() => ImportChannelsDialogState();
}

class ImportChannelsDialogState extends State<ImportChannelsDialog> {
  // Focus nodes for DPAD navigation
  final FocusNode _deviceFocusNode = FocusNode();
  final FocusNode _linkFocusNode = FocusNode();
  final FocusNode _communityFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();

  // Track current focused index for visual feedback
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();

    // Set up focus listeners
    _deviceFocusNode.addListener(() {
      if (_deviceFocusNode.hasFocus) {
        setState(() => _focusedIndex = 0);
      }
    });

    _linkFocusNode.addListener(() {
      if (_linkFocusNode.hasFocus) {
        setState(() => _focusedIndex = 1);
      }
    });

    _communityFocusNode.addListener(() {
      if (_communityFocusNode.hasFocus) {
        setState(() => _focusedIndex = 2);
      }
    });

    _cancelFocusNode.addListener(() {
      if (_cancelFocusNode.hasFocus) {
        setState(() => _focusedIndex = 3);
      }
    });

    // Auto-focus first option for TV
    if (widget.isAndroidTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _deviceFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _deviceFocusNode.dispose();
    _linkFocusNode.dispose();
    _communityFocusNode.dispose();
    _cancelFocusNode.dispose();
    super.dispose();
  }

  Widget _buildImportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required FocusNode focusNode,
    required VoidCallback onSelect,
    required bool isFocused,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            onSelect();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: isFocused ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isFocused
                ? const Color(0xFF1E293B).withOpacity(0.8)
                : const Color(0xFF0F172A).withOpacity(0.6),
            border: Border.all(
              color: isFocused
                  ? accentColor.withOpacity(0.4)
                  : Colors.white.withOpacity(0.05),
              width: 1,
            ),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: accentColor.withOpacity(0.15),
                      blurRadius: 16,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                // Left accent strip on focus
                if (isFocused)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accentColor,
                            accentColor.withOpacity(0.6),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.isAndroidTv ? null : onSelect,
                    borderRadius: BorderRadius.circular(12),
                    splashColor: accentColor.withOpacity(0.1),
                    highlightColor: accentColor.withOpacity(0.05),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isFocused ? 16 : 14,
                        12,
                        14,
                        12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            icon,
                            size: 28,
                            color: isFocused
                                ? accentColor
                                : Colors.white.withOpacity(0.7),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: widget.isAndroidTv ? 17 : 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: widget.isAndroidTv ? 13 : 12,
                                    color: Colors.white.withOpacity(0.65),
                                    height: 1.3,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isFocused)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.arrow_forward_ios_rounded,
                                color: accentColor.withOpacity(0.8),
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = widget.isAndroidTv ? 540.0 : 500.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.06),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.download_rounded,
                    color: Colors.white.withOpacity(0.9),
                    size: widget.isAndroidTv ? 24 : 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Import Channels',
                    style: TextStyle(
                      fontSize: widget.isAndroidTv ? 22 : 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Column(
                    children: [
                      // Device Import Option
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: _buildImportOption(
                          icon: Icons.sd_storage_rounded,
                          title: 'Import from Device',
                          subtitle:
                              'Load a .zip, .yaml, .txt, or .debrify file',
                          accentColor: const Color(0xFF2563EB),
                          focusNode: _deviceFocusNode,
                          isFocused: _focusedIndex == 0,
                          onSelect: () {
                            Navigator.of(
                              context,
                            ).pop(ImportChannelsMode.device);
                          },
                        ),
                      ),

                      // Link Import Option
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(2),
                        child: _buildImportOption(
                          icon: Icons.link_rounded,
                          title: 'Import from Link',
                          subtitle:
                              'Paste a debrify:// link or URL to a channel file',
                          accentColor: const Color(0xFF7C3AED),
                          focusNode: _linkFocusNode,
                          isFocused: _focusedIndex == 1,
                          onSelect: () {
                            Navigator.of(context).pop(ImportChannelsMode.url);
                          },
                        ),
                      ),

                      // Community Import Option
                      FocusTraversalOrder(
                        order: const NumericFocusOrder(3),
                        child: _buildImportOption(
                          icon: Icons.people_rounded,
                          title: 'Import Community Shared Channels',
                          subtitle:
                              'Browse and import channels from community repositories',
                          accentColor: const Color(0xFF10B981),
                          focusNode: _communityFocusNode,
                          isFocused: _focusedIndex == 2,
                          onSelect: () {
                            Navigator.of(
                              context,
                            ).pop(ImportChannelsMode.community);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Cancel Button
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.06),
                    width: 1,
                  ),
                ),
              ),
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(4),
                child: Focus(
                  focusNode: _cancelFocusNode,
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.space ||
                          event.logicalKey == LogicalKeyboardKey.gameButtonA) {
                        Navigator.of(context).pop();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: _focusedIndex == 3
                          ? Colors.white.withOpacity(0.08)
                          : Colors.transparent,
                      border: Border.all(
                        color: _focusedIndex == 3
                            ? Colors.white.withOpacity(0.2)
                            : Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.isAndroidTv
                            ? null
                            : () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.close_rounded,
                                color: _focusedIndex == 3
                                    ? Colors.white.withOpacity(0.9)
                                    : Colors.white.withOpacity(0.6),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: widget.isAndroidTv ? 16 : 15,
                                  fontWeight: FontWeight.w500,
                                  color: _focusedIndex == 3
                                      ? Colors.white.withOpacity(0.9)
                                      : Colors.white.withOpacity(0.6),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
