import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/events/map_bubble.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';

class SendLocationDialog extends StatefulWidget {
  final Room room;
  final Thread? thread;
  final Event? replyEvent;

  const SendLocationDialog({
    required this.room,
    required this.thread,
    this.replyEvent,
    super.key,
  });

  @override
  SendLocationDialogState createState() => SendLocationDialogState();
}

class SendLocationDialogState extends State<SendLocationDialog> {
  bool disabled = false;
  bool denied = false;
  bool isSending = false;
  Position? position;
  Object? error;

  @override
  void initState() {
    super.initState();
    requestLocation();
  }

  Future<void> requestLocation() async {
    error = null;
    if (!(await Geolocator.isLocationServiceEnabled())) {
      setState(() => disabled = true);
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => denied = true);
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      setState(() => denied = true);
      return;
    }
    try {
      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
      } on TimeoutException {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 5),
          ),
        );
      }
      setState(() => this.position = position);
    } catch (e) {
      setState(() => error = e);
    }
  }

  void sendAction() async {
    setState(() => isSending = true);
    final body =
        'https://www.openstreetmap.org/?mlat=${position!.latitude}&mlon=${position!.longitude}#map=16/${position!.latitude}/${position!.longitude}';
    final uri =
        'geo:${position!.latitude},${position!.longitude};u=${position!.accuracy}';
    final threadRootEventId = widget.thread?.rootEvent.eventId;
    final lastThreadEvent = widget.thread?.lastEvent;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => widget.room.sendEvent(
        {'msgtype': 'm.location', 'body': body, 'geo_uri': uri},
        inReplyTo: widget.replyEvent,
        threadRootEventId: threadRootEventId,
        threadLastEventId:
            lastThreadEvent != null && lastThreadEvent.status.isSynced
            ? lastThreadEvent.eventId
            : threadRootEventId,
      ),
    );
    if (!mounted || result.isError) return;
    Navigator.of(context, rootNavigator: false).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Widget contentWidget;
    if (position != null) {
      contentWidget = MapBubble(
        latitude: position!.latitude,
        longitude: position!.longitude,
      );
    } else if (disabled) {
      contentWidget = Text(L10n.of(context).locationDisabledNotice);
    } else if (denied) {
      contentWidget = Text(L10n.of(context).locationPermissionDeniedNotice);
    } else if (error != null) {
      contentWidget = Text(
        L10n.of(context).errorObtainingLocation(error.toString()),
      );
    } else {
      contentWidget = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator.adaptive(),
          const SizedBox(width: 12),
          Text(L10n.of(context).obtainingLocation),
        ],
      );
    }
    return AlertDialog.adaptive(
      title: Text(L10n.of(context).shareLocation),
      content: contentWidget,
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24.0),
            ),
          ),
          onPressed: Navigator.of(context, rootNavigator: false).pop,
          child: Text(L10n.of(context).cancel),
        ),
        if (error != null)
          FilledButton(
            onPressed: requestLocation,
            child: Text(L10n.of(context).retry),
          ),
        if (position != null)
          FilledButton(
            onPressed: isSending ? null : sendAction,
            child: Text(L10n.of(context).send),
          ),
      ],
    );
  }
}
