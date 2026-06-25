import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class IptvStore {
  static const _key = 'pt_iptv_verified_portals';
  static const _favKey = 'pt_iptv_favorite_portal_keys';

  static Future<List<VerifiedPortal>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final arr = json.decode(raw) as List;
      return arr.map((e) {
        final o = e as Map<String, dynamic>;
        return VerifiedPortal(
          portal: IptvPortal(
            url: o['url'] as String? ?? '',
            username: o['username'] as String? ?? '',
            password: o['password'] as String? ?? '',
            source: o['source'] as String? ?? '',
          ),
          name: o['name'] as String? ?? '',
          expiry: o['expiry'] as String? ?? '',
          maxConnections: o['max'] as String? ?? '1',
          activeConnections: o['active'] as String? ?? '0',
        );
      }).toList();
    } catch (e) {
      debugPrint('IptvStore.load failed: $e');
      return [];
    }
  }

  static Future<void> save(List<VerifiedPortal> list) async {
    final prefs = await SharedPreferences.getInstance();
    final arr = list
        .map((v) => {
              'url': v.portal.url,
              'username': v.portal.username,
              'password': v.portal.password,
              'source': v.portal.source,
              'name': v.name,
              'expiry': v.expiry,
              'max': v.maxConnections,
              'active': v.activeConnections,
            })
        .toList();
    await prefs.setString(_key, json.encode(arr));
  }

  static Future<Set<String>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_favKey) ?? const <String>[];
    return list.toSet();
  }

  static Future<void> saveFavorites(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favKey, keys.toList());
  }
}

class IptvAliveStore {
  static String portalKey(IptvPortal p) =>
      '${p.url}|${p.username}|${p.password}'.toLowerCase();

  static String _aliveKey(String k) => 'pt_iptv_alive_$k';
  static String _liveOnlyKey(String k) => 'pt_iptv_liveonly_$k';

  static Future<AliveSnapshot?> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_aliveKey(key));
    if (raw == null) return null;
    try {
      final o = json.decode(raw) as Map<String, dynamic>;
      final ids = (o['ids'] as List).map((e) => e as String).toSet();
      return AliveSnapshot(
        checkedAt: (o['at'] as num?)?.toInt() ?? 0,
        aliveIds: ids,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String key, AliveSnapshot snap) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _aliveKey(key),
      json.encode({'at': snap.checkedAt, 'ids': snap.aliveIds.toList()}),
    );
  }

  static Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_aliveKey(key));
    await prefs.remove(_liveOnlyKey(key));
  }

  static Future<bool> loadLiveOnly(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_liveOnlyKey(key)) ?? false;
  }

  static Future<void> saveLiveOnly(String key, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_liveOnlyKey(key), enabled);
  }
}

class IptvChannelResultsStore {
  static String _key(String channelId) => 'pt_iptv_ch_$channelId';

  static Future<List<StoredHit>> load(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(channelId));
    if (raw == null) return [];
    try {
      final arr = json.decode(raw) as List;
      return arr.map((e) {
        final o = e as Map<String, dynamic>;
        return StoredHit(
          portalUrl: o['pu'] as String? ?? '',
          portalUser: o['uu'] as String? ?? '',
          portalPass: o['pp'] as String? ?? '',
          portalName: o['pn'] as String? ?? '',
          streamId: o['sid'] as String? ?? '',
          streamName: o['sn'] as String? ?? '',
          streamIcon: o['si'] as String? ?? '',
          streamCategoryId: o['scid'] as String? ?? '',
          streamContainerExt: o['sce'] as String? ?? '',
          streamKind: o['sk'] as String? ?? 'live',
          streamUrl: o['url'] as String? ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(String channelId, List<StoredHit> hits) async {
    final prefs = await SharedPreferences.getInstance();
    final arr = hits
        .map((h) => {
              'pu': h.portalUrl,
              'uu': h.portalUser,
              'pp': h.portalPass,
              'pn': h.portalName,
              'sid': h.streamId,
              'sn': h.streamName,
              'si': h.streamIcon,
              'scid': h.streamCategoryId,
              'sce': h.streamContainerExt,
              'sk': h.streamKind,
              'url': h.streamUrl,
            })
        .toList();
    await prefs.setString(_key(channelId), json.encode(arr));
  }

  static Future<void> clear(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(channelId));
  }
}

class IptvChannelFavoritesStore {
  static String _key(String channelId) => 'pt_iptv_chfav_$channelId';

  static Future<Set<String>> load(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key(channelId)) ?? const <String>[]).toSet();
  }

  static Future<void> save(String channelId, Set<String> urls) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(channelId), urls.toList());
  }
}
