import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:geocoding/geocoding.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme/app_colors.dart';
import '../../services/order_service.dart';
import '../../services/app_voice_service.dart';
import '../../services/sound_controller.dart';
import '../../shared/maps/yango_map_widget.dart';
import '../../shared/utils/location_display.dart';
import '../../shared/utils/maps_route.dart';
import '../../shared/utils/deligo_viewport.dart';
import '../../shared/widgets/order_chat_button.dart';
import 'tracking_provider.dart';

class TrackingMapPage extends StatefulWidget {
  final String orderId;
  final String viewerRole;
  final bool embedded;

  const TrackingMapPage({
    super.key,
    required this.orderId,
    this.viewerRole = 'client',
    this.embedded = false,
  });

  @override
  State<TrackingMapPage> createState() => _TrackingMapPageState();
}

class _TrackingMapPageState extends State<TrackingMapPage> {
  static const Duration _popupDuration = Duration(milliseconds: 1000);

  final OrderService _orderService = OrderService();
  final SupabaseClient _supabase = Supabase.instance.client;
  DeligoMapController? mapController;
  RealtimeChannel? _notificationsChannel;
  bool _followCourier = true;
  RouteInfo? _routeInfo;
  BitmapDescriptor? _courierMarkerIcon;
  BitmapDescriptor? _restaurantMarkerIcon;
  BitmapDescriptor? _clientMarkerIcon;

  double _restaurantLat = -25.9655;
  double _restaurantLng = 32.5832;
  double _deliveryLat = -25.9695;
  double _deliveryLng = 32.5732;
  double? _courierLat;
  double? _courierLng;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Circle> _circles = {};
  List<LatLng> _routePoints = [];
  List<LatLng> _animatedRoutePoints = [];
  Timer? _routeAnimationTimer;
  Timer? _mapFallbackTimer;
  int _routeAnimationIndex = 0;
  DateTime? _lastRouteAt;
  LatLng? _lastRouteOrigin;
  LatLng? _lastRouteDest;
  String _routePhase = 'to_restaurant';
  String? _lastStatus;
  final Set<String> _notifiedStatuses = {};
  LatLng? _lastAnimatedCourierLatLng;
  LatLng? _lastProviderCourierLatLng;
  int _courierAnimationToken = 0;
  bool _clientPanelsHidden = false;
  bool _mapReady = false;
  bool _mapFallbackVisible = false;

  String _restaurantPlace = 'Restaurante';
  String _deliveryPlace = 'Destino do cliente';
  String _courierPlace = 'Ainda sem estafeta atribuido';
  String _restaurantName = 'Restaurante';
  final List<_RippleEntry> _ripples = [];
  int _rippleColorIndex = 0;

  bool get _isCourierView => widget.viewerRole == 'courier';

  bool _shouldAutoHideClientPanels(TrackingProvider provider) {
    if (_isCourierView || !_hasAssignedCourier(provider)) return false;
    switch (provider.status) {
      case 'assigned':
      case 'at_restaurant':
      case 'in_transit':
      case 'arrived':
      case 'delivered':
      case 'completed':
      case 'delivery_failed_otp':
        return true;
      default:
        return false;
    }
  }

