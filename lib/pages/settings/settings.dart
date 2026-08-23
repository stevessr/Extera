import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/clean_exif.dart';
import 'package:extera_next/utils/file_selector.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/crypto_backup_extension.dart';
import 'package:extera_next/utils/avatar_history.dart';
import 'package:extera_next/widgets/avatar_history_picker.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import '../../widgets/matrix.dart';
import 'settings_view.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  SettingsController createState() => SettingsController();
}

class SettingsController extends State<Settings> {
  Future<String?>? aboutFuture;
  bool isQueryingAbout = false;

  // Uri? bannerUrl;
  Future<String?>? bannerFuture;
  bool isQueryingBanner = false;
  bool hasBanner = false;

  Future<String?>? timezoneFuture;
  bool hasTimezone = false;

  Future<String?> _getAbout() async {
    final client = Matrix.of(context).client;
    try {
      final aboutResponse = await client.getProfileField(
        client.userID!,
        AppConfig.aboutProfileField,
      );
      if (aboutResponse.containsKey(AppConfig.aboutProfileField) &&
          aboutResponse[AppConfig.aboutProfileField] is String &&
          aboutResponse[AppConfig.aboutProfileField].toString().length <= 256) {
        return aboutResponse[AppConfig.aboutProfileField].toString();
      }
    } catch (ex) {
      Logs().e("Failed to query About field", ex);
    }
    return null;
  }

  Future<String?> _getBanner() async {
    final client = Matrix.of(context).client;
    try {
      final bannerResponse = await client.getProfileField(
        client.userID!,
        AppConfig.bannerProfileField,
      );
      if (bannerResponse.containsKey((AppConfig.bannerProfileField)) &&
          bannerResponse[AppConfig.bannerProfileField] is String &&
          bannerResponse[AppConfig.bannerProfileField].toString().startsWith(
            'mxc://',
          )) {
        hasBanner = true;
        return bannerResponse.tryGet<String>(AppConfig.bannerProfileField);
      }
    } catch (ex) {
      Logs().e("Failed to query banner field", ex);
    }
    hasBanner = false;
    return null;
  }

  Future<String?> _getTimezone() async {
    final client = Matrix.of(context).client;
    try {
      final response = await client.getProfileField(client.userID!, 'm.tz');
      if (response.containsKey('m.tz') &&
          response['m.tz'] is String &&
          response['m.tz'].toString().isNotEmpty) {
        hasTimezone = true;
        return response['m.tz'].toString();
      }
    } catch (ex) {
      Logs().e("Failed to query timezone field", ex);
    }
    hasTimezone = false;
    return null;
  }

  // bool aboutUpdated = false;

  Future<Profile>? profileFuture;

  void updateProfile() => setState(() {
    // profileUpdated = true;
    profileFuture = null;
  });

  void updateAbout() => setState(() {
    // aboutUpdated = true;
    aboutFuture = null;
  });

  void updateBanner() => setState(() {
    bannerFuture = null;
  });

  void updateTimezone() => setState(() {
    timezoneFuture = null;
  });

