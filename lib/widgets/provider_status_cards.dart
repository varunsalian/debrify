import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/rd_user.dart';
import '../models/torbox_user.dart';
import '../services/account_service.dart';
import '../services/torbox_account_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/storage_service.dart';
import 'home_focus_controller.dart';

// Callback type for notifier listeners
typedef _VoidCallback = void Function();

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

/// Animated pulsing dot for connected provider status
class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingDot({this.color = const Color(0xFF10B981), this.size = 6});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.5),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact provider status cards for the home screen
class ProviderStatusCards extends StatefulWidget {
  final VoidCallback? onTapRealDebrid;
  final VoidCallback? onTapTorbox;
  final VoidCallback? onTapPikPak;
  final HomeFocusController? focusController;
  final VoidCallback? onRequestFocusAbove;
  final VoidCallback? onRequestFocusBelow;
  final bool isTelevision;

  const ProviderStatusCards({
    super.key,
    this.onTapRealDebrid,
    this.onTapTorbox,
    this.onTapPikPak,
    this.focusController,
    this.onRequestFocusAbove,
    this.onRequestFocusBelow,
    this.isTelevision = false,
  });

  @override
  State<ProviderStatusCards> createState() => _ProviderStatusCardsState();
}

class _ProviderStatusCardsState extends State<ProviderStatusCards> {
  ProviderStatus? _rdStatus;
  ProviderStatus? _torboxStatus;
  ProviderStatus? _pikpakStatus;
  bool _isLoading = true;

  // Focus management for DPAD navigation
  final List<FocusNode> _cardFocusNodes = [];
  final ScrollController _scrollController = ScrollController();

  // Listener callbacks for service notifiers
  late final _VoidCallback _rdListener;
  late final _VoidCallback _torboxListener;
  late final _VoidCallback _pikpakListener;

  @override
  void initState() {
    super.initState();

    // Set up listeners for reactive updates
    _rdListener = () => _onRdStatusChanged();
    _torboxListener = () => _onTorboxStatusChanged();
    _pikpakListener = () => _onPikpakStatusChanged();

    AccountService.userNotifier.addListener(_rdListener);
    TorboxAccountService.userNotifier.addListener(_torboxListener);
    PikPakApiService.instance.authStateNotifier.addListener(_pikpakListener);

    _loadProviderStatuses();
  }

