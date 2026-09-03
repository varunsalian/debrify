import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/engine/local_engine_storage.dart';
import '../../services/iptv_transfer_payload.dart';
import '../../services/stream_badges_service.dart';
import '../../services/remote_control/remote_chunked_send.dart';
import '../../services/remote_control/remote_constants.dart';
import '../../services/remote_control/remote_control_state.dart';
import '../../services/remote_control/remote_session.dart';
import '../../services/remote_control/remote_transfer_diagnostics.dart';
import 'remote_pairing_dialog.dart';
import '../../services/storage_service.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../services/stremio_service.dart';
import '../../services/profiles/profile_async_authorization.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/profile_database_snapshot.dart';
import '../../services/profiles/profile_package_service.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/profiles/connection_resource_service.dart';
import '../../services/profiles/device_key_provider.dart';
import '../../services/profiles/portable_profile_package.dart';
import '../../models/profiles/profile_policy.dart';

/// One-click "Transfer Everything" flow. Pushes all configured services
/// (debrid keys, Trakt/Simkl sessions, search engines, PikPak, WebDAV,
/// Jackett/Prowlarr, IPTV providers + favorites + lists, stream badge
/// rulesets, and installed Stremio addons) from this device to the currently
/// connected receiver.
class RemoteTransferAll extends StatefulWidget {
  final VoidCallback onBack;

  const RemoteTransferAll({super.key, required this.onBack});

  @override
  State<RemoteTransferAll> createState() => _RemoteTransferAllState();
}

enum _ItemStatus { pending, sending, success, failure, skipped }

class _TransferItem {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  _ItemStatus status;

  _TransferItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
  }) : status = _ItemStatus.pending;
}

class _RemoteTransferAllState extends State<RemoteTransferAll> {
  late final RemoteControlState _remoteState;
  int _eligibilityCheck = 0;
  bool _loading = true;
  bool _transferring = false;

  /// The credential gate runs BEFORE any item is sent and can take several
  /// seconds against a TV that never answers the handshake (an old build).
  /// Without this the button sits inert for that whole window and the
  /// transfer reads as broken — the refusal dialog only lands afterwards.
  bool _connecting = false;
  bool _done = false;

  /// Admin-only: send the complete profile graph (profiles, connections,
  /// PINs, portable files, and durable library state) instead of merging
  /// items into the TV's current profile.
  bool _canSendProfileGraph = false;
  bool _includeProfiles = false;

  String? _traktUsername;
  String? _simklUsername;
  String? _mdblistUsername;
  int _engineCount = 0;
  int _webDavCount = 0;
  int _indexerManagerCount = 0;
  int _iptvPlaylistCount = 0;
  int _iptvFavoriteCount = 0;
  int _iptvListCount = 0;
  int _iptvListChannelCount = 0;
  int _iptvFileImported = 0;
  int _streamBadgeCount = 0;

  final _pikpakPasswordController = TextEditingController();
  bool _showPikpakPassword = false;

  final List<_TransferItem> _items = [];

  @override
  void initState() {
    super.initState();
    _remoteState = RemoteControlState();
    _remoteState.addListener(_handleRemoteStateChanged);
    _loadBundle();
  }

  @override
  void dispose() {
    _remoteState.removeListener(_handleRemoteStateChanged);
    _pikpakPasswordController.dispose();
    super.dispose();
  }

  void _handleRemoteStateChanged() {
    final check = ++_eligibilityCheck;
    unawaited(() async {
      final eligible = await _profileGraphEligible();
      if (!mounted || check != _eligibilityCheck) return;
      setState(() {
        _canSendProfileGraph = eligible;
        if (!eligible && !_connecting && !_transferring) {
          _includeProfiles = false;
        }
      });
    }());
  }