  Future<void> _callCourier(String? rawPhone) async {
    final phone = rawPhone?.trim();
    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O contacto do estafeta ainda nao esta disponivel.'),
        ),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    final launched = await launchUrl(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel ligar para $phone agora.')),
      );
    }
  }

  Future<void> _callExternalContact(
    String? rawPhone, {
    required String label,
  }) async {
    final phone = rawPhone?.trim();
    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Numero do $label indisponivel.')));
      return;
    }

    final uri = Uri(
      scheme: 'tel',
      path: phone.replaceAll(RegExp(r'[^0-9+]'), ''),
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel ligar para o $label agora.')),
      );
    }
  }

  void _showSearchingInfoSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D7DE),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.search_rounded,
                    color: Colors.orange,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'A procurar estafeta',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Deligo esta a procurar estafetas proximos do restaurante para recolher o teu pedido. Assim que um estafeta aceitar, vais ver o nome, a foto e o contacto aqui.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Color(0xFF54656F),
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoPoint(
                  icon: Icons.notifications_active_outlined,
                  text:
                      'Recebes atualizacao assim que houver estafeta atribuido.',
                ),
                const SizedBox(height: 10),
                _buildInfoPoint(
                  icon: Icons.map_outlined,
                  text: 'O mapa fica mais limpo para veres melhor o percurso.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCourierDetailsSheet(TrackingProvider provider) {
    final courierName = (provider.courierName?.trim().isNotEmpty ?? false)
        ? provider.courierName!.trim()
        : 'Estafeta atribuido';
    final phone = provider.courierPhone?.trim();
    final avatarUrl = provider.courierAvatarUrl?.trim();
    final courierPlace = (_courierLat != null && _courierLng != null)
        ? _courierPlace
        : _fallbackCourierPlace(provider);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D7DE),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _buildCourierAvatar(
                      avatarUrl: avatarUrl,
                      name: courierName,
                      radius: 34,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Estafeta atribuido',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            courierName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (phone != null && phone.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              phone,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF54656F),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildCourierInfoCard(
                  icon: Icons.place_outlined,
                  label: 'Ultima localizacao',
                  value: courierPlace,
                ),
                const SizedBox(height: 10),
                _buildCourierInfoCard(
                  icon: Icons.storefront_outlined,
                  label: 'Restaurante',
                  value: _restaurantStopValue(),
                ),
                const SizedBox(height: 10),
                _buildCourierInfoCard(
                  icon: Icons.flag_outlined,
                  label: 'Entrega',
                  value: _deliveryPlace,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _callCourier(phone),
                        icon: const Icon(Icons.phone),
                        label: const Text('Ligar'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF111B21),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OrderChatButton(
                        orderId: widget.orderId,
                        onPressed: () {
                          Navigator.of(context).pop();
                          this.context.push('/chat/${widget.orderId}');
                        },
                        label: 'Chat',
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF111B21),
                          side: const BorderSide(color: Color(0xFFCCD3DA)),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // O cliente deve poder explorar o mapa livremente. O acompanhamento
    // automático continua disponível pelo botão de centralizar/seguir.
    _followCourier = _isCourierView;
    // A device without Google Play Services may never invoke onMapCreated.
    // Keep tracking usable and expose a clear fallback instead of leaving a
    // blank/blocked surface indefinitely.
    _mapFallbackTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _mapReady) return;
      setState(() => _mapFallbackVisible = true);
    });
    unawaited(_loadMarkerIcons());
    unawaited(_subscribeRealtimeNotifications());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeTracking();
      unawaited(_loadOrderPresentationData());
    });
  }

  @override
  void dispose() {
    _routeAnimationTimer?.cancel();
    _mapFallbackTimer?.cancel();
    _notificationsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _subscribeRealtimeNotifications() async {
    await _notificationsChannel?.unsubscribe();
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    _notificationsChannel = _supabase
        .channel('tracking-notifications-${widget.orderId}-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'push_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted || payload.newRecord.isEmpty) return;
            final notification = Map<String, dynamic>.from(payload.newRecord);
            if (!_notificationMatchesOrder(notification)) return;
            _handleRealtimeNotification(notification);
          },
        )
        .subscribe();
  }

  bool _notificationMatchesOrder(Map<String, dynamic> notification) {
    final entityId = notification['entity_id']?.toString().trim() ?? '';
    if (entityId == widget.orderId) return true;

    final directOrderId = notification['order_id']?.toString().trim() ?? '';
    if (directOrderId == widget.orderId) return true;

    final metadata = notification['metadata'];
    if (metadata is Map &&
        metadata['order_id']?.toString().trim() == widget.orderId) {
      return true;
    }

    final data = notification['data'];
    if (data is Map && data['order_id']?.toString().trim() == widget.orderId) {
      return true;
    }

    return false;
  }

  void _handleRealtimeNotification(Map<String, dynamic> notification) {
    final rawType = notification['type']?.toString().trim() ?? '';
    if (rawType != 'DRIVER_AT_RESTAURANT') return;

    final provider = context.read<TrackingProvider>();
    if (provider.status == 'delivered' ||
        provider.status == 'completed' ||
        provider.status == 'delivery_failed_otp') {
      return;
    }

    provider.markCourierAtRestaurant();
  }

  Future<void> _loadMarkerIcons() async {
    final icons = await Future.wait([
      _loadSmallMarkerIcon('assets/markers/restaurant.png'),
      _loadSmallMarkerIcon('assets/markers/client.png'),
      _loadSmallMarkerIcon('assets/markers/delivery.png'),
    ]);

    _restaurantMarkerIcon =
        icons[0] ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    _clientMarkerIcon =
        icons[1] ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    _courierMarkerIcon =
        icons[2] ??
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);

    if (!mounted) return;
    setState(_updateMarkers);
  }

  Future<BitmapDescriptor?> _loadSmallMarkerIcon(
    String assetPath, {
    int size = 44,
  }) async {
    try {
      final data = await rootBundle.load(assetPath);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: size,
        targetHeight: size,
      );
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (bytes == null) return null;
      return BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
    } catch (error) {
      debugPrint('Falha ao carregar marcador $assetPath: $error');
      return null;
    }
  }

  void _initializeTracking() {
    final provider = context.read<TrackingProvider>();

    if (provider.restaurantLatitude != null) {
      _restaurantLat = provider.restaurantLatitude!;
    }
    if (provider.restaurantLongitude != null) {
      _restaurantLng = provider.restaurantLongitude!;
    }
    if (provider.deliveryLatitude != null) {
      _deliveryLat = provider.deliveryLatitude!;
    }
    if (provider.deliveryLongitude != null) {
      _deliveryLng = provider.deliveryLongitude!;
    }
    if (provider.courierLatitude != null) {
      _courierLat = provider.courierLatitude;
    }
    if (provider.courierLongitude != null) {
      _courierLng = provider.courierLongitude;
    }
    if (_courierLat != null && _courierLng != null) {
      _lastAnimatedCourierLatLng = LatLng(_courierLat!, _courierLng!);
      _lastProviderCourierLatLng = LatLng(_courierLat!, _courierLng!);
    }

    if (!provider.isTracking) {
      provider.startTracking(
        orderId: widget.orderId,
        restaurantLat: _restaurantLat,
        restaurantLng: _restaurantLng,
        deliveryLat: _deliveryLat,
        deliveryLng: _deliveryLng,
      );
    }

    _updateMarkers();
    _refreshRoute();
    _refreshPlaceLabels();
    setState(() {});
  }

  Future<void> _loadOrderPresentationData() async {
    final order = await _orderService.getOrderById(widget.orderId);
    if (!mounted || order == null) return;

    final restaurantFallback = LocationDisplay.displayAddress(
      address: order.restaurantAddress,
      neighborhood: order.restaurantNeighborhood,
      city: order.restaurantCity,
      fallback: 'Local do restaurante confirmado no mapa',
    );
    final deliveryFallback = LocationDisplay.displayAddress(
      address: order.deliveryAddress,
      fallback: 'Destino do cliente confirmado no mapa',
    );

    setState(() {
      if (order.pickupLatitude != null) {
        _restaurantLat = order.pickupLatitude!;
      } else if (order.restaurantLatitude != null) {
        _restaurantLat = order.restaurantLatitude!;
      }
      if (order.pickupLongitude != null) {
        _restaurantLng = order.pickupLongitude!;
      } else if (order.restaurantLongitude != null) {
        _restaurantLng = order.restaurantLongitude!;
      }
      if (order.deliveryLatitude != null) {
        _deliveryLat = order.deliveryLatitude!;
      }
      if (order.deliveryLongitude != null) {
        _deliveryLng = order.deliveryLongitude!;
      }
      if (order.restaurantName?.trim().isNotEmpty == true) {
        _restaurantName = order.restaurantName!.trim();
      }
      _restaurantPlace = restaurantFallback;
      _deliveryPlace = deliveryFallback;
      _updateMarkers();
    });

    await _refreshPlaceLabels();
    await _refreshRoute(force: true);
  }

  Future<void> _refreshPlaceLabels() async {
    final provider = context.read<TrackingProvider>();
    final restaurantFuture = _resolvePlaceName(
      _restaurantLat,
      _restaurantLng,
      fallbackLabel: LocationDisplay.displayAddress(
        address: provider.restaurantAddress ?? _restaurantPlace,
        fallback: _restaurantPlace,
      ),
    );
    final deliveryFuture = _resolvePlaceName(
      _deliveryLat,
      _deliveryLng,
      fallbackLabel: LocationDisplay.displayAddress(
        address: provider.deliveryAddress ?? _deliveryPlace,
        fallback: _deliveryPlace,
      ),
    );
    final courierFuture = (_courierLat != null && _courierLng != null)
        ? _resolvePlaceName(
            _courierLat!,
            _courierLng!,
            fallbackLabel: _fallbackCourierPlace(provider),
          )
        : Future.value(_fallbackCourierPlace(provider));

    final results = await Future.wait([
      restaurantFuture,
      deliveryFuture,
      courierFuture,
    ]);

    if (!mounted) return;
    setState(() {
      _restaurantPlace = results[0];
      _deliveryPlace = results[1];
      _courierPlace = results[2];
    });
  }

  Future<String> _resolvePlaceName(
    double lat,
    double lng, {
    required String fallbackLabel,
  }) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return _coordsLabel(fallbackLabel);
      final p = placemarks.first;
      final parts = <String>[
        if ((p.street ?? '').trim().isNotEmpty) p.street!.trim(),
        if ((p.subLocality ?? '').trim().isNotEmpty) p.subLocality!.trim(),
        if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
      ];
      if (parts.isEmpty) return _coordsLabel(fallbackLabel);
      return parts.take(2).join(', ');
    } catch (_) {
      return _coordsLabel(fallbackLabel);
    }
  }

  String _coordsLabel(String fallbackLabel) {
    final sanitized = fallbackLabel.trim();
    if (sanitized.isNotEmpty &&
        sanitized != 'Restaurante' &&
        sanitized != 'Destino do cliente') {
      return sanitized;
    }
    return 'Localizacao confirmada no mapa';
  }

  bool _hasAssignedCourier(TrackingProvider provider) {
    final courierId = provider.courierId?.trim() ?? '';
    return courierId.isNotEmpty;
  }

  String _fallbackCourierPlace(TrackingProvider provider) {
    if (provider.status == 'at_restaurant') {
      return 'Estafeta ja esta no restaurante';
    }
    if (_hasAssignedCourier(provider)) {
      return 'Estafeta atribuido, localizacao a atualizar';
    }
    return provider.status == 'searching'
        ? 'Ainda sem estafeta atribuido'
        : 'Aguardando dados reais do estafeta';
  }

  void _updateMarkers() {
    _markers = {
      Marker(
        markerId: const MarkerId('restaurant'),
        position: LatLng(_restaurantLat, _restaurantLng),
        infoWindow: InfoWindow(
          title: _restaurantName,
          snippet: _restaurantPlace,
        ),
        icon:
            _restaurantMarkerIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      Marker(
        markerId: const MarkerId('delivery'),
        position: LatLng(_deliveryLat, _deliveryLng),
        infoWindow: InfoWindow(title: 'Cliente', snippet: _deliveryPlace),
        icon:
            _clientMarkerIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    };

    if (_courierLat != null && _courierLng != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('courier'),
          position: LatLng(_courierLat!, _courierLng!),
          infoWindow: InfoWindow(title: 'Estafeta', snippet: _courierPlace),
          anchor: const Offset(0.5, 0.5),
          flat: true,
          rotation: _computeCourierBearing(),
          icon:
              _courierMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    _updateCircles();
  }

  void _updateCircles() {
    /* final circles = <Circle>{
      Circle(
        circleId: const CircleId('restaurant_zone'),
        center: LatLng(_restaurantLat, _restaurantLng),
        radius: 110,
        fillColor: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
        strokeColor: const Color(0xFF0EA5E9).withValues(alpha: 0.35),
        strokeWidth: 2,
      ),
      Circle(
        circleId: const CircleId('delivery_zone'),
        center: LatLng(_deliveryLat, _deliveryLng),
        radius: 110,
        fillColor: const Color(0xFF22C55E).withValues(alpha: 0.12),
        strokeColor: const Color(0xFF22C55E).withValues(alpha: 0.35),
        strokeWidth: 2,
      ),
    };

    if (_courierLat != null && _courierLng != null) {
      circles.addAll({
        Circle(
          circleId: const CircleId('courier_glow'),
          center: LatLng(_courierLat!, _courierLng!),
          radius: 90,
          fillColor: AppColors.primaryRed.withValues(alpha: 0.08),
          strokeColor: AppColors.primaryRed.withValues(alpha: 0.20),
          strokeWidth: 1,
        ),
        Circle(
          circleId: const CircleId('courier_core'),
          center: LatLng(_courierLat!, _courierLng!),
          radius: 42,
          fillColor: AppColors.primaryRed.withValues(alpha: 0.18),
          strokeColor: AppColors.primaryRed.withValues(alpha: 0.42),
          strokeWidth: 2,
        ),
      });
    }

    _circles = circles; */
    // Keep only functional markers; accuracy circles and glows are decorative
    // and imply a GPS precision the backend may not currently have.
    _circles = const <Circle>{};
  }

  double _computeCourierBearing() {
    if (_lastAnimatedCourierLatLng == null ||
        _courierLat == null ||
        _courierLng == null) {
      return 0;
    }
    final previous = _lastAnimatedCourierLatLng!;
    final current = LatLng(_courierLat!, _courierLng!);
    final dx = current.longitude - previous.longitude;
    final dy = current.latitude - previous.latitude;
    if (dx == 0 && dy == 0) return 0;
    final angle = math.atan2(dy, dx);
    final bearing = (90 - angle * 180 / math.pi) % 360;
    return bearing.isNaN ? 0 : bearing.toDouble();
  }

  List<Color> get _rippleColors => const [
    AppColors.primaryGreen,
    AppColors.deepBlack,
    AppColors.accentYellow,
    AppColors.primaryRed,
  ];

  void _handleMapTap(LatLng position) {
    // Native map gestures remain enabled; customer taps do not create
    // decorative overlays.
  }

  Future<void> _spawnRipple(LatLng position) async {
    if (mapController == null) return;
    final screen = await mapController!.getScreenCoordinate(position);
    final color = _rippleColors[_rippleColorIndex];
    _rippleColorIndex = (_rippleColorIndex + 1) % _rippleColors.length;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    if (!mounted) return;
    setState(() {
      _ripples.add(
        _RippleEntry(
          id: id,
          dx: screen.x.toDouble(),
          dy: screen.y.toDouble(),
          color: color,
        ),
      );
    });
  }

  void _removeRipple(String id) {
    if (!mounted) return;
    setState(() {
      _ripples.removeWhere((entry) => entry.id == id);
    });
  }

  Widget _buildRippleWidget(_RippleEntry entry) {
    return Positioned(
      left: entry.dx - 60,
      top: entry.dy - 60,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 120),
        duration: const Duration(milliseconds: 600),
        builder: (context, size, child) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.color.withValues(alpha: 0.28),
            ),
          );
        },
        onEnd: () => _removeRipple(entry.id),
      ),
    );
  }

  void _applyRoutePolylines() {
    if (_routePoints.isEmpty) {
      _polylines = {};
      return;
    }

    final livePoints = _animatedRoutePoints.length >= 2
        ? _animatedRoutePoints
        : _routePoints;

    _polylines = {
      Polyline(
        polylineId: const PolylineId('route'),
        color: AppColors.primaryRed,
        width: 6,
        points: livePoints,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  void _startRouteAnimation() {
    _routeAnimationTimer?.cancel();
    // Draw the real road geometry immediately. Progressive line animation
    // looks artificial and is misleading on slow or stale GPS updates.
    _animatedRoutePoints = _routePoints;
    _applyRoutePolylines();
  }

  Future<void> _refreshRoute({bool force = false}) async {
    final trackingStatus = context.read<TrackingProvider>().status;
    if (trackingStatus == 'delivered' || trackingStatus == 'completed') {
      _routeAnimationTimer?.cancel();
      if (mounted) {
        setState(() {
          _routePoints = const <LatLng>[];
          _animatedRoutePoints = const <LatLng>[];
          _polylines = const <Polyline>{};
        });
      }
      return;
    }

    final origin = (_courierLat != null && _courierLng != null)
        ? LatLng(_courierLat!, _courierLng!)
        : LatLng(_restaurantLat, _restaurantLng);
    final dest = _routePhase == 'to_restaurant'
        ? LatLng(_restaurantLat, _restaurantLng)
        : LatLng(_deliveryLat, _deliveryLng);

    final originMovedMeters = _lastRouteOrigin == null
        ? double.infinity
        : _distanceMeters(_lastRouteOrigin!, origin);
    if (_lastRouteOrigin != null &&
        _lastRouteDest != null &&
        _lastRouteDest == dest &&
        _lastRouteAt != null &&
        originMovedMeters < 250 &&
        DateTime.now().difference(_lastRouteAt!).inSeconds < 90 &&
        !force) {
      return;
    }

    final points = await MapsRouteService.getRoute(
      origin: origin,
      destination: dest,
    );
    final routeInfo = await MapsRouteService.getRouteInfo(
      origin: origin,
      destination: dest,
    );

    if (!mounted) return;
    setState(() {
      _lastRouteAt = DateTime.now();
      _lastRouteOrigin = origin;
      _lastRouteDest = dest;
      _routeInfo = routeInfo;
      _routePoints = points;
      _applyRoutePolylines();
    });
    _startRouteAnimation();
    final minutes = routeInfo?.durationSeconds != null
        ? (routeInfo!.durationSeconds! / 60).ceil()
        : null;
    if (minutes != null) {
      context.read<TrackingProvider>().setEstimatedTime(minutes);
    }
  }

  Future<void> _followCourierCamera() async {
    if (!_followCourier || mapController == null) {
      return;
    }
    await _applyPhaseCamera();
  }

  Future<void> _applyPhaseCamera() async {
    if (mapController == null) return;
    LatLng? anchorA;
    LatLng? anchorB;

    if (_routePhase == 'to_restaurant') {
      anchorA = (_courierLat != null && _courierLng != null)
          ? LatLng(_courierLat!, _courierLng!)
          : LatLng(_restaurantLat, _restaurantLng);
      anchorB = LatLng(_restaurantLat, _restaurantLng);
    } else {
      anchorA = (_courierLat != null && _courierLng != null)
          ? LatLng(_courierLat!, _courierLng!)
          : LatLng(_restaurantLat, _restaurantLng);
      anchorB = LatLng(_deliveryLat, _deliveryLng);
    }

    _lastAnimatedCourierLatLng = anchorA;
    final latDelta = (anchorA.latitude - anchorB.latitude).abs();
    final lngDelta = (anchorA.longitude - anchorB.longitude).abs();
    if (latDelta < 0.00005 && lngDelta < 0.00005) {
      await mapController!.animateTo(anchorA, zoom: 16.6);
      return;
    }
    final southWest = LatLng(
      math.min(anchorA.latitude, anchorB.latitude),
      math.min(anchorA.longitude, anchorB.longitude),
    );
    final northEast = LatLng(
      math.max(anchorA.latitude, anchorB.latitude),
      math.max(anchorA.longitude, anchorB.longitude),
    );
    final bounds = LatLngBounds(southwest: southWest, northeast: northEast);
    await mapController!.fitLatLngBounds(bounds, padding: 80);
  }

  Future<void> _animateCourierTo(double targetLat, double targetLng) async {
    // Use the last backend-confirmed point directly. Interpolating between
    // points can display movement that never happened, especially after a
    // delayed Realtime event or a background resume.
    if (!mounted) return;
    _courierAnimationToken++;
    setState(() {
      _courierLat = targetLat;
      _courierLng = targetLng;
      _updateMarkers();
    });
    await _followCourierCamera();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = DeligoViewport.fromSize(MediaQuery.sizeOf(context));
    return Scaffold(
      backgroundColor: const Color(0xFFF4F1EB),
      body: Consumer<TrackingProvider>(
        builder: (context, provider, child) {
          if (_lastStatus != provider.status) {
            _lastStatus = provider.status;
            _routePhase = _resolvePhase(provider.status);
            if (!_isCourierView) {
              _clientPanelsHidden = _shouldAutoHideClientPanels(provider);
            }
            unawaited(_refreshRoute(force: true));
            unawaited(_followCourierCamera());
            _notifyStatus(provider.status);
          }

          if (provider.courierLatitude != null &&
              provider.courierLongitude != null) {
            final incoming = LatLng(
              provider.courierLatitude!,
              provider.courierLongitude!,
            );
            final changed =
                _lastProviderCourierLatLng == null ||
                _lastProviderCourierLatLng!.latitude != incoming.latitude ||
                _lastProviderCourierLatLng!.longitude != incoming.longitude;
            if (changed) {
              _lastProviderCourierLatLng = incoming;
              unawaited(
                _animateCourierTo(incoming.latitude, incoming.longitude),
              );
              unawaited(_refreshRoute());
              unawaited(_refreshPlaceLabels());
            }
          }

          double centerLat = (_restaurantLat + _deliveryLat) / 2;
          double centerLng = (_restaurantLng + _deliveryLng) / 2;

          if (_courierLat != null && _courierLng != null) {
            centerLat = (_restaurantLat + _deliveryLat + _courierLat!) / 3;
            centerLng = (_restaurantLng + _deliveryLng + _courierLng!) / 3;
          }

          return Stack(
            children: [
              Positioned.fill(
                child: YangoMapWidget(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(centerLat, centerLng),
                    zoom: 16.2,
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  circles: _circles,
                  mapStyle: YangoMapWidget.deliveryFocusMapStyle,
                  onTap: _handleMapTap,
                  overlayChildren: const <Widget>[],
                  onMapCreated: (controller) {
                    if (mounted) {
                      _mapFallbackTimer?.cancel();
                      setState(() {
                        _mapReady = true;
                        _mapFallbackVisible = false;
                      });
                    }
                    mapController = controller;
                    _followCourierCamera();
                  },
                  onCameraMoveStarted: _isCourierView
                      ? null
                      : () {
                          if (!mounted || !_followCourier) return;
                          setState(() => _followCourier = false);
                        },
                  myLocationEnabled: false,
                  compassEnabled: true,
                  mapToolbarEnabled: false,
                  zoomControlsEnabled: false,
                  trafficEnabled: true,
                  myLocationButtonEnabled: false,
                  eagerGestureHandling: true,
                ),
              ),
              if (_mapFallbackVisible)
                Positioned(
                  left: 16,
                  right: 16,
                  top: _isCourierView ? 82 : 116,
                  child: _buildMapFallbackCard(),
                ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: _isCourierView || _clientPanelsHidden
                        ? 120
                        : (provider.status == 'assigned' &&
                                  _hasAssignedCourier(provider)
                              ? 136
                              : 190),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.34),
                          Colors.black.withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 18,
                left: 16,
                right: 16,
                child: _isCourierView
                    ? _buildCourierMapHud(provider)
                    : _clientPanelsHidden
                    ? Row(
                        children: [
                          _buildTopIconButton(
                            icon: Icons.arrow_back_rounded,
                            onTap: () => context.pop(),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _buildTopBar(provider),
                          const SizedBox(height: 12),
                          _buildClientStatusCard(provider),
                        ],
                      ),
              ),
              Positioned(
                right: 16,
                bottom: _isCourierView ? 24 : (_clientPanelsHidden ? 24 : 156),
                child: _isCourierView
                    ? _buildCourierMapActionRail(provider)
                    : _buildClientMapActionRail(),
              ),
              if (!_isCourierView && !_clientPanelsHidden)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DeligoViewportScrollArea(
                    maxHeightFraction: viewport.isCompact ? 0.68 : 0.72,
                    child: _buildBottomPanel(provider),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMapFallbackCard() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          children: [
            Icon(Icons.map_outlined, color: AppColors.primaryRed),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mapa indisponível neste dispositivo. O acompanhamento continua ativo; verifique os Serviços do Google Play.',
                style: TextStyle(
                  color: Color(0xFF1F2937),
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourierMapHud(TrackingProvider provider) {
    final meta = <String>[
      if (provider.estimatedTime != null) '${provider.estimatedTime} min',
      if (_routeInfo?.distanceMeters != null)
        '${(_routeInfo!.distanceMeters! / 1000).toStringAsFixed(1)} km',
    ].join('  •  ');

    return Row(
      children: [
        _buildTopIconButton(
          icon: Icons.arrow_back_rounded,
          onTap: () => context.pop(),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _courierRouteTitle(provider),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111B21),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta.isNotEmpty
                      ? meta.replaceAll('â€¢', '-')
                      : _statusHeadline(provider.status),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF54656F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _courierRouteTitle(TrackingProvider provider) {
    if (provider.status == 'at_restaurant') {
      return 'No restaurante';
    }
    return _routePhase == 'to_client'
        ? 'Rota para o cliente'
        : 'Rota para o restaurante';
  }

  Widget _buildCourierMapActionRail(TrackingProvider provider) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMapActionButton(
          heroTag: 'follow_courier_map',
          tooltip: _followCourier ? 'Mover livremente' : 'Seguir rota',
          icon: Icons.navigation_rounded,
          backgroundColor: _followCourier
              ? const Color(0xFF111B21)
              : Colors.white,
          foregroundColor: _followCourier
              ? Colors.white
              : const Color(0xFF111B21),
          onPressed: () async {
            setState(() => _followCourier = !_followCourier);
            if (_followCourier) {
              await _followCourierCamera();
            }
          },
        ),
        if ((provider.restaurantPhone?.trim().isNotEmpty ?? false)) ...[
          const SizedBox(height: 8),
          _buildMapActionButton(
            heroTag: 'call_restaurant_map',
            tooltip: 'Ligar para o restaurante',
            icon: Icons.storefront_outlined,
            onPressed: () => _callExternalContact(
              provider.restaurantPhone,
              label: 'restaurante',
            ),
          ),
        ],
        if ((provider.clientPhone?.trim().isNotEmpty ?? false)) ...[
          const SizedBox(height: 8),
          _buildMapActionButton(
            heroTag: 'call_client_map',
            tooltip: 'Ligar para o cliente',
            icon: Icons.phone_in_talk_outlined,
            onPressed: () =>
                _callExternalContact(provider.clientPhone, label: 'cliente'),
          ),
        ],
      ],
    );
  }

  Widget _buildClientMapActionRail() {
    return SizedBox(
      width: 132,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 132,
            child: FilledButton.icon(
              onPressed: () {
                setState(() => _clientPanelsHidden = !_clientPanelsHidden);
              },
              icon: Icon(
                _clientPanelsHidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
              label: Text(_clientPanelsHidden ? 'Mostrar' : 'Esconder'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF111B21),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            heroTag: 'follow_courier',
            backgroundColor: _followCourier
                ? const Color(0xFF111B21)
                : Colors.white,
            foregroundColor: _followCourier
                ? Colors.white
                : const Color(0xFF111B21),
            onPressed: () async {
              setState(() => _followCourier = !_followCourier);
              if (_followCourier) {
                await _followCourierCamera();
              }
            },
            child: const Icon(Icons.navigation_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildMapActionButton({
    required String heroTag,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color backgroundColor = Colors.white,
    Color foregroundColor = const Color(0xFF111B21),
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 42,
        height: 42,
        child: FloatingActionButton(
          heroTag: heroTag,
          mini: true,
          elevation: 3,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          onPressed: onPressed,
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }

  Widget _buildTopBar(TrackingProvider provider) {
    return Row(
      children: [
        _buildTopIconButton(
          icon: Icons.arrow_back_rounded,
          onTap: () => context.pop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pedido #${widget.orderId.substring(0, 8)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111B21),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusHeadline(provider.status),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF54656F),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClientStatusCard(TrackingProvider provider) {
    final showCompactAssignedCard =
        provider.status == 'assigned' && _hasAssignedCourier(provider);
    if (showCompactAssignedCard) {
      return _buildCompactAssignedCard(provider);
    }
    return _buildHeroStatusCard(provider);
  }

  Widget _buildTopIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: const Color(0xFF111B21)),
      ),
    );
  }

  Widget _buildHeroStatusCard(TrackingProvider provider) {
    String statusText;
    IconData statusIcon;
    Color statusColor;

    switch (provider.status) {
      case 'searching':
        statusText = 'À procura de estafeta';
        statusIcon = Icons.search_rounded;
        statusColor = Colors.orange;
        break;
      case 'assigned':
        statusText = 'Estafeta atribuido';
        statusIcon = Icons.delivery_dining_rounded;
        statusColor = Colors.blue;
        break;
      case 'at_restaurant':
        statusText = 'No restaurante';
        statusIcon = Icons.storefront_rounded;
        statusColor = Colors.deepOrange;
        break;
      case 'in_transit':
        statusText = 'A caminho de ti';
        statusIcon = Icons.local_shipping_rounded;
        statusColor = Colors.green;
        break;
      case 'arrived':
        statusText = 'Chegou ao destino';
        statusIcon = Icons.check_circle_rounded;
        statusColor = Colors.green;
        break;
      case 'delivered':
        statusText = 'Entrega concluída';
        statusIcon = Icons.verified_rounded;
        statusColor = AppColors.successGreen;
        break;
      case 'completed':
        statusText = 'Pedido concluido';
        statusIcon = Icons.task_alt_rounded;
        statusColor = AppColors.successGreen;
        break;
      case 'confirmed':
        statusText = 'Pedido confirmado';
        statusIcon = Icons.check_circle_outline_rounded;
        statusColor = Colors.blueGrey;
        break;
      case 'preparing':
        statusText = 'Em preparação';
        statusIcon = Icons.restaurant_rounded;
        statusColor = Colors.deepOrange;
        break;
      case 'ready':
        statusText = 'Pronto para recolha';
        statusIcon = Icons.inventory_2_rounded;
        statusColor = Colors.teal;
        break;
      default:
        statusText = 'A atualizar pedido';
        statusIcon = Icons.hourglass_empty_rounded;
        statusColor = Colors.grey;
    }

    if (provider.status == 'searching') {
      statusText = 'A procura de estafetas proximos';
    }

    final isLive = switch (provider.status) {
      'assigned' ||
      'at_restaurant' ||
      'in_transit' ||
      'arrived' ||
      'ready' => true,
      _ => false,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusPulseIcon(
                icon: statusIcon,
                color: statusColor,
                active: isLive,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusHelper(provider.status),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF54656F),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _TrackingLiveBadge(
                      active: provider.courierActivityLabel != 'Offline',
                      color: provider.courierActivityLabel == 'Em movimento'
                          ? const Color(0xFF159455)
                          : provider.courierActivityLabel == 'Parado'
                          ? const Color(0xFFE6A100)
                          : const Color(0xFFD92D20),
                      label: provider.courierActivityLabel,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (provider.status == 'searching') ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                backgroundColor: statusColor.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  'ETA',
                  provider.estimatedTime != null
                      ? '${provider.estimatedTime} min'
                      : '--',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  'Distancia',
                  _routeInfo?.distanceMeters != null
                      ? '${(_routeInfo!.distanceMeters! / 1000).toStringAsFixed(1)} km'
                      : '--',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  'Modo',
                  _followCourier ? 'Ao vivo' : 'Livre',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAssignedCard(TrackingProvider provider) {
    final etaText = provider.estimatedTime != null
        ? '${provider.estimatedTime} min'
        : null;
    final distanceText = _routeInfo?.distanceMeters != null
        ? '${(_routeInfo!.distanceMeters! / 1000).toStringAsFixed(1)} km'
        : null;
    final summaryParts = <String>[
      'O estafeta ja esta a seguir para o restaurante.',
    ];
    if (etaText != null) {
      summaryParts.add('ETA $etaText');
    }
    if (distanceText != null) {
      summaryParts.add(distanceText);
    }
    final summary = summaryParts.join(' - ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.delivery_dining_rounded,
              color: Colors.blue,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estafeta atribuido',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111B21),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: Color(0xFF54656F),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => setState(() => _clientPanelsHidden = true),
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: const Text('Esconder'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF111B21),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111B21),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(TrackingProvider provider) {
    final hasAssignedCourier = _hasAssignedCourier(provider);
    final courierName = hasAssignedCourier
        ? ((provider.courierName?.trim().isNotEmpty ?? false)
              ? provider.courierName!.trim()
              : 'Estafeta atribuido')
        : 'Aguardando estafeta';
    final courierSummary = hasAssignedCourier
        ? ((provider.courierPhone?.trim().isNotEmpty ?? false)
              ? provider.courierPhone!.trim()
              : 'Toque para ver foto, nome e contacto')
        : 'Toque para ver como estamos a procurar um estafeta';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D7DE),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _clientTrackingHeadline(provider),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111B21),
                    ),
                  ),
                ),
                if (provider.estimatedTime != null)
                  Text(
                    '~${provider.estimatedTime} min',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF159455),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildCourierAvatar(
                  avatarUrl: provider.courierAvatarUrl,
                  name: courierName,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        courierName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        courierSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.neutralGray,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: hasAssignedCourier
                        ? const Color(0xFFEAF4FF)
                        : const Color(0xFFFFF4E5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    hasAssignedCourier ? 'Ao vivo' : 'Procura',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: hasAssignedCourier
                          ? const Color(0xFF0057B8)
                          : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: hasAssignedCourier
                        ? () => _showCourierDetailsSheet(provider)
                        : _showSearchingInfoSheet,
                    icon: Icon(
                      hasAssignedCourier
                          ? Icons.person_outline_rounded
                          : Icons.search_rounded,
                    ),
                    label: Text(
                      hasAssignedCourier ? 'Ver estafeta' : 'Info da procura',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF111B21),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: hasAssignedCourier
                      ? OutlinedButton.icon(
                          onPressed: () => _callCourier(provider.courierPhone),
                          icon: const Icon(Icons.phone_outlined),
                          label: const Text('Ligar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF111B21),
                            side: const BorderSide(color: Color(0xFFCCD3DA)),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        )
                      : OrderChatButton(
                          orderId: widget.orderId,
                          onPressed: () {
                            context.push('/chat/${widget.orderId}');
                          },
                          label: 'Chat',
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF111B21),
                            side: const BorderSide(color: Color(0xFFCCD3DA)),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => hasAssignedCourier
                  ? _showCourierDetailsSheet(provider)
                  : _showSearchingInfoSheet(),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(
                hasAssignedCourier
                    ? 'Ver detalhes do estafeta e percurso'
                    : 'Ver detalhes da procura de estafeta',
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF54656F),
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _clientTrackingHeadline(TrackingProvider provider) {
    switch (provider.status) {
      case 'searching':
        return 'A procurar estafeta';
      case 'assigned':
        return 'Estafeta a caminho do restaurante';
      case 'at_restaurant':
        return 'Estafeta no restaurante';
      case 'in_transit':
        return 'O seu estafeta está a caminho';
      case 'arrived':
        return 'O seu estafeta está a chegar';
      case 'delivered':
      case 'completed':
        return 'Entrega concluída';
      default:
        return _statusHeadline(provider.status);
    }
  }

  Widget _buildInfoPoint({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6F8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF111B21)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Color(0xFF54656F),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCourierInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF111B21)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111B21),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourierAvatar({
    required String? avatarUrl,
    required String name,
    double radius = 26,
  }) {
    final normalizedUrl = avatarUrl?.trim();
    final initials = _initialsFromName(name);

    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF111B21),
      backgroundImage: normalizedUrl != null && normalizedUrl.isNotEmpty
          ? NetworkImage(normalizedUrl)
          : null,
      child: normalizedUrl == null || normalizedUrl.isEmpty
          ? Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.55,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }

  String _initialsFromName(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'E';
    return parts.map((part) => part[0].toUpperCase()).join();
  }

  String _restaurantStopValue() {
    final name = _restaurantName.trim();
    final place = _restaurantPlace.trim();
    if (name.isEmpty) return place;
    if (place.isEmpty) return name;
    if (place.toLowerCase().contains(name.toLowerCase())) return place;
    return '$name, $place';
  }

  String _statusHeadline(String status) {
    if (status == 'delivery_failed_otp') {
      return 'Entrega em revisao admin';
    }

    if (status == 'completed') {
      return 'Pedido concluido com sucesso';
    }

    if (status == 'delivered') {
      return 'Entrega validada, falta a tua confirmacao';
    }

    if (status == 'searching') {
      return 'Deligo esta a procurar um estafeta proximo do restaurante';
    }

    if (status == 'at_restaurant') {
      return 'Estafeta no restaurante para recolha';
    }

    switch (status) {
      case 'searching':
        return 'Deligo esta a procurar um estafeta proximo do restaurante';
      case 'assigned':
        return 'Estafeta confirmado para este pedido';
      case 'at_restaurant':
        return 'Estafeta no restaurante para recolha';
      case 'in_transit':
        return 'A tua entrega já segue no mapa';
      case 'arrived':
        return 'Estafeta chegou ao destino';
      case 'completed':
        return 'Pedido concluido com sucesso';
      case 'delivered':
        return 'Entrega concluída com sucesso';
      case 'confirmed':
        return 'Restaurante confirmou o pedido';
      case 'preparing':
        return 'O pedido está em preparação';
      case 'ready':
        return 'Pronto para recolha';
      default:
        return 'Estamos a atualizar o pedido';
    }
  }

  String _statusHelper(String status) {
    if (status == 'delivery_failed_otp') {
      return 'O OTP falhou na entrega. A equipa admin foi alertada para rever o caso com seguranca antes do fecho.';
    }

    if (status == 'completed') {
      return 'A entrega foi fechada e este pedido ja nao deve mostrar alertas antigos no mapa.';
    }

    if (status == 'in_transit') {
      return 'Acompanha o movimento no mapa em tempo real. O teu codigo de entrega ja deve estar visivel no detalhe do pedido.';
    }

    if (status == 'delivered') {
      return 'O codigo ja foi validado. Confirma no app quando receberes tudo ou reporta um problema antes do fecho automatico.';
    }

    if (status == 'searching') {
      return 'Assim que um estafeta proximo aceitar, a rota vai aparecer automaticamente no mapa.';
    }

    if (status == 'at_restaurant') {
      return 'O estafeta ja chegou ao restaurante e esta a recolher o pedido.';
    }

    switch (status) {
      case 'searching':
        return 'Estamos a localizar um estafeta disponível perto do restaurante.';
      case 'assigned':
        return 'O estafeta já foi atribuído e deve iniciar a recolha em breve.';
      case 'in_transit':
        return 'Acompanha o movimento no mapa em tempo real.';
      case 'arrived':
        return 'O estafeta já está no local. Podes ligar ou abrir o chat se precisares.';
      case 'completed':
        return 'Entrega finalizada com sucesso. Obrigado por acompanhares a rota.';
      case 'delivered':
        return 'O pedido foi marcado como entregue.';
      case 'confirmed':
        return 'O restaurante já recebeu e validou o pedido.';
      case 'preparing':
        return 'A cozinha está a preparar o pedido agora.';
      case 'ready':
        return 'O pedido terminou o preparo e já pode seguir.';
      default:
        return 'Vamos continuar a atualizar esta tela automaticamente.';
    }
  }

  String _resolvePhase(String status) {
    if (status == 'at_restaurant') {
      return 'to_restaurant';
    }

    switch (status) {
      case 'in_transit':
      case 'picked_up':
      case 'in_delivery':
      case 'arrived':
      case 'delivery_failed_otp':
      case 'delivered':
      case 'completed':
        return 'to_client';
      case 'assigned':
      case 'confirmed':
      case 'preparing':
      case 'ready':
      case 'searching':
      default:
        return 'to_restaurant';
    }
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
    return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  void _notifyStatus(String status) {
    if (_notifiedStatuses.contains(status) || !mounted) return;
    _notifiedStatuses.add(status);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    unawaited(SoundController.instance.shortBang());
    final voiceType = _voiceTypeForStatus(status);
    String message;
    if (status == 'delivery_failed_otp') {
      message = 'O OTP falhou nesta entrega. A equipa admin foi alertada.';
      _speakTrackingPopup(status, voiceType, message);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: _popupDuration,
        ),
      );
      return;
    }
    if (status == 'delivered') {
      message = 'Entrega validada. Falta a tua confirmacao final no app.';
      _speakTrackingPopup(status, voiceType, message);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: _popupDuration,
        ),
      );
      return;
    }
    if (status == 'completed') {
      message = 'Pedido concluido com sucesso.';
      _speakTrackingPopup(status, voiceType, message);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 850),
        ),
      );
      return;
    }
    if (status == 'in_transit') {
      message =
          'Estafeta ja levantou o pedido. O teu codigo de entrega ja esta no app.';
      _speakTrackingPopup(status, voiceType, message);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: _popupDuration,
        ),
      );
      return;
    }

    if (status == 'at_restaurant') {
      message =
          'Estafeta chegou ao restaurante. O estafeta ja esta no restaurante para recolher o produto.';
      _speakTrackingPopup(status, voiceType, message);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: _popupDuration,
        ),
      );
      return;
    }

    switch (status) {
      case 'assigned':
        return;
      case 'ready':
        message =
            'Pedido pronto para retirar. O pedido terminou o preparo e ja pode ser retirado.';
        break;
      case 'in_transit':
        message = 'Pedido levantado. Está a caminho!';
        break;
      case 'arrived':
        message = 'O estafeta já chegou ao destino.';
        break;
      case 'completed':
        message = 'Pedido concluido com sucesso.';
        break;
      case 'delivered':
        message = 'Entrega concluída com sucesso.';
        break;
      default:
        return;
    }
    _speakTrackingPopup(status, voiceType, message);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: status == 'completed' || status == 'delivered'
            ? const Duration(milliseconds: 850)
            : _popupDuration,
      ),
    );
  }

  String? _voiceTypeForStatus(String status) {
    switch (status) {
      case 'ready':
        return 'ORDER_READY';
      case 'in_transit':
        return 'ORDER_PICKED_UP';
      case 'at_restaurant':
        return 'DRIVER_ARRIVED';
      case 'arrived':
        return 'DRIVER_ARRIVED';
      case 'delivered':
        return 'ORDER_DELIVERED';
      case 'completed':
        return 'ORDER_COMPLETED';
      case 'delivery_failed_otp':
        return 'DELIVERY_SLA_EXCEEDED';
      default:
        return null;
    }
  }

  void _speakTrackingPopup(String status, String? voiceType, String message) {
    if (voiceType == null) return;
    unawaited(
      AppVoiceService.instance.speakNotification(
        type: voiceType,
        title: 'DeliGo',
        body: message,
        notificationId: 'tracking_popup_${widget.orderId}_$status',
        channel: 'client_alert',
        priority: 'HIGH',
      ),
    );
  }
}

class _RippleEntry {
  final String id;
  final double dx;
  final double dy;
  final Color color;

  const _RippleEntry({
    required this.id,
    required this.dx,
    required this.dy,
    required this.color,
  });
}

class _StatusPulseIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool active;

  const _StatusPulseIcon({
    required this.icon,
    required this.color,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (active)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.72, end: 1.26),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              onEnd: () {},
              builder: (context, value, child) {
                return Container(
                  width: 42 * value,
                  height: 42 * value,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(
                      alpha: (1 - (value - 0.72)).clamp(0, 1) * 0.12,
                    ),
                  ),
                );
              },
            ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
        ],
      ),
    );
  }
}

class _TrackingLiveBadge extends StatelessWidget {
  final bool active;
  final Color color;
  final String label;

  const _TrackingLiveBadge({
    required this.active,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: active ? 0.6 : 1, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              return Opacity(
                opacity: active ? value : 1,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
