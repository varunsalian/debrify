import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controller/iptv_controller.dart';
import '../data/hardcoded_channels.dart';
import '../data/iptv_client.dart';
import '../data/iptv_scraper.dart';
import '../data/models.dart';
import '../../../../screens/video_player_screen.dart';
import '../../../../models/iptv_playlist.dart';

class IptvPtScreen extends StatefulWidget {
  const IptvPtScreen({super.key});

  @override
  State<IptvPtScreen> createState() => _IptvPtScreenState();
}

class _IptvPtScreenState extends State<IptvPtScreen> {
  late final IptvController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = IptvController();
    _ctrl.init();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _ctrl.view == IptvView.portalList,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _ctrl.back();
      },
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A0F), Color(0xFF0E1428), Color(0xFF06070C)],
          ),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: KeyedSubtree(
              key: ValueKey(_ctrl.view),
              child: _buildView(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildView(BuildContext context) {
    switch (_ctrl.view) {
      case IptvView.portalList:
        return _PortalListView(ctrl: _ctrl);
      case IptvView.sectionPick:
        return _SectionPickView(ctrl: _ctrl);
      case IptvView.browser:
        return _BrowserView(ctrl: _ctrl);
      case IptvView.episodeList:
        return _EpisodeListView(ctrl: _ctrl);
      case IptvView.channelsHub:
        return _ChannelsHubView(ctrl: _ctrl);
      case IptvView.channelResults:
        return _ChannelResultsView(ctrl: _ctrl);
    }
  }
}

class _PtAppBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  const _PtAppBar({
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70, size: 20),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.bebasNeue(
                        color: Colors.white,
                        fontSize: 28,
                        letterSpacing: 1.6)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool subtle;
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.subtle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: subtle
              ? LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.06),
                    Colors.white.withValues(alpha: 0.03),
                  ],
                )
              : const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF00E5FF)],
                ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: subtle ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: busy ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else
                  Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(label,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalListView extends StatelessWidget {
  final IptvController ctrl;
  const _PortalListView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _PtAppBar(
            title: 'IPTV Portals',
            subtitle: ctrl.statusText.isEmpty
                ? '${ctrl.verified.length} verified'
                : ctrl.statusText,
            actions: [
              IconButton(
                tooltip: 'Add portal',
                onPressed: () => _showAddDialog(context),
                icon: const Icon(Icons.add_rounded, color: Color(0xFF00E5FF)),
              ),
              if (ctrl.verified.isNotEmpty)
                IconButton(
                  tooltip: ctrl.editMode ? 'Done' : 'Edit',
                  onPressed: ctrl.toggleEditMode,
                  icon: Icon(
                    ctrl.editMode ? Icons.check_rounded : Icons.edit_rounded,
                    color: ctrl.editMode ? const Color(0xFF00E5FF) : Colors.white70,
                  ),
                ),
            ],
          ),
          if (ctrl.editMode && ctrl.verified.isNotEmpty)
            _buildEditBar(),
          Expanded(
            child: ctrl.verified.isEmpty ? _buildEmpty() : _buildPortalGrid(),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildEditBar() {
    final allSelected = ctrl.selected.length == ctrl.verified.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1565C0).withValues(alpha: 0.15),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: ctrl.toggleSelectAll,
            icon: Icon(
              allSelected ? Icons.deselect : Icons.select_all,
              color: const Color(0xFF00E5FF), size: 18,
            ),
            label: Text(allSelected ? 'Clear' : 'All',
                style: GoogleFonts.poppins(color: const Color(0xFF00E5FF))),
          ),
          const Spacer(),
          Text('${ctrl.selected.length} selected',
              style: GoogleFonts.poppins(color: Colors.white70)),
          const SizedBox(width: 12),
          IconButton(
            onPressed: ctrl.selected.isEmpty ? null : () => ctrl.deleteSelected(),
            icon: Icon(Icons.delete_rounded,
                color: ctrl.selected.isEmpty ? Colors.white24 : const Color(0xFFEF4444)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.satellite_alt_rounded, size: 80, color: Color(0xFF00E5FF)),
            const SizedBox(height: 24),
            Text('No portals yet',
                style: GoogleFonts.bebasNeue(
                    color: Colors.white, fontSize: 36, letterSpacing: 1.6)),
            const SizedBox(height: 8),
            Text(
              ctrl.statusText.isEmpty
                  ? 'Find live Xtream portals,\nor add one manually.'
                  : ctrl.statusText,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white60),
            ),
            const SizedBox(height: 28),
            _PrimaryButton(
              icon: Icons.travel_explore,
              label: 'Find Portals',
              busy: ctrl.isScraping,
              onPressed: ctrl.scrape,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortalGrid() {
    return LayoutBuilder(
      builder: (context, c) {
        final cross = (c.maxWidth ~/ 320).clamp(1, 4);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 120,
          ),
          itemCount: ctrl.verified.length,
          itemBuilder: (_, i) {
            final v = ctrl.verified[i];
            final selected = ctrl.selected.contains(v.key);
            return _PortalCard(
              v: v,
              editMode: ctrl.editMode,
              selected: selected,
              isFavorite: ctrl.isFavoritePortal(v.key),
              onToggleFavorite: () => ctrl.toggleFavoritePortal(v.key),
              onTap: () {
                if (ctrl.editMode) {
                  ctrl.toggleSelect(v.key);
                } else {
                  ctrl.openPortal(v);
                }
              },
              onLongPress: () {
                if (!ctrl.editMode) {
                  ctrl.toggleEditMode();
                  ctrl.toggleSelect(v.key);
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSourcePicker(),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PrimaryButton(
                  icon: Icons.travel_explore,
                  label: 'Scrape',
                  busy: ctrl.isScraping,
                  onPressed: ctrl.scrape,
                ),
                const SizedBox(width: 8),
                if (ctrl.canGetMore)
                  _PrimaryButton(
                    icon: Icons.add_circle_outline,
                    label: 'Get More',
                    subtle: true,
                    onPressed: ctrl.isScraping ? null : ctrl.getMore,
                  ),
                if (ctrl.canGetMore) const SizedBox(width: 8),
                _PrimaryButton(
                  icon: Icons.tv_rounded,
                  label: 'Channels',
                  subtle: true,
                  onPressed: ctrl.openChannelsHub,
                ),
                const SizedBox(width: 8),
                if (ctrl.verified.isNotEmpty)
                  _PrimaryButton(
                    icon: Icons.refresh_rounded,
                    label: 'Re-verify',
                    subtle: true,
                    onPressed: ctrl.runVerification,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcePicker() {
    const items = <(CatalogSource, String, String)>[
      (CatalogSource.best, 'Source 1', 'Best'),
      (CatalogSource.works, 'Source 2', 'Works'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final it in items) ...[
            _SourceChip(
              label: it.$2,
              tag: it.$3,
              selected: ctrl.scrapeSource == it.$1,
              enabled: !ctrl.isScraping,
              onTap: () => ctrl.setScrapeSource(it.$1),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final urlCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AnimatedBuilder(
        animation: ctrl,
        builder: (_, _) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A24),
          title: Text('Add Portal',
              style: GoogleFonts.bebasNeue(
                  color: Colors.white, fontSize: 26, letterSpacing: 1.4)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _input(urlCtrl, 'http://portal.example.com:8080', 'Portal URL'),
                const SizedBox(height: 8),
                _input(userCtrl, 'username', 'Username'),
                const SizedBox(height: 8),
                _input(passCtrl, 'password', 'Password', obscure: true),
                if (ctrl.addError != null) ...[
                  const SizedBox(height: 10),
                  Text(ctrl.addError!,
                      style: GoogleFonts.poppins(
                          color: const Color(0xFFEF4444), fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: ctrl.isAdding
                  ? null
                  : () {
                      ctrl.dismissAddDialog();
                      Navigator.of(ctx).pop();
                    },
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: Colors.white70)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
              onPressed: ctrl.isAdding
                  ? null
                  : () async {
                      await ctrl.addManual(
                        url: urlCtrl.text,
                        username: userCtrl.text,
                        password: passCtrl.text,
                      );
                      if (ctrl.addError == null && ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
              child: ctrl.isAdding
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Add',
                      style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController c, String hint, String label,
      {bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: Colors.white60, fontSize: 12),
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 12),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  final String label;
  final String tag;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _SourceChip({
    required this.label,
    required this.tag,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF00E5FF)],
                  )
                : null,
            color: selected ? null : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.transparent : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                  const SizedBox(width: 6),
                  Text(tag,
                      style: GoogleFonts.poppins(
                          color: selected ? Colors.white : const Color(0xFF00E5FF),
                          fontWeight: FontWeight.w500,
                          fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalCard extends StatelessWidget {
  final VerifiedPortal v;
  final bool editMode;
  final bool selected;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFavorite;
  const _PortalCard({
    required this.v,
    required this.editMode,
    required this.selected,
    required this.isFavorite,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF14213A), Color(0xFF0E1428)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFF00E5FF)
                : Colors.white.withValues(alpha: 0.08),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                if (editMode)
                  Icon(
                    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    color: selected ? const Color(0xFF00E5FF) : Colors.white30,
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1565C0), Color(0xFF00E5FF)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tv_rounded, color: Colors.white, size: 22),
                  ),
                if (!editMode) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(v.name.isEmpty ? v.portal.url : v.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(v.portal.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              color: Colors.white60, fontSize: 11)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _Pill(
                              icon: Icons.event_rounded,
                              label: v.expiry,
                              color: const Color(0xFFA855F7)),
                          const SizedBox(width: 6),
                          _Pill(
                              icon: Icons.people_rounded,
                              label: '${v.activeConnections}/${v.maxConnections}',
                              color: const Color(0xFF22C55E)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!editMode) ...[
                  IconButton(
                    tooltip: 'Copy',
                    onPressed: () {
                      final p = v.portal;
                      Clipboard.setData(ClipboardData(
                          text: '${p.url}:${p.username}:${p.password}'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Copied'),
                            duration: Duration(seconds: 2)),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, color: Colors.white54, size: 20),
                  ),
                  IconButton(
                    tooltip: isFavorite ? 'Unfavorite' : 'Favorite',
                    onPressed: onToggleFavorite,
                    icon: Icon(
                      isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                      color: isFavorite ? const Color(0xFFFACC15) : Colors.white38,
                      size: 22,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Pill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.poppins(
                  color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SectionPickView extends StatelessWidget {
  final IptvController ctrl;
  const _SectionPickView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _PtAppBar(
            title: ctrl.activePortal?.name ?? 'Portal',
            subtitle: ctrl.activePortal?.portal.url,
            onBack: ctrl.back,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) {
                final cross = c.maxWidth >= 600 ? 3 : 1;
                return GridView.count(
                  padding: const EdgeInsets.all(20),
                  crossAxisCount: cross,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: cross == 1 ? 2.6 : 1.1,
                  children: [
                    _SectionTile(
                      icon: Icons.live_tv_rounded,
                      label: 'Live TV',
                      colors: const [Color(0xFFEF4444), Color(0xFF7C2D12)],
                      onTap: () => ctrl.openSection(IptvSection.live),
                    ),
                    _SectionTile(
                      icon: Icons.movie_rounded,
                      label: 'Movies',
                      colors: const [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                      onTap: () => ctrl.openSection(IptvSection.vod),
                    ),
                    _SectionTile(
                      icon: Icons.video_library_rounded,
                      label: 'Series',
                      colors: const [Color(0xFF1565C0), Color(0xFF00E5FF)],
                      onTap: () => ctrl.openSection(IptvSection.series),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;
  const _SectionTile({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          borderRadius: BorderRadius.circular(20),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 56),
                const SizedBox(height: 14),
                Text(label,
                    style: GoogleFonts.bebasNeue(
                        color: Colors.white, fontSize: 28, letterSpacing: 1.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrowserView extends StatefulWidget {
  final IptvController ctrl;
  const _BrowserView({required this.ctrl});

  @override
  State<_BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends State<_BrowserView> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.ctrl.browserSearch;
    if (widget.ctrl.activeSection == IptvSection.live &&
        widget.ctrl.aliveCheckedAt == null &&
        !widget.ctrl.isVerifyingAlive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.ctrl.startAliveCheck();
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  String get _sectionTitle {
    switch (widget.ctrl.activeSection) {
      case IptvSection.live: return 'Live TV';
      case IptvSection.vod: return 'Movies';
      case IptvSection.series: return 'Series';
      default: return 'Browse';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return SafeArea(
      child: Column(
        children: [
          _PtAppBar(
            title: _sectionTitle,
            subtitle: ctrl.activePortal?.name,
            onBack: ctrl.back,
            actions: [
              if (ctrl.activeSection == IptvSection.live)
                IconButton(
                  tooltip: ctrl.isVerifyingAlive ? 'Stop' : 'Re-check alive',
                  onPressed: ctrl.isVerifyingAlive
                      ? ctrl.stopAliveCheck
                      : ctrl.recheckAlive,
                  icon: Icon(
                    ctrl.isVerifyingAlive ? Icons.stop_circle_rounded : Icons.refresh_rounded,
                    color: const Color(0xFF00E5FF),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: ctrl.setBrowserSearch,
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white60),
                hintText: 'Search channels or categories…',
                hintStyle: GoogleFonts.poppins(color: Colors.white30, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
            ),
          ),
          if (ctrl.activeSection == IptvSection.live && ctrl.isVerifyingAlive)
            _buildAliveProgress(ctrl),
          if (ctrl.activeSection == IptvSection.live && !ctrl.isVerifyingAlive && ctrl.aliveCheckedAt != null)
            _buildLiveOnlyToggle(ctrl),
          if (ctrl.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(ctrl.error!,
                  style: GoogleFonts.poppins(color: const Color(0xFFEF4444))),
            ),
          Expanded(
            child: ctrl.isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
                : _buildContent(ctrl),
          ),
        ],
      ),
    );
  }

  Widget _buildAliveProgress(IptvController ctrl) {
    final ratio = ctrl.aliveTotal == 0 ? 0.0 : ctrl.aliveChecked / ctrl.aliveTotal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Checking: ${ctrl.aliveChecked}/${ctrl.aliveTotal} · ${ctrl.aliveCount} alive',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00E5FF)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveOnlyToggle(IptvController ctrl) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Switch(
            value: ctrl.liveOnly,
            activeThumbColor: const Color(0xFF00E5FF),
            onChanged: ctrl.setLiveOnly,
          ),
          const SizedBox(width: 8),
          Text('Show alive only (${ctrl.aliveStreamIds.length})',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildContent(IptvController ctrl) {
    final cats = ctrl.categories;
    final list = _filteredStreams(ctrl);

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: cats.length,
            itemBuilder: (_, i) {
              final c = cats[i];
              final selected = c.id == ctrl.browserSelectedCategoryId;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: ChoiceChip(
                  label: Text(c.name.isEmpty ? 'All' : c.name,
                      style: GoogleFonts.poppins(
                          color: selected ? Colors.black : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  selected: selected,
                  showCheckmark: false,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  selectedColor: const Color(0xFF00E5FF),
                  onSelected: (_) => ctrl.selectBrowserCategory(c.id),
                ),
              );
            },
          ),
        ),
        Expanded(child: _buildStreamGrid(ctrl, list)),
      ],
    );
  }

  List<IptvStream> _filteredStreams(IptvController ctrl) {
    var s = ctrl.browserAllStreams;
    final cat = ctrl.browserSelectedCategoryId;
    final q = ctrl.browserSearch.trim().toLowerCase();

    if (q.isNotEmpty) {
      final catNameById = <String, String>{
        for (final c in ctrl.categories) c.id: c.name.toLowerCase(),
      };
      s = s.where((x) {
        if (x.name.toLowerCase().contains(q)) return true;
        final cn = catNameById[x.categoryId];
        return cn != null && cn.contains(q);
      }).toList();
    } else if (cat != null && cat.isNotEmpty) {
      s = s.where((x) => x.categoryId == cat).toList();
    }

    if (ctrl.activeSection == IptvSection.live && ctrl.liveOnly) {
      s = s.where((x) => ctrl.aliveStreamIds.contains(x.streamId)).toList();
    }
    return s;
  }

  Widget _buildStreamGrid(IptvController ctrl, List<IptvStream> list) {
    if (list.isEmpty) {
      return Center(
        child: Text('No streams in this view',
            style: GoogleFonts.poppins(color: Colors.white60)),
      );
    }
    return LayoutBuilder(
      builder: (_, c) {
        final cross = (c.maxWidth ~/ 180).clamp(2, 8);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.9,
          ),
          itemCount: list.length,
          itemBuilder: (_, i) => _StreamCard(
            stream: list[i],
            ctrl: ctrl,
            onTap: () => _onStreamTap(ctrl, list[i]),
          ),
        );
      },
    );
  }

  void _onStreamTap(IptvController ctrl, IptvStream s) {
    final p = ctrl.activePortal;
    if (p == null) return;
    if (s.kind == 'series') {
      ctrl.openSeries(s);
      return;
    }
    final streams = ctrl.browserAllStreams;
    final channels = <IptvChannel>[];
    var startIndex = 0;
    for (var i = 0; i < streams.length; i++) {
      final st = streams[i];
      final url = IptvClient.streamUrl(p.portal, st);
      if (url.isEmpty) continue;
      channels.add(IptvChannel(
        name: st.name,
        url: url,
        logoUrl: st.icon.isNotEmpty ? st.icon : null,
      ));
      if (st.streamId == s.streamId) startIndex = channels.length - 1;
    }
    if (channels.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: channels[startIndex].url,
          title: s.name,
          showChannelName: true,
          channelName: p.name,
          iptvChannels: channels,
          iptvStartIndex: startIndex,
        ),
      ),
    );
  }
}

class _StreamCard extends StatelessWidget {
  final IptvStream stream;
  final IptvController ctrl;
  final VoidCallback onTap;
  const _StreamCard({
    required this.stream,
    required this.ctrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: stream.icon.isEmpty
                      ? Container(
                          color: Colors.white.withValues(alpha: 0.03),
                          child: const Icon(Icons.tv_rounded, color: Colors.white24, size: 40),
                        )
                      : Image.network(
                          stream.icon,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: Colors.white.withValues(alpha: 0.03),
                            child: const Icon(Icons.tv_rounded, color: Colors.white24, size: 40),
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  stream.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeListView extends StatelessWidget {
  final IptvController ctrl;
  const _EpisodeListView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _PtAppBar(
            title: ctrl.activeSeries?.name ?? 'Episodes',
            subtitle: 'Season ${ctrl.episodes.isNotEmpty ? ctrl.episodes.first.season : ''}',
            onBack: ctrl.back,
          ),
          if (ctrl.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(ctrl.error!, style: GoogleFonts.poppins(color: const Color(0xFFEF4444))),
            ),
          Expanded(
            child: ctrl.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: ctrl.episodes.length,
                    itemBuilder: (_, i) {
                      final ep = ctrl.episodes[i];
                      return ListTile(
                        leading: ep.image.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(ep.image, width: 60, height: 60, fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(Icons.movie, color: Colors.white38)),
                              )
                            : const Icon(Icons.movie, color: Colors.white38),
                        title: Text('S${ep.season}E${ep.episode} - ${ep.title}',
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                        subtitle: ep.plot.isNotEmpty
                            ? Text(ep.plot, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11))
                            : null,
                        onTap: () {
                          final p = ctrl.activePortal;
                          if (p == null) return;
                          final url = IptvClient.episodeUrl(p.portal, ep);
                          _playUrl(context, url, ep.title, p.name);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _playUrl(BuildContext context, String url, String name, String portalName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: url,
          title: name,
          showChannelName: true,
          channelName: portalName,
        ),
      ),
    );
  }
}

class _ChannelsHubView extends StatelessWidget {
  final IptvController ctrl;
  const _ChannelsHubView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _PtAppBar(
            title: 'Channels',
            subtitle: 'Search across all portals',
            onBack: ctrl.back,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) {
                final cross = (c.maxWidth ~/ 160).clamp(2, 6);
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: 100,
                  ),
                  itemCount: HardcodedChannels.all.length,
                  itemBuilder: (_, i) {
                    final ch = HardcodedChannels.all[i];
                    return _ChannelTile(
                      channel: ch,
                      onTap: () => ctrl.openHardcodedChannel(ch),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final HardcodedChannel channel;
  final VoidCallback onTap;
  const _ChannelTile({required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: channel.gradient,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(channel.short,
                    style: GoogleFonts.bebasNeue(
                        color: Colors.white, fontSize: 24, letterSpacing: 1.4)),
                const SizedBox(height: 4),
                Text(channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelResultsView extends StatelessWidget {
  final IptvController ctrl;
  const _ChannelResultsView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _PtAppBar(
            title: ctrl.activeHardcoded?.name ?? 'Results',
            subtitle: ctrl.channelStatus.isEmpty
                ? '${ctrl.channelResults.length} hits'
                : ctrl.channelStatus,
            onBack: ctrl.back,
            actions: [
              if (!ctrl.channelIsRunning)
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: ctrl.searchAgainChannel,
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00E5FF)),
                ),
              if (ctrl.channelResults.isNotEmpty && !ctrl.channelIsRunning)
                IconButton(
                  tooltip: 'Get More',
                  onPressed: ctrl.getMoreChannels,
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00E5FF)),
                ),
              if (ctrl.channelIsRunning)
                IconButton(
                  tooltip: 'Stop',
                  onPressed: ctrl.stopChannelSearch,
                  icon: const Icon(Icons.stop_circle_rounded, color: Color(0xFFEF4444)),
                ),
            ],
          ),
          Expanded(
            child: ctrl.channelResults.isEmpty
                ? Center(
                    child: Text(ctrl.channelStatus.isEmpty ? 'Searching...' : ctrl.channelStatus,
                        style: GoogleFonts.poppins(color: Colors.white60)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: ctrl.channelResults.length,
                    itemBuilder: (_, i) {
                      final hit = ctrl.channelResults[i];
                      return ListTile(
                        leading: hit.stream.icon.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(hit.stream.icon,
                                    width: 48, height: 48, fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(Icons.tv, color: Colors.white38)),
                              )
                            : const Icon(Icons.tv, color: Colors.white38),
                        title: Text(hit.stream.name,
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
                        subtitle: Text(hit.portal.name,
                            style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11)),
                        trailing: IconButton(
                          icon: Icon(
                            ctrl.isFavoriteHit(ctrl.activeHardcoded!.id, hit)
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: ctrl.isFavoriteHit(ctrl.activeHardcoded!.id, hit)
                                ? const Color(0xFFFACC15)
                                : Colors.white38,
                          ),
                          onPressed: () => ctrl.toggleFavoriteHit(hit),
                        ),
                        onTap: () => _playUrl(context, hit.streamUrl, hit.stream.name, hit.portal.name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _playUrl(BuildContext context, String url, String name, String portalName) {
    final hits = ctrl.channelResults;
    final channels = <IptvChannel>[];
    var startIndex = 0;
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      if (h.streamUrl.isEmpty) continue;
      channels.add(IptvChannel(
        name: h.stream.name,
        url: h.streamUrl,
        logoUrl: h.stream.icon.isNotEmpty ? h.stream.icon : null,
      ));
      if (h.streamUrl == url) startIndex = channels.length - 1;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: channels.isNotEmpty ? channels[startIndex].url : url,
          title: name,
          showChannelName: true,
          channelName: portalName,
          iptvChannels: channels.isNotEmpty ? channels : null,
          iptvStartIndex: channels.isNotEmpty ? startIndex : null,
        ),
      ),
    );
  }
}
