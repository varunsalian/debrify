import 'package:flutter/services.dart';

/// Platform adapter; callers decide whether their originating action is current.
Future<void> writeSystemClipboardText(String text) =>
    Clipboard.setData(ClipboardData(text: text));
