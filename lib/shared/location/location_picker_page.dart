import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_env.dart';
import '../../config/theme/app_colors.dart';
import '../maps/yango_map_widget.dart';

class LocationAddressDetails {
  final LatLng position;
  final String formattedAddress;
  final String? neighborhood;
  final String? city;
  final String? street;
  final String? route;
  final String? streetNumber;
  final String? suggestedReference;

  const LocationAddressDetails({
    required this.position,
    required this.formattedAddress,
    this.neighborhood,
    this.city,
    this.street,
    this.route,
    this.streetNumber,
    this.suggestedReference,
  });
}

class LocationPickerPage extends StatefulWidget {
  final LatLng initialPosition;
  final String title;
  final String confirmLabel;
  final bool useCurrentLocationOnStart;

  const LocationPickerPage({
    super.key,
    required this.initialPosition,
    this.title = 'Confirmar localizacao',
    this.confirmLabel = 'Confirmar localizacao',
    this.useCurrentLocationOnStart = false,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  DeligoMapController? _mapController;
  late LatLng _cameraTarget;
  LocationAddressDetails? _details;
  bool _loadingAddress = false;
  int _lookupToken = 0;

  @override
  void initState() {
    super.initState();
    _cameraTarget = widget.initialPosition;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.useCurrentLocationOnStart) {
        await _moveToCurrentLocation();
      } else {
        await _refreshAddress();
      }
    });
  }

  Future<void> _moveToCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permita a localizacao para usar a posicao atual.'),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final target = LatLng(position.latitude, position.longitude);
      _cameraTarget = target;
      await _mapController?.animateTo(target, zoom: 17);
      await _refreshAddress();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel obter a localizacao atual agora.'),
        ),
      );
    }
  }

  Future<void> _refreshAddress() async {
    final token = ++_lookupToken;
    setState(() => _loadingAddress = true);
    final details = await reverseGeocodeGoogle(_cameraTarget);
    if (!mounted || token != _lookupToken) return;
    setState(() {
      _details = details;
      _loadingAddress = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final address = _details?.formattedAddress.trim();
    final subtitle = [
      if (_details?.neighborhood?.trim().isNotEmpty == true)
        _details!.neighborhood!.trim(),
      if (_details?.city?.trim().isNotEmpty == true) _details!.city!.trim(),
    ].join(' • ');

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          YangoMapWidget(
            initialCameraPosition: CameraPosition(
              target: widget.initialPosition,
              zoom: 16,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onCameraMove: (position) {
              _cameraTarget = position.target;
            },
            onCameraIdle: _refreshAddress,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_pin,
                        color: AppColors.primaryRed,
                        size: 42,
                      ),
                    ),
                    Container(
                      width: 4,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 210,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _moveToCurrentLocation,
                icon: const Icon(
                  Icons.my_location_rounded,
                  color: AppColors.primaryRed,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 28,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.primaryRed.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.place_outlined,
                              color: AppColors.primaryRed,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Endereco detectado',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.neutralGray,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (address != null && address.isNotEmpty)
                                      ? address
                                      : 'Mova o mapa para detectar o endereco',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                  ),
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(
                                      color: AppColors.neutralGray,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_loadingAddress)
                            const Padding(
                              padding: EdgeInsets.only(left: 8, top: 6),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loadingAddress
                              ? null
                              : () {
                                  Navigator.of(context).pop(
                                    _details ??
                                        LocationAddressDetails(
                                          position: _cameraTarget,
                                          formattedAddress: '',
                                        ),
                                  );
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text(widget.confirmLabel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<LocationAddressDetails?> reverseGeocodeGoogle(LatLng position) async {
  final nominatim = await _reverseGeocodeNominatim(position);
  if (nominatim != null &&
      ((nominatim.neighborhood ?? '').trim().isNotEmpty ||
          (nominatim.city ?? '').trim().isNotEmpty)) {
    return nominatim;
  }

  final key = AppEnv.googleMapsApiKey.isNotEmpty
      ? AppEnv.googleMapsApiKey
      : AppEnv.firebaseWebApiKey;
  if (key.isEmpty) return null;

  final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
    'latlng': '${position.latitude},${position.longitude}',
    'key': key,
  });

  try {
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final results = (data['results'] as List?)?.cast<Map<String, dynamic>>();
    if (results == null || results.isEmpty) return null;

    final first = results.first;
    final rawFormatted = first['formatted_address']?.toString().trim() ?? '';

    String? neighborhood;
    String? city;
    String? route;
    String? streetNumber;
    String? premise;
    String? pointOfInterest;

    for (final result in results) {
      final components =
          (result['address_components'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];
      for (final component in components) {
        final types = (component['types'] as List?)?.cast<String>() ?? const [];
        final value = component['long_name']?.toString().trim();
        if (value == null || value.isEmpty) continue;

        if (neighborhood == null &&
            (types.contains('neighborhood') ||
                types.contains('sublocality') ||
                types.contains('sublocality_level_1'))) {
          neighborhood = value;
        }
        if (city == null &&
            (types.contains('locality') ||
                types.contains('administrative_area_level_2') ||
                types.contains('administrative_area_level_1'))) {
          city = value;
        }
        if (route == null && types.contains('route')) {
          route = value;
        }
        if (streetNumber == null && types.contains('street_number')) {
          streetNumber = value;
        }
        if (pointOfInterest == null && types.contains('point_of_interest')) {
          pointOfInterest = value;
        }
        if (premise == null &&
            (types.contains('premise') || types.contains('establishment'))) {
          premise = value;
        }
      }
    }

    final street = route == null
        ? null
        : streetNumber == null
        ? route
        : '$route, $streetNumber';

    final composedAddressParts = <String>[
      if ((street ?? '').trim().isNotEmpty) street!.trim(),
      if ((neighborhood ?? '').trim().isNotEmpty) neighborhood!.trim(),
      if ((city ?? '').trim().isNotEmpty) city!.trim(),
    ];

    final formatted = composedAddressParts.isNotEmpty
        ? composedAddressParts.join(', ')
        : rawFormatted;

    return LocationAddressDetails(
      position: position,
      formattedAddress: formatted,
      neighborhood: neighborhood,
      city: city,
      street: street,
      route: route,
      streetNumber: streetNumber,
      suggestedReference: pointOfInterest ?? premise,
    );
  } catch (_) {
    return null;
  }
}

Future<LocationAddressDetails?> _reverseGeocodeNominatim(
  LatLng position,
) async {
  try {
    if (Supabase.instance.client.auth.currentSession == null) return null;
    final response = await Supabase.instance.client.functions
        .invoke(
          'maps-gateway',
          body: {
            'action': 'reverse',
            'latitude': position.latitude,
            'longitude': position.longitude,
          },
        )
        .timeout(const Duration(seconds: 8));
    final data = response.data;
    if (response.status != 200 || data is! Map) return null;
    // The gateway normally returns {results: [...]}, but keep this tolerant of
    // the common wrapped shape {data: {results: [...]}} so the UI does not
    // silently lose the address when the edge function adds an envelope.
    final payload = data['data'] is Map ? data['data'] as Map : data;
    final results = payload['results'];
    if (results is! List || results.isEmpty || results.first is! Map) {
      return null;
    }

    final first = results.first as Map;
    final address = first['address'] is Map
        ? first['address'] as Map
        : const {};
    String? value(List<String> keys) {
      for (final key in keys) {
        final candidate = address[key]?.toString().trim();
        if (candidate?.isNotEmpty == true) return candidate;
      }
      return null;
    }

    final route = value(['road', 'pedestrian', 'footway']);
    final streetNumber = value(['house_number']);
    final neighborhood = value([
      'suburb',
      'neighbourhood',
      'quarter',
      'city_district',
    ]);
    final city = value(['city', 'town', 'village', 'municipality', 'state']);
    final street = route == null
        ? null
        : streetNumber == null
        ? route
        : '$route, $streetNumber';
    final formatted = first['display_name']?.toString().trim() ?? '';
    // A valid reverse-geocode result can occasionally omit display_name while
    // still providing road/city fields. Keep it usable instead of discarding
    // it and leaving all three restaurant fields blank.
    final fallbackFormatted = [
      street,
      neighborhood,
      city,
    ].where((part) => part != null && part.trim().isNotEmpty).join(', ');
    if (formatted.isEmpty && fallbackFormatted.isEmpty) return null;

    return LocationAddressDetails(
      position: position,
      formattedAddress: formatted.isNotEmpty ? formatted : fallbackFormatted,
      neighborhood: neighborhood,
      city: city,
      street: street,
      route: route,
      streetNumber: streetNumber,
      suggestedReference: value(['amenity', 'shop', 'tourism', 'building']),
    );
  } catch (_) {
    return null;
  }
}
