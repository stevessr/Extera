import 'package:material_ui/material_ui.dart';

import 'settings_calls_view.dart';

class SettingsCalls extends StatefulWidget {
  const SettingsCalls({super.key});

  @override
  SettingsCallsController createState() => SettingsCallsController();
}

class SettingsCallsController extends State<SettingsCalls> {
  @override
  Widget build(BuildContext context) => SettingsCallsView(this);
}
