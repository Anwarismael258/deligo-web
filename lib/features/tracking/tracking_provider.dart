import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/realtime_service.dart';

class TrackingProvider extends ChangeNotifier {
  final RealtimeService _realtimeService = RealtimeService();
  final SupabaseClient _supabase = Supabase.instance.client;

  String? currentOrderId;
  String? courierId;
  String? courierName;
  String? courierPhone;
  String? courierAvatarUrl;
  String? clientName;
  String? clientPhone;
  String? restaurantName;
  String? restaurantAddress;
  String? restaurantPhone;
  String? deliveryAddress;
  double? courierLatitude;
  double? courierLongitude;
  double? courierSpeedMetersPerSecond;
  double? courierHeadingDegrees;
  int? courierBatteryPercent;
  DateTime? locationRecordedAt;
  double? restaurantLatitude;
  double? restaurantLongitude;
  double? deliveryLatitude;
  double? deliveryLongitude;
  String status = 'idle';
  bool _dispatchActive = false;
  int? estimatedTime;
  bool isTracking = false;
  Timer? _positionPollTimer;

  String get courierActivityLabel {
    final recordedAt = locationRecordedAt;
    if (recordedAt == null ||
        DateTime.now().toUtc().difference(recordedAt.toUtc()).inSeconds > 60) {
      return 'Offline';
    }
    if ((courierSpeedMetersPerSecond ?? 0) >= 1) return 'Em movimento';
    return 'Parado';
  }

  // Throttle control
  DateTime? _lastLocationUpdate;
  static const int _minUpdateIntervalSeconds = 3;
  static const double _minDistanceMeters = 5.0;

  /// Iniciar rastreamento
  Future<void> startTracking({
    required String orderId,
    required double restaurantLat,
    required double restaurantLng,
    required double deliveryLat,
    required double deliveryLng,
  }) async {
    if (currentOrderId != null && currentOrderId != orderId) {
      _realtimeService.stopAll();
    }
    currentOrderId = orderId;
    restaurantLatitude = restaurantLat;
    restaurantLongitude = restaurantLng;
    deliveryLatitude = deliveryLat;
    deliveryLongitude = deliveryLng;
    courierId = null;
    courierName = null;
    courierPhone = null;
    courierAvatarUrl = null;
    clientName = null;
    clientPhone = null;
    restaurantPhone = null;
    courierLatitude = null;
    courierLongitude = null;
    // Do not show an active search before the server snapshot confirms that
    // a dispatch attempt is running.
    status = 'loading';
    _dispatchActive = false;
    isTracking = true;

    _realtimeService.onCourierLocationUpdate = _onLocationUpdate;
    _realtimeService.onOrderStatusUpdate = _onStatusUpdate;

    await _loadOrderSnapshot(orderId);

    await _realtimeService.startDeliveryTracking(orderId);
    await _realtimeService.startOrderTracking(orderId);
    _startPositionPolling(orderId);

    notifyListeners();
  }

  void _onLocationUpdate(double lat, double lng) {
    courierLatitude = lat;
    courierLongitude = lng;
    notifyListeners();
  }

  void _onStatusUpdate(String newStatus) {
    if (newStatus == 'cancelled') {
      stopTracking();
      return;
    }
    _applyOrderStatus(
      newStatus,
      hasAssignedCourier: courierId?.trim().isNotEmpty == true,
    );
    if (currentOrderId != null &&
        (newStatus == 'courier_assigned' ||
            newStatus == 'in_transit' ||
            newStatus == 'on_the_way' ||
            newStatus == 'arrived' ||
            newStatus == 'delivered' ||
            newStatus == 'completed')) {
      unawaited(_loadOrderSnapshot(currentOrderId!));
    }
    notifyListeners();
  }

