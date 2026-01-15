import 'package:flutter/material.dart';
import '../models/rd_user.dart';
import '../models/torbox_user.dart';
import '../services/account_service.dart';
import '../services/torbox_account_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/storage_service.dart';

/// Data class to hold provider status info
class ProviderStatus {
  final String name;
  final String? email;
  final bool isConfigured;
  final bool isConnected;
  final bool isPremium;
  final String? planType;
  final DateTime? expiryDate;
  final int? daysRemaining;
  final String? error;
  final Map<String, dynamic>? extraData;

  const ProviderStatus({
    required this.name,
    this.email,
    this.isConfigured = false,
    this.isConnected = false,
    this.isPremium = false,
    this.planType,
    this.expiryDate,
    this.daysRemaining,
    this.error,
    this.extraData,
  });
}

/// Compact provider status cards for the home screen
class ProviderStatusCards extends StatefulWidget {
  final VoidCallback? onTapRealDebrid;
  final VoidCallback? onTapTorbox;
  final VoidCallback? onTapPikPak;

  const ProviderStatusCards({
    super.key,
    this.onTapRealDebrid,
    this.onTapTorbox,
    this.onTapPikPak,
  });

  @override
  State<ProviderStatusCards> createState() => _ProviderStatusCardsState();
}

class _ProviderStatusCardsState extends State<ProviderStatusCards> {
  ProviderStatus? _rdStatus;
  ProviderStatus? _torboxStatus;
  ProviderStatus? _pikpakStatus;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProviderStatuses();
  }

  Future<void> _loadProviderStatuses() async {
    setState(() => _isLoading = true);

    // Load all statuses in parallel
    await Future.wait([
      _loadRealDebridStatus(),
      _loadTorboxStatus(),
      _loadPikPakStatus(),
    ]);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRealDebridStatus() async {
    try {
      final apiKey = await StorageService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        _rdStatus = const ProviderStatus(
          name: 'Real-Debrid',
          isConfigured: false,
        );
        return;
      }

      // Try to get cached user first, otherwise validate
      RDUser? user = AccountService.currentUser;
      if (user == null) {
        await AccountService.validateAndGetUserInfo(apiKey);
        user = AccountService.currentUser;
      }

      if (user != null) {
        final daysLeft = (user.premium / (24 * 60 * 60)).floor();
        _rdStatus = ProviderStatus(
          name: 'Real-Debrid',
          email: user.email,
          isConfigured: true,
          isConnected: true,
          isPremium: user.isPremium,
          planType: user.isPremium ? 'Premium' : 'Free',
          expiryDate: DateTime.tryParse(user.expiration),
          daysRemaining: daysLeft > 0 ? daysLeft : null,
          extraData: {
            'points': user.points,
            'username': user.username,
          },
        );
      } else {
        _rdStatus = const ProviderStatus(
          name: 'Real-Debrid',
          isConfigured: true,
          isConnected: false,
          error: 'Connection failed',
        );
      }
    } catch (e) {
      _rdStatus = ProviderStatus(
        name: 'Real-Debrid',
        isConfigured: true,
        isConnected: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _loadTorboxStatus() async {
    try {
      final apiKey = await StorageService.getTorboxApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        _torboxStatus = const ProviderStatus(
          name: 'Torbox',
          isConfigured: false,
        );
        return;
      }

      // Try to get cached user first, otherwise validate
      TorboxUser? user = TorboxAccountService.currentUser;
      if (user == null) {
        await TorboxAccountService.validateAndGetUserInfo(apiKey);
        user = TorboxAccountService.currentUser;
      }

      if (user != null) {
        int? daysRemaining;
        if (user.premiumExpiresAt != null) {
          daysRemaining = user.premiumExpiresAt!.difference(DateTime.now()).inDays;
          if (daysRemaining < 0) daysRemaining = 0;
        }

        String planName;
        switch (user.plan) {
          case 0:
            planName = 'Free';
            break;
          case 1:
            planName = 'Essential';
            break;
          case 2:
            planName = 'Pro';
            break;
          case 3:
            planName = 'Standard';
            break;
          default:
            planName = 'Plan ${user.plan}';
        }

        _torboxStatus = ProviderStatus(
          name: 'Torbox',
          email: user.email,
          isConfigured: true,
          isConnected: true,
          isPremium: user.hasActiveSubscription,
          planType: planName,
          expiryDate: user.premiumExpiresAt,
          daysRemaining: daysRemaining,
          extraData: {
            'downloaded': user.formattedTotalDownloaded,
            'torrents': user.torrentsDownloaded,
          },
        );
      } else {
        _torboxStatus = const ProviderStatus(
          name: 'Torbox',
          isConfigured: true,
          isConnected: false,
          error: 'Connection failed',
        );
      }
    } catch (e) {
      _torboxStatus = ProviderStatus(
        name: 'Torbox',
        isConfigured: true,
        isConnected: false,
        error: e.toString(),
      );
    }
  }

  Future<void> _loadPikPakStatus() async {
    try {
      final isAuth = await PikPakApiService.instance.isAuthenticated();
      if (!isAuth) {
        _pikpakStatus = const ProviderStatus(
          name: 'PikPak',
          isConfigured: false,
        );
        return;
      }

      final email = await PikPakApiService.instance.getEmail();
      final testOk = await PikPakApiService.instance.testConnection();

      _pikpakStatus = ProviderStatus(
        name: 'PikPak',
        email: email,
        isConfigured: true,
        isConnected: testOk,
        isPremium: true, // PikPak doesn't expose plan info easily
        planType: 'Connected',
        error: testOk ? null : 'Connection failed',
      );
    } catch (e) {
      _pikpakStatus = ProviderStatus(
        name: 'PikPak',
        isConfigured: true,
        isConnected: false,
        error: e.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    // Check if any provider is configured
    final hasAnyProvider = (_rdStatus?.isConfigured ?? false) ||
        (_torboxStatus?.isConfigured ?? false) ||
        (_pikpakStatus?.isConfigured ?? false);

    if (!hasAnyProvider) {
      return _buildNoProvidersState();
    }

    // Build list of configured providers
    final configuredProviders = <Widget>[];
    if (_rdStatus != null && _rdStatus!.isConfigured) {
      configuredProviders.add(
        _buildProviderCard(
          status: _rdStatus!,
          color: const Color(0xFF10B981), // Emerald
          icon: Icons.bolt_rounded,
          onTap: widget.onTapRealDebrid,
        ),
      );
    }
    if (_torboxStatus != null && _torboxStatus!.isConfigured) {
      configuredProviders.add(
        _buildProviderCard(
          status: _torboxStatus!,
          color: const Color(0xFF3B82F6), // Blue
          icon: Icons.inventory_2_rounded,
          onTap: widget.onTapTorbox,
        ),
      );
    }
    if (_pikpakStatus != null && _pikpakStatus!.isConfigured) {
      configuredProviders.add(
        _buildProviderCard(
          status: _pikpakStatus!,
          color: const Color(0xFFF59E0B), // Amber
          icon: Icons.cloud_upload_rounded,
          onTap: widget.onTapPikPak,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.cloud_done_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                'Debrid Services',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: _loadProviderStatuses,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Horizontal scrolling provider cards
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: configuredProviders.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) => configuredProviders[index],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.cloud_done_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                'Debrid Services',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) => Container(
              width: 140,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF6366F1),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoProvidersState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E293B),
            const Color(0xFF1E293B).withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.link_rounded,
              color: Color(0xFF6366F1),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connect a Debrid Service',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add Real-Debrid, Torbox, or PikPak in Settings',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard({
    required ProviderStatus status,
    required Color color,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final bool hasWarning = status.daysRemaining != null && status.daysRemaining! <= 7;
    final bool hasError = status.error != null || !status.isConnected;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140, // Fixed width for horizontal scroll
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1E293B),
              Color.lerp(const Color(0xFF1E293B), color, 0.1)!,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasError
                ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                : hasWarning
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                    : color.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row: Icon + Status indicator
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon,
                    size: 14,
                    color: color,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Status dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasError
                        ? const Color(0xFFEF4444)
                        : hasWarning
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF10B981),
                    boxShadow: [
                      BoxShadow(
                        color: (hasError
                                ? const Color(0xFFEF4444)
                                : hasWarning
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF10B981))
                            .withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Status info
            if (hasError)
              Text(
                status.error ?? 'Disconnected',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else ...[
              // Plan type
              if (status.planType != null)
                Text(
                  status.planType!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              // Days remaining
              if (status.daysRemaining != null) ...[
                const SizedBox(height: 2),
                Text(
                  status.daysRemaining == 1
                      ? '1 day left'
                      : '${status.daysRemaining} days left',
                  style: TextStyle(
                    fontSize: 10,
                    color: hasWarning
                        ? const Color(0xFFF59E0B)
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ] else if (status.isPremium && status.planType != 'Connected')
                Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
