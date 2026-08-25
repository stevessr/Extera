import 'package:flutter/material.dart';

import 'package:flutter_map/flutter_map.dart' deferred as fm;
import 'package:latlong2/latlong.dart';

import 'package:extera_next/utils/platform_infos.dart';

class MapBubble extends StatefulWidget {
  final double latitude;
  final double longitude;
  final double zoom;
  final double width;
  final double height;
  final double radius;
  const MapBubble({
    required this.latitude,
    required this.longitude,
    this.zoom = 14.0,
    this.width = 400,
    this.height = 400,
    this.radius = 10.0,
    super.key,
  });

  @override
  State<MapBubble> createState() => _MapBubbleState();
}

class _MapBubbleState extends State<MapBubble> {
  late final Future<void> _libraryLoad = fm.loadLibrary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const .all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        clipBehavior: .hardEdge,
        child: Container(
          constraints: BoxConstraints.loose(Size(widget.width, widget.height)),
          child: AspectRatio(
            aspectRatio: widget.width / widget.height,
            child: Stack(
              children: <Widget>[
                FutureBuilder<void>(
                  future: _libraryLoad,
                  // Native builds compile deferred libraries in eagerly, so
                  // the placeholder only ever shows for a frame there; on
                  // the web the map chunk stays out of the startup bundle
                  // until a location message renders.
                  builder: (context, snapshot) =>
                      snapshot.connectionState != ConnectionState.done
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : _buildMap(),
                ),
                Container(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    ' © OpenStreetMap contributors ',
                    style: TextStyle(
                      color: theme.brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                      backgroundColor: theme.appBarTheme.backgroundColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    return fm.FlutterMap(
      options: fm.MapOptions(
        initialCenter: LatLng(widget.latitude, widget.longitude),
        initialZoom: widget.zoom,
        interactionOptions: fm.InteractionOptions(
          flags: fm.InteractiveFlag.none,
        ),
      ),
      children: [
        fm.TileLayer(
          maxZoom: 20,
          minZoom: 0,
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: '${PlatformInfos.clientName} (flutter_map)',
        ),
        fm.MarkerLayer(
          rotate: true,
          markers: [
            fm.Marker(
              point: LatLng(widget.latitude, widget.longitude),
              width: 30,
              height: 30,
              child: Transform.translate(
                // No idea why the offset has to be like this, instead of -15
                // It has been determined by trying out, though, that this yields
                // the tip of the location pin to be static when zooming.
                // Might have to do with psychological perception of where the tip exactly is
                offset: const Offset(0, -12.5),
                child: const Icon(
                  Icons.location_pin,
                  color: Colors.red,
                  size: 30,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
