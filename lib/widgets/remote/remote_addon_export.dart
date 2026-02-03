import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/stremio_service.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../services/remote_control/remote_constants.dart';

/// Widget for exporting Stremio addons to connected TV
class RemoteAddonExport extends StatefulWidget {
  final VoidCallback onBack;

  const RemoteAddonExport({
    super.key,
    required this.onBack,
  });

  @override
  State<RemoteAddonExport> createState() => _RemoteAddonExportState();
}

class _RemoteAddonExportState extends State<RemoteAddonExport> {
  List<StremioAddon> _addons = [];
  bool _loading = true;
  final Set<String> _sendingAddons = {};

  @override
  void initState() {
    super.initState();
    _loadAddons();
  }

  Future<void> _loadAddons() async {
    setState(() => _loading = true);
    try {
      final addons = await StremioService.instance.getAddons();
      setState(() {
        _addons = addons;
        _loading = false;
      });
    } catch (e) {
      debugPrint('RemoteAddonExport: Failed to load addons: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _sendAddonToTv(StremioAddon addon) async {
    if (_sendingAddons.contains(addon.manifestUrl)) return;

    setState(() => _sendingAddons.add(addon.manifestUrl));
    HapticFeedback.mediumImpact();

    try {
      RemoteControlState().sendAddonCommand(
        AddonCommand.install,
        manifestUrl: addon.manifestUrl,
      );

      // Show success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent "${addon.name}" to TV'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('RemoteAddonExport: Failed to send addon: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send addon: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingAddons.remove(addon.manifestUrl));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back to menu button
        TextButton.icon(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to menu'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.7),
          ),
        ),

        const SizedBox(height: 16),

        // Title
        Text(
          'Stremio Addons',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'Tap an addon to install it on your TV',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 24),

        // Content
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
          )
        else if (_addons.isEmpty)
          _buildEmptyState()
        else
          ..._addons.map((addon) => _buildAddonTile(addon)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1E293B),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Icon(
                Icons.extension_off,
                size: 36,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No addons installed',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Install addons from the Addons tab first',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddonTile(StremioAddon addon) {
    final isSending = _sendingAddons.contains(addon.manifestUrl);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSending ? null : () => _sendAddonToTv(addon),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                // Addon icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.extension,
                    color: Colors.white,
                    size: 24,
                  ),
                ),

                const SizedBox(width: 16),

                // Addon info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        addon.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (addon.description != null &&
                          addon.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          addon.description!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Send button/indicator
                if (isSending)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.send,
                          color: Color(0xFF6366F1),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Send',
                          style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
