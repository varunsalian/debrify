import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/dialog_tap_guard.dart';
import '../../utils/tv_keys.dart';
import '../tv_text_field.dart';

/// Name entry for a channel list — used to create one and to rename one.
///
/// Returns the trimmed name, or null when cancelled. [existingNames] is
/// checked case-insensitively so two lists can't end up visually identical in
/// the Sources picker, where the name is all the user has to tell them apart.
Future<String?> showIptvListNameDialog({
  required BuildContext context,
  required String title,
  required String confirmLabel,
  String initialValue = '',
  List<String> existingNames = const [],
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _IptvListNameDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialValue: initialValue,
      existingNames: existingNames,
    ),
  );
}

class _IptvListNameDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String initialValue;
  final List<String> existingNames;

  const _IptvListNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialValue,
    required this.existingNames,
  });

  @override
  State<_IptvListNameDialog> createState() => _IptvListNameDialogState();
}

class _IptvListNameDialogState extends State<_IptvListNameDialog> {
  static const _accent = Color(0xFF8B5CF6);

  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  final FocusNode _fieldNode = FocusNode(debugLabel: 'iptv-list-name-field');
  final FocusNode _confirmNode = FocusNode(debugLabel: 'iptv-list-name-ok');
  final FocusNode _cancelNode = FocusNode(debugLabel: 'iptv-list-name-cancel');
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _fieldNode.dispose();
    _confirmNode.dispose();
    _cancelNode.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the list a name');
      return;
    }
    final clash = widget.existingNames.any(
      (existing) =>
          existing.toLowerCase() == name.toLowerCase() &&
          existing.toLowerCase() != widget.initialValue.trim().toLowerCase(),
    );
    if (clash) {
      setState(() => _error = 'You already have a list called that');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Dialog(
      backgroundColor: const Color(0xFF141019),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width < 480 ? width : 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              // Back on the (non-editing) field hops to Cancel rather than
              // bubbling on and popping the dialog. While EDITING, TvTextField
              // consumes Back itself to close the keyboard.
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.escape ||
                      key == LogicalKeyboardKey.goBack ||
                      key == LogicalKeyboardKey.browserBack) {
                    _cancelNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TvTextField(
                  controller: _controller,
                  focusNode: _fieldNode,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'List name',
                    labelStyle: const TextStyle(color: Colors.white60),
                    hintText: 'e.g. Kids, Sports, Weekend',
                    hintStyle: const TextStyle(color: Colors.white38),
                    errorText: _error,
                    filled: true,
                    fillColor: const Color(0xFF0F0B14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A2233)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2A2233)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _accent, width: 2),
                    ),
                  ),
                  onDownArrow: () => _confirmNode.requestFocus(),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _NameDialogButton(
                    focusNode: _cancelNode,
                    label: 'Cancel',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _NameDialogButton(
                    focusNode: _confirmNode,
                    label: widget.confirmLabel,
                    filled: true,
                    onTap: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameDialogButton extends StatefulWidget {
  final FocusNode focusNode;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _NameDialogButton({
    required this.focusNode,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  State<_NameDialogButton> createState() => _NameDialogButtonState();
}

class _NameDialogButtonState extends State<_NameDialogButton> {
  static const _accent = Color(0xFF8B5CF6);
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (isActivateKey(event.logicalKey)) {
          DialogTapGuard.markKeyAction();
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          if (DialogTapGuard.shouldIgnoreTap()) return;
          widget.onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: widget.filled
                ? _accent.withValues(alpha: _focused ? 1 : 0.85)
                : Colors.white.withValues(alpha: _focused ? 0.16 : 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
