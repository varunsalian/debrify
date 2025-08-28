import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/channel_hub.dart';

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
  
  /// Delete a channel hub
  static Future<bool> deleteChannelHub(String hubId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<ChannelHub> existingHubs = await getChannelHubs();
      
      existingHubs.removeWhere((hub) => hub.id == hubId);
      
      final String hubsJson = json.encode(existingHubs.map((h) => h.toJson()).toList());
      return await prefs.setString(_storageKey, hubsJson);
    } catch (e) {
      print('Error deleting channel hub: $e');
      return false;
    }
  }
  
  /// Generate a unique ID for a new channel hub
  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
} 