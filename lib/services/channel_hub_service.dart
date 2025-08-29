import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel_hub.dart';
import 'torrentio_service.dart';

class ChannelHubService {
  static const String _storageKey = 'channel_hubs';
  
  /// Get all channel hubs
  static Future<List<ChannelHub>> getChannelHubs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? hubsJson = prefs.getString(_storageKey);
      
      if (hubsJson == null || hubsJson.isEmpty) {
        return [];
      }
      
      final List<dynamic> hubsList = json.decode(hubsJson);
      return hubsList.map((json) => ChannelHub.fromJson(json)).toList();
    } catch (e) {
      print('Error loading channel hubs: $e');
      return [];
    }
  }
  
  /// Save a channel hub
  static Future<bool> saveChannelHub(ChannelHub hub) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<ChannelHub> existingHubs = await getChannelHubs();
      
      // Check if hub with same ID already exists
      final existingIndex = existingHubs.indexWhere((h) => h.id == hub.id);
      if (existingIndex != -1) {
        existingHubs[existingIndex] = hub;
      } else {
        existingHubs.add(hub);
      }
      
      final String hubsJson = json.encode(existingHubs.map((h) => h.toJson()).toList());
      return await prefs.setString(_storageKey, hubsJson);
    } catch (e) {
      print('Error saving channel hub: $e');
      return false;
    }
  }
  
  /// Delete a channel hub and all its related data
  static Future<bool> deleteChannelHub(String hubId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<ChannelHub> existingHubs = await getChannelHubs();
      
      // Find the hub to get its movies and series
      final hubToDelete = existingHubs.firstWhere((hub) => hub.id == hubId);
      
      // Clean up Torrentio streams for all movies in this hub
      for (final movie in hubToDelete.movies) {
        await TorrentioService.clearMovieCache(movie.id, hubId: hubId);
      }
      
      // Clear all Torrentio cache for this hub
      await TorrentioService.clearHubCache(hubId);
      
      // Remove the hub from the list
      existingHubs.removeWhere((hub) => hub.id == hubId);
      
      // Save the updated list
      final String hubsJson = json.encode(existingHubs.map((h) => h.toJson()).toList());
      final result = await prefs.setString(_storageKey, hubsJson);
      
      print('DEBUG: Deleted channel hub $hubId and cleaned up all related data');
      return result;
    } catch (e) {
      print('Error deleting channel hub: $e');
      return false;
    }
  }
  
  /// Generate a unique ID for a new channel hub
  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
  
  /// Get a specific channel hub by ID
  static Future<ChannelHub?> getChannelHub(String hubId) async {
    try {
      final List<ChannelHub> hubs = await getChannelHubs();
      return hubs.firstWhere((hub) => hub.id == hubId);
    } catch (e) {
      print('Error getting channel hub: $e');
      return null;
    }
  }
  
  /// Update an existing channel hub
  static Future<bool> updateChannelHub(ChannelHub updatedHub) async {
    return await saveChannelHub(updatedHub);
  }
} 