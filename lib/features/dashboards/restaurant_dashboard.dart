import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme/app_colors.dart';
import '../../services/notification_router_service.dart';
import '../../services/app_voice_service.dart';
import '../../services/order_service.dart';
import 'package:deligo_app/services/restaurant_service.dart';
import '../../services/restaurant_share_service.dart';
import '../../services/public_share_service.dart';
import '../../services/server_clock_service.dart';
import '../../services/push_notification_service.dart';
import '../../services/sound_controller.dart';
import 'package:deligo_app/services/welcome_voice_service.dart';
import '../../services/weather_service.dart';
import '../../shared/models/menu_item.dart';
import '../../shared/models/order.dart';
import '../../shared/models/restaurant.dart';
import '../../shared/location/location_picker_page.dart';
import '../../shared/widgets/order_chat_button.dart';
import '../../shared/widgets/support_headset_button.dart';
import '../../shared/widgets/institutional_footer.dart';
import '../../shared/widgets/tap_scale.dart';
import '../../shared/utils/location_display.dart';
import '../../shared/utils/deligo_viewport.dart';
import '../../shared/utils/mozambique_time.dart';
import '../../shared/utils/chat_notification_utils.dart';
import '../../shared/utils/notification_type_utils.dart';
import '../categories/deligo_food_categories.dart';
import '../marketing/restaurant_marketing_page.dart';

class RestaurantDashboard extends StatefulWidget {
  final String? initialTab;
  final String? initialOrderId;

  const RestaurantDashboard({super.key, this.initialTab, this.initialOrderId});

  @override
  State<RestaurantDashboard> createState() => _RestaurantDashboardState();
}

class _LiveClockText extends StatefulWidget {
  const _LiveClockText({required this.format});

  final String Function(DateTime value) format;

  @override
  State<_LiveClockText> createState() => _LiveClockTextState();
}

class _LiveClockTextState extends State<_LiveClockText> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = ServerClockService.instance.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = ServerClockService.instance.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    widget.format(_now),
    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
  );
}

class _RestaurantCountdownPill extends StatefulWidget {
  const _RestaurantCountdownPill({required this.deadline});

  final DateTime deadline;

  @override
  State<_RestaurantCountdownPill> createState() =>
      _RestaurantCountdownPillState();
}

class _RestaurantCountdownPillState extends State<_RestaurantCountdownPill> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = ServerClockService.instance.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = ServerClockService.instance.now());
    });
  }

  @override
  void didUpdateWidget(covariant _RestaurantCountdownPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) {
      setState(() => _now = ServerClockService.instance.now());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.deadline.difference(_now);
    final safeRemaining = remaining.isNegative ? Duration.zero : remaining;
    final minutes = safeRemaining.inMinutes;
    final seconds = safeRemaining.inSeconds % 60;
    final clock =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    final color = safeRemaining.inSeconds <= 60 ? Colors.red : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        'Confirmar em $clock',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _DishSalesSnapshot {
  final String name;
  final int quantity;
  final double revenue;

  const _DishSalesSnapshot({
    required this.name,
    required this.quantity,
    required this.revenue,
  });
}

class _MerchantBrandMark extends StatelessWidget {
  const _MerchantBrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryRed,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Icon(
        Icons.storefront_rounded,
        color: Colors.white,
        size: 19,
      ),
    );
  }
}

class _MerchantTopAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final int count;
  final VoidCallback? onTap;

  const _MerchantTopAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.count = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onTap,
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFFE3E1DC)),
              ),
              child: Icon(
                icon,
                size: 21,
                color: onTap == null
                    ? const Color(0xFFAAAAAA)
                    : const Color(0xFF333333),
              ),
            ),
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryRed,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
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
}

