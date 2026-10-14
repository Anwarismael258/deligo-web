import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme/app_colors.dart';
import '../../services/courier_foreground_service.dart';
import '../../services/delivery_service.dart';
import '../../services/courier_offer_feedback_deadline.dart';
import '../../services/courier_offer_visibility_deadline.dart';
import '../../services/notification_router_service.dart';
import '../../services/public_share_service.dart';
import '../../services/weather_service.dart';
import '../../services/push_notification_service.dart';
import '../../shared/maps/yango_map_widget.dart';
import '../../shared/models/menu_item.dart';
import '../../shared/models/order.dart';
import '../../shared/utils/location_display.dart';
import '../../shared/utils/maps_route.dart';
import '../../shared/utils/ecosystem_test_persona.dart';
import '../../shared/utils/mozambique_time.dart';
import '../../shared/widgets/order_chat_button.dart';
import '../../shared/widgets/institutional_footer.dart';
import '../../shared/widgets/tap_scale.dart';
import '../../shared/widgets/profile_image_viewer.dart';
import '../../shared/utils/chat_notification_utils.dart';
import '../../shared/utils/courier_dispatch_utils.dart';
import '../../shared/utils/deligo_viewport.dart';
import '../../services/order_service.dart';
import '../../services/profile_service.dart';
import '../../services/account_deletion_service.dart';
import '../../services/sound_controller.dart';
import 'package:deligo_app/services/welcome_voice_service.dart';
import 'package:deligo_app/services/app_voice_service.dart';
import '../../config/router/app_router.dart';

class CourierDashboardEnhanced extends StatefulWidget {
  const CourierDashboardEnhanced({super.key});

  @override
  State<CourierDashboardEnhanced> createState() =>
      _CourierDashboardEnhancedState();
}

