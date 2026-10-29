// Composition for Settings › Storage Usage: opens the storage feature's page
// so the settings feature reaches it without importing another feature.
import 'package:debrify/features/storage_usage/presentation/storage_usage_page.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:flutter/material.dart';

Future<void> openStorageUsagePage(BuildContext context) =>
    pushSettingsPage(context, const StorageUsagePage());
