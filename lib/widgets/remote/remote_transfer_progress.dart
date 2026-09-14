import 'package:flutter/material.dart';

import '../../services/remote_control/remote_control_state.dart';
import '../../services/remote_control/remote_transfer_activity.dart';

class RemoteTransferProgressPanel extends StatelessWidget {
  const RemoteTransferProgressPanel({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<RemoteTransferActivity?>(
    valueListenable: RemoteControlState().transferActivity.status,
    builder: (context, activity, _) {
      if (activity == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(activity.stage, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: activity.fraction),
            const SizedBox(height: 8),
            const Text(
              'Keep Debrify open on both devices until the transfer finishes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
}
