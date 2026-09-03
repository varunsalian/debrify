import 'package:flutter/material.dart';

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

  @override
  void dispose() {
    _controller.dispose();
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
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
        TextButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}
