import 'package:debrify/models/premiumize_folder_item.dart';

List<PremiumizeFolderItem> applySortedView(List<PremiumizeFolderItem> items) {
  final folders = items.where((i) => i.isFolder).toList();
  final files = items.where((i) => !i.isFolder).toList();

  int cmp(String a, String b, {bool seasonAware = false}) {
    final aNum = seasonAware ? extractSeasonNumber(a) : extractLeadingNumber(a);
    final bNum = seasonAware ? extractSeasonNumber(b) : extractLeadingNumber(b);
    if (aNum != null && bNum != null) return aNum.compareTo(bNum);
    if (aNum != null) return -1;
    if (bNum != null) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  folders.sort((a, b) => cmp(a.name, b.name, seasonAware: true));
  files.sort((a, b) => cmp(a.name, b.name));
  return [...folders, ...files];
}

int? extractSeasonNumber(String name) {
  final patterns = [
    RegExp(r'^(\d+)[\s._-]'),
    RegExp(r'season[\s_-]*(\d+)', caseSensitive: false),
    RegExp(r'chapter[\s_-]*(\d+)', caseSensitive: false),
    RegExp(r'episode[\s_-]*(\d+)', caseSensitive: false),
    RegExp(r'part[\s_-]*(\d+)', caseSensitive: false),
    RegExp(r'^[a-z]+[\s_-]*(\d+)', caseSensitive: false),
  ];
  final lower = name.toLowerCase();
  for (final p in patterns) {
    final m = p.firstMatch(lower);
    if (m != null && m.groupCount >= 1) return int.tryParse(m.group(1)!);
  }
  return null;
}

int? extractLeadingNumber(String name) {
  final m = RegExp(r'^(\d+)[\s._-]').firstMatch(name);
  if (m != null && m.groupCount >= 1) return int.tryParse(m.group(1)!);
  return null;
}
