import 'package:material_ui/material_ui.dart';

import 'package:go_router/go_router.dart';

import 'settings_multiple_emotes_view.dart';

class MultipleEmotesSettings extends StatefulWidget {
  const MultipleEmotesSettings({super.key});

  @override
  MultipleEmotesSettingsController createState() =>
      MultipleEmotesSettingsController();
}

class MultipleEmotesSettingsController extends State<MultipleEmotesSettings> {
  String? get roomId => GoRouterState.of(context).pathParameters['roomid'];
  @override
  Widget build(BuildContext context) => MultipleEmotesSettingsView(this);
}
