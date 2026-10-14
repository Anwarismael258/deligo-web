import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_env.dart';

class MapsRouteService {
  static final Map<String, RouteInfo> _routeCache = <String, RouteInfo>{};
  static final Map<String, RoutePlan> _routePlanCache = <String, RoutePlan>{};
  static final Map<String, Future<RoutePlan>> _routePlanInFlight =
      <String, Future<RoutePlan>>{};

  static Future<RoutePlan> getCachedRoutePlan({
    required String cacheKey,
    required LatLng origin,
    required LatLng destination,
    String travelMode = 'driving',
  }) {
    final key =
        '$cacheKey:${origin.latitude.toStringAsFixed(5)},'
        '${origin.longitude.toStringAsFixed(5)}:${destination.latitude.toStringAsFixed(5)},'
        '${destination.longitude.toStringAsFixed(5)}:$travelMode';
    final cached = _routePlanCache[key];
    if (cached != null) return Future.value(cached);
    return _routePlanInFlight.putIfAbsent(key, () async {
      try {
        final resolved = await _resolveRoute(
          origin: origin,
          destination: destination,
          travelMode: travelMode,
        );
        final plan = RoutePlan(points: resolved.points, info: resolved.info);
        _routePlanCache[key] = plan;
        return plan;
      } finally {
        _routePlanInFlight.remove(key);
      }
    });
  }

  static Future<RouteInfo?> getCachedRouteInfo({
    required String cacheKey,
    required LatLng origin,
    required LatLng destination,
    String travelMode = 'driving',
  }) async {
    final key =
        '$cacheKey:${origin.latitude.toStringAsFixed(5)},'
        '${origin.longitude.toStringAsFixed(5)}:${destination.latitude.toStringAsFixed(5)},'
        '${destination.longitude.toStringAsFixed(5)}:$travelMode';
    final cached = _routeCache[key];
    if (cached != null) return cached;
    final info = await getRouteInfo(
      origin: origin,
      destination: destination,
      travelMode: travelMode,
    );
    if (info != null) _routeCache[key] = info;
    return info;
  }

  static void clearCachedRoutes() {
    _routeCache.clear();
    _routePlanCache.clear();
  }

  static Future<RouteInfo?> getRouteInfo({
    required LatLng origin,
    required LatLng destination,
    String? apiKey,
    String travelMode = 'driving',
  }) async {
    final route = await _resolveRoute(
      origin: origin,
      destination: destination,
      apiKey: apiKey,
      travelMode: travelMode,
    );
    return route.info;
  }

  static Future<List<LatLng>> getRoute({
    required LatLng origin,
    required LatLng destination,
    String? apiKey,
    String travelMode = 'driving',
  }) async {
    final route = await _resolveRoute(
      origin: origin,
      destination: destination,
      apiKey: apiKey,
      travelMode: travelMode,
    );
    return route.points;
  }

  static Future<_ResolvedRoute> _resolveRoute({
    required LatLng origin,
    required LatLng destination,
    String? apiKey,
    required String travelMode,
  }) async {
    final graphHopperRoute = await _fetchGraphHopperRoute(
      origin: origin,
      destination: destination,
      travelMode: travelMode,
    );
    if (graphHopperRoute != null) return graphHopperRoute;

    final osrmRoute = await _fetchOsrmRoute(
      origin: origin,
      destination: destination,
      travelMode: travelMode,
    );
    if (osrmRoute != null) return osrmRoute;

    final googleRoute = await _fetchGoogleRoute(
      origin: origin,
      destination: destination,
      apiKey: apiKey,
      travelMode: travelMode,
    );
    if (googleRoute != null) return googleRoute;

    return _ResolvedRoute(
      points: _fallbackRoute(origin, destination),
      info: _fallbackRouteInfo(origin, destination),
    );
  }

