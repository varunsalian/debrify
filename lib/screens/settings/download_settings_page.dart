import 'package:flutter/material.dart';
import '../../services/storage_service.dart';

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
				],
			),
		);
	}
} 