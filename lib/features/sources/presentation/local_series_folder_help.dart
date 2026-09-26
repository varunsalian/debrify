import 'package:flutter/material.dart';

Future<void> showLocalSeriesFolderHelp(
  BuildContext context, {
  required String title,
  required String pickedFolderName,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Choose the Show Folder',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select the folder named like "$title".',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            _ExpectationRow(
              label: 'Good',
              value: 'TV Shows/$title/',
              color: Color(0xFF34D399),
            ),
            const SizedBox(height: 6),
            _ExpectationRow(
              label: 'Not',
              value: pickedFolderName.isEmpty
                  ? 'TV Shows/'
                  : '$pickedFolderName/',
              color: Color(0xFFF87171),
            ),
            const SizedBox(height: 12),
            const Text(
              'Episode files inside can still be named S01E01.mkv, S01E02.mkv, and so on.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFF60A5FA))),
          ),
        ],
      );
    },
  );
}

class _ExpectationRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ExpectationRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
