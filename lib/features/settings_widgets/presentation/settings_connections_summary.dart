import 'package:debrify/features/settings_widgets/presentation/settings_connection_card.dart';
import 'package:debrify/features/settings_widgets/presentation/settings_connection_info.dart';
import 'package:debrify/features/settings_widgets/presentation/settings_root_chrome.dart';
import 'package:flutter/material.dart';

class ConnectionsSummary extends StatefulWidget {
  final ConnectionInfo realDebrid;
  final ConnectionInfo torbox;
  final ConnectionInfo premiumize;
  final ConnectionInfo allDebrid;
  final ConnectionInfo pikpak;
  final ConnectionInfo webDav;
  final ConnectionInfo? mediaServers;
  final ConnectionInfo indexerManagers;
  final ConnectionInfo iptv;
  final ConnectionInfo trakt;
  final ConnectionInfo simkl;
  final ConnectionInfo tracking;
  // Null when MDBList is hidden (alpha) — its card + focus node are then omitted.
  final ConnectionInfo? mdblist;
  final FocusNode? firstCardFocusNode;

  const ConnectionsSummary({
    super.key,
    required this.realDebrid,
    required this.torbox,
    required this.premiumize,
    required this.allDebrid,
    required this.pikpak,
    required this.webDav,
    this.mediaServers,
    required this.indexerManagers,
    required this.iptv,
    required this.trakt,
    required this.simkl,
    required this.tracking,
    this.mdblist,
    this.firstCardFocusNode,
  });

  @override
  State<ConnectionsSummary> createState() => _ConnectionsSummaryState();
}

class _ConnectionsSummaryState extends State<ConnectionsSummary> {
  // Focus nodes for grid navigation
  // Layout (wide) — the Reddit card is hidden (source retired), its
  // ConnectionInfo/focus node are kept so nothing else has to change:
  // [realDebrid,  torbox]
  // [premiumize,  allDebrid]
  // [pikpak,      webDav]
  // [indexerManagers, iptv]
  // [tracking policy]      (full width)
  // [trakt,       simkl]
  // [mdblist]     (alone)
  late final FocusNode _torboxFocusNode;
  late final FocusNode _premiumizeFocusNode;
  late final FocusNode _allDebridFocusNode;
  late final FocusNode _pikpakFocusNode;
  late final FocusNode _webDavFocusNode;
  final FocusNode _mediaServersFocusNode = FocusNode(
    debugLabel: 'settings-media-servers',
  );
  late final FocusNode _indexerManagersFocusNode;
  late final FocusNode _iptvFocusNode;
  late final FocusNode _trackingFocusNode;
  late final FocusNode _traktFocusNode;
  late final FocusNode _simklFocusNode;
  late final FocusNode _mdblistFocusNode;

  @override
  void initState() {
    super.initState();
    _torboxFocusNode = FocusNode(debugLabel: 'settings-torbox');
    _premiumizeFocusNode = FocusNode(debugLabel: 'settings-premiumize');
    _allDebridFocusNode = FocusNode(debugLabel: 'settings-alldebrid');
    _pikpakFocusNode = FocusNode(debugLabel: 'settings-pikpak');
    _webDavFocusNode = FocusNode(debugLabel: 'settings-webdav');
    _indexerManagersFocusNode = FocusNode(
      debugLabel: 'settings-indexer-managers',
    );
    _iptvFocusNode = FocusNode(debugLabel: 'settings-iptv');
    _trackingFocusNode = FocusNode(debugLabel: 'settings-tracking');
    _traktFocusNode = FocusNode(debugLabel: 'settings-trakt');
    _simklFocusNode = FocusNode(debugLabel: 'settings-simkl');
    _mdblistFocusNode = FocusNode(debugLabel: 'settings-mdblist');
  }

