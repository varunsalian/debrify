import 'package:flutter/material.dart';

import '../services/storage/tv_display_storage.dart';
import '../utils/platform_util.dart';
import 'tv_text_field.dart';

/// A single-field prompt (a URL, a pasted document) that pops the trimmed
/// text on confirm and null on cancel. Empty input never confirms.
class TextPromptDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String helper;

  /// Label of the confirm button.
  final String action;
  final bool multiline;

  /// Ignored when [multiline] (which forces the multiline keyboard).
  final TextInputType? keyboardType;

  const TextPromptDialog({
    super.key,
    required this.title,
    required this.hint,
    required this.helper,
    required this.action,
    this.multiline = false,
    this.keyboardType,
  });

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _actionNode = FocusNode(debugLabel: 'text-prompt-action');

  @override
  void dispose() {
    _controller.dispose();
    _actionNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // On TV a plain (multiline) field kept every remote press: UP and
            // DOWN moved its caret, so the action button was unreachable.
            // The TV field is one line and DOWN goes to the action.
            if (PlatformUtil.isTelevision)
              TvTextField(
                controller: _controller,
                autofocus: true,
                keyboardType: widget.multiline
                    ? TextInputType.text
                    : (widget.keyboardType ?? TextInputType.text),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  border: const OutlineInputBorder(),
                ),
                // Apple TV's system keyboard reports Done and Menu alike as
                // "editing ended", so submitting there would import on Menu;
                // DOWN reaches the action instead.
                onSubmitted:
                    PlatformUtil.isTvOS &&
                        !TvDisplayStorage.tvKeyboardEnabledCached
                    ? null
                    : (_) => _submit(),
                onDownArrow: _actionNode.requestFocus,
              )
            else
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: widget.multiline
                    ? TextInputType.multiline
                    : (widget.keyboardType ?? TextInputType.text),
                maxLines: widget.multiline ? 10 : 1,
                minLines: widget.multiline ? 6 : 1,
                textInputAction: widget.multiline
                    ? TextInputAction.newline
                    : TextInputAction.done,
                onSubmitted: widget.multiline ? null : (_) => _submit(),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  border: const OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 8),
            Text(widget.helper, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          focusNode: _actionNode,
          onPressed: _submit,
          child: Text(widget.action),
        ),
      ],
    );
  }
}