  static Future<_ResolvedRoute?> _fetchGraphHopperRoute({
    required LatLng origin,
    required LatLng destination,
    required String travelMode,
  }) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        _logFallback('graphhopper', 'missing_session');
        return null;
      }

      final response = await Supabase.instance.client.functions
          .invoke(
            'maps-gateway',
            body: {
              'action': 'route',
              'origin_lat': origin.latitude,
              'origin_lng': origin.longitude,
              'destination_lat': destination.latitude,
              'destination_lng': destination.longitude,
              'travel_mode': travelMode,
            },
          )
          .timeout(const Duration(seconds: 10));
      final data = response.data;
      if (response.status != 200 || data is! Map) {
        _logFallback('graphhopper', 'http_error', httpStatus: response.status);
        return null;
      }

      final rawPoints = data['points'];
      if (rawPoints is! List || rawPoints.length < 2) {
        _logFallback('graphhopper', 'missing_geometry');
        return null;
      }

      final points = <LatLng>[];
      for (final rawPoint in rawPoints) {
        if (rawPoint is! Map) continue;
        final lat = (rawPoint['latitude'] as num?)?.toDouble();
        final lng = (rawPoint['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) points.add(LatLng(lat, lng));
      }
      if (points.length < 2) return null;

      debugPrint(
        'MapsRouteService graphhopper success: '
        'mode=$travelMode, points=${points.length}',
      );
      return _ResolvedRoute(
        points: points,
        info: RouteInfo(
          distanceMeters: (data['distance_meters'] as num?)?.round(),
          durationSeconds: (data['duration_seconds'] as num?)?.round(),
        ),
      );
    } catch (error) {
      _logFallback('graphhopper', 'exception', errorMessage: error.toString());
      return null;
    }
  }

  static Future<_ResolvedRoute?> _fetchGoogleRoute({
    required LatLng origin,
    required LatLng destination,
    String? apiKey,
    required String travelMode,
  }) async {
    final key = _resolveApiKey(apiKey);
    if (key.isEmpty) {
      _logFallback('google', 'missing_api_key');
      return null;
    }

    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': travelMode,
      'key': key,
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        _logFallback('google', 'http_error', httpStatus: response.statusCode);
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final apiStatus = data['status']?.toString() ?? '';
      final errorMessage = data['error_message']?.toString();
      if (apiStatus.isNotEmpty && apiStatus != 'OK') {
        _logFallback(
          'google',
          'api_status_not_ok',
          apiStatus: apiStatus,
          errorMessage: errorMessage,
        );
        return null;
      }

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        _logFallback(
          'google',
          'no_routes',
          apiStatus: apiStatus,
          errorMessage: errorMessage,
        );
        return null;
      }

      final firstRoute = routes.first as Map<String, dynamic>;
      final polyline = firstRoute['overview_polyline'] as Map<String, dynamic>?;
      final encodedPoints = polyline?['points'] as String?;
      if (encodedPoints == null || encodedPoints.isEmpty) {
        _logFallback(
          'google',
          'missing_polyline',
          apiStatus: apiStatus,
          errorMessage: errorMessage,
        );
        return null;
      }

      final legs = firstRoute['legs'] as List?;
      final leg = legs != null && legs.isNotEmpty
          ? legs.first as Map<String, dynamic>
          : null;
      final distance = (leg?['distance'] as Map?)?['value'] as num?;
      final duration = (leg?['duration'] as Map?)?['value'] as num?;
      debugPrint(
        'MapsRouteService google success: routes=${routes.length}, mode=$travelMode',
      );

      return _ResolvedRoute(
        points: _decodePolyline(encodedPoints),
        info: RouteInfo(
          distanceMeters: distance?.toInt(),
          durationSeconds: duration?.toInt(),
        ),
      );
    } catch (error) {
      _logFallback('google', 'exception', errorMessage: error.toString());
      return null;
    }
  }

  static Future<_ResolvedRoute?> _fetchOsrmRoute({
    required LatLng origin,
    required LatLng destination,
    required String travelMode,
  }) async {
    final profile = _osrmProfileFor(travelMode);
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/'
      '$profile/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        _logFallback('osrm', 'http_error', httpStatus: response.statusCode);
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final code = data['code']?.toString() ?? '';
      final message = data['message']?.toString();
      if (code.isNotEmpty && code != 'Ok') {
        _logFallback(
          'osrm',
          'api_status_not_ok',
          apiStatus: code,
          errorMessage: message,
        );
        return null;
      }

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        _logFallback(
          'osrm',
          'no_routes',
          apiStatus: code,
          errorMessage: message,
        );
        return null;
      }

      final firstRoute = routes.first as Map<String, dynamic>;
      final distance = (firstRoute['distance'] as num?)?.toDouble();
      final duration = (firstRoute['duration'] as num?)?.toDouble();
      final steps = <RouteInstruction>[];
      final legs = firstRoute['legs'] as List?;
      final rawSteps = legs != null && legs.isNotEmpty
          ? ((legs.first as Map?)?['steps'] as List?)
          : null;
      for (final rawStep in rawSteps ?? const []) {
        if (rawStep is! Map) continue;
        final maneuver = rawStep['maneuver'] as Map?;
        final type = maneuver?['type']?.toString() ?? '';
        final modifier = maneuver?['modifier']?.toString() ?? '';
        final name = rawStep['name']?.toString().trim() ?? '';
        final meters = (rawStep['distance'] as num?)?.round();
        if (type.isEmpty) continue;
        steps.add(
          RouteInstruction(
            type: type,
            modifier: modifier,
            streetName: name,
            distanceMeters: meters,
          ),
        );
      }
      final geometry = firstRoute['geometry'] as Map<String, dynamic>?;
      final coordinates = geometry?['coordinates'] as List?;
      if (coordinates == null || coordinates.isEmpty) {
        _logFallback(
          'osrm',
          'missing_geometry',
          apiStatus: code,
          errorMessage: message,
        );
        return null;
      }

      final points = <LatLng>[];
      for (final coordinate in coordinates) {
        if (coordinate is! List || coordinate.length < 2) continue;
        final lon = (coordinate[0] as num?)?.toDouble();
        final lat = (coordinate[1] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        points.add(LatLng(lat, lon));
      }

      if (points.isEmpty) {
        _logFallback(
          'osrm',
          'empty_points',
          apiStatus: code,
          errorMessage: message,
        );
        return null;
      }

      debugPrint(
        'MapsRouteService osrm success: routes=${routes.length}, profile=$profile, points=${points.length}',
      );

      return _ResolvedRoute(
        points: points,
        info: RouteInfo(
          distanceMeters: distance?.round(),
          durationSeconds: duration?.round(),
          instructions: steps,
        ),
      );
    } catch (error) {
      _logFallback('osrm', 'exception', errorMessage: error.toString());
      return null;
    }
  }

  static String _resolveApiKey(String? apiKey) {
    if (apiKey?.trim().isNotEmpty == true) {
      return apiKey!.trim();
    }
    if (AppEnv.googleMapsApiKey.isNotEmpty) {
      return AppEnv.googleMapsApiKey;
    }
    return AppEnv.firebaseWebApiKey;
  }

  static String _osrmProfileFor(String travelMode) {
    switch (travelMode.trim().toLowerCase()) {
      case 'walking':
        return 'foot';
      case 'bicycling':
        return 'bike';
      case 'driving':
      default:
        return 'driving';
    }
  }

  static void _logFallback(
    String provider,
    String reason, {
    int? httpStatus,
    String? apiStatus,
    String? errorMessage,
  }) {
    debugPrint(
      'MapsRouteService fallback from $provider: '
      'reason=$reason'
      '${httpStatus != null ? ', httpStatus=$httpStatus' : ''}'
      '${apiStatus != null && apiStatus.isNotEmpty ? ', apiStatus=$apiStatus' : ''}'
      '${errorMessage != null && errorMessage.isNotEmpty ? ', error=$errorMessage' : ''}',
    );
  }

  static RouteInfo? _fallbackRouteInfo(LatLng origin, LatLng destination) {
    final distanceMeters = _distanceMeters(origin, destination).round();
    if (distanceMeters <= 0) return null;

    const assumedUrbanSpeedMetersPerSecond = 7.5;
    final durationSeconds = math.max(
      60,
      (distanceMeters / assumedUrbanSpeedMetersPerSecond).round(),
    );
    return RouteInfo(
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      isFallback: true,
    );
  }

  static List<LatLng> _fallbackRoute(LatLng origin, LatLng destination) {
    if (!_hasMeaningfulSeparation(origin, destination)) {
      return const <LatLng>[];
    }
    return <LatLng>[origin, destination];
  }

  static bool _hasMeaningfulSeparation(LatLng origin, LatLng destination) {
    return (origin.latitude - destination.latitude).abs() > 0.00001 ||
        (origin.longitude - destination.longitude).abs() > 0.00001;
  }

  static double _distanceMeters(LatLng origin, LatLng destination) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = _toRadians(origin.latitude);
    final lat2 = _toRadians(destination.latitude);
    final dLat = _toRadians(destination.latitude - origin.latitude);
    final dLng = _toRadians(destination.longitude - origin.longitude);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _toRadians(double degrees) => degrees * (math.pi / 180);

  static List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }
}

