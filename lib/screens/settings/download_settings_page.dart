import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import '../../services/android_native_downloader.dart';

class DownloadSettingsPage extends StatefulWidget {
	const DownloadSettingsPage({super.key});

	@override
	State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
	bool _loading = true;
	int _maxParallel = 2;

	@override
	void initState() {
		super.initState();
		_load();
	}

	Future<void> _load() async {
		final val = await StorageService.getMaxParallelDownloads();
		setState(() {
			_maxParallel = val;
			_loading = false;
		});
	}

	Future<void> _save(int value) async {
		await StorageService.setMaxParallelDownloads(value);
		setState(() {
			_maxParallel = value;
		});
		ScaffoldMessenger.of(context).showSnackBar(
			const SnackBar(content: Text('Parallel downloads updated')),
		);
	}

	@override
	Widget build(BuildContext context) {
		if (_loading) {
			return const Scaffold(
				body: Center(child: CircularProgressIndicator()),
			);
		}
		return Scaffold(
			appBar: AppBar(title: const Text('Download Settings')),
			body: ListView(
				padding: const EdgeInsets.all(16),
				children: [
					Card(
						child: Padding(
							padding: const EdgeInsets.all(16),
							child: Row(
								children: [
									Expanded(
										child: Column(
											crossAxisAlignment: CrossAxisAlignment.start,
											children: [
												Text('Parallel downloads', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
												const SizedBox(height: 4),
												Text('Limit how many files download at once', style: Theme.of(context).textTheme.bodySmall),
											],
										),
									),
									DropdownButton<int>(
										value: _maxParallel,
										items: List.generate(8, (i) => i + 1)
											.map((v) => DropdownMenuItem<int>(value: v, child: Text(v.toString())))
											.toList(),
										onChanged: (v) {
											if (v != null) _save(v);
										},
									),
								],
							),
						),
					),
					const SizedBox(height: 12),
					Card(
						child: Padding(
							padding: const EdgeInsets.all(16),
							child: Column(
								crossAxisAlignment: CrossAxisAlignment.start,
								children: [
									Row(
										children: [
											Container(
												padding: const EdgeInsets.all(10),
												decoration: BoxDecoration(
													color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
													borderRadius: BorderRadius.circular(12),
												),
												child: Icon(Icons.battery_saver, color: Theme.of(context).colorScheme.primary),
											),
											const SizedBox(width: 12),
											Expanded(
												child: Column(
													crossAxisAlignment: CrossAxisAlignment.start,
																								children: const [
												Text('Allow background downloads', style: TextStyle(fontWeight: FontWeight.w600)),
												SizedBox(height: 4),
												Text('Open system settings to ignore battery optimizations for reliable downloads', style: TextStyle(fontSize: 12)),
											],
										),
									),
									FilledButton(
										onPressed: () async {
											final ok = await showDialog<bool>(
												context: context,
												builder: (ctx) => AlertDialog(
													title: const Text('Allow background downloads'),
													content: const Text('Open system settings to allow this app to ignore battery optimizations?'),
													actions: [
														TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
														FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Open')),
													],
												),
											) ?? false;
											if (ok) {
												await StorageService.setBatteryOptimizationStatus('denied');
												await AndroidNativeDownloader.openBatteryOptimizationSettings();
											}
									},
									child: const Text('Open settings'),
								),
								], // end Row children
								), // end Row
							], // end Column children
							), // end Column
						), // end Padding
					), // end Card
				],
			),
		);
	}
} 