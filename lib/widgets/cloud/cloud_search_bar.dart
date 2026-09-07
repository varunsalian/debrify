import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';
import '../tv_text_field.dart';

/// The in-folder "search all files" bar shared by the TorBox and Real-Debrid
/// cloud files screens (G4-5). Moved from `_buildSearchBar`, which was
/// identical in the two hosts apart from the clear button's fill and focus
/// ring — those two colours are now parameters, so the divergence the
/// Real-Debrid host deliberately carries is preserved rather than converged.
class CloudSearchBar extends StatelessWidget {
  const CloudSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.clearFocusNode,
    required this.onChanged,
    required this.onClear,
    required this.clearButtonFill,
    required this.clearButtonFocusRing,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode clearFocusNode;

  /// `_performSearch` on the host.
  final ValueChanged<String> onChanged;

  /// Clears the controller and the host's result list inside its `setState`.
  /// Focus is returned to [focusNode] here, as the origin did.
  final VoidCallback onClear;

  final Color clearButtonFill;
  final Color clearButtonFocusRing;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final hasText = controller.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent wrapper)
              onUpArrow: () => focusNode.unfocus(),
              onDownArrow: () => focusNode.unfocus(),
              onRightArrow: hasText
                  ? () => clearFocusNode.requestFocus()
                  : null,
              decoration: InputDecoration(
                hintText: 'Search all files...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: app.fade(app.core.tx, 0.06),
                border: OutlineInputBorder(
                  borderRadius: app.shape.br(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: onChanged,
              onSubmitted: (_) => focusNode.unfocus(),
            ),
          ),
          // Clear button - separate focusable widget for D-pad navigation
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: clearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;

                  // Select/Enter: clear search
                  if (isActivateKey(key)) {
                    onClear();
                    focusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  // Arrow Left: go back to TextField
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    focusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return Container(
                      decoration: BoxDecoration(
                        color: clearButtonFill,
                        borderRadius: app.shape.br(8),
                        border: isFocused
                            ? Border.all(color: clearButtonFocusRing, width: 2)
                            : null,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          onClear();
                          focusNode.requestFocus();
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
