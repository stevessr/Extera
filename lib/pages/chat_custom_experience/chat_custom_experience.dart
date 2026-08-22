import 'package:flutter/material.dart';

import 'chat_custom_experience_view.dart';

/// Hub for the per-room customizations: the profile shown inside this chat,
/// its own wallpaper and its privacy settings.
class ChatCustomExperience extends StatelessWidget {
  final String roomId;

  const ChatCustomExperience({required this.roomId, super.key});

  @override
  Widget build(BuildContext context) => ChatCustomExperienceView(this);
}