  @override
  void dispose() {
    // Remove notifier listeners
    AccountService.userNotifier.removeListener(_rdListener);
    TorboxAccountService.userNotifier.removeListener(_torboxListener);
    PikPakApiService.instance.authStateNotifier.removeListener(_pikpakListener);

    // Unregister from controller
    widget.focusController?.unregisterSection(HomeSection.providers);
    // Dispose focus nodes
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  // Called when Real-Debrid user state changes
  void _onRdStatusChanged() {
    if (!mounted) return;
    _loadRealDebridStatus().then((_) {
      if (mounted) setState(() {});
    });
  }

  // Called when Torbox user state changes
  void _onTorboxStatusChanged() {
    if (!mounted) return;
    _loadTorboxStatus().then((_) {
      if (mounted) setState(() {});
    });
  }

  // Called when PikPak auth state changes
  void _onPikpakStatusChanged() {
    if (!mounted) return;
    _loadPikPakStatus().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Ensure we have the right number of focus nodes for configured providers
  void _ensureFocusNodes(int count) {
    while (_cardFocusNodes.length < count) {
      _cardFocusNodes
          .add(FocusNode(debugLabel: 'provider_card_${_cardFocusNodes.length}'));
    }
    while (_cardFocusNodes.length > count) {
      _cardFocusNodes.removeLast().dispose();
    }
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

      // Count configured providers
      int configuredCount = 0;
      if (_rdStatus?.isConfigured == true) configuredCount++;
      if (_torboxStatus?.isConfigured == true) configuredCount++;
      if (_pikpakStatus?.isConfigured == true) configuredCount++;

      // Update focus nodes and register with controller
      _ensureFocusNodes(configuredCount);
      widget.focusController?.registerSection(
        HomeSection.providers,
        hasItems: configuredCount > 0,
        focusNodes: _cardFocusNodes,
      );
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
          daysRemaining =
              user.premiumExpiresAt!.difference(DateTime.now()).inDays;
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

    // Build list of configured providers with focus nodes
    final configuredProviders = <Widget>[];
    int focusIndex = 0;

    if (_rdStatus != null && _rdStatus!.isConfigured) {
      configuredProviders.add(
        _buildProviderCard(
          status: _rdStatus!,
          color: const Color(0xFF10B981), // Emerald
          onTap: widget.onTapRealDebrid,
          index: focusIndex,
          focusNode: focusIndex < _cardFocusNodes.length
              ? _cardFocusNodes[focusIndex]
              : null,
        ),
      );
      focusIndex++;
    }
    if (_torboxStatus != null && _torboxStatus!.isConfigured) {
      configuredProviders.add(
        _buildProviderCard(
          status: _torboxStatus!,
          color: const Color(0xFF3B82F6), // Blue
          onTap: widget.onTapTorbox,
          index: focusIndex,
          focusNode: focusIndex < _cardFocusNodes.length
              ? _cardFocusNodes[focusIndex]
              : null,
        ),
      );
      focusIndex++;
    }
    if (_pikpakStatus != null && _pikpakStatus!.isConfigured) {
      configuredProviders.add(
        _buildProviderCard(
          status: _pikpakStatus!,
          color: const Color(0xFFF59E0B), // Amber
          onTap: widget.onTapPikPak,
          index: focusIndex,
          focusNode: focusIndex < _cardFocusNodes.length
              ? _cardFocusNodes[focusIndex]
              : null,
        ),
      );
      focusIndex++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              // Icon container
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.cloud_done_rounded,
                  size: 18,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 12),
              // Title
              Text(
                'Services',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.95),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(width: 10),
              // Connected count badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${configuredProviders.length} active',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Refresh button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _loadProviderStatuses,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Horizontal scrolling provider cards with edge fade
        SizedBox(
          height: 120,
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [0.0, 0.02, 0.98, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              clipBehavior: Clip.none,
              itemCount: configuredProviders.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.only(
                      right:
                          index < configuredProviders.length - 1 ? 12 : 0),
                  child: configuredProviders[index],
                );
              },
            ),
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
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  width: 155,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                      width: 0.5,
                    ),
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
          ),
        ),
      ],
    );
  }

  Widget _buildNoProvidersState() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF6366F1).withValues(alpha: 0.3),
              width: 0.5,
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
        ),
      ),
    );
  }

  Widget _buildProviderCard({
    required ProviderStatus status,
    required Color color,
    VoidCallback? onTap,
    int index = 0,
    FocusNode? focusNode,
  }) {
    // Count configured providers for totalCount
    int configuredCount = 0;
    if (_rdStatus?.isConfigured == true) configuredCount++;
    if (_torboxStatus?.isConfigured == true) configuredCount++;
    if (_pikpakStatus?.isConfigured == true) configuredCount++;

    return _ProviderCardWithFocus(
      onTap: onTap,
      accentColor: color,
      focusNode: focusNode,
      index: index,
      totalCount: configuredCount,
      scrollController: _scrollController,
      onUpPressed: widget.onRequestFocusAbove,
      onDownPressed: widget.onRequestFocusBelow,
      onFocusChanged: (focused, idx) {
        if (focused) {
          widget.focusController
              ?.saveLastFocusedIndex(HomeSection.providers, idx);
        }
      },
      child: (isFocused, isHovered) {
        final isActive = isFocused || isHovered;

        // Note: scale animation is handled by _ProviderCardWithFocus's AnimatedScale
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          width: 155,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 20,
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isActive
                          ? color.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.06),
                      width: isActive ? 2.0 : 0.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: provider icon/name + connection dot
                        Row(
                          children: [
                            // Provider icon (small colored circle with first letter)
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    color,
                                    color.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  status.name[0],
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                status.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Connection status
                            if (status.isConnected)
                              const _PulsingDot(color: Color(0xFF10B981))
                            else
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Email (if available)
                        if (status.email != null)
                          Text(
                            status.email!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        const Spacer(),
                        // Bottom row: PRO badge + days remaining
                        Row(
                          children: [
                            if (status.isPremium)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      color,
                                      color.withValues(alpha: 0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'PRO',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            if (status.daysRemaining != null)
                              Text(
                                '${status.daysRemaining}d left',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
      },
    );
  }
}

/// Focus-aware wrapper for provider cards with DPAD/TV support
class _ProviderCardWithFocus extends StatefulWidget {
  final VoidCallback? onTap;
  final Color accentColor;
  final FocusNode? focusNode;
  final int index;
  final int totalCount;
  final ScrollController? scrollController;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;
  final void Function(bool focused, int index)? onFocusChanged;
  final Widget Function(bool isFocused, bool isHovered) child;

  const _ProviderCardWithFocus({
    required this.onTap,
    required this.accentColor,
    required this.child,
    this.focusNode,
    this.index = 0,
    this.totalCount = 1,
    this.scrollController,
    this.onUpPressed,
    this.onDownPressed,
    this.onFocusChanged,
  });

  @override
  State<_ProviderCardWithFocus> createState() => _ProviderCardWithFocusState();
}

class _ProviderCardWithFocusState extends State<_ProviderCardWithFocus> {
  bool _isFocused = false;
  bool _isHovered = false;
  final GlobalKey _cardKey = GlobalKey();

  void _onFocusChange(bool focused) {
    setState(() => _isFocused = focused);
    widget.onFocusChanged?.call(focused, widget.index);

    // Scroll card into view when focused
    if (focused && widget.scrollController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _cardKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // Select/Enter/GameButtonA - activate the card
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.gameButtonA) {
        widget.onTap?.call();
        return KeyEventResult.handled;
      }

      // Arrow Up - go to previous section
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        widget.onUpPressed?.call();
        return KeyEventResult.handled;
      }

      // Arrow Down - this is the last section, no action needed
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        widget.onDownPressed?.call();
        return KeyEventResult.handled;
      }

      // Arrow Left/Right - let Flutter's directional focus handle it
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        return KeyEventResult.ignored;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: _onFocusChange,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: (_isFocused || _isHovered) ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: KeyedSubtree(
              key: _cardKey,
              child: widget.child(_isFocused, _isHovered),
            ),
          ),
        ),
      ),
    );
  }
}
