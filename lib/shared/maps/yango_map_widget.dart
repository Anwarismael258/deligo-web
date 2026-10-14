import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart' as ll;

import '../../config/theme/app_colors.dart';

class DeligoMapController {
  final gmap.GoogleMapController? _google;
  final fmap.MapController? _web;
  const DeligoMapController.google(this._google) : _web = null;
  const DeligoMapController.web(this._web) : _google = null;

  Future<gmap.ScreenCoordinate> getScreenCoordinate(gmap.LatLng position) async {
    if (_google != null) return _google.getScreenCoordinate(position);
    return const gmap.ScreenCoordinate(x: 0, y: 0);
  }

  Future<void> animateTo(gmap.LatLng target, {double? zoom, double? bearing, double? tilt, EdgeInsets padding = EdgeInsets.zero}) async {
    if (_google != null) {
      await _google.animateCamera(gmap.CameraUpdate.newCameraPosition(gmap.CameraPosition(target: target, zoom: zoom ?? 15, bearing: bearing ?? 0, tilt: tilt ?? 0)));
      return;
    }
    _web?.move(ll.LatLng(target.latitude, target.longitude), zoom ?? 15);
  }

  Future<void> fitLatLngBounds(gmap.LatLngBounds bounds, {double padding = 64}) async {
    if (_google != null) {
      await _google.animateCamera(gmap.CameraUpdate.newLatLngBounds(bounds, padding));
      return;
    }
    _web?.fitCamera(fmap.CameraFit.bounds(bounds: fmap.LatLngBounds(ll.LatLng(bounds.southwest.latitude, bounds.southwest.longitude), ll.LatLng(bounds.northeast.latitude, bounds.northeast.longitude)), padding: EdgeInsets.all(padding)));
  }

  void dispose() => _google?.dispose();
}

class YangoMapWidget extends StatefulWidget {
  static const String cleanMapStyle = 'clean';
  static const String deliveryFocusMapStyle = 'delivery';
  final gmap.CameraPosition initialCameraPosition;
  final Set<gmap.Marker> markers;
  final Set<gmap.Polyline> polylines;
  final Set<gmap.Circle> circles;
  final bool myLocationEnabled, myLocationButtonEnabled, zoomControlsEnabled, mapToolbarEnabled, trafficEnabled, compassEnabled;
  final EdgeInsets padding;
  final VoidCallback? onCurrentLocationPressed, onFollowToggle;
  final bool showCurrentLocationButton, showFollowButton, followEnabled, eagerGestureHandling;
  final String mapStyle;
  final void Function(DeligoMapController controller)? onMapCreated;
  final VoidCallback? onCameraMoveStarted, onCameraIdle;
  final void Function(gmap.CameraPosition position)? onCameraMove;
  final void Function(gmap.LatLng position)? onTap;
  final List<Widget> overlayChildren;

  const YangoMapWidget({super.key, required this.initialCameraPosition, this.markers = const <gmap.Marker>{}, this.polylines = const <gmap.Polyline>{}, this.circles = const <gmap.Circle>{}, this.myLocationEnabled = false, this.myLocationButtonEnabled = false, this.zoomControlsEnabled = false, this.mapToolbarEnabled = false, this.trafficEnabled = false, this.compassEnabled = false, this.padding = EdgeInsets.zero, this.onCurrentLocationPressed, this.onFollowToggle, this.showCurrentLocationButton = false, this.showFollowButton = false, this.followEnabled = false, this.eagerGestureHandling = false, this.mapStyle = cleanMapStyle, this.onMapCreated, this.onCameraMoveStarted, this.onCameraMove, this.onCameraIdle, this.onTap, this.overlayChildren = const <Widget>[]});
  @override State<YangoMapWidget> createState() => _YangoMapWidgetState();
}

class _YangoMapWidgetState extends State<YangoMapWidget> {
  final fmap.MapController _webController = fmap.MapController();