class _CourierDashboardEnhancedState extends State<CourierDashboardEnhanced>
    with WidgetsBindingObserver {
  static const Duration _popupDuration = Duration(milliseconds: 1000);

  final supabase = Supabase.instance.client;
  final DeliveryService _deliveryService = DeliveryService();
  final OrderService _orderService = OrderService();
  final PublicShareService _publicShareService = PublicShareService.instance;
  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _profileChannel;
  RealtimeChannel? _courierChannel;
  RealtimeChannel? _walletChannel;
  RealtimeChannel? _notificationsChannel;
  Timer? _ordersRefreshDebounce;
  Timer? _profileRefreshDebounce;
  Timer? _notificationsRefreshDebounce;
  Timer? _presenceHeartbeatTimer;
  Timer? _homeClockTimer;
  Timer? _availableOfferExpiryTimer;
  Timer? _offerCountdownTimer;
  Timer? _availableOfferRecoveryTimer;
  int _loadVersion = 0;
  int _availableOfferRefreshVersion = 0;
  bool _availableOfferRefreshInFlight = false;

  int _selectedIndex = 0;
  bool isOnline = false;
  bool _autoOnlineAttempted = false;
  bool isLoading = true;
  String? kycStatus;
  String? rejectionReason;
  final Set<String> _deliveryActionsInFlight = <String>{};
  Position? _currentPosition;
  bool _loadingLocation = false;
  bool _savingProfile = false;
  bool _uploadingAvatar = false;
  Map<String, dynamic> _profileSettings = {};
  Map<String, dynamic>? _profileData;
  String? _avatarUrl;
  String _preferredPaymentMethod = 'm-pesa';
  bool _pushNotificationsEnabled = true;
  bool _orderSoundsEnabled = true;
  bool _pushActive = false;
  String _languageCode = 'pt';
  String _voiceMode = 'important_only';
  double _courierRating = 0;
  double _walletBalance = 0;
  String _walletCurrency = 'MZN';
  bool _isTestWallet = false;
  bool _courierSuspended = false;
  String? _suspensionReason;
  WeatherSnapshot? _weather;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _workZoneController = TextEditingController();
  final _deliveryOtpController = TextEditingController();
  final ProfileService _profileService = ProfileService();

  // Dados do entregador
  int _totalDeliveries = 0;
  double _totalEarnings = 0;
  double _todayEarnings = 0;
  double _weekEarnings = 0;
  int _courierReviewCount = 0;
  Duration _onlineToday = Duration.zero;
  DateTime? _onlineTodayLoadedAt;
  List<Order> _availableDeliveries = [];
  List<Order> _completedDeliveries = [];
  Map<String, int> _completedItemCounts = {};
  Order? _currentDelivery;
  final Set<String> _locallyDeclinedDeliveryIds = {};
  final Map<String, Map<String, String>> _routeLocationCache = {};
  final Map<String, List<OrderItem>> _availableOrderItems = {};
  final Map<String, Future<List<OrderItem>>> _availableOrderItemsInFlight = {};
  final Set<String> _availableOrderItemsFailed = <String>{};
  final Map<String, double> _availableCourierAmounts = {};
  final Map<String, DateTime> _availableOfferDeadlines = {};
  final Map<String, Future<RoutePlan?>> _availableRoutePlans = {};
  final Set<String> _expandedOfferOrderIds = <String>{};
  final Set<String> _fittedOfferRouteKeys = <String>{};
  List<Map<String, dynamic>> _smartNotifications = [];
  bool _loadingHistory = true;
  StreamSubscription<Position>? _locationSub;
  DeligoMapController? _courierMapController;
  bool _followCourierMap = true;
  LatLng? _displayCourierLatLng;
  double? _displayCourierBearing;
  Position? _lastAcceptedCourierPosition;
  BitmapDescriptor? _courierMapMarkerIcon;
  bool _isAnimatingCourierCamera = false;
  int _courierMapAnimationToken = 0;
  DateTime? _lastCourierMapCameraAt;
  Future<List<LatLng>>? _homeRouteFuture;
  Future<RouteInfo?>? _homeRouteInfoFuture;
  String? _homeRouteKey;
  Future<LatLng?>? _homeEndpointFuture;
  String? _homeEndpointKey;
  LatLng? _homeResolvedEndpoint;
  String _currentAddressLine = '';
  String _currentNeighborhood = '';
  String _currentCity = '';
  DateTime? _lastGeocodeAt;
  Position? _lastGeocodePosition;
  bool _resolvingAddress = false;
  bool _verifyingDeliveryOtp = false;
  bool _updatingDeliveryStatus = false;
  String? _lastCourierDeliveryPopupKey;
  final Set<String> _closedDeliveryPopupOrderIds = <String>{};
  final Set<String> _arrivalNotificationInFlight = <String>{};
  final Set<String> _arrivedAtRestaurantOrderIds = <String>{};
  final Set<String> _restaurantArrivalAttemptedOrderIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCourierMapMarkerIcon());
    _homeClockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && isOnline) setState(() {});
    });
    _checkKycStatus();
  }

  Future<void> _loadCourierMapMarkerIcon() async {
    try {
      final icon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(40, 40)),
        'assets/markers/delivery.png',
      );
      if (mounted) setState(() => _courierMapMarkerIcon = icon);
    } catch (error) {
      debugPrint('[COURIER_MAP] marker asset unavailable: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Realtime may have been missed while the screen/process was suspended.
      // Recovery must query the server even when the local online flag is stale.
      unawaited(_refreshAvailableOffersImmediately());
      _scheduleCourierDataRefresh();
    }
  }

  @override
  void dispose() {
    _ordersRefreshDebounce?.cancel();
    _profileRefreshDebounce?.cancel();
    _notificationsRefreshDebounce?.cancel();
    _presenceHeartbeatTimer?.cancel();
    _homeClockTimer?.cancel();
    _availableOfferExpiryTimer?.cancel();
    _offerCountdownTimer?.cancel();
    _availableOfferRecoveryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _locationSub?.cancel();
    _courierMapController?.dispose();
    _ordersChannel?.unsubscribe();
    _profileChannel?.unsubscribe();
    _courierChannel?.unsubscribe();
    _walletChannel?.unsubscribe();
    _notificationsChannel?.unsubscribe();
    _nameController.dispose();
    _phoneController.dispose();
    _workZoneController.dispose();
    _deliveryOtpController.dispose();
    super.dispose();
  }

  Future<void> _initRealtimeOrders() async {
    if (_ordersChannel != null) return;
    _ordersChannel = supabase.channel('courier-orders');
    _ordersChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            final previousRecord = payload.oldRecord.isNotEmpty
                ? Map<String, dynamic>.from(payload.oldRecord)
                : const <String, dynamic>{};
            final nextRecord = payload.newRecord.isNotEmpty
                ? Map<String, dynamic>.from(payload.newRecord)
                : const <String, dynamic>{};
            _handleRealtimeOrderChange(
              previousRecord: previousRecord,
              nextRecord: nextRecord,
            );
          },
        )
        .subscribe();
  }

  Future<void> _checkKycStatus() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final response = await supabase
            .from('profiles')
            .select('kyc_status, kyc_rejection_reason')
            .eq('id', user.id)
            .single();

        if (mounted) {
          setState(() {
            kycStatus = response['kyc_status'];
            rejectionReason = response['kyc_rejection_reason'];
            isLoading = false;
          });

          if (kycStatus == 'approved') {
            _loadCourierData();
            _initRealtimeOrders();
            _initRealtimeProfile();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _loadCourierData() async {
    try {
      final loadVersion = ++_loadVersion;
      final user = supabase.auth.currentUser;
      if (user == null) return;
      _isTestWallet = EcosystemTestPersona.matches(user);
      final previousCurrentDelivery = _currentDelivery;
      final results = await Future.wait<dynamic>([
        supabase
            .from('profiles')
            .select(
              'full_name, gender, settings, phone, avatar_url, preferred_payment_method, payment_contact, is_blocked, block_reason, fcm_token',
            )
            .eq('id', user.id)
            .maybeSingle(),
        supabase.from('couriers').select('*').eq('id', user.id).maybeSingle(),
        supabase
            .from('wallets')
            .select('balance, currency')
            .eq('user_id', user.id)
            .maybeSingle(),
        _deliveryService.getCurrentDelivery(user.id),
        _deliveryService.getAvailableDeliveries(),
        _getCompletedDeliveries(),
        _getCourierStats(user.id),
      ]);
      if (!mounted || loadVersion != _loadVersion) return;
      final profile = results[0] as Map<String, dynamic>?;
      final courierProfile = results[1] as Map<String, dynamic>?;
      final wallet = results[2] as Map<String, dynamic>?;
      final current = results[3] as Order?;
      final available = _prepareAvailableOffers(results[4] as List<Order>);
      final completed = results[5] as List<Order>;
      final completedItemCounts = await _getCompletedItemCounts(completed);
      if (!mounted || loadVersion != _loadVersion) return;
      final stats = results[6] as Map<String, dynamic>;
      await _syncCourierPublicProfileMirror(
        userId: user.id,
        profile: profile,
        courierProfile: courierProfile,
      );

      if (mounted) {
        setState(() {
          _currentDelivery = current;
          _availableDeliveries = available;
          _completedDeliveries = completed;
          _completedItemCounts = completedItemCounts;
          _totalDeliveries = stats['deliveries'] ?? 0;
          _totalEarnings = (stats['earnings'] ?? 0).toDouble();
          _todayEarnings = (stats['todayEarnings'] ?? 0).toDouble();
          _weekEarnings = (stats['weekEarnings'] ?? 0).toDouble();
          _courierReviewCount = stats['reviewCount'] ?? 0;
          _onlineToday = Duration(
            seconds: (stats['onlineTodaySeconds'] ?? 0) as int,
          );
          _onlineTodayLoadedAt = MozambiqueTime.now();
          _loadingHistory = false;
          isOnline = courierProfile?['is_online'] == true;
          _courierRating =
              (courierProfile?['rating'] as num?)?.toDouble() ?? _courierRating;
          _walletBalance = (wallet?['balance'] as num?)?.toDouble() ?? 0;
          _walletCurrency = wallet?['currency']?.toString() ?? 'MZN';
          _courierSuspended = courierProfile?['is_suspended'] == true;
          _suspensionReason = courierProfile?['suspension_reason']?.toString();
          _pushActive = (profile?['fcm_token'] as String?)?.isNotEmpty == true;
        });
        _scheduleAvailableOfferExpiry();
        if (isOnline) {
          _startAvailableOfferRecovery();
        } else {
          _stopAvailableOfferRecovery();
        }
        unawaited(_ensureCourierOnlineSession(isOnline));
        unawaited(
          _syncCourierForegroundProtection(
            online: courierProfile?['is_online'] == true,
            currentDelivery: current,
            availableDeliveries: available.length,
          ),
        );
        _applyCourierDeliveryUpdate(
          previousOrder: previousCurrentDelivery,
          nextOrder: current,
        );
        if (_currentDelivery?.status != OrderStatus.arrived &&
            _currentDelivery?.status != OrderStatus.inTransit &&
            _currentDelivery?.status != OrderStatus.onTheWay) {
          _deliveryOtpController.clear();
          _verifyingDeliveryOtp = false;
        }
        _hydrateProfileState(profile, courierProfile);
      }

      // A Home operacional do estafeta deve iniciar a sessão online uma vez
      // por abertura da tela. O estado persistido continua sendo a fonte da
      // verdade; esta chamada apenas reutiliza o fluxo existente de ativação
      // (localização, heartbeat e refresh das ofertas).
      final canAutoGoOnline =
          !_autoOnlineAttempted &&
          !isOnline &&
          current == null &&
          kycStatus == 'approved' &&
          courierProfile?['is_suspended'] != true &&
          profile?['is_blocked'] != true;
      if (canAutoGoOnline) {
        _autoOnlineAttempted = true;
        debugPrint('[COURIER] Home abriu offline; ativando sessão online');
        unawaited(_setCourierOnline(true));
      }

      await _syncAvailableDeliveryDispatchSound(
        nextAvailable: available,
        nextCurrentDelivery: current,
      );

      await _loadSmartNotifications();

      await _loadCurrentLocation();
      await _loadWeather();

      // A posição exata inicial é sempre obtida acima para centrar o mapa.
      // O stream contínuo (e o respetivo foreground service Android) só é
      // necessário quando o estafeta está operacional, evitando encerrar o
      // processo em emuladores enquanto está simplesmente a consultar a app.
      if (isOnline || _currentDelivery != null) {
        _startLocationUpdates();
      }

      final settings =
          (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
      await WelcomeVoiceService.instance.greetOnce(
        userId: user.id,
        name: (profile?['full_name'] as String?)?.trim().isNotEmpty == true
            ? (profile?['full_name'] as String)
            : (user.email?.split('@').first ?? 'estafeta'),
        role: 'courier',
        gender: profile?['gender']?.toString(),
        languageCode: settings['language']?.toString(),
        voiceMode: settings['voice_mode']?.toString(),
      );
    } catch (e) {
      debugPrint('Erro ao carregar dados do estafeta: $e');
    }
  }

  Future<void> _loadWeather() async {
    final weather = await WeatherService.instance.fetchWeather(
      latitude: _currentPosition?.latitude,
      longitude: _currentPosition?.longitude,
      city: _workZoneController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _weather = weather);
  }

  String _formatLiveClock(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)} ${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  bool get _isCompactCourierViewport {
    if (!mounted) return false;
    final size = MediaQuery.sizeOf(context);
    return size.width < 380 || size.height < 700;
  }

  double get _courierMapZoom => _isCompactCourierViewport ? 16.1 : 16.8;

  double get _courierMapTilt => _isCompactCourierViewport ? 0 : 45;

  double _courierMapHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final availableHeight = math.max(
      0.0,
      size.height - MediaQuery.paddingOf(context).vertical,
    );
    // Do not force a 260px map into short landscape viewports.
    return (availableHeight * 0.44)
        .clamp(
          math.min(150.0, availableHeight),
          math.min(390.0, availableHeight),
        )
        .toDouble();
  }

  double _distanceBetweenLatLng(LatLng start, LatLng end) {
    return Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
  }

  String _money(double value) => '${value.toStringAsFixed(2)} MZN';

  Future<void> _syncCourierPublicProfileMirror({
    required String userId,
    Map<String, dynamic>? profile,
    Map<String, dynamic>? courierProfile,
  }) async {
    final profileName = profile?['full_name']?.toString().trim() ?? '';
    final profilePhone = profile?['phone']?.toString().trim() ?? '';
    final profileAvatar = profile?['avatar_url']?.toString().trim() ?? '';
    final courierName = courierProfile?['full_name']?.toString().trim() ?? '';
    final courierPhone = courierProfile?['phone']?.toString().trim() ?? '';
    final courierAvatar =
        courierProfile?['avatar_url']?.toString().trim() ?? '';

    final needsSync =
        (profileName.isNotEmpty && profileName != courierName) ||
        (profilePhone.isNotEmpty && profilePhone != courierPhone) ||
        profileAvatar != courierAvatar;
    if (!needsSync) return;

    try {
      await supabase.from('couriers').upsert({
        'id': userId,
        if (profileName.isNotEmpty) 'full_name': profileName,
        if (profilePhone.isNotEmpty) 'phone': profilePhone,
        'avatar_url': profileAvatar.isNotEmpty ? profileAvatar : null,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');
    } catch (error) {
      debugPrint('Falha ao sincronizar perfil publico do estafeta: $error');
    }
  }

  Widget _buildWeatherClockBanner() {
    final weatherLine = _weather != null
        ? '${_weather!.temperatureC.toStringAsFixed(0)} C - ${_weather!.condition}'
        : (_workZoneController.text.trim().isNotEmpty
              ? _workZoneController.text.trim()
              : 'Condicoes do dia indisponiveis');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3ED), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tempo e hora do dia',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            weatherLine,
            style: const TextStyle(color: AppColors.neutralGray),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StreamBuilder<DateTime>(
                stream: Stream<DateTime>.periodic(
                  const Duration(seconds: 1),
                  (_) => MozambiqueTime.now(),
                ),
                initialData: MozambiqueTime.now(),
                builder: (context, snapshot) => _buildSummaryPill(
                  Icons.schedule_rounded,
                  _formatLiveClock(snapshot.data ?? MozambiqueTime.now()),
                ),
              ),
              if (_weather != null)
                _buildSummaryPill(Icons.thermostat_rounded, 'C'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primaryRed),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Future<void> _refreshDeliveriesAndStats() async {
    final loadVersion = ++_loadVersion;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final previousCurrentDelivery = _currentDelivery;
    final results = await Future.wait<dynamic>([
      _deliveryService.getCurrentDelivery(user.id),
      _deliveryService.getAvailableDeliveries(),
      _getCompletedDeliveries(),
      _getCourierStats(user.id),
    ]);
    if (!mounted || loadVersion != _loadVersion) return;
    final completed = results[2] as List<Order>;
    final completedItemCounts = await _getCompletedItemCounts(completed);
    if (!mounted || loadVersion != _loadVersion) return;
    final available = _prepareAvailableOffers(results[1] as List<Order>);
    setState(() {
      _currentDelivery = results[0] as Order?;
      _availableDeliveries = available;
      _completedDeliveries = completed;
      _completedItemCounts = completedItemCounts;
      final stats = results[3] as Map<String, dynamic>;
      _totalDeliveries = stats['deliveries'] ?? _totalDeliveries;
      _totalEarnings = (stats['earnings'] ?? _totalEarnings).toDouble();
      _loadingHistory = false;
    });
    _scheduleAvailableOfferExpiry();
    unawaited(_primeAvailableDeliveryDetails(_availableDeliveries));
    unawaited(
      _syncCourierForegroundProtection(
        online: isOnline,
        currentDelivery: _currentDelivery,
        availableDeliveries: _availableDeliveries.length,
      ),
    );
    await _syncAvailableDeliveryDispatchSound(
      nextAvailable: results[1] as List<Order>,
      nextCurrentDelivery: results[0] as Order?,
    );
    _applyCourierDeliveryUpdate(
      previousOrder: previousCurrentDelivery,
      nextOrder: _currentDelivery,
    );
    if (_currentDelivery?.status != OrderStatus.arrived &&
        _currentDelivery?.status != OrderStatus.inTransit &&
        _currentDelivery?.status != OrderStatus.onTheWay) {
      _deliveryOtpController.clear();
      _verifyingDeliveryOtp = false;
    }
  }

  Future<void> _refreshAvailableOffersImmediately() async {
    if (_availableOfferRefreshInFlight) return;
    _availableOfferRefreshInFlight = true;
    try {
      final available = _prepareAvailableOffers(
        await _deliveryService.getAvailableDeliveries(),
      );
      if (!mounted) return;
      setState(() => _availableDeliveries = available);
      _scheduleAvailableOfferExpiry();
      unawaited(_primeAvailableDeliveryDetails(available));
      unawaited(
        _syncAvailableDeliveryDispatchSound(
          nextAvailable: available,
          nextCurrentDelivery: _currentDelivery,
        ),
      );
    } catch (error) {
      debugPrint('[COURIER_OFFER] immediate refresh failed: $error');
    } finally {
      _availableOfferRefreshInFlight = false;
    }
  }

  void _startAvailableOfferRecovery() {
    _availableOfferRecoveryTimer?.cancel();
    // Realtime/FCM remains the fast path. This short server refresh is only a
    // recovery path for delayed/missed transports and never creates deadlines.
    _availableOfferRecoveryTimer = Timer.periodic(const Duration(seconds: 3), (
      _,
    ) {
      if (!mounted) return;
      unawaited(_refreshAvailableOffersImmediately());
    });
  }

  void _stopAvailableOfferRecovery() {
    _availableOfferRecoveryTimer?.cancel();
    _availableOfferRecoveryTimer = null;
  }

  Future<void> _primeAvailableDeliveryDetails(List<Order> orders) async {
    final position = _currentPosition == null
        ? _displayCourierLatLng
        : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    for (final order in orders) {
      unawaited(_loadAvailableOrderItems(order.id));
      if (position != null) unawaited(_loadAvailableRoutePlan(order, position));
    }
  }

  Future<List<OrderItem>> _loadAvailableOrderItems(String orderId) {
    final cached = _availableOrderItems[orderId];
    if (cached != null) return Future.value(cached);
    return _availableOrderItemsInFlight.putIfAbsent(orderId, () async {
      _availableOrderItemsFailed.remove(orderId);
      try {
        final details = await _deliveryService.getCourierOfferDetails(orderId);
        if (details == null) {
          throw StateError('offer_not_authorized_or_expired');
        }
        _availableOrderItems[orderId] = details.items;
        _availableCourierAmounts[orderId] = details.courierAmount;
        if (mounted) setState(() {});
        return details.items;
      } catch (error) {
        _availableOrderItemsFailed.add(orderId);
        debugPrint('[COURIER_OFFER] items failed order=$orderId: $error');
        if (mounted) setState(() {});
        return const <OrderItem>[];
      } finally {
        _availableOrderItemsInFlight.remove(orderId);
      }
    });
  }

  String? _availableRouteRequestKey(Order order, LatLng origin) {
    final destination = _latLng(
      order.pickupLatitude ?? order.restaurantLatitude,
      order.pickupLongitude ?? order.restaurantLongitude,
    );
    if (destination == null) return null;
    // Bucket the live origin so tiny GPS jitter does not trigger routing.
    return '${order.id}:${origin.latitude.toStringAsFixed(3)},'
        '${origin.longitude.toStringAsFixed(3)}:'
        '${destination.latitude.toStringAsFixed(5)},'
        '${destination.longitude.toStringAsFixed(5)}';
  }

  Future<RoutePlan?> _loadAvailableRoutePlan(Order order, LatLng origin) {
    final destination = _latLng(
      order.pickupLatitude ?? order.restaurantLatitude,
      order.pickupLongitude ?? order.restaurantLongitude,
    );
    final key = _availableRouteRequestKey(order, origin);
    if (destination == null || key == null) return Future.value(null);
    return _availableRoutePlans.putIfAbsent(key, () async {
      try {
        final plan = await MapsRouteService.getCachedRoutePlan(
          cacheKey: 'courier-offer-${order.id}',
          origin: origin,
          destination: destination,
          travelMode: 'driving',
        );
        if (mounted) setState(() {});
        return plan;
      } catch (error) {
        debugPrint('[COURIER_OFFER] route failed order=${order.id}: $error');
        if (mounted) setState(() {});
        return null;
      }
    });
  }

  Order? get _lastCompletedDelivery =>
      _completedDeliveries.isEmpty ? null : _completedDeliveries.first;

  void _handleRealtimeOrderChange({
    required Map<String, dynamic> previousRecord,
    required Map<String, dynamic> nextRecord,
  }) {
    final currentUserId = supabase.auth.currentUser?.id;
    final affectsDashboard =
        CourierDispatchUtils.affectsCourierDashboardOrderChange(
          previousRecord: previousRecord,
          nextRecord: nextRecord,
          currentCourierId: currentUserId,
        );
    if (!affectsDashboard || !mounted) return;

    if (CourierDispatchUtils.becameAvailableDelivery(
      previousRecord: previousRecord,
      nextRecord: nextRecord,
    )) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Novo pedido perto de si. Vale a pena ver agora.'),
          ),
        );
    } else if (CourierDispatchUtils.leftAvailableDelivery(
      previousRecord: previousRecord,
      nextRecord: nextRecord,
    )) {
      final orderId = previousRecord['id']?.toString();
      if (orderId != null && orderId.trim().isNotEmpty) {
        unawaited(
          SoundController.instance.stopCourierDispatchLoop(orderId: orderId),
        );
      }
    }

    _applyImmediateCourierOrderRealtimeChange(
      previousRecord: previousRecord,
      nextRecord: nextRecord,
      currentCourierId: currentUserId,
    );
    _scheduleCourierDataRefresh();
  }

  void _applyImmediateCourierOrderRealtimeChange({
    required Map<String, dynamic> previousRecord,
    required Map<String, dynamic> nextRecord,
    required String? currentCourierId,
  }) {
    final currentDelivery = _currentDelivery;
    if (currentDelivery == null || currentCourierId == null) return;

    final nextCourierId = nextRecord['courier_id']?.toString().trim();
    final previousCourierId = previousRecord['courier_id']?.toString().trim();
    final nextOrderId = nextRecord['id']?.toString().trim();
    final previousOrderId = previousRecord['id']?.toString().trim();

    final affectsCurrentDelivery =
        nextOrderId == currentDelivery.id ||
        previousOrderId == currentDelivery.id ||
        nextCourierId == currentCourierId ||
        previousCourierId == currentCourierId;
    if (!affectsCurrentDelivery) return;

    final mergedNextRecord = <String, dynamic>{
      ...currentDelivery.toMap(),
      ...nextRecord,
    };
    final mergedPreviousRecord = <String, dynamic>{
      ...currentDelivery.toMap(),
      ...previousRecord,
    };
    final previousOrder = Order.fromMap(mergedPreviousRecord);
    final nextOrder = Order.fromMap(mergedNextRecord);

    if (previousOrder.id != nextOrder.id ||
        previousOrder.status == nextOrder.status) {
      return;
    }

    // A server-confirmed terminal delivery must disappear from the active
    // route immediately. Realtime refresh remains responsible for the full
    // reconciliation, but the old route must never remain interactive while
    // that refresh is in flight.
    if (_isClosedCourierOrderStatus(nextOrder.status)) {
      setState(() {
        _currentDelivery = null;
        _homeRouteFuture = null;
        _homeRouteInfoFuture = null;
        _homeRouteKey = null;
        _homeEndpointFuture = null;
        _homeEndpointKey = null;
        _homeResolvedEndpoint = null;
        _deliveryOtpController.clear();
        _verifyingDeliveryOtp = false;
        _updatingDeliveryStatus = false;
      });
      _applyCourierDeliveryUpdate(
        previousOrder: previousOrder,
        nextOrder: nextOrder,
      );
      return;
    }

    setState(() {
      _currentDelivery = nextOrder;
      if (nextOrder.status != OrderStatus.arrived &&
          nextOrder.status != OrderStatus.inTransit &&
          nextOrder.status != OrderStatus.onTheWay) {
        _deliveryOtpController.clear();
        _verifyingDeliveryOtp = false;
      }
    });

    _applyCourierDeliveryUpdate(
      previousOrder: previousOrder,
      nextOrder: nextOrder,
    );
  }

  Future<void> _syncAvailableDeliveryDispatchSound({
    required List<Order> nextAvailable,
    required Order? nextCurrentDelivery,
  }) async {
    final soundController = SoundController.instance;
    final activeDispatchOrderId = soundController.courierDispatchOrderId
        ?.trim();
    final activeDispatchAttemptId = soundController.courierDispatchAttemptId
        ?.trim();

    if (nextCurrentDelivery != null) {
      if (soundController.isCourierDispatchLoopActive) {
        if (activeDispatchOrderId != null && activeDispatchOrderId.isNotEmpty) {
          await soundController.stopCourierDispatchLoop(
            orderId: activeDispatchOrderId,
          );
        } else {
          await soundController.stopCourierDispatchLoop();
        }
      }
      return;
    }

    if (soundController.isCourierDispatchLoopActive && nextAvailable.isEmpty) {
      if (activeDispatchOrderId != null && activeDispatchOrderId.isNotEmpty) {
        await soundController.stopCourierDispatchLoop(
          orderId: activeDispatchOrderId,
        );
      } else {
        await soundController.stopCourierDispatchLoop();
      }
      return;
    }

    Order? activeOffer;
    if (activeDispatchOrderId != null) {
      for (final order in nextAvailable) {
        if (order.id == activeDispatchOrderId) {
          activeOffer = order;
          break;
        }
      }
    }
    if (soundController.isCourierDispatchLoopActive &&
        (activeOffer == null ||
            activeOffer.dispatchAttemptId != activeDispatchAttemptId)) {
      await soundController.stopCourierDispatchLoop(
        orderId: activeDispatchOrderId,
      );
    }
  }

  void _scheduleCourierDataRefresh() {
    _ordersRefreshDebounce?.cancel();
    _ordersRefreshDebounce = Timer(const Duration(milliseconds: 120), () {
      _refreshDeliveriesAndStats();
    });
  }

  void _scheduleProfileRefresh() {
    _profileRefreshDebounce?.cancel();
    _profileRefreshDebounce = Timer(const Duration(milliseconds: 500), () {
      _loadCourierData();
    });
  }

  void _scheduleNotificationsRefresh() {
    _notificationsRefreshDebounce?.cancel();
    _notificationsRefreshDebounce = Timer(
      const Duration(milliseconds: 300),
      () {
        _loadSmartNotifications();
      },
    );
  }

  Future<void> _initRealtimeProfile() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    await _profileChannel?.unsubscribe();
    await _courierChannel?.unsubscribe();
    await _walletChannel?.unsubscribe();
    await _notificationsChannel?.unsubscribe();

    _profileChannel = supabase.channel('courier-profile-$userId');
    _profileChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleProfileRefresh();
          },
        )
        .subscribe();

    _courierChannel = supabase.channel('courier-meta-$userId');
    _courierChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'couriers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleProfileRefresh();
          },
        )
        .subscribe();

    _walletChannel = supabase.channel('courier-wallet-$userId');
    _walletChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleProfileRefresh();
          },
        )
        .subscribe();

    _notificationsChannel = supabase.channel('courier-notifications-$userId');
    _notificationsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'push_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            if (payload.eventType == PostgresChangeEvent.insert &&
                payload.newRecord.isNotEmpty) {
              final notification = Map<String, dynamic>.from(payload.newRecord);
              _rememberCourierOfferDeadline(notification);
              _showRealtimeNotificationPopup(notification);
              final notificationType = notification['type']
                  ?.toString()
                  .trim()
                  .toUpperCase();
              final notificationChannel = notification['channel']
                  ?.toString()
                  .trim()
                  .toLowerCase();
              // The push sound and the Realtime row can arrive with slightly
              // different payload nesting. Refresh on the canonical offer
              // type/channel as well as the strict deadline contract, so a
              // valid second round cannot ring without updating Home.
              if (CourierOfferFeedbackDeadline.isCourierOfferPayload(
                    notification,
                  ) ||
                  notificationType == 'DELIVERY_OPPORTUNITY' ||
                  notificationChannel == 'courier_dispatch') {
                // Offer cards are latency-critical. Refresh only the
                // targeted offer list first; history/stats can update later.
                unawaited(_refreshAvailableOffersImmediately());
              }
            }
            _scheduleNotificationsRefresh();
          },
        )
        .subscribe();
  }

  String _offerStateKey(Order order) =>
      '${order.id}:${order.dispatchAttemptId?.trim() ?? ''}';

  List<Order> _prepareAvailableOffers(List<Order> orders) {
    final now = DateTime.now().toUtc();
    final valid = <Order>[];
    for (final order in orders) {
      final attemptId = order.dispatchAttemptId?.trim() ?? '';
      final key = _offerStateKey(order);
      if (attemptId.isEmpty || order.dispatchExpiresAt == null) continue;

      final deadline = CourierOfferVisibilityDeadline.calculate(
        receivedAt: now,
        dispatchExpiresAt: order.dispatchExpiresAt,
        serverOfferExpiresAt:
            CourierOfferVisibilityDeadline.activeCachedDeadline(
              _availableOfferDeadlines[key],
              now: now,
            ),
        hasAttemptId: true,
      );
      if (deadline == null) continue;

      final previousDeadline = _availableOfferDeadlines[key];
      _availableOfferDeadlines[key] =
          !CourierOfferVisibilityDeadline.shouldReplaceCachedDeadline(
            current: previousDeadline,
            incoming: deadline,
            now: now,
          )
          ? previousDeadline!
          : deadline;
      valid.add(order);
    }

    _availableOfferDeadlines.removeWhere(
      (key, deadline) =>
          deadline.isBefore(now.subtract(const Duration(minutes: 1))),
    );
    while (_availableOfferDeadlines.length > 128) {
      _availableOfferDeadlines.remove(_availableOfferDeadlines.keys.first);
    }
    _scheduleAvailableOfferExpiry();
    return valid;
  }

  void _rememberCourierOfferDeadline(Map<dynamic, dynamic> payload) {
    final deadline = CourierOfferFeedbackDeadline.fromCourierOfferPayload(
      payload,
      now: DateTime.now().toUtc(),
    );
    final attemptId = CourierOfferFeedbackDeadline.attemptIdFromPayload(
      payload,
    );
    final orderId = _offerPayloadValue(payload, const [
      'order_id',
      'entity_id',
      'pedido_id',
    ]);
    if (deadline == null || attemptId == null || orderId == null) return;

    final key = '$orderId:$attemptId';
    final current = _availableOfferDeadlines[key];
    if (CourierOfferVisibilityDeadline.shouldReplaceCachedDeadline(
      current: current,
      incoming: deadline,
    )) {
      _availableOfferDeadlines[key] = deadline.toUtc();
    }
    _scheduleAvailableOfferExpiry();
  }

  String? _offerPayloadValue(Map<dynamic, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key]?.toString().trim();
      if (value?.isNotEmpty == true) return value;
    }
    for (final key in const ['metadata', 'data']) {
      var nested = payload[key];
      if (nested is String && nested.trim().startsWith('{')) {
        try {
          nested = jsonDecode(nested);
        } catch (_) {
          continue;
        }
      }
      if (nested is Map) {
        final value = _offerPayloadValue(nested, keys);
        if (value != null) return value;
      }
    }
    return null;
  }

  DateTime? _offerDeadlineFor(Order order) =>
      _availableOfferDeadlines[_offerStateKey(order)];

  bool _isOfferActionable(Order order) {
    final attemptId = order.dispatchAttemptId?.trim() ?? '';
    final deadline = _offerDeadlineFor(order);
    return attemptId.isNotEmpty &&
        deadline != null &&
        deadline.isAfter(DateTime.now().toUtc()) &&
        order.dispatchExpiresAt?.isAfter(DateTime.now().toUtc()) == true;
  }

  void _scheduleAvailableOfferExpiry() {
    _availableOfferExpiryTimer?.cancel();
    _offerCountdownTimer?.cancel();
    if (!mounted || _availableDeliveries.isEmpty) return;
    // This timer only repaints the visible countdown. The deadline stored from
    // the server remains the sole authority for validity and acceptance.
    _offerCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _availableDeliveries.isEmpty) {
        _offerCountdownTimer?.cancel();
        return;
      }
      setState(() {});
    });
    final deadlines = _availableDeliveries
        .map(_offerDeadlineFor)
        .whereType<DateTime>()
        .toList();
    if (deadlines.isEmpty) return;
    deadlines.sort();
    final delay = deadlines.first.difference(DateTime.now().toUtc());
    _availableOfferExpiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      _expireVisibleCourierOffers,
    );
  }

  void _expireVisibleCourierOffers() {
    if (!mounted) return;
    final now = DateTime.now().toUtc();
    final expired = _availableDeliveries
        .where((order) => !(_offerDeadlineFor(order)?.isAfter(now) ?? false))
        .toList(growable: false);
    if (expired.isEmpty) {
      _scheduleAvailableOfferExpiry();
      return;
    }

    final expiredIds = expired.map((order) => order.id).toSet();
    setState(() {
      _availableDeliveries.removeWhere(
        (order) => expiredIds.contains(order.id),
      );
    });
    for (final order in expired) {
      _clearAvailableOfferCache(order.id);
    }
    unawaited(
      _syncAvailableDeliveryDispatchSound(
        nextAvailable: _availableDeliveries,
        nextCurrentDelivery: _currentDelivery,
      ),
    );
    unawaited(
      _syncCourierForegroundProtection(
        online: isOnline,
        currentDelivery: _currentDelivery,
        availableDeliveries: _availableDeliveries.length,
      ),
    );
    _scheduleAvailableOfferExpiry();
    unawaited(_refreshAvailableOffersAfterExpiry());
  }

  String _availableOfferRemainingLabel(Order order) {
    final deadline = _offerDeadlineFor(order);
    if (deadline == null) return '—';
    final remaining = deadline.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) return '00:00';
    final totalSeconds = remaining.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  int _availableOfferRemainingSeconds(Order order) {
    final deadline = _offerDeadlineFor(order);
    if (deadline == null) return 0;
    final remaining = deadline.difference(DateTime.now().toUtc());
    return remaining <= Duration.zero ? 0 : remaining.inSeconds;
  }

  void _clearAvailableOfferCache(String orderId) {
    _availableOrderItems.remove(orderId);
    _availableOrderItemsFailed.remove(orderId);
    _availableCourierAmounts.remove(orderId);
    _expandedOfferOrderIds.remove(orderId);
    _availableOfferDeadlines.removeWhere(
      (key, _) => key.startsWith('$orderId:'),
    );
    _availableRoutePlans.removeWhere((key, _) => key.startsWith('$orderId:'));
  }

  Future<void> _refreshAvailableOffersAfterExpiry() async {
    final loadVersion = _loadVersion;
    final requestVersion = ++_availableOfferRefreshVersion;
    final rows = await _deliveryService.getAvailableDeliveries();
    if (!mounted ||
        loadVersion != _loadVersion ||
        requestVersion != _availableOfferRefreshVersion) {
      return;
    }
    final available = _prepareAvailableOffers(rows);
    setState(() => _availableDeliveries = available);
    _scheduleAvailableOfferExpiry();
    unawaited(_primeAvailableDeliveryDetails(available));
    await _syncAvailableDeliveryDispatchSound(
      nextAvailable: available,
      nextCurrentDelivery: _currentDelivery,
    );
    unawaited(
      _syncCourierForegroundProtection(
        online: isOnline,
        currentDelivery: _currentDelivery,
        availableDeliveries: available.length,
      ),
    );
  }

  void _applyCourierDeliveryUpdate({
    required Order? previousOrder,
    required Order? nextOrder,
  }) {
    if (!mounted) return;

    if (previousOrder == null && nextOrder == null) return;

    if (previousOrder == null && nextOrder != null) {
      _showCourierDeliveryPopupOnce(
        popupKey: 'assigned:${nextOrder.id}:${nextOrder.status.name}',
        title: 'Entrega atribuida',
        message: 'Um pedido entrou na sua rota agora.',
        backgroundColor: AppColors.primaryRed,
        icon: Icons.delivery_dining_rounded,
        playSound: true,
        duration: _popupDuration,
      );
      return;
    }

    if (previousOrder != null && nextOrder == null) {
      if (_isClosedCourierOrderStatus(previousOrder.status)) {
        return;
      }
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _showCourierDeliveryPopupOnce(
        popupKey: 'removed:${previousOrder.id}:${previousOrder.status.name}',
        title: 'Entrega concluida',
        message: 'A entrega saiu da sua rota atual.',
        backgroundColor: AppColors.successGreen,
        icon: Icons.check_circle_outline_rounded,
        duration: const Duration(milliseconds: 850),
      );
      return;
    }

    if (previousOrder == null || nextOrder == null) return;
    if (previousOrder.id != nextOrder.id) {
      _showCourierDeliveryPopupOnce(
        popupKey:
            'switched:${previousOrder.id}->${nextOrder.id}:${nextOrder.status.name}',
        title: 'Nova entrega',
        message: 'Tem um novo pedido na sua rota.',
        backgroundColor: AppColors.primaryRed,
        icon: Icons.route_rounded,
        playSound: true,
        duration: _popupDuration,
      );
      return;
    }
    if (previousOrder.status == nextOrder.status) return;

    switch (nextOrder.status) {
      case OrderStatus.courierAssigned:
        break;
      case OrderStatus.inTransit:
      case OrderStatus.onTheWay:
        _showCourierDeliveryPopupOnce(
          popupKey:
              'status:${nextOrder.id}:${previousOrder.status.name}->${nextOrder.status.name}',
          title: 'Entrega em curso',
          message: 'Siga para o cliente. A entrega ja esta em andamento.',
          backgroundColor: const Color(0xFF102A43),
          icon: Icons.local_shipping_outlined,
        );
        break;
      case OrderStatus.arrived:
        _showCourierDeliveryPopupOnce(
          popupKey:
              'status:${nextOrder.id}:${previousOrder.status.name}->${nextOrder.status.name}',
          title: 'Chegou ao destino',
          message: 'Confirme a entrega com o cliente.',
          backgroundColor: const Color(0xFF7C2D12),
          icon: Icons.place_rounded,
          duration: _popupDuration,
        );
        break;
      case OrderStatus.delivered:
      case OrderStatus.completed:
      case OrderStatus.autoCompleted:
        final closedPopupKey = 'closed:${nextOrder.id}';
        if (_closedDeliveryPopupOrderIds.contains(nextOrder.id)) {
          return;
        }
        _closedDeliveryPopupOrderIds.add(nextOrder.id);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showCourierDeliveryPopupOnce(
          popupKey: closedPopupKey,
          title: 'Entrega concluida',
          message: 'Pedido entregue com sucesso.',
          backgroundColor: AppColors.successGreen,
          icon: Icons.check_circle_outline_rounded,
          duration: const Duration(milliseconds: 850),
        );
        break;
      case OrderStatus.deliveryFailedOtp:
        _showCourierDeliveryPopupOnce(
          popupKey:
              'status:${nextOrder.id}:${previousOrder.status.name}->${nextOrder.status.name}',
          title: 'Falha no OTP',
          message: 'O codigo OTP falhou. Revise antes de concluir.',
          backgroundColor: Colors.orange.shade700,
          icon: Icons.sms_failed_rounded,
        );
        break;
      case OrderStatus.cancelled:
        _showCourierDeliveryPopupOnce(
          popupKey:
              'status:${nextOrder.id}:${previousOrder.status.name}->${nextOrder.status.name}',
          title: 'Pedido cancelado',
          message: 'Este pedido foi cancelado.',
          backgroundColor: Colors.orange.shade700,
          icon: Icons.cancel_outlined,
        );
        break;
      default:
        break;
    }
  }

  void _showCourierDeliveryPopupOnce({
    required String popupKey,
    required String title,
    required String message,
    required Color backgroundColor,
    required IconData icon,
    bool playSound = false,
    Duration duration = _popupDuration,
  }) {
    if (_lastCourierDeliveryPopupKey == popupKey) return;
    _lastCourierDeliveryPopupKey = popupKey;
    _showOrderStatePopup(
      title: title,
      message: message,
      backgroundColor: backgroundColor,
      icon: icon,
      playSound: playSound,
      duration: duration,
    );
  }

  bool _isClosedCourierOrderStatus(OrderStatus status) {
    return status == OrderStatus.delivered ||
        status == OrderStatus.completed ||
        status == OrderStatus.autoCompleted;
  }

  void _showOrderStatePopup({
    required String title,
    required String message,
    required Color backgroundColor,
    required IconData icon,
    bool playSound = false,
    Duration duration = _popupDuration,
  }) {
    unawaited(SoundController.instance.shortBang());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: backgroundColor,
          duration: duration,
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(message, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _showRealtimeNotificationPopup(Map<String, dynamic> notification) {
    final type = notification['type']?.toString() ?? '';
    if (_shouldSuppressRealtimeNotificationPopup(type)) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      return;
    }
    final popup = _realtimePopupFor(type);
    if (popup == null) return;

    final title = notification['title']?.toString().trim();
    final body = notification['body']?.toString().trim();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    if (!{
      'ORDER_READY_FOR_PICKUP',
      'NEW_DRIVER_ORDER',
      'DELIVERY_OPPORTUNITY',
    }.contains(type)) {
      // PushNotificationService owns the bounded dispatch loop for offers.
      // Avoid adding a second independent sound on the dashboard Realtime path.
      unawaited(SoundController.instance.shortBang());
    }
    final duration = switch (type) {
      'ORDER_DELIVERED' ||
      'ORDER_COMPLETED' ||
      'ORDER_AUTO_COMPLETED' => const Duration(milliseconds: 850),
      _ => _popupDuration,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: popup.backgroundColor,
          duration: duration,
          content: Row(
            children: [
              Icon(popup.icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title?.isNotEmpty == true ? title! : 'Nova mensagem',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (body?.isNotEmpty == true)
                      Text(body!, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  bool _shouldSuppressRealtimeNotificationPopup(String type) {
    final currentDelivery = _currentDelivery;
    if (currentDelivery == null) return false;

    final status = currentDelivery.status;
    final isClosed =
        status == OrderStatus.delivered ||
        status == OrderStatus.completed ||
        status == OrderStatus.autoCompleted;

    switch (type) {
      case 'ORDER_PICKED_UP':
        return status == OrderStatus.inTransit ||
            status == OrderStatus.onTheWay ||
            status == OrderStatus.arrived ||
            isClosed;
      case 'DRIVER_ARRIVED':
        return status == OrderStatus.arrived || isClosed;
      case 'ORDER_DELIVERED':
        return status == OrderStatus.delivered ||
            status == OrderStatus.completed ||
            status == OrderStatus.autoCompleted;
      case 'ORDER_COMPLETED':
      case 'ORDER_AUTO_COMPLETED':
        return status == OrderStatus.completed ||
            status == OrderStatus.autoCompleted;
      default:
        return false;
    }
  }

  ({Color backgroundColor, IconData icon})? _realtimePopupFor(String type) {
    switch (type) {
      case 'MESSAGE_RECEIVED':
        return (
          backgroundColor: const Color(0xFF102A43),
          icon: Icons.mark_chat_unread_rounded,
        );
      case 'ORDER_READY_FOR_PICKUP':
      case 'NEW_DRIVER_ORDER':
      case 'DELIVERY_OPPORTUNITY':
        return (
          backgroundColor: AppColors.primaryRed,
          icon: Icons.delivery_dining_rounded,
        );
      case 'ORDER_CANCELLED':
      case 'ORDER_EXPIRED':
      case 'PAYMENT_FAILED':
        return (
          backgroundColor: Colors.orange.shade700,
          icon: Icons.cancel_outlined,
        );
      case 'DRIVER_ARRIVED':
      case 'ORDER_PICKED_UP':
        return (
          backgroundColor: const Color(0xFF7C2D12),
          icon: Icons.local_shipping_outlined,
        );
      default:
        return null;
    }
  }

  Future<Map<String, dynamic>> _getCourierStats(String courierId) async {
    try {
      final deliveriesResponse = await supabase
          .from('orders')
          .select(
            'id, updated_at, created_at, payment_splits(courier_amount,status)',
          )
          .eq('courier_id', courierId)
          // `delivered` only means OTP was verified. Earnings are available
          // after the client's final confirmation closes the order.
          .inFilter('status', ['completed', 'auto_completed']);

      final now = MozambiqueTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final weekStart = todayStart.subtract(
        Duration(days: todayStart.weekday - 1),
      );
      int count = (deliveriesResponse as List).length;
      double earnings = 0;
      double todayEarnings = 0;
      double weekEarnings = 0;

      for (var order in deliveriesResponse) {
        final split = order['payment_splits'];
        final splitRow = split is List && split.isNotEmpty
            ? split.first
            : split is Map
            ? split
            : null;
        // The payment split is the financial authority. Do not derive the
        // courier earning from delivery_fee or a UI commission constant.
        if (splitRow is! Map || splitRow['status']?.toString() != 'completed') {
          continue;
        }
        final courierNet = (splitRow['courier_amount'] as num?)?.toDouble() ?? 0;
        earnings += courierNet;
        final completedAt =
            MozambiqueTime.tryParse(
              order['updated_at'] ?? order['created_at'],
            ) ??
            now;
        if (!completedAt.isBefore(todayStart)) todayEarnings += courierNet;
        if (!completedAt.isBefore(weekStart)) weekEarnings += courierNet;
      }

      var reviewCount = 0;
      try {
        final reviews = await supabase
            .from('courier_reviews')
            .select('id')
            .eq('courier_id', courierId);
        reviewCount = (reviews as List).length;
      } catch (_) {
        // A política de avaliações pode não estar disponível em instalações antigas.
      }

      var onlineTodaySeconds = 0;
      try {
        final online = await supabase.rpc('get_courier_online_today_seconds');
        onlineTodaySeconds = (online as num?)?.toInt() ?? 0;
      } catch (_) {
        // A migração de sessões é aditiva. Sem ela, não apresentamos uma estimativa falsa.
      }

      return {
        'deliveries': count,
        'earnings': earnings,
        'todayEarnings': todayEarnings,
        'weekEarnings': weekEarnings,
        'reviewCount': reviewCount,
        'onlineTodaySeconds': onlineTodaySeconds,
      };
    } catch (e) {
      return {
        'deliveries': 0,
        'earnings': 0,
        'todayEarnings': 0,
        'weekEarnings': 0,
        'reviewCount': 0,
        'onlineTodaySeconds': 0,
      };
    }
  }

  void _hydrateProfileState(
    Map<String, dynamic>? profile,
    Map<String, dynamic>? courierProfile,
  ) {
    _profileData = profile == null ? null : Map<String, dynamic>.from(profile);
    final settings =
        (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final notifications =
        (settings['notifications'] as Map?)?.cast<String, dynamic>() ?? {};
    _profileSettings = Map<String, dynamic>.from(settings);
    _avatarUrl = profile?['avatar_url']?.toString();
    _nameController.text = profile?['full_name']?.toString() ?? '';
    _phoneController.text = profile?['phone']?.toString() ?? '';
    _workZoneController.text =
        settings['courier_work_zone']?.toString() ??
        profile?['address']?.toString() ??
        '';
    _preferredPaymentMethod =
        profile?['preferred_payment_method']?.toString().isNotEmpty == true
        ? profile!['preferred_payment_method'].toString()
        : 'm-pesa';
    _pushNotificationsEnabled = notifications['push'] != false;
    _orderSoundsEnabled =
        (settings['sound_enabled'] as bool?) ??
        notifications['order_status'] != false;
    _languageCode = settings['language']?.toString() ?? 'pt';
    _voiceMode = settings['voice_mode']?.toString() ?? 'important_only';
    _courierRating =
        (courierProfile?['rating'] as num?)?.toDouble() ?? _courierRating;
    _applyDefaultCourierProfile();
  }

  bool _isDeligoBikerAccount() {
    return true;
  }

  void _applyDefaultCourierProfile() {
    final profileData = _profileData;
    final paymentContact = profileData == null
        ? null
        : profileData['payment_contact'];
    final phone = profileData == null ? null : profileData['phone'];
    final paymentContactText = paymentContact?.toString().trim();
    final phoneText = phone?.toString().trim();
    final profilePhone =
        (paymentContactText != null && paymentContactText.isNotEmpty)
        ? paymentContactText
        : phoneText;
    if (_nameController.text.trim().isEmpty && _isDeligoBikerAccount()) {
      _nameController.text = 'Deligo Biker';
    }
    if (_phoneController.text.trim().isEmpty && _isDeligoBikerAccount()) {
      if (profilePhone != null && profilePhone.isNotEmpty) {
        _phoneController.text = profilePhone;
      }
    }
    if (_workZoneController.text.trim().isEmpty) {
      final inferredZone = _deduceMozCityFromPosition(_currentPosition);
      if (inferredZone != null) {
        _workZoneController.text = inferredZone;
      }
    }
  }

  String? _normalizePhoneForStorage(String raw) {
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return null;

    String localDigits;
    if (digitsOnly.startsWith('258')) {
      localDigits = digitsOnly.substring(3);
    } else if (digitsOnly.startsWith('0')) {
      localDigits = digitsOnly.substring(1);
    } else {
      localDigits = digitsOnly;
    }

    final mozRegex = RegExp(r'^[8-9]\d{8}$');
    if (!mozRegex.hasMatch(localDigits)) {
      return null;
    }

    return '+258$localDigits';
  }

  String _normalizedPaymentContact() {
    final normalizedWallet = _normalizePhoneForStorage(_phoneController.text);
    if (normalizedWallet != null) {
      return normalizedWallet.replaceFirst('+258', '');
    }
    return _phoneController.text.trim();
  }

  String _displayPaymentContact(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('+258') && trimmed.length == 13) {
      return trimmed.substring(4);
    }
    return trimmed;
  }

  String? _deduceMozCityFromPosition(Position? position) {
    if (position == null) return null;
    if (position.latitude <= -25.86) {
      return 'Matola';
    }
    return 'Maputo';
  }

  String _fallbackLocationLabel(Position position) {
    final city = _deduceMozCityFromPosition(position) ?? 'Moçambique';
    return '$city • Localização atual';
  }

  String _fallbackLocationLabelForLatLng(LatLng position) {
    final city = position.latitude <= -25.86 ? 'Matola' : 'Maputo';
    return '$city • Localização atual';
  }

  Future<void> _updateAddressFromPosition(
    Position position, {
    bool force = false,
  }) async {
    if (_resolvingAddress) return;
    final now = MozambiqueTime.now();
    if (!force && _lastGeocodeAt != null && _lastGeocodePosition != null) {
      final seconds = now.difference(_lastGeocodeAt!).inSeconds;
      final distance = Geolocator.distanceBetween(
        _lastGeocodePosition!.latitude,
        _lastGeocodePosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (seconds < 10 && distance < 30) {
        return;
      }
    }

    _resolvingAddress = true;
    var updated = false;
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 4));
      if (!mounted) return;
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final street = (place.street ?? '').trim();
        final subLocality = (place.subLocality ?? '').trim();
        final locality = (place.locality ?? '').trim();
        final addressLine = [
          street,
          subLocality,
          locality,
        ].where((part) => part.isNotEmpty).join(', ');
        setState(() {
          _currentAddressLine = addressLine.isNotEmpty
              ? addressLine
              : _fallbackLocationLabel(position);
          _currentNeighborhood = subLocality;
          _currentCity = locality;
          _lastGeocodeAt = now;
          _lastGeocodePosition = position;
        });
        updated = true;
      }
    } catch (_) {
    } finally {
      if (mounted && !updated) {
        setState(() {
          _currentAddressLine = _fallbackLocationLabel(position);
          _lastGeocodeAt = now;
          _lastGeocodePosition = position;
        });
      }
      _resolvingAddress = false;
    }
  }

  Future<void> _syncWorkZoneFromCurrentLocation() async {
    if (_currentPosition == null) return;
    String? inferredZone;
    try {
      final placemarks = await placemarkFromCoordinates(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      ).timeout(const Duration(seconds: 3));
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        inferredZone = (placemark.locality ?? '').trim().isNotEmpty
            ? placemark.locality!.trim()
            : (placemark.subAdministrativeArea ?? '').trim().isNotEmpty
            ? placemark.subAdministrativeArea!.trim()
            : null;
      }
    } catch (_) {
      inferredZone = null;
    }

    inferredZone ??= _weather?.cityName.trim();
    inferredZone ??= _deduceMozCityFromPosition(_currentPosition);
    if (!mounted || inferredZone == null || inferredZone.isEmpty) return;
    setState(() {
      _workZoneController.text = inferredZone!;
    });
  }

  Future<void> _syncCourierPresenceLocation(Position position) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final displayName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : (_profileData?['full_name']?.toString().trim().isNotEmpty == true
              ? _profileData!['full_name'].toString().trim()
              : 'Deligo Biker');
    final normalizedPhone =
        _normalizePhoneForStorage(_phoneController.text) ??
        _profileData?['phone']?.toString().trim() ??
        '';

    try {
      await supabase.from('couriers').upsert({
        'id': user.id,
        'full_name': displayName,
        'phone': normalizedPhone,
        'is_online': isOnline,
        'current_latitude': position.latitude,
        'current_longitude': position.longitude,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'id');
    } catch (error) {
      debugPrint('Falha ao sincronizar localizacao do estafeta: $error');
    }
  }

  void _startPresenceHeartbeat() {
    _presenceHeartbeatTimer?.cancel();
    _presenceHeartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final position = _currentPosition;
      if (!mounted || !isOnline || position == null) return;
      unawaited(_syncCourierPresenceLocation(position));
    });
  }

  void _stopPresenceHeartbeat() {
    _presenceHeartbeatTimer?.cancel();
    _presenceHeartbeatTimer = null;
  }

  Future<void> _refreshCourierDataInBackground() async {
    try {
      await _loadCourierData();
    } catch (e) {
      debugPrint('Falha ao recarregar dados do estafeta em background: $e');
    }
  }

  Future<void> _syncCourierForegroundProtection({
    required bool online,
    Order? currentDelivery,
    int availableDeliveries = 0,
  }) async {
    await CourierForegroundService.instance.syncOnlineState(
      isOnline: online,
      hasActiveDelivery: currentDelivery != null,
      availableDeliveries: availableDeliveries,
    );
  }

  Future<void> _maybePromptCourierBatteryOptimization() async {
    final alreadyIgnored = await CourierForegroundService.instance
        .isIgnoringBatteryOptimizations();
    if (alreadyIgnored || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Para manter pedidos e tracking ativos em segundo plano, permita bateria sem restricoes para a app.',
        ),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Ajustar',
          onPressed: () {
            unawaited(
              CourierForegroundService.instance
                  .openBatteryOptimizationSettings(),
            );
          },
        ),
      ),
    );
  }

  Future<void> _setCourierOnline(bool value) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final previousValue = isOnline;
    final normalizedPhone = _normalizePhoneForStorage(_phoneController.text);
    if (normalizedPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Informe um telefone valido no formato +258XXXXXXXXX antes de ficar online.',
          ),
        ),
      );
      return;
    }
    setState(() => isOnline = value);
    try {
      final timestamp = DateTime.now().toIso8601String();
      final existingCourier = await supabase
          .from('couriers')
          .select('id,is_online')
          .eq('id', user.id)
          .maybeSingle();
      if (existingCourier != null && existingCourier['is_online'] == value) {
        if (mounted) {
          setState(() => isOnline = value);
        }
      } else if (existingCourier == null) {
        await supabase.from('couriers').insert({
          'id': user.id,
          'full_name': _nameController.text.trim(),
          'phone': normalizedPhone,
          'is_online': value,
          'updated_at': timestamp,
        });
      } else {
        await supabase
            .from('couriers')
            .update({'is_online': value, 'updated_at': timestamp})
            .eq('id', user.id);
      }
      await _ensureCourierOnlineSession(value);
    } catch (e) {
      try {
        final fallbackCourier = await supabase
            .from('couriers')
            .select('is_online')
            .eq('id', user.id)
            .maybeSingle();
        if (fallbackCourier != null && fallbackCourier['is_online'] == value) {
          if (mounted) {
            setState(() => isOnline = value);
          }
          return;
        }
      } catch (_) {}
      if (mounted) {
        setState(() => isOnline = previousValue);
      }
      debugPrint('Falha ao atualizar is_online do estafeta: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel atualizar o estado online agora.'),
        ),
      );
      return;
    }

    try {
      await _syncCourierForegroundProtection(
        online: value,
        currentDelivery: _currentDelivery,
        availableDeliveries: value ? _availableDeliveries.length : 0,
      );
      final shouldKeepTracking = value || _currentDelivery != null;
      if (shouldKeepTracking) {
        await _loadCurrentLocation();
        _startPresenceHeartbeat();
        await _startLocationUpdates();
        if (value) {
          await _maybePromptCourierBatteryOptimization();
          await _refreshDeliveriesAndStats();
          _startAvailableOfferRecovery();
        }
      } else {
        _stopAvailableOfferRecovery();
        _stopPresenceHeartbeat();
        await _locationSub?.cancel();
        _locationSub = null;
      }
      await _loadCourierData();
    } catch (e) {
      if (!value) {
        _stopPresenceHeartbeat();
      }
      debugPrint(
        'Estado online atualizado, mas falhou refresh/localizacao: $e',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Estado online atualizado. Ative a localizacao para receber entregas.'
                : 'Estado offline atualizado.',
          ),
        ),
      );
    }
  }

  Future<void> _ensureCourierOnlineSession(bool online) async {
    try {
      await supabase.rpc(
        'set_courier_online_session',
        params: {'p_online': online},
      );
    } catch (error) {
      // Older deployments can operate normally until the additive migration is applied.
      debugPrint('Sessão online ainda não disponível no backend: $error');
    }
  }

  Future<void> _requestCourierOnlineChange(bool value) async {
    if (value == isOnline) return;
    if (!value && _currentDelivery != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Conclua a entrega atual antes de ficar offline. O rastreamento deve permanecer ativo.',
          ),
        ),
      );
      return;
    }
    if (!value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ficar offline?'),
          content: const Text(
            'Enquanto estiver offline não receberá novas propostas de entrega.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('FICAR OFFLINE'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _setCourierOnline(value);
  }

  Future<void> _saveCourierProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    setState(() => _savingProfile = true);
    try {
      final notifications =
          (_profileSettings['notifications'] as Map?)
              ?.cast<String, dynamic>() ??
          {};
      notifications['push'] = _pushNotificationsEnabled;
      notifications['order_status'] = _orderSoundsEnabled;
      _profileSettings['notifications'] = notifications;
      _profileSettings['language'] = _languageCode;
      _profileSettings['voice_mode'] = _voiceMode;
      _profileSettings['sound_enabled'] = _orderSoundsEnabled;
      final trimmedZone = _workZoneController.text.trim().isNotEmpty
          ? _workZoneController.text.trim()
          : (_deduceMozCityFromPosition(_currentPosition) ?? '');
      _profileSettings['courier_work_zone'] = trimmedZone;
      await supabase
          .from('profiles')
          .update({
            'address': trimmedZone,
            'preferred_payment_method': _preferredPaymentMethod,
            'settings': _profileSettings,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);
      if (!mounted) return;
      setState(() {
        _workZoneController.text = trimmedZone;
        _savingProfile = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil atualizado. Ja esta tudo pronto para seguir.'),
          backgroundColor: AppColors.successGreen,
        ),
      );
      unawaited(_refreshCourierDataInBackground());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nao foi possivel guardar o perfil do estafeta agora. $e',
          ),
        ),
      );
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  Future<void> _changeAvatar() async {
    setState(() => _uploadingAvatar = true);
    try {
      final uploaded = await _profileService.takeProfilePhoto();
      if (!mounted) return;
      if (uploaded != null) {
        setState(() => _avatarUrl = uploaded);
        await _syncCourierPublicProfileMirror(
          userId: supabase.auth.currentUser!.id,
          profile: {
            'full_name': _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'avatar_url': uploaded,
          },
          courierProfile: {
            'full_name': _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
          },
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foto de perfil atualizada.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _uploadingAvatar = true);
    try {
      final ok = await _profileService.removeProfilePhoto();
      if (!mounted) return;
      if (ok) {
        setState(() => _avatarUrl = null);
        await _syncCourierPublicProfileMirror(
          userId: supabase.auth.currentUser!.id,
          profile: {
            'full_name': _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'avatar_url': null,
          },
          courierProfile: {
            'full_name': _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'avatar_url': '',
          },
        );
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = supabase.auth.currentUser?.email;
    if (email == null || email.isEmpty) return;
    try {
      await supabase.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enviamos um link de alteracao de palavra-passe para $email',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel enviar o link de seguranca agora.'),
        ),
      );
    }
  }

  Future<void> _acceptDelivery(Order order) async {
    if (!_isOfferActionable(order)) {
      _expireVisibleCourierOffers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Esta oferta já expirou.')),
        );
      }
      return;
    }
    if (!_deliveryActionsInFlight.add('accept:${order.id}')) return;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final result = await _deliveryService.acceptDelivery(
        orderId: order.id,
        courierId: user.id,
        dispatchAttemptId: order.dispatchAttemptId ?? '',
      );

      if (result.success) {
        await SoundController.instance.stopCourierDispatchLoop(
          orderId: order.id,
        );
        if (!mounted) return;
        unawaited(SoundController.instance.shortBang());
        unawaited(
          _speakCourierEvent(
            order: order,
            state: 'accepted',
            message: 'Entrega aceite. Siga para o restaurante.',
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: AppColors.successGreen,
            duration: _popupDuration,
          ),
        );
        // Depois de aceitar, a operação continua na Home map-first. O
        // tracking detalhado permanece acessível pelo painel da Home.
        setState(() {
          _selectedIndex = 0;
          _homeEndpointKey = null;
          _homeRouteKey = null;
          _homeResolvedEndpoint = null;
          _homeEndpointFuture = null;
          _homeRouteFuture = null;
          _homeRouteInfoFuture = null;
        });
        _refreshDeliveriesAndStats();
      }
      if (!result.success && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Algo nao correu bem ao aceitar a entrega. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      _deliveryActionsInFlight.remove('accept:${order.id}');
    }
  }

  Future<void> _speakCourierEvent({
    required Order order,
    required String state,
    required String message,
  }) async {
    final eventId = 'courier:${order.id}:$state';
    await AppVoiceService.instance.speakNotification(
      type: 'COURIER_OPERATIONAL_STATE',
      title: state,
      body: message,
      notificationId: eventId,
      channel: 'courier_navigation',
      priority: 'high',
    );
  }

  Future<void> _confirmAcceptDelivery(Order order) async {
    if (!_isOfferActionable(order)) {
      _expireVisibleCourierOffers();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Esta oferta já expirou.')));
      return;
    }
    if (_currentDelivery != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conclua a entrega atual antes de aceitar outra.'),
        ),
      );
      return;
    }
    final shortId = order.id.length > 8 ? order.id.substring(0, 8) : order.id;
    final gainSummary = order.courierAmount == null
        ? 'O ganho oficial ainda não está disponível nesta oferta.'
        : 'Ganho previsto: ${order.courierAmount!.toStringAsFixed(0)} ${order.currency}.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aceitar esta entrega?'),
        content: Text(
          'Pedido #${shortId.toUpperCase()}\n$gainSummary\n\nAo aceitar, deve seguir para o restaurante e manter a localização ativa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ACEITAR ENTREGA'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _acceptDelivery(order);
  }

  Future<void> _startLocationUpdates() async {
    if (_locationSub != null) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _locationSub =
        Geolocator.getPositionStream(
          locationSettings: _liveCourierLocationSettings(),
        ).listen((position) {
          if (!_acceptCourierPosition(position)) return;
          final resolvedBearing = _resolveCourierBearing(position);
          _lastAcceptedCourierPosition = position;
          if (mounted) {
            setState(() {
              _currentPosition = position;
              if (resolvedBearing != null) {
                _displayCourierBearing = resolvedBearing;
              }
            });
          }
          unawaited(_updateAddressFromPosition(position));
          if (isOnline || _currentDelivery != null) {
            unawaited(_syncCourierPresenceLocation(position));
          }
          unawaited(
            _animateCourierMapTo(LatLng(position.latitude, position.longitude)),
          );
          if (_currentDelivery == null &&
              isOnline &&
              _availableDeliveries.isNotEmpty) {
            _refreshAvailableOfferRoutes(position);
          }
          if (_currentDelivery == null) return;
          unawaited(
            _maybeConfirmRestaurantArrival(_currentDelivery!, position),
          );
          unawaited(_sendCourierTelemetry(_currentDelivery!.id, position));
        });
  }

  bool _acceptCourierPosition(Position position) {
    if (!position.latitude.isFinite || !position.longitude.isFinite) {
      return false;
    }
    if (position.accuracy.isFinite && position.accuracy > 100) return false;

    final previous = _lastAcceptedCourierPosition;
    if (previous != null) {
      final distance = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
      final elapsed = position.timestamp.difference(previous.timestamp);
      final seconds = elapsed.inMilliseconds <= 0
          ? 1.0
          : elapsed.inMilliseconds / 1000.0;
      // Reject impossible jumps instead of drawing the marker over an
      // unrelated road or making the camera snap across the map.
      if (distance > 250 && distance / seconds > 55) return false;
    }
    return true;
  }

  double? _resolveCourierBearing(Position position) {
    final gpsHeading = position.heading;
    final headingIsReliable = gpsHeading.isFinite &&
        gpsHeading >= 0 &&
        gpsHeading <= 360 &&
        (position.speed >= 1.2 || _displayCourierBearing == null);

    double? target;
    if (headingIsReliable) {
      target = gpsHeading;
    } else {
      final previous = _lastAcceptedCourierPosition;
      if (previous != null &&
          (previous.latitude != position.latitude ||
              previous.longitude != position.longitude)) {
        target = _bearingBetween(
          LatLng(previous.latitude, previous.longitude),
          LatLng(position.latitude, position.longitude),
        );
      }
    }
    if (target == null) return _displayCourierBearing;
    final current = _displayCourierBearing;
    if (current == null) return target;

    // Smooth the shortest angular path to avoid sudden spins at 0/360.
    final delta = ((target - current + 540) % 360) - 180;
    return (current + delta.clamp(-28.0, 28.0)) % 360;
  }

  double _bearingBetween(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final deltaLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(deltaLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  void _refreshAvailableOfferRoutes(Position position) {
    final origin = LatLng(position.latitude, position.longitude);
    for (final order in _availableDeliveries) {
      final key = _availableRouteRequestKey(order, origin);
      if (key != null && !_availableRoutePlans.containsKey(key)) {
        unawaited(_loadAvailableRoutePlan(order, origin));
      }
    }
  }

  Future<void> _sendCourierTelemetry(String orderId, Position position) async {
    final battery = await CourierForegroundService.instance.getBatteryLevel();
    await _deliveryService.updateCourierLocation(
      orderId: orderId,
      latitude: position.latitude,
      longitude: position.longitude,
      speedMetersPerSecond: position.speed >= 0 ? position.speed : null,
      headingDegrees: position.heading >= 0 ? position.heading : null,
      accuracyMeters: position.accuracy,
      batteryPercent: battery,
      recordedAt: position.timestamp,
    );
  }

  LocationSettings _liveCourierLocationSettings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'DeliGo - entrega em curso',
          notificationText: 'Localizacao em tempo real ativa para a entrega.',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    );
  }

  Future<void> _maybeConfirmRestaurantArrival(
    Order order,
    Position position,
  ) async {
    if (!_isHeadingToRestaurant(order) ||
        _arrivedAtRestaurantOrderIds.contains(order.id) ||
        _arrivalNotificationInFlight.contains(order.id)) {
      return;
    }
    final restaurantLat =
        order.pickupLatitude ?? order.restaurantLatitude;
    final restaurantLng =
        order.pickupLongitude ?? order.restaurantLongitude;
    if (restaurantLat == null || restaurantLng == null) return;
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      restaurantLat,
      restaurantLng,
    );
    if (distance > 50) return;
    // Geofence only prepares the next action. The courier must still confirm
    // the arrival explicitly so an imprecise GPS fix never changes order
    // state on its own.
    if (!mounted) return;
    setState(() => _arrivedAtRestaurantOrderIds.add(order.id));
  }

  Future<void> _confirmRestaurantArrival(
    Order order, {
    bool automatic = false,
  }) async {
    if (_arrivalNotificationInFlight.contains(order.id)) return;
    if (mounted) {
      setState(() => _restaurantArrivalAttemptedOrderIds.add(order.id));
    }
    _arrivalNotificationInFlight.add(order.id);
    // Refresh and persist the GPS fix immediately before the RPC. The
    // background stream can otherwise leave the delivery row with an older
    // position even after the courier has reached the restaurant.
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _displayCourierLatLng = LatLng(position.latitude, position.longitude);
        });
      }
      await _sendCourierTelemetry(order.id, position);
    } catch (error) {
      debugPrint('Falha ao atualizar GPS antes da chegada: $error');
    }
    final success = await _deliveryService.notifyCourierArrivedAtRestaurant(
      order.id,
    );
    _arrivalNotificationInFlight.remove(order.id);
    if (!mounted) return;
    if (success) {
      setState(() => _arrivedAtRestaurantOrderIds.add(order.id));
      unawaited(
        _speakCourierEvent(
          order: order,
          state: 'arrived_restaurant',
          message: 'Chegou ao restaurante.',
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            automatic
                ? 'Chegada detectada. Restaurante e cliente foram notificados.'
                : 'Restaurante e cliente foram notificados da chegada.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nao foi possivel confirmar a chegada.')),
      );
    }
  }

  Future<void> _animateCourierMapTo(LatLng target) async {
    final start = _displayCourierLatLng;
    if (start != null) {
      final distanceMeters = _distanceBetweenLatLng(start, target);
      if (distanceMeters < 4) return;

      if (distanceMeters < 12) {
        if (!mounted) return;
        setState(() => _displayCourierLatLng = target);
        await _maybeFollowCourierMapCamera(
          target,
          force: distanceMeters >= (_isCompactCourierViewport ? 18 : 25),
        );
        return;
      }
    }

    final animationStart = start ?? target;
    final token = ++_courierMapAnimationToken;
    const totalSteps = 4;

    for (var step = 1; step <= totalSteps; step++) {
      if (!mounted || token != _courierMapAnimationToken) return;
      final t = step / totalSteps;
      final frame = LatLng(
        animationStart.latitude +
            ((target.latitude - animationStart.latitude) * t),
        animationStart.longitude +
            ((target.longitude - animationStart.longitude) * t),
      );
      setState(() => _displayCourierLatLng = frame);
      if (step < totalSteps) {
        await Future<void>.delayed(const Duration(milliseconds: 90));
      }
    }

    final distanceMeters = start == null
        ? double.infinity
        : _distanceBetweenLatLng(start, target);
    await _maybeFollowCourierMapCamera(
      target,
      force:
          start == null ||
          distanceMeters >= (_isCompactCourierViewport ? 18 : 25),
    );
  }

  Future<void> _maybeFollowCourierMapCamera(
    LatLng target, {
    bool force = false,
  }) async {
    if (!_followCourierMap) return;
    final now = DateTime.now();
    final lastCameraAt = _lastCourierMapCameraAt;
    final minIntervalMs = _isCompactCourierViewport ? 1400 : 900;
    if (!force &&
        lastCameraAt != null &&
        now.difference(lastCameraAt).inMilliseconds < minIntervalMs) {
      return;
    }
    _lastCourierMapCameraAt = now;
    final speed = _currentPosition?.speed ?? 0;
    final dynamicZoom = speed >= 12
        ? (_courierMapZoom - 1.0)
        : speed >= 5
        ? (_courierMapZoom - 0.4)
        : _courierMapZoom + 0.4;
    _isAnimatingCourierCamera = true;
    try {
      await _courierMapController?.animateTo(
        target,
        zoom: dynamicZoom.clamp(15.2, 18.2),
        bearing: _displayCourierBearing,
        tilt: _courierMapTilt,
      );
    } finally {
      _isAnimatingCourierCamera = false;
    }
  }

  Future<void> _followCourierMapCamera() async {
    final target = _displayCourierLatLng;
    if (!_followCourierMap || target == null) return;
    await _maybeFollowCourierMapCamera(target, force: true);
  }

  Future<void> _loadSmartNotifications() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase
          .from('push_notifications')
          .select(
            'id, type, title, body, action, entity_id, priority, channel, read_at, metadata, data, created_at',
          )
          .eq('user_id', user.id)
          // Delivery opportunities are transient offers, not notification
          // history. The active offer card on Home is the only place where a
          // courier may inspect/act on those details.
          .neq('type', 'DELIVERY_OPPORTUNITY')
          .order('created_at', ascending: false)
          .limit(6);

      final seen = <String>{};
      final notifications = (response as List)
          .cast<Map<String, dynamic>>()
          .where((notification) {
            final type = notification['type']?.toString() ?? 'UNKNOWN';
            final entity = notification['entity_id']?.toString() ?? '';
            final metadata = notification['metadata'];
            final eventId = metadata is Map
                ? metadata['event_id']?.toString() ?? ''
                : '';
            final key = eventId.isNotEmpty
                ? 'event:$eventId'
                : entity.isNotEmpty
                ? 'entity:$type:$entity'
                : 'id:${notification['id']}';
            return seen.add(key);
          })
          .toList();

      if (!mounted) return;
      setState(() {
        _smartNotifications = notifications;
      });
    } catch (_) {
      debugPrint('[COURIER_NOTIFICATIONS] refresh failed');
    }
  }

  Future<void> _activatePush() async {
    await PushNotificationService().initialize();
    final token = await PushNotificationService().registerFcmToken(token: null);
    if (mounted) {
      setState(() => _pushActive = token != null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            token != null ? 'Push ativo' : 'Falha ao registrar push',
          ),
        ),
      );
      if (token != null &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Protecao em segundo plano'),
            content: const Text(
              'Para chamadas de entrega no ecra bloqueado, mantenha o canal '
              '"Chamadas de entrega" com som ativo e remova as restricoes de '
              'bateria do Android para a Deligo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Percebi'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _markAllNotificationsAsRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final readAt = DateTime.now().toIso8601String();
    if (mounted) {
      setState(() {
        for (final notification in _smartNotifications) {
          if (notification['read_at'] == null) {
            notification['read_at'] = readAt;
          }
        }
      });
    }
    try {
      await HapticFeedback.lightImpact();
      await supabase
          .from('push_notifications')
          .update({'read_at': readAt})
          .eq('user_id', user.id)
          .isFilter('read_at', null);
      await _loadSmartNotifications();
    } catch (_) {
      debugPrint('[COURIER_NOTIFICATIONS] mark all as read failed');
    }
  }

  Future<void> _showCourierNotifications() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Notificacoes',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_unreadNotificationCount > 0)
                    TextButton(
                      onPressed: () async {
                        await _markAllNotificationsAsRead();
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      child: const Text('Marcar todas como lidas'),
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (_smartNotifications.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Text('Sem notificacoes recentes.'),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: _smartNotifications.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final notification = _smartNotifications[index];
                    final isUnread = notification['read_at'] == null;
                    final type = notification['type']?.toString() ?? '';
                    final createdAt = DateTime.tryParse(
                      notification['created_at']?.toString() ?? '',
                    )?.toLocal();
                    return ListTile(
                      leading: Icon(
                        _courierNotificationIcon(type),
                        color: isUnread
                            ? AppColors.primaryRed
                            : AppColors.neutralGray,
                      ),
                      title: Text(
                        _courierNotificationTitle(notification, type),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isUnread
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${_courierNotificationBody(notification, type)}${createdAt == null ? '' : '\n${_formatCourierNotificationDate(createdAt)}'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        await NotificationRouterService()
                            .handleStoredNotificationTap(notification);
                        await _loadSmartNotifications();
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  int get _unreadNotificationCount =>
      _smartNotifications.where((item) => item['read_at'] == null).length;

  String _courierNotificationTitle(
    Map<String, dynamic> notification,
    String type,
  ) {
    if (type == 'DELIVERY_UNAVAILABLE') return 'Oferta de entrega perdida';
    return notification['title']?.toString().trim().isNotEmpty == true
        ? notification['title'].toString()
        : 'Notificacao DeliGo';
  }

  String _courierNotificationBody(
    Map<String, dynamic> notification,
    String type,
  ) {
    if (type == 'DELIVERY_UNAVAILABLE') {
      return 'A oferta expirou antes de ser aceite.';
    }
    return notification['body']?.toString() ?? '';
  }

  IconData _courierNotificationIcon(String type) {
    switch (type) {
      case 'DELIVERY_OPPORTUNITY':
      case 'DELIVERY_UNAVAILABLE':
      case 'DRIVER_ASSIGNED':
      case 'ORDER_READY':
        return Icons.delivery_dining_rounded;
      case 'MESSAGE_RECEIVED':
      case 'SUPPORT_UPDATED':
      case 'TICKET_RESOLVED':
        return Icons.chat_bubble_outline_rounded;
      case 'ORDER_DELIVERED':
        return Icons.verified_rounded;
      case 'PAYMENT_CONFIRMED':
      case 'CASHBACK_RECEIVED':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  String _formatCourierNotificationDate(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    if (now.year == date.year &&
        now.month == date.month &&
        now.day == date.day) {
      return 'Hoje, $hh:$mm';
    }
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} $hh:$mm';
  }

  int _unreadChatCountFor(String orderId) {
    return _smartNotifications.where((notification) {
      return ChatNotificationUtils.isUnreadChatNotification(notification) &&
          ChatNotificationUtils.matchesOrder(notification, orderId);
    }).length;
  }

  Widget _buildTabIcon(
    String assetPath, {
    int badgeCount = 0,
    bool selected = false,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(selected ? 5 : 4),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryRed.withValues(alpha: 0.08)
                : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Image.asset(
            assetPath,
            width: selected ? 26 : 22,
            height: selected ? 26 : 22,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primaryRed,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                badgeCount > 9 ? '9+' : '$badgeCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _loadCurrentLocation() async {
    if (_loadingLocation) return;
    setState(() => _loadingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _loadingLocation = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Active a localizacao do dispositivo para obter a sua posicao real.',
              ),
            ),
          );
        }
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _loadingLocation = false);
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        _courierMapAnimationToken++;
        _displayCourierLatLng = LatLng(position.latitude, position.longitude);
        _loadingLocation = false;
      });
      // A oferta pode ter sido carregada antes da localização. Recalcular a
      // rota agora evita deixar o card permanentemente em "A calcular".
      if (_availableDeliveries.isNotEmpty) {
        unawaited(_primeAvailableDeliveryDetails(_availableDeliveries));
      }
      unawaited(_updateAddressFromPosition(position, force: true));
      if (isOnline || _currentDelivery != null) {
        await _syncCourierPresenceLocation(position);
      }
      await _followCourierMapCamera();
      await _syncWorkZoneFromCurrentLocation();
    } catch (_) {
      if (mounted) {
        setState(() => _loadingLocation = false);
      }
    }
  }

  Future<void> _updateDeliveryStatus(String status) async {
    final current = _currentDelivery;
    if (current == null) return;

    try {
      if (mounted) setState(() => _updatingDeliveryStatus = true);
      bool success = false;

      switch (status) {
        case 'in_transit':
          success = await _deliveryService.updateDeliveryStatus(
            current.id,
            'in_transit',
          );
          break;
        case 'arrived':
          success = await _deliveryService.courierArrived(current.id);
          break;
      }

      if (success && mounted) {
        unawaited(SoundController.instance.shortBang());
        final voiceState = status == 'in_transit'
            ? 'picked_up'
            : status == 'arrived'
            ? 'arrived_client'
            : status;
        final voiceMessage = status == 'in_transit'
            ? 'Pedido recolhido. Agora siga para o cliente.'
            : status == 'arrived'
            ? 'Chegou ao destino. Confirme a entrega no aplicativo.'
            : 'Entrega atualizada.';
        unawaited(
          _speakCourierEvent(
            order: current,
            state: voiceState,
            message: voiceMessage,
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'delivered'
                  ? 'Entrega concluida!'
                  : status == 'in_transit'
                  ? 'Pedido recolhido. Cliente notificado que ja esta a caminho.'
                  : 'Chegada registada.',
            ),
            backgroundColor: AppColors.successGreen,
            duration: _popupDuration,
          ),
        );
        await _refreshDeliveriesAndStats();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'O backend nao confirmou esta transicao. Verifica a atribuicao do pedido e tenta novamente.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ocorreu um erro. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingDeliveryStatus = false);
    }
  }

  Future<void> _logout() async {
    try {
      AuthRefreshNotifier.markIntentionalSignOut();
      await supabase.auth.signOut();
      if (mounted) {
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nao foi possivel sair agora. Tente novamente.'),
          ),
        );
      }
    }
  }

  Future<void> _verifyCurrentDeliveryOtp() async {
    final current = _currentDelivery;
    if (current == null || _verifyingDeliveryOtp) return;

    final otp = _deliveryOtpController.text.trim();
    if (otp.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insira um codigo OTP de 4 digitos.')),
      );
      return;
    }

    setState(() => _verifyingDeliveryOtp = true);
    final result = await _deliveryService.verifyDeliveryOtp(
      orderId: current.id,
      otpCode: otp,
    );
    if (!mounted) return;

    setState(() => _verifyingDeliveryOtp = false);
    unawaited(SoundController.instance.shortBang());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? AppColors.successGreen : null,
        duration: result.success
            ? const Duration(milliseconds: 850)
            : _popupDuration,
      ),
    );

    if (result.success) {
      _deliveryOtpController.clear();
      await _refreshDeliveriesAndStats();
    }
  }

  Future<void> _showDeliveryOtpDialog(Order order) async {
    _deliveryOtpController.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar entrega'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Peça ao cliente o OTP do pedido #${order.id.substring(0, 8)}.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _deliveryOtpController,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'OTP do cliente',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              await _verifyCurrentDeliveryOtp();
              if (mounted && !_verifyingDeliveryOtp) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Validar OTP'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, String?>> _fetchClientProfileSummary(Order order) async {
    final clientId = order.clientId.trim();
    if (clientId.isEmpty) {
      return const {'full_name': null, 'gender': null, 'phone': null};
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select('full_name, gender, phone')
          .eq('id', clientId)
          .maybeSingle();
      return {
        'full_name': profile?['full_name']?.toString(),
        'gender': profile?['gender']?.toString(),
        'phone': profile?['phone']?.toString(),
      };
    } catch (_) {
      return const {'full_name': null, 'gender': null, 'phone': null};
    }
  }

  Future<Map<String, dynamic>> _fetchCourierOrderContactDetails(
    Order order,
  ) async {
    try {
      final response = await supabase.rpc(
        'get_courier_order_contact_details',
        params: {'p_order_id': order.id},
      );
      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }
    } catch (_) {}
    return const <String, dynamic>{};
  }

  Future<Map<String, String?>> _fetchRestaurantSummary(Order order) async {
    final fallbackName = order.restaurantName?.trim().isNotEmpty == true
        ? order.restaurantName!.trim()
        : 'Restaurante';
    final fallbackAddress = LocationDisplay.displayAddress(
      address: order.restaurantAddress,
      neighborhood: order.restaurantNeighborhood,
      city: order.restaurantCity,
      fallback: 'Local do restaurante confirmado no mapa',
    );
    final restaurantId = order.restaurantId.trim();
    if (restaurantId.isEmpty) {
      return {
        'name': fallbackName,
        'phone': null,
        'address': fallbackAddress,
        'reference': order.restaurantLandmarkReference,
      };
    }

    try {
      final restaurant = await supabase
          .from('restaurants')
          .select(
            'name, phone, address, neighborhood, landmark_reference, city',
          )
          .eq('id', restaurantId)
          .maybeSingle();
      return {
        'name': restaurant?['name']?.toString() ?? fallbackName,
        'phone': restaurant?['phone']?.toString(),
        'address': LocationDisplay.displayAddress(
          address:
              restaurant?['address']?.toString() ?? order.restaurantAddress,
          neighborhood:
              restaurant?['neighborhood']?.toString() ??
              order.restaurantNeighborhood,
          city: restaurant?['city']?.toString() ?? order.restaurantCity,
          fallback: fallbackAddress,
        ),
        'reference':
            restaurant?['landmark_reference']?.toString() ??
            order.restaurantLandmarkReference,
      };
    } catch (_) {
      return {
        'name': fallbackName,
        'phone': null,
        'address': fallbackAddress,
        'reference': order.restaurantLandmarkReference,
      };
    }
  }

  Future<void> _callPhoneNumber(
    String rawPhone, {
    String contactLabel = 'contacto',
  }) async {
    final trimmed = rawPhone.trim();
    if (trimmed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Numero do $contactLabel indisponivel.')),
      );
      return;
    }

    final uri = Uri(
      scheme: 'tel',
      path: trimmed.replaceAll(RegExp(r'[^0-9+]'), ''),
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel abrir a chamada agora.'),
        ),
      );
    }
  }

  bool _isHeadingToRestaurant(Order order) {
    return order.status == OrderStatus.paymentAuthorized ||
        order.status == OrderStatus.paid ||
        order.status == OrderStatus.accepted ||
        order.status == OrderStatus.preparing ||
        order.status == OrderStatus.courierAssigned ||
        order.status == OrderStatus.ready;
  }

  Future<String> _resolveOrderLocationLabel({
    double? latitude,
    double? longitude,
    String? address,
    String? neighborhood,
    String? city,
    required String fallback,
  }) async {
    if (latitude != null && longitude != null) {
      try {
        final placemarks = await placemarkFromCoordinates(
          latitude,
          longitude,
        ).timeout(const Duration(seconds: 4));
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          final parts = <String>[
            if ((place.street ?? '').trim().isNotEmpty) place.street!.trim(),
            if ((place.subLocality ?? '').trim().isNotEmpty)
              place.subLocality!.trim(),
            if ((place.locality ?? '').trim().isNotEmpty)
              place.locality!.trim(),
          ];
          if (parts.isNotEmpty) {
            return parts.take(2).join(', ');
          }
        }
      } catch (_) {}
    }

    return LocationDisplay.displayAddress(
      address: address,
      neighborhood: neighborhood,
      city: city,
      fallback: fallback,
    );
  }

  Future<Map<String, String>> _loadRouteSnapshot(Order order) async {
    final cached = _routeLocationCache[order.id];
    final restaurantName =
        cached?['restaurant_name'] ??
        (order.restaurantName?.trim().isNotEmpty == true
            ? order.restaurantName!.trim()
            : 'Restaurante');
    final headingToRestaurant = _isHeadingToRestaurant(order);
    late final String restaurantStop;
    late final String customerStop;
    if (cached != null) {
      restaurantStop =
          cached['restaurant_stop'] ??
          'Local do restaurante confirmado no mapa';
      customerStop =
          cached['customer_stop'] ?? 'Destino do cliente confirmado no mapa';
    } else {
      final results = await Future.wait<String>([
        _resolveOrderLocationLabel(
          latitude: order.restaurantLatitude,
          longitude: order.restaurantLongitude,
          address: order.restaurantAddress,
          neighborhood: order.restaurantNeighborhood,
          city: order.restaurantCity,
          fallback: 'Local do restaurante confirmado no mapa',
        ),
        _resolveOrderLocationLabel(
          latitude: order.deliveryLatitude,
          longitude: order.deliveryLongitude,
          address: order.deliveryAddress,
          fallback: 'Destino do cliente confirmado no mapa',
        ),
      ]);
      restaurantStop = results[0];
      customerStop = results[1];
      _routeLocationCache[order.id] = {
        'restaurant_name': restaurantName,
        'restaurant_stop': restaurantStop,
        'customer_stop': customerStop,
      };
    }

    return {
      'restaurant_name': restaurantName,
      'restaurant_stop': restaurantStop,
      'customer_stop': customerStop,
      'route_stage': headingToRestaurant
          ? 'Rota ativa: siga para o restaurante'
          : 'Rota ativa: siga para o cliente',
      'route_description': headingToRestaurant
          ? 'O mapa vai guiar-te ate o restaurante para levantar o pedido.'
          : 'O mapa agora mostra a saida do restaurante ate ao cliente.',
    };
  }

  Widget _buildCurrentDeliveryRouteSummary(Order order) {
    final headingToRestaurant = _isHeadingToRestaurant(order);
    if (!headingToRestaurant) return const SizedBox.shrink();
    final restaurantName = order.restaurantName?.trim().isNotEmpty == true
        ? order.restaurantName!.trim()
        : 'Restaurante';
    final restaurantLatitude =
        order.pickupLatitude ?? order.restaurantLatitude;
    final restaurantLongitude =
        order.pickupLongitude ?? order.restaurantLongitude;

    return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: const Color(0xF2111827),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .18)),
          ),
          child: FutureBuilder<RouteInfo?>(
            future: _homeRouteInfoFuture,
            builder: (context, snapshot) {
              final info = snapshot.data;
              final routeReady = info?.distanceMeters != null &&
                  info?.durationSeconds != null;
              final routeLabel = restaurantLatitude == null ||
                      restaurantLongitude == null
                  ? 'Localização do restaurante indisponível'
                  : !routeReady
                  ? 'A obter rota…'
                  : '${(info!.durationSeconds! / 60).ceil()} min • ${(info.distanceMeters! / 1000).toStringAsFixed(1)} km';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
              Text(
                restaurantName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                routeLabel,
                style: TextStyle(
                  color: routeReady ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w800,
                ),
              ),
                ],
              );
            },
          ),
        );
  }

  Widget _buildRouteSummaryRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primaryRed),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.neutralGray,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRouteMetric(IconData icon, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primaryRed, size: 20),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.neutralGray),
        ),
      ],
    );
  }

  Future<void> _showOrderDetails(Order order) async {
    final results = await Future.wait<dynamic>([
      _orderService.getOrderItems(order.id),
      _fetchCourierOrderContactDetails(order),
    ]);
    final items = results[0] as List<OrderItem>;
    final contactDetails = results[1] as Map<String, dynamic>;
    final clientProfile = contactDetails['client'] is Map
        ? Map<String, dynamic>.from(contactDetails['client'] as Map)
        : const <String, dynamic>{};
    final restaurantData = contactDetails['restaurant'] is Map
        ? Map<String, dynamic>.from(contactDetails['restaurant'] as Map)
        : const <String, dynamic>{};
    final restaurantSummary = <String, String?>{
      'name': restaurantData['name']?.toString(),
      'phone': restaurantData['phone']?.toString(),
      'address': restaurantData['address']?.toString(),
      'neighborhood': restaurantData['neighborhood']?.toString(),
      'city': restaurantData['city']?.toString(),
      'reference': restaurantData['landmark_reference']?.toString(),
    };
    final clientFullName =
        clientProfile['full_name']?.toString().trim().isNotEmpty == true
        ? clientProfile['full_name'].toString().trim()
        : (order.clientName?.trim().isNotEmpty == true
              ? order.clientName!.trim()
              : 'Cliente nao identificado');
    final clientGender =
        clientProfile['gender']?.toString().trim().isNotEmpty == true
        ? clientProfile['gender'].toString().trim()
        : 'Nao informado';
    final clientPhone =
        clientProfile['phone']?.toString().trim().isNotEmpty == true
        ? clientProfile['phone'].toString().trim()
        : 'Nao informado';
    final restaurantName = restaurantSummary['name']?.trim().isNotEmpty == true
        ? restaurantSummary['name']!.trim()
        : (order.restaurantName?.trim().isNotEmpty == true
              ? order.restaurantName!.trim()
              : 'Restaurante');
    final restaurantPhone =
        restaurantSummary['phone']?.trim().isNotEmpty == true
        ? restaurantSummary['phone']!.trim()
        : 'Nao informado';
    final restaurantPickupLocation = LocationDisplay.displayAddress(
      address: restaurantSummary['address'],
      neighborhood: restaurantSummary['neighborhood'],
      city: restaurantSummary['city'],
      fallback: 'Local do restaurante confirmado no mapa',
    );
    final totalItemQuantity = items.fold<int>(
      0,
      (total, item) => total + item.quantity,
    );
    final restaurantReference =
        restaurantSummary['reference']?.trim().isNotEmpty == true
        ? restaurantSummary['reference']!.trim()
        : (order.restaurantLandmarkReference?.trim() ?? '');
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detalhes da entrega · Pedido #${order.id.substring(0, order.id.length < 8 ? order.id.length : 8)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _buildHistoryRestaurantAvatar(
                    restaurantData['image_url']?.toString() ??
                        order.restaurantImageUrl,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      restaurantName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildCompletedStatusChip(),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _formatHistoryDateTime(
                  order.deliveredAt ?? order.updatedAt ?? order.createdAt,
                ),
              ),
              const SizedBox(height: 4),
              Text('Estado final: Entregue • $totalItemQuantity itens'),
              if (order.courierAmount != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Ganho oficial: ${_money(order.courierAmount!)}',
                  style: const TextStyle(
                    color: AppColors.successGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                'Destino do cliente: ${LocationDisplay.displayAddress(address: order.deliveryAddress, fallback: 'Destino do cliente confirmado no mapa')}',
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F1E7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE9DCC8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dados do restaurante',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text('Nome: $restaurantName'),
                    const SizedBox(height: 4),
                    Text('Telefone: $restaurantPhone'),
                    const SizedBox(height: 4),
                    Text('Local de recolha: $restaurantPickupLocation'),
                    if (restaurantReference.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Referencia: $restaurantReference'),
                    ],
                    if (restaurantPhone != 'Nao informado') ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _callPhoneNumber(
                          restaurantPhone,
                          contactLabel: 'restaurante',
                        ),
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('Ligar para restaurante'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueGrey.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dados do cliente',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text('Nome completo: $clientFullName'),
                    const SizedBox(height: 4),
                    Text('Sexo: $clientGender'),
                    const SizedBox(height: 4),
                    Text('Telefone: $clientPhone'),
                    const SizedBox(height: 4),
                    Text(
                      'Localizacao: ${LocationDisplay.displayAddress(address: order.deliveryAddress, fallback: 'Destino do cliente confirmado no mapa')}',
                    ),
                    if (clientPhone != 'Nao informado') ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _callPhoneNumber(
                          clientPhone,
                          contactLabel: 'cliente',
                        ),
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('Ligar para cliente'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Text(
                    'Este pedido ainda nao tem itens visiveis para o estafeta.',
                  ),
                )
              else
                ...items.map(
                  (item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        item.menuItem?.imageUrl != null &&
                            item.menuItem!.imageUrl!.trim().isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: item.menuItem!.imageUrl!,
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                              memCacheWidth: 176,
                              memCacheHeight: 176,
                              errorWidget: (_, _, _) => Container(
                                width: 88,
                                height: 88,
                                color: AppColors.primaryRed.withValues(
                                  alpha: 0.10,
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.fastfood_rounded,
                                  color: AppColors.primaryRed,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: AppColors.primaryRed.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.fastfood_rounded,
                              color: AppColors.primaryRed,
                            ),
                          ),
                    title: Text(
                      item.menuItem?.name ?? 'Prato',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      '${item.menuItem?.description?.trim().isNotEmpty == true ? item.menuItem!.description!.trim() + "\n" : ""}Qtd ${item.quantity} - ${_money(item.unitPrice)}',
                    ),
                    isThreeLine:
                        item.menuItem?.description?.trim().isNotEmpty == true,
                    trailing: Text(_money(item.subtotal)),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TapScale(
                    child: OrderChatButton(
                      orderId: order.id,
                      onPressed: () {
                        Navigator.of(context).pop();
                        this.context.push('/chat/${order.id}');
                      },
                      unreadCount: _unreadChatCountFor(order.id),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyCourierShareLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link publico do estafeta copiado.')),
    );
  }

  Future<void> _shareCourierProfileTo(String channel) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final courierName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Estafeta DeliGo';
    final link = _publicShareService.courierLink(userId);
    final text = _publicShareService.courierMessage(
      courierName: courierName,
      link: link,
    );

    Uri? uri;
    switch (channel) {
      case 'whatsapp':
        uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}');
        break;
      case 'facebook':
        if (!_publicShareService.hasWebBaseUrl) {
          await _copyCourierShareLink(text);
          return;
        }
        uri = Uri.parse(
          'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(link)}',
        );
        break;
      case 'instagram':
      case 'tiktok':
        await _copyCourierShareLink(text);
        return;
    }

    if (uri != null) {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        await _copyCourierShareLink(text);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (kycStatus != 'approved') {
      return _buildKycBlockedScreen();
    }

    return _buildMainDashboard();
  }

  Widget _buildKycBlockedScreen() {
    final isRejected = kycStatus == 'rejected';

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('Deligo - Estafeta'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
        actions: [
          IconButton(
            icon: const Icon(Icons.support_agent),
            onPressed: () => context.push('/support'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (isRejected ? Colors.red : Colors.orange).withValues(
                  alpha: 0.1,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isRejected ? Icons.cancel : Icons.hourglass_empty,
                size: 80,
                color: isRejected ? Colors.red : Colors.orange,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              isRejected ? 'KYC Reprovado' : 'KYC Pendente',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.darkGray,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (isRejected && rejectionReason != null) ...[
              Card(
                color: Colors.red.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            'Motivo da rejeicao:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        rejectionReason!,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _checkKycStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Verificar Novamente'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryRed,
                  side: const BorderSide(color: AppColors.primaryRed),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainDashboard() {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: _selectedIndex == 0
          ? null
          : AppBar(
              titleSpacing: 12,
              title: Row(
                children: [
                  ProfileImageViewer(
                    imageUrl: _avatarUrl,
                    size: 40,
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    fallbackIcon: Icons.person,
                    iconColor: Colors.white,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nameController.text.trim().isNotEmpty
                              ? _nameController.text.trim()
                              : 'Deligo Biker',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          _phoneController.text.trim().isNotEmpty
                              ? _phoneController.text.trim()
                              : 'Sem telefone definido',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.primaryRed,
              foregroundColor: AppColors.cleanWhite,
              actions: [
                IconButton(
                  onPressed: () => context.push('/deligo-ai'),
                  icon: const Icon(Icons.auto_awesome_outlined),
                  tooltip: 'Assistente DeliGo',
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '$_walletCurrency ${_walletBalance.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Ajuda e segurança',
                  icon: const Icon(Icons.support_agent_outlined),
                  onPressed: _openCourierHelpCenter,
                ),
                IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
              ],
            ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: [_buildHomeTab(), _buildHistoryTab(), _buildProfileTab()],
        ),
      ),
      floatingActionButton: null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          border: Border(
            top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              if (index == 1) {
                HapticFeedback.heavyImpact();
              } else {
                HapticFeedback.selectionClick();
              }
              setState(() => _selectedIndex = index);
            },
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: AppColors.primaryRed,
            unselectedItemColor: AppColors.neutralGray,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
            showSelectedLabels: true,
            showUnselectedLabels: true,
            items: [
              BottomNavigationBarItem(
                icon: _buildTabIcon('assets/bottom_nav/estafeta/home.gif'),
                activeIcon: _buildTabIcon(
                  'assets/bottom_nav/estafeta/home.gif',
                  selected: true,
                ),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: _buildTabIcon('assets/bottom_nav/estafeta/historico.gif'),
                activeIcon: _buildTabIcon(
                  'assets/bottom_nav/estafeta/historico.gif',
                  selected: true,
                ),
                label: 'Histórico',
              ),
              BottomNavigationBarItem(
                icon: _buildTabIcon('assets/bottom_nav/estafeta/perfil.gif'),
                activeIcon: _buildTabIcon(
                  'assets/bottom_nav/estafeta/perfil.gif',
                  selected: true,
                ),
                label: 'Perfil',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    return _buildHomeTabPremium();
    /*
    return RefreshIndicator(
      onRefresh: _loadCourierData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWeatherClockBanner(),
            const SizedBox(height: 16),
            const Text(
              'Dashboard Estafeta',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),

            // Status Online
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Disponibilidade para entregas',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    Switch(
                      value: isOnline,
                      onChanged: _requestCourierOnlineChange,
                      activeThumbColor: Colors.green,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isOnline
                          ? 'Estafeta disponivel para novas entregas'
                          : 'Estafeta indisponivel no momento',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isOnline ? Colors.green : Colors.red,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildCurrentLocationCardYango(),
            const SizedBox(height: 16),

            // Entrega Atual
            if (_currentDelivery != null) ...[
              const Text(
                'Entrega Atual',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                color: AppColors.primaryRed.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pedido #${_currentDelivery!.id.substring(0, 8)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Destino: ${LocationDisplay.displayAddress(address: _currentDelivery!.deliveryAddress, fallback: "Destino do cliente confirmado no mapa")}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total: ${_currentDelivery!.totalAmount.toStringAsFixed(0)} MZN',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryRed,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildCurrentDeliveryRouteSummary(_currentDelivery!),
                      if (_unreadChatCountFor(_currentDelivery!.id) > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 16,
                              color: AppColors.primaryRed,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${_unreadChatCountFor(_currentDelivery!.id)} mensagem(ns) novas',
                              style: const TextStyle(
                                color: AppColors.primaryRed,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      FutureBuilder<List<OrderItem>>(
                        future: _orderService.getOrderItems(
                          _currentDelivery!.id,
                        ),
                        builder: (context, snapshot) {
                          final items = snapshot.data ?? const <OrderItem>[];
                          if (items.isEmpty) {
                            return const Text(
                              'Itens indisponiveis no momento.',
                              style: TextStyle(color: AppColors.neutralGray),
                            );
                          }
                          return _buildOrderItemsPreview(items);
                        },
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => _showOrderDetails(_currentDelivery!),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Ver itens'),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OrderChatButton(
                            orderId: _currentDelivery!.id,
                            onPressed: () =>
                                context.push('/chat/${_currentDelivery!.id}'),
                            unreadCount: _unreadChatCountFor(
                              _currentDelivery!.id,
                            ),
                            label: 'Entrar no chat',
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.push(
                              '/tracking/${_currentDelivery!.id}?viewer=courier',
                            ),
                            icon: const Icon(Icons.route_outlined),
                            label: Text(
                              _isHeadingToRestaurant(_currentDelivery!)
                                  ? 'Ver rota ate o restaurante'
                                  : 'Ver rota ate o cliente',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                  if (_isHeadingToRestaurant(_currentDelivery!)) ...[
                    ElevatedButton.icon(
                          onPressed: () async {
                            final confirmed = await _deliveryService
                                .notifyCourierArrivedAtRestaurant(
                                  _currentDelivery!.id,
                                );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  confirmed
                                      ? 'Cliente e restaurante notificados da chegada.'
                                      : 'Nao foi possivel confirmar a chegada. Verifique o GPS e a proximidade do restaurante.',
                                ),
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(milliseconds: 1000),
                              ),
                            );
                          },
                          icon: const Icon(Icons.storefront_outlined),
                      label: const Text('Ja cheguei ao restaurante'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF111B21),
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _updatingDeliveryStatus ? null : () => _updateDeliveryStatus('in_transit'),
                          icon: const Icon(Icons.delivery_dining),
                          label: const Text('Levantei o pedido'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryRed,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                      if (_currentDelivery!.status == OrderStatus.inTransit ||
                          _currentDelivery!.status == OrderStatus.onTheWay) ...[
                        ElevatedButton.icon(
                          onPressed: _updatingDeliveryStatus ? null : () => _updateDeliveryStatus('arrived'),
                          icon: const Icon(Icons.location_on),
                          label: const Text('Cheguei'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                      if (_currentDelivery!.status == OrderStatus.arrived ||
                          _currentDelivery!.status == OrderStatus.inTransit ||
                          _currentDelivery!.status == OrderStatus.onTheWay) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F4F2),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: AppColors.primaryRed.withValues(
                                alpha: 0.18,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Validar codigo do cliente',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _currentDelivery!.status ==
                                            OrderStatus.inTransit ||
                                        _currentDelivery!.status ==
                                            OrderStatus.onTheWay
                                    ? 'Valide o OTP do cliente. Depois, aguarde a confirmação final dele no app para libertar o ganho.'
                                    : 'Peça o OTP ao cliente. O valor só será libertado quando ele confirmar o recebimento no app.',
                                style: const TextStyle(
                                  color: AppColors.neutralGray,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _deliveryOtpController,
                                keyboardType: TextInputType.number,
                                maxLength: 4,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'OTP do cliente',
                                  counterText: '',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _verifyingDeliveryOtp
                                      ? null
                                      : _verifyCurrentDeliveryOtp,
                                  icon: _verifyingDeliveryOtp
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.verified_outlined),
                                  label: Text(
                                    _verifyingDeliveryOtp
                                        ? 'A validar codigo...'
                                        : 'Validar OTP da entrega',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryRed,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'O OTP confirma a entrega física. A confirmação final do cliente fecha o pedido e disponibiliza o ganho.',
                                style: TextStyle(
                                  color: AppColors.neutralGray,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_currentDelivery!.status ==
                          OrderStatus.deliveryFailedOtp) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.deepOrange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.deepOrange.withValues(alpha: 0.20),
                            ),
                          ),
                          child: const Text(
                            'O caso foi enviado para revisao admin. Aguarde a decisao antes de tentar fechar esta entrega.',
                            style: TextStyle(
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                      if (_currentDelivery!.status == OrderStatus.inTransit ||
                          _currentDelivery!.status == OrderStatus.onTheWay ||
                          _currentDelivery!.status == OrderStatus.arrived ||
                          _currentDelivery!.status ==
                              OrderStatus.deliveryFailedOtp ||
                          _currentDelivery!.status ==
                              OrderStatus.delivered) ...[
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            context.push(
                              '/tracking/${_currentDelivery!.id}?viewer=courier',
                            );
                          },
                          icon: const Icon(Icons.map),
                          label: const Text('Ver no Mapa'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Estatisticas
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            '$_totalDeliveries',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text('Entregas'),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            '${_totalEarnings.toStringAsFixed(0)} MZN',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text('Ganho'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_lastCompletedDelivery != null) ...[
              const SizedBox(height: 16),
              _buildLastCompletedDeliveryCard(_lastCompletedDelivery!),
            ],
          ],
        ),
      ),
    );
    */
  }

  Widget _buildHomeTabPremium() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final bottomInset =
            math.max(mediaQuery.padding.bottom, mediaQuery.viewPadding.bottom) +
            mediaQuery.viewInsets.bottom;
        final availableHeight = math.max(
          0.0,
          constraints.maxHeight - bottomInset,
        );
        final viewport = DeligoViewport(
          width: constraints.maxWidth,
          height: availableHeight,
        );
        final compactMapControls = viewport.isLandscape || viewport.isShort;
        final hasOffer =
            _availableDeliveries.isNotEmpty &&
            isOnline &&
            _currentDelivery == null;
        final panelHeight = hasOffer
            ? viewport.boundedHeight(
                preferred: viewport.isCompact ? 320 : 360,
                fraction: compactMapControls
                    ? 0.78
                    : (viewport.isCompact ? 0.55 : 0.48),
                minimum: compactMapControls ? 176 : 240,
              )
            : _currentDelivery != null
            ? viewport.boundedHeight(
                preferred: viewport.isCompact ? 150 : 172,
                fraction: compactMapControls
                    ? 0.42
                    : (viewport.isCompact ? 0.48 : 0.30),
                minimum: 96,
              )
            : isOnline
            ? 0.0
            : viewport.boundedHeight(
                preferred: 68,
                fraction: compactMapControls ? 0.32 : 0.12,
                minimum: 44,
              );

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _buildCourierFullscreenMap()),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 10,
              left: 12,
              right: 12,
              child: _buildCourierMapHeaderOverlay(),
            ),
            Positioned(
              right: 12,
              bottom: panelHeight + 12,
              child: _buildCourierMapControlsOverlay(
                horizontal: compactMapControls,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: bottomInset + 8,
              height: panelHeight,
              child: hasOffer
                  ? _buildDirectAvailableOfferCard(compact: viewport.isCompact)
                  : _buildCourierHomeDeliveryOverlay(
                      compact: viewport.isCompact,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCourierHomeDeliveryOverlay({bool compact = false}) {
    final delivery = _currentDelivery;
    if (delivery == null) {
      if (_availableDeliveries.isNotEmpty && isOnline) {
        return _buildDirectAvailableOfferCard(compact: compact);
      }
      return _buildCourierDeliveryStatusOverlay();
    }
    final headingToRestaurant = _isHeadingToRestaurant(delivery);
    final arrivedAtRestaurant =
        _arrivedAtRestaurantOrderIds.contains(delivery.id) ||
        delivery.status == OrderStatus.arrived;

    // A Home deve continuar a ser o centro operacional. O resumo detalhado
    // fica sobre o mapa; a página de tracking permanece apenas como ação
    // secundária quando o estafeta toca no painel.
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF111827).withValues(alpha: .92),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .35)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              '#${delivery.id.substring(0, 8).toLowerCase()}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: .4,
              ),
            ),
          ),
        ),
        _buildCurrentDeliveryRouteSummary(delivery),
        const SizedBox(height: 8),
        _courierGlassOverlay(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showOrderDetails(delivery),
                  icon: const Icon(Icons.receipt_long_outlined, size: 17),
                  label: const Text('Ver itens'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: .55),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                if (headingToRestaurant && !arrivedAtRestaurant)
                  FilledButton.icon(
                    onPressed: () => _confirmRestaurantArrival(delivery),
                    icon: const Icon(Icons.storefront_outlined, size: 17),
                    label: const Text('Cheguei'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF111827),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (headingToRestaurant && arrivedAtRestaurant)
                  FilledButton.icon(
                    onPressed: _updatingDeliveryStatus
                        ? null
                        : () => _updateDeliveryStatus('in_transit'),
                    icon: const Icon(Icons.inventory_2_outlined, size: 17),
                    label: const Text('Recolher pedido'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (!headingToRestaurant &&
                    (delivery.status == OrderStatus.inTransit ||
                        delivery.status == OrderStatus.onTheWay))
                  FilledButton.icon(
                    onPressed: _updatingDeliveryStatus
                        ? null
                        : () => _updateDeliveryStatus('arrived'),
                    icon: const Icon(Icons.location_on_outlined, size: 17),
                    label: const Text('Cheguei ao cliente'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.successGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                if (!headingToRestaurant &&
                    delivery.status == OrderStatus.arrived)
                  FilledButton.icon(
                    onPressed: _verifyingDeliveryOtp
                        ? null
                        : () => _showDeliveryOtpDialog(delivery),
                    icon: const Icon(Icons.verified_user_outlined, size: 17),
                    label: const Text('Confirmar entrega com OTP'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    return compact ? SingleChildScrollView(child: content) : content;
  }

  Widget _buildDirectAvailableOfferCard({bool compact = false}) {
    final order = _availableDeliveries.first;
    final routeFuture = _availableRoutePlanFor(order);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: ColoredBox(
        color: const Color(0xF2111827),
        child: FutureBuilder<RoutePlan?>(
          future: routeFuture,
          builder: (context, routeSnapshot) {
            final plan = routeSnapshot.data;
            final routeInfo = plan != null && !plan.isFallback
                ? plan.info
                : null;
            final distanceMeters = routeInfo?.distanceMeters;
            final durationSeconds = routeInfo?.durationSeconds;
            final items = _availableOrderItems[order.id];
            final expanded = _expandedOfferOrderIds.contains(order.id);
            final visibleItems = items == null
                ? const <OrderItem>[]
                : (expanded ? items : items.take(2).toList());
            final itemCount = items?.fold<int>(
              0,
              (sum, item) => sum + item.quantity,
            );
            final rating = order.restaurantRating;
            final courierAmount = _availableCourierAmounts[order.id];
            final offerActionable = _isOfferActionable(order);
            final offerRemaining = _availableOfferRemainingLabel(order);
            final offerUrgent =
                offerActionable && _availableOfferRemainingSeconds(order) <= 5;

            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 16,
                      compact ? 8 : 10,
                      compact ? 12 : 16,
                      8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white38,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1683F7),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              'NOVA ENTREGA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .35,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child:
                                  (order.restaurantImageUrl
                                          ?.trim()
                                          .isNotEmpty ==
                                      true)
                                  ? CachedNetworkImage(
                                      imageUrl: order.restaurantImageUrl!
                                          .trim(),
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          _courierRestaurantFallback(size: 50),
                                    )
                                  : _courierRestaurantFallback(size: 50),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order.restaurantName?.trim().isNotEmpty ==
                                            true
                                        ? order.restaurantName!.trim()
                                        : 'Restaurante',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _offerPickupZone(order),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (rating != null && rating > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white24),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 17,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      rating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _offerMetric(
                                icon: Icons.route_rounded,
                                label: 'Distância',
                                value: distanceMeters == null
                                    ? '—'
                                    : '${(distanceMeters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km',
                                caption: distanceMeters != null
                                    ? 'Até ao restaurante'
                                    : 'Rota por estrada',
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: _offerMetric(
                                icon: Icons.schedule_rounded,
                                label: 'Tempo',
                                value: durationSeconds == null
                                    ? '—'
                                    : '${(durationSeconds / 60).ceil()} min',
                                caption: durationSeconds != null
                                    ? 'ETA da rota'
                                    : routeSnapshot.connectionState ==
                                          ConnectionState.waiting
                                    ? 'A calcular rota'
                                    : 'Rota indisponível',
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: _offerMetric(
                                icon: Icons.account_balance_wallet_rounded,
                                label: 'Seu ganho',
                                value: courierAmount == null
                                    ? '—'
                                    : '${courierAmount.toStringAsFixed(0)} MT',
                                caption: courierAmount == null
                                    ? 'Aguardando valor oficial'
                                    : 'Valor do split',
                                highlight: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .055),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .10),
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Itens do pedido${itemCount == null ? '' : ' ($itemCount)'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (items != null && items.length > 2)
                                    TextButton(
                                      onPressed: () => setState(() {
                                        if (expanded) {
                                          _expandedOfferOrderIds.remove(
                                            order.id,
                                          );
                                        } else {
                                          _expandedOfferOrderIds.add(order.id);
                                        }
                                      }),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      child: Text(
                                        expanded ? 'Ver menos' : 'Ver todos',
                                      ),
                                    ),
                                ],
                              ),
                              if (_availableOrderItemsFailed.contains(
                                order.id,
                              )) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Falha ao carregar os itens.',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => unawaited(
                                        _loadAvailableOrderItems(order.id),
                                      ),
                                      child: const Text('Tentar novamente'),
                                    ),
                                  ],
                                ),
                              ] else if (items == null) ...[
                                const SizedBox(height: 6),
                                const Text(
                                  'A carregar os itens da oferta…',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ] else if (items.isEmpty) ...[
                                const SizedBox(height: 6),
                                const Text(
                                  'Os detalhes dos itens não estão disponíveis antes da aceitação.',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ] else ...[
                                const Divider(
                                  color: Colors.white12,
                                  height: 12,
                                ),
                                for (final item in visibleItems)
                                  _buildOfferItemRow(item),
                                if (items.length > visibleItems.length)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text(
                                      '+${items.length - visibleItems.length} produtos',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 16,
                    6,
                    compact ? 12 : 16,
                    10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: offerUrgent
                              ? const Color(0xFFFF434A).withValues(alpha: .18)
                              : offerActionable
                              ? const Color(0xFF1683F7).withValues(alpha: .16)
                              : Colors.white.withValues(alpha: .06),
                          border: Border.all(
                            color: offerUrgent
                                ? const Color(0xFFFF434A).withValues(alpha: .85)
                                : offerActionable
                                ? const Color(0xFF1683F7).withValues(alpha: .7)
                                : Colors.white24,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 20,
                              color: offerUrgent
                                  ? const Color(0xFFFFA0A4)
                                  : offerActionable
                                  ? Colors.white
                                  : Colors.white54,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Disponível por',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              offerRemaining,
                              style: TextStyle(
                                color: offerUrgent
                                    ? const Color(0xFFFFA0A4)
                                    : offerActionable
                                    ? Colors.white
                                    : Colors.white54,
                                fontSize: 20,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: OutlinedButton(
                              onPressed: offerActionable
                                  ? () => _declineDelivery(order)
                                  : null,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFF434A),
                                side: const BorderSide(
                                  color: Color(0xFFFF434A),
                                  width: 1.6,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 44),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Recusar',
                                  maxLines: 1,
                                  softWrap: false,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: FilledButton(
                              onPressed: offerActionable
                                  ? () => _confirmAcceptDelivery(order)
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFF3039),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 44),
                              ),
                              child: const Text(
                                'Aceitar entrega',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _offerMetric({
    required IconData icon,
    required String label,
    required String value,
    required String caption,
    bool highlight = false,
  }) {
    final color = highlight ? const Color(0xFF37D878) : Colors.white;
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFF075B36).withValues(alpha: .72)
            : Colors.white.withValues(alpha: .07),
        border: Border.all(
          color: highlight ? const Color(0xFF28A860) : Colors.white12,
        ),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferItemRow(OrderItem item) {
    final relation = item.menuItem;
    final name = relation is MenuItem
        ? relation.name
        : relation is Map
        ? relation['name']?.toString()
        : null;
    final imageUrl = relation is MenuItem
        ? relation.imageUrl
        : relation is Map
        ? relation['image_url']?.toString()
        : null;
    final image = imageUrl?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: image.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: image,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _offerItemFallback(),
                  )
                : _offerItemFallback(),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${item.quantity} × ${name?.trim().isNotEmpty == true ? name!.trim() : 'Produto'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offerItemFallback() => Container(
    width: 42,
    height: 42,
    color: Colors.white10,
    alignment: Alignment.center,
    child: const Icon(
      Icons.restaurant_menu_rounded,
      color: Colors.white60,
      size: 19,
    ),
  );

  Widget _courierRestaurantFallback({double size = 46}) => Container(
    width: size,
    height: size,
    color: AppColors.primaryRed.withValues(alpha: .18),
    child: const Icon(Icons.storefront_rounded, color: Colors.white),
  );

  String _offerPickupZone(Order order) {
    bool isCoordinate(String value) => RegExp(
      r'^-?\d{1,3}\.\d{4,}(?:\s*[,;]\s*-?\d{1,3}\.\d{4,})?$',
    ).hasMatch(value.trim());
    final pickupAddress = order.pickupAddress?.trim() ?? '';
    if (pickupAddress.isNotEmpty && !isCoordinate(pickupAddress)) {
      return pickupAddress;
    }
    final locality = [order.restaurantNeighborhood, order.restaurantCity]
        .map((value) => value?.trim() ?? '')
        .where((value) => value.isNotEmpty && !isCoordinate(value))
        .toSet()
        .toList();
    if (locality.isNotEmpty) return locality.join(', ');
    final landmark = order.restaurantLandmarkReference?.trim() ?? '';
    if (landmark.isNotEmpty && !isCoordinate(landmark)) return landmark;
    final address = order.restaurantAddress?.trim() ?? '';
    if (address.isNotEmpty && !isCoordinate(address)) return address;
    return 'Local de recolha não indicado';
  }

  Future<RoutePlan?>? _availableRoutePlanFor(Order order) {
    final origin = _currentPosition == null
        ? _displayCourierLatLng
        : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    if (origin == null) return null;
    final key = _availableRouteRequestKey(order, origin);
    return key == null ? null : _availableRoutePlans[key];
  }

  Future<void> _declineDelivery(Order order) async {
    if (!_deliveryActionsInFlight.add('decline:${order.id}')) return;
    try {
      final success = await _deliveryService.declineDispatchOpportunity(
        orderId: order.id,
      );
      if (!mounted) return;
      if (success) {
        setState(
          () => _availableDeliveries.removeWhere((item) => item.id == order.id),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível recusar esta oferta agora.'),
          ),
        );
      }
    } finally {
      _deliveryActionsInFlight.remove('decline:${order.id}');
    }
  }

  Widget _buildCourierFullscreenMap() {
    final position = _currentPosition;
    final livePosition =
        _displayCourierLatLng ??
        (position != null
            ? LatLng(position.latitude, position.longitude)
            : null);
    final target = livePosition ?? const LatLng(-25.9692, 32.5732);
    final markers = <Marker>{};
    final circles = <Circle>{};
    if (livePosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('courier_current_live_fullscreen'),
          position: livePosition,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          rotation: _displayCourierBearing ?? 0,
          infoWindow: const InfoWindow(title: 'Sua localização atual'),
          icon: _courierMapMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }
    final delivery = _currentDelivery;
    final offerOrder =
        delivery == null && isOnline && _availableDeliveries.isNotEmpty
        ? _availableDeliveries.first
        : null;
    final offerDestination = offerOrder == null
        ? null
        : _latLng(
            offerOrder.pickupLatitude ?? offerOrder.restaurantLatitude,
            offerOrder.pickupLongitude ?? offerOrder.restaurantLongitude,
          );
    final offerOrigin = position == null
        ? livePosition
        : LatLng(position.latitude, position.longitude);
    final offerRouteKey = offerOrder != null && offerOrigin != null
        ? _availableRouteRequestKey(offerOrder, offerOrigin)
        : null;
    final offerRouteFuture = offerRouteKey == null
        ? null
        : _availableRoutePlans[offerRouteKey];
    final headingToRestaurant =
        delivery != null && _isHeadingToRestaurant(delivery);
    final directDestination = delivery == null
        ? null
        : headingToRestaurant
        ? _latLng(
            delivery.pickupLatitude ?? delivery.restaurantLatitude,
            delivery.pickupLongitude ?? delivery.restaurantLongitude,
          )
        : _latLng(delivery.deliveryLatitude, delivery.deliveryLongitude);
    final phaseKey = delivery == null
        ? null
        : '${delivery.id}:${headingToRestaurant ? 'restaurant' : 'client'}';
    if (phaseKey != null && _homeEndpointKey != phaseKey) {
      _homeEndpointKey = phaseKey;
      _homeResolvedEndpoint = directDestination;
      _homeEndpointFuture = directDestination != null
          ? Future<LatLng?>.value(directDestination)
          : _resolveHomeEndpoint(delivery!, headingToRestaurant);
      _homeEndpointFuture!.then((resolved) {
        if (!mounted || _homeEndpointKey != phaseKey) return;
        if (_homeResolvedEndpoint == resolved) return;
        setState(() => _homeResolvedEndpoint = resolved);
      });
    }
    final destination =
        directDestination ??
        (_homeEndpointKey == phaseKey ? _homeResolvedEndpoint : null);
    final routeKey = phaseKey == null || destination == null
        ? null
        : '$phaseKey:${livePosition == null ? 'waiting-for-gps' : 'gps-ready'}';
    if (routeKey != null && _homeRouteKey != routeKey) {
      _homeRouteKey = routeKey;
      final origin = livePosition ?? destination!;
      _homeRouteFuture = MapsRouteService.getRoute(
        origin: origin,
        destination: destination!,
        travelMode: 'driving',
      );
      _homeRouteInfoFuture = MapsRouteService.getCachedRouteInfo(
        cacheKey: 'courier-home-$routeKey',
        origin: origin,
        destination: destination,
        travelMode: 'driving',
      );
    }

    Widget mapWithRoute(
      List<LatLng> routePoints, {
      bool isOfferRoute = false,
      bool routeIsFallback = false,
    }) {
      final markerDestination = isOfferRoute ? offerDestination : destination;
      if (markerDestination != null) {
        markers.add(
          Marker(
            markerId: MarkerId(
              isOfferRoute
                  ? 'courier_offer_restaurant'
                  : (headingToRestaurant
                        ? 'courier_home_restaurant'
                        : 'courier_home_client'),
            ),
            position: markerDestination,
            infoWindow: InfoWindow(
              title: isOfferRoute
                  ? (offerOrder?.restaurantName ?? 'Restaurante')
                  : (headingToRestaurant ? 'Restaurante' : 'Cliente'),
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isOfferRoute || headingToRestaurant
                  ? BitmapDescriptor.hueOrange
                  : BitmapDescriptor.hueRed,
            ),
          ),
        );
      }
      final polylines =
          routePoints.length < 2 || (isOfferRoute && routeIsFallback)
          ? <Polyline>{}
          : <Polyline>{
              Polyline(
                polylineId: PolylineId(
                  isOfferRoute
                      ? 'courier_offer_route_${offerOrder!.id}'
                      : 'courier_home_active_route',
                ),
                points: routePoints,
                color: AppColors.primaryRed,
                width: 6,
                jointType: JointType.round,
              ),
            };
      return YangoMapWidget(
        key: const ValueKey('courier_dashboard_fullscreen_map'),
        initialCameraPosition: CameraPosition(
          target: target,
          zoom: livePosition == null ? 12 : _courierMapZoom,
          tilt: _courierMapTilt,
        ),
        markers: markers,
        polylines: polylines,
        circles: circles,
        // The DeliGo marker is the single source of the courier position.
        // The native Google Maps blue dot would create a duplicate marker.
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        compassEnabled: false,
        showCurrentLocationButton: false,
        showFollowButton: false,
        followEnabled: _followCourierMap,
        eagerGestureHandling: true,
        onCurrentLocationPressed: _loadCurrentLocation,
        onCameraMoveStarted: () {
          if (_followCourierMap && !_isAnimatingCourierCamera) {
            setState(() => _followCourierMap = false);
          }
        },
        onFollowToggle: () async {
          setState(() => _followCourierMap = !_followCourierMap);
          if (_followCourierMap) await _followCourierMapCamera();
        },
        onMapCreated: (controller) {
          _courierMapController = controller;
          if (offerOrder != null &&
              offerDestination != null &&
              offerOrigin != null &&
              offerRouteFuture != null &&
              offerRouteKey != null) {
            _fittedOfferRouteKeys.remove(offerRouteKey);
            offerRouteFuture.then((plan) {
              if (plan != null && !plan.isFallback) {
                _scheduleOfferRouteCameraFit(
                  routeKey: offerRouteKey,
                  origin: offerOrigin,
                  destination: offerDestination,
                  points: plan.points,
                );
              }
            });
          } else if (livePosition != null) {
            _followCourierMapCamera();
          }
        },
      );
    }

    if (offerOrder != null && offerDestination != null && offerOrigin != null) {
      final future = offerRouteFuture;
      if (future != null && offerRouteKey != null) {
        return FutureBuilder<RoutePlan?>(
          future: future,
          builder: (context, snapshot) {
            final plan = snapshot.data;
            if (plan != null && !plan.isFallback) {
              _scheduleOfferRouteCameraFit(
                routeKey: offerRouteKey,
                origin: offerOrigin,
                destination: offerDestination,
                points: plan.points,
              );
              return mapWithRoute(plan.points, isOfferRoute: true);
            }
            return mapWithRoute(
              const <LatLng>[],
              isOfferRoute: true,
              routeIsFallback: plan?.isFallback ?? false,
            );
          },
        );
      }
      return mapWithRoute(const <LatLng>[], isOfferRoute: true);
    }

    final routeFuture = _homeRouteFuture;
    if (routeFuture == null) return mapWithRoute(const <LatLng>[]);
    return FutureBuilder<List<LatLng>>(
      future: routeFuture,
      builder: (context, snapshot) => mapWithRoute(snapshot.data ?? const []),
    );
  }

  void _scheduleOfferRouteCameraFit({
    required String routeKey,
    required LatLng origin,
    required LatLng destination,
    required List<LatLng> points,
  }) {
    if (!_followCourierMap || _fittedOfferRouteKeys.contains(routeKey)) return;
    final controller = _courierMapController;
    if (controller == null || points.length < 2) return;
    final boundsPoints = <LatLng>[origin, destination, ...points];
    final minLat = boundsPoints.map((point) => point.latitude).reduce(math.min);
    final maxLat = boundsPoints.map((point) => point.latitude).reduce(math.max);
    final minLng = boundsPoints
        .map((point) => point.longitude)
        .reduce(math.min);
    final maxLng = boundsPoints
        .map((point) => point.longitude)
        .reduce(math.max);
    if (minLat == maxLat && minLng == maxLng) return;
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    _fittedOfferRouteKeys.add(routeKey);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_followCourierMap || _currentDelivery != null) {
        _fittedOfferRouteKeys.remove(routeKey);
        return;
      }
      final stillOffered = _availableDeliveries.any(
        (order) =>
            order.id == routeKey.split(':').first &&
            _availableRouteRequestKey(order, origin) == routeKey,
      );
      if (!stillOffered) {
        _fittedOfferRouteKeys.remove(routeKey);
        return;
      }
      final latestOrigin = _currentPosition == null
          ? _displayCourierLatLng
          : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      final latestOrder = _availableDeliveries.firstWhere(
        (order) => order.id == routeKey.split(':').first,
        orElse: () => _availableDeliveries.first,
      );
      if (latestOrigin == null ||
          _availableRouteRequestKey(latestOrder, latestOrigin) != routeKey) {
        _fittedOfferRouteKeys.remove(routeKey);
        return;
      }
      try {
        await _courierMapController?.fitLatLngBounds(bounds, padding: 100);
      } catch (error) {
        debugPrint('[COURIER_OFFER] camera fit failed: $error');
      }
    });
  }

  Future<LatLng?> _resolveHomeEndpoint(
    Order order,
    bool headingToRestaurant,
  ) async {
    if (headingToRestaurant && order.restaurantId.trim().isNotEmpty) {
      try {
        final restaurant = await supabase
            .from('restaurants')
            .select('latitude, longitude, location_status')
            .eq('id', order.restaurantId.trim())
            .maybeSingle();
        final latitude = (restaurant?['latitude'] as num?)?.toDouble();
        final longitude = (restaurant?['longitude'] as num?)?.toDouble();
        final locationStatus = restaurant?['location_status'] as String?;
        if (latitude != null &&
            longitude != null &&
            locationStatus == 'confirmed') {
          return LatLng(latitude, longitude);
        }
      } catch (_) {}

      // An address is for human display only. Never geocode it as an
      // operational pickup destination: an ambiguous street name can send a
      // courier to a different place. The restaurant must confirm its pin,
      // or the order must carry a pickup snapshot.
      return null;
    }

    // Addresses are for display only. Pickup and delivery routes must use
    // coordinates frozen in the order snapshot, never ambiguous geocoding.
    return null;
  }

  LatLng? _latLng(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return null;
    return LatLng(latitude, longitude);
  }

  Widget _buildCourierMapHeaderOverlay() {
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Estafeta DeliGo';
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 500) {
          return Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: const Color(0xFF111827),
                backgroundImage:
                    _avatarUrl != null && _avatarUrl!.trim().isNotEmpty
                    ? NetworkImage(_avatarUrl!)
                    : null,
                child: (_avatarUrl == null || _avatarUrl!.trim().isEmpty)
                    ? const Icon(Icons.person_rounded, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _courierGlassOverlay(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: isOnline
                                  ? AppColors.successGreen
                                  : Colors.white54,
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () =>
                                  _requestCourierOnlineChange(!isOnline),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isOnline ? 'Online' : 'Offline',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    const Icon(
                                      Icons.power_settings_new_rounded,
                                      size: 13,
                                      color: Colors.white70,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '${_walletBalance.toStringAsFixed(0)} $_walletCurrency',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              _courierIconButton(
                icon: Icons.notifications_none_rounded,
                tooltip: 'Notificações',
                badgeCount: _unreadNotificationCount,
                onTap: () => unawaited(_showCourierNotifications()),
              ),
            ],
          );
        }

        return Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: const Color(0xFF111827),
              backgroundImage:
                  _avatarUrl != null && _avatarUrl!.trim().isNotEmpty
                  ? NetworkImage(_avatarUrl!)
                  : null,
              child: (_avatarUrl == null || _avatarUrl!.trim().isEmpty)
                  ? const Icon(Icons.person_rounded, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 158,
              child: _courierGlassOverlay(
                child: InkWell(
                  onTap: () => _requestCourierOnlineChange(!isOnline),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.circle,
                          size: 9,
                          color: isOnline
                              ? AppColors.successGreen
                              : Colors.white54,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isOnline ? 'Online' : 'Offline',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.power_settings_new_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _courierGlassOverlay(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  '${_walletBalance.toStringAsFixed(0)} $_walletCurrency',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _courierIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notificações',
              badgeCount: _unreadNotificationCount,
              onTap: () {
                unawaited(_showCourierNotifications());
              },
            ),
          ],
        );
      },
    );
  }

  Widget _courierGlassOverlay({required Widget child}) {
    return ColoredBox(color: const Color(0xDD111827), child: child);
  }

  Widget _buildCourierMapControlsOverlay({bool horizontal = false}) {
    final controls = [
      _courierGlassOverlay(
        child: IconButton(
          tooltip: 'Recentrar localização',
          onPressed: _loadCurrentLocation,
          icon: const Icon(Icons.my_location_rounded, color: Colors.white),
        ),
      ),
      _courierGlassOverlay(
        child: IconButton(
          tooltip: 'Seguir localização',
          onPressed: () async {
            setState(() => _followCourierMap = true);
            await _followCourierMapCamera();
          },
          icon: Icon(
            Icons.navigation_rounded,
            color: _followCourierMap ? AppColors.successGreen : Colors.white,
          ),
        ),
      ),
    ];
    if (horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [controls.first, const SizedBox(width: 8), controls.last],
      );
    }
    return Column(
      children: [controls.first, const SizedBox(height: 8), controls.last],
    );
  }

  Widget _buildCourierDeliveryStatusOverlay() {
    final delivery = _currentDelivery;
    if (delivery == null) {
      final online = isOnline;
      if (online) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xE6111827),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .16)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 19, color: Colors.amber),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Fique online para receber entregas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isAtRestaurant =
        _arrivedAtRestaurantOrderIds.contains(delivery.id) ||
        delivery.status == OrderStatus.arrived;
    final headingToRestaurant =
        _isHeadingToRestaurant(delivery) && !isAtRestaurant;
    final text = isAtRestaurant
        ? 'Chegou ao restaurante · #${delivery.id.substring(0, 8)}'
        : headingToRestaurant
        ? 'Ir ao restaurante · próxima ação'
        : 'Ir ao cliente · próxima ação';
    return SizedBox.expand(
      child: _courierGlassOverlay(
        child: InkWell(
          onTap: () => context.push('/tracking/${delivery.id}?viewer=courier'),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            child: Row(
              children: [
                const Icon(Icons.local_shipping_rounded, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCourierPremiumHeader() {
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Estafeta DeliGo';
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFF111827),
          backgroundImage: _avatarUrl != null && _avatarUrl!.trim().isNotEmpty
              ? NetworkImage(_avatarUrl!)
              : null,
          child: (_avatarUrl == null || _avatarUrl!.trim().isEmpty)
              ? const Icon(Icons.person_rounded, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => _requestCourierOnlineChange(!isOnline),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 10,
                        color: isOnline
                            ? AppColors.successGreen
                            : AppColors.neutralGray,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: isOnline
                              ? AppColors.successGreen
                              : AppColors.neutralGray,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.power_settings_new_rounded, size: 15),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () => context.push('/wallet'),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _isTestWallet ? 'SALDO TESTE' : 'SALDO',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${_walletBalance.toStringAsFixed(0)} $_walletCurrency',
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _courierIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: 'Notificacoes',
          badgeCount: _unreadNotificationCount,
          onTap: () {
            unawaited(_showCourierNotifications());
          },
        ),
      ],
    );
  }

  Widget _buildCourierNextDeliveryCard(Order? order) {
    if (order == null) {
      return _premiumCourierCard(
        child: Row(
          children: [
            _courierAccentIcon(Icons.radar_rounded, AppColors.primaryRed),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isOnline
                    ? 'Estamos a procurar a proxima entrega ideal para si.'
                    : 'Fique online para receber entregas em tempo real.',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF101828),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final pickupToClient =
        (order.pickupLatitude ?? order.restaurantLatitude) != null &&
            (order.pickupLongitude ?? order.restaurantLongitude) != null &&
            order.deliveryLatitude != null &&
            order.deliveryLongitude != null
        ? Geolocator.distanceBetween(
            order.pickupLatitude ?? order.restaurantLatitude!,
            order.pickupLongitude ?? order.restaurantLongitude!,
            order.deliveryLatitude!,
            order.deliveryLongitude!,
          )
        : null;
    final routeLabel = pickupToClient == null
        ? 'Distancia a confirmar'
        : pickupToClient < 1000
        ? '${pickupToClient.round()} m rota'
        : '${(pickupToClient / 1000).toStringAsFixed(1)} km rota';

    return _premiumCourierCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _courierAccentIcon(
                Icons.local_shipping_outlined,
                AppColors.primaryRed,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Proxima entrega',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              Text(
                '${order.deliveryFee.toStringAsFixed(0)} MZN',
                style: const TextStyle(
                  color: AppColors.primaryRed,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _courierMiniPill(Icons.route_outlined, routeLabel),
              _courierMiniPill(
                Icons.timer_outlined,
                pickupToClient == null
                    ? 'Tempo a confirmar'
                    : '${((pickupToClient / 1000) / 25 * 60).ceil()} min rota',
              ),
              _courierMiniPill(
                Icons.schedule_outlined,
                '${order.estimatedPreparationMinutes} min',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _courierInfoLine(
            Icons.storefront_outlined,
            order.restaurantName?.trim().isNotEmpty == true
                ? order.restaurantName!
                : 'Restaurante parceiro',
          ),
          const SizedBox(height: 8),
          _courierInfoLine(
            Icons.person_outline,
            order.clientName?.trim().isNotEmpty == true
                ? order.clientName!
                : 'Cliente DeliGo',
          ),
          const SizedBox(height: 8),
          _courierInfoLine(
            Icons.location_on_outlined,
            LocationDisplay.displayAddress(
              address: order.deliveryAddress,
              fallback: 'Destino confirmado no mapa',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.push('/wallet?section=deposit'),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Depositar'),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _locallyDeclinedDeliveryIds.add(order.id));
                    HapticFeedback.selectionClick();
                  },
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Recusar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF111827),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: isOnline
                      ? () => _confirmAcceptDelivery(order)
                      : null,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Aceitar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.successGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
    );
  }

  Widget _buildCourierActiveDeliveryCard(Order order) {
    final headingToRestaurant = _isHeadingToRestaurant(order);
    final headingToClient =
        order.status == OrderStatus.inTransit ||
        order.status == OrderStatus.onTheWay;
    final arrivedAtRestaurant = _arrivedAtRestaurantOrderIds.contains(order.id);
    return _premiumCourierCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _courierAccentIcon(
                Icons.navigation_rounded,
                AppColors.successGreen,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Entrega ativa #${order.id.substring(0, 8)}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              _courierMiniPill(
                Icons.payments_outlined,
                '${order.totalAmount.toStringAsFixed(0)} MZN',
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCourierDeliveryMetrics(order),
          const SizedBox(height: 14),
          if (headingToRestaurant) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: arrivedAtRestaurant
                    ? null
                    : () => _confirmRestaurantArrival(order),
                icon: Icon(
                  arrivedAtRestaurant
                      ? Icons.check_circle_rounded
                      : Icons.storefront_outlined,
                ),
                label: Text(
                  arrivedAtRestaurant
                      ? 'Chegada confirmada'
                      : 'Ja cheguei ao restaurante',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _updatingDeliveryStatus
                    ? null
                    : () => _updateDeliveryStatus('in_transit'),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Levantei o pedido'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (headingToClient) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _updatingDeliveryStatus
                    ? null
                    : () => _updateDeliveryStatus('arrived'),
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Ja cheguei ao cliente'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.successGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (order.status == OrderStatus.arrived) ...[
            TextField(
              controller: _deliveryOtpController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Codigo de entrega do cliente',
                hintText: 'Digite os 4 digitos',
                counterText: '',
                prefixIcon: Icon(Icons.password_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _verifyingDeliveryOtp
                    ? null
                    : _verifyCurrentDeliveryOtp,
                icon: _verifyingDeliveryOtp
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_outlined),
                label: Text(
                  _verifyingDeliveryOtp
                      ? 'A validar codigo...'
                      : 'Validar e concluir entrega',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.successGreen.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.successGreen.withValues(alpha: 0.24),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.successGreen,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cliente notificado. Solicite o codigo para concluir a entrega.',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OrderChatButton(
                orderId: order.id,
                onPressed: () => context.push('/chat/${order.id}'),
                unreadCount: _unreadChatCountFor(order.id),
                label: 'Chat',
              ),
              FilledButton.icon(
                onPressed: () =>
                    context.push('/tracking/${order.id}?viewer=courier'),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Navegar'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showOrderDetails(order),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Itens'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCourierDeliveryMetrics(Order order) {
    final current = _currentPosition;
    final pickupLat = order.restaurantLatitude;
    final pickupLng = order.restaurantLongitude;
    final deliveryLat = order.deliveryLatitude;
    final deliveryLng = order.deliveryLongitude;

    double? distanceToPickup;
    if (current != null && pickupLat != null && pickupLng != null) {
      distanceToPickup = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        pickupLat,
        pickupLng,
      );
    }
    double? pickupToClient;
    if (pickupLat != null &&
        pickupLng != null &&
        deliveryLat != null &&
        deliveryLng != null) {
      pickupToClient = Geolocator.distanceBetween(
        pickupLat,
        pickupLng,
        deliveryLat,
        deliveryLng,
      );
    }

    int minutesFor(double? meters) =>
        meters == null ? 0 : ((meters / 1000) / 25 * 60).ceil().clamp(1, 999);
    String distanceLabel(double? meters) {
      if (meters == null) return '--';
      return meters < 1000
          ? '${meters.round()} m'
          : '${(meters / 1000).toStringAsFixed(1)} km';
    }

    final headingToRestaurant = _isHeadingToRestaurant(order);
    final currentLegDistance = headingToRestaurant
        ? distanceToPickup
        : (current != null && deliveryLat != null && deliveryLng != null)
        ? Geolocator.distanceBetween(
            current.latitude,
            current.longitude,
            deliveryLat,
            deliveryLng,
          )
        : pickupToClient;
    final totalMinutes = headingToRestaurant
        ? minutesFor(distanceToPickup) + minutesFor(pickupToClient)
        : minutesFor(currentLegDistance);
    final metrics = <({String label, String value, IconData icon})>[
      (
        label: 'Coleta',
        value: LocationDisplay.displayAddress(
          address: order.restaurantAddress,
          neighborhood: order.restaurantNeighborhood,
          city: order.restaurantCity,
          fallback: order.restaurantName ?? 'Restaurante',
        ),
        icon: Icons.storefront_outlined,
      ),
      (
        label: 'Entrega',
        value: LocationDisplay.displayAddress(
          address: order.deliveryAddress,
          fallback: 'Endereco do cliente',
        ),
        icon: Icons.location_on_outlined,
      ),
      (
        label: 'Distancia',
        value: distanceLabel(currentLegDistance),
        icon: Icons.route_outlined,
      ),
      (
        label: 'Ate a coleta',
        value: '${minutesFor(distanceToPickup)} min',
        icon: Icons.schedule_outlined,
      ),
      (
        label: 'A receber',
        value: '${order.deliveryFee.toStringAsFixed(0)} MZN',
        icon: Icons.payments_outlined,
      ),
      (
        label: 'Tempo estimado',
        value: '$totalMinutes min',
        icon: Icons.timer_outlined,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.85,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Icon(metric.icon, size: 18, color: AppColors.primaryRed),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.neutralGray,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      metric.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF101828),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCourierGoalBar(int remaining) {
    final progress = remaining == 0 ? 1.0 : (3 - remaining) / 3;
    return _premiumCourierCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _courierAccentIcon(Icons.flag_outlined, const Color(0xFFFFB020)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  remaining == 0
                      ? 'Meta batida. Bonus +200 MT desbloqueado.'
                      : 'Faca mais $remaining entrega(s) e ganhe +200 MT.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: const Color(0xFFFFB020),
              backgroundColor: const Color(0xFFE5E7EB),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourierStatsGrid(int todayDeliveries) {
    final onlineElapsed =
        _onlineToday +
        (isOnline && _onlineTodayLoadedAt != null
            ? MozambiqueTime.now().difference(_onlineTodayLoadedAt!)
            : Duration.zero);
    final stats = [
      (
        'Ganhos hoje',
        '${_todayEarnings.toStringAsFixed(0)} MT',
        Icons.today_outlined,
      ),
      (
        'Esta semana',
        '${_weekEarnings.toStringAsFixed(0)} MT',
        Icons.date_range_outlined,
      ),
      (
        'Disponível',
        '${_walletBalance.toStringAsFixed(0)} MT',
        Icons.account_balance_wallet_outlined,
      ),
      (
        'Avaliação',
        '★ ${_courierRating.toStringAsFixed(1)} · $_courierReviewCount',
        Icons.star_rounded,
      ),
      ('Entregas hoje', '$todayDeliveries', Icons.check_circle_outline),
      (
        'Online hoje',
        _formatOnlineDuration(onlineElapsed),
        Icons.access_time_rounded,
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.05,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final stat = stats[index];
        return _premiumCourierCard(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(stat.$3, color: AppColors.primaryRed, size: 19),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stat.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stat.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.neutralGray,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatOnlineDuration(Duration value) {
    final minutes = value.inMinutes;
    if (minutes <= 0) return isOnline ? 'A iniciar…' : '0 min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return hours > 0 ? '${hours}h ${remaining}min' : '$remaining min';
  }

  Widget _buildCourierWalletPanel() {
    return _premiumCourierCard(
      child: Row(
        children: [
          _courierAccentIcon(
            Icons.account_balance_wallet_outlined,
            AppColors.primaryRed,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isTestWallet
                      ? 'Carteira de teste — não levantável'
                      : 'Carteira disponível',
                  style: TextStyle(
                    color: AppColors.neutralGray,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_walletCurrency ${_walletBalance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF101828),
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => context.push('/operational-finance/courier'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF111827),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Financeiro'),
          ),
        ],
      ),
    );
  }

  Widget _buildCourierQuickActions() {
    final List<({IconData icon, String label, VoidCallback onTap})> actions = [
      (
        icon: Icons.chat_bubble_outline,
        label: 'Chat',
        onTap: () {
          if (_currentDelivery != null) {
            context.push('/chat/${_currentDelivery!.id}');
          } else {
            setState(() => _selectedIndex = 1);
          }
        },
      ),
      (
        icon: Icons.support_agent_outlined,
        label: 'Suporte',
        onTap: () => context.push('/support'),
      ),
      (
        icon: Icons.sos_outlined,
        label: 'SOS',
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Canal SOS aberto. A equipa de suporte foi destacada.',
              ),
              duration: Duration(milliseconds: 1200),
            ),
          );
          context.push('/support');
        },
      ),
      (
        icon: Icons.navigation_outlined,
        label: 'Navegacao',
        onTap: () {
          if (_currentDelivery != null) {
            context.push('/tracking/${_currentDelivery!.id}?viewer=courier');
          }
        },
      ),
    ];
    return Row(
      children: actions.map((action) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _premiumCourierCard(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: InkWell(
                onTap: action.onTap,
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  children: [
                    Icon(action.icon, color: const Color(0xFF111827)),
                    const SizedBox(height: 6),
                    Text(
                      action.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _premiumCourierCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EAEE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _courierIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Icon(icon, color: const Color(0xFF111827)),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryRed,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badgeCount > 9 ? '9+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _courierAccentIcon(IconData icon, Color color) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color),
    );
  }

  Widget _courierMiniPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF111827)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _courierInfoLine(IconData icon, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.neutralGray),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF344054),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeliveriesTab() {
    return RefreshIndicator(
      onRefresh: _loadCourierData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Entregas Disponiveis',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            if (!isOnline)
              Card(
                color: Colors.orange.withValues(alpha: 0.1),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Fique online para receber entregas'),
                    ],
                  ),
                ),
              ),

            if (_availableDeliveries.isEmpty && isOnline)
              Center(
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Icon(
                      Icons.local_shipping,
                      size: 64,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 16),
                    const Text('Nenhuma entrega disponivel'),
                  ],
                ),
              )
            else if (_availableDeliveries.isNotEmpty)
              ...(_availableDeliveries.map(
                (order) => _buildDeliveryCard(order),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryCard(Order order) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pedido #${order.id.substring(0, 8)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${order.totalAmount.toStringAsFixed(0)} MZN',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryRed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 16,
                  color: AppColors.neutralGray,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    LocationDisplay.displayAddress(
                      address: order.deliveryAddress,
                      fallback: 'Destino do cliente confirmado no mapa',
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.neutralGray,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<OrderItem>>(
              future: _orderService.getOrderItems(order.id),
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <OrderItem>[];
                if (items.isEmpty) {
                  return const Text(
                    'Itens indisponiveis no momento.',
                    style: TextStyle(color: AppColors.neutralGray),
                  );
                }
                return _buildOrderItemsPreview(items);
              },
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: TapScale(
                    child: OutlinedButton.icon(
                      onPressed: () => _showOrderDetails(order),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Ver itens'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TapScale(
                    child: ElevatedButton(
                      onPressed: isOnline
                          ? () => _confirmAcceptDelivery(order)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryRed,
                        foregroundColor: AppColors.cleanWhite,
                      ),
                      child: const Text('Aceitar Entrega'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItemsPreview(List<OrderItem> items) {
    final visibleItems = items.take(3).toList();
    return Column(
      children: [
        ...visibleItems.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                if (item.menuItem?.imageUrl != null &&
                    item.menuItem!.imageUrl!.trim().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: item.menuItem!.imageUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      memCacheWidth: 88,
                      memCacheHeight: 88,
                    ),
                  )
                else
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.fastfood_rounded,
                      color: AppColors.primaryRed,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.menuItem?.name ?? 'Item',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'Qtd ${item.quantity} · ${item.unitPrice.toStringAsFixed(0)} MZN',
                        style: const TextStyle(color: AppColors.neutralGray),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${item.subtotal.toStringAsFixed(0)} MZN',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        if (items.length > visibleItems.length)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '+${items.length - visibleItems.length} itens',
              style: const TextStyle(color: AppColors.neutralGray),
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    return _buildDeliveryHistoryTab();
  }

  Widget _buildAnimatedHistoryItem({
    required int order,
    required Widget child,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (order * 40)),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, builtChild) {
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * (18 + (order * 3))),
            child: builtChild,
          ),
        );
      },
    );
  }

  Widget _buildDeliveryHistoryTab() {
    if (_loadingHistory && _completedDeliveries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_completedDeliveries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text(
              'Ainda nao concluiu entregas',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _completedDeliveries.length,
      itemBuilder: (context, index) {
        final order = _completedDeliveries[index];
        final completedAt =
            order.deliveredAt ?? order.updatedAt ?? order.createdAt;
        final restaurantName = order.restaurantName?.trim().isNotEmpty == true
            ? order.restaurantName!.trim()
            : 'Restaurante';
        final quantity = _completedItemCounts[order.id];
        final courierAmount = order.courierAmount;
        return _buildAnimatedHistoryItem(
          order: index,
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _showOrderDetails(order),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _buildHistoryRestaurantAvatar(order.restaurantImageUrl),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            restaurantName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Pedido #${order.id.substring(0, order.id.length < 8 ? order.id.length : 8)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.neutralGray,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _formatHistoryDateTime(completedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            quantity == null
                                ? 'Itens indisponiveis'
                                : '$quantity ${quantity == 1 ? 'item' : 'itens'}',
                            style: const TextStyle(
                              color: AppColors.neutralGray,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildCompletedStatusChip(),
                              if (courierAmount != null)
                                Text(
                                  'Ganho: ${_money(courierAmount)}',
                                  style: const TextStyle(
                                    color: AppColors.successGreen,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                )
                              else
                                const Text(
                                  'Ganho nao registado',
                                  style: TextStyle(
                                    color: AppColors.neutralGray,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<List<Order>> _getCompletedDeliveries() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return [];

      final response = await supabase
          .from('orders')
          .select(
            '*, restaurants(name,image_url,address,neighborhood,city), payment_splits(courier_amount)',
          )
          .eq('courier_id', user.id)
          .inFilter('status', ['delivered', 'completed', 'auto_completed'])
          .order('updated_at', ascending: false);

      return (response as List).map((data) => Order.fromMap(data)).toList();
    } catch (e) {
      debugPrint('[COURIER_HISTORY] completed deliveries load failed: $e');
      return [];
    }
  }

  Future<Map<String, int>> _getCompletedItemCounts(List<Order> orders) async {
    if (orders.isEmpty) return const {};
    try {
      final response = await supabase
          .from('order_items')
          .select('order_id,quantity')
          .inFilter('order_id', orders.map((order) => order.id).toList());
      final counts = <String, int>{for (final order in orders) order.id: 0};
      for (final row in (response as List).cast<Map<String, dynamic>>()) {
        final orderId = row['order_id']?.toString();
        if (orderId == null || orderId.isEmpty) continue;
        counts.update(
          orderId,
          (count) => count + ((row['quantity'] as num?)?.toInt() ?? 0),
          ifAbsent: () => (row['quantity'] as num?)?.toInt() ?? 0,
        );
      }
      return counts;
    } catch (error) {
      debugPrint('[COURIER_HISTORY] item counts unavailable: $error');
      return const {};
    }
  }

  Widget _buildHistoryRestaurantAvatar(String? imageUrl) {
    final url = imageUrl?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 56,
        height: 56,
        child: url.isEmpty
            ? _historyRestaurantFallback()
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 112,
                memCacheHeight: 112,
                errorWidget: (_, _, _) => _historyRestaurantFallback(),
                placeholder: (_, _) => _historyRestaurantFallback(),
              ),
      ),
    );
  }

  Widget _buildCompletedStatusChip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.successGreen.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Text(
      'Entregue',
      style: TextStyle(
        color: AppColors.successGreen,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _historyRestaurantFallback() => Container(
    color: AppColors.primaryRed.withValues(alpha: 0.08),
    alignment: Alignment.center,
    child: const Icon(Icons.restaurant_rounded, color: AppColors.primaryRed),
  );

  String _formatHistoryDateTime(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} • ${two(date.hour)}:${two(date.minute)}';
  }

  String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)} ${two(date.hour)}:${two(date.minute)}';
  }

  Widget _buildCurrentLocationCardYango() {
    final position = _currentPosition;
    final mapHeight = _courierMapHeight(context);
    final livePosition =
        _displayCourierLatLng ??
        (position != null
            ? LatLng(position.latitude, position.longitude)
            : null);
    final hasLivePosition = livePosition != null;
    final addressLine = _currentAddressLine.trim().isNotEmpty
        ? _currentAddressLine.trim()
        : (_resolvingAddress
              ? 'A obter localização…'
              : (livePosition != null
                    ? _fallbackLocationLabelForLatLng(livePosition)
                    : 'A obter localização…'));
    final localityLine = [
      _currentNeighborhood.trim(),
      _currentCity.trim(),
    ].where((value) => value.isNotEmpty).join(' - ');
    final markers = <Marker>{};
    final circles = <Circle>{};

    if (livePosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('courier_current_live'),
          position: livePosition,
          anchor: const Offset(0.5, 0.5),
          flat: true,
          infoWindow: const InfoWindow(title: 'Sua localizacao atual'),
          icon: _courierMapMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          rotation: _displayCourierBearing ?? 0,
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.my_location, color: AppColors.primaryRed),
                const SizedBox(width: 8),
                const Text(
                  'Mapa do estafeta',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loadCurrentLocation,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loadingLocation) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 10),
            ],
            if (!hasLivePosition)
              const Text(
                'Ative a localizacao para ver o mapa do estafeta em tempo real.',
                style: TextStyle(color: AppColors.neutralGray),
              )
            else ...[
              Text(
                addressLine,
                style: const TextStyle(color: AppColors.neutralGray),
              ),
              if (localityLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  localityLine,
                  style: const TextStyle(color: AppColors.neutralGray),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                isOnline ? 'Estas online' : 'Estas offline',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isOnline
                      ? AppColors.successGreen
                      : AppColors.neutralGray,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: mapHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: YangoMapWidget(
                          key: const ValueKey('courier_dashboard_live_map'),
                          initialCameraPosition: CameraPosition(
                            target: livePosition,
                            zoom: _courierMapZoom,
                            tilt: _courierMapTilt,
                          ),
                          markers: markers,
                          circles: circles,
                          myLocationEnabled: false,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          compassEnabled: false,
                          showCurrentLocationButton: true,
                          showFollowButton: true,
                          followEnabled: _followCourierMap,
                          eagerGestureHandling: true,
                          onCurrentLocationPressed: _loadCurrentLocation,
                          onFollowToggle: () async {
                            setState(
                              () => _followCourierMap = !_followCourierMap,
                            );
                            if (_followCourierMap) {
                              await _followCourierMapCamera();
                            }
                          },
                          onMapCreated: (controller) {
                            _courierMapController = controller;
                            _followCourierMapCamera();
                          },
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.10),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 10,
                                    color: isOnline
                                        ? AppColors.successGreen
                                        : AppColors.neutralGray,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isOnline ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: isOnline
                                          ? AppColors.successGreen
                                          : AppColors.neutralGray,
                                    ),
                                  ),
                                  if (_resolvingAddress) ...[
                                    const SizedBox(width: 8),
                                    const SizedBox(
                                      height: 14,
                                      width: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (_currentDelivery != null)
                              ActionChip(
                                avatar: const Icon(
                                  Icons.route_outlined,
                                  size: 18,
                                  color: Color(0xFF111B21),
                                ),
                                label: const Text('Abrir rota'),
                                onPressed: () => context.push(
                                  '/tracking/${_currentDelivery!.id}?viewer=courier',
                                ),
                                backgroundColor: Colors.white,
                                side: BorderSide.none,
                                elevation: 1,
                                shadowColor: Colors.black.withValues(
                                  alpha: 0.10,
                                ),
                                labelStyle: const TextStyle(
                                  color: Color(0xFF111B21),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLastCompletedDeliveryCard(Order order) {
    final completedAt = order.updatedAt ?? order.createdAt;
    return Card(
      color: AppColors.successGreen.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sua ultima entrega foi concluida',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successGreen,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Concluida',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Pedido #${order.id.substring(0, 8)}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Hora da entrega: ${_formatDate(completedAt)}',
              style: const TextStyle(color: Color(0xFF374151)),
            ),
            const SizedBox(height: 6),
            Text(
              'Entrega: ${LocationDisplay.displayAddress(address: order.deliveryAddress, fallback: "Destino do cliente confirmado no mapa")}',
              style: const TextStyle(color: Color(0xFF374151)),
            ),
            const SizedBox(height: 6),
            Text(
              'Valor: ${order.totalAmount.toStringAsFixed(0)} MZN',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OrderChatButton(
                  orderId: order.id,
                  onPressed: () => context.push('/chat/${order.id}'),
                  unreadCount: _unreadChatCountFor(order.id),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _selectedIndex = 1),
                  icon: const Icon(Icons.history),
                  label: const Text('Ver historico'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    final name = _nameController.text.trim().isEmpty
        ? 'Estafeta DeliGo'
        : _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final accountStatus = _courierSuspended
        ? 'Suspenso'
        : (kycStatus == 'approved' ? 'Verificado' : 'Em análise');
    final payout = _maskedCourierPhone(phone);

    return RefreshIndicator(
      onRefresh: _loadCourierData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCourierProfileSummary(name: name, accountStatus: accountStatus),
          const SizedBox(height: 14),
          _buildCourierProfileWallet(payout),
          const SizedBox(height: 14),
          _buildCourierProfileMenuSection(
            title: 'Ajuda',
            children: [
              _profileMenuItem(
                icon: Icons.support_agent_outlined,
                title: 'Central de ajuda',
                subtitle: 'Falar com a equipa DeliGo',
                onTap: () => context.push('/support'),
              ),
            ],
          ),
          _buildCourierProfileMenuSection(
            title: 'Legal',
            children: [
              _profileMenuItem(
                icon: Icons.description_outlined,
                title: 'Termos de uso',
                onTap: () => context.push('/terms'),
              ),
              _profileMenuItem(
                icon: Icons.privacy_tip_outlined,
                title: 'Política de privacidade',
                onTap: () => context.push('/privacy'),
              ),
              _profileMenuItem(
                icon: Icons.receipt_long_outlined,
                title: 'Pagamentos e reembolsos',
                onTap: () => context.push('/refund-policy'),
              ),
            ],
          ),
          _buildCourierProfileMenuSection(
            title: 'Conta',
            children: [
              _profileMenuItem(
                icon: Icons.delete_forever_outlined,
                title: 'Eliminar conta',
                subtitle: 'Solicitar eliminação permanente da conta',
                danger: true,
                onTap: _showCourierDeleteAccountDialog,
              ),
            ],
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Terminar sessão'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryRed,
              minimumSize: const Size.fromHeight(52),
              side: const BorderSide(color: AppColors.primaryRed),
            ),
          ),
          const SizedBox(height: 16),
          const InstitutionalFooter(),
        ],
      ),
    );
  }

  String _maskedCourierPhone(String rawPhone) {
    final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    final local = digits.startsWith('258') ? digits.substring(3) : digits;
    if (local.length < 6) return 'Associado ao seu número de cadastro';
    return 'M-Pesa • ${local.substring(0, 3)} *** ${local.substring(local.length - 3)}';
  }

  Future<void> _showCourierDeleteAccountDialog() async {
    final deletionService = AccountDeletionService();
    late final AccountDeletionPreview preview;
    try {
      preview = await deletionService.previewDeletion();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
      return;
    }
    if (!preview.canDelete) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            preview.message ?? 'Não é possível eliminar a conta agora.',
          ),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar conta'),
        content: Text(
          'Esta ação é permanente e remove o acesso à sua conta DeliGo. Deseja continuar?'
          '${preview.transferableAmount > 0 ? '\n\n${preview.confirmationDisclosure}' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final result = await deletionService.requestDeletion(
                  confirmationText: 'DELETE',
                );
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(result.message)));
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Não foi possível eliminar a conta agora: $error',
                    ),
                  ),
                );
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Widget _buildCourierProfileSummary({
    required String name,
    required String accountStatus,
  }) {
    return _premiumCourierCard(
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: AppColors.primaryRed.withValues(alpha: 0.10),
                backgroundImage: _avatarUrl?.trim().isNotEmpty == true
                    ? NetworkImage(_avatarUrl!)
                    : null,
                child: _avatarUrl?.trim().isNotEmpty == true
                    ? null
                    : const Icon(Icons.person_rounded, size: 42),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: IconButton.filled(
                  onPressed: _uploadingAvatar ? null : _changeAvatar,
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Estafeta DeliGo · ${isOnline ? '🟢 Disponível' : '⚪ Offline'}',
                  style: const TextStyle(
                    color: AppColors.neutralGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildHeaderBadge(
                      '★ ${_courierRating.toStringAsFixed(1)} · $_courierReviewCount avaliações',
                      const Color(0xFFF59E0B),
                    ),
                    _buildHeaderBadge(
                      '$_totalDeliveries entregas',
                      const Color(0xFF2563EB),
                    ),
                    _buildHeaderBadge(
                      'KYC ✓ $accountStatus',
                      AppColors.successGreen,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourierProfileWallet(String payout) {
    final canWithdraw = !_isTestWallet && _walletBalance > 0;
    return _premiumCourierCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: AppColors.successGreen,
              ),
              SizedBox(width: 8),
              Text(
                'Carteira',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Disponível para levantamento',
            style: TextStyle(color: AppColors.neutralGray),
          ),
          Text(
            '${_walletBalance.toStringAsFixed(2)} $_walletCurrency',
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(payout, style: const TextStyle(fontWeight: FontWeight.w800)),
          const Text(
            'Associado ao seu número de cadastro.',
            style: TextStyle(color: AppColors.neutralGray, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.push('/wallet?section=history'),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Ver extrato'),
              ),
              FilledButton.icon(
                onPressed: canWithdraw
                    ? () => context.push('/wallet?section=withdraw')
                    : null,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Levantar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCourierProfileAvailability() {
    return _premiumCourierCard(
      child: Row(
        children: [
          Icon(
            Icons.power_settings_new_rounded,
            color: isOnline ? AppColors.successGreen : AppColors.neutralGray,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Disponibilidade',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  isOnline
                      ? 'Online — A receber entregas'
                      : 'Offline — Não recebe entregas',
                  style: TextStyle(
                    color: isOnline
                        ? AppColors.successGreen
                        : AppColors.neutralGray,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isOnline,
            onChanged: _requestCourierOnlineChange,
            activeThumbColor: AppColors.successGreen,
          ),
        ],
      ),
    );
  }

  Widget _buildCourierProfileMenuSection({
    required String title,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: _premiumCourierCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _profileMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    bool danger = false,
    required VoidCallback onTap,
  }) {
    final color = danger ? AppColors.primaryRed : const Color(0xFF101828);
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w800, color: color),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
    );
  }

  Widget _profileStatusChip(String value) => Chip(
    label: Text(value),
    labelStyle: const TextStyle(
      fontWeight: FontWeight.w800,
      color: AppColors.successGreen,
    ),
    backgroundColor: AppColors.successGreen.withValues(alpha: 0.10),
    side: BorderSide.none,
  );

  void _showCourierInfoDialog(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _showCourierPersonalDataSheet() {
    final phone = _phoneController.text.trim();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dados pessoais',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Text(
                'Nome verificado: ${_nameController.text.trim()}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Text(
                'A identidade validada só pode ser corrigida pela Central DeliGo.',
                style: TextStyle(color: AppColors.neutralGray),
              ),
              const SizedBox(height: 12),
              Text(
                'Telefone principal: $phone',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Text(
                'A alteração exige confirmação por OTP no novo número.',
                style: TextStyle(color: AppColors.neutralGray),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _startCourierPhoneChange();
                },
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Alterar telefone com OTP'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _sendPasswordReset();
                },
                icon: const Icon(Icons.lock_reset_outlined),
                label: const Text('Alterar palavra-passe'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startCourierPhoneChange() async {
    final controller = TextEditingController();
    final newPhone = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo número de telefone'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: '+258 84XXXXXXX'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Enviar OTP'),
          ),
        ],
      ),
    );
    controller.dispose();
    final normalized = _normalizePhoneForStorage(newPhone ?? '');
    if (normalized == null) return;
    try {
      await supabase.auth.updateUser(UserAttributes(phone: normalized));
      if (!mounted) return;
      context.push('/phone-otp?phone=${Uri.encodeQueryComponent(normalized)}');
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  void _showCourierWorkZoneSheet() {
    final controller = TextEditingController(text: _workZoneController.text);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Zona de trabalho',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: _profileDecoration('Cidade ou zona operacional'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  setState(
                    () => _workZoneController.text = controller.text.trim(),
                  );
                  Navigator.pop(sheetContext);
                  await _saveCourierProfile();
                },
                child: const Text('Guardar zona'),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _openCourierHelpCenter() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text(
                'Ajuda e segurança',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('Falar com suporte'),
              onTap: () => Navigator.of(sheetContext).pop('support'),
            ),
            ListTile(
              leading: const Icon(Icons.report_problem_outlined),
              title: const Text('Reportar problema'),
              onTap: () => Navigator.of(sheetContext).pop('support'),
            ),
            ListTile(
              leading: const Icon(Icons.sos_outlined, color: Colors.red),
              title: const Text('Emergência / SOS'),
              onTap: () => Navigator.of(sheetContext).pop('sos'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'support') {
      context.push('/support');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enviar emergência?'),
        content: const Text(
          'Use esta opção apenas quando precisar de assistência urgente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar SOS'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _openCourierSos();
  }

  void _openCourierSos() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pedido de emergência enviado à Central.'),
        duration: Duration(milliseconds: 1200),
      ),
    );
    context.push('/support');
  }

  Widget _buildLegacyProfileTab() {
    final accountStatus = _courierSuspended
        ? 'Suspenso'
        : (kycStatus == 'approved' ? 'Ativo' : 'Em revisao');
    final courierName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Deligo Biker';
    final courierPhone = _phoneController.text.trim().isNotEmpty
        ? _phoneController.text.trim()
        : 'Sem telefone definido';
    final payoutContact = _phoneController.text.trim().isNotEmpty
        ? _displayPaymentContact(_phoneController.text.trim())
        : 'Sem contacto de levantamento';
    return RefreshIndicator(
      onRefresh: _loadCourierData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCourierProfileHeader(
            courierName: courierName,
            courierPhone: courierPhone,
            payoutContact: payoutContact,
            accountStatus: accountStatus,
          ),
          const SizedBox(height: 20),
          _buildProfileSection(
            title: 'Disponibilidade',
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOnline ? 'Disponivel' : 'Indisponivel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isOnline
                              ? AppColors.successGreen
                              : AppColors.alertRed,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isOnline
                            ? 'Voce pode receber e aceitar novas entregas.'
                            : 'Ative este botao quando quiser comecar a trabalhar.',
                        style: const TextStyle(color: AppColors.neutralGray),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isOnline,
                  onChanged: _requestCourierOnlineChange,
                  activeThumbColor: AppColors.successGreen,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildProfileSection(
            title: 'Informacoes pessoais',
            child: Column(
              children: [
                _buildProfileField(_nameController, 'Nome'),
                const SizedBox(height: 12),
                _buildProfileField(
                  _phoneController,
                  'Numero de telefone',
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
          _buildProfileSection(
            title: 'Pagamento',
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _preferredPaymentMethod,
                  decoration: _profileDecoration('Carteira de pagamento'),
                  items: const [
                    DropdownMenuItem(value: 'm-pesa', child: Text('M-Pesa')),
                    DropdownMenuItem(value: 'emola', child: Text('e-Mola')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _preferredPaymentMethod = value);
                  },
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: _profileDecoration('Numero para levantamento'),
                  child: Text(
                    _phoneController.text.trim().isNotEmpty
                        ? _displayPaymentContact(_phoneController.text.trim())
                        : 'Use o mesmo numero do cadastro',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'O numero de levantamento e sempre o mesmo numero com que o estafeta se cadastrou.',
                    style: TextStyle(
                      color: AppColors.neutralGray,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildProfileSection(
            title: 'Acoes rapidas',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TapScale(
                        child: ElevatedButton.icon(
                          onPressed: _savingProfile
                              ? null
                              : _saveCourierProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryRed,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            _savingProfile
                                ? 'A guardar...'
                                : 'Guardar alteracoes',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isTestWallet
                            ? null
                            : () => context.push('/wallet?section=withdraw'),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Levantar saldo'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isTestWallet
                        ? null
                        : () => context.push('/wallet?section=deposit'),
                    icon: const Icon(Icons.add_card_outlined),
                    label: const Text('Depositar'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Configuracoes'),
                  ),
                ),
              ],
            ),
          ),
          _buildProfileSection(
            title: 'Partilhar perfil',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Use um link publico para partilhar o seu perfil de estafeta fora da app.',
                  style: TextStyle(color: AppColors.neutralGray, height: 1.35),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Copiar link'),
                      onPressed: () {
                        final userId = supabase.auth.currentUser?.id;
                        if (userId == null) return;
                        _copyCourierShareLink(
                          _publicShareService.courierLink(userId),
                        );
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.chat, size: 18),
                      label: const Text('WhatsApp'),
                      onPressed: () => _shareCourierProfileTo('whatsapp'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.facebook, size: 18),
                      label: const Text('Facebook'),
                      onPressed: () => _shareCourierProfileTo('facebook'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('Instagram'),
                      onPressed: () => _shareCourierProfileTo('instagram'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildProfileSection(
            title: 'Zona de trabalho',
            child: _buildProfileField(_workZoneController, 'Cidade ou area'),
          ),
          _buildProfileSection(
            title: 'Preferencias e notificacoes',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativar notificacoes'),
                  value: _pushNotificationsEnabled,
                  onChanged: (value) =>
                      setState(() => _pushNotificationsEnabled = value),
                ),
                if (!_pushActive)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: _activatePush,
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('Ativar push no dispositivo'),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sons de pedidos'),
                  value: _orderSoundsEnabled,
                  onChanged: (value) =>
                      setState(() => _orderSoundsEnabled = value),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _languageCode,
                  decoration: _profileDecoration('Idioma'),
                  items: const [
                    DropdownMenuItem(value: 'pt', child: Text('Portugues')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _languageCode = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _voiceMode,
                  decoration: _profileDecoration('Voz do app'),
                  items: const [
                    DropdownMenuItem(
                      value: 'full',
                      child: Text('Voz completa'),
                    ),
                    DropdownMenuItem(
                      value: 'important_only',
                      child: Text('Apenas eventos importantes'),
                    ),
                    DropdownMenuItem(value: 'off', child: Text('Sem voz')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _voiceMode = value);
                  },
                ),
              ],
            ),
          ),
          _buildProfileSection(
            title: 'Seguranca',
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _sendPasswordReset,
                icon: const Icon(Icons.lock_reset),
                label: const Text('Alterar palavra-passe'),
              ),
            ),
          ),
          _buildProfileSection(
            title: 'Conta',
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => context.push('/profile?section=security'),
                icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                label: const Text('Eliminar conta'),
              ),
            ),
          ),
          _buildProfileSection(
            title: 'Informacao protegida',
            child: Column(
              children: [
                _buildReadonlyRow('Rating', _courierRating.toStringAsFixed(1)),
                _buildReadonlyRow(
                  'Numero de entregas',
                  _totalDeliveries.toString(),
                ),
                _buildReadonlyRow('Estado da conta', accountStatus),
                _buildReadonlyRow(
                  'Verificacao KYC',
                  kycStatus == 'approved'
                      ? 'Aprovado'
                      : (kycStatus ?? 'Pendente'),
                ),
                if ((_suspensionReason ?? '').trim().isNotEmpty)
                  _buildReadonlyRow('Motivo da suspensao', _suspensionReason!),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Documento de identificacao e verificacao ficam protegidos e so podem ser alterados com suporte.',
                    style: TextStyle(color: AppColors.neutralGray),
                  ),
                ),
              ],
            ),
          ),
          _buildProfileSection(
            title: 'Legal',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Termos de uso'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/terms'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Politica de privacidade'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/privacy'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Pagamentos e reembolsos'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/refund-policy'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: TapScale(
              child: FilledButton.icon(
                onPressed: _savingProfile ? null : _saveCourierProfile,
                icon: _savingProfile
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _savingProfile ? 'Salvando...' : 'Guardar alteracoes',
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildCourierProfileHeader({
    required String courierName,
    required String courierPhone,
    required String payoutContact,
    required String accountStatus,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: AppColors.primaryRed.withValues(alpha: 0.10),
                  backgroundImage:
                      _avatarUrl != null && _avatarUrl!.trim().isNotEmpty
                      ? NetworkImage(_avatarUrl!)
                      : null,
                  child: (_avatarUrl == null || _avatarUrl!.trim().isEmpty)
                      ? const Icon(
                          Icons.person,
                          size: 46,
                          color: AppColors.primaryRed,
                        )
                      : null,
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primaryRed,
                    child: IconButton(
                      icon: const Icon(
                        Icons.camera_alt,
                        size: 18,
                        color: Colors.white,
                      ),
                      onPressed: _uploadingAvatar ? null : _changeAvatar,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              courierName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              courierPhone,
              style: const TextStyle(color: AppColors.neutralGray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Wallet: $payoutContact',
              style: const TextStyle(color: AppColors.neutralGray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildHeaderBadge(
                  isOnline ? 'Disponivel' : 'Indisponivel',
                  isOnline ? AppColors.successGreen : AppColors.alertRed,
                ),
                _buildHeaderBadge(
                  'Saldo: $_walletCurrency ${_walletBalance.toStringAsFixed(2)}',
                  AppColors.primaryRed,
                ),
                _buildHeaderBadge(accountStatus, Colors.indigo),
              ],
            ),
            const SizedBox(height: 10),
            if (_avatarUrl != null && _avatarUrl!.trim().isNotEmpty)
              TextButton.icon(
                onPressed: _uploadingAvatar ? null : _removeAvatar,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remover foto'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildProfileSection({required String title, required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildProfileField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _profileDecoration(
        label,
      ).copyWith(suffixIcon: const Icon(Icons.edit_outlined)),
    );
  }

  InputDecoration _profileDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _buildReadonlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.neutralGray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
