import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../config/theme/app_colors.dart';

class DeligoMapController {
  final GoogleMapController _controller;

  const DeligoMapController(this._controller);

  Future<ScreenCoordinate> getScreenCoordinate(LatLng position) async {
    return _controller.getScreenCoordinate(position);
  }

  Future<void> animateTo(
    LatLng target, {
    double? zoom,
    double? bearing,
    double? tilt,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    return _controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: zoom ?? 15,
          bearing: bearing ?? 0,
          tilt: tilt ?? 0,
        ),
      ),
    );
  }

  Future<void> fitLatLngBounds(LatLngBounds bounds, {double padding = 64}) {
    return _controller.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, padding),
    );
  }

  void dispose() {
    _controller.dispose();
  }
}

class YangoMapWidget extends StatefulWidget {
  static const String cleanMapStyle = 'clean';
  static const String deliveryFocusMapStyle = 'delivery';

  static const String osmRasterStyle = '''
{
  "version": 8,
  "name": "DeliGo Map",
  "sources": {
    "osm": {
      "type": "raster",
      "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      "tileSize": 256,
      "attribution": "© OpenStreetMap contributors",
      "maxzoom": 19
    }
  },
  "layers": [
    {"id": "background", "type": "background", "paint": {"background-color": "#f4f6f5"}},
    {"id": "osm", "type": "raster", "source": "osm", "paint": {"raster-saturation": -0.12, "raster-contrast": 0.04}}
  ]
}
''';

  final CameraPosition initialCameraPosition;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final bool zoomControlsEnabled;
  final bool mapToolbarEnabled;
  final bool trafficEnabled;
  final bool compassEnabled;
  final EdgeInsets padding;
  final VoidCallback? onCurrentLocationPressed;
  final VoidCallback? onFollowToggle;
  final bool showCurrentLocationButton;
  final bool showFollowButton;
  final bool followEnabled;
  final bool eagerGestureHandling;
  final String mapStyle;
  final void Function(DeligoMapController controller)? onMapCreated;
  final VoidCallback? onCameraMoveStarted;
  final void Function(CameraPosition position)? onCameraMove;
  final VoidCallback? onCameraIdle;
  final void Function(LatLng position)? onTap;
  final List<Widget> overlayChildren;

  const YangoMapWidget({
    super.key,
    required this.initialCameraPosition,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.circles = const <Circle>{},
    this.myLocationEnabled = false,
    this.myLocationButtonEnabled = false,
    this.zoomControlsEnabled = false,
    this.mapToolbarEnabled = false,
    this.trafficEnabled = false,
    this.compassEnabled = false,
    this.padding = EdgeInsets.zero,
    this.onCurrentLocationPressed,
    this.onFollowToggle,
    this.showCurrentLocationButton = false,
    this.showFollowButton = false,
    this.followEnabled = false,
    this.eagerGestureHandling = false,
    this.mapStyle = cleanMapStyle,
    this.onMapCreated,
    this.onCameraMoveStarted,
    this.onCameraMove,
    this.onCameraIdle,
    this.onTap,
    this.overlayChildren = const <Widget>[],
  });

  @override
  State<YangoMapWidget> createState() => _YangoMapWidgetState();
}

class _YangoMapWidgetState extends State<YangoMapWidget> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: widget.initialCameraPosition,
          markers: widget.markers,
          polylines: widget.polylines,
          circles: widget.circles,
          myLocationEnabled: widget.myLocationEnabled,
          myLocationButtonEnabled: widget.myLocationButtonEnabled,
          zoomControlsEnabled: widget.zoomControlsEnabled,
          mapToolbarEnabled: widget.mapToolbarEnabled,
          trafficEnabled: widget.trafficEnabled,
          compassEnabled: widget.compassEnabled,
          padding: widget.padding,
          gestureRecognizers: widget.eagerGestureHandling
              ? <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    EagerGestureRecognizer.new,
                  ),
                }
              : <Factory<OneSequenceGestureRecognizer>>{},
          onMapCreated: (controller) {
            widget.onMapCreated?.call(DeligoMapController(controller));
          },
          onCameraMoveStarted: widget.onCameraMoveStarted,
          onTap: widget.onTap,
          onCameraMove: widget.onCameraMove,
          onCameraIdle: widget.onCameraIdle,
        ),
        if (widget.showCurrentLocationButton || widget.showFollowButton)
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showFollowButton)
                  _MapActionButton(
                    icon: Icons.navigation_rounded,
                    active: widget.followEnabled,
                    onPressed: widget.onFollowToggle,
                  ),
                if (widget.showFollowButton && widget.showCurrentLocationButton)
                  const SizedBox(height: 10),
                if (widget.showCurrentLocationButton)
                  _MapActionButton(
                    icon: Icons.my_location_rounded,
                    active: false,
                    onPressed: widget.onCurrentLocationPressed,
                  ),
              ],
            ),
          ),
        ...widget.overlayChildren,
      ],
    );
  }
}

class _MapActionButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  const _MapActionButton({
    required this.icon,
    required this.active,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? const Color(0xFF111B21) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: IconButton(
        tooltip: active ? 'Desativar seguimento' : 'Localização',
        onPressed: onPressed,
        icon: Icon(icon, color: active ? Colors.white : AppColors.primaryRed),
      ),
    );
  }
}