  @override Widget build(BuildContext context) {
    final map = kIsWeb ? _buildWebMap() : _buildGoogleMap();
    return Stack(children: [map, if (widget.showCurrentLocationButton || widget.showFollowButton) Positioned(right: 16, bottom: 16, child: Column(mainAxisSize: MainAxisSize.min, children: [if (widget.showFollowButton) _MapActionButton(icon: Icons.navigation_rounded, active: widget.followEnabled, onPressed: widget.onFollowToggle), if (widget.showFollowButton && widget.showCurrentLocationButton) const SizedBox(height: 10), if (widget.showCurrentLocationButton) _MapActionButton(icon: Icons.my_location_rounded, active: false, onPressed: widget.onCurrentLocationPressed)])), ...widget.overlayChildren]);
  }

  Widget _buildGoogleMap() => gmap.GoogleMap(initialCameraPosition: widget.initialCameraPosition, markers: widget.markers, polylines: widget.polylines, circles: widget.circles, myLocationEnabled: widget.myLocationEnabled, myLocationButtonEnabled: widget.myLocationButtonEnabled, zoomControlsEnabled: widget.zoomControlsEnabled, mapToolbarEnabled: widget.mapToolbarEnabled, trafficEnabled: widget.trafficEnabled, compassEnabled: widget.compassEnabled, padding: widget.padding, gestureRecognizers: widget.eagerGestureHandling ? <Factory<OneSequenceGestureRecognizer>>{Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)} : <Factory<OneSequenceGestureRecognizer>>{}, onMapCreated: (c) => widget.onMapCreated?.call(DeligoMapController.google(c)), onCameraMoveStarted: widget.onCameraMoveStarted, onTap: widget.onTap, onCameraMove: widget.onCameraMove, onCameraIdle: widget.onCameraIdle);

  Widget _buildWebMap() {
    final center = ll.LatLng(widget.initialCameraPosition.target.latitude, widget.initialCameraPosition.target.longitude);
    const key = String.fromEnvironment('MAPTILER_KEY');
    final tiles = key.isNotEmpty ? 'https://api.maptiler.com/maps/streets/{z}/{x}/{y}.png?key=$key' : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    return fmap.FlutterMap(mapController: _webController, options: fmap.MapOptions(initialCenter: center, initialZoom: widget.initialCameraPosition.zoom, onMapReady: () => widget.onMapCreated?.call(DeligoMapController.web(_webController)), onTap: (_, p) => widget.onTap?.call(gmap.LatLng(p.latitude, p.longitude))), children: [fmap.TileLayer(urlTemplate: tiles, userAgentPackageName: 'com.deligo.app'), fmap.PolylineLayer(polylines: widget.polylines.map((line) => fmap.Polyline(points: line.points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList(), color: line.color, strokeWidth: line.width.toDouble().clamp(1, 12))).toList()), fmap.CircleLayer(circles: widget.circles.map((c) => fmap.CircleMarker(point: ll.LatLng(c.center.latitude, c.center.longitude), radius: c.radius, useRadiusInMeter: true, color: c.fillColor, borderColor: c.strokeColor, borderStrokeWidth: c.strokeWidth.toDouble())).toList()), fmap.MarkerLayer(markers: widget.markers.map((m) => fmap.Marker(point: ll.LatLng(m.position.latitude, m.position.longitude), width: 48, height: 48, child: _marker(m))).toList())]);
  }

  Widget _marker(gmap.Marker marker) { final id = marker.markerId.value.toLowerCase(); final color = id.contains('courier') || id.contains('driver') ? AppColors.primaryRed : id.contains('restaurant') ? Colors.orange : Colors.blueAccent; return DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)]), child: const Icon(Icons.location_on, color: Colors.white, size: 30)); }
}

class _MapActionButton extends StatelessWidget {
  final IconData icon; final bool active; final VoidCallback? onPressed;
  const _MapActionButton({required this.icon, required this.active, this.onPressed});
  @override Widget build(BuildContext context) => DecoratedBox(decoration: BoxDecoration(color: active ? const Color(0xFF111B21) : Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 6))]), child: IconButton(tooltip: active ? 'Desativar seguimento' : 'Localização', onPressed: onPressed, icon: Icon(icon, color: active ? Colors.white : AppColors.primaryRed)));
}
