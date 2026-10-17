import 'dart:async';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:flutter/material.dart';

abstract interface class VpIptvZapBannerHost {
  ValueNotifier<bool> get controlsVisible;
  bool get iptvZapBannerOwnsIdentity;
  IptvChannel? get iptvZapChannel;
  set iptvZapChannel(IptvChannel? v);
  set iptvZapClock(DateTime v);
  EpgNowNext? get iptvZapEpg;
  set iptvZapEpg(EpgNowNext? v);
  bool get iptvZapEpgLoading;
  set iptvZapEpgLoading(bool v);
  bool get iptvZapFloatingMounted;
  set iptvZapFloatingMounted(bool v);
  bool get showChannelGuide;
  bool get showIptvChannelSheet;
  bool get showIptvZapBanner;
  set showIptvZapBanner(bool v);
  bool get showSourceSheet;
  bool get mounted;
  void setState(VoidCallback fn);
}

class VpIptvZapBanner {
  VpIptvZapBanner(this._host);
  final VpIptvZapBannerHost _host;

  Timer? iptvZapHideTimer;
  Timer? iptvZapTicker;
  int iptvZapEpgTicket = 0;

  /// Adopt [channel] as the banner's subject and start its guide lookup.
  ///
  /// Called on the first tune and on every zap, whatever is on screen at the
  /// time: the dock can be opened minutes later and must find the panel's
  /// data already loaded.
  void prepareIptvBannerData(IptvChannel channel) {
    if (!_host.mounted || !channel.isLive) return;
    final ticket = ++iptvZapEpgTicket;
    // Whatever the guide already knows paints immediately; the fetch below
    // only ever upgrades it.
    final known = IptvEpgService.instance.peekNowNext(channel.url);
    _host.setState(() {
      _host.iptvZapChannel = channel;
      _host.iptvZapEpg = known;
      _host.iptvZapEpgLoading = known == null;
      _host.iptvZapClock = DateTime.now();
    });
    // Even with an immediate XMLTV answer, the playing Xtream channel needs
    // one archive-aware upgrade: XMLTV has titles/times but no has_archive.
    unawaited(loadIptvZapBannerEpg(channel, ticket));
    // Zapping from VOD to live with the dock already open gives the panel its
    // first channel here rather than at raise time — start its clock.
    syncIptvBannerTicker();
  }

  /// Float the banner over bare video and let it fade itself out.
  void raiseIptvZapBanner() {
    if (!_host.mounted || _host.iptvZapChannel == null) return;
    // Anything the user deliberately opened keeps the frame. The dock is the
    // exception it used to share this strip with: it now carries the same
    // panel itself, so there is nothing to raise over it.
    if (_host.showIptvChannelSheet ||
        _host.showSourceSheet ||
        _host.showChannelGuide ||
        _host.controlsVisible.value) {
      return;
    }
    _host.setState(() {
      _host.showIptvZapBanner = true;
      _host.iptvZapFloatingMounted = true;
    });
    iptvZapHideTimer?.cancel();
    iptvZapHideTimer = Timer(
      const Duration(milliseconds: 4500),
      hideIptvZapBanner,
    );
    syncIptvBannerTicker();
  }

  /// [immediate] skips the fade and unmounts in the same frame — for a handoff
  /// to the dock's copy, where a fade would show both at once.
  void hideIptvZapBanner({bool immediate = false}) {
    iptvZapHideTimer?.cancel();
    iptvZapHideTimer = null;
    final live =
        _host.showIptvZapBanner || (immediate && _host.iptvZapFloatingMounted);
    if (_host.mounted && live) {
      _host.setState(() {
        _host.showIptvZapBanner = false;
        if (immediate) _host.iptvZapFloatingMounted = false;
      });
    }
    syncIptvBannerTicker();
  }

  /// The panel's clock only has to run while the panel is on screen — in
  /// either home. Without it the countdown and the elapsed rule sit frozen,
  /// which is most obvious exactly where the dock is used: while paused,
  /// where the position stream has stopped driving rebuilds.
  void syncIptvBannerTicker() {
    final onScreen =
        _host.iptvZapChannel != null &&
        (_host.showIptvZapBanner ||
            (_host.controlsVisible.value && _host.iptvZapBannerOwnsIdentity));
    if (!onScreen) {
      iptvZapTicker?.cancel();
      iptvZapTicker = null;
      return;
    }
    if (iptvZapTicker != null) return;
    iptvZapTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_host.mounted) return;
      _host.setState(() => _host.iptvZapClock = DateTime.now());
      refreshIptvBannerEpgIfEnded();
    });
  }

  /// The dock can stay open past the end of the programme it is describing.
  /// Re-ask once the current one has finished rather than leave a listing
  /// that is quietly wrong.
  DateTime? iptvArchiveRetryAt;

  void refreshIptvBannerEpgIfEnded() {
    if (_host.iptvZapEpgLoading) return;
    final channel = _host.iptvZapChannel;
    final current = _host.iptvZapEpg?.now;
    if (channel == null || current == null) return;
    final retryArchive =
        !current.hasArchive &&
        iptvArchiveRetryAt != null &&
        !DateTime.now().isBefore(iptvArchiveRetryAt!);
    if (current.stop.isAfter(DateTime.now()) && !retryArchive) return;
    final ticket = ++iptvZapEpgTicket;
    _host.setState(() => _host.iptvZapEpgLoading = true);
    unawaited(loadIptvZapBannerEpg(channel, ticket));
  }

  /// The same lazy now/next fetch the guide rows use. [ticket] is the banner's
  /// generation: a zap that lands mid-flight owns the banner, so a late answer
  /// for the previous channel is dropped rather than painted under the new
  /// channel's name.
  Future<void> loadIptvZapBannerEpg(IptvChannel channel, int ticket) async {
    EpgNowNext? result;
    try {
      result = await IptvEpgService.instance.nowNextWithCatchupMetadata(
        channel.url,
      );
    } catch (_) {
      result = null;
    }
    if (!_host.mounted || ticket != iptvZapEpgTicket) return;
    iptvArchiveRetryAt = DateTime.now().add(const Duration(seconds: 60));
    _host.setState(() {
      _host.iptvZapEpg = result;
      _host.iptvZapEpgLoading = false;
    });
  }
}
