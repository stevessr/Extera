import 'package:flutter/material.dart';

import 'package:extera_next/widgets/matrix.dart';

import 'settings_calls_view.dart';

class SettingsCalls extends StatefulWidget {
  const SettingsCalls({super.key});

  @override
  SettingsCallsController createState() => SettingsCallsController();
}

class SettingsCallsController extends State<SettingsCalls> {
  void onExperimentalVoipChanged(bool value) {
    Matrix.of(context).createVoipPlugin();
  }

  @override
  Widget build(BuildContext context) => SettingsCallsView(this);
}
