import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/remote_control/remote_control_state.dart';
import '../../services/remote_control/remote_constants.dart';

/// Widget for sending keyboard input to connected TV
class RemoteKeyboardInput extends StatefulWidget {
  final VoidCallback? onClose;

  const RemoteKeyboardInput({
    super.key,
    this.onClose,
  });

  @override
  State<RemoteKeyboardInput> createState() => _RemoteKeyboardInputState();
}

class _RemoteKeyboardInputState extends State<RemoteKeyboardInput> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  String _lastSentText = '';

  @override
  void initState() {
    super.initState();
    // Auto-focus to show keyboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged(String newText) {
    final state = RemoteControlState();
    if (!state.isConnected) return;

    // Determine what changed
    if (newText.length > _lastSentText.length) {
      // Text was added - send the new characters
      final addedText = newText.substring(_lastSentText.length);
      state.sendTextCommand(TextCommand.type, text: addedText);
      HapticFeedback.selectionClick();
    } else if (newText.length < _lastSentText.length) {
      // Text was deleted - send backspace for each deleted character
      final deletedCount = _lastSentText.length - newText.length;
      for (var i = 0; i < deletedCount; i++) {
        state.sendTextCommand(TextCommand.backspace);
      }
      HapticFeedback.selectionClick();
    }

    _lastSentText = newText;
  }

  void _clearField() {
    HapticFeedback.mediumImpact();
    RemoteControlState().sendTextCommand(TextCommand.clear);
    _textController.clear();
    _lastSentText = '';
  }

  void _sendEnter() {
    HapticFeedback.mediumImpact();
    // Send select/enter command to submit
    RemoteControlState().sendNavigateCommand(NavigateCommand.select);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.keyboard,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'TV Keyboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 20,
                  ),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            'Type here to send text to TV',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 12),

          // Text input field
          TextField(
            controller: _textController,
            focusNode: _focusNode,
            onChanged: _onTextChanged,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Start typing...',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
              ),
              filled: true,
              fillColor: const Color(0xFF0F172A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              suffixIcon: _textController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 20,
                      ),
                      onPressed: _clearField,
                    )
                  : null,
            ),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendEnter(),
          ),

          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              // Clear button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _clearField,
                  icon: const Icon(Icons.backspace_outlined, size: 18),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: 0.7),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Enter/Submit button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _sendEnter,
                  icon: const Icon(Icons.keyboard_return, size: 18),
                  label: const Text('Enter'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
