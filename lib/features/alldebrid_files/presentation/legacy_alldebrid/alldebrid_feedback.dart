import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_feedback_state.dart';
import 'package:flutter/material.dart';

typedef AllDebridFeedbackDeps = ({
  AllDebridFeedbackState feedbackState,
  BuildContext Function() context,
  bool Function() mounted,
});

class AllDebridFeedback {
  final AllDebridFeedbackDeps _deps;
  AllDebridFeedback(this._deps);
  AllDebridFeedbackState get _feedback => _deps.feedbackState;

  void showLoading(String message) {
    if (_feedback.loadingDialogOpen || !_deps.mounted()) return;
    _feedback.loadingDialogOpen = true;
    showDialog(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (_) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void dismissLoading() {
    if (!_feedback.loadingDialogOpen) return;
    _feedback.loadingDialogOpen = false;
    if (_deps.mounted()) {
      Navigator.of(_deps.context(), rootNavigator: true).pop();
    }
  }

  void snack(String message, {bool isError = true}) {
    if (!_deps.mounted()) return;
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
