import 'package:url_launcher/url_launcher.dart';

/// Opens a settings community link. Shared so both layouts launch the same URL.
Future<void> launchSettingsUrl(String url) async {
  await launchUrl(Uri.parse(url));
}