  Future<void> _loadBundle() async {
    setState(() => _loading = true);

    try {
      final realDebridApiKey = await StorageService.getApiKey(
        forRemoteTransfer: true,
      );
      final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
      final hasRd = (realDebridApiKey?.isNotEmpty ?? false) && rdEnabled;

      final torboxApiKey = await StorageService.getTorboxApiKey(
        forRemoteTransfer: true,
      );
      final tbEnabled = await StorageService.getTorboxIntegrationEnabled();
      final hasTb = (torboxApiKey?.isNotEmpty ?? false) && tbEnabled;

      final premiumizeApiKey = await StorageService.getPremiumizeApiKey(
        forRemoteTransfer: true,
      );
      final pmEnabled = await StorageService.getPremiumizeIntegrationEnabled();
      final hasPm = (premiumizeApiKey?.isNotEmpty ?? false) && pmEnabled;

      final allDebridApiKey = await StorageService.getAllDebridApiKey(
        forRemoteTransfer: true,
      );
      final adEnabled = await StorageService.getAllDebridIntegrationEnabled();
      final hasAd = (allDebridApiKey?.isNotEmpty ?? false) && adEnabled;

      final pikpakEmail = await StorageService.getPikPakEmail(
        forRemoteTransfer: true,
      );
      final ppEnabled = await StorageService.getPikPakEnabled();
      final hasPp = (pikpakEmail?.isNotEmpty ?? false) && ppEnabled;

      final traktAccessToken = await StorageService.getTraktAccessToken(
        forRemoteTransfer: true,
      );
      final traktRefreshToken = await StorageService.getTraktRefreshToken(
        forRemoteTransfer: true,
      );
      _traktUsername = await StorageService.getTraktUsername();
      final hasTrakt =
          (traktAccessToken?.isNotEmpty ?? false) &&
          (traktRefreshToken?.isNotEmpty ?? false);

      final simklAccessToken = await StorageService.getSimklAccessToken(
        forRemoteTransfer: true,
      );
      _simklUsername = await StorageService.getSimklUsername();
      final hasSimkl = simklAccessToken?.isNotEmpty ?? false;

      final mdblistApiKey = kMdblistEnabled
          ? await StorageService.getMdblistApiKey(forRemoteTransfer: true)
          : null;
      _mdblistUsername = await StorageService.getMdblistUsername();
      final hasMdblist = mdblistApiKey?.isNotEmpty ?? false;

      await LocalEngineStorage.instance.initialize();
      final engineIds = await LocalEngineStorage.instance
          .getImportedEngineIds();
      _engineCount = engineIds.length;
      final hasEngines = _engineCount > 0;

      var addons = <StremioAddon>[];
      try {
        addons = await StremioService.instance.getAddons(
          forRemoteTransfer: true,
        );
      } catch (_) {
        debugPrint('RemoteTransferAll: addon inventory failed');
      }

      try {
        final servers = await StorageService.getWebDavServers(
          forSettings: false,
          forRemoteTransfer: true,
        );
        _webDavCount = servers.length;
      } catch (_) {
        debugPrint('RemoteTransferAll: WebDAV inventory failed');
        _webDavCount = 0;
      }

      try {
        final managers = await StorageService.getIndexerManagerConfigs(
          forSettings: false,
          forRemoteTransfer: true,
        );
        _indexerManagerCount = managers.length;
      } catch (_) {
        debugPrint('RemoteTransferAll: indexer inventory failed');
        _indexerManagerCount = 0;
      }
      try {
        final playlists = await IptvTransferPayload.buildPlaylists(
          forRemoteTransfer: true,
        );
        final favorites = await IptvTransferPayload.buildFavorites(
          forRemoteTransfer: true,
        );
        final lists = await IptvTransferPayload.buildCustomLists(
          forRemoteTransfer: true,
        );
        _iptvPlaylistCount = playlists.length;
        _iptvFavoriteCount = favorites.length;
        _iptvListCount = lists.length;
        _iptvListChannelCount = IptvTransferPayload.countListChannels(lists);
        _iptvFileImported =
            (await IptvTransferPayload.countPlaylists()).fileImported;
      } catch (_) {
        debugPrint('RemoteTransferAll: IPTV inventory failed');
        _iptvPlaylistCount = 0;
        _iptvFavoriteCount = 0;
        _iptvListCount = 0;
        _iptvListChannelCount = 0;
      }

      try {
        _streamBadgeCount =
            (await StreamBadgesService.instance.getSources()).length;
      } catch (_) {
        debugPrint('RemoteTransferAll: stream badge inventory failed');
        _streamBadgeCount = 0;
      }

      final hasWebDav = _webDavCount > 0;
      final hasIndexers = _indexerManagerCount > 0;

      final items = <_TransferItem>[];
      if (hasRd) {
        items.add(
          _TransferItem(
            key: ConfigCommand.realDebrid,
            label: 'Real-Debrid',
            icon: Icons.speed,
            color: const Color(0xFF10B981),
          ),
        );
      }
      if (hasTb) {
        items.add(
          _TransferItem(
            key: ConfigCommand.torbox,
            label: 'Torbox',
            icon: Icons.inventory_2,
            color: const Color(0xFFF59E0B),
          ),
        );
      }
      if (hasPm) {
        items.add(
          _TransferItem(
            key: ConfigCommand.premiumize,
            label: 'Premiumize',
            icon: Icons.workspace_premium_rounded,
            color: const Color(0xFFFB923C),
          ),
        );
      }
      if (hasAd) {
        items.add(
          _TransferItem(
            key: ConfigCommand.allDebrid,
            label: 'AllDebrid',
            icon: Icons.all_inclusive_rounded,
            color: const Color(0xFF26A69A),
          ),
        );
      }
      if (hasPp) {
        items.add(
          _TransferItem(
            key: ConfigCommand.pikpak,
            label: 'PikPak',
            icon: Icons.cloud,
            color: const Color(0xFF3B82F6),
          ),
        );
      }
      if (hasTrakt) {
        items.add(
          _TransferItem(
            key: ConfigCommand.trakt,
            label: _traktUsername != null
                ? 'Trakt (${_traktUsername!})'
                : 'Trakt',
            icon: Icons.history_rounded,
            color: const Color(0xFFED1C24),
          ),
        );
      }
      if (hasSimkl) {
        items.add(
          _TransferItem(
            key: ConfigCommand.simkl,
            label: _simklUsername != null
                ? 'Simkl (${_simklUsername!})'
                : 'Simkl',
            icon: Icons.movie_filter_rounded,
            color: const Color(0xFF22D3EE),
          ),
        );
      }
      if (hasMdblist) {
        items.add(
          _TransferItem(
            key: ConfigCommand.mdblist,
            label: _mdblistUsername != null
                ? 'MDBList (${_mdblistUsername!})'
                : 'MDBList',
            icon: Icons.list_alt_rounded,
            color: const Color(0xFF8B5CF6),
          ),
        );
      }
      items.add(
        _TransferItem(
          key: ConfigCommand.trackingPreferences,
          label: 'Tracking preferences',
          icon: Icons.sync_alt_rounded,
          color: const Color(0xFF38BDF8),
        ),
      );
      if (hasEngines) {
        items.add(
          _TransferItem(
            key: ConfigCommand.searchEngines,
            label: 'Search Engines ($_engineCount)',
            icon: Icons.search,
            color: const Color(0xFF8B5CF6),
          ),
        );
      }
      if (hasWebDav) {
        items.add(
          _TransferItem(
            key: ConfigCommand.webDav,
            label: 'WebDAV ($_webDavCount)',
            icon: Icons.dns_rounded,
            color: const Color(0xFF0EA5E9),
          ),
        );
      }
      if (hasIndexers) {
        items.add(
          _TransferItem(
            key: ConfigCommand.indexerManagers,
            label: 'Jackett/Prowlarr ($_indexerManagerCount)',
            icon: Icons.manage_search_rounded,
            color: const Color(0xFFEAB308),
          ),
        );
      }
      // IPTV in dependency order: a membership names the provider it came
      // from, so the provider has to land first.
      if (_iptvPlaylistCount > 0) {
        items.add(
          _TransferItem(
            key: ConfigCommand.iptvPlaylists,
            label: 'IPTV providers ($_iptvPlaylistCount)',
            icon: Icons.live_tv_rounded,
            color: const Color(0xFF14B8A6),
          ),
        );
      }
      if (_iptvFavoriteCount > 0) {
        items.add(
          _TransferItem(
            key: ConfigCommand.iptvFavorites,
            label: 'IPTV favorites ($_iptvFavoriteCount)',
            icon: Icons.star_rounded,
            color: const Color(0xFFF472B6),
          ),
        );
      }
      if (_iptvListCount > 0) {
        items.add(
          _TransferItem(
            key: ConfigCommand.iptvLists,
            label:
                'IPTV lists ($_iptvListCount, '
                '$_iptvListChannelCount channels)',
            icon: Icons.playlist_play_rounded,
            color: const Color(0xFFA78BFA),
          ),
        );
      }
      if (_streamBadgeCount > 0) {
        items.add(
          _TransferItem(
            key: ConfigCommand.streamBadges,
            label:
                'Stream badges ($_streamBadgeCount '
                'ruleset${_streamBadgeCount == 1 ? '' : 's'})',
            icon: Icons.sell_rounded,
            color: const Color(0xFFFBBF24),
          ),
        );
      }
      for (final addon in addons) {
        items.add(
          _TransferItem(
            key: 'addon:${addon.connectionResourceId ?? addon.id}',
            label: 'Addon · ${addon.name}',
            icon: Icons.extension,
            color: const Color(0xFF6366F1),
          ),
        );
      }

      final canSendProfileGraph = await _profileGraphEligible();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _canSendProfileGraph = canSendProfileGraph;
        _loading = false;
      });
    } catch (_) {
      debugPrint('RemoteTransferAll: setup inventory failed');
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasPikpak => _items.any((i) => i.key == ConfigCommand.pikpak);

  bool get _canStart {
    if (_transferring || _connecting || _done) return false;
    // A graph send supersedes the item list, PikPak password included —
    // the package carries the sealed secret store, not re-entered passwords.
    if (_includeProfiles) return true;
    if (_items.isEmpty) return false;
    if (_hasPikpak && _pikpakPasswordController.text.isEmpty) return false;
    return true;
  }

  Future<bool> _profileGraphEligible() async {
    try {
      final target = _remoteState.connectedDevice;
      if (target == null || !target.maySupportComprehensiveProfileGraph) {
        return false;
      }
      if (!ProfileRuntime.isInitialized || !ProfileRuntime.isProfileCommitted) {
        return false;
      }
      final registry = ProfileBootstrap.registry;
      final authorization = await ProfileAuthorizationContext.capture(registry);
      final actor = await authorization.validate(registry);
      return actor.role == UserProfileRole.admin &&
          actor.allows(ProfileFeature.manageProfiles) &&
          actor.allows(ProfileFeature.backupRestore);
    } catch (_) {
      return false;
    }
  }

  Future<void> _start() async {
    final state = _remoteState;
    final target = state.connectedDevice;
    if (target == null) {
      _toast('Not connected to a device', error: true);
      return;
    }
    final sendProfiles = _includeProfiles;
    if (sendProfiles) {
      RemoteTransferDiagnostics.record(
        'sender_gate_start',
        fields: <String, Object?>{
          'advertisedKnown': target.protocolVersionKnown,
          'advertisedProtocol': target.protoVersion,
        },
      );
    }
    if (sendProfiles &&
        target.protocolVersionKnown &&
        !target.supportsComprehensiveProfileGraph) {
      RemoteTransferDiagnostics.record(
        'sender_gate_rejected_advertised_protocol',
        fields: <String, Object?>{'protocol': target.protoVersion},
      );
      setState(() => _includeProfiles = false);
      _toast(
        'Update the receiving TV before sending all profiles',
        error: true,
      );
      return;
    }

    // Credential gate: encrypted session + pairing code (or remembered
    // pairing). Old-version TVs are refused with an "update the TV" dialog —
    // there is no plaintext credential path anymore.
    // No overall deadline here on purpose: every step inside the gate is
    // individually bounded (6s handshake probe, 120s pairing-code entry), and
    // a flat ceiling would abort a first-time pairing while the user is still
    // typing the code the TV is showing. The spinner covers the wait; the
    // gate itself owns telling the user what went wrong.
    setState(() => _connecting = true);
    final RemoteSession? session;
    try {
      session = await ensureAuthorizedSession(context, state, target);
    } catch (error) {
      if (sendProfiles) {
        RemoteTransferDiagnostics.record(
          'sender_gate_exception',
          fields: <String, Object?>{'errorType': error.runtimeType},
        );
      }
      rethrow;
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
    if (session == null || !mounted) {
      if (sendProfiles) {
        RemoteTransferDiagnostics.record(
          'sender_gate_stopped',
          fields: <String, Object?>{
            'sessionReady': session != null,
            'screenMounted': mounted,
          },
        );
      }
      return;
    }
    if (sendProfiles) {
      RemoteTransferDiagnostics.record(
        'sender_gate_ready',
        fields: <String, Object?>{
          'peerProtocol': session.peerProtocolVersion,
          'authorized': session.authorized,
        },
      );
    }

    // Manual/VPN targets have no discovery record. The authenticated
    // handshake carries the peer's real capability version, so gate v5 only
    // after that probe instead of treating the default v1 placeholder as an
    // instruction to hide/refuse the feature.
    if (sendProfiles &&
        session.peerProtocolVersion <
            kComprehensiveProfileGraphProtocolVersion) {
      RemoteTransferDiagnostics.record(
        'sender_gate_rejected_peer_protocol',
        fields: <String, Object?>{'peerProtocol': session.peerProtocolVersion},
      );
      setState(() => _includeProfiles = false);
      _toast(
        'Update the receiving TV before sending all profiles',
        error: true,
      );
      return;
    }

    if (sendProfiles) {
      await _startProfileGraph(state, target.ip);
      return;
    }

    setState(() {
      _transferring = true;
      _done = false;
    });
    HapticFeedback.mediumImpact();

    int success = 0;
    int failure = 0;
    final deliveredCommands = <String>[];
    final supportsApplicationResult = target.supportsRemoteTransferResult;
    final requestId = createRemoteTransferRequestId();

    if (supportsApplicationResult &&
        !await beginRemoteTransfer(state, target.ip, requestId: requestId)) {
      if (!mounted) return;
      setState(() => _transferring = false);
      _toast('The TV refused to start the transfer', error: true);
      return;
    }

    for (final item in _items) {
      if (!mounted) return;
      setState(() => item.status = _ItemStatus.sending);

      bool ok = false;
      try {
        final authorization = await ProfileAsyncAuthorization.capture(
          ProfileFeature.remoteTransfer,
        );
        Future<bool> sendItem() async {
          if (item.key.startsWith('addon:')) {
            final resourceId = item.key.substring('addon:'.length);
            final currentAddons = await StremioService.instance.getAddons(
              forRemoteTransfer: true,
            );
            StremioAddon? authorizedAddon;
            for (final addon in currentAddons) {
              if ((addon.connectionResourceId ?? addon.id) == resourceId) {
                authorizedAddon = addon;
                break;
              }
            }
            return authorizedAddon != null &&
                await state.sendAddonCommandToDevice(
                  AddonCommand.install,
                  target.ip,
                  manifestUrl: supportsApplicationResult
                      ? remoteTransferItemBody(
                          requestId: requestId,
                          payload: authorizedAddon.manifestUrl,
                        )
                      : authorizedAddon.manifestUrl,
                );
          }
          return _sendConfigItem(
            state,
            target.ip,
            item.key,
            transferRequestId: supportsApplicationResult ? requestId : null,
          );
        }

        ok = authorization == null
            ? await sendItem()
            : await authorization.runIfCurrentAsOutbound(sendItem);
      } catch (_) {
        debugPrint('RemoteTransferAll: setup item send failed');
        ok = false;
      }

      if (!mounted) return;
      setState(() {
        item.status = ok ? _ItemStatus.success : _ItemStatus.failure;
      });
      if (ok) {
        success++;
        deliveredCommands.add(
          item.key.startsWith('addon:') ? RemoteAction.addon : item.key,
        );
      } else {
        failure++;
      }

      await Future.delayed(const Duration(milliseconds: 250));
    }

    ({bool ok, String message})? applicationResult;
    if (success > 0) {
      await Future.delayed(const Duration(milliseconds: 400));
      final resultCompleter = Completer<({bool ok, String message})>();
      StreamSubscription<({String requestId, bool ok, String message})>?
      resultSubscription;
      if (supportsApplicationResult) {
        resultSubscription = state.remoteTransferResults.stream.listen((
          result,
        ) {
          if (result.requestId == requestId && !resultCompleter.isCompleted) {
            resultCompleter.complete((ok: result.ok, message: result.message));
          }
        });
      }
      try {
        final completed = supportsApplicationResult
            ? await sendRemoteTransferCompletion(
                state,
                target.ip,
                requestId: requestId,
                expectedCommands: deliveredCommands,
              )
            : await state.sendConfigCommandToDevice(
                ConfigCommand.complete,
                target.ip,
              );
        if (!completed) {
          applicationResult = (
            ok: false,
            message: 'The TV refused the transfer completion',
          );
        } else if (supportsApplicationResult) {
          applicationResult = await resultCompleter.future.timeout(
            const Duration(minutes: 3),
            onTimeout: () =>
                (ok: false, message: 'No application result received from TV'),
          );
        }
      } finally {
        await resultSubscription?.cancel();
      }
    }

    if (!mounted) return;
    setState(() {
      _transferring = false;
      _done = applicationResult?.ok ?? true;
    });

    final finalApplicationResult = applicationResult;
    if (finalApplicationResult != null && !finalApplicationResult.ok) {
      _toast(finalApplicationResult.message, error: true);
    } else if (failure == 0) {
      _toast(
        target.supportsRemoteTransferResult
            ? 'Applied $success item${success == 1 ? '' : 's'} on TV'
            : 'Delivered $success item${success == 1 ? '' : 's'} — confirm on TV',
        warning: !target.supportsRemoteTransferResult,
      );
    } else if (success == 0) {
      _toast('Transfer failed', error: true);
    } else {
      _toast(
        '${target.supportsRemoteTransferResult ? 'Applied' : 'Delivered'} '
        '$success, $failure failed',
        warning: true,
      );
    }
  }

  /// Sends the complete profile graph as one atomic payload — the file
  /// restore's package over the sealed session, no passphrase step. The TV
  /// confirms on-screen before importing, so success here means DELIVERED,
  /// not yet applied.
  Future<void> _startProfileGraph(
    RemoteControlState state,
    String targetIp,
  ) async {
    setState(() {
      _transferring = true;
      _done = false;
    });
    HapticFeedback.mediumImpact();
    final random = Random.secure();
    final requestId = base64UrlEncode(
      List<int>.generate(18, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
    final trace = RemoteTransferDiagnostics.traceToken(requestId);
    final startedAt = Stopwatch()..start();
    var phase = 'initialize';
    var cancelled = false;
    RemoteTransferDiagnostics.record(
      'sender_graph_start',
      fields: <String, Object?>{'trace': trace},
    );
    // Listen before the first byte is sent. An onboarding receiver can reject
    // or finish immediately after the final UDP chunk, and this is a broadcast
    // stream: subscribing after sendConfigPayloadToDevice returns loses that
    // result and leaves the phone apparently spinning until the timeout.
    final resultCompleter = Completer<({bool ok, String message})>();
    final resultSubscription = state.profileGraphResults.stream.listen((
      result,
    ) {
      if (profileGraphResultMatchesRequest(
            requestId: requestId,
            resultRequestId: result.requestId,
          ) &&
          !resultCompleter.isCompleted) {
        RemoteTransferDiagnostics.record(
          'sender_result_received',
          fields: <String, Object?>{'trace': trace, 'ok': result.ok},
        );
        resultCompleter.complete((ok: result.ok, message: result.message));
      }
    });
    var ok = false;
    try {
      Future<bool> sendGraph() async {
        PortableProfilePackage tagRequest(PortableProfilePackage package) {
          return PortableProfilePackage(
            sourceVersion: package.sourceVersion,
            mode: package.mode,
            createdAt: package.createdAt,
            profiles: package.profiles,
            resources: package.resources,
            sections: package.sections,
            omissions: <String, dynamic>{
              ...package.omissions,
              kProfileGraphRequestIdOmission: requestId,
            },
          );
        }

        final registry = ProfileBootstrap.registry;
        final authorization = await ProfileAuthorizationContext.capture(
          registry,
        );
        final service = ProfilePackageService(
          registry: registry,
          resources: ConnectionResourceService(
            registry: registry,
            cipher: DeviceKeyProvider.cipher,
          ),
        );
        Future<bool> confirmDebrifyTvOmission(
          PortableProfilePackage candidate,
        ) async {
          final omission = DebrifyTvBackupOmission.fromOmissions(
            candidate.omissions,
          );
          if (omission == null || omission.isEmpty) {
            return true;
          }
          phase = 'confirm_debrify_tv_omission';
          RemoteTransferDiagnostics.record(
            'sender_compaction_confirmation_shown',
            fields: <String, Object?>{
              'trace': trace,
              'channels': omission.channels,
              'savedHashes': omission.savedHashes,
              'profiles': omission.profilesAffected,
            },
          );
          final accepted = await _confirmProfileGraphDebrifyTvOmission(
            omission,
          );
          if (!accepted) {
            cancelled = true;
            RemoteTransferDiagnostics.record(
              'sender_compaction_confirmation_declined',
              fields: <String, Object?>{'trace': trace},
            );
            return false;
          }
          return true;
        }

        phase = 'export_full';
        RemoteTransferDiagnostics.record(
          'sender_export_start',
          fields: <String, Object?>{'trace': trace, 'compacted': false},
        );
        var package = tagRequest(
          await service.exportAllProfiles(
            context: authorization,
            includeSecrets: true,
          ),
        );
        RemoteTransferDiagnostics.record(
          'sender_export_complete',
          fields: <String, Object?>{
            'trace': trace,
            'compacted': false,
            'profiles': package.profiles.length,
            'resources': package.resources.length,
            'sections': package.sections.length,
          },
        );
        ({String payload, int wireBytes, int expandedBytes, bool compressed})?
        encoded;
        phase = 'encode_full';
        try {
          encoded = await PortableProfilePackage.encodeAuthenticatedTransport(
            package,
            requestId: requestId,
            maxExpandedPayloadBytes: kMaxProfileGraphExpandedBytes,
          );
        } catch (error) {
          if (!PortableProfilePackage.isExportTooLarge(error)) rethrow;
          RemoteTransferDiagnostics.record(
            'sender_encode_requires_compaction',
            fields: <String, Object?>{
              'trace': trace,
              'errorType': error.runtimeType,
            },
          );
        }
        if (encoded != null) {
          RemoteTransferDiagnostics.record(
            'sender_encode_complete',
            fields: <String, Object?>{
              'trace': trace,
              'compacted': false,
              'compressed': encoded.compressed,
              'wireBytes': encoded.wireBytes,
              'expandedBytes': encoded.expandedBytes,
            },
          );
        }
        if (encoded == null ||
            profileGraphTransportNeedsCompaction(
              wireBytes: encoded.wireBytes,
              expandedBytes: encoded.expandedBytes,
            )) {
          // Keep durable IPTV/history rows, but omit Debrify TV as a complete
          // feature. A channel definition without its saved hashes is not a
          // usable restore, so the user must explicitly accept this package.
          phase = 'export_compacted';
          RemoteTransferDiagnostics.record(
            'sender_export_start',
            fields: <String, Object?>{'trace': trace, 'compacted': true},
          );
          package = tagRequest(
            await service.exportAllProfiles(
              context: authorization,
              includeSecrets: true,
              compactDatabaseSnapshots: true,
            ),
          );
          RemoteTransferDiagnostics.record(
            'sender_export_complete',
            fields: <String, Object?>{
              'trace': trace,
              'compacted': true,
              'profiles': package.profiles.length,
              'resources': package.resources.length,
              'sections': package.sections.length,
            },
          );
          phase = 'encode_compacted';
          encoded = await PortableProfilePackage.encodeAuthenticatedTransport(
            package,
            requestId: requestId,
            maxExpandedPayloadBytes: kMaxProfileGraphExpandedBytes,
          );
          RemoteTransferDiagnostics.record(
            'sender_encode_complete',
            fields: <String, Object?>{
              'trace': trace,
              'compacted': true,
              'compressed': encoded.compressed,
              'wireBytes': encoded.wireBytes,
              'expandedBytes': encoded.expandedBytes,
            },
          );
        }
        if (encoded.wireBytes > kMaxProfileGraphWireBytes) {
          RemoteTransferDiagnostics.record(
            'sender_wire_limit_exceeded',
            fields: <String, Object?>{
              'trace': trace,
              'wireBytes': encoded.wireBytes,
              'limitBytes': kMaxProfileGraphWireBytes,
            },
          );
          throw const ProfilePackageTooLargeException();
        }
        if (!await confirmDebrifyTvOmission(package)) return false;
        phase = 'wire_send';
        RemoteTransferDiagnostics.record(
          'sender_wire_start',
          fields: <String, Object?>{
            'trace': trace,
            'wireBytes': encoded.wireBytes,
          },
        );
        return sendConfigPayloadToDevice(
          state,
          ConfigCommand.profileGraph,
          targetIp,
          encoded.payload,
          label: 'All profiles',
          resultRequestId: requestId,
        );
      }

      // Same outbound barrier every piecemeal item send runs under.
      final outbound = await ProfileAsyncAuthorization.capture(
        ProfileFeature.remoteTransfer,
      );
      ok = outbound == null
          ? await sendGraph()
          : await outbound.runIfCurrentAsOutbound(sendGraph);
      RemoteTransferDiagnostics.record(
        'sender_wire_finished',
        fields: <String, Object?>{
          'trace': trace,
          'ok': ok,
          'elapsedMs': startedAt.elapsedMilliseconds,
        },
      );
    } catch (error) {
      RemoteTransferDiagnostics.record(
        'sender_graph_exception',
        fields: <String, Object?>{
          'trace': trace,
          'phase': phase,
          'errorType': error.runtimeType,
          'elapsedMs': startedAt.elapsedMilliseconds,
        },
      );
      debugPrint('RemoteTransferAll: profile graph send failed');
      ok = false;
    }
    if (!mounted) {
      await resultSubscription.cancel();
      return;
    }
    if (!ok) {
      RemoteTransferDiagnostics.record(
        'sender_graph_stopped',
        fields: <String, Object?>{
          'trace': trace,
          'phase': phase,
          'elapsedMs': startedAt.elapsedMilliseconds,
        },
      );
      await resultSubscription.cancel();
      setState(() => _transferring = false);
      if (cancelled) {
        _toast('Profile transfer cancelled');
      } else {
        _toast('Profile transfer failed', error: true);
      }
      return;
    }
    // Delivered is not applied: the TV user still confirms, authorization
    // can refuse, the import can fail. Wait for the receiver's real
    // outcome instead of declaring victory at the first hop.
    _toast('Delivered — confirm the import on the TV');
    try {
      final result = await resultCompleter.future.timeout(
        const Duration(seconds: 180),
      );
      if (!mounted) return;
      setState(() {
        _transferring = false;
        _done = result.ok;
      });
      RemoteTransferDiagnostics.record(
        'sender_graph_result',
        fields: <String, Object?>{
          'trace': trace,
          'ok': result.ok,
          'elapsedMs': startedAt.elapsedMilliseconds,
        },
      );
      _toast(result.message, error: !result.ok);
    } on TimeoutException {
      RemoteTransferDiagnostics.record(
        'sender_result_timeout',
        fields: <String, Object?>{
          'trace': trace,
          'elapsedMs': startedAt.elapsedMilliseconds,
        },
      );
      if (!mounted) return;
      setState(() => _transferring = false);
      _toast(
        'No response from the TV. Open an Admin profile there and resend.',
        error: true,
      );
    } finally {
      await resultSubscription.cancel();
    }
  }

  Future<bool> _confirmProfileGraphDebrifyTvOmission(
    DebrifyTvBackupOmission omission,
  ) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Continue without Debrify TV?'),
            content: Text(
              'This profile transfer had to be compacted to fit on the TV. '
              'Debrify TV will not be included: ${omission.contentsLabel} '
              'will be left out. No empty channels will be created.\n\n'
              'You can cancel and open Debrify TV → Export first to save a '
              'ZIP containing the channels and their playable pools. After '
              'the profile transfer, import that ZIP from storage or use '
              'Remote → Debrify TV Channels.'
              '${omission.profilesAffected > 1 ? ' Repeat the channel transfer for each affected profile.' : ''}',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel and export ZIP'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continue without Debrify TV'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _sendConfigItem(
    RemoteControlState state,
    String targetIp,
    String key, {
    String? transferRequestId,
  }) async {
    String transferData(String value) => transferRequestId == null
        ? value
        : remoteTransferItemBody(requestId: transferRequestId, payload: value);

    Future<bool> sendScalar(
      String command,
      Future<String?> Function() read,
    ) async {
      final value = await read();
      return value != null &&
          value.isNotEmpty &&
          await state.sendConfigCommandToDevice(
            command,
            targetIp,
            configData: transferData(value),
          );
    }

    switch (key) {
      case ConfigCommand.realDebrid:
        return sendScalar(
          ConfigCommand.realDebrid,
          () => StorageService.getApiKey(forRemoteTransfer: true),
        );
      case ConfigCommand.torbox:
        return sendScalar(
          ConfigCommand.torbox,
          () => StorageService.getTorboxApiKey(forRemoteTransfer: true),
        );
      case ConfigCommand.premiumize:
        return sendScalar(
          ConfigCommand.premiumize,
          () => StorageService.getPremiumizeApiKey(forRemoteTransfer: true),
        );
      case ConfigCommand.allDebrid:
        return sendScalar(
          ConfigCommand.allDebrid,
          () => StorageService.getAllDebridApiKey(forRemoteTransfer: true),
        );
      case ConfigCommand.pikpak:
        final email = await StorageService.getPikPakEmail(
          forRemoteTransfer: true,
        );
        if (email == null || email.isEmpty) return false;
        return state.sendConfigCommandToDevice(
          ConfigCommand.pikpak,
          targetIp,
          configData: transferData(
            jsonEncode({
              'email': email,
              'password': _pikpakPasswordController.text,
            }),
          ),
        );
      case ConfigCommand.trakt:
        final access = await StorageService.getTraktAccessToken(
          forRemoteTransfer: true,
        );
        final refresh = await StorageService.getTraktRefreshToken(
          forRemoteTransfer: true,
        );
        if (access == null ||
            access.isEmpty ||
            refresh == null ||
            refresh.isEmpty) {
          return false;
        }
        final expiry = await StorageService.getTraktTokenExpiry();
        final username = await StorageService.getTraktUsername();
        return state.sendConfigCommandToDevice(
          ConfigCommand.trakt,
          targetIp,
          configData: transferData(
            jsonEncode({
              'access_token': access,
              'refresh_token': refresh,
              if (expiry != null) 'expiry_ms': expiry,
              if (username != null) 'username': username,
            }),
          ),
        );
      case ConfigCommand.simkl:
        final access = await StorageService.getSimklAccessToken(
          forRemoteTransfer: true,
        );
        if (access == null || access.isEmpty) return false;
        final username = await StorageService.getSimklUsername();
        return state.sendConfigCommandToDevice(
          ConfigCommand.simkl,
          targetIp,
          configData: transferData(
            jsonEncode({
              'access_token': access,
              if (username != null) 'username': username,
            }),
          ),
        );
      case ConfigCommand.mdblist:
        final apiKey = await StorageService.getMdblistApiKey(
          forRemoteTransfer: true,
        );
        if (apiKey == null || apiKey.isEmpty) return false;
        final username = await StorageService.getMdblistUsername();
        return state.sendConfigCommandToDevice(
          ConfigCommand.mdblist,
          targetIp,
          configData: transferData(
            jsonEncode({
              'api_key': apiKey,
              if (username != null) 'username': username,
            }),
          ),
        );
      case ConfigCommand.trackingPreferences:
        return state.sendConfigCommandToDevice(
          ConfigCommand.trackingPreferences,
          targetIp,
          configData: transferData(
            jsonEncode(await StorageService.buildTrackingPreferencesPayload()),
          ),
        );
      case ConfigCommand.searchEngines:
        await LocalEngineStorage.instance.initialize();
        final engineIds = await LocalEngineStorage.instance
            .getImportedEngineIds();
        if (engineIds.isEmpty) return false;
        return state.sendConfigCommandToDevice(
          ConfigCommand.searchEngines,
          targetIp,
          configData: transferData(jsonEncode(engineIds)),
        );
      case ConfigCommand.webDav:
        final servers = await StorageService.getWebDavServers(
          forSettings: false,
          forRemoteTransfer: true,
        );
        if (servers.isEmpty) return false;
        return state.sendConfigCommandToDevice(
          ConfigCommand.webDav,
          targetIp,
          configData: transferData(
            jsonEncode([for (final server in servers) server.toTransferJson()]),
          ),
        );
      case ConfigCommand.indexerManagers:
        final managers = await StorageService.getIndexerManagerConfigs(
          forSettings: false,
          forRemoteTransfer: true,
        );
        if (managers.isEmpty) return false;
        return state.sendConfigCommandToDevice(
          ConfigCommand.indexerManagers,
          targetIp,
          configData: transferData(
            jsonEncode([
              for (final manager in managers) manager.toTransferJson(),
            ]),
          ),
        );
      // The IPTV payloads routinely outgrow a single datagram — a few hundred
      // starred channels is tens of kilobytes — so they take the chunked path.
      case ConfigCommand.iptvPlaylists:
        final payload = await IptvTransferPayload.buildPlaylists(
          forRemoteTransfer: true,
        );
        if (payload.isEmpty) return false;
        return sendConfigPayloadToDevice(
          state,
          ConfigCommand.iptvPlaylists,
          targetIp,
          jsonEncode(payload),
          label: 'IPTV providers',
          transferRequestId: transferRequestId,
        );
      case ConfigCommand.iptvFavorites:
        final payload = await IptvTransferPayload.buildFavorites(
          forRemoteTransfer: true,
        );
        if (payload.isEmpty) return false;
        return sendConfigPayloadToDevice(
          state,
          ConfigCommand.iptvFavorites,
          targetIp,
          jsonEncode(payload),
          label: 'IPTV favorites',
          transferRequestId: transferRequestId,
        );
      case ConfigCommand.iptvLists:
        final payload = await IptvTransferPayload.buildCustomLists(
          forRemoteTransfer: true,
        );
        if (payload.isEmpty) return false;
        return sendConfigPayloadToDevice(
          state,
          ConfigCommand.iptvLists,
          targetIp,
          jsonEncode(payload),
          label: 'IPTV lists',
          transferRequestId: transferRequestId,
        );
      case ConfigCommand.streamBadges:
        final payload = await StreamBadgesService.instance.exportJson();
        if (payload.isEmpty) return false;
        return sendConfigPayloadToDevice(
          state,
          ConfigCommand.streamBadges,
          targetIp,
          jsonEncode(payload),
          label: 'Stream badges',
          transferRequestId: transferRequestId,
        );
      default:
        return false;
    }
  }

  void _toast(String msg, {bool error = false, bool warning = false}) {
    if (!mounted) return;
    final color = error
        ? const Color(0xFFEF4444)
        : warning
        ? const Color(0xFFF59E0B)
        : const Color(0xFF10B981);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _transferring ? null : widget.onBack,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to menu'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Transfer Everything',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Send all configured services and installed addons to the '
          'connected device in one go.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 24),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            ),
          )
        else if (_items.isEmpty && !_canSendProfileGraph) ...[
          _buildEmpty(),
          // Nothing sendable, but if the reason is a file-only IPTV setup the
          // user deserves to know that rather than "nothing configured".
          if (_iptvFileImported > 0) _buildFileImportedNote(),
        ] else ...[
          if (_canSendProfileGraph) _buildProfilesToggle(),
          if (!_includeProfiles) ...[
            if (_hasPikpak) _buildPikpakPassword(),
            ..._items.map(_buildItemTile),
            if (_iptvFileImported > 0) _buildFileImportedNote(),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canStart ? _start : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                disabledBackgroundColor: const Color(
                  0xFF6366F1,
                ).withValues(alpha: 0.3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _transferring
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_connecting)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        else
                          Icon(_done ? Icons.check : Icons.send, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _connecting
                              ? 'Connecting securely…'
                              : _done
                              ? 'Done'
                              : _includeProfiles
                              ? 'Send All Profiles'
                              : 'Transfer Everything',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (_hasPikpak &&
              _pikpakPasswordController.text.isEmpty &&
              !_transferring) ...[
            const SizedBox(height: 8),
            Text(
              'Enter PikPak password to enable transfer',
              style: TextStyle(
                color: Colors.amber.withValues(alpha: 0.8),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildProfilesToggle() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(
            0xFF6366F1,
          ).withValues(alpha: _includeProfiles ? 0.6 : 0.15),
        ),
      ),
      child: SwitchListTile(
        value: _includeProfiles,
        onChanged: _transferring || _connecting
            ? null
            : (value) => setState(() => _includeProfiles = value),
        title: const Text('Include all profiles'),
        subtitle: Text(
          'Recreates every profile on the TV — settings, connections, PINs, '
          'playlists, favorites, and library state — instead of merging into '
          'its signed-in profile. The TV asks before importing.',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildFileImportedNote() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '$_iptvFileImported IPTV playlist'
        '${_iptvFileImported == 1 ? '' : 's'} imported from a file can\'t be '
        'sent — import the file on the TV. Starred channels from them still '
        'go across.',
        style: TextStyle(
          color: Colors.amber.withValues(alpha: 0.75),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
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
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Icon(
                Icons.inbox_outlined,
                size: 36,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing to transfer',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set up a debrid provider, Trakt, search engines, or addons '
              'first.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPikpakPassword() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud, color: Color(0xFF3B82F6), size: 18),
                const SizedBox(width: 8),
                Text(
                  'PikPak password',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Connected account',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pikpakPasswordController,
              obscureText: !_showPikpakPassword,
              enabled: !_transferring && !_done,
              decoration: InputDecoration(
                hintText: 'Enter password',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPikpakPassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: Colors.white.withValues(alpha: 0.5),
                    size: 20,
                  ),
                  onPressed: () => setState(
                    () => _showPikpakPassword = !_showPikpakPassword,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(_TransferItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.icon, color: item.color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            _buildStatus(item.status),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(_ItemStatus status) {
    switch (status) {
      case _ItemStatus.pending:
        return Icon(
          Icons.radio_button_unchecked,
          color: Colors.white.withValues(alpha: 0.25),
          size: 18,
        );
      case _ItemStatus.sending:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
        );
      case _ItemStatus.success:
        return const Icon(
          Icons.check_circle,
          color: Color(0xFF10B981),
          size: 18,
        );
      case _ItemStatus.failure:
        return const Icon(Icons.error, color: Color(0xFFEF4444), size: 18);
      case _ItemStatus.skipped:
        return Icon(
          Icons.remove_circle_outline,
          color: Colors.white.withValues(alpha: 0.3),
          size: 18,
        );
    }
  }
}