  void setAboutAction() async {
    final about = await aboutFuture;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).editAbout,
      message: L10n.of(context).editAboutDescription,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText: about ?? "",
      hintText: L10n.of(context).aboutExample,
      maxLength: 256,
      maxLines: 1,
    );
    if (input == null) return;
    final matrix = Matrix.of(context);
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setProfileField(
        matrix.client.userID!,
        'xyz.extera.about',
        {'xyz.extera.about': input},
      ),
    );
    if (success.error == null) {
      updateAbout();
    }
  }

  void setTimezoneAction() async {
    final currentTz = await timezoneFuture;
    final matrix = Matrix.of(context);

    if (currentTz != null) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () =>
            matrix.client.deleteProfileField(matrix.client.userID!, 'm.tz'),
      );
      if (success.error == null) {
        updateTimezone();
      }
    } else {
      final detectedTz = _detectIanaTimezone();
      final selectedTz = await showDialog<String>(
        context: context,
        useRootNavigator: false,
        builder: (context) =>
            _TimezonePickerDialog(detectedTimezone: detectedTz),
      );
      if (selectedTz == null) return;
      final success = await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.setProfileField(
          matrix.client.userID!,
          'm.tz',
          {'m.tz': selectedTz},
        ),
      );
      if (success.error == null) {
        updateTimezone();
      }
    }
  }

  String? _detectIanaTimezone() {
    final systemName = DateTime.now().timeZoneName;
    try {
      tz.getLocation(systemName);
      return systemName;
    } catch (_) {}
    final localOffset = DateTime.now().timeZoneOffset;
    final now = DateTime.now().toUtc();

    const preferredRegions = [
      'Europe',
      'Asia',
      'America',
      'Africa',
      'Australia',
      'Pacific',
      'Atlantic',
      'Indian',
      'Antarctica',
    ];

    final candidates = <String>[];
    for (final name in tz.timeZoneDatabase.locations.keys) {
      final location = tz.getLocation(name);
      final tzTime = tz.TZDateTime.from(now, location);
      if (tzTime.timeZoneOffset == localOffset) {
        candidates.add(name);
      }
    }

    if (candidates.isEmpty) return null;

    for (final region in preferredRegions) {
      final match = candidates.firstWhereOrNull(
        (name) => name.startsWith('$region/'),
      );
      if (match != null) return match;
    }

    return candidates.first;
  }

  void setCheckForUpdates(bool newValue) {
    AppSettings.checkForUpdates.setItem(newValue);
    setState(() {});
  }

  void setDisplaynameAction() async {
    final profile = await profileFuture;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: L10n.of(context).editDisplayname,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText:
          profile?.displayName ?? Matrix.of(context).client.userID!.localpart,
    );
    if (input == null) return;
    final matrix = Matrix.of(context);
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setProfileField(
        matrix.client.userID!,
        'displayname',
        {'displayname': input},
      ),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  void logoutAction() async {
    final noBackup = showChatBackupBanner == true;
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: L10n.of(context).areYouSureYouWantToLogout,
          message: L10n.of(context).noBackupWarning,
          isDestructive: noBackup,
          okLabel: L10n.of(context).logout,
          cancelLabel: L10n.of(context).cancel,
        ) !=
        OkCancelResult.ok) {
      return;
    }
    final matrix = Matrix.of(context);
    await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.logout(),
    );
  }

  void setAvatarAction() async {
    final profile = await profileFuture;
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: L10n.of(context).openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: L10n.of(context).openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      AdaptiveModalAction(
        value: AvatarAction.history,
        label: L10n.of(context).avatarHistory,
        icon: const Icon(Icons.history_outlined),
      ),
      if (profile?.avatarUrl != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: L10n.of(context).removeYourAvatar,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: L10n.of(context).changeYourAvatar,
            cancelLabel: L10n.of(context).cancel,
            actions: actions,
          );
    if (action == null) return;
    if (action == AvatarAction.history) {
      final mxc = await showAvatarHistoryPicker(context);
      if (mxc == null || !mounted) return;
      final success = await showFutureLoadingDialog(
        context: context,
        future: () async {
          await Matrix.of(context).client.setProfileField(
            Matrix.of(context).client.userID!,
            'avatar_url',
            {'avatar_url': mxc},
          );
          await AvatarHistory.record(mxc);
        },
      );
      if (success.error == null) {
        updateProfile();
      }
      return;
    }
    final matrix = Matrix.of(context);
    if (action == AvatarAction.remove) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.setAvatar(null),
      );
      if (success.error == null) {
        updateProfile();
      }
      return;
    }
    MatrixFile file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == AvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = MatrixFile(
        bytes: Uint8List.fromList(
          ExifCleaner.removeExifData(await result.readAsBytes()),
        ),
        name: result.path,
      );
    } else {
      final result = await selectFiles(context, type: FileType.image);
      final pickedFile = result.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: Uint8List.fromList(
          ExifCleaner.removeExifData(await pickedFile.readAsBytes()),
        ),
        name: pickedFile.name,
      );
    }
    final success = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final mxc = await matrix.client.uploadContent(
          file.bytes,
          filename: file.name,
          contentType: file.mimeType,
        );
        await matrix.client.setProfileField(
          matrix.client.userID!,
          'avatar_url',
          {'avatar_url': mxc.toString()},
        );
        await AvatarHistory.record(mxc.toString());
      },
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  void setBannerAction() async {
    final bannerUrl = await bannerFuture;
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: L10n.of(context).openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: L10n.of(context).openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (bannerUrl != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: L10n.of(context).clearBanner,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: L10n.of(context).changeYourBanner,
            cancelLabel: L10n.of(context).cancel,
            actions: actions,
          );
    if (action == null) return;
    final matrix = Matrix.of(context);
    if (action == AvatarAction.remove) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.deleteProfileField(
          matrix.client.userID!,
          AppConfig.bannerProfileField,
        ),
      );
      if (success.error == null) {
        updateBanner();
      }
      return;
    }
    MatrixFile file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == AvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = MatrixFile(
        bytes: Uint8List.fromList(
          ExifCleaner.removeExifData(await result.readAsBytes()),
        ),
        name: result.path,
      );
    } else {
      final result = await selectFiles(context, type: FileType.image);
      final pickedFile = result.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: Uint8List.fromList(
          ExifCleaner.removeExifData(await pickedFile.readAsBytes()),
        ),
        name: pickedFile.name,
      );
    }
    final success = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final url = await matrix.client.uploadContent(
          file.bytes,
          filename: file.name,
          contentType: file.mimeType,
        );
        await matrix.client.setProfileField(
          matrix.client.userID!,
          AppConfig.bannerProfileField,
          {AppConfig.bannerProfileField: url.toString()},
        );
      },
    );
    if (success.error == null) {
      updateBanner();
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) => checkBootstrap());

    super.initState();
  }

  void checkBootstrap() async {
    final client = Matrix.of(context).client;
    if (!client.encryptionEnabled) return;
    await client.accountDataLoading;
    await client.userDeviceKeysLoading;
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }
    final crossSigning = await client.hasCachedCrossSigningKeys();
    final needsBootstrap =
        await client.encryption?.keyManager.isCached() == false ||
        client.encryption?.crossSigning.enabled == false ||
        crossSigning == false;
    final isUnknownSession = client.isUnknownSession;
    if (!mounted) return;
    setState(() {
      showChatBackupBanner = needsBootstrap || isUnknownSession;
    });
  }

  bool? crossSigningCached;
  bool? showChatBackupBanner;

  void firstRunBootstrapAction([dynamic _]) async {
    if (showChatBackupBanner != true) {
      showOkAlertDialog(
        context: context,
        title: L10n.of(context).chatBackup,
        message: L10n.of(context).onlineKeyBackupEnabled,
        okLabel: L10n.of(context).close,
      );
      return;
    }
    await context.push('/backup');
    checkBootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    profileFuture ??= client.getProfileFromUserId(client.userID!);
    aboutFuture ??= _getAbout();
    bannerFuture ??= _getBanner();
    timezoneFuture ??= _getTimezone();

    return SettingsView(this);
  }
}

