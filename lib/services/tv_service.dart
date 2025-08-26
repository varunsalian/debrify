import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tv_channel.dart';
import '../models/tv_channel_torrent.dart';
import '../models/torrent.dart';
import 'search_engine_factory.dart';
import 'search_engine.dart';

class TVService {
  static const String _channelsKey = 'tv_channels';
  static const String _channelTorrentsKey = 'tv_channel_torrents';

  // Channel management
  static Future<List<TVChannel>> getChannels() async {
    final prefs = await SharedPreferences.getInstance();
    final channelsJson = prefs.getString(_channelsKey);
    if (channelsJson == null || channelsJson.isEmpty) return [];
    
    try {
      final List<dynamic> channelsList = jsonDecode(channelsJson);
      return channelsList.map((json) => TVChannel.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveChannels(List<TVChannel> channels) async {
    final prefs = await SharedPreferences.getInstance();
    final channelsJson = jsonEncode(channels.map((c) => c.toJson()).toList());
    await prefs.setString(_channelsKey, channelsJson);
  }

  static Future<void> addChannel(TVChannel channel) async {
    final channels = await getChannels();
    channels.add(channel);
    await saveChannels(channels);
  }

  static Future<void> updateChannel(TVChannel channel) async {
    final channels = await getChannels();
    final index = channels.indexWhere((c) => c.id == channel.id);
    if (index != -1) {
      channels[index] = channel;
      await saveChannels(channels);
    }
  }

  static Future<void> deleteChannel(String channelId) async {
    final channels = await getChannels();
    channels.removeWhere((c) => c.id == channelId);
    await saveChannels(channels);
    
    // Also delete associated torrents
    await deleteChannelTorrents(channelId);
  }

  // Torrent management
  static Future<List<TVChannelTorrent>> getChannelTorrents(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    final torrentsJson = prefs.getString('${_channelTorrentsKey}_$channelId');
    if (torrentsJson == null || torrentsJson.isEmpty) return [];
    
    try {
      final List<dynamic> torrentsList = jsonDecode(torrentsJson);
      return torrentsList.map((json) => TVChannelTorrent.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> saveChannelTorrents(String channelId, List<TVChannelTorrent> torrents) async {
    final prefs = await SharedPreferences.getInstance();
    final torrentsJson = jsonEncode(torrents.map((t) => t.toJson()).toList());
    await prefs.setString('${_channelTorrentsKey}_$channelId', torrentsJson);
  }

  static Future<void> addChannelTorrents(String channelId, List<TVChannelTorrent> newTorrents) async {
    final existingTorrents = await getChannelTorrents(channelId);
    final existingMagnets = existingTorrents.map((t) => t.magnet).toSet();
    
    // Filter out duplicates based on magnet links
    final uniqueNewTorrents = newTorrents.where((t) => !existingMagnets.contains(t.magnet)).toList();
    
    if (uniqueNewTorrents.isNotEmpty) {
      existingTorrents.addAll(uniqueNewTorrents);
      await saveChannelTorrents(channelId, existingTorrents);
    }
  }

  static Future<void> deleteChannelTorrents(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_channelTorrentsKey}_$channelId');
  }

  // Search functionality
  static Future<List<TVChannelTorrent>> searchChannelContent(TVChannel channel) async {
    final List<TVChannelTorrent> allResults = [];
    final searchEngines = SearchEngineFactory.getSearchEngines();
    
    for (final keyword in channel.keywords) {
      for (final engine in searchEngines) {
        try {
          final torrents = await engine.search(keyword);
          final channelTorrents = torrents.map((t) => 
            TVChannelTorrent.fromTorrent(t, channel.id, engine.name)
          ).toList();
          allResults.addAll(channelTorrents);
        } catch (e) {
          // Continue with other engines if one fails
          continue;
        }
      }
    }
    
    // Remove duplicates based on magnet links
    final uniqueResults = <String, TVChannelTorrent>{};
    for (final torrent in allResults) {
      uniqueResults[torrent.magnet] = torrent;
    }
    
    return uniqueResults.values.toList();
  }

  static Future<void> refreshChannelContent(TVChannel channel) async {
    final newTorrents = await searchChannelContent(channel);
    await addChannelTorrents(channel.id, newTorrents);
    
    // Update channel's last updated timestamp
    final updatedChannel = channel.copyWith(lastUpdated: DateTime.now());
    await updateChannel(updatedChannel);
  }

  static Future<void> refreshAllChannels() async {
    final channels = await getChannels();
    for (final channel in channels) {
      await refreshChannelContent(channel);
    }
  }
} 