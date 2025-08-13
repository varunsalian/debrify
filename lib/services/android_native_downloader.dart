import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class AndroidNativeDownloader {
	static const MethodChannel _channel = MethodChannel('com.debrify.app/downloader');
	static const EventChannel _events = EventChannel('com.debrify.app/downloader_events');

	static Stream<Map<String, dynamic>>? _eventStream;

	static Stream<Map<String, dynamic>> get events {
		_eventStream ??= _events
			.receiveBroadcastStream()
			.map((e) => Map<String, dynamic>.from(e as Map));
		return _eventStream!;
	}

	static Future<String?> start({
		required String url,
		String fileName = 'download',
		String subDir = 'Debrify',
		String mimeType = 'application/octet-stream',
		Map<String, String>? headers,
	}) async {
		if (!Platform.isAndroid) return null;
		final taskId = await _channel.invokeMethod<String>('startMediaStoreDownload', {
			'url': url,
			'fileName': fileName,
			'subDir': subDir,
			'mimeType': mimeType,
			'headers': headers ?? <String, String>{},
		});
		return taskId;
	}

	static Future<bool> pause(String taskId) async {
		if (!Platform.isAndroid) return false;
		return (await _channel.invokeMethod<bool>('pause', {'taskId': taskId})) ?? false;
	}

	static Future<bool> resume(String taskId) async {
		if (!Platform.isAndroid) return false;
		return (await _channel.invokeMethod<bool>('resume', {'taskId': taskId})) ?? false;
	}

	static Future<bool> cancel(String taskId) async {
		if (!Platform.isAndroid) return false;
		return (await _channel.invokeMethod<bool>('cancel', {'taskId': taskId})) ?? false;
	}

	static Future<bool> openContentUri(String uri, String mimeType) async {
		if (!Platform.isAndroid) return false;
		return (await _channel.invokeMethod<bool>('openContentUri', {
			'uri': uri,
			'mimeType': mimeType,
		})) ?? false;
	}

	static Future<bool> openBatteryOptimizationSettings() async {
		if (!Platform.isAndroid) return false;
		return (await _channel.invokeMethod<bool>('openBatteryOptimizationSettings')) ?? false;
	}

	static Future<bool> requestIgnoreBatteryOptimizationsForApp() async {
		if (!Platform.isAndroid) return false;
		return (await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizationForApp')) ?? false;
	}
} 