enum AvatarAction { camera, file, remove, history }

class _TimezonePickerDialog extends StatefulWidget {
  final String? detectedTimezone;

  const _TimezonePickerDialog({this.detectedTimezone});

  @override
  State<_TimezonePickerDialog> createState() => _TimezonePickerDialogState();
}

class _TimezonePickerDialogState extends State<_TimezonePickerDialog> {
  late String? _selectedTimezone;
  String _searchQuery = '';

  late final List<String> _allTimezones;
  late final Duration _localOffset;
  late final Map<String, Duration> _offsets;

  @override
  void initState() {
    super.initState();
    _selectedTimezone = widget.detectedTimezone;
    _localOffset = DateTime.now().timeZoneOffset;

    final now = DateTime.now().toUtc();
    final locations = tz.timeZoneDatabase.locations.keys.toList();

    _offsets = {
      for (final name in locations)
        name: tz.TZDateTime.from(now, tz.getLocation(name)).timeZoneOffset,
    };

    const preferredRegions = [
      'Europe',
      'Asia',
      'America',
      'Africa',
      'Australia',
      'Pacific',
      'Atlantic',
      'Indian',
      'Antarctica',
    ];

    locations.sort((a, b) {
      final aMatchesOffset = _offsets[a] == _localOffset;
      final bMatchesOffset = _offsets[b] == _localOffset;
      if (aMatchesOffset != bMatchesOffset) {
        return aMatchesOffset ? -1 : 1;
      }

      final aRegion = a.split('/').first;
      final bRegion = b.split('/').first;
      final aIndex = preferredRegions.indexOf(aRegion);
      final bIndex = preferredRegions.indexOf(bRegion);
      final aPriority = aIndex == -1 ? preferredRegions.length : aIndex;
      final bPriority = bIndex == -1 ? preferredRegions.length : bIndex;
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);
      return a.compareTo(b);
    });
    _allTimezones = locations;
  }

  List<String> get _filteredTimezones {
    if (_searchQuery.isEmpty) return _allTimezones;
    final query = _searchQuery.toLowerCase();
    return _allTimezones
        .where((tz) => tz.toLowerCase().contains(query))
        .toList();
  }

  String _formatOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredTimezones;

    return AlertDialog(
      title: Text(L10n.of(context).publishTimezone),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 450),
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.detectedTimezone != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    L10n.of(
                      context,
                    ).publishTimezoneConfirmation(widget.detectedTimezone!),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              TextField(
                decoration: InputDecoration(
                  hintText: L10n.of(context).search,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RadioGroup<String>(
                  groupValue: _selectedTimezone ?? '',
                  onChanged: (value) {
                    setState(() => _selectedTimezone = value);
                  },
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final tzName = filtered[index];
                      final offset = _offsets[tzName] ?? Duration.zero;
                      return RadioListTile<String>(
                        title: Text(
                          tzName,
                          style: const TextStyle(fontSize: 14),
                        ),
                        secondary: Text(
                          _formatOffset(offset),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        value: tzName,
                        dense: true,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24.0),
            ),
          ),
          onPressed: () => Navigator.of(context).pop<String>(null),
          child: Text(L10n.of(context).cancel),
        ),
        FilledButton(
          onPressed: _selectedTimezone != null
              ? () => Navigator.of(context).pop<String>(_selectedTimezone)
              : null,
          child: Text(L10n.of(context).ok),
        ),
      ],
    );
  }
}