class RouteInfo {
  final int? distanceMeters;
  final int? durationSeconds;
  final bool isFallback;
  final List<RouteInstruction> instructions;

  const RouteInfo({
    this.distanceMeters,
    this.durationSeconds,
    this.isFallback = false,
    this.instructions = const <RouteInstruction>[],
  });
}

class RouteInstruction {
  final String type;
  final String modifier;
  final String streetName;
  final int? distanceMeters;

  const RouteInstruction({
    required this.type,
    required this.modifier,
    required this.streetName,
    required this.distanceMeters,
  });
}

class RoutePlan {
  final List<LatLng> points;
  final RouteInfo? info;

  const RoutePlan({required this.points, required this.info});

  bool get isFallback => info?.isFallback ?? true;
}

class DeliveryEstimate {
  final RouteInfo route;
  final int preparationMinutes;
  final int operationalMarginMinutes;

  const DeliveryEstimate({
    required this.route,
    required this.preparationMinutes,
    this.operationalMarginMinutes = 5,
  });

  int get totalMinutes =>
      preparationMinutes +
      ((route.durationSeconds ?? 0) / 60).ceil() +
      operationalMarginMinutes;
}

class _ResolvedRoute {
  final List<LatLng> points;
  final RouteInfo? info;

  const _ResolvedRoute({required this.points, required this.info});
}
