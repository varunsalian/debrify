import 'package:flutter/material.dart';

class IptvSettingsInputOwner {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController urlController = TextEditingController();
  final TextEditingController epgUrlController = TextEditingController();

  // Xtream Codes controllers and focus nodes
  final TextEditingController xcNameController = TextEditingController();
  final TextEditingController xcServerController = TextEditingController();
  final TextEditingController xcUsernameController = TextEditingController();
  final TextEditingController xcPasswordController = TextEditingController();
  bool isXcAdding = false;

  late TabController tabController;
  bool isAdding = false;
}