  @override
  void dispose() {
    _torboxFocusNode.dispose();
    _premiumizeFocusNode.dispose();
    _allDebridFocusNode.dispose();
    _pikpakFocusNode.dispose();
    _webDavFocusNode.dispose();
    _mediaServersFocusNode.dispose();
    _indexerManagersFocusNode.dispose();
    _iptvFocusNode.dispose();
    _trackingFocusNode.dispose();
    _traktFocusNode.dispose();
    _simklFocusNode.dispose();
    _mdblistFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('Connections'),
        LayoutBuilder(
          builder: (context, constraints) {
            final bool wide = constraints.maxWidth > 520;
            final double itemWidth = wide
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
            // Grid layout (wide) — Reddit card hidden, source retired:
            // [RD]         [Torbox]
            // [Premiumize] [AllDebrid]
            // [PikPak]     [WebDAV]
            // [Indexers]   [IPTV]
            // ── Tracking ──
            // [cross-service policy]
            // ── Tracker services ──
            // [Trakt]       [Simkl]
            // [MDBList]
            //
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // Row 1: Real Debrid (left), Torbox (right)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.realDebrid,
                        focusNode: widget.firstCardFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _torboxFocusNode : null,
                        downNeighbor: wide
                            ? _premiumizeFocusNode
                            : _torboxFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.torbox,
                        focusNode: _torboxFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? widget.firstCardFocusNode : null,
                        upNeighbor: wide ? null : widget.firstCardFocusNode,
                        downNeighbor: wide
                            ? _allDebridFocusNode
                            : _premiumizeFocusNode,
                      ),
                    ),
                    // Row 2: Premiumize (left), AllDebrid (right)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.premiumize,
                        focusNode: _premiumizeFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _allDebridFocusNode : null,
                        upNeighbor: wide
                            ? widget.firstCardFocusNode
                            : _torboxFocusNode,
                        downNeighbor: wide
                            ? _pikpakFocusNode
                            : _allDebridFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.allDebrid,
                        focusNode: _allDebridFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _premiumizeFocusNode : null,
                        upNeighbor: wide
                            ? _torboxFocusNode
                            : _premiumizeFocusNode,
                        downNeighbor: wide
                            ? _webDavFocusNode
                            : _pikpakFocusNode,
                      ),
                    ),
                    // Row 3: PikPak (left), WebDAV (right)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.pikpak,
                        focusNode: _pikpakFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _webDavFocusNode : null,
                        upNeighbor: wide
                            ? _premiumizeFocusNode
                            : _allDebridFocusNode,
                        downNeighbor: wide
                            ? _indexerManagersFocusNode
                            : _webDavFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.webDav,
                        focusNode: _webDavFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _pikpakFocusNode : null,
                        upNeighbor: wide
                            ? _allDebridFocusNode
                            : _pikpakFocusNode,
                        downNeighbor: wide
                            ? _iptvFocusNode
                            : _indexerManagersFocusNode,
                      ),
                    ),
                    // Row 4: Indexer managers (left), IPTV (right).
                    // (The retired Reddit source's card, params and focus
                    // node were removed with its orphaned settings page.)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.indexerManagers,
                        focusNode: _indexerManagersFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _iptvFocusNode : null,
                        upNeighbor: wide ? _pikpakFocusNode : _webDavFocusNode,
                        downNeighbor: wide
                            ? (widget.mediaServers != null
                                  ? _mediaServersFocusNode
                                  : _trackingFocusNode)
                            : _iptvFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.iptv,
                        focusNode: _iptvFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _indexerManagersFocusNode : null,
                        upNeighbor: wide
                            ? _webDavFocusNode
                            : _indexerManagersFocusNode,
                        downNeighbor: widget.mediaServers != null
                            ? _mediaServersFocusNode
                            : _trackingFocusNode,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                if (widget.mediaServers != null) ...[
                  ConnectionCard(
                    info: widget.mediaServers!,
                    focusNode: _mediaServersFocusNode,
                    isLeftColumn: true,
                    upNeighbor: _iptvFocusNode,
                    downNeighbor: _trackingFocusNode,
                  ),
                  const SizedBox(height: 22),
                ],
                const SettingsSectionLabel('Tracking'),
                SizedBox(
                  width: constraints.maxWidth,
                  child: ConnectionCard(
                    info: widget.tracking,
                    focusNode: _trackingFocusNode,
                    isLeftColumn: true,
                    upNeighbor: widget.mediaServers != null
                        ? _mediaServersFocusNode
                        : wide
                        ? _indexerManagersFocusNode
                        : _iptvFocusNode,
                    downNeighbor: _traktFocusNode,
                  ),
                ),
                const SizedBox(height: 22),
                const SettingsSectionLabel('Tracker services'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // Row 1: Trakt (left), Simkl (right).
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.trakt,
                        focusNode: _traktFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _simklFocusNode : null,
                        upNeighbor: _trackingFocusNode,
                        downNeighbor: wide && widget.mdblist != null
                            ? _mdblistFocusNode
                            : _simklFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.simkl,
                        focusNode: _simklFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _traktFocusNode : null,
                        upNeighbor: wide ? _trackingFocusNode : _traktFocusNode,
                        downNeighbor: !wide && widget.mdblist != null
                            ? _mdblistFocusNode
                            : null,
                      ),
                    ),
                    // Row 2: MDBList (left, when enabled).
                    if (widget.mdblist != null)
                      SizedBox(
                        width: itemWidth,
                        child: ConnectionCard(
                          info: widget.mdblist!,
                          focusNode: _mdblistFocusNode,
                          isLeftColumn: true,
                          upNeighbor: wide ? _traktFocusNode : _simklFocusNode,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
