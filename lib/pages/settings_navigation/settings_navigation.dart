import 'package:material_ui/material_ui.dart';

import 'settings_navigation_view.dart';

class SettingsNavigation extends StatefulWidget {
  const SettingsNavigation({super.key});

  @override
  SettingsNavigationController createState() => SettingsNavigationController();
}

class SettingsNavigationController extends State<SettingsNavigation> {
  @override
  Widget build(BuildContext context) => SettingsNavigationView(this);
}
