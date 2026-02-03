import 'package:flutter/material.dart';

import '../../services/remote_control/remote_control_state.dart';
import '../../services/remote_control/udp_discovery_service.dart';

/// Dialog result containing the user's choice
class AddonInstallChoice {
  final String target; // 'phone' or 'tv'
  final DiscoveredDevice? device; // The TV device if target is 'tv'

  AddonInstallChoice({required this.target, this.device});
}

/// Dialog for choosing where to install a Stremio addon
class AddonInstallDialog extends StatefulWidget {
  final String manifestUrl;

  const AddonInstallDialog({
    super.key,
    required this.manifestUrl,
  });

  /// Show the dialog and return the user's choice
  static Future<AddonInstallChoice?> show(BuildContext context, String manifestUrl) async {
    return showDialog<AddonInstallChoice>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AddonInstallDialog(manifestUrl: manifestUrl),
    );
  }

  @override
  State<AddonInstallDialog> createState() => _AddonInstallDialogState();
}

class _AddonInstallDialogState extends State<AddonInstallDialog> {
  List<DiscoveredDevice> _devices = [];
  bool _scanning = false;
  UdpDiscoveryService? _discoveryService;

  @override
  void initState() {
    super.initState();
    _devices = List.from(RemoteControlState().discoveredDevices);
    _startScan();
  }

  @override
  void dispose() {
    _discoveryService?.stop();
    super.dispose();
  }

  String _generateDeviceId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    return List.generate(8, (i) => chars[(random + i * 7) % chars.length]).join();
  }

  Future<void> _startScan() async {
    if (_scanning) return;

    setState(() => _scanning = true);

    _discoveryService = UdpDiscoveryService(
      deviceId: _generateDeviceId(),
      isTv: false,
    );
    _discoveryService!.onDevicesUpdated = (devices) {
      if (mounted) {
        setState(() => _devices = devices);
      }
    };

    await _discoveryService!.start();

    await Future.delayed(const Duration(seconds: 5));

    if (mounted) {
      _discoveryService?.stop();
      setState(() => _scanning = false);
    }
  }

  String _extractAddonName() {
    try {
      final uri = Uri.parse(widget.manifestUrl);
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final idx = pathSegments.indexOf('manifest.json');
        if (idx > 0) {
          var name = pathSegments[idx - 1];
          if (name.isNotEmpty) {
            return name[0].toUpperCase() + name.substring(1);
          }
        }
      }
    } catch (_) {}
    return 'Stremio Addon';
  }

  @override
  Widget build(BuildContext context) {
    final addonName = _extractAddonName();

    return Dialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header - more compact
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.extension,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Install Addon',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          addonName,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // This device - compact tile
              _buildCompactTile(
                icon: Icons.smartphone,
                title: 'This device',
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
                onTap: () => Navigator.of(context).pop(
                  AddonInstallChoice(target: 'phone'),
                ),
              ),

              const SizedBox(height: 16),

              // TV section
              Row(
                children: [
                  Text(
                    'SEND TO TV',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  if (_scanning)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Scanning',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    )
                  else
                    GestureDetector(
                      onTap: _startScan,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Rescan',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // TV list or empty state
              if (_devices.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  width: double.infinity,
                  child: Column(
                    children: [
                      Icon(
                        _scanning ? Icons.radar : Icons.tv_off_outlined,
                        size: 28,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _scanning ? 'Looking for TVs...' : 'No TVs found',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...List.generate(_devices.length, (index) {
                  final device = _devices[index];
                  return Padding(
                    padding: EdgeInsets.only(bottom: index < _devices.length - 1 ? 8 : 0),
                    child: _buildCompactTile(
                      icon: Icons.tv,
                      title: device.deviceName,
                      subtitle: device.ip,
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
                      onTap: () => Navigator.of(context).pop(
                        AddonInstallChoice(target: 'tv', device: device),
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 16),

              // Cancel - full width text button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}