class _MerchantMapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final routePaint = Paint()
      ..color = AppColors.primaryRed.withValues(alpha: 0.55)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var x = 0.0; x < size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x + 28, size.height), gridPaint);
    }
    for (var y = 14.0; y < size.height; y += 38) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 20), gridPaint);
    }

    final path = Path()
      ..moveTo(size.width * 0.16, size.height * 0.68)
      ..cubicTo(
        size.width * 0.32,
        size.height * 0.42,
        size.width * 0.52,
        size.height * 0.62,
        size.width * 0.68,
        size.height * 0.32,
      )
      ..cubicTo(
        size.width * 0.76,
        size.height * 0.18,
        size.width * 0.86,
        size.height * 0.26,
        size.width * 0.92,
        size.height * 0.18,
      );
    canvas.drawPath(path, routePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RestaurantDashboardState extends State<RestaurantDashboard>
    with WidgetsBindingObserver {
  static const Duration _popupDuration = Duration(milliseconds: 1000);

  final _supabase = Supabase.instance.client;
  final _restaurantService = RestaurantService();
  final _restaurantShareService = RestaurantShareService();
  final PublicShareService _publicShareService = PublicShareService.instance;
  final _orderService = OrderService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _loading = true;
  bool _isSubmitting = false;
  int _tab = 0;
  String _orderFilter = 'all';
  static const _mobileNavigationTabs = <int>[0, 1, 2, 4, 5];
  String _stockFilter = 'available';
  String _revenueRange = 'today';
  String _dishSalesRange = '24h';
  List<_DishSalesSnapshot> _dishSales24h = const [];
  List<_DishSalesSnapshot> _dishSales7d = const [];
  List<_DishSalesSnapshot> _dishSales30d = const [];
  String? _restaurantId;
  String _restaurantName = 'Restaurante';
  String _restaurantPhone = '';
  String _restaurantAddress = '';
  String _restaurantImageUrl = '';
  String _restaurantCategory = 'Restaurante';
  String _restaurantNeighborhood = '';
  String _restaurantCity = '';
  String _restaurantDescription = '';
  String _restaurantLandmarkReference = '';
  double? _restaurantLatitude;
  double? _restaurantLongitude;
  String _restaurantPriceRange = '\$\$';
  String _restaurantPaymentWalletNumber = '';
  int _restaurantDeliveryTime = 25;
  bool _isOpen = true;
  double _walletBalance = 0;
  List<Map<String, dynamic>> _walletMovements = const [];
  Map<String, dynamic> _shareStats = const {};
  List<Order> _orders = const [];
  List<MenuItem> _menuItems = const [];
  List<Map<String, dynamic>> _reviews = const [];
  List<Map<String, dynamic>> _restaurantNotifications = const [];
  List<Map<String, dynamic>> _dailyCombos = const [];
  final List<Map<String, dynamic>> _liveEvents = [];
  final Set<String> _autoReadyTriggeredOrderIds = {};
  final Set<String> _timedOutHiddenOrderIds = {};
  final Set<String> _archivedPendingOrderIds = {};
  final Set<String> _shownRestaurantLifecyclePopupKeys = {};
  final Map<String, List<OrderItem>> _orderItemsCache = {};
  final Map<String, Future<List<OrderItem>>> _orderItemsFlights = {};
  final Map<String, Future<void>> _orderRefreshFlights = {};
  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _notificationsChannel;
  RealtimeChannel? _catalogChannel;
  RealtimeChannel? _restaurantChannel;
  RealtimeChannel? _walletChannel;
  RealtimeChannel? _reviewsChannel;
  RealtimeChannel? _shareChannel;
  bool _pushActive = false;
  Timer? _ordersRefreshDebounce;
  Timer? _catalogRefreshDebounce;
  Timer? _snapshotRefreshDebounce;
  Timer? _shareStatsRefreshDebounce;
  Timer? _expiryTimer;
  Future<void>? _ordersAndBalanceRefreshInFlight;
  Future<void>? _realtimeSubscriptionFlight;
  String? _realtimeSubscriptionFlightKey;
  String? _pendingRealtimeRestaurantId;
  String? _pendingRealtimeUserId;
  int _initialLoadVersion = 0;
  int _ordersLoadVersion = 0;
  int _catalogLoadVersion = 0;
  int _shareStatsLoadVersion = 0;
  WeatherSnapshot? _weather;
  bool _openedInitialOrder = false;
  DateTime? _lastExpiredCountdownRefreshAt;
  final Map<String, DateTime> _restaurantIncomingEventSeen =
      <String, DateTime>{};

  DateTime get _serverNow => ServerClockService.instance.now();

  DateTime get _serverNowLocal => MozambiqueTime.from(_serverNow);

  String get _serverNowIsoUtc => ServerClockService.instance.nowIso8601Utc();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyInitialRouteState();
    unawaited(_syncServerClock(force: true));
    // Expiry housekeeping is not a visual clock. It runs less frequently and
    // only calls setState when an order actually expires.
    _expiryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _hideTimedOutOrdersIfNeeded();
      _maybeRefreshExpiredOrderCountdowns();
    });
    _load();
  }

  @override
  void didUpdateWidget(covariant RestaurantDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab ||
        oldWidget.initialOrderId != widget.initialOrderId) {
      _openedInitialOrder = false;
      _applyInitialRouteState();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialOrderFromRoute();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ordersRefreshDebounce?.cancel();
    _catalogRefreshDebounce?.cancel();
    _snapshotRefreshDebounce?.cancel();
    _shareStatsRefreshDebounce?.cancel();
    _expiryTimer?.cancel();
    _ordersChannel?.unsubscribe();
    _notificationsChannel?.unsubscribe();
    _catalogChannel?.unsubscribe();
    _restaurantChannel?.unsubscribe();
    _walletChannel?.unsubscribe();
    _reviewsChannel?.unsubscribe();
    _shareChannel?.unsubscribe();
    _restaurantIncomingEventSeen.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(_refreshRestaurantDashboardAfterResume());
  }

  Future<void> _refreshRestaurantDashboardAfterResume() async {
    await _syncServerClock(force: true, refreshUi: false);
    if (_restaurantId == null || _restaurantId!.isEmpty) {
      await _load(showLoading: false);
      return;
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null && userId.isNotEmpty) {
      unawaited(_refreshRestaurantNotifications(userId));
    }
    await _refreshOrdersAndBalance();
    final requestedOrderId = widget.initialOrderId?.trim() ?? '';
    if (requestedOrderId.isNotEmpty) {
      _openedInitialOrder = false;
      unawaited(_refreshRealtimeOrder(requestedOrderId));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialOrderFromRoute();
      });
    }
  }

  Future<void> _refreshDashboardManually() async {
    final restaurantId = _restaurantId;
    final userId = _supabase.auth.currentUser?.id;
    if (restaurantId == null || restaurantId.isEmpty || userId == null) {
      await _load(showLoading: false);
      return;
    }

    await Future.wait([
      _refreshRestaurantSnapshot(),
      _refreshOrdersAndBalance(),
      _refreshMenuReviewsAndCombos(),
      _refreshRestaurantNotifications(userId),
      _refreshShareStats(),
      _refreshWalletMovementsAndSales(restaurantId),
    ]);
  }

  Future<void> _syncServerClock({
    bool force = false,
    bool refreshUi = true,
  }) async {
    await ServerClockService.instance.sync(force: force);
    if (!mounted || !refreshUi) return;
    // Visual clocks/countdowns own their own refresh scope. This sync only
    // refreshes the server-time source used by business logic.
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
    }
  }

  void _applyInitialRouteState() {
    final requestedOrderId = widget.initialOrderId?.trim() ?? '';
    if (requestedOrderId.isNotEmpty) {
      _tab = 1;
      return;
    }

    switch (widget.initialTab?.trim().toLowerCase()) {
      case 'orders':
      case 'pedidos':
        _tab = 1;
        break;
      case 'menu':
      case 'pratos':
        _tab = 2;
        break;
      case 'wallet':
        _tab = 3;
        break;
      case 'analytics':
      case 'receitas':
        _tab = 4;
        break;
      case 'profile':
      case 'perfil':
        _tab = 5;
        break;
      case 'marketing':
      case 'eventos':
      case 'events':
        _tab = 6;
        break;
      default:
        break;
    }
  }

  void _openInitialOrderFromRoute({int attempt = 0}) {
    if (_openedInitialOrder || !mounted) return;
    final requestedOrderId = widget.initialOrderId?.trim() ?? '';
    if (requestedOrderId.isEmpty) return;

    final order = _orders.cast<Order?>().firstWhere(
      (candidate) => candidate?.id == requestedOrderId,
      orElse: () => null,
    );
    if (order == null) {
      unawaited(_refreshRealtimeOrder(requestedOrderId, attempt: attempt));
      if (attempt < 5) {
        final delay = Duration(milliseconds: 350 * (attempt + 1));
        Future<void>.delayed(delay, () {
          if (!mounted || _openedInitialOrder) return;
          _openInitialOrderFromRoute(attempt: attempt + 1);
        });
      }
      return;
    }

    _openedInitialOrder = true;
    if (_tab != 1) {
      setState(() => _tab = 1);
    }
    _showOrderDetails(order);
  }

  Future<List<Order>> _fetchOrders(String restaurantId) async {
    // Maintenance is best effort and must not delay the first dashboard paint.
    unawaited(
      Future.wait([
        _supabase.rpc('process_preparing_orders'),
        _supabase.rpc('process_restaurant_confirmation_timeouts'),
        _supabase.rpc('process_stuck_orders'),
      ]).catchError((_) => <dynamic>[]),
    );

    final response = await _supabase
        .from('orders')
        .select(
          '*, payment_status, restaurants(name,address,neighborhood,city,latitude,longitude,estimated_delivery_time), payment_splits(restaurant_confirmed_at,status)',
        )
        .eq('restaurant_id', restaurantId)
        .order('created_at', ascending: false);
    final rows = (response as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();

    await _reconcileOrderPaymentStatuses(rows);

    return rows.map(Order.fromMap).toList();
  }

  Future<void> _reconcileOrderPaymentStatuses(
    List<Map<String, dynamic>> rows,
  ) async {
    final orderIds = rows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    if (orderIds.isEmpty) return;

    try {
      final payments = await _supabase
          .from('payments')
          .select('order_id,status,updated_at')
          .inFilter('order_id', orderIds)
          .order('updated_at', ascending: false);

      final paymentStatusByOrder = <String, String>{};
      for (final raw in (payments as List)) {
        final payment = Map<String, dynamic>.from(raw as Map);
        final orderId = payment['order_id']?.toString();
        final status = payment['status']?.toString().trim().toLowerCase();
        if (orderId == null ||
            orderId.isEmpty ||
            status == null ||
            status.isEmpty ||
            paymentStatusByOrder.containsKey(orderId)) {
          continue;
        }
        paymentStatusByOrder[orderId] = status;
      }

      for (final row in rows) {
        final orderId = row['id']?.toString();
        if (orderId == null || orderId.isEmpty) continue;
        final paymentStatus = paymentStatusByOrder[orderId];
        if (paymentStatus == 'settled') {
          row['payment_status'] = 'settled';
        } else if (paymentStatus == 'completed' ||
            paymentStatus == 'paid' ||
            paymentStatus == 'authorized') {
          row['payment_status'] = 'completed';
        }
      }
    } catch (error) {
      debugPrint(
        'RestaurantDashboard: erro ao reconciliar payment_status dos pedidos: $error',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRestaurantNotifications(
    String userId,
  ) async {
    final response = await _supabase
        .from('push_notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(30);
    final seen = <String>{};
    return (response as List).cast<Map<String, dynamic>>().where((
      notification,
    ) {
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
    }).toList();
  }

  Future<Order?> _fetchOrderSnapshot(String orderId) async {
    final response = await _supabase
        .from('orders')
        .select(
          '*, payment_status, restaurants(name,address,neighborhood,city,latitude,longitude,estimated_delivery_time), payment_splits(restaurant_confirmed_at,status)',
        )
        .eq('id', orderId)
        .maybeSingle();
    if (response == null) return null;

    final row = Map<String, dynamic>.from(response as Map);
    await _reconcileOrderPaymentStatuses([row]);
    return Order.fromMap(row);
  }

  void _upsertRealtimeOrderLocally(Map<String, dynamic> record) {
    if (!mounted || record.isEmpty) return;
    final orderId = record['id']?.toString().trim() ?? '';
    if (orderId.isEmpty) return;

    Map<String, dynamic> mergedRecord = Map<String, dynamic>.from(record);
    for (final existing in _orders) {
      if (existing.id != orderId) continue;
      mergedRecord = {...existing.toMap(), ...record};
      break;
    }

    final nextOrder = Order.fromMap(mergedRecord);
    setState(() {
      final nextOrders =
          _orders.where((candidate) => candidate.id != orderId).toList()
            ..add(nextOrder)
            ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
      _orders = nextOrders;
    });
    _focusAwaitingOrdersIfNeeded(_orders);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openInitialOrderFromRoute();
    });
  }

  void _removeRealtimeOrderLocally(String orderId) {
    final normalizedOrderId = orderId.trim();
    if (!mounted || normalizedOrderId.isEmpty) return;
    _orderItemsCache.remove(normalizedOrderId);
    _orderItemsFlights.remove(normalizedOrderId);
    setState(() {
      _orders = _orders
          .where((candidate) => candidate.id != normalizedOrderId)
          .toList();
    });
  }

  Future<void> _refreshRealtimeOrder(String orderId, {int attempt = 0}) {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return Future<void>.value();

    final existingFlight = _orderRefreshFlights[normalizedOrderId];
    // Orders Realtime and push_notifications can describe the same logical
    // order event. One in-flight snapshot is enough; do not queue a second
    // refresh when the other channel arrives milliseconds later.
    if (existingFlight != null) return existingFlight;

    final refresh = _refreshRealtimeOrderInternal(
      normalizedOrderId,
      attempt: attempt,
    );
    _orderRefreshFlights[normalizedOrderId] = refresh;
    refresh.then(
      (_) => _finishOrderRefreshFlight(normalizedOrderId, refresh),
      onError: (Object error, StackTrace stackTrace) {
        _finishOrderRefreshFlight(normalizedOrderId, refresh);
      },
    );
    return refresh;
  }

  Future<void> _refreshRealtimeOrderInternal(
    String orderId, {
    required int attempt,
  }) async {
    Order? order;
    try {
      order = await _fetchOrderSnapshot(orderId);
    } catch (_) {
      // A specific snapshot failed; the debounced full refresh remains the
      // safe fallback for list and balance consistency.
      _scheduleOrdersRefresh();
      return;
    }
    if (!mounted) return;

    if (order == null) {
      _scheduleOrdersRefresh();
      if (attempt < 3) {
        final delay = Duration(milliseconds: 450 * (attempt + 1));
        await Future<void>.delayed(delay);
        if (mounted) {
          await _refreshRealtimeOrder(orderId, attempt: attempt + 1);
        }
      }
      return;
    }

    _upsertRealtimeOrderLocally(order.toMap());
  }

  void _finishOrderRefreshFlight(String orderId, Future<void> refresh) {
    if (!identical(_orderRefreshFlights[orderId], refresh)) return;
    _orderRefreshFlights.remove(orderId);
  }

  void _applyRestaurantSnapshot(Map<String, dynamic> restaurant) {
    _restaurantId = restaurant['id']?.toString();
    _restaurantName = restaurant['name']?.toString() ?? 'Deligo Restaurante';
    _restaurantPhone = restaurant['phone']?.toString() ?? '';
    _restaurantAddress = restaurant['address']?.toString() ?? '';
    _restaurantImageUrl = restaurant['image_url']?.toString() ?? '';
    _restaurantCategory =
        restaurant['category']?.toString().trim().isNotEmpty == true
        ? restaurant['category'].toString().trim()
        : 'Restaurante';
    _restaurantNeighborhood = restaurant['neighborhood']?.toString() ?? '';
    _restaurantCity = restaurant['city']?.toString() ?? '';
    _restaurantDescription = restaurant['description']?.toString() ?? '';
    _restaurantLandmarkReference =
        restaurant['landmark_reference']?.toString() ?? '';
    _restaurantLatitude = (restaurant['latitude'] as num?)?.toDouble();
    _restaurantLongitude = (restaurant['longitude'] as num?)?.toDouble();
    _restaurantPriceRange =
        restaurant['price_range']?.toString().trim().isNotEmpty == true
        ? restaurant['price_range'].toString().trim()
        : '\$\$';
    _restaurantPaymentWalletNumber =
        restaurant['payment_wallet_number']?.toString() ?? _restaurantPhone;
    _restaurantDeliveryTime =
        (restaurant['estimated_delivery_time'] as num?)?.toInt() ?? 25;
    _isOpen = restaurant['is_open'] != false;
  }

  Future<void> _load({bool showLoading = true}) async {
    unawaited(_syncServerClock(force: showLoading, refreshUi: false));
    final loadVersion = ++_initialLoadVersion;
    if (showLoading && mounted) {
      setState(() => _loading = true);
    }
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }
    final initialData = await Future.wait<dynamic>([
      _supabase
          .from('profiles')
          .select('settings, fcm_token')
          .eq('id', user.id)
          .maybeSingle(),
      _restaurantService.getRestaurantByOwnerId(user.id),
    ]);
    final profile = initialData[0] as Map<String, dynamic>?;
    final restaurant = initialData[1] as Map<String, dynamic>?;
    final settings =
        (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};

    if (restaurant == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _applyRestaurantSnapshot(restaurant);

    unawaited(
      WelcomeVoiceService.instance.greetOnce(
        userId: user.id,
        name: _restaurantName,
        role: 'restaurant',
        gender: 'masculino',
        languageCode: settings['language']?.toString(),
        voiceMode: settings['voice_mode']?.toString(),
      ),
    );

    final pushTokenFuture = kIsWeb
        ? Future<String?>.value(null)
        : PushNotificationService().registerFcmToken();

    final restaurantId = _restaurantId;
    if (restaurantId != null && restaurantId.isNotEmpty) {
      unawaited(
        _configureRealtimeSubscriptions(
          restaurantId: restaurantId,
          userId: user.id,
        ),
      );
      final results = await Future.wait<dynamic>([
        _restaurantService.getRestaurantBalance(restaurantId),
        _loadWalletMovements(restaurantId),
        _restaurantService.getAllMenuItems(restaurantId),
        _restaurantService.getRestaurantMenuItemReviewInsights(restaurantId),
        _restaurantService.getRestaurantDailyCombos(restaurantId),
        _restaurantShareService.getRestaurantShareStats(restaurantId),
        _fetchRestaurantNotifications(user.id),
        _fetchOrders(restaurantId),
        _loadDishSales(restaurantId),
        pushTokenFuture,
      ]);

      if (!mounted || loadVersion != _initialLoadVersion) return;
      setState(() {
        _walletBalance = (results[0] as num?)?.toDouble() ?? 0;
        _walletMovements = (results[1] as List).cast<Map<String, dynamic>>();
        _menuItems = (results[2] as List).cast<MenuItem>();
        _reviews = (results[3] as List).cast<Map<String, dynamic>>();
        _dailyCombos = (results[4] as List).cast<Map<String, dynamic>>();
        _shareStats = (results[5] as Map?)?.cast<String, dynamic>() ?? {};
        _restaurantNotifications = (results[6] as List)
            .cast<Map<String, dynamic>>();
        _orders = (results[7] as List).cast<Order>();
        _pushActive =
            (results[9] as String?)?.isNotEmpty == true ||
            (profile?['fcm_token'] as String?)?.isNotEmpty == true;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialOrderFromRoute();
      });
      await _loadWeather();
      return;
    }

    if (mounted && loadVersion == _initialLoadVersion) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadWeather() async {
    final weather = await WeatherService.instance.fetchWeather(
      latitude: _restaurantLatitude,
      longitude: _restaurantLongitude,
      city: _restaurantCity.isNotEmpty
          ? _restaurantCity
          : _restaurantNeighborhood,
    );
    if (!mounted) return;
    setState(() => _weather = weather);
  }

  Future<List<Map<String, dynamic>>> _loadWalletMovements(
    String restaurantId,
  ) async {
    try {
      final restaurant = await _supabase
          .from('restaurants')
          .select('owner_id')
          .eq('id', restaurantId)
          .maybeSingle();
      final ownerId = restaurant?['owner_id']?.toString();
      if (ownerId == null || ownerId.isEmpty) return const [];
      final wallets = await _supabase
          .from('wallets')
          .select('id')
          .eq('user_id', ownerId)
          .order('updated_at', ascending: false)
          .limit(1);
      if (wallets.isEmpty) return const [];
      final walletId = wallets.first['id']?.toString();
      if (walletId == null || walletId.isEmpty) return const [];
      final rows = await _supabase
          .from('wallet_ledger')
          .select(
            'id,direction,entry_type,amount,created_at,reference_key,metadata',
          )
          .eq('wallet_id', walletId)
          .order('created_at', ascending: false)
          .limit(5);
      return (rows as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (error) {
      debugPrint('RestaurantDashboard wallet movements: $error');
      return const [];
    }
  }

  Future<List<OrderItem>> _loadOrderItemsFor(String orderId) async {
    final normalizedOrderId = orderId.trim();
    final cached = _orderItemsCache[normalizedOrderId];
    if (cached != null) return cached;
    final inFlight = _orderItemsFlights[normalizedOrderId];
    if (inFlight != null) return inFlight;

    final future = _orderService.getOrderItems(normalizedOrderId);
    _orderItemsFlights[normalizedOrderId] = future;
    try {
      final items = await future;
      if (items.isNotEmpty) {
        _orderItemsCache[normalizedOrderId] = items;
      }
      return items;
    } finally {
      if (identical(_orderItemsFlights[normalizedOrderId], future)) {
        _orderItemsFlights.remove(normalizedOrderId);
      }
    }
  }

  Future<void> _loadDishSales(String restaurantId) async {
    final since = _serverNowLocal.subtract(const Duration(days: 30));
    try {
      final response = await _supabase
          .from('order_items')
          .select(
            'quantity, subtotal, menu_items(id,name), orders(created_at,status,restaurant_id)',
          )
          .eq('orders.restaurant_id', restaurantId)
          .inFilter('orders.status', [
            'delivered',
            'completed',
            'auto_completed',
          ])
          .gte('orders.created_at', since.toIso8601String());

      final rows = (response as List).cast<Map<String, dynamic>>();
      final now = _serverNowLocal;
      final bucket24h = now.subtract(const Duration(hours: 24));
      final bucket7d = now.subtract(const Duration(days: 7));

      List<_DishSalesSnapshot> aggregate(DateTime from) {
        final map = <String, _DishSalesSnapshot>{};
        for (final row in rows) {
          final order = (row['orders'] as Map?)?.cast<String, dynamic>();
          final createdAtRaw = order?['created_at']?.toString();
          if (createdAtRaw == null) continue;
          final createdAt = DateTime.tryParse(createdAtRaw)?.toLocal();
          if (createdAt == null || createdAt.isBefore(from)) continue;

          final menu = (row['menu_items'] as Map?)?.cast<String, dynamic>();
          final name = menu?['name']?.toString() ?? 'Prato';
          final key = menu?['id']?.toString() ?? name;
          final qty = (row['quantity'] as num?)?.toInt() ?? 0;
          final subtotal = (row['subtotal'] as num?)?.toDouble() ?? 0.0;
          final current = map[key];
          if (current == null) {
            map[key] = _DishSalesSnapshot(
              name: name,
              quantity: qty,
              revenue: subtotal,
            );
          } else {
            map[key] = _DishSalesSnapshot(
              name: current.name,
              quantity: current.quantity + qty,
              revenue: current.revenue + subtotal,
            );
          }
        }
        final list = map.values.toList()
          ..sort((a, b) => b.revenue.compareTo(a.revenue));
        return list.take(8).toList();
      }

      if (!mounted) return;
      setState(() {
        _dishSales24h = aggregate(bucket24h);
        _dishSales7d = aggregate(bucket7d);
        _dishSales30d = aggregate(since);
      });
    } catch (e) {
      debugPrint('Erro ao carregar vendas por prato: $e');
    }
  }

  String _formatLiveClock(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  Widget _buildDashboardClimateHeader() {
    final locationName =
        (_weather?.cityName ?? _restaurantCity).trim().isNotEmpty
        ? (_weather?.cityName ?? _restaurantCity)
        : (_restaurantNeighborhood.isNotEmpty
              ? _restaurantNeighborhood
              : 'Sua zona');
    final weatherLine = _weather != null
        ? '$locationName - ${_weather!.temperatureC.toStringAsFixed(0)}C - ${_weather!.condition}'
        : (_restaurantAddress.isNotEmpty
              ? _restaurantAddress
              : 'Condicoes do dia indisponiveis');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17203B), Color(0xFF11182B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tempo e hora do dia',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(weatherLine, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _dashboardHeaderLiveClockPill(),
              if (_weather != null)
                _dashboardHeaderPill(
                  Icons.thermostat_rounded,
                  '${_weather!.temperatureC.toStringAsFixed(0)}C',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dashboardHeaderPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardHeaderLiveClockPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          _LiveClockText(format: _formatLiveClock),
        ],
      ),
    );
  }

  Future<void> _refreshOrdersAndBalance() {
    final inFlight = _ordersAndBalanceRefreshInFlight;
    if (inFlight != null) return inFlight;

    final refresh = _refreshOrdersAndBalanceInternal();
    _ordersAndBalanceRefreshInFlight = refresh;
    refresh.then(
      (_) {
        if (identical(_ordersAndBalanceRefreshInFlight, refresh)) {
          _ordersAndBalanceRefreshInFlight = null;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_ordersAndBalanceRefreshInFlight, refresh)) {
          _ordersAndBalanceRefreshInFlight = null;
        }
      },
    );
    return refresh;
  }

  Future<void> _refreshOrdersAndBalanceInternal() async {
    final restaurantId = _restaurantId;
    if (restaurantId == null || restaurantId.isEmpty) return;
    final loadVersion = ++_ordersLoadVersion;
    final previousOrders = List<Order>.from(_orders);
    final results = await Future.wait<dynamic>([
      _fetchOrders(restaurantId),
      _restaurantService.getRestaurantBalance(restaurantId),
    ]);
    if (!mounted || loadVersion != _ordersLoadVersion) return;
    final nextOrders = (results[0] as List).cast<Order>();
    setState(() {
      _orders = nextOrders;
      _archivedPendingOrderIds.removeWhere((id) {
        return !nextOrders.any(
          (order) => order.id == id && _isAwaitingRestaurantConfirmation(order),
        );
      });
      _walletBalance = (results[1] as num?)?.toDouble() ?? _walletBalance;
    });
    _focusAwaitingOrdersIfNeeded(nextOrders);
    _applyRestaurantOrderUpdates(previousOrders, nextOrders);
  }

  void _focusAwaitingOrdersIfNeeded(List<Order> orders) {
    final hasAwaiting = orders.any(_isAwaitingRestaurantConfirmation);
    if (!hasAwaiting || !mounted) return;
    if (_tab == 1 && (_orderFilter == 'paid' || _orderFilter == 'all')) {
      return;
    }
    setState(() {
      _tab = 1;
      _orderFilter = 'paid';
    });
  }

  Future<void> _refreshRestaurantNotifications(String userId) async {
    try {
      final notifications = await _fetchRestaurantNotifications(userId);
      if (!mounted) return;
      setState(() => _restaurantNotifications = notifications);
    } catch (_) {
      // Resume refresh is best effort; orders remain the priority.
    }
  }

  Future<void> _refreshWalletMovementsAndSales(String restaurantId) async {
    final movements = await _loadWalletMovements(restaurantId);
    if (mounted) {
      setState(() => _walletMovements = movements);
    }
    await _loadDishSales(restaurantId);
  }

  Future<void> _refreshMenuReviewsAndCombos() async {
    final restaurantId = _restaurantId;
    if (restaurantId == null || restaurantId.isEmpty) return;
    final loadVersion = ++_catalogLoadVersion;
    final results = await Future.wait<dynamic>([
      _restaurantService.getAllMenuItems(restaurantId),
      _restaurantService.getRestaurantMenuItemReviewInsights(restaurantId),
      _restaurantService.getRestaurantDailyCombos(restaurantId),
    ]);
    if (!mounted || loadVersion != _catalogLoadVersion) return;
    setState(() {
      _menuItems = (results[0] as List).cast<MenuItem>();
      _reviews = (results[1] as List).cast<Map<String, dynamic>>();
      _dailyCombos = (results[2] as List).cast<Map<String, dynamic>>();
    });
  }

  Future<void> _refreshRestaurantSnapshot() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final restaurant = await _restaurantService.getRestaurantByOwnerId(userId);
    if (restaurant == null || !mounted) return;
    setState(() => _applyRestaurantSnapshot(restaurant));
    await _loadWeather();
  }

  Future<void> _refreshShareStats() async {
    final restaurantId = _restaurantId;
    if (restaurantId == null || restaurantId.isEmpty) return;
    final loadVersion = ++_shareStatsLoadVersion;
    final stats = await _restaurantShareService.getRestaurantShareStats(
      restaurantId,
    );
    if (!mounted || loadVersion != _shareStatsLoadVersion) return;
    setState(() => _shareStats = stats);
  }

  void _scheduleOrdersRefresh() {
    _ordersRefreshDebounce?.cancel();
    _ordersRefreshDebounce = Timer(const Duration(milliseconds: 120), () {
      _refreshOrdersAndBalance();
    });
  }

  void _scheduleCatalogRefresh() {
    _catalogRefreshDebounce?.cancel();
    _catalogRefreshDebounce = Timer(const Duration(milliseconds: 500), () {
      _refreshMenuReviewsAndCombos();
    });
  }

  void _scheduleRestaurantSnapshotRefresh() {
    _snapshotRefreshDebounce?.cancel();
    _snapshotRefreshDebounce = Timer(const Duration(milliseconds: 500), () {
      _refreshRestaurantSnapshot();
    });
  }

  void _scheduleShareStatsRefresh() {
    _shareStatsRefreshDebounce?.cancel();
    _shareStatsRefreshDebounce = Timer(const Duration(milliseconds: 500), () {
      _refreshShareStats();
    });
  }

  Future<void> _configureRealtimeSubscriptions({
    required String restaurantId,
    required String userId,
  }) {
    final key = '$restaurantId\u0000$userId';
    final activeFlight = _realtimeSubscriptionFlight;
    if (activeFlight != null) {
      if (_realtimeSubscriptionFlightKey != key) {
        _pendingRealtimeRestaurantId = restaurantId;
        _pendingRealtimeUserId = userId;
      }
      return activeFlight;
    }

    final configuration = _configureRealtimeSubscriptionsInternal(
      restaurantId: restaurantId,
      userId: userId,
    );
    _realtimeSubscriptionFlight = configuration;
    _realtimeSubscriptionFlightKey = key;
    configuration.then(
      (_) => _finishRealtimeSubscriptionFlight(configuration),
      onError: (Object error, StackTrace stackTrace) {
        _finishRealtimeSubscriptionFlight(configuration);
      },
    );
    return configuration;
  }

  Future<void> _configureRealtimeSubscriptionsInternal({
    required String restaurantId,
    required String userId,
  }) async {
    try {
      await Future.wait([
        _subscribeToRealtimeOrders(restaurantId),
        _subscribeToRealtimeNotifications(userId),
        _subscribeToRealtimeRestaurantData(
          restaurantId: restaurantId,
          userId: userId,
        ),
      ]);
    } catch (error, stackTrace) {
      debugPrint(
        'RestaurantDashboard: falha ao configurar Realtime: $error\n$stackTrace',
      );
    }
  }

  void _finishRealtimeSubscriptionFlight(Future<void> configuration) {
    if (!identical(_realtimeSubscriptionFlight, configuration)) return;
    _realtimeSubscriptionFlight = null;
    _realtimeSubscriptionFlightKey = null;

    final pendingRestaurantId = _pendingRealtimeRestaurantId;
    final pendingUserId = _pendingRealtimeUserId;
    _pendingRealtimeRestaurantId = null;
    _pendingRealtimeUserId = null;
    if (!mounted || pendingRestaurantId == null || pendingUserId == null) {
      return;
    }
    unawaited(
      _configureRealtimeSubscriptions(
        restaurantId: pendingRestaurantId,
        userId: pendingUserId,
      ),
    );
  }

  Future<void> _subscribeToRealtimeNotifications(String userId) async {
    await _notificationsChannel?.unsubscribe();
    _notificationsChannel = _supabase.channel(
      'restaurant-notifications-$userId',
    );
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
            final row = Map<String, dynamic>.from(
              payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord,
            );
            final notificationId = row['id']?.toString() ?? '';
            final type = row['type']?.toString() ?? '';
            final normalizedType = NotificationTypeUtils.canonicalize(type);
            final normalizedRow = {...row, 'type': normalizedType};
            setState(() {
              if (payload.eventType == PostgresChangeEvent.delete) {
                _restaurantNotifications = _restaurantNotifications
                    .where(
                      (notification) =>
                          notification['id']?.toString() != notificationId,
                    )
                    .toList();
                return;
              }

              if (payload.eventType == PostgresChangeEvent.insert) {
                _restaurantNotifications = [
                  normalizedRow,
                  ..._restaurantNotifications.where(
                    (notification) =>
                        notification['id']?.toString() != notificationId,
                  ),
                ];
                return;
              }

              var replaced = false;
              final updated = _restaurantNotifications.map((notification) {
                if (notification['id']?.toString() != notificationId) {
                  return notification;
                }
                replaced = true;
                return normalizedRow;
              }).toList();
              if (!replaced) {
                updated.insert(0, normalizedRow);
              }
              _restaurantNotifications = updated;
            });
            if (payload.eventType == PostgresChangeEvent.insert &&
                (normalizedType == 'NEW_PAID_ORDER' ||
                    normalizedType == 'NEW_ORDER')) {
              final orderId = _restaurantNotificationOrderId(normalizedRow);
              if (orderId.isNotEmpty) {
                unawaited(_refreshRealtimeOrder(orderId));
              } else {
                unawaited(_refreshOrdersAndBalance());
              }
              _showIncomingRestaurantOrderPopup(normalizedRow);
            } else if (payload.eventType == PostgresChangeEvent.insert &&
                (normalizedType == 'MESSAGE_RECEIVED' ||
                    normalizedType == 'DRIVER_ARRIVED' ||
                    normalizedType == 'ORDER_PICKED_UP')) {
              _showRealtimeNotificationPopup(normalizedRow);
              final orderId = _restaurantNotificationOrderId(normalizedRow);
              if (orderId.isNotEmpty) {
                unawaited(_refreshRealtimeOrder(orderId));
              } else {
                _scheduleOrdersRefresh();
              }
            } else if (payload.eventType == PostgresChangeEvent.insert &&
                (normalizedType == 'ORDER_DELIVERED' ||
                    normalizedType == 'ORDER_COMPLETED' ||
                    normalizedType == 'ORDER_AUTO_COMPLETED')) {
              final orderId = _restaurantNotificationOrderId(normalizedRow);
              if (orderId.isNotEmpty) {
                unawaited(_refreshRealtimeOrder(orderId));
              } else {
                _scheduleOrdersRefresh();
              }
            }
          },
        )
        .subscribe();
  }

  void _showIncomingRestaurantOrderPopup(Map<String, dynamic> notification) {
    final type = NotificationTypeUtils.canonicalize(
      notification['type']?.toString(),
    );
    final title = notification['title']?.toString().trim();
    final body = notification['body']?.toString().trim();
    final orderId = _restaurantNotificationOrderId(notification);
    final eventKey = '${orderId.trim()}|$type';
    final now = DateTime.now();
    _restaurantIncomingEventSeen.removeWhere(
      (_, seenAt) => now.difference(seenAt) > const Duration(minutes: 10),
    );
    if (orderId.isNotEmpty &&
        _restaurantIncomingEventSeen.containsKey(eventKey)) {
      return;
    }
    if (orderId.isNotEmpty) {
      _restaurantIncomingEventSeen[eventKey] = now;
      while (_restaurantIncomingEventSeen.length > 512) {
        _restaurantIncomingEventSeen.remove(
          _restaurantIncomingEventSeen.keys.first,
        );
      }
    }
    final shortId = orderId.length >= 8 ? orderId.substring(0, 8) : orderId;
    final fallbackTitle = type == 'NEW_PAID_ORDER'
        ? 'Novo pedido pago'
        : 'Novo pedido';
    final fallbackMessage = shortId.isNotEmpty
        ? 'Pedido #$shortId esta a aguardar confirmacao do restaurante.'
        : 'Existe um pedido novo a aguardar confirmacao do restaurante.';

    _showRestaurantOrderPopup(
      title: title == null || title.isEmpty ? fallbackTitle : title,
      message: body == null || body.isEmpty ? fallbackMessage : body,
      backgroundColor: AppColors.primaryRed,
      icon: Icons.receipt_long_rounded,
      playSound: true,
      criticalOrderId: orderId,
      duration: const Duration(milliseconds: 1800),
    );
  }

  void _showRealtimeNotificationPopup(Map<String, dynamic> notification) {
    final type = NotificationTypeUtils.canonicalize(
      notification['type']?.toString(),
    );
    if (_shouldSuppressRealtimeRestaurantPopup(notification, type)) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      return;
    }
    final title = notification['title']?.toString().trim();
    final body = notification['body']?.toString().trim();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    final backgroundColor = switch (type) {
      'DRIVER_ARRIVED' => const Color(0xFF0F766E),
      'ORDER_PICKED_UP' => const Color(0xFF102A43),
      _ => const Color(0xFF3B0D11),
    };
    final icon = switch (type) {
      'DRIVER_ARRIVED' => Icons.storefront_rounded,
      'ORDER_PICKED_UP' => Icons.delivery_dining_rounded,
      _ => Icons.chat_bubble_rounded,
    };
    final duration = switch (type) {
      'DRIVER_ARRIVED' || 'ORDER_PICKED_UP' => _popupDuration,
      _ => _popupDuration,
    };
    final fallbackTitle = switch (type) {
      'DRIVER_ARRIVED' => 'Estafeta chegou',
      'ORDER_PICKED_UP' => 'Pedido levantado',
      _ => 'Nova mensagem',
    };
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
                      title?.isNotEmpty == true ? title! : fallbackTitle,
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

  String _restaurantNotificationOrderId(Map<String, dynamic> notification) {
    String? readOrderId(Object? value) {
      if (value == null) return null;
      if (value is Map) {
        for (final key in const [
          'order_id',
          'entity_id',
          'id_pedido',
          'pedido_id',
        ]) {
          final candidate = value[key]?.toString().trim() ?? '';
          if (candidate.isNotEmpty) return candidate;
        }
        for (final key in const ['data', 'metadata', 'payload']) {
          final nested = readOrderId(value[key]);
          if (nested != null && nested.isNotEmpty) return nested;
        }
        return null;
      }
      final raw = value.toString().trim();
      if (raw.isEmpty) return null;
      if (raw.startsWith('{') && raw.endsWith('}')) {
        try {
          final decoded = jsonDecode(raw);
          final nested = readOrderId(decoded);
          if (nested != null && nested.isNotEmpty) return nested;
        } catch (_) {}
      }
      return null;
    }

    for (final key in const [
      'entity_id',
      'order_id',
      'data',
      'metadata',
      'payload',
    ]) {
      final candidate = readOrderId(notification[key]);
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }

    return '';
  }

  bool _shouldSuppressRealtimeRestaurantPopup(
    Map<String, dynamic> notification,
    String type,
  ) {
    final orderId = _restaurantNotificationOrderId(notification);
    if (orderId.isEmpty) return false;

    Order? order;
    for (final candidate in _orders) {
      if (candidate.id == orderId) {
        order = candidate;
        break;
      }
    }
    if (order == null) return false;

    final status = order.status;
    switch (type) {
      case 'DRIVER_ARRIVED':
        return status == OrderStatus.arrived ||
            status == OrderStatus.delivered ||
            status == OrderStatus.completed ||
            status == OrderStatus.autoCompleted;
      case 'ORDER_PICKED_UP':
        return status == OrderStatus.inTransit ||
            status == OrderStatus.onTheWay ||
            status == OrderStatus.arrived ||
            status == OrderStatus.delivered ||
            status == OrderStatus.completed ||
            status == OrderStatus.autoCompleted;
      default:
        return false;
    }
  }

  void _applyRestaurantOrderUpdates(
    List<Order> previousOrders,
    List<Order> nextOrders,
  ) {
    if (!mounted) return;

    final previousById = {for (final order in previousOrders) order.id: order};
    final nextById = {for (final order in nextOrders) order.id: order};
    for (final previous in previousOrders) {
      final next = nextById[previous.id];
      if (_isAwaitingRestaurantConfirmation(previous) &&
          (next == null || !_isAwaitingRestaurantConfirmation(next))) {
        unawaited(
          SoundController.instance.stopRestaurantOrderAlert(
            orderId: previous.id,
          ),
        );
      }
    }

    for (final order in nextOrders) {
      final previous = previousById[order.id];
      if (previous == null) {
        if (_isAwaitingRestaurantConfirmation(order)) {
          unawaited(
            SoundController.instance.startRestaurantOrderAlert(
              orderId: order.id,
              repeats: 2,
            ),
          );
        }
        return;
      }

      final previousAwaitingRestaurantConfirmation =
          _isAwaitingRestaurantConfirmation(previous);
      final nextAwaitingRestaurantConfirmation =
          _isAwaitingRestaurantConfirmation(order);
      if (!previousAwaitingRestaurantConfirmation &&
          nextAwaitingRestaurantConfirmation) {
        unawaited(
          SoundController.instance.startRestaurantOrderAlert(
            orderId: order.id,
            repeats: 2,
          ),
        );
        return;
      }

      if (!nextAwaitingRestaurantConfirmation) {
        unawaited(
          SoundController.instance.stopRestaurantOrderAlert(orderId: order.id),
        );
      }

      if (previous.status == order.status) continue;

      switch (order.status) {
        case OrderStatus.accepted:
        case OrderStatus.preparing:
          if (!_shownRestaurantLifecyclePopupKeys.add(
            'confirmed:${order.id}',
          )) {
            return;
          }
          _showRestaurantOrderPopup(
            title: 'Pedido confirmado',
            message: 'O restaurante confirmou o pedido e iniciou o preparo.',
            backgroundColor: AppColors.successGreen,
            icon: Icons.check_circle_outline_rounded,
          );
          return;
        case OrderStatus.ready:
        case OrderStatus.awaitingPickupConfirmation:
          if (!_shownRestaurantLifecyclePopupKeys.add('ready:${order.id}')) {
            return;
          }
          _showRestaurantOrderPopup(
            title: 'Pedido pronto para retirar',
            message: 'O pedido terminou o preparo e ja pode ser retirado.',
            backgroundColor: AppColors.primaryRed,
            icon: Icons.inventory_2_rounded,
          );
          return;
        case OrderStatus.courierAssigned:
          _showRestaurantOrderPopup(
            title: 'Estafeta atribuido',
            message: 'Ja existe estafeta associado a este pedido.',
            backgroundColor: const Color(0xFF102A43),
            icon: Icons.delivery_dining_rounded,
          );
          return;
        case OrderStatus.delivered:
          _showRestaurantOrderPopup(
            title: 'Entrega validada',
            message: 'O estafeta marcou a entrega ao cliente.',
            backgroundColor: AppColors.successGreen,
            icon: Icons.verified_rounded,
            duration: _popupDuration,
          );
          return;
        case OrderStatus.completed:
        case OrderStatus.autoCompleted:
          _showRestaurantOrderPopup(
            title: 'Pedido concluido',
            message: 'O cliente confirmou o recebimento do pedido.',
            backgroundColor: AppColors.successGreen,
            icon: Icons.task_alt_rounded,
            duration: const Duration(milliseconds: 850),
          );
          return;
        case OrderStatus.deliveryFailedOtp:
          _showRestaurantOrderPopup(
            title: 'Falha na entrega',
            message: 'A entrega falhou no OTP e exige atencao.',
            backgroundColor: Colors.orange.shade700,
            icon: Icons.sms_failed_rounded,
          );
          return;
        case OrderStatus.disputed:
          _showRestaurantOrderPopup(
            title: 'Pedido em disputa',
            message: 'Um pedido entrou em disputa.',
            backgroundColor: Colors.orange.shade700,
            icon: Icons.gavel_rounded,
          );
          return;
        case OrderStatus.cancelled:
        case OrderStatus.expired:
        case OrderStatus.paymentFailed:
          _showRestaurantOrderPopup(
            title: 'Pedido cancelado',
            message: 'Um pedido saiu do fluxo por cancelamento ou falha.',
            backgroundColor: Colors.orange.shade700,
            icon: Icons.cancel_outlined,
          );
          return;
        default:
          break;
      }
    }
  }

  void _showRestaurantOrderPopup({
    required String title,
    required String message,
    required Color backgroundColor,
    required IconData icon,
    bool playSound = false,
    String? criticalOrderId,
    Duration duration = _popupDuration,
  }) {
    final voiceType = _voiceTypeForRestaurantPopup(title, message);
    if (voiceType != null) {
      unawaited(
        AppVoiceService.instance.speakNotification(
          type: voiceType,
          title: title,
          body: message,
          notificationId:
              'restaurant_popup_${title.hashCode}_${message.hashCode}',
          channel: 'restaurant',
          priority: 'HIGH',
        ),
      );
    }
    if (playSound) {
      unawaited(
        SoundController.instance.startRestaurantOrderAlert(
          orderId: criticalOrderId,
          repeats: 2,
        ),
      );
    } else {
      unawaited(SoundController.instance.shortBang());
    }
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

  String? _voiceTypeForRestaurantPopup(String title, String message) {
    final text = '$title $message'.toLowerCase();
    if (text.contains('pedido confirmado')) return 'ORDER_ACCEPTED';
    if (text.contains('pedido pronto')) return 'ORDER_READY';
    if (text.contains('estafeta atribuido')) return 'DRIVER_ASSIGNED';
    if (text.contains('entrega validada')) return 'ORDER_DELIVERED';
    if (text.contains('pedido concluido')) return 'ORDER_COMPLETED';
    if (text.contains('cancelado')) return 'ORDER_CANCELLED';
    if (text.contains('disputa')) return 'ORDER_DISPUTED';
    return null;
  }

  Future<void> _subscribeToRealtimeRestaurantData({
    required String restaurantId,
    required String userId,
  }) async {
    await _catalogChannel?.unsubscribe();
    await _restaurantChannel?.unsubscribe();
    await _walletChannel?.unsubscribe();
    await _reviewsChannel?.unsubscribe();
    await _shareChannel?.unsubscribe();

    _catalogChannel = _supabase.channel('restaurant-catalog-$restaurantId');
    _catalogChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'menu_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: restaurantId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleCatalogRefresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'daily_combos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: restaurantId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleCatalogRefresh();
          },
        )
        .subscribe();

    _restaurantChannel = _supabase.channel('restaurant-profile-$restaurantId');
    _restaurantChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: restaurantId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleRestaurantSnapshotRefresh();
            _scheduleOrdersRefresh();
          },
        )
        .subscribe();

    _walletChannel = _supabase.channel('restaurant-wallet-$userId');
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
            _scheduleOrdersRefresh();
          },
        )
        .subscribe();

    _reviewsChannel = _supabase.channel('restaurant-reviews-$restaurantId');
    _reviewsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reviews',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: restaurantId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleCatalogRefresh();
          },
        )
        .subscribe();

    _shareChannel = _supabase.channel('restaurant-share-stats-$restaurantId');
    _shareChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_shares',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: restaurantId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleShareStatsRefresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_share_events',
          callback: (_) {
            if (!mounted) return;
            _scheduleShareStatsRefresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_referral_rewards',
          callback: (_) {
            if (!mounted) return;
            _scheduleShareStatsRefresh();
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B1020),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_restaurantId == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(title: const Text('Dashboard do restaurante')),
        body: const Center(
          child: Text(
            'Ainda nao encontramos um restaurante ligado a esta conta.',
          ),
        ),
      );
    }

    if (kIsWeb) return _buildMerchantWeb();

    final isWide = MediaQuery.of(context).size.width >= 980;
    final appBarViewport = DeligoViewport.fromSize(MediaQuery.sizeOf(context));

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: _tab == 0
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF11182B),
              foregroundColor: Colors.white,
              elevation: 0,
              title: Text(
                _restaurantName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  onPressed: _restaurantNotifications.isEmpty
                      ? null
                      : _showRestaurantNotifications,
                  icon: Badge(
                    isLabelVisible: _unreadRestaurantNotifications > 0,
                    label: Text(
                      _unreadRestaurantNotifications > 9
                          ? '9+'
                          : _unreadRestaurantNotifications.toString(),
                    ),
                    child: const Icon(Icons.notifications_none_rounded),
                  ),
                  tooltip: 'Notificacoes',
                ),
                IconButton(
                  onPressed: _totalUnreadChatCount > 0
                      ? () => setState(() => _tab = 1)
                      : null,
                  icon: _badgeIcon(
                    Icons.chat_bubble_outline,
                    count: _totalUnreadChatCount,
                  ),
                  tooltip: 'Mensagens nao lidas',
                ),
                SupportHeadsetButton(onPressed: () => context.push('/support')),
                if (appBarViewport.isCompact)
                  PopupMenuButton<String>(
                    tooltip: 'Mais opções',
                    onSelected: (value) {
                      if (value == 'settings') context.push('/settings');
                      if (value == 'refresh') _load();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'settings',
                        child: ListTile(
                          leading: Icon(Icons.settings_outlined),
                          title: Text('Configurações'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'refresh',
                        child: ListTile(
                          leading: Icon(Icons.refresh),
                          title: Text('Atualizar'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  )
                else ...[
                  IconButton(
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Configuracoes',
                  ),
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                ],
              ],
            ),
      floatingActionButton: _tab == 2
          ? FloatingActionButton.extended(
              onPressed: _showAddMenuItemDialog,
              backgroundColor: AppColors.primaryRed,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar prato'),
            )
          : null,
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _mobileNavigationIndex,
              onDestinationSelected: (value) =>
                  setState(() => _tab = _mobileNavigationTabs[value]),
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  label: 'Resumo',
                ),
                NavigationDestination(
                  icon: _badgeIcon(
                    Icons.receipt_long_outlined,
                    count: _awaitingConfirmationCount,
                  ),
                  label: _ordersTabLabel(),
                ),
                NavigationDestination(
                  icon: Icon(Icons.restaurant_menu_outlined),
                  label: 'Pratos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.analytics_outlined),
                  label: 'Receitas',
                ),
                NavigationDestination(
                  icon: Icon(Icons.storefront_outlined),
                  label: 'Perfil',
                ),
              ],
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (isWide) _buildSidebar(),
            Expanded(
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _tab == 1
                        ? _buildAwaitingConfirmationBanner()
                        : const SizedBox(
                            key: ValueKey('restaurant-awaiting-banner-hidden'),
                          ),
                  ),
                  Expanded(child: _currentTab()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _mobileNavigationIndex {
    if (_tab == 3 || _tab == 4) return 3;
    if (_tab == 5 || _tab == 6) return 4;
    final index = _mobileNavigationTabs.indexOf(_tab);
    return index < 0 ? 0 : index;
  }

  Widget _buildMerchantWeb() {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F2),
      floatingActionButton: _tab == 2
          ? FloatingActionButton.extended(
              onPressed: _showAddMenuItemDialog,
              backgroundColor: AppColors.primaryRed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Adicionar prato',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: Row(
        children: [
          if (!isMobile) _buildMerchantSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildMerchantTopBar(),
                if (_tab == 1) _buildAwaitingConfirmationBanner(),
                Expanded(
                  child: Container(
                    margin: EdgeInsets.fromLTRB(
                      isMobile ? 8 : 24,
                      isMobile ? 10 : 20,
                      isMobile ? 8 : 24,
                      0,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0B1020),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(26),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 32,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      child: KeyedSubtree(
                        key: ValueKey('merchant-web-tab-$_tab'),
                        child: _currentTab(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantSidebar() {
    final items = <({IconData icon, String label})>[
      (icon: Icons.space_dashboard_rounded, label: 'Visão geral'),
      (icon: Icons.receipt_long_outlined, label: _ordersTabLabel()),
      (icon: Icons.restaurant_menu_rounded, label: 'Menu'),
      (icon: Icons.account_balance_wallet_outlined, label: 'Carteira'),
      (icon: Icons.insights_rounded, label: 'Receitas'),
      (icon: Icons.storefront_outlined, label: 'Restaurante'),
      (icon: Icons.campaign_outlined, label: 'Marketing'),
    ];
    return Container(
      width: 248,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        border: Border(right: BorderSide(color: Color(0xFF252525))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _MerchantBrandMark(),
                SizedBox(width: 11),
                Text(
                  'DeliGo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'MERCHANT',
              style: TextStyle(
                color: Color(0xFF777777),
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(items.length, (index) {
            final item = items[index];
            final selected = _tab == index;
            final count = index == 1 ? _awaitingConfirmationCount : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _tab = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.icon,
                        size: 21,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF929292),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : const Color(0xFFAAAAAA),
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (count > 0)
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primaryRed,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          _buildMerchantWalletCard(),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push('/support'),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    Icons.headset_mic_outlined,
                    size: 20,
                    color: Color(0xFF929292),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Suporte DeliGo',
                    style: TextStyle(
                      color: Color(0xFFAAAAAA),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantWalletCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => _tab = 3),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Color(0xFFBDBDBD),
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  'Saldo disponível',
                  style: TextStyle(
                    color: Color(0xFFBDBDBD),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _money(_walletBalance),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantTopBar() {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    return Container(
      height: isMobile ? 72 : 86,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 28),
      decoration: const BoxDecoration(
        color: Color(0xFFF5F5F2),
        border: Border(bottom: BorderSide(color: Color(0xFFE6E5E0))),
      ),
      child: Row(
        children: [
          if (isMobile) ...[
            PopupMenuButton<int>(
              tooltip: 'Abrir menu',
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Color(0xFF191919),
              ),
              onSelected: (tab) => setState(() => _tab = tab),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 0, child: Text('Visão geral')),
                PopupMenuItem(value: 1, child: Text(_ordersTabLabel())),
                const PopupMenuItem(value: 2, child: Text('Menu')),
                const PopupMenuItem(value: 3, child: Text('Carteira')),
                const PopupMenuItem(value: 4, child: Text('Receitas')),
                const PopupMenuItem(value: 5, child: Text('Restaurante')),
                const PopupMenuItem(value: 6, child: Text('Marketing')),
              ],
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMobile)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFFFE2D9),
                      backgroundImage: _restaurantImageUrl.trim().isNotEmpty
                          ? NetworkImage(_restaurantImageUrl)
                          : null,
                      child: _restaurantImageUrl.trim().isEmpty
                          ? const Icon(
                              Icons.restaurant_rounded,
                              color: Color(0xFFFF4D0A),
                              size: 20,
                            )
                          : null,
                    ),
                  ),
                if (!isMobile)
                  Text(
                    _restaurantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF191919),
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                if (!isMobile) const SizedBox(height: 4),
                Text(
                  _merchantStatusLine(),
                  style: const TextStyle(
                    color: Color(0xFF777777),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (isMobile)
            IconButton(
              tooltip: _isOpen ? 'Fechar restaurante' : 'Abrir restaurante',
              onPressed: _toggleRestaurantOpenState,
              icon: Icon(
                Icons.circle,
                size: 14,
                color: _isOpen
                    ? const Color(0xFF188A57)
                    : const Color(0xFFB54A4A),
              ),
            )
          else
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _toggleRestaurantOpenState,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _isOpen
                      ? const Color(0xFFE8F6EF)
                      : const Color(0xFFF3E8E8),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _isOpen
                        ? const Color(0xFFC7E8D7)
                        : const Color(0xFFE8CACA),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isOpen
                            ? const Color(0xFF188A57)
                            : const Color(0xFFB54A4A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isOpen ? 'Aberto agora' : 'Fechado',
                      style: TextStyle(
                        color: _isOpen
                            ? const Color(0xFF176A47)
                            : const Color(0xFF8D3838),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!isMobile) const SizedBox(width: 12),
          _MerchantTopAction(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Notificações',
            count: _unreadRestaurantNotifications,
            onTap: _restaurantNotifications.isEmpty
                ? null
                : _showRestaurantNotifications,
          ),
          const SizedBox(width: 10),
          _MerchantTopAction(
            icon: Icons.settings_outlined,
            tooltip: 'Configurações',
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }

  String _merchantStatusLine() {
    final pending = _awaitingConfirmationCount;
    if (pending > 0) {
      return '$pending pedido(s) aguardam a sua atenção';
    }
    if (_confirmedOrdersCount > 0) {
      return '$_confirmedOrdersCount pedido(s) em preparação • Operação estável';
    }
    return 'Tudo sob controlo • Pronto para o próximo pedido';
  }

  int get _unreadRestaurantNotifications {
    return _restaurantNotifications
        .where((notification) => notification['read_at'] == null)
        .length;
  }

  Widget _badgeIcon(IconData icon, {required int count, Color? iconColor}) {
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: Colors.redAccent,
      label: Text(count > 99 ? '99+' : count.toString()),
      child: Icon(icon, color: iconColor),
    );
  }

  String _ordersTabLabel() {
    if (_awaitingConfirmationCount > 0 && _confirmedOrdersCount > 0) {
      return 'Pedidos ($_awaitingConfirmationCount/$_confirmedOrdersCount)';
    }
    if (_awaitingConfirmationCount > 0) {
      return 'Pedidos ($_awaitingConfirmationCount)';
    }
    if (_confirmedOrdersCount > 0) {
      return 'Pedidos ($_confirmedOrdersCount)';
    }
    return 'Pedidos';
  }

  Order? get _activeAwaitingConfirmationOrder {
    for (final order in _visibleActiveRestaurantOrders) {
      if (_isAwaitingRestaurantConfirmation(order)) {
        return order;
      }
    }
    return null;
  }

  Widget _buildAwaitingConfirmationBanner() {
    final order = _activeAwaitingConfirmationOrder;
    if (order == null) {
      return const SizedBox(key: ValueKey('restaurant-awaiting-banner-empty'));
    }
    final isCompact = MediaQuery.of(context).size.width < 600;

    final shortId = order.id.length >= 8
        ? order.id.substring(0, 8).toUpperCase()
        : order.id.toUpperCase();
    final extraOrders = _awaitingConfirmationCount - 1;
    final headline = extraOrders > 0
        ? '$_awaitingConfirmationCount pedidos pagos aguardam confirmacao'
        : 'Novo pedido pago pronto para aceite';
    final helper = extraOrders > 0
        ? 'Pedido #$shortId em destaque. Mais $extraOrders pedido(s) pagos seguem na fila.'
        : 'Pedido #$shortId ja entrou com pagamento confirmado.';

    return Padding(
      key: ValueKey(
        'restaurant-awaiting-banner-${order.id}-$_awaitingConfirmationCount',
      ),
      padding: EdgeInsets.fromLTRB(16, isCompact ? 10 : 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(isCompact ? 12 : 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A160B), Color(0xFF25110B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(isCompact ? 18 : 24),
          border: Border.all(
            color: Colors.orangeAccent.withValues(alpha: 0.34),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: isCompact ? 12 : 18,
              offset: Offset(0, isCompact ? 6 : 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: isCompact ? 38 : 44,
                  height: isCompact ? 38 : 44,
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(isCompact ? 12 : 14),
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: Colors.orangeAccent,
                  ),
                ),
                SizedBox(width: isCompact ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        maxLines: isCompact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: isCompact ? 14 : 16,
                        ),
                      ),
                      SizedBox(height: isCompact ? 2 : 4),
                      Text(
                        helper,
                        maxLines: isCompact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: isCompact ? 12 : 14,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: isCompact ? 8 : 12),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 10 : 12,
                    vertical: isCompact ? 6 : 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    _money(order.totalAmount),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: isCompact ? 12 : 14,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isCompact ? 10 : 12),
            Text(
              _deliveryDestinationLabel(order),
              maxLines: isCompact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: isCompact ? 12 : 14,
              ),
            ),
            SizedBox(height: isCompact ? 8 : 10),
            _countdownPill(order),
            SizedBox(height: isCompact ? 10 : 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => _changeStatus(
                          context,
                          order,
                          'accepted',
                          closeSheet: false,
                        ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(isCompact ? 'Aceitar' : 'Aceitar pedido'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showOrderDetails(order),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(isCompact ? 'Ver' : 'Ver pedido'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.20),
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

  Widget _currentTab() {
    switch (_tab) {
      case 1:
        return _ordersTab();
      case 2:
        return _menuTab();
      case 3:
        return _walletTab();
      case 4:
        return _analyticsTab();
      case 5:
        return _profileTab();
      case 6:
        return const RestaurantMarketingPage();
      default:
        return _summaryTab();
    }
  }

  Widget _summaryTab() {
    return _premiumMerchantSummaryTab();
    /*
    final lastCompletedOrder = _orders.cast<Order?>().firstWhere(
      (order) =>
          order?.status.value == 'completed' ||
          order?.status.value == 'auto_completed',
      orElse: () => null,
    );

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDashboardClimateHeader(),
          const SizedBox(height: 16),
          _heroCard(),
          const SizedBox(height: 16),
          _buildTopMetrics(),
          const SizedBox(height: 18),
          _buildLivePanels(),
          const SizedBox(height: 18),
          _buildChartsPanel(),
          const SizedBox(height: 18),
          const Text(
            'Alertas e feedback',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          _alertCard(
            icon: Icons.payments_outlined,
            color: Colors.green,
            title: _awaitingConfirmationCount > 0
                ? '$_awaitingConfirmationCount pagamento(s) a aguardar confirmacao'
                : 'Nenhum pagamento pendente de confirmacao',
            subtitle: _awaitingConfirmationCount > 0
                ? 'Entre em Pedidos para confirmar rapidamente e acelerar a operacao.'
                : 'Bom sinal: a fila financeira esta limpa agora.',
          ),
          const SizedBox(height: 10),
          _alertCard(
            icon: Icons.inventory_2_outlined,
            color: Colors.orange,
            title: _lowStockItems.isNotEmpty
                ? '${_lowStockItems.length} prato(s) abaixo de 10 unidades'
                : 'Nenhum prato abaixo de 10 unidades',
            subtitle: _outOfStockItems.isNotEmpty
                ? '${_outOfStockItems.length} item(ns) sem stock no cardapio.'
                : 'Seu cardapio esta bem abastecido no momento.',
          ),
          if (lastCompletedOrder != null) ...[
            const SizedBox(height: 18),
            const Text(
              'Ultimo pedido concluido',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            _completedOrderCard(lastCompletedOrder),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Combo do Dia',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _showCreateComboDialog(),
                icon: const Icon(Icons.local_offer_outlined),
                label: const Text('Criar combo'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_dailyCombos.isEmpty)
            _emptyCard('Nenhum combo criado ainda')
          else
            ..._dailyCombos.take(3).map(_comboCard),
        ],
      ),
    );
    */
  }

  Widget _premiumMerchantSummaryTab() {
    final activeOrders = _visibleActiveRestaurantOrders.toList();
    final preparingCount = activeOrders
        .where(
          (order) =>
              order.status.value == 'accepted' ||
              order.status.value == 'preparing',
        )
        .length;
    return RefreshIndicator(
      onRefresh: _refreshDashboardManually,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!kIsWeb) ...[
            _buildMerchantCommandHeader(),
            const SizedBox(height: 16),
          ],
          _buildMerchantRevenueHero(),
          const SizedBox(height: 16),
          _buildMerchantActionOrders(
            activeOrders,
            preparingCount: preparingCount,
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantCommandHeader() {
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.primaryRed,
          backgroundImage: _restaurantImageUrl.trim().isNotEmpty
              ? NetworkImage(_restaurantImageUrl)
              : null,
          child: _restaurantImageUrl.trim().isEmpty
              ? const Icon(Icons.storefront_rounded, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _restaurantName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _merchantStatusPill(
                    _isOpen ? 'Aberto' : 'Fechado',
                    _isOpen ? AppColors.successGreen : AppColors.primaryRed,
                  ),
                  _merchantStatusPill(
                    '${_restaurantDeliveryTime} min preparo',
                    const Color(0xFF5B8CFF),
                  ),
                  _merchantStatusPill('4.9', const Color(0xFFFFB020)),
                ],
              ),
            ],
          ),
        ),
        _merchantHeaderButton(
          Icons.notifications_none_rounded,
          _unreadRestaurantNotifications,
          _showRestaurantNotifications,
        ),
        const SizedBox(width: 8),
        _merchantHeaderButton(
          Icons.chat_bubble_outline,
          _totalUnreadChatCount,
          () => setState(() => _tab = 1),
        ),
      ],
    );
  }

  Widget _buildMerchantActionOrders(
    List<Order> orders, {
    required int preparingCount,
  }) {
    final actionable = orders.where((order) {
      final status = order.status.value;
      return status == 'pending' ||
          status == 'paid' ||
          status == 'accepted' ||
          status == 'preparing' ||
          status == 'ready';
    }).toList();
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pedidos agora',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '$preparingCount em preparação',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (actionable.isEmpty)
              const Text(
                'Nenhum pedido aguardando',
                style: TextStyle(color: Color(0xFFD1D5DB)),
              )
            else
              ...actionable.take(3).map(_merchantOrderPreviewRow),
          ],
        ),
      ),
    );
  }

  Widget _merchantOrderPreviewRow(Order order) {
    final shortId = order.id.length > 8 ? order.id.substring(0, 8) : order.id;
    final statusColor = switch (order.status.value) {
      'paid' => const Color(0xFF86EFAC),
      'accepted' || 'preparing' => const Color(0xFF93C5FD),
      'ready' => const Color(0xFFFDE68A),
      _ => const Color(0xFFD1D5DB),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        'Pedido #$shortId · ${_money(order.totalAmount)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        order.status.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFFE5E7EB),
      ),
      onTap: () {
        setState(() => _tab = 1);
        _showOrderDetails(order);
      },
    );
  }

  Widget _buildMerchantRevenueHero() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF151D33), Color(0xFF0B0F19)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF27324D)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Vendas hoje',
            style: TextStyle(
              color: Colors.white60,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _money(_todayRevenue),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '+18,6% comparado com ontem',
            style: TextStyle(
              color: AppColors.successGreen,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 56, child: _buildMiniRevenueChart()),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => setState(() => _tab = 4),
                icon: const Icon(Icons.insights_rounded),
                label: const Text('Ver relatorio'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _tab = 3),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Levantar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantRealtimeBoard({
    required int newOrders,
    required int preparing,
    required int ready,
    required int inDelivery,
    required int completed,
  }) {
    final items = [
      ('Novos', newOrders, Icons.fiber_new_rounded, AppColors.successGreen),
      ('Preparacao', preparing, Icons.soup_kitchen_outlined, Colors.orange),
      ('Prontos', ready, Icons.done_all_rounded, const Color(0xFF5B8CFF)),
      ('Estafeta', inDelivery, Icons.delivery_dining, const Color(0xFF9C6BFF)),
      ('Concluidos', completed, Icons.check_circle_outline, Colors.teal),
      (
        'Cancelados',
        _orders.where((o) => o.status.value == 'cancelled').length,
        Icons.cancel_outlined,
        AppColors.primaryRed,
      ),
    ];
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Operacao em tempo real',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 2.35,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return _merchantMetricTile(
                  label: item.$1,
                  value: item.$2.toString(),
                  icon: item.$3,
                  color: item.$4,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantFinanceCenter() {
    final metrics = [
      ('Vendas hoje', _money(_todayRevenue)),
      ('Vendas esta semana', _money(_weekRevenue)),
      ('Vendas este mes', _money(_monthRevenue)),
      ('Saldo real da carteira', _money(_walletBalance)),
    ];
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Centro financeiro',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            ...metrics.map(
              (metric) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        metric.$1,
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ),
                    Text(
                      metric.$2,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push('/wallet?section=withdraw'),
                icon: const Icon(Icons.account_balance_outlined),
                label: const Text('Levantar saldo'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantLiveMapCard() {
    return _darkCard(
      child: Container(
        height: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF121A2E), Color(0xFF0B0F19)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _MerchantMapGridPainter()),
            ),
            Align(
              alignment: Alignment.center,
              child: _merchantMapPin(Icons.storefront, AppColors.primaryRed),
            ),
            Align(
              alignment: const Alignment(-0.68, -0.38),
              child: _merchantMapPin(Icons.delivery_dining, Colors.greenAccent),
            ),
            Align(
              alignment: const Alignment(0.58, 0.28),
              child: _merchantMapPin(
                Icons.location_on,
                const Color(0xFF5B8CFF),
              ),
            ),
            const Positioned(
              left: 0,
              top: 0,
              child: Text(
                'Mapa ao vivo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Positioned(
              left: 0,
              bottom: 0,
              child: Text(
                'Restaurante, estafetas, clientes e pedidos em rota',
                style: TextStyle(color: Colors.white60),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantSmartProducts() {
    final products = List<MenuItem>.from(_menuItems)
      ..sort((a, b) => b.stockQuantity.compareTo(a.stockQuantity));
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Produtos inteligentes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            if (products.isEmpty)
              const Text(
                'Sem pratos cadastrados.',
                style: TextStyle(color: Colors.white60),
              )
            else
              ...products.take(3).map(_merchantProductRow),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantActiveOrdersPreview(List<Order> orders) {
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pedidos ativos',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _tab = 1),
                  child: const Text('Ver todos'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (orders.isEmpty)
              const Text(
                'Sem pedidos ativos agora.',
                style: TextStyle(color: Colors.white60),
              )
            else
              ...orders.map(_merchantOrderPreviewRow),
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantQuickActions() {
    final List<({IconData icon, String label, VoidCallback onTap})> actions = [
      (
        icon: Icons.add_rounded,
        label: 'Novo prato',
        onTap: () => _showAddMenuItemDialog(),
      ),
      (
        icon: Icons.restaurant_menu_outlined,
        label: 'Cardapio',
        onTap: () => setState(() => _tab = 2),
      ),
      (
        icon: Icons.local_offer_outlined,
        label: 'Promocao',
        onTap: () => _showCreateComboDialog(),
      ),
      (
        icon: Icons.insights_rounded,
        label: 'Relatorios',
        onTap: () => setState(() => _tab = 4),
      ),
      (
        icon: Icons.payments_outlined,
        label: 'Levantar',
        onTap: () => setState(() => _tab = 3),
      ),
      (
        icon: Icons.auto_awesome,
        label: 'IA',
        onTap: () => setState(() => _tab = 6),
      ),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.05,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final action = actions[index];
        return InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(20),
          child: _darkCard(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: Colors.white),
                const SizedBox(height: 8),
                Text(
                  action.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _merchantStatusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _merchantHeaderButton(
    IconData icon,
    int count,
    VoidCallback? onPressed,
  ) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton.filledTonal(
          onPressed: onPressed,
          icon: Icon(icon),
          color: Colors.white,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF11182B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        if (count > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primaryRed,
                shape: BoxShape.circle,
              ),
              child: Text(
                count > 9 ? '9+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMiniRevenueChart() {
    final values = _revenueSeries;
    final maxY = values.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY <= 0 ? 10 : maxY * 1.2,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i]),
            ],
            isCurved: true,
            color: Colors.white,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _merchantMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _merchantMapPin(IconData icon, Color color) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }

  Widget _merchantProductRow(MenuItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: item.imageUrl != null && item.imageUrl!.trim().isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: item.imageUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    memCacheWidth: _cacheDimension(48),
                    memCacheHeight: _cacheDimension(48),
                  )
                : Container(
                    width: 48,
                    height: 48,
                    color: AppColors.primaryRed.withValues(alpha: 0.18),
                    child: const Icon(Icons.restaurant, color: Colors.white),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_money(item.price)}  |  Stock ${item.stockQuantity}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            iconColor: Colors.white,
            color: const Color(0xFF11182B),
            onSelected: (value) {
              if (value == 'edit') {
                unawaited(_showAddMenuItemDialog(item: item));
                return;
              }
              if (value == 'delete') {
                unawaited(_confirmDeleteMenuItem(item));
                return;
              }
              setState(() => _tab = 2);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(value: 'delete', child: Text('Apagar')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ordersTab() {
    final filteredOrders = _filteredOrders;
    if (filteredOrders.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _emptyCard('Sem pedidos por agora'),
          const SizedBox(height: 12),
          if (_orderFilter != 'all')
            OutlinedButton.icon(
              onPressed: () => setState(() => _orderFilter = 'all'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar para todos'),
            ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pedidos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Por confirmar: $_awaitingConfirmationCount  |  Confirmados: $_confirmedOrdersCount',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            if (_orderFilter != 'all')
              TextButton.icon(
                onPressed: () => setState(() => _orderFilter = 'all'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Todos'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _totalUnreadChatCount > 0
              ? 'Existem $_totalUnreadChatCount mensagem(ns) novas em $_ordersWithUnreadChatCount pedido(s). Os pedidos com mensagens aparecem primeiro.'
              : 'Os pedidos atualizam em tempo real sem refresh manual.',
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _orderSummaryChip(
              label: 'Por confirmar',
              count: _awaitingConfirmationCount,
              color: Colors.orangeAccent,
            ),
            _orderSummaryChip(
              label: 'Confirmados',
              count: _confirmedOrdersCount,
              color: Colors.greenAccent,
            ),
            _orderSummaryChip(
              label: 'Arquivados',
              count: _archivedPendingCount,
              color: Colors.redAccent,
            ),
            _orderSummaryChip(
              label: 'Chat nao lido',
              count: _totalUnreadChatCount,
              color: Colors.lightBlueAccent,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip(
                'Todos (${_orders.length})',
                _orderFilter == 'all',
                () => setState(() => _orderFilter = 'all'),
              ),
              _filterChip(
                'Pagos ($_awaitingConfirmationCount)',
                _orderFilter == 'paid',
                () => setState(() => _orderFilter = 'paid'),
              ),
              _filterChip(
                'Arquivados ($_archivedPendingCount)',
                _orderFilter == 'archived',
                () => setState(() => _orderFilter = 'archived'),
              ),
              _filterChip(
                'Preparando (${_orders.where((order) => order.status.value == 'preparing').length})',
                _orderFilter == 'preparing',
                () => setState(() => _orderFilter = 'preparing'),
              ),
              _filterChip(
                'Prontos (${_orders.where((order) => order.status.value == 'ready').length})',
                _orderFilter == 'ready',
                () => setState(() => _orderFilter = 'ready'),
              ),
              _filterChip(
                'Entregues (${_postDeliveryOrders.length})',
                _orderFilter == 'delivered',
                () => setState(() => _orderFilter = 'delivered'),
              ),
              _filterChip(
                'Concluidos (${_completedOrders.length})',
                _orderFilter == 'completed',
                () => setState(() => _orderFilter = 'completed'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...filteredOrders.indexed.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildOrderEntrance(
              order: entry.$1,
              child: _buildSwipeableOrderCard(entry.$2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderEntrance({required int order, required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + (order * 45)),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, builtChild) {
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * (20 + (order * 3))),
            child: builtChild,
          ),
        );
      },
    );
  }

  Widget _menuTab() {
    final visibleItems = _filteredMenuItems;
    final sectionTitle = switch (_stockFilter) {
      'out' => 'Produtos sem stock',
      'low' => 'Produtos com stock baixo',
      'all' => 'Todos os pratos',
      _ => 'Pratos disponiveis',
    };
    final sectionSubtitle = switch (_stockFilter) {
      'out' => 'Aqui aparecem apenas os produtos com stock zero',
      'low' => 'Itens abaixo de 10 unidades em stock',
      'all' => 'Todos os itens do cardapio',
      _ => 'Itens disponiveis para venda agora',
    };
    final emptyLabel = switch (_stockFilter) {
      'low' => 'Nenhum prato com stock baixo agora',
      'out' => 'Nenhum prato sem stock agora',
      'all' => 'Cardapio vazio',
      _ => 'Nenhum prato disponivel agora',
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildSectionTitle(sectionTitle, sectionSubtitle),
              ),
              if (_stockFilter != 'available')
                TextButton.icon(
                  onPressed: () => setState(() => _stockFilter = 'available'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Voltar para disponiveis'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(
                      'Disponiveis (${_menuItems.where((item) => item.isAvailable && item.stockQuantity > 0).length})',
                      _stockFilter == 'available',
                      () => setState(() => _stockFilter = 'available'),
                    ),
                    _filterChip(
                      '< 10 em stock (${_lowStockItems.length})',
                      _stockFilter == 'low',
                      () => setState(() => _stockFilter = 'low'),
                    ),
                    _filterChip(
                      'Sem stock (${_outOfStockItems.length})',
                      _stockFilter == 'out',
                      () => setState(() => _stockFilter = 'out'),
                    ),
                    _filterChip(
                      'Todos (${_menuItems.length})',
                      _stockFilter == 'all',
                      () => setState(() => _stockFilter = 'all'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (visibleItems.isEmpty)
                _emptyCard(emptyLabel)
              else
                ...visibleItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildDishCard(item),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _walletTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle('Wallet', 'Saldo real da carteira do restaurante'),
        const SizedBox(height: 12),
        _darkCard(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saldo disponivel',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  _money(_walletBalance),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => context.push('/wallet?section=withdraw'),
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('Levantar saldo'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _darkCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Resumo financeiro',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                _financeRow('Vendas de hoje', _money(_todayRevenue)),
                _financeRow('Vendas da semana', _money(_weekRevenue)),
                _financeRow('Vendas do mes', _money(_monthRevenue)),
                _financeRow(
                  'Pedidos concluidos',
                  _completedOrders.length.toString(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionTitle(
          'Movimentos recentes',
          'Entradas e levantamentos reais',
        ),
        const SizedBox(height: 8),
        _darkCard(
          child: _walletMovements.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Ainda não existem movimentos financeiros.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : Column(
                  children: _walletMovements.map((movement) {
                    final credit =
                        movement['direction']?.toString() == 'credit';
                    final amount =
                        (movement['amount'] as num?)?.toDouble() ?? 0;
                    final type =
                        movement['entry_type']?.toString() ?? 'Movimento';
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      leading: Icon(
                        credit
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        color: credit
                            ? AppColors.successGreen
                            : AppColors.primaryRed,
                      ),
                      title: Text(
                        type,
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: Text(
                        '${credit ? '+' : '-'}${_money(amount)}',
                        style: TextStyle(
                          color: credit
                              ? AppColors.successGreen
                              : AppColors.primaryRed,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _analyticsTab() {
    final sales = _dishSalesRange == '24h'
        ? _dishSales24h
        : _dishSalesRange == '7d'
        ? _dishSales7d
        : _dishSales30d;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionTitle(
          'Receitas',
          'Saldo, vendas, comissões e movimentos do restaurante',
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip(
                'Hoje',
                _revenueRange == 'today',
                () => setState(() => _revenueRange = 'today'),
              ),
              _filterChip(
                'Semana',
                _revenueRange == 'week',
                () => setState(() => _revenueRange = 'week'),
              ),
              _filterChip(
                'Mes',
                _revenueRange == 'month',
                () => setState(() => _revenueRange = 'month'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildMerchantFinanceCenter(),
        const SizedBox(height: 12),
        _buildChartsPanel(),
        const SizedBox(height: 22),
        _buildSectionTitle(
          'Pratos mais vendidos',
          'Resumo dos pratos que mais faturam',
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip(
                '24h',
                _dishSalesRange == '24h',
                () => setState(() => _dishSalesRange = '24h'),
              ),
              _filterChip(
                '7 dias',
                _dishSalesRange == '7d',
                () => setState(() => _dishSalesRange = '7d'),
              ),
              _filterChip(
                '30 dias',
                _dishSalesRange == '30d',
                () => setState(() => _dishSalesRange = '30d'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _darkCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: sales.isEmpty
                ? const Text(
                    'Ainda sem vendas suficientes para gerar relatorio.',
                    style: TextStyle(color: Colors.white70),
                  )
                : Column(
                    children: sales.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primaryRed.withValues(
                                  alpha: 0.18,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.restaurant_menu_rounded,
                                color: AppColors.primaryRed,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.quantity} vendidos',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _money(item.revenue),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _profileTab() {
    final smartLocation = LocationDisplay.smartLocation(
      address: _restaurantAddress,
      neighborhood: _restaurantNeighborhood,
      city: _restaurantCity,
    );
    final smartReference = _restaurantLandmarkReference.trim().isNotEmpty
        ? _restaurantLandmarkReference.trim()
        : LocationDisplay.compactReference(
            address: _restaurantAddress,
            neighborhood: _restaurantNeighborhood,
            city: _restaurantCity,
          );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              SizedBox(
                height: 180,
                width: double.infinity,
                child: _restaurantImageUrl.isNotEmpty
                    ? Image.network(
                        _restaurantImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stackTrace) =>
                            _profileHeroFallback(),
                      )
                    : _profileHeroFallback(),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.08),
                        Colors.black.withValues(alpha: 0.64),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _restaurantName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _isOpen
                              ? Icons.circle
                              : Icons.pause_circle_filled_rounded,
                          size: 12,
                          color: _isOpen
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFFFCA5A5),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isOpen ? 'Aberto' : 'Fechado',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Meu restaurante',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            TextButton.icon(
              onPressed: _showEditRestaurantProfileDialog,
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Editar perfil'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryRed,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        _profileMenuRow(
          Icons.support_agent_outlined,
          'Central de ajuda',
          () => context.push('/support'),
        ),
        _profileMenuRow(
          Icons.lock_outline,
          'Conta e segurança',
          () => context.push('/settings'),
        ),
        _profileMenuRow(
          Icons.event_outlined,
          'Eventos',
          () => setState(() => _tab = 6),
        ),
        _profileMenuRow(
          Icons.qr_code_2_outlined,
          'QR Code do restaurante',
          () => context.push(
            '/restaurant-dashboard/qr',
            extra: {
              'restaurantId': _restaurantId,
              'restaurantName': _restaurantName,
              'imageUrl': _restaurantImageUrl,
              'dishes': _menuItems,
            },
          ),
        ),
        const Divider(height: 24),
        _profileMenuRow(
          _isOpen ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
          _isOpen ? 'Aberto' : 'Fechado',
          _isSubmitting ? () {} : _toggleRestaurantOpenState,
        ),
        const Divider(height: 24),
        const Text(
          'Informações do restaurante',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        _profileLine(Icons.location_on_outlined, 'Localizacao', smartLocation),
        const SizedBox(height: 10),
        _profileLine(Icons.place_outlined, 'Referencia', smartReference),
        const SizedBox(height: 10),
        _profileLine(
          Icons.description_outlined,
          'Descricao',
          _restaurantDescription.trim().isEmpty
              ? 'Sem descricao definida ainda.'
              : _restaurantDescription.trim(),
        ),
        const SizedBox(height: 10),
        _profileLine(
          Icons.phone_outlined,
          'Telefone',
          _restaurantPhone.trim().isEmpty
              ? 'Nao definido'
              : _restaurantPhone.trim(),
        ),
        const SizedBox(height: 20),
        const Text(
          'Legal e suporte',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        _profileMenuRow(
          Icons.description_outlined,
          'Termos de uso',
          () => context.push('/terms'),
        ),
        _profileMenuRow(
          Icons.privacy_tip_outlined,
          'Politica de privacidade',
          () => context.push('/privacy'),
        ),
        _profileMenuRow(
          Icons.receipt_long_outlined,
          'Pagamentos e reembolsos',
          () => context.push('/refund-policy'),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sair'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.neutralGray,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
        ),
        const InstitutionalFooter(),
      ],
    );
  }

  Future<void> _subscribeToRealtimeOrders(String restaurantId) async {
    await _ordersChannel?.unsubscribe();
    _ordersChannel = _supabase.channel('restaurant-dashboard-$restaurantId');
    _ordersChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: restaurantId,
          ),
          callback: (payload) {
            final record = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            final orderId = record['id']?.toString() ?? '---';
            final shortId = orderId.length >= 8
                ? orderId.substring(0, 8)
                : orderId;
            final status = record['status']?.toString() ?? 'updated';
            final previousAwaitingRestaurantConfirmation =
                _recordAwaitingRestaurantConfirmation(payload.oldRecord);
            final nextAwaitingRestaurantConfirmation =
                _recordAwaitingRestaurantConfirmation(payload.newRecord);
            if (!mounted) return;
            if (payload.eventType == PostgresChangeEvent.delete) {
              _removeRealtimeOrderLocally(orderId);
            } else if (payload.newRecord.isNotEmpty) {
              _upsertRealtimeOrderLocally(
                Map<String, dynamic>.from(payload.newRecord),
              );
              if (orderId.isNotEmpty && orderId != '---') {
                unawaited(_refreshRealtimeOrder(orderId));
              }
            }
            setState(() {
              _liveEvents.insert(0, {
                'id':
                    '${_serverNow.millisecondsSinceEpoch}-${payload.eventType.name}',
                'title':
                    nextAwaitingRestaurantConfirmation &&
                        !previousAwaitingRestaurantConfirmation
                    ? 'Novo pedido pago'
                    : payload.eventType == PostgresChangeEvent.insert
                    ? 'Novo pedido ao vivo'
                    : 'Pedido atualizado ao vivo',
                'subtitle': 'Pedido #$shortId - $status',
                'priority':
                    nextAwaitingRestaurantConfirmation &&
                        !previousAwaitingRestaurantConfirmation
                    ? 'HIGH'
                    : payload.eventType == PostgresChangeEvent.insert
                    ? 'HIGH'
                    : 'MEDIUM',
              });
              if (_liveEvents.length > 8) {
                _liveEvents.removeRange(8, _liveEvents.length);
              }
            });
            if (orderId.isEmpty || orderId == '---') {
              _scheduleOrdersRefresh();
            }
          },
        )
        .subscribe();
  }

  bool _recordAwaitingRestaurantConfirmation(Map<String, dynamic> record) {
    if (record.isEmpty) return false;
    final status = record['status']?.toString().trim().toLowerCase() ?? '';
    final paymentStatus =
        record['payment_status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'paid' || status == 'payment_authorized') return true;
    return status == 'pending' &&
        (paymentStatus == 'completed' ||
            paymentStatus == 'paid' ||
            paymentStatus == 'authorized');
  }

  List<Order> get _completedOrders => _orders
      .where(
        (order) =>
            order.status.value == 'completed' ||
            order.status.value == 'auto_completed',
      )
      .toList();
  List<Order> get _postDeliveryOrders => _orders
      .where(
        (order) =>
            order.status.value == 'delivery_failed_otp' ||
            order.status.value == 'delivered' ||
            order.status.value == 'disputed',
      )
      .toList();
  List<MenuItem> get _lowStockItems => _menuItems
      .where(
        (item) =>
            item.isAvailable &&
            item.stockQuantity > 0 &&
            item.stockQuantity < 10,
      )
      .toList();
  List<MenuItem> get _outOfStockItems =>
      _menuItems.where((item) => item.stockQuantity <= 0).toList();

  bool _isAwaitingRestaurantConfirmation(Order order) {
    final status = order.status.value;
    if (status == 'paid' || status == 'payment_authorized') return true;
    return status == 'pending' &&
        (order.paymentStatus == 'completed' ||
            order.paymentStatus == 'paid' ||
            order.paymentStatus == 'authorized');
  }

  bool _isTimedOutRestaurantConfirmationOrder(Order order) {
    if (!_isAwaitingRestaurantConfirmation(order)) return false;
    final deadline = order.restaurantConfirmationStartedAt.add(
      const Duration(minutes: 3),
    );
    return !deadline.isAfter(_serverNow);
  }

  void _hideTimedOutOrdersIfNeeded() {
    final timedOutIds = _orders
        .where(_isTimedOutRestaurantConfirmationOrder)
        .map((order) => order.id)
        .where((id) => !_timedOutHiddenOrderIds.contains(id))
        .toList(growable: false);
    if (timedOutIds.isEmpty) return;

    setState(() {
      _timedOutHiddenOrderIds.addAll(timedOutIds);
    });
    _scheduleOrdersRefresh();
  }

  Iterable<Order> get _visibleRestaurantOrders =>
      _orders.where((order) => !_timedOutHiddenOrderIds.contains(order.id));

  Iterable<Order> get _visibleActiveRestaurantOrders =>
      _visibleRestaurantOrders.where((order) {
        return !_archivedPendingOrderIds.contains(order.id);
      });

  Iterable<Order> get _archivedPendingOrders =>
      _visibleRestaurantOrders.where((order) {
        return _archivedPendingOrderIds.contains(order.id) &&
            _isAwaitingRestaurantConfirmation(order);
      });

  Duration _preparationRemaining(Order order) {
    final prepMinutes = order.estimatedPreparationMinutes <= 0
        ? 25
        : order.estimatedPreparationMinutes;
    final deadline = order.preparationReference.add(
      Duration(minutes: prepMinutes),
    );
    debugPrint(
      '[PREP_TIMER] orderId=${order.id} acceptedAt=${order.acceptedAt?.toIso8601String()} '
      'preparingAt=${order.preparationStartedAt?.toIso8601String()} '
      'readyAt=${order.readyAt?.toIso8601String()} '
      'remainingSeconds=${deadline.difference(_serverNow).inSeconds}',
    );
    final remaining = deadline.difference(_serverNow);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool _hasExpiredPreparationCountdown(Order order) {
    final status = order.status.value;
    if (status != 'accepted' && status != 'preparing') return false;
    return _preparationRemaining(order) == Duration.zero;
  }

  bool _hasExpiredOperationalCountdown(Order order) {
    return _isTimedOutRestaurantConfirmationOrder(order) ||
        _hasExpiredPreparationCountdown(order);
  }

  void _maybeRefreshExpiredOrderCountdowns() {
    final now = _serverNow;
    final hasExpiredCountdown = _orders.any(_hasExpiredOperationalCountdown);
    if (!hasExpiredCountdown) return;

    if (_lastExpiredCountdownRefreshAt != null &&
        now.difference(_lastExpiredCountdownRefreshAt!) <
            const Duration(seconds: 5)) {
      return;
    }

    _lastExpiredCountdownRefreshAt = now;
    unawaited(_refreshOrdersAndBalance());
  }

  bool _isConfirmedOperationalOrder(Order order) {
    const confirmedStatuses = {
      'accepted',
      'preparing',
      'ready',
      'awaiting_pickup_confirmation',
      'picked_up',
      'in_delivery',
      'courier_assigned',
      'in_transit',
      'arrived',
      'delivery_failed_otp',
      'delivered',
      'disputed',
    };
    return confirmedStatuses.contains(order.status.value);
  }

  int get _awaitingConfirmationCount => _visibleActiveRestaurantOrders
      .where(_isAwaitingRestaurantConfirmation)
      .length;

  int get _archivedPendingCount => _archivedPendingOrders.length;

  int get _confirmedOrdersCount =>
      _visibleActiveRestaurantOrders.where(_isConfirmedOperationalOrder).length;

  int get _totalUnreadChatCount =>
      _restaurantNotifications.where((notification) {
        return ChatNotificationUtils.isUnreadChatNotification(notification);
      }).length;

  int get _ordersWithUnreadChatCount => _visibleRestaurantOrders
      .where((order) => _unreadChatCountFor(order.id) > 0)
      .length;

  int _unreadChatCountFor(String orderId) {
    return _restaurantNotifications.where((notification) {
      return ChatNotificationUtils.isUnreadChatNotification(notification) &&
          ChatNotificationUtils.matchesOrder(notification, orderId);
    }).length;
  }

  List<Order> _prioritizeOrdersWithUnreadChat(Iterable<Order> orders) {
    final result = orders.toList();
    result.sort((a, b) {
      final unreadDifference = _unreadChatCountFor(
        b.id,
      ).compareTo(_unreadChatCountFor(a.id));
      if (unreadDifference != 0) return unreadDifference;
      return (b.createdAt).compareTo(a.createdAt);
    });
    return result;
  }

  Future<void> _markOrderChatNotificationsAsRead(String orderId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final readAt = _serverNowIsoUtc;
    final matching = _restaurantNotifications.where(
      (notification) =>
          ChatNotificationUtils.isUnreadChatNotification(notification) &&
          ChatNotificationUtils.matchesOrder(notification, orderId),
    );
    final ids = matching
        .map((notification) => notification['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    try {
      await _supabase
          .from('push_notifications')
          .update({'read_at': readAt})
          .eq('user_id', user.id)
          .inFilter('id', ids);
    } catch (error) {
      debugPrint('RestaurantDashboard mark chat read: $error');
    }
    if (!mounted) return;
    setState(() {
      _restaurantNotifications = _restaurantNotifications.map((notification) {
        final id = notification['id']?.toString();
        if (!ids.contains(id)) return notification;
        return {...notification, 'read_at': readAt};
      }).toList();
    });
  }

  double _restaurantSaleAmount(Order order) =>
      (order.totalAmount - order.deliveryFee).clamp(0, double.infinity);

  double get _todayRevenue {
    final now = _serverNowLocal;
    return _completedOrders
        .where((order) {
          final dt = (order.updatedAt ?? order.createdAt).toLocal();
          return dt.year == now.year &&
              dt.month == now.month &&
              dt.day == now.day;
        })
        .fold<double>(0, (sum, order) => sum + _restaurantSaleAmount(order));
  }

  double get _weekRevenue {
    final now = _serverNowLocal;
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return _completedOrders
        .where(
          (order) =>
              (order.updatedAt ?? order.createdAt).toLocal().isAfter(start),
        )
        .fold<double>(0, (sum, order) => sum + _restaurantSaleAmount(order));
  }

  double get _monthRevenue {
    final now = _serverNowLocal;
    final start = DateTime(now.year, now.month, 1);
    return _completedOrders
        .where(
          (order) =>
              (order.updatedAt ?? order.createdAt).toLocal().isAfter(start),
        )
        .fold<double>(0, (sum, order) => sum + _restaurantSaleAmount(order));
  }

  List<Order> get _filteredOrders {
    switch (_orderFilter) {
      case 'paid':
        return _prioritizeOrdersWithUnreadChat(
          _visibleActiveRestaurantOrders.where(
            _isAwaitingRestaurantConfirmation,
          ),
        );
      case 'archived':
        return _prioritizeOrdersWithUnreadChat(_archivedPendingOrders);
      case 'preparing':
      case 'ready':
        return _prioritizeOrdersWithUnreadChat(
          _visibleActiveRestaurantOrders.where(
            (order) => order.status.value == _orderFilter,
          ),
        );
      case 'delivered':
        return _prioritizeOrdersWithUnreadChat(
          _postDeliveryOrders.where(
            (order) => !_timedOutHiddenOrderIds.contains(order.id),
          ),
        );
      case 'completed':
        return _prioritizeOrdersWithUnreadChat(
          _completedOrders.where(
            (order) => !_timedOutHiddenOrderIds.contains(order.id),
          ),
        );
      default:
        return _prioritizeOrdersWithUnreadChat(_visibleActiveRestaurantOrders);
    }
  }

  List<MenuItem> get _filteredMenuItems {
    switch (_stockFilter) {
      case 'low':
        return _lowStockItems;
      case 'out':
        return _outOfStockItems;
      case 'all':
        return _menuItems;
      default:
        return _menuItems
            .where((item) => item.isAvailable && item.stockQuantity > 0)
            .toList();
    }
  }

  List<double> get _revenueSeries {
    final now = _serverNowLocal;
    if (_revenueRange == 'today') {
      return List<double>.generate(6, (index) {
        final bucket = now.subtract(Duration(hours: 5 - index));
        return _completedOrders
            .where((order) {
              final dt = (order.updatedAt ?? order.createdAt).toLocal();
              return dt.year == bucket.year &&
                  dt.month == bucket.month &&
                  dt.day == bucket.day &&
                  dt.hour == bucket.hour;
            })
            .fold<double>(
              0,
              (sum, order) => sum + _restaurantSaleAmount(order),
            );
      });
    }
    if (_revenueRange == 'month') {
      return List<double>.generate(4, (index) {
        final start = now.subtract(Duration(days: (3 - index) * 7));
        final end = start.add(const Duration(days: 7));
        return _completedOrders
            .where((order) {
              final dt = (order.updatedAt ?? order.createdAt).toLocal();
              return dt.isAfter(start) && dt.isBefore(end);
            })
            .fold<double>(
              0,
              (sum, order) => sum + _restaurantSaleAmount(order),
            );
      });
    }
    return List<double>.generate(7, (index) {
      final bucket = now.subtract(Duration(days: 6 - index));
      return _completedOrders
          .where((order) {
            final dt = (order.updatedAt ?? order.createdAt).toLocal();
            return dt.year == bucket.year &&
                dt.month == bucket.month &&
                dt.day == bucket.day;
          })
          .fold<double>(0, (sum, order) => sum + _restaurantSaleAmount(order));
    });
  }

  List<double> get _productsSeries {
    final top = List<MenuItem>.from(_menuItems)
      ..sort((a, b) => b.stockQuantity.compareTo(a.stockQuantity));
    final values = top
        .take(5)
        .map((item) => item.stockQuantity.toDouble())
        .toList();
    while (values.length < 5) {
      values.add(0);
    }
    return values;
  }

  Widget _buildSidebar() => Container(
    width: 244,
    decoration: const BoxDecoration(
      color: Color(0xFF11182B),
      border: Border(right: BorderSide(color: Color(0xFF1F2940))),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryRed,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Painel do restaurante',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Gestao profissional ao vivo',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _sidebarTile(0, Icons.dashboard_customize_outlined, 'Resumo'),
        _sidebarTile(
          1,
          Icons.receipt_long_outlined,
          _ordersTabLabel(),
          badgeCount: _awaitingConfirmationCount,
        ),
        _sidebarTile(2, Icons.restaurant_menu_outlined, 'Pratos'),
        _sidebarTile(3, Icons.account_balance_wallet_outlined, 'Wallet'),
        _sidebarTile(4, Icons.analytics_outlined, 'Receitas'),
        _sidebarTile(5, Icons.storefront_outlined, 'Perfil'),
        _sidebarTile(6, Icons.event_outlined, 'Eventos'),
      ],
    ),
  );

  Widget _sidebarTile(
    int index,
    IconData icon,
    String label, {
    int badgeCount = 0,
  }) {
    final active = _tab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primaryRed.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? AppColors.primaryRed.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: ListTile(
          leading: _badgeIcon(
            icon,
            count: badgeCount,
            iconColor: active ? Colors.white : Colors.white70,
          ),
          title: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white70,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          onTap: () => setState(() => _tab = index),
        ),
      ),
    );
  }

  Widget _darkCard({required Widget child}) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF11182B),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF1E2A44)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x22000000),
          blurRadius: 12,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );

  Widget _buildSectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: Colors.white54)),
    ],
  );

  Widget _filterChip(String label, bool selected, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: AppColors.primaryRed.withValues(alpha: 0.24),
          labelStyle: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w700,
          ),
          backgroundColor: const Color(0xFF11182B),
          side: BorderSide(
            color: selected ? AppColors.primaryRed : const Color(0xFF25314F),
          ),
        ),
      );

  Widget _buildTopMetrics() {
    final metrics = <Map<String, dynamic>>[
      {
        'title': 'Pedidos',
        'value': _orders.length.toString(),
        'icon': Icons.receipt_long_outlined,
        'color': const Color(0xFF5B8CFF),
      },
      {
        'title': 'Pratos',
        'value': _menuItems.length.toString(),
        'icon': Icons.restaurant_menu_outlined,
        'color': const Color(0xFF13C296),
      },
      {
        'title': 'Wallet',
        'value': _money(_walletBalance),
        'icon': Icons.account_balance_wallet_outlined,
        'color': const Color(0xFFFFB020),
      },
      {
        'title': 'Receita hoje',
        'value': _money(_todayRevenue),
        'icon': Icons.today_outlined,
        'color': AppColors.primaryRed,
      },
      {
        'title': 'Semana',
        'value': _money(_weekRevenue),
        'icon': Icons.date_range_outlined,
        'color': const Color(0xFF9C6BFF),
      },
      {
        'title': 'Mes',
        'value': _money(_monthRevenue),
        'icon': Icons.calendar_month_outlined,
        'color': const Color(0xFF00BCD4),
      },
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: metrics.map((metric) {
        final color = metric['color'] as Color;
        final icon = metric['icon'] as IconData;
        return SizedBox(
          width: 182,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            child: _darkCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      metric['title'].toString(),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      metric['value'].toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
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

  Widget _buildLivePanels() {
    final stockAlertText = _lowStockItems.isEmpty
        ? 'Nenhum prato abaixo de 10 unidades'
        : '${_lowStockItems.length} prato(s) abaixo de 10 unidades';
    final outText = _outOfStockItems.isEmpty
        ? 'Nenhum prato sem stock'
        : '${_outOfStockItems.length} prato(s) sem stock';
    final completedToday = _completedOrders.where((o) {
      final dt = (o.updatedAt ?? o.createdAt).toLocal();
      final now = _serverNowLocal;
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).length;
    final events = _liveEvents.isEmpty
        ? [
            <String, dynamic>{
              'title': 'Aguardando novos pedidos',
              'subtitle':
                  'O painel vai atualizar assim que entrar um pedido novo.',
              'priority': 'LOW',
            },
          ]
        : _liveEvents.take(4).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final left = _darkCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Painel ao vivo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                _liveMetric(
                  'Pedidos concluidos hoje',
                  completedToday.toString(),
                ),
                _liveMetric('Alertas de stock', stockAlertText),
                _liveMetric('Sem stock', outText),
              ],
            ),
          ),
        );
        final right = _darkCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Eventos websocket',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                ...events.map(
                  (event) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: event['priority'] == 'HIGH'
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event['title'].toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                event['subtitle'].toString(),
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        if (compact) {
          return Column(children: [left, const SizedBox(height: 12), right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _liveMetric(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildChartsPanel({bool expanded = false}) {
    final revenueSeries = _revenueSeries;
    final productsSeries = _productsSeries;
    final avgTicket = _completedOrders.isEmpty
        ? 0.0
        : _completedOrders.fold<double>(
                0,
                (sum, order) => sum + _restaurantSaleAmount(order),
              ) /
              _completedOrders.length;
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Graficos em tempo real',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Lucro, vendas e produtos com atualizacao visual continua.',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: expanded ? 180 : 140,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: Color(0xFF24314D), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: AppColors.primaryRed,
                      barWidth: 4,
                      dotData: const FlDotData(show: false),
                      spots: List.generate(
                        revenueSeries.length,
                        (index) =>
                            FlSpot(index.toDouble(), revenueSeries[index]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: expanded ? 140 : 100,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (productsSeries.reduce((a, b) => a > b ? a : b) + 5)
                      .clamp(10, 200),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: Color(0xFF24314D), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  barGroups: List.generate(
                    productsSeries.length,
                    (index) => BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: productsSeries[index],
                          color: const Color(0xFF13C296),
                          width: 18,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _liveMetric('Ticket medio', _money(avgTicket))),
                const SizedBox(width: 16),
                Expanded(
                  child: _liveMetric(
                    'Produtos ativos',
                    _menuItems
                        .where((e) => e.isAvailable && e.stockQuantity > 0)
                        .length
                        .toString(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    final isCompleted =
        order.status.value == 'completed' ||
        order.status.value == 'auto_completed';
    final isPaid = order.hasConfirmedPayment || order.fundsHeldInEscrow;
    final isPaymentSettled = order.isPaymentSettled;
    final paymentCompleted =
        isPaid ||
        order.status.value == 'paid' ||
        order.status.value == 'payment_authorized';
    final canConfirm =
        order.status.value == 'pending' ||
        order.status.value == 'paid' ||
        order.status.value == 'payment_authorized';
    final unreadChatCount = _unreadChatCountFor(order.id);
    final waitingConfirmation = _isAwaitingRestaurantConfirmation(order);
    final isArchivedPending = _archivedPendingOrderIds.contains(order.id);

    return _darkCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showOrderDetails(order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<List<OrderItem>>(
            future: _loadOrderItemsFor(order.id),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <OrderItem>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _orderHeadline(items),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        _money(order.totalAmount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusChip(order.status.value),
                    ],
                  ),
                  if (waitingConfirmation || unreadChatCount > 0) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (waitingConfirmation)
                          _orderSignalChip(
                            label: 'Aguardando confirmacao',
                            value: '3 min',
                            color: Colors.orangeAccent,
                          ),
                        if (unreadChatCount > 0)
                          GestureDetector(
                            onTap: () async {
                              await _markOrderChatNotificationsAsRead(order.id);
                              if (mounted) context.push('/chat/${order.id}');
                            },
                            child: _orderSignalChip(
                              label: 'Chat nao lido',
                              value: unreadChatCount.toString(),
                              color: Colors.lightBlueAccent,
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _formatDateTime(order.createdAt),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _deliveryDestinationLabel(order),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (items.isEmpty)
                    const Text(
                      'Itens indisponiveis no momento.',
                      style: TextStyle(color: Colors.white70),
                    )
                  else
                    _buildReadableOrderItemsPreview(items),
                  const SizedBox(height: 8),
                  _compactPaymentBadge(
                    isPaymentSettled
                        ? 'Pagamento concluido'
                        : isPaid
                        ? 'Pago'
                        : 'Pagamento pendente',
                    isPaid ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                  if (!isCompleted &&
                      (order.status.value == 'paid' ||
                          order.status.value == 'payment_authorized' ||
                          ((order.status.value == 'pending') &&
                              (order.paymentStatus == 'completed' ||
                                  order.paymentStatus == 'paid' ||
                                  order.paymentStatus == 'authorized')))) ...[
                    const SizedBox(height: 8),
                    _countdownPill(order),
                  ],
                  if (!isCompleted && canConfirm) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: paymentCompleted
                              ? FilledButton.icon(
                                  onPressed: _isSubmitting
                                      ? null
                                      : () => _changeStatus(
                                          context,
                                          order,
                                          'accepted',
                                          closeSheet: false,
                                        ),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Aceitar pedido'),
                                )
                              : OutlinedButton.icon(
                                  onPressed: null,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Aceitar pedido'),
                                ),
                        ),
                        if (waitingConfirmation) ...[
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => isArchivedPending
                                ? _restoreArchivedPendingOrder(order)
                                : _archivePendingOrder(order),
                            icon: Icon(
                              isArchivedPending
                                  ? Icons.undo_rounded
                                  : Icons.archive_outlined,
                            ),
                            label: Text(
                              isArchivedPending ? 'Restaurar' : 'Arquivar',
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!paymentCompleted) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Aguardando pagamento do cliente.',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                  if (!isCompleted) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OrderChatButton(
                          orderId: order.id,
                          onPressed: () async {
                            await _markOrderChatNotificationsAsRead(order.id);
                            if (mounted) context.push('/chat/${order.id}');
                          },
                          unreadCount: unreadChatCount,
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _showOrderDetails(order),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Detalhes'),
                        ),
                        if (order.isDelivery)
                          OutlinedButton.icon(
                            onPressed: () => context.push(
                              '/tracking/${order.id}?viewer=restaurant',
                            ),
                            icon: const Icon(Icons.route_outlined),
                            label: const Text('Ver rota'),
                          ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildReadableOrderItemsPreview(List<OrderItem> items) {
    final visibleItems = items.take(3).toList();
    return Column(
      children: [
        ...visibleItems.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  if (item.menuItem?.imageUrl != null &&
                      item.menuItem!.imageUrl!.trim().isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: item.menuItem!.imageUrl!,
                        width: 82,
                        height: 82,
                        fit: BoxFit.cover,
                        memCacheWidth: _cacheDimension(82),
                        memCacheHeight: _cacheDimension(82),
                        errorWidget: (_, _, _) => _square(size: 82),
                      ),
                    )
                  else
                    _square(size: 82),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.menuItem?.name ?? 'Item',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Quantidade ${item.quantity} • ${_money(item.unitPrice)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _money(item.subtotal),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (items.length > visibleItems.length)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '+${items.length - visibleItems.length} itens',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
      ],
    );
  }

  Widget _buildSwipeableOrderCard(Order order) {
    final waitingConfirmation = _isAwaitingRestaurantConfirmation(order);
    final isArchived = _archivedPendingOrderIds.contains(order.id);
    if (!waitingConfirmation || isArchived) {
      return _buildOrderCard(order);
    }

    return Dismissible(
      key: ValueKey('restaurant-pending-order-${order.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (!_isAwaitingRestaurantConfirmation(order)) return false;
        if (direction == DismissDirection.startToEnd) {
          if (_isSubmitting) return false;
          await _changeStatus(context, order, 'accepted', closeSheet: false);
          _showMessage('Pedido aceito');
          return false;
        }
        _archivePendingOrder(order);
        return false;
      },
      background: _swipeActionBackground(
        alignment: Alignment.centerLeft,
        color: AppColors.successGreen,
        icon: Icons.check_circle_outline,
        label: 'Aceitar',
      ),
      secondaryBackground: _swipeActionBackground(
        alignment: Alignment.centerRight,
        color: Colors.redAccent,
        icon: Icons.archive_outlined,
        label: 'Arquivar',
      ),
      child: _buildOrderCard(order),
    );
  }

  Widget _swipeActionBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    final isLeft = alignment == Alignment.centerLeft;
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: isLeft
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: [
          if (!isLeft)
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          if (!isLeft) const SizedBox(width: 8),
          Icon(icon, color: Colors.white),
          if (isLeft) const SizedBox(width: 8),
          if (isLeft)
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }

  void _archivePendingOrder(Order order) {
    if (!_isAwaitingRestaurantConfirmation(order)) return;
    setState(() {
      _archivedPendingOrderIds.add(order.id);
      if (_orderFilter == 'paid' && _awaitingConfirmationCount == 0) {
        _orderFilter = 'all';
      }
    });
    _showMessage('Pedido arquivado');
  }

  void _restoreArchivedPendingOrder(Order order) {
    setState(() {
      _archivedPendingOrderIds.remove(order.id);
      _orderFilter = 'paid';
    });
    _showMessage('Pedido voltou para pendentes');
  }

  // ignore: unused_element
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
                      memCacheWidth: _cacheDimension(44),
                      memCacheHeight: _cacheDimension(44),
                      errorWidget: (_, _, _) => _square(size: 44),
                    ),
                  )
                else
                  _square(size: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.menuItem?.name ?? 'Item',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Qtd ${item.quantity} · ${_money(item.unitPrice)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Text(
                  _money(item.subtotal),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
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
              style: const TextStyle(color: Colors.white70),
            ),
          ),
      ],
    );
  }

  Widget _orderSummaryChip({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          shadows: [
            Shadow(color: color.withValues(alpha: 0.3), blurRadius: 12),
          ],
        ),
      ),
    );
  }

  Widget _orderSignalChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _countdownPill(Order order) {
    final baseTime = order.restaurantConfirmationStartedAt;
    final deadline = baseTime.add(const Duration(minutes: 3));
    return _RestaurantCountdownPill(deadline: deadline);
  }

  Widget _buildDishCard(MenuItem item) {
    final status = item.stockQuantity <= 0 || !item.isAvailable
        ? 'closed'
        : item.stockQuantity < 10
        ? 'low_stock'
        : 'open';
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                item.imageUrl != null && item.imageUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: item.imageUrl!,
                          width: 58,
                          height: 58,
                          fit: BoxFit.cover,
                          memCacheWidth: _cacheDimension(58),
                          memCacheHeight: _cacheDimension(58),
                          errorWidget: (_, error, stackTrace) => _square(),
                        ),
                      )
                    : _square(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_money(item.price)} - Stock ${item.stockQuantity} - ${item.prepTimeMinutes} min',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showAddMenuItemDialog(item: item),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _confirmDeleteMenuItem(item),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Apagar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _financeRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5E4D), Color(0xFFD81B1B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _restaurantName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isOpen ? 'Disponivel no app' : 'Pausado no app',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _alertCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _completedOrderCard(Order order) {
    final completedAt = order.updatedAt ?? order.createdAt;
    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pedido finalizado com sucesso',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                _statusChip('completed'),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resumo rapido',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ultima entrega concluida em ${_formatDateTime(completedAt)}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    order.clientName?.trim().isNotEmpty == true
                        ? 'Cliente: ${order.clientName}'
                        : 'Cliente: visivel no detalhe do pedido',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<OrderItem>>(
              future: _loadOrderItemsFor(order.id),
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <OrderItem>[];
                return Text(
                  _orderHeadline(items),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            Text('Hora do pedido: ${_formatDateTime(order.createdAt)}'),
            const SizedBox(height: 6),
            Text('Hora da entrega: ${_formatDateTime(completedAt)}'),
            const SizedBox(height: 6),
            Text(_deliveryDestinationLabel(order)),
            const SizedBox(height: 6),
            Text('Total: ${_money(order.totalAmount)}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showOrderDetails(order),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Abrir pedido'),
                ),
                if ((order.status == OrderStatus.completed ||
                    order.status == OrderStatus.autoCompleted))
                  OutlinedButton.icon(
                    onPressed: () => _openCourierProfileForOrder(order),
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('Ver estafeta'),
                  ),
                OrderChatButton(
                  orderId: order.id,
                  onPressed: () async {
                    await _markOrderChatNotificationsAsRead(order.id);
                    if (mounted) context.push('/chat/${order.id}');
                  },
                  unreadCount: _unreadChatCountFor(order.id),
                  label: 'Ver chat',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _comboCard(Map<String, dynamic> combo) {
    final discount = ((combo['discount_percentage'] as num?)?.toDouble() ?? 0)
        .toStringAsFixed(0);
    final isCurrent = combo['is_currently_active'] == true;
    final start = DateTime.tryParse(combo['start_date']?.toString() ?? '');
    final end = DateTime.tryParse(combo['end_date']?.toString() ?? '');

    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${combo['title'] ?? 'Combo do Dia'} - $discount% OFF',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _statusChip(isCurrent ? 'open' : 'closed'),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              combo['description']?.toString() ??
                  'Desconto aplicado automaticamente no pedido.',
            ),
            const SizedBox(height: 8),
            Text(
              'Periodo: ${start == null ? '-' : _formatDateTime(start)} ate ${end == null ? '-' : _formatDateTime(end)}',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showCreateComboDialog(combo: combo),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await _restaurantService.updateDailyCombo(
                      comboId: combo['id'].toString(),
                      restaurantId: _restaurantId!,
                      isActive: !(combo['is_active'] == true),
                    );
                    if (!mounted) return;
                    if (ok) {
                      await _refreshMenuReviewsAndCombos();
                    }
                  },
                  icon: Icon(
                    combo['is_active'] == true
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                  ),
                  label: Text(
                    combo['is_active'] == true ? 'Desativar' : 'Ativar',
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final ok = await _restaurantService.deleteDailyCombo(
                      combo['id'].toString(),
                    );
                    if (!mounted) return;
                    if (ok) {
                      await _refreshMenuReviewsAndCombos();
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remover'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> review) {
    final reviewerName = review['reviewer_name']?.toString() ?? 'Cliente';
    final reviewerAvatarUrl = review['reviewer_avatar_url']?.toString();
    final itemName = review['menu_item_name']?.toString() ?? 'Prato';
    final itemImageUrl = review['menu_item_image_url']?.toString();
    final reviewImageUrl = review['image_url']?.toString();
    final comment = review['comment']?.toString() ?? 'Sem comentario';
    final createdAt = DateTime.tryParse(review['created_at']?.toString() ?? '');
    final rating = (review['rating'] as num?)?.toDouble() ?? 5;

    return _darkCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.red.shade50,
                  backgroundImage:
                      reviewerAvatarUrl != null && reviewerAvatarUrl.isNotEmpty
                      ? NetworkImage(reviewerAvatarUrl)
                      : null,
                  child:
                      (reviewerAvatarUrl == null || reviewerAvatarUrl.isEmpty)
                      ? Text(
                          _initials(reviewerName),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reviewerName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        createdAt == null ? '-' : _formatDateTime(createdAt),
                      ),
                    ],
                  ),
                ),
                _ratingPill(rating),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                itemImageUrl != null && itemImageUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: itemImageUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          memCacheWidth: _cacheDimension(60),
                          memCacheHeight: _cacheDimension(60),
                          errorWidget: (_, error, stackTrace) =>
                              _square(size: 60),
                        ),
                      )
                    : _square(size: 60),
                const SizedBox(width: 12),
                Expanded(child: Text('$itemName\n$comment')),
              ],
            ),
            if (reviewImageUrl != null && reviewImageUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  reviewImageUrl,
                  width: double.infinity,
                  height: 170,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stackTrace) => Container(
                    height: 110,
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    child: const Text(
                      'Nao foi possivel carregar a foto da review',
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showRestaurantNotifications() async {
    if (!mounted) return;
    final reviewItems = _reviews.take(4).toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryRed.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.notifications_active_outlined,
                        color: AppColors.primaryRed,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Notificacoes',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${_unreadRestaurantNotifications} nao lidas',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.neutralGray,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _unreadRestaurantNotifications == 0
                          ? null
                          : _markAllRestaurantNotificationsAsRead,
                      child: const Text('Marcar como lidas'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child:
                      (_restaurantNotifications.isEmpty && reviewItems.isEmpty)
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: _emptyCard(
                            'Ainda sem notificacoes para mostrar',
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            if (reviewItems.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'Reviews recentes',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              ...reviewItems.map(
                                (review) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _reviewNotificationTile(review),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (_restaurantNotifications.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'Notificacoes',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              ..._groupRestaurantNotificationsByDate().entries
                                  .expand(
                                    (entry) => [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 2,
                                          bottom: 8,
                                        ),
                                        child: _notificationDateHeader(
                                          entry.key,
                                          entry.value.length,
                                        ),
                                      ),
                                      ...entry.value.map(
                                        (notification) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 10,
                                          ),
                                          child: _restaurantNotificationTile(
                                            notification,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>>
  _groupRestaurantNotificationsByDate() {
    final groups = <String, List<Map<String, dynamic>>>{
      'Hoje': [],
      'Ontem': [],
      'Esta semana': [],
      'Mais antigas': [],
    };
    final now = _serverNow;
    final today = DateTime(now.year, now.month, now.day);
    for (final notification in _restaurantNotifications) {
      final parsed = DateTime.tryParse(
        notification['created_at']?.toString() ?? '',
      )?.toLocal();
      final day = parsed == null
          ? null
          : DateTime(parsed.year, parsed.month, parsed.day);
      final label = day == null
          ? 'Mais antigas'
          : day == today
          ? 'Hoje'
          : day == today.subtract(const Duration(days: 1))
          ? 'Ontem'
          : day.isAfter(today.subtract(const Duration(days: 7)))
          ? 'Esta semana'
          : 'Mais antigas';
      groups[label]!.add(notification);
    }
    groups.removeWhere((_, value) => value.isEmpty);
    return groups;
  }

  Widget _notificationDateHeader(String label, int count) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primaryRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryRed,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _markAllRestaurantNotificationsAsRead() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final readAt = _serverNowIsoUtc;
      await _supabase
          .from('push_notifications')
          .update({'read_at': readAt})
          .eq('user_id', user.id)
          .isFilter('read_at', null);
      if (!mounted) return;
      setState(() {
        _restaurantNotifications = _restaurantNotifications.map((notification) {
          if (notification['read_at'] != null) return notification;
          return {...notification, 'read_at': readAt};
        }).toList();
      });
    } catch (_) {}
  }

  Widget _restaurantNotificationTile(Map<String, dynamic> notification) {
    final type = notification['type']?.toString() ?? 'SYSTEM_ALERT';
    final title = _restaurantNotificationTitle(notification, type);
    final body = _restaurantNotificationBody(notification, type);
    final createdAt = DateTime.tryParse(
      notification['created_at']?.toString() ?? '',
    );
    final isUnread = notification['read_at'] == null;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        await NotificationRouterService().handleStoredNotificationTap(
          notification,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUnread
              ? AppColors.primaryRed.withValues(alpha: 0.05)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isUnread
                ? AppColors.primaryRed.withValues(alpha: 0.18)
                : AppColors.borderGray.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _notificationTone(type).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                _notificationIcon(type),
                color: _notificationTone(type),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(color: AppColors.neutralGray),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    createdAt == null ? '-' : _formatDateTime(createdAt),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.neutralGray,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _restaurantNotificationTitle(
    Map<String, dynamic> notification,
    String type,
  ) {
    if (type == 'DELIVERY_UNAVAILABLE') return 'Entrega indisponivel';
    return notification['title']?.toString() ?? 'DeliGo';
  }

  String _restaurantNotificationBody(
    Map<String, dynamic> notification,
    String type,
  ) {
    if (type == 'DELIVERY_UNAVAILABLE') {
      return 'O cliente pode tentar procurar novamente ou escolher levantar no restaurante.';
    }
    return notification['body']?.toString() ?? '';
  }

  Widget _reviewNotificationTile(Map<String, dynamic> review) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.of(context).pop();
        setState(() => _tab = 2);
      },
      child: _reviewCard(review),
    );
  }

  IconData _notificationIcon(String type) {
    switch (type) {
      case 'NEW_PAID_ORDER':
        return Icons.receipt_long_rounded;
      case 'ORDER_PICKED_UP':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_ARRIVED':
      case 'ORDER_DELIVERED':
        return Icons.delivery_dining_rounded;
      case 'MESSAGE_RECEIVED':
        return Icons.chat_bubble_outline_rounded;
      case 'ORDER_ACCEPTED':
      case 'ORDER_READY':
        return Icons.receipt_long_rounded;
      case 'ORDER_AUTO_COMPLETED':
        return Icons.task_alt_rounded;
      case 'PROMO_OFFER':
      case 'FREE_DELIVERY_PROMO':
        return Icons.local_offer_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color _notificationTone(String type) {
    switch (type) {
      case 'NEW_PAID_ORDER':
        return AppColors.primaryRed;
      case 'ORDER_PICKED_UP':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_ARRIVED':
      case 'ORDER_DELIVERED':
        return const Color(0xFF0EA5E9);
      case 'MESSAGE_RECEIVED':
        return const Color(0xFF8B5CF6);
      case 'ORDER_ACCEPTED':
      case 'ORDER_READY':
        return AppColors.successGreen;
      case 'ORDER_AUTO_COMPLETED':
        return AppColors.successGreen;
      case 'PROMO_OFFER':
      case 'FREE_DELIVERY_PROMO':
        return const Color(0xFFF97316);
      default:
        return AppColors.primaryRed;
    }
  }

  List<DeligoFoodCategory> _uniqueFoodCategories() {
    final seen = <String>{};
    return DeligoFoodCategories.list
        .where((category) {
          final key = category.label.trim().toLowerCase();
          return key.isNotEmpty && seen.add(key);
        })
        .toList(growable: false);
  }

  String _matchFoodCategory(
    String? rawValue,
    List<DeligoFoodCategory> options,
  ) {
    final normalized = rawValue?.trim().toLowerCase() ?? '';
    return options
        .firstWhere(
          (category) => category.label.trim().toLowerCase() == normalized,
          orElse: () => options.first,
        )
        .label;
  }

  Future<void> _showAddMenuItemDialog({MenuItem? item}) async {
    if (_restaurantId == null) return;

    final isEditing = item != null;
    final nameController = TextEditingController(text: item?.name ?? '');
    final descriptionController = TextEditingController(
      text: item?.description ?? '',
    );
    final priceController = TextEditingController(
      text: item != null ? item.price.toStringAsFixed(0) : '',
    );
    final stockController = TextEditingController(
      text: item?.stockQuantity.toString() ?? '10',
    );
    final ratingController = TextEditingController(
      text: item != null ? item.rating.toStringAsFixed(1) : '4.5',
    );
    final prepTimeController = TextEditingController(
      text:
          item?.prepTimeMinutes.toString() ??
          _restaurantDeliveryTime.toString(),
    );
    final categoryOptions = _uniqueFoodCategories();
    final initialCategory = _matchFoodCategory(item?.category, categoryOptions);
    final categoryController = TextEditingController(text: initialCategory);
    XFile? selectedImage;
    String? imageUrl = item?.imageUrl?.trim().isEmpty == false
        ? item!.imageUrl!.trim()
        : null;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          scrollable: true,
          title: Text(
            isEditing ? 'Editar prato' : 'Adicionar prato',
            style: const TextStyle(color: Colors.black87),
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField(nameController, 'Nome do prato'),
                  _buildTextField(descriptionController, 'Descricao'),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      value: categoryController.text,
                      decoration: InputDecoration(
                        labelText: 'Categoria',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: categoryOptions
                          .map(
                            (category) => DropdownMenuItem<String>(
                              value: category.label,
                              child: Row(
                                children: [
                                  Icon(
                                    category.icon,
                                    size: 18,
                                    color: category.color,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    category.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          categoryController.text = value;
                        }
                      },
                    ),
                  ),
                  _buildTextField(
                    priceController,
                    'Preco (MZN)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  _buildTextField(
                    stockController,
                    'Stock',
                    keyboardType: TextInputType.number,
                  ),
                  _buildTextField(
                    ratingController,
                    'Rating',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    readOnly: true,
                  ),
                  _buildTextField(
                    prepTimeController,
                    'Tempo de preparo (min)',
                    keyboardType: TextInputType.number,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Imagem do prato',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            selectedImage != null
                                ? selectedImage!.name
                                : imageUrl?.isNotEmpty == true
                                ? 'Imagem atual pronta para uso'
                                : 'Nenhuma imagem selecionada',
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _isSubmitting
                                    ? null
                                    : () async {
                                        final picked = await _imagePicker
                                            .pickImage(
                                              source: ImageSource.gallery,
                                              imageQuality: 85,
                                              maxWidth: 1600,
                                            );
                                        if (picked == null) return;
                                        setDialogState(
                                          () => selectedImage = picked,
                                        );
                                      },
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Escolher imagem'),
                              ),
                              if (imageUrl?.isNotEmpty == true ||
                                  selectedImage != null)
                                TextButton.icon(
                                  onPressed: _isSubmitting
                                      ? null
                                      : () => setDialogState(() {
                                          selectedImage = null;
                                          imageUrl = null;
                                        }),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Remover imagem'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: _isSubmitting
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final price =
                          double.tryParse(
                            priceController.text.trim().replaceAll(',', '.'),
                          ) ??
                          0;
                      final stock =
                          int.tryParse(stockController.text.trim()) ?? 0;
                      final rating =
                          double.tryParse(
                            ratingController.text.trim().replaceAll(',', '.'),
                          ) ??
                          4.5;
                      final prepTime =
                          int.tryParse(prepTimeController.text.trim()) ??
                          _restaurantDeliveryTime;

                      if (name.isEmpty || price <= 0) {
                        _showMessage(
                          'Preencha pelo menos o nome e um preco valido.',
                        );
                        return;
                      }

                      Navigator.of(dialogContext).pop();
                      setState(() => _isSubmitting = true);
                      try {
                        String? uploadedImageUrl = imageUrl;
                        if (selectedImage != null) {
                          uploadedImageUrl = await _restaurantService
                              .uploadRestaurantAsset(
                                file: selectedImage!,
                                ownerId: _supabase.auth.currentUser!.id,
                                folder: 'menu_items',
                              );
                        }

                        final ok = isEditing
                            ? await _restaurantService.updateMenuItem(
                                itemId: item.id,
                                restaurantId: _restaurantId!,
                                name: name,
                                price: price,
                                stockQuantity: stock,
                                prepTimeMinutes: prepTime,
                                description: descriptionController.text.trim(),
                                category: categoryController.text.trim(),
                                imageUrl: uploadedImageUrl,
                                updateImage:
                                    selectedImage != null || imageUrl == null,
                              )
                            : await _restaurantService.addMenuItem(
                                    restaurantId: _restaurantId!,
                                    name: name,
                                    price: price,
                                    stockQuantity: stock,
                                    prepTimeMinutes: prepTime,
                                    description: descriptionController.text
                                        .trim(),
                                    category: categoryController.text.trim(),
                                    imageUrl: uploadedImageUrl,
                                  ) !=
                                  null;

                        if (!mounted) return;
                        if (ok) {
                          SoundController.instance.play(AppSoundType.success);
                          try {
                            await _refreshMenuReviewsAndCombos();
                          } catch (error, stackTrace) {
                            // A gravação já foi confirmada; um erro no refresh
                            // não pode desmontar o dashboard nem abrir o
                            // ErrorWidget global.
                            debugPrint(
                              'Erro no refresh apos atualizar stock/prato: $error',
                            );
                            debugPrintStack(stackTrace: stackTrace);
                          }
                          _showMessage(
                            isEditing
                                ? 'Stock atualizado.'
                                : 'Prato criado com sucesso. Ja pode aparecer no menu.',
                          );
                        } else {
                          SoundController.instance.play(AppSoundType.error);
                          _showMessage(
                            isEditing
                                ? 'Nao foi possivel atualizar o prato agora.'
                                : 'Nao foi possivel criar o prato agora.',
                          );
                        }
                      } catch (error, stackTrace) {
                        debugPrint('Erro ao guardar stock/prato: $error');
                        debugPrintStack(stackTrace: stackTrace);
                        if (mounted) {
                          SoundController.instance.play(AppSoundType.error);
                          _showMessage(
                            'Nao foi possivel atualizar o stock. Tente novamente.',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isSubmitting = false);
                      }
                    },
              child: Text(isEditing ? 'Salvar prato' : 'Criar prato'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    stockController.dispose();
    ratingController.dispose();
    prepTimeController.dispose();
    categoryController.dispose();
  }

  Future<void> _showCreateComboDialog({Map<String, dynamic>? combo}) async {
    if (_restaurantId == null) return;

    final isEditing = combo != null;
    final titleController = TextEditingController(
      text: combo?['title']?.toString() ?? '',
    );
    final descriptionController = TextEditingController(
      text: combo?['description']?.toString() ?? '',
    );
    final discountController = TextEditingController(
      text: ((combo?['discount_percentage'] as num?)?.toDouble() ?? 15)
          .toStringAsFixed(0),
    );
    final now = _serverNowLocal;
    DateTime startDate =
        DateTime.tryParse(combo?['start_date']?.toString() ?? '') ?? now;
    DateTime endDate =
        DateTime.tryParse(combo?['end_date']?.toString() ?? '') ??
        now.add(const Duration(hours: 8));
    bool isActive = combo?['is_active'] == true || combo == null;

    String dateLabel(DateTime value) => _formatDateTime(value);

    Future<void> pickDateTime({
      required BuildContext dialogContext,
      required bool isStart,
      required StateSetter setDialogState,
    }) async {
      final seed = isStart ? startDate : endDate;
      final pickedDate = await showDatePicker(
        context: dialogContext,
        initialDate: seed,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 2),
      );
      if (pickedDate == null) return;
      if (!dialogContext.mounted) return;
      final pickedTime = await showTimePicker(
        context: dialogContext,
        initialTime: TimeOfDay.fromDateTime(seed),
      );
      if (pickedTime == null) return;
      final merged = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      setDialogState(() {
        if (isStart) {
          startDate = merged;
          if (!endDate.isAfter(startDate)) {
            endDate = startDate.add(const Duration(hours: 4));
          }
        } else {
          endDate = merged.isAfter(startDate)
              ? merged
              : startDate.add(const Duration(hours: 4));
        }
      });
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Editar combo' : 'Criar combo'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField(titleController, 'Titulo do combo'),
                  _buildTextField(descriptionController, 'Descricao'),
                  _buildTextField(
                    discountController,
                    'Desconto (%)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  SwitchListTile.adaptive(
                    value: isActive,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Combo ativo'),
                    subtitle: const Text(
                      'Mostra o combo na vitrine quando ativo.',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => isActive = value),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inicio'),
                    subtitle: Text(dateLabel(startDate)),
                    trailing: const Icon(Icons.event_outlined),
                    onTap: () => pickDateTime(
                      dialogContext: dialogContext,
                      isStart: true,
                      setDialogState: setDialogState,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fim'),
                    subtitle: Text(dateLabel(endDate)),
                    trailing: const Icon(Icons.event_available_outlined),
                    onTap: () => pickDateTime(
                      dialogContext: dialogContext,
                      isStart: false,
                      setDialogState: setDialogState,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: _isSubmitting
                  ? null
                  : () async {
                      final title = titleController.text.trim();
                      final description = descriptionController.text.trim();
                      final discount =
                          double.tryParse(
                            discountController.text.trim().replaceAll(',', '.'),
                          ) ??
                          0;

                      if (title.isEmpty ||
                          description.isEmpty ||
                          discount <= 0) {
                        _showMessage(
                          'Preencha titulo, descricao e desconto valido.',
                        );
                        return;
                      }

                      Navigator.of(dialogContext).pop();
                      setState(() => _isSubmitting = true);
                      try {
                        final ok = isEditing
                            ? await _restaurantService.updateDailyCombo(
                                comboId: combo['id'].toString(),
                                restaurantId: _restaurantId!,
                                title: title,
                                description: description,
                                discountPercentage: discount,
                                startDate: startDate,
                                endDate: endDate,
                                isActive: isActive,
                              )
                            : await _restaurantService.createDailyCombo(
                                restaurantId: _restaurantId!,
                                title: title,
                                description: description,
                                discountPercentage: discount,
                                startDate: startDate,
                                endDate: endDate,
                                isActive: isActive,
                              );

                        if (!mounted) return;
                        if (ok) {
                          SoundController.instance.play(AppSoundType.success);
                          await _refreshMenuReviewsAndCombos();
                          _showMessage(
                            isEditing
                                ? 'Combo atualizado. Ja pode destacar na vitrine.'
                                : 'Combo criado com sucesso. Ja pode destacar na vitrine.',
                          );
                        } else {
                          SoundController.instance.play(AppSoundType.error);
                          _showMessage(
                            isEditing
                                ? 'Nao foi possivel atualizar o combo agora.'
                                : 'Nao foi possivel criar o combo agora.',
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _isSubmitting = false);
                      }
                    },
              child: Text(isEditing ? 'Salvar combo' : 'Criar combo'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteMenuItem(MenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apagar prato'),
        content: Text('Tem certeza que deseja apagar "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      final ok = await _restaurantService.deleteMenuItem(
        item.id,
        restaurantId: _restaurantId!,
      );
      if (!mounted) return;
      if (ok) {
        SoundController.instance.play(AppSoundType.success);
        await _refreshMenuReviewsAndCombos();
        _showMessage('Prato removido com sucesso do menu.');
      } else {
        SoundController.instance.play(AppSoundType.error);
        _showMessage('Nao foi possivel remover o prato agora.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _toggleRestaurantOpenState() async {
    if (_restaurantId == null) return;

    setState(() => _isSubmitting = true);
    try {
      final nextValue = !_isOpen;
      final ok = await _restaurantService.updateRestaurant(
        restaurantId: _restaurantId!,
        isOpen: nextValue,
      );
      if (!mounted) return;
      if (ok) {
        setState(() => _isOpen = nextValue);
        _showMessage(
          nextValue
              ? 'Restaurante marcado como aberto.'
              : 'Restaurante marcado como fechado.',
        );
      } else {
        _showMessage('Nao foi possivel atualizar o estado do restaurante.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showPromoteRestaurantDialog() async {
    if (_restaurantId == null) return;

    final previewRestaurant = Restaurant(
      id: _restaurantId!,
      ownerId: _supabase.auth.currentUser?.id ?? '',
      name: _restaurantName,
      address: _restaurantAddress,
      latitude: _restaurantLatitude,
      longitude: _restaurantLongitude,
      neighborhood: _restaurantNeighborhood,
      city: _restaurantCity,
      isOpen: _isOpen,
      createdAt: _serverNowLocal,
      description: _restaurantDescription,
      phone: _restaurantPhone,
      deliveryTime: _restaurantDeliveryTime,
      imageUrl: _restaurantImageUrl,
    );
    final invite = _restaurantShareService.buildPreviewInvite(
      restaurant: previewRestaurant,
      topDishName: _menuItems.isNotEmpty ? _menuItems.first.name : null,
    );
    final publicLink = _publicShareService.restaurantLink(_restaurantId!);
    final publicMessage = _publicShareService.restaurantMessage(
      restaurantName: _restaurantName,
      link: publicLink,
    );
    final topDish = _menuItems.isNotEmpty ? _menuItems.first : null;
    final dishLink = topDish == null
        ? null
        : _publicShareService.dishLink(
            restaurantId: _restaurantId!,
            dishId: topDish.id,
          );
    final dishMessage = topDish == null || dishLink == null
        ? null
        : _publicShareService.dishMessage(
            dishName: topDish.name,
            restaurantName: _restaurantName,
            link: dishLink,
          );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Promover restaurante'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  invite.marketingCopy,
                  style: const TextStyle(height: 1.45),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.borderGray),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Top prato do dia',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _menuItems.isNotEmpty
                            ? _menuItems.first.name
                            : 'Prato em destaque',
                      ),
                      const SizedBox(height: 10),
                      Text('Link com tracking: ${invite.magicLink}'),
                      const SizedBox(height: 8),
                      Text('Link publico: $publicLink'),
                      if (dishLink != null) ...[
                        const SizedBox(height: 6),
                        Text('Link do prato: $dishLink'),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar copy'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: invite.marketingCopy),
                        );
                        if (!mounted) return;
                        _showMessage('Copy promocional copiada.');
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Copiar link'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: invite.magicLink),
                        );
                        if (!mounted) return;
                        _showMessage('Link promocional copiado.');
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.chat, size: 18),
                      label: const Text('WhatsApp'),
                      onPressed: () => _openExternalShare(
                        Uri.parse(
                          'https://wa.me/?text=${Uri.encodeComponent(invite.marketingCopy)}',
                        ),
                        fallbackText: invite.marketingCopy,
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.storefront_outlined, size: 18),
                      label: const Text('Perfil publico'),
                      onPressed: () => _openExternalShare(
                        Uri.parse(
                          'https://wa.me/?text=${Uri.encodeComponent(publicMessage)}',
                        ),
                        fallbackText: publicMessage,
                      ),
                    ),
                    if (dishMessage != null)
                      ActionChip(
                        avatar: const Icon(Icons.fastfood_outlined, size: 18),
                        label: const Text('Prato'),
                        onPressed: () => _openExternalShare(
                          Uri.parse(
                            'https://wa.me/?text=${Uri.encodeComponent(dishMessage)}',
                          ),
                          fallbackText: dishMessage,
                        ),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.facebook, size: 18),
                      label: const Text('Facebook'),
                      onPressed: () => _openExternalShare(
                        Uri.parse(
                          'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(invite.magicLink)}',
                        ),
                        fallbackText: invite.marketingCopy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternalShare(
    Uri uri, {
    required String fallbackText,
  }) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !mounted) return;
    await Clipboard.setData(ClipboardData(text: fallbackText));
    _showMessage('Nao abriu o app externo. Texto copiado.');
  }

  Future<void> _showEditRestaurantProfileDialog() async {
    if (_restaurantId == null) return;

    final nameController = TextEditingController(text: _restaurantName);
    final categoryOptions = _uniqueFoodCategories();
    final categoryController = TextEditingController(
      text: _matchFoodCategory(_restaurantCategory, categoryOptions),
    );
    final neighborhoodController = TextEditingController(
      text: _restaurantNeighborhood,
    );
    final cityController = TextEditingController(text: _restaurantCity);
    final referenceController = TextEditingController(
      text: _restaurantLandmarkReference,
    );
    final addressController = TextEditingController(text: _restaurantAddress);
    final descriptionController = TextEditingController(
      text: _restaurantDescription,
    );
    final phoneController = TextEditingController(text: _restaurantPhone);
    final deliveryController = TextEditingController(
      text: _restaurantDeliveryTime.toString(),
    );
    LatLng? selectedLocation =
        (_restaurantLatitude != null && _restaurantLongitude != null)
        ? LatLng(_restaurantLatitude!, _restaurantLongitude!)
        : null;
    XFile? selectedHeroImage;
    bool resolvingLocation = false;
    String? heroImageUrl = _restaurantImageUrl.trim().isEmpty
        ? null
        : _restaurantImageUrl.trim();
    String priceRange = _restaurantPriceRange.trim().isEmpty
        ? '\$\$'
        : _restaurantPriceRange.trim();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Editar restaurante'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField(nameController, 'Nome do restaurante'),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Imagem de capa',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            selectedHeroImage != null
                                ? selectedHeroImage!.name
                                : heroImageUrl?.isNotEmpty == true
                                ? 'Capa atual pronta para uso'
                                : 'Nenhuma capa selecionada',
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _isSubmitting
                                    ? null
                                    : () async {
                                        final picked = await _imagePicker
                                            .pickImage(
                                              source: ImageSource.gallery,
                                              imageQuality: 85,
                                              maxWidth: 1800,
                                            );
                                        if (picked == null) return;
                                        setDialogState(
                                          () => selectedHeroImage = picked,
                                        );
                                      },
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Escolher da galeria'),
                              ),
                              if (heroImageUrl?.isNotEmpty == true ||
                                  selectedHeroImage != null)
                                TextButton.icon(
                                  onPressed: _isSubmitting
                                      ? null
                                      : () => setDialogState(() {
                                          selectedHeroImage = null;
                                          heroImageUrl = null;
                                        }),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Remover capa'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      value: categoryController.text,
                      decoration: InputDecoration(
                        labelText: 'Categoria',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: categoryOptions
                          .map(
                            (category) => DropdownMenuItem<String>(
                              value: category.label,
                              child: Row(
                                children: [
                                  Icon(
                                    category.icon,
                                    size: 18,
                                    color: category.color,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    category.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          categoryController.text = value;
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      margin: EdgeInsets.zero,
                      color: const Color(0xFFF7F7FB),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Localizacao precisa',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              selectedLocation == null
                                  ? 'Escolha no mapa para preencher avenida, cidade e endereco automaticamente. A referencia continua manual.'
                                  : resolvingLocation
                                  ? 'A obter o endereco desta localizacao...'
                                  : 'Lat ${selectedLocation!.latitude.toStringAsFixed(5)}, Lng ${selectedLocation!.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(
                                color: AppColors.neutralGray,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: resolvingLocation
                                  ? null
                                  : () async {
                                      setDialogState(
                                        () => resolvingLocation = true,
                                      );
                                      try {
                                        final picked =
                                            await _pickRestaurantLocationOnMap(
                                              initial: selectedLocation,
                                            );
                                        if (picked == null || !mounted) return;
                                        final avenue =
                                            (picked.route?.trim().isNotEmpty ==
                                                        true
                                                    ? picked.route
                                                    : picked.street)
                                                ?.trim() ??
                                            picked.neighborhood?.trim() ??
                                            '';
                                        final city = picked.city?.trim() ?? '';
                                        final completeAddress =
                                            picked.formattedAddress
                                                .trim()
                                                .isNotEmpty
                                            ? picked.formattedAddress.trim()
                                            : [avenue, city]
                                                  .where(
                                                    (part) => part.isNotEmpty,
                                                  )
                                                  .join(', ');
                                        setDialogState(() {
                                          selectedLocation = picked.position;
                                          neighborhoodController.text = avenue;
                                          cityController.text = city;
                                          addressController.text =
                                              completeAddress;
                                        });
                                        if (avenue.isEmpty &&
                                            city.isEmpty &&
                                            completeAddress.isEmpty &&
                                            mounted) {
                                          ScaffoldMessenger.of(context)
                                            ..hideCurrentSnackBar()
                                            ..showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Coordenadas guardadas. Preencha o endereco manualmente porque o servico nao devolveu o endereco.',
                                                ),
                                              ),
                                            );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setDialogState(
                                            () => resolvingLocation = false,
                                          );
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.map_outlined),
                              label: Text(
                                resolvingLocation
                                    ? 'A obter endereco...'
                                    : 'Escolher no mapa',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _buildTextField(neighborhoodController, 'Avenida'),
                  _buildTextField(cityController, 'Cidade'),
                  _buildTextField(referenceController, 'Referencia conhecida'),
                  _buildTextField(addressController, 'Endereco completo'),
                  _buildTextField(
                    deliveryController,
                    'Tempo medio de preparacao (min)',
                    keyboardType: TextInputType.number,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      initialValue: priceRange,
                      decoration: InputDecoration(
                        labelText: 'Faixa de preco',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: '\$', child: Text('Economico')),
                        DropdownMenuItem(
                          value: '\$\$',
                          child: Text('Preco medio'),
                        ),
                        DropdownMenuItem(
                          value: '\$\$\$',
                          child: Text('Premium'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) priceRange = value;
                      },
                    ),
                  ),
                  _buildTextField(
                    phoneController,
                    'Numero de contacto (bloqueado)',
                    readOnly: true,
                  ),
                  _buildTextField(descriptionController, 'Descricao'),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: _isSubmitting
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final delivery =
                          int.tryParse(deliveryController.text.trim()) ?? 25;
                      if (name.isEmpty) {
                        _showMessage('O nome do restaurante e obrigatorio.');
                        return;
                      }

                      Navigator.of(dialogContext).pop();
                      setState(() => _isSubmitting = true);
                      try {
                        String? uploadedHeroUrl = heroImageUrl;
                        if (selectedHeroImage != null) {
                          uploadedHeroUrl = await _restaurantService
                              .uploadRestaurantAsset(
                                file: selectedHeroImage!,
                                ownerId: _supabase.auth.currentUser!.id,
                                folder: 'restaurant_hero',
                              );
                        }
                        final ok = await _restaurantService.updateRestaurant(
                          restaurantId: _restaurantId!,
                          name: name,
                          category: categoryController.text.trim(),
                          imageUrl: uploadedHeroUrl,
                          neighborhood: neighborhoodController.text.trim(),
                          city: cityController.text.trim(),
                          landmarkReference: referenceController.text.trim(),
                          address: addressController.text.trim(),
                          estimatedDeliveryTime: delivery,
                          priceRange: priceRange,
                          phone: phoneController.text.trim(),
                          paymentWalletNumber: _restaurantPaymentWalletNumber,
                          description: descriptionController.text.trim(),
                          latitude: selectedLocation?.latitude,
                          longitude: selectedLocation?.longitude,
                        );

                        if (!mounted) return;
                        if (ok) {
                          SoundController.instance.play(AppSoundType.success);
                          await _refreshRestaurantSnapshot();
                          _showMessage('Perfil do restaurante atualizado.');
                        } else {
                          SoundController.instance.play(AppSoundType.error);
                          _showMessage('Nao foi possivel atualizar o perfil.');
                        }
                      } finally {
                        if (mounted) setState(() => _isSubmitting = false);
                      }
                    },
              child: const Text('Salvar alteracoes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<LocationAddressDetails?> _pickRestaurantLocationOnMap({
    LatLng? initial,
  }) async {
    final seed = initial ?? const LatLng(-25.9655, 32.5832);
    if (!mounted) return null;
    return Navigator.of(context).push<LocationAddressDetails>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          initialPosition: seed,
          title: 'Localizacao da loja',
          confirmLabel: 'Confirmar localizacao',
          useCurrentLocationOnStart: initial == null,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _logout() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  Future<Map<String, String?>> _fetchClientProfileSummary(Order order) async {
    final clientId = order.clientId.trim();
    if (clientId.isEmpty) {
      return const {'full_name': null, 'gender': null, 'phone': null};
    }

    try {
      final profile = await _supabase.rpc(
        'get_order_client_contact',
        params: {'p_order_id': order.id},
      );
      if (profile is Map) {
        return {
          'full_name': profile['full_name']?.toString(),
          'gender': profile['gender']?.toString(),
          'phone': profile['phone']?.toString(),
        };
      }
    } catch (_) {}

    try {
      final profile = await _supabase
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

  Future<void> _callPhoneNumber(String rawPhone) async {
    final trimmed = rawPhone.trim();
    if (trimmed.isEmpty) {
      _showMessage('Numero do cliente indisponivel.');
      return;
    }

    final uri = Uri(
      scheme: 'tel',
      path: trimmed.replaceAll(RegExp(r'[^0-9+]'), ''),
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showMessage('Nao foi possivel abrir a chamada agora.');
    }
  }

  Future<void> _showOrderDetails(Order order) async {
    final isPaymentSettled = order.isPaymentSettled;
    final paymentCompleted =
        order.hasConfirmedPayment ||
        order.fundsHeldInEscrow ||
        order.status.value == 'paid' ||
        order.status.value == 'payment_authorized';
    final paymentPending = !paymentCompleted;
    final items = await _orderService.getOrderItems(order.id);
    final clientProfile = await _fetchClientProfileSummary(order);
    final clientFullName = clientProfile['full_name']?.trim().isNotEmpty == true
        ? clientProfile['full_name']!.trim()
        : (order.clientName?.trim().isNotEmpty == true
              ? order.clientName!.trim()
              : 'Cliente nao identificado');
    final clientGender = clientProfile['gender']?.trim().isNotEmpty == true
        ? clientProfile['gender']!.trim()
        : 'Nao informado';
    final clientPhone = clientProfile['phone']?.trim().isNotEmpty == true
        ? clientProfile['phone']!.trim()
        : 'Nao informado';
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + mediaQuery.viewInsets.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pedido #${order.id.substring(0, 8)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_unreadChatCountFor(order.id) > 0) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.blueGrey.shade100),
                      ),
                      child: Text(
                        'Mensagens novas: ${_unreadChatCountFor(order.id)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(_formatDateTime(order.createdAt)),
                  const SizedBox(height: 6),
                  Text(
                    LocationDisplay.displayAddress(
                      address: order.deliveryAddress,
                      fallback: 'Endereco do cliente confirmado no mapa',
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
                        if (clientPhone != 'Nao informado') ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => _callPhoneNumber(clientPhone),
                            icon: const Icon(Icons.call_outlined),
                            label: const Text('Ligar para cliente'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isPaymentSettled)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pagamento concluido',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'O pedido ja foi fechado e o valor deste pedido ja foi liquidado para o restaurante.',
                          ),
                        ],
                      ),
                    ),
                  if (isPaymentSettled) const SizedBox(height: 12),
                  if (paymentCompleted &&
                      (order.status.value == 'pending' ||
                          order.status.value == 'paid' ||
                          order.status.value == 'payment_authorized'))
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tempo para confirmar',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          _countdownPill(order),
                          const SizedBox(height: 6),
                          const Text(
                            'Se o tempo terminar, o pedido e cancelado e o valor volta ao cliente.',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (order.status.value == 'paid' ||
                      order.status.value == 'payment_authorized')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aguardando a sua confirmacao',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'O cliente ja pagou. Aceite o pedido para iniciar o preparo e liberar o fluxo operacional.',
                          ),
                        ],
                      ),
                    ),
                  if (order.status.value == 'accepted' ||
                      order.status.value == 'preparing' ||
                      order.status.value == 'ready')
                    Builder(
                      builder: (context) {
                        final isPickup = order.deliveryFee <= 0;
                        final prepMinutes =
                            order.estimatedPreparationMinutes <= 0
                            ? 25
                            : order.estimatedPreparationMinutes;
                        final prepReadyAt = order.preparationReference.add(
                          Duration(minutes: prepMinutes),
                        );
                        final remaining = prepReadyAt.difference(_serverNow);
                        final initialSeconds = remaining.inSeconds > 0
                            ? remaining.inSeconds
                            : 0;
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.indigo.shade100),
                          ),
                          child: TweenAnimationBuilder<int>(
                            key: ValueKey(
                              'prep-${order.id}-${order.preparationReference.millisecondsSinceEpoch}',
                            ),
                            tween: IntTween(begin: initialSeconds, end: 0),
                            duration: Duration(seconds: initialSeconds),
                            onEnd: () {
                              if (order.status.value != 'ready' &&
                                  !_autoReadyTriggeredOrderIds.contains(
                                    order.id,
                                  )) {
                                _autoReadyTriggeredOrderIds.add(order.id);
                                _changeStatus(
                                  context,
                                  order,
                                  'ready',
                                  closeSheet: true,
                                );
                              }
                            },
                            builder: (context, value, _) {
                              final minutes = value ~/ 60;
                              final seconds = value % 60;
                              final clock =
                                  '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
                              final phaseLabel = _prepPhaseLabel(
                                value,
                                prepMinutes,
                              );
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Tempo estimado do preparo',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    clock,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    phaseLabel,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: value <= 0
                                          ? AppColors.successGreen
                                          : Colors.indigo,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _prepPhaseHelper(
                                      remainingSeconds: value,
                                      isPickup: isPickup,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 12),
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
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                                memCacheWidth: _cacheDimension(96),
                                memCacheHeight: _cacheDimension(96),
                              ),
                            )
                          : Container(
                              width: 96,
                              height: 96,
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
                  if (paymentPending)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade100),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pagamento ainda nao confirmado',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Enquanto o valor nao entrar, o pedido nao pode ser confirmado pelo restaurante.',
                          ),
                        ],
                      ),
                    ),
                  if (paymentCompleted &&
                      (order.status.value == 'pending' ||
                          order.status.value == 'paid' ||
                          order.status.value == 'payment_authorized'))
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade100),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pagamento confirmado em escrow',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'O valor do pedido ja ficou protegido em escrow. Quando o restaurante confirmar o recebimento, o preparo comeca imediatamente.',
                          ),
                        ],
                      ),
                    ),
                  if (paymentPending ||
                      (paymentCompleted &&
                          (order.status.value == 'pending' ||
                              order.status.value == 'paid')))
                    const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TapScale(
                        child: OrderChatButton(
                          orderId: order.id,
                          onPressed: () async {
                            await _markOrderChatNotificationsAsRead(order.id);
                            Navigator.of(context).pop();
                            if (mounted) this.context.push('/chat/${order.id}');
                          },
                          unreadCount: _unreadChatCountFor(order.id),
                        ),
                      ),
                      if (order.isDelivery)
                        TapScale(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              this.context.push(
                                '/tracking/${order.id}?viewer=restaurant',
                              );
                            },
                            icon: const Icon(Icons.route_outlined),
                            label: const Text('Ver rota'),
                          ),
                        ),
                      if ((order.deliveryType != 'pickup' ||
                              order.deliveryFee > 0) &&
                          (order.status == OrderStatus.completed ||
                              order.status == OrderStatus.autoCompleted))
                        TapScale(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await _openCourierProfileForOrder(order);
                            },
                            icon: const Icon(Icons.badge_outlined),
                            label: const Text('Ver estafeta'),
                          ),
                        ),
                      if (paymentCompleted &&
                          (order.status.value == 'pending' ||
                              order.status.value == 'paid' ||
                              order.status.value == 'payment_authorized'))
                        TapScale(
                          child: FilledButton.icon(
                            onPressed: _isSubmitting
                                ? null
                                : () => _changeStatus(
                                    context,
                                    order,
                                    'accepted',
                                    closeSheet: true,
                                  ),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Aceitar pedido'),
                          ),
                        ),
                      if (!paymentCompleted &&
                          (order.status.value == 'pending' ||
                              order.status.value == 'paid' ||
                              order.status.value == 'payment_authorized'))
                        TapScale(
                          child: OutlinedButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Aceitar pedido'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _orderHeadline(List<OrderItem> items) {
    if (items.isEmpty) return 'Pedido DeliGo';
    final names = items
        .map((item) => item.menuItem?.name?.trim() ?? '')
        .where((name) => name.isNotEmpty)
        .take(2)
        .toList();
    if (names.isEmpty) return 'Pedido DeliGo';
    if (items.length > 2) {
      return '${names.join(' + ')} +${items.length - 2}';
    }
    return names.join(' + ');
  }

  // ignore: unused_element
  String _orderDeliveryLabel(Order order) {
    final isPickup = order.deliveryType == 'pickup';
    if (isPickup) {
      final isCompleted =
          order.status == OrderStatus.completed ||
          order.status == OrderStatus.autoCompleted;
      return isCompleted
          ? 'Retirou no restaurante'
          : 'Levantamento no restaurante';
    }
    return 'Delivery • ${order.deliveryAddress}';
  }

  String _deliveryDestinationLabel(Order order) {
    final isPickup = order.deliveryType == 'pickup';
    if (isPickup) {
      final isCompleted =
          order.status == OrderStatus.completed ||
          order.status == OrderStatus.autoCompleted;
      return isCompleted
          ? 'Retirou no restaurante'
          : 'Levantamento no restaurante';
    }
    final destination = LocationDisplay.displayAddress(
      address: order.deliveryAddress,
      fallback: 'Endereco do cliente confirmado no mapa',
    );
    return 'Delivery • $destination';
  }

  Future<String?> _resolveCourierIdForOrder(Order order) async {
    final directCourierId = order.courierId?.trim() ?? '';
    if (directCourierId.isNotEmpty) {
      return directCourierId;
    }

    try {
      final delivery = await _supabase
          .from('deliveries')
          .select('courier_id')
          .eq('order_id', order.id)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final fallbackCourierId =
          delivery?['courier_id']?.toString().trim() ?? '';
      if (fallbackCourierId.isNotEmpty) {
        return fallbackCourierId;
      }
    } catch (_) {}

    try {
      final refreshedOrder = await _orderService.getOrderById(order.id);
      final refreshedCourierId = refreshedOrder?.courierId?.trim() ?? '';
      if (refreshedCourierId.isNotEmpty) {
        return refreshedCourierId;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _openCourierProfileForOrder(Order order) async {
    final courierId = await _resolveCourierIdForOrder(order);
    if (!mounted) return;
    if (courierId == null || courierId.isEmpty) {
      _showMessage('Ainda nao encontramos o estafeta real deste pedido.');
      return;
    }
    context.push('/courier/$courierId?orderId=${order.id}');
  }

  String _prepPhaseLabel(int remainingSeconds, int totalMinutes) {
    final totalSeconds = (totalMinutes <= 0 ? 25 : totalMinutes) * 60;
    if (remainingSeconds <= 0) return 'Pronto';
    final ratio = remainingSeconds / totalSeconds;
    if (ratio > 0.75) {
      return 'Em preparacao';
    }
    if (ratio > 0.50) return 'A cozinhar';
    if (ratio > 0.25) return 'Quase pronto';
    return 'Finalizando';
  }

  String _prepPhaseHelper({
    required int remainingSeconds,
    required bool isPickup,
  }) {
    if (remainingSeconds <= 0) {
      return isPickup
          ? 'Pedido pronto. O cliente ja pode levantar no restaurante.'
          : 'Pedido pronto. O estafeta ja pode levantar e iniciar a entrega.';
    }
    final phase = remainingSeconds;
    if (phase > 15 * 60) {
      return 'A cozinha ja comecou a preparar o pedido.';
    }
    if (phase > 10 * 60) {
      return 'O pedido esta a cozinhar e a avancar normalmente.';
    }
    if (phase > 5 * 60) {
      return 'O pedido esta quase pronto para seguir.';
    }
    return 'Ultimos minutos antes do pedido ficar pronto.';
  }

  Future<void> _changeStatus(
    BuildContext modalContext,
    Order order,
    String status, {
    bool closeSheet = false,
  }) async {
    if (closeSheet && Navigator.of(modalContext).canPop()) {
      Navigator.of(modalContext).pop();
    }
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final ok = await _orderService.updateOrderStatus(order.id, status);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _orders = _orders
              .map(
                (existing) => existing.id == order.id
                    ? Order(
                        id: existing.id,
                        clientId: existing.clientId,
                        restaurantId: existing.restaurantId,
                        status: OrderStatus.fromString(status),
                        totalAmount: existing.totalAmount,
                        deliveryFee: existing.deliveryFee,
                        deliveryAddress: existing.deliveryAddress,
                        deliveryType: existing.deliveryType,
                        paymentStatus: existing.paymentStatus,
                        estimatedPreparationMinutes:
                            existing.estimatedPreparationMinutes,
                        createdAt: existing.createdAt,
                        updatedAt: _serverNow,
                        preparationStartedAt: status == 'accepted'
                            ? (existing.preparationStartedAt ?? _serverNow)
                            : existing.preparationStartedAt,
                        courierId: existing.courierId,
                        scheduledFor: existing.scheduledFor,
                        groupCode: existing.groupCode,
                        comboId: existing.comboId,
                        comboTitle: existing.comboTitle,
                        comboDiscountPercentage:
                            existing.comboDiscountPercentage,
                        comboDiscountAmount: existing.comboDiscountAmount,
                        deliveryLatitude: existing.deliveryLatitude,
                        deliveryLongitude: existing.deliveryLongitude,
                        restaurantName: existing.restaurantName,
                        clientName: existing.clientName,
                      )
                    : existing,
              )
              .toList();
        });
        if (status == 'accepted') {
          _tab = 1;
          _orderFilter = 'preparing';
          SoundController.instance.orderAccepted();
        } else if (status == 'preparing' || status == 'ready') {
          SoundController.instance.preparing();
        } else {
          SoundController.instance.play(AppSoundType.success);
        }
        await _refreshOrdersAndBalance();
      } else {
        SoundController.instance.play(AppSoundType.error);
        _showMessage('Nao foi possivel atualizar o pedido.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _ratingPill(double rating) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 16, color: Colors.amber),
          const SizedBox(width: 4),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _profileHeroFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF745C), Color(0xFFD81B1B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.storefront_rounded, size: 54, color: Colors.white),
      ),
    );
  }

  Widget _profileLine(IconData icon, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primaryRed.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primaryRed, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFCBD5E1),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _profileMenuRow(IconData icon, String title, VoidCallback onTap) {
    return SizedBox(
      height: 46,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        dense: true,
        leading: Icon(icon, color: AppColors.darkGray, size: 21),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 21),
        onTap: onTap,
      ),
    );
  }

  Widget _compactPaymentBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    String label;
    switch (status) {
      case 'open':
        color = Colors.green;
        label = 'Disponivel';
        break;
      case 'closed':
        color = Colors.red;
        label = 'Pausado';
        break;
      case 'paid':
        color = Colors.green;
        label = 'Pago';
        break;
      case 'pending':
        color = Colors.amber;
        label = 'Pendente';
        break;
      case 'payment_authorized':
        color = Colors.green;
        label = 'Pago';
        break;
      case 'accepted':
        color = Colors.orange;
        label = 'Confirmado';
        break;
      case 'preparing':
        color = Colors.deepOrange;
        label = 'Delivery';
        break;
      case 'ready':
        color = Colors.amber;
        label = 'Pronto';
        break;
      case 'picked_up':
      case 'in_delivery':
      case 'in_transit':
      case 'on_the_way':
        color = Colors.deepOrange;
        label = 'Delivery';
        break;
      case 'awaiting_pickup_confirmation':
        color = Colors.purple;
        label = 'Levantamento';
        break;
      case 'courier_assigned':
        color = Colors.blue;
        label = 'Estafeta';
        break;
      case 'delivered':
        color = Colors.green;
        label = 'Retirado';
        break;
      case 'delivery_failed_otp':
        color = Colors.deepOrange;
        label = 'OTP falhou';
        break;
      case 'completed':
        color = Colors.green;
        label = 'Concluido';
        break;
      case 'auto_completed':
        color = Colors.green;
        label = 'Auto';
        break;
      case 'disputed':
        color = Colors.deepOrange;
        label = 'Disputa';
        break;
      case 'cancelled':
      case 'expired':
      case 'payment_failed':
      case 'refunded':
        color = Colors.red;
        label = 'Cancelado';
        break;
      default:
        color = Colors.grey;
        label = status;
        break;
    }
    final isCancelledStatus = {
      'cancelled',
      'expired',
      'payment_failed',
      'refunded',
    }.contains(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: isCancelledStatus ? FontWeight.w900 : FontWeight.w700,
          fontSize: isCancelledStatus ? 14 : 12,
        ),
      ),
    );
  }

  Widget _emptyCard(String text) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 18),
            child: child,
          ),
        );
      },
      child: _darkCard(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(text, textAlign: TextAlign.center)),
        ),
      ),
    );
  }

  Widget _square({double size = 56}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.image_outlined, color: Colors.grey.shade600),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y as $h:$min';
  }

  int _cacheDimension(double logicalPixels) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    return (logicalPixels * dpr).round();
  }

  String _money(double value) => '${value.toStringAsFixed(2)} MZN';

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'CL';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
