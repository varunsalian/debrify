import 'package:flutter/material.dart';

import '../tv_text_field.dart';

/// Shared search header for the "Browse" sidebar tabs (IPTV, YouTube).
///
/// Matches the styling of the Stremio TV search field. The parent owns the
/// controller/focus node and decides whether to react on [onChanged] (live
/// filtering) or [onSubmitted] (network search).
///
/// The clear (✕) affordance is driven by the controller's actual text — not by
/// any committed query value — so it stays in sync while typing even when the
/// parent only commits the query on submit.
class BrowseSearchHeader extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback onClear;

  /// DPAD-down exit from the field (drops into the results/filters).
  final VoidCallback? onDownArrow;

  const BrowseSearchHeader({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onClear,
    this.onChanged,
    this.onSubmitted,
    this.onDownArrow,
  });

  @override
  State<BrowseSearchHeader> createState() => _BrowseSearchHeaderState();
}

class _BrowseSearchHeaderState extends State<BrowseSearchHeader> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(BrowseSearchHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    // Rebuild so the clear button appears/disappears with the field contents.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: TvTextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        style: const TextStyle(color: Colors.white),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onDownArrow: widget.onDownArrow,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: Colors.white.withValues(alpha: 0.35),
          ),
          suffixIcon: hasText
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  onPressed: widget.onClear,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.07),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
