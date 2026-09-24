import 'dart:core';

import 'package:flutter/foundation.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/utils/platform_infos.dart';

import '../widgets/matrix.dart';

/// Sound engine for LiveKit calls: ringtone playback for incoming calls
/// (delegated by LiveKitIncomingCallManager), ringtone preview in settings,
/// and short sound effects (e.g. mute/unmute feedback).
class VoipPlugin {
  final MatrixState matrix;
  Client get client => matrix.client;
  VoipPlugin(this.matrix);

  AudioPlayer? callSoundPlayer;

  Future<void> playRingtone() async {
    try {
      if (AppSettings.ringtone.value == 'system') {
        FlutterRingtonePlayer().playRingtone(looping: true);
      } else if (kIsWeb ||
          PlatformInfos.isMobile ||
          PlatformInfos.isMacOS ||
          PlatformInfos.isLinux) {
        final player = callSoundPlayer = AudioPlayer(playerId: 'ringtone');
        player.setReleaseMode(ReleaseMode.loop);
        player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              audioMode: AndroidAudioMode.ringtone,
              usageType: AndroidUsageType.notificationRingtone,
            ),
          ),
        );
        player.play(
          AssetSource(AppConfig.ringtoneFiles[AppSettings.ringtone.value]!),
        );
      }
    } catch (ex) {
      Logs().e("Failed to play ringtone", ex);
    }
  }

  Future<void> stopRingtone() async {
    try {
      Logs().w("Stopping ringtone");
      if (AppSettings.ringtone.value == 'system') {
        FlutterRingtonePlayer().stop();
      } else {
        await callSoundPlayer?.stop();
        await callSoundPlayer?.release();
        await callSoundPlayer?.dispose();
        callSoundPlayer = null;
      }
    } catch (ex) {
      Logs().e("Failed to stop ringtone", ex);
    }
  }

  AudioPlayer? sfxPlayer;

  Future<void> playSoundEffect(String name) async {
    try {
      Logs().w("Playing $name call sfx");
      final path = 'sounds/$name.ogg';
      if (kIsWeb ||
          PlatformInfos.isMobile ||
          PlatformInfos.isMacOS ||
          PlatformInfos.isLinux) {
        final player = sfxPlayer = AudioPlayer(playerId: 'sfx');
        player.setReleaseMode(ReleaseMode.release);
        player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              audioMode: AndroidAudioMode.inCall,
              usageType: AndroidUsageType.voiceCommunication,
            ),
          ),
        );
        player.play(AssetSource(path));
      } else {
        Logs().w('Playing sound not implemented for this platform!');
      }
    } catch (e) {
      Logs().e("Failed to play sound effect", e);
    }
  }

  Future<void> stopCallingSound() async {
    if (callSoundPlayer != null) {
      await callSoundPlayer?.stop();
      await callSoundPlayer?.dispose();
      callSoundPlayer = null;
    }
    if (sfxPlayer != null) {
      await sfxPlayer?.stop();
      await sfxPlayer?.dispose();
      sfxPlayer = null;
    }
    stopRingtone();
  }
}