  void _startPositionPolling(String orderId) {
    _positionPollTimer?.cancel();
    _positionPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!isTracking || currentOrderId != orderId) return;
      unawaited(_pollCourierPosition(orderId));
    });
  }

  Future<void> _pollCourierPosition(String orderId) async {
    try {
      final row = await _supabase
          .from('deliveries')
          .select(
            'current_latitude, current_longitude, courier_id, location_recorded_at',
          )
          .eq('order_id', orderId)
          .maybeSingle();
      if (row == null || currentOrderId != orderId) return;
      final lat = (row['current_latitude'] as num?)?.toDouble();
      final lng = (row['current_longitude'] as num?)?.toDouble();
      final nextCourierId = row['courier_id']?.toString().trim() ?? '';
      courierSpeedMetersPerSecond = null;
      courierHeadingDegrees = null;
      courierBatteryPercent = null;
      locationRecordedAt = DateTime.tryParse(
        row['location_recorded_at']?.toString() ?? '',
      );
      if (nextCourierId.isNotEmpty && courierId != nextCourierId) {
        courierId = nextCourierId;
        unawaited(_loadOrderSnapshot(orderId));
      }
      if (lat != null &&
          lng != null &&
          (lat != courierLatitude || lng != courierLongitude)) {
        _onLocationUpdate(lat, lng);
      }
    } catch (error) {
      debugPrint('TrackingProvider position poll error: $error');
    }
  }

  void _applyOrderStatus(
    String newStatus, {
    bool hasAssignedCourier = false,
    bool isDelivery = true,
    bool dispatchActive = false,
  }) {
    _dispatchActive = dispatchActive;
    switch (newStatus) {
      case 'paid':
      case 'accepted':
        status = 'confirmed';
        break;
      case 'preparing':
        status = 'preparing';
        break;
      case 'ready':
        status = isDelivery && !hasAssignedCourier && dispatchActive
            ? 'searching'
            : 'ready';
        break;
      case 'courier_assigned':
        status = 'assigned';
        break;
      case 'in_transit':
      case 'on_the_way':
        status = 'in_transit';
        break;
      case 'arrived':
        status = 'arrived';
        break;
      case 'delivery_failed_otp':
        status = 'delivery_failed_otp';
        break;
      case 'delivered':
        status = 'delivered';
        break;
      case 'completed':
      case 'auto_completed':
        status = 'completed';
        break;
      case 'disputed':
        status = 'delivered';
        break;
    }
  }

  Future<void> _loadOrderSnapshot(String orderId) async {
    try {
      final order = await _supabase
          .from('orders')
          .select('''
            status,
            client_id,
            customer_id,
            courier_id,
            delivery_type,
            delivery_fee,
            delivery_address,
            delivery_latitude,
            delivery_longitude,
            dispatch_attempt_id,
            dispatch_expires_at,
            pickup_address,
            pickup_latitude,
            pickup_longitude,
            restaurants(name, address, latitude, longitude, phone)
          ''')
          .eq('id', orderId)
          .maybeSingle();
      if (order == null) return;

      Map<String, dynamic>? deliveryRow;
      try {
        deliveryRow = await _supabase
            .from('deliveries')
            .select('''
              courier_id,
              pickup_latitude,
              pickup_longitude,
              delivery_latitude,
              delivery_longitude,
              current_latitude,
              current_longitude,
              location_recorded_at
            ''')
            .eq('order_id', orderId)
            .maybeSingle();
      } catch (error) {
        debugPrint(
          'TrackingProvider._loadOrderSnapshot delivery lookup error: $error',
        );
      }

      final restaurant = order['restaurants'] is Map
          ? Map<String, dynamic>.from(order['restaurants'] as Map)
          : null;
      restaurantName = restaurant?['name']?.toString();
      restaurantAddress =
          order['pickup_address']?.toString() ??
          restaurant?['address']?.toString();
      final nextRestaurantPhone = restaurant?['phone']?.toString().trim();
      restaurantPhone = (nextRestaurantPhone?.isNotEmpty ?? false)
          ? nextRestaurantPhone
          : restaurantPhone;
      deliveryAddress = order['delivery_address']?.toString();
      restaurantLatitude =
          (order['pickup_latitude'] as num?)?.toDouble() ??
          (deliveryRow?['pickup_latitude'] as num?)?.toDouble() ??
          (restaurant?['latitude'] as num?)?.toDouble() ??
          restaurantLatitude;
      restaurantLongitude =
          (order['pickup_longitude'] as num?)?.toDouble() ??
          (deliveryRow?['pickup_longitude'] as num?)?.toDouble() ??
          (restaurant?['longitude'] as num?)?.toDouble() ??
          restaurantLongitude;
      deliveryLatitude =
          (order['delivery_latitude'] as num?)?.toDouble() ??
          (deliveryRow?['delivery_latitude'] as num?)?.toDouble() ??
          deliveryLatitude;
      deliveryLongitude =
          (order['delivery_longitude'] as num?)?.toDouble() ??
          (deliveryRow?['delivery_longitude'] as num?)?.toDouble() ??
          deliveryLongitude;

      final orderStatus = order['status']?.toString().trim();
      final deliveryType = order['delivery_type']
          ?.toString()
          .trim()
          .toLowerCase();
      final deliveryFee = (order['delivery_fee'] as num?)?.toDouble() ?? 0;
      final isDelivery = deliveryType != 'pickup' && deliveryFee > 0;
      final dispatchAttemptId = order['dispatch_attempt_id']?.toString().trim();
      final dispatchExpiresAt = DateTime.tryParse(
        order['dispatch_expires_at']?.toString() ?? '',
      );
      final dispatchActive =
          isDelivery &&
          dispatchAttemptId != null &&
          dispatchAttemptId.isNotEmpty &&
          dispatchExpiresAt?.toUtc().isAfter(DateTime.now().toUtc()) == true;
      final orderCourierId = order['courier_id']?.toString().trim() ?? '';
      final deliveryCourierId =
          deliveryRow?['courier_id']?.toString().trim() ?? '';
      final nextCourierId = orderCourierId.isNotEmpty
          ? orderCourierId
          : deliveryCourierId;
      final nextClientId =
          (order['client_id'] ?? order['customer_id'])?.toString().trim() ?? '';
      if (orderStatus != null && orderStatus.isNotEmpty) {
        _applyOrderStatus(
          orderStatus,
          hasAssignedCourier: nextCourierId.isNotEmpty,
          isDelivery: isDelivery,
          dispatchActive: dispatchActive,
        );
      }
      if (nextCourierId.isEmpty) {
        courierId = null;
        courierName = null;
        courierPhone = null;
        courierAvatarUrl = null;
        courierLatitude = null;
        courierLongitude = null;
        return;
      }

      courierId = nextCourierId;

      Map<String, dynamic>? courierPublicProfile;
      try {
        courierPublicProfile = await _supabase
            .from('couriers')
            .select('*')
            .eq('id', nextCourierId)
            .maybeSingle();
      } catch (error) {
        debugPrint(
          'TrackingProvider._loadOrderSnapshot courier public lookup error: $error',
        );
      }

      Map<String, dynamic>? courierProfile;
      try {
        courierProfile = await _supabase
            .from('profiles')
            .select('full_name, phone, avatar_url')
            .eq('id', nextCourierId)
            .maybeSingle();
      } catch (_) {
        courierProfile = null;
      }

      final fullName =
          courierPublicProfile?['full_name']?.toString().trim().isNotEmpty ==
              true
          ? courierPublicProfile!['full_name'].toString().trim()
          : courierProfile?['full_name']?.toString().trim();
      final phone =
          courierPublicProfile?['phone']?.toString().trim().isNotEmpty == true
          ? courierPublicProfile!['phone'].toString().trim()
          : courierProfile?['phone']?.toString().trim();
      final avatarUrl =
          courierPublicProfile?['avatar_url']?.toString().trim().isNotEmpty ==
              true
          ? courierPublicProfile!['avatar_url'].toString().trim()
          : courierProfile?['avatar_url']?.toString().trim();
      if (fullName != null && fullName.isNotEmpty) {
        courierName = fullName;
      }
      if (phone != null && phone.isNotEmpty) {
        courierPhone = phone;
      }
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        courierAvatarUrl = avatarUrl;
      }

      if (nextClientId.isNotEmpty) {
        Map<String, dynamic>? clientProfile;
        try {
          clientProfile = await _supabase
              .from('profiles')
              .select('full_name, phone')
              .eq('id', nextClientId)
              .maybeSingle();
        } catch (_) {
          clientProfile = null;
        }
        final clientFullName = clientProfile?['full_name']?.toString().trim();
        final clientPhoneValue = clientProfile?['phone']?.toString().trim();
        if (clientFullName != null && clientFullName.isNotEmpty) {
          clientName = clientFullName;
        }
        if (clientPhoneValue != null && clientPhoneValue.isNotEmpty) {
          clientPhone = clientPhoneValue;
        }
      }

      courierLatitude =
          (deliveryRow?['current_latitude'] as num?)?.toDouble() ??
          (courierPublicProfile?['current_latitude'] as num?)?.toDouble() ??
          courierLatitude;
      courierLongitude =
          (deliveryRow?['current_longitude'] as num?)?.toDouble() ??
          (courierPublicProfile?['current_longitude'] as num?)?.toDouble() ??
          courierLongitude;
      courierSpeedMetersPerSecond = (deliveryRow?['current_speed_mps'] as num?)
          ?.toDouble();
      courierHeadingDegrees = (deliveryRow?['current_heading_degrees'] as num?)
          ?.toDouble();
      courierBatteryPercent = (deliveryRow?['courier_battery_percent'] as num?)
          ?.toInt();
      locationRecordedAt = DateTime.tryParse(
        deliveryRow?['location_recorded_at']?.toString() ?? '',
      );
    } catch (error) {
      debugPrint('TrackingProvider._loadOrderSnapshot error: $error');
    }
  }

  void assignCourier({
    required String courierId,
    required String courierName,
    required String courierPhone,
    required double latitude,
    required double longitude,
    String? courierAvatarUrl,
  }) {
    this.courierId = courierId;
    this.courierName = courierName;
    this.courierPhone = courierPhone;
    this.courierAvatarUrl = courierAvatarUrl;
    courierLatitude = latitude;
    courierLongitude = longitude;
    status = 'assigned';
    notifyListeners();
  }

  /// Atualizar localizacao com throttle (5 m ou 3 s)
  Future<void> updateCourierLocation(double latitude, double longitude) async {
    final now = DateTime.now();

    double? distance;
    if (_lastLocationUpdate != null &&
        courierLatitude != null &&
        courierLongitude != null) {
      distance = Geolocator.distanceBetween(
        courierLatitude!,
        courierLongitude!,
        latitude,
        longitude,
      );
    }

    final timeSinceLastUpdate = _lastLocationUpdate != null
        ? now.difference(_lastLocationUpdate!).inSeconds
        : _minUpdateIntervalSeconds + 1;

    if (distance != null &&
        distance < _minDistanceMeters &&
        timeSinceLastUpdate < _minUpdateIntervalSeconds) {
      return;
    }

    courierLatitude = latitude;
    courierLongitude = longitude;
    _lastLocationUpdate = now;

    if (currentOrderId != null) {
      await _realtimeService.updateDeliveryLocation(
        currentOrderId!,
        latitude,
        longitude,
      );
    }

    notifyListeners();
  }

  /// Iniciar atualizacao automatica de localizacao
  StreamSubscription<Position>? _locationSubscription;

  Future<void> startLocationUpdates() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _locationSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((Position position) {
          updateCourierLocation(position.latitude, position.longitude);
        });
  }

  void courierArrived() {
    status = 'arrived';
    notifyListeners();
  }

  void markCourierAtRestaurant() {
    if (status == 'delivered' ||
        status == 'completed' ||
        status == 'arrived' ||
        status == 'in_transit' ||
        status == 'delivery_failed_otp') {
      return;
    }
    status = 'at_restaurant';
    notifyListeners();
  }

  void setEstimatedTime(int minutes) {
    estimatedTime = minutes;
    notifyListeners();
  }

  void stopTracking() {
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
    _locationSubscription?.cancel();
    _locationSubscription = null;
    currentOrderId = null;
    courierId = null;
    courierName = null;
    courierPhone = null;
    courierAvatarUrl = null;
    clientName = null;
    clientPhone = null;
    courierLatitude = null;
    courierLongitude = null;
    restaurantLatitude = null;
    restaurantLongitude = null;
    restaurantName = null;
    restaurantAddress = null;
    restaurantPhone = null;
    deliveryAddress = null;
    deliveryLatitude = null;
    deliveryLongitude = null;
    status = 'idle';
    _dispatchActive = false;
    estimatedTime = null;
    isTracking = false;
    _lastLocationUpdate = null;

    _realtimeService.stopAll();
    notifyListeners();
  }

  @override
  void dispose() {
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _realtimeService.dispose();
    super.dispose();
  }
}
