import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/theme/app_colors.dart';
import '../../services/payment_service.dart';
import '../../services/order_service.dart';
import '../../services/server_clock_service.dart';
import '../../services/sound_controller.dart';
import '../../shared/models/order.dart';
import '../../shared/location/location_picker_page.dart';
import '../../shared/utils/location_display.dart';
import '../../shared/utils/mozambique_time.dart';
import '../../shared/widgets/order_chat_button.dart';
import '../../shared/widgets/tap_scale.dart';

class OrderDetailsPage extends StatefulWidget {
  final String orderId;

  const OrderDetailsPage({super.key, required this.orderId});

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  static const Duration _popupDuration = Duration(milliseconds: 1000);

  final OrderService _orderService = OrderService();
  final PaymentService _paymentService = PaymentService();
  final SupabaseClient _supabase = Supabase.instance.client;

  RealtimeChannel? _orderChannel;
  RealtimeChannel? _itemsChannel;
  RealtimeChannel? _deliveryOtpChannel;
  RealtimeChannel? _notificationsChannel;

  Order? _order;
  List<OrderItem> _items = const [];
  List<Map<String, dynamic>> _events = const [];
  OrderStatus? _lastStatus;
  final Set<String> _shownLifecyclePopupKeys = {};

  bool _loading = true;
  String? _loadError;
  Future<void>? _loadInFlight;
  bool _reloadQueued = false;
  Timer? _realtimeLoadDebounce;
  bool _confirming = false;
  bool _convertingDelivery = false;
  bool _recoveringAssignedDelivery = false;
  bool _cancelling = false;
  bool _retryingPayment = false;
  bool _openingDispute = false;
  bool _regeneratingDeliveryOtp = false;
  bool _requestingMoreTime = false;
  bool _reportingDeliveryProblem = false;
  Timer? _clockTimer;
  DateTime _now = ServerClockService.instance.now();
  String? _deliveryOtpCode;
  String? _resolvedDeliveryAddress;
  Map<String, dynamic>? _courierMotionAssessment;

  bool get _isDelivery {
    if (_order == null) return true;
    // A delivery that timed out is still a delivery order financially, but its
    // execution method is now customer pickup. The tracker and action button
    // must use this same authoritative fulfillment method.
    if (_order!.isCustomerPickupFallback) return false;
    if (_order!.isPickup) return false;
    return (_order!.deliveryFee) > 0;
  }

  bool get _isOrderFlowClosed {
    final status = _order?.status;
    return status == OrderStatus.delivered ||
        status == OrderStatus.completed ||
        status == OrderStatus.autoCompleted;
  }

  bool get _deliveryUnavailable {
    final status = _order?.deliveryStatus.trim().toLowerCase();
    final order = _order;
    final deadlineExpired =
        order?.dispatchExpiresAt != null &&
        !order!.dispatchExpiresAt!.toUtc().isAfter(_now.toUtc());
    return order != null &&
        order.isDelivery &&
        (status == 'delivery_unavailable' ||
            status == 'fallback' ||
            (status == 'searching' && deadlineExpired));
  }

  bool get _assignedCourierHasNotPickedUp {
    final order = _order;
    return order != null &&
        order.isDelivery &&
        order.status == OrderStatus.courierAssigned &&
        order.courierId?.trim().isNotEmpty == true &&
        order.pickedUpAt == null;
  }

  bool get _assignedCourierRecoveryDue {
    final serverAssessment = _courierMotionAssessment;
    if (serverAssessment != null) {
      return serverAssessment['recovery_due'] == true &&
          serverAssessment['state'] == 'no_progress_confirmed';
    }
    final assignedAt = _order?.courierAssignedAt ?? _order?.updatedAt;
    if (!_assignedCourierHasNotPickedUp || assignedAt == null) return false;
    return !_now.toUtc().isBefore(
      assignedAt.toUtc().add(const Duration(minutes: 5)),
    );
  }

  bool get _isAutoCancelledOrder {
    return _order?.status == OrderStatus.expired;
  }

  bool get _canShowCourierProfileAction {
    final order = _order;
    if (order == null || !order.isDelivery) {
      return false;
    }
    // The courier is relevant from assignment through completion. Before an
    // assignment there is no identity to expose; after a cancellation the
    // operational channel is closed.
    if (order.status == OrderStatus.pending ||
        order.status == OrderStatus.paymentAuthorized ||
        order.status == OrderStatus.paid ||
        order.status == OrderStatus.accepted ||
        order.status == OrderStatus.preparing ||
        order.status == OrderStatus.ready ||
        order.status == OrderStatus.cancelled ||
        order.status == OrderStatus.expired ||
        order.status == OrderStatus.paymentFailed ||
        order.status == OrderStatus.refunded) {
      return false;
    }
    final courierId = order.courierId?.trim() ?? '';
    return courierId.isNotEmpty;
  }

  bool get _canShowRestaurantAction {
    final order = _order;
    if (order == null || order.restaurantId.trim().isEmpty) return false;
    // The restaurant menu and public information are useful during every
    // order stage, including preparation and delivery tracking.
    return true;
  }

  bool get _canTrackOrder {
    final order = _order;
    if (order == null || !order.isDelivery) return false;
    return order.isOperationallyActive && !order.isCompletedState;
  }

  void _openRestaurantMenu() {
    final restaurantId = _order?.restaurantId.trim() ?? '';
    if (restaurantId.isEmpty) {
      _toast('Ainda nao encontramos o restaurante deste pedido.');
      return;
    }
    context.push('/restaurant/$restaurantId');
  }

  @override
  void initState() {
    super.initState();
    unawaited(_syncServerClock(force: true));
    _load();
    _subscribeRealtime();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = ServerClockService.instance.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _realtimeLoadDebounce?.cancel();
    _orderChannel?.unsubscribe();
    _itemsChannel?.unsubscribe();
    _deliveryOtpChannel?.unsubscribe();
    _notificationsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _subscribeRealtime() async {
    await _orderChannel?.unsubscribe();
    await _itemsChannel?.unsubscribe();
    await _deliveryOtpChannel?.unsubscribe();
    await _notificationsChannel?.unsubscribe();
    _orderChannel = _supabase.channel('order-details-${widget.orderId}');
    _orderChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.orderId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleRealtimeLoad();
          },
        )
        .subscribe();

    _itemsChannel = _supabase.channel('order-items-${widget.orderId}');
    _itemsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: widget.orderId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleRealtimeLoad();
          },
        )
        .subscribe();

    _deliveryOtpChannel = _supabase.channel('delivery-otp-${widget.orderId}');
    _deliveryOtpChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'delivery_otp_secrets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: widget.orderId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleRealtimeLoad();
          },
        )
        .subscribe();

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;

    _notificationsChannel = _supabase
        .channel('order-details-notifications-${widget.orderId}-$userId')
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
    if (_isOrderFlowClosed) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      return;
    }

    final title = notification['title']?.toString().trim().isNotEmpty == true
        ? notification['title']!.toString().trim()
        : 'Estafeta chegou ao restaurante';
    final body = notification['body']?.toString().trim().isNotEmpty == true
        ? notification['body']!.toString().trim()
        : 'O estafeta ja esta no restaurante para recolher o pedido.';

    _showStatusPopup(
      title: title,
      message: body,
      backgroundColor: const Color(0xFF0F766E),
      icon: Icons.storefront_rounded,
    );
  }

  Future<void> _syncServerClock({bool force = false}) async {
    await ServerClockService.instance.sync(force: force);
    if (!mounted) return;
    setState(() => _now = ServerClockService.instance.now());
  }

  void _scheduleRealtimeLoad() {
    _realtimeLoadDebounce?.cancel();
    _realtimeLoadDebounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) unawaited(_load(silent: true));
    });
  }

  Future<void> _load({bool silent = false}) {
    final active = _loadInFlight;
    if (active != null) {
      _reloadQueued = true;
      return active;
    }
    final future = _performLoad(silent: silent);
    _loadInFlight = future;
    return future.whenComplete(() {
      if (!identical(_loadInFlight, future)) return;
      _loadInFlight = null;
      if (_reloadQueued && mounted) {
        _reloadQueued = false;
        unawaited(_load(silent: true));
      }
    });
  }

  Future<void> _performLoad({required bool silent}) async {
    if (!silent && _order == null && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    final previousOrder = _order;
    try {
      await ServerClockService.instance.sync();
      if (!mounted) return;
      // getOrderById already performs the authoritative preparation sweep.
      // Load the order first, then its dependent snapshots concurrently.
      final order = await _orderService.getOrderById(
        widget.orderId,
        rethrowOnError: true,
      );
      if (order == null) {
        if (!mounted) return;
        setState(() {
          _order = null;
          _items = const [];
          _events = const [];
          _loading = false;
          _loadError = null;
        });
        return;
      }
      final dependent = await Future.wait<dynamic>([
        _orderService.getOrderItems(widget.orderId, rethrowOnError: true),
        _orderService.getOrderEvents(widget.orderId, rethrowOnError: true),
        _shouldLoadDeliveryOtp(order)
            ? _orderService.getDeliveryOtpCode(
                widget.orderId,
                rethrowOnError: true,
              )
            : Future<String?>.value(null),
        _assessCourierMotion(order),
      ]);
      if (!mounted) return;
      final previousStatus = _lastStatus;
      final nextStatus = order.status;
      final items = dependent[0] as List<OrderItem>;
      final events = dependent[1] as List<Map<String, dynamic>>;
      final deliveryOtpCode = dependent[2] as String?;
      final motionAssessment = dependent[3] as Map<String, dynamic>?;
      setState(() {
        _order = order;
        _items = items;
        _events = events;
        _loading = false;
        _loadError = null;
        _now = ServerClockService.instance.now();
        _lastStatus = nextStatus;
        _deliveryOtpCode = deliveryOtpCode;
        _courierMotionAssessment = motionAssessment;
      });
      unawaited(_resolveDeliveryAddressIfNeeded(order));
      _applyOrderStatusFeedback(previousOrder, order);
      final previousPaymentCaptured =
          previousOrder != null &&
          (previousOrder.hasConfirmedPayment ||
              previousOrder.fundsHeldInEscrow ||
              previousOrder.status == OrderStatus.paid ||
              previousOrder.status == OrderStatus.paymentAuthorized);
      if (previousStatus != null && nextStatus == OrderStatus.cancelled) {
        _toast(
          previousPaymentCaptured
              ? 'Pedido cancelado. O valor voltou para a sua conta.'
              : 'Pedido cancelado antes da confirmacao do pagamento.',
        );
      }
    } catch (error) {
      debugPrint('[ORDER_DETAILS_LOAD] orderId=${widget.orderId} error=$error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Não foi possível atualizar os dados do pedido.';
      });
    }
  }

  Future<Map<String, dynamic>?> _assessCourierMotion(Order order) async {
    if (!order.isDelivery ||
        order.courierId?.trim().isEmpty != false ||
        order.pickedUpAt != null ||
        order.status != OrderStatus.courierAssigned) {
      return null;
    }
    try {
      final response = await _supabase.rpc(
        'assess_courier_motion',
        params: {'p_order_id': order.id},
      );
      return response is Map ? Map<String, dynamic>.from(response) : null;
    } catch (error) {
      // Older environments without the local migration keep the existing
      // assignment-time fallback; they must never show a false recovery.
      debugPrint('[COURIER_MOTION] assessment unavailable: $error');
      return null;
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: _popupDuration,
        ),
      );
  }

  void _showStatusPopup({
    required String title,
    required String message,
    required Color backgroundColor,
    required IconData icon,
    Duration duration = _popupDuration,
  }) {
    if (!mounted) return;
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

  void _applyOrderStatusFeedback(Order? previousOrder, Order? nextOrder) {
    if (!mounted || previousOrder == null || nextOrder == null) return;
    if (previousOrder.id != nextOrder.id ||
        previousOrder.status == nextOrder.status) {
      return;
    }

    switch (nextOrder.status) {
      case OrderStatus.accepted:
      case OrderStatus.preparing:
        if (!_shownLifecyclePopupKeys.add('confirmed:${nextOrder.id}')) {
          break;
        }
        _showStatusPopup(
          title: 'Pedido confirmado',
          message: 'O restaurante confirmou o pedido e iniciou o preparo.',
          backgroundColor: AppColors.successGreen,
          icon: Icons.check_circle_outline_rounded,
        );
        break;
      case OrderStatus.ready:
      case OrderStatus.awaitingPickupConfirmation:
        if (!_shownLifecyclePopupKeys.add('ready:${nextOrder.id}')) {
          break;
        }
        _showStatusPopup(
          title: 'Pedido pronto para retirar',
          message: 'O pedido terminou o preparo e ja pode ser retirado.',
          backgroundColor: AppColors.primaryRed,
          icon: Icons.inventory_2_rounded,
        );
        break;
      case OrderStatus.courierAssigned:
        _showStatusPopup(
          title: 'Estafeta atribuido',
          message: 'Ja existe estafeta associado ao teu pedido.',
          backgroundColor: const Color(0xFF102A43),
          icon: Icons.delivery_dining_rounded,
          duration: _popupDuration,
        );
        break;
      case OrderStatus.inTransit:
      case OrderStatus.onTheWay:
        if (!_shownLifecyclePopupKeys.add('picked_up:${nextOrder.id}')) {
          break;
        }
        _showStatusPopup(
          title: 'Estafeta ja levantou o pedido',
          message: 'O teu codigo de entrega ja esta no app.',
          backgroundColor: const Color(0xFF102A43),
          icon: Icons.local_shipping_outlined,
        );
        break;
      case OrderStatus.arrived:
        _showStatusPopup(
          title: 'Estafeta chegou',
          message: 'O estafeta ja esta no destino.',
          backgroundColor: const Color(0xFF7C2D12),
          icon: Icons.place_rounded,
        );
        break;
      case OrderStatus.delivered:
        _showStatusPopup(
          title: 'Entrega validada',
          message: 'A entrega foi marcada como concluida no sistema.',
          backgroundColor: AppColors.successGreen,
          icon: Icons.task_alt_rounded,
        );
        break;
      case OrderStatus.disputed:
        _showStatusPopup(
          title: 'Pedido em disputa',
          message: 'O pedido entrou em disputa e sera analisado.',
          backgroundColor: Colors.orange.shade700,
          icon: Icons.gavel_rounded,
        );
        break;
      case OrderStatus.deliveryFailedOtp:
        _showStatusPopup(
          title: 'Falha no OTP',
          message: 'Houve falha na confirmacao OTP desta entrega.',
          backgroundColor: Colors.orange.shade700,
          icon: Icons.sms_failed_rounded,
        );
        break;
      case OrderStatus.cancelled:
      case OrderStatus.expired:
      case OrderStatus.paymentFailed:
        _showStatusPopup(
          title: 'Pedido cancelado',
          message: 'O pedido saiu do fluxo por cancelamento ou falha.',
          backgroundColor: Colors.orange.shade700,
          icon: Icons.cancel_outlined,
        );
        break;
      case OrderStatus.completed:
      case OrderStatus.autoCompleted:
        _showStatusPopup(
          title: 'Pedido concluido',
          message: 'O pedido foi fechado com sucesso.',
          backgroundColor: AppColors.successGreen,
          icon: Icons.check_circle_outline_rounded,
          duration: const Duration(milliseconds: 850),
        );
        break;
      default:
        break;
    }
  }

  void _applyLocalConfirmedState(String? statusValue) {
    final order = _order;
    if (order == null) return;
    final nextStatus = OrderStatus.fromString(statusValue ?? 'completed');
    if (nextStatus != OrderStatus.completed &&
        nextStatus != OrderStatus.autoCompleted) {
      return;
    }

    final updated = order.toMap()
      ..['status'] = nextStatus.value
      ..['payment_status'] = 'settled'
      ..['funds_status'] = 'released'
      ..['confirmed_by_customer'] = true
      ..['order_completed_at'] = DateTime.now().toUtc().toIso8601String()
      ..['settlement_processed_at'] = DateTime.now().toUtc().toIso8601String()
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();

    setState(() {
      _order = Order.fromMap(updated);
      _lastStatus = nextStatus;
    });
  }

  String _orderRef(String id) {
    final compact = id.replaceAll('-', '').toUpperCase();
    return '#${compact.length >= 8 ? compact.substring(0, 8) : compact}';
  }

  String _money(double value) => '${value.toStringAsFixed(2)} MZN';

  String _restaurantDisplayName(Order order) {
    final directName = order.restaurantName?.trim() ?? '';
    return directName.isNotEmpty ? directName : 'Restaurante';
  }

  String _displayDeliveryAddress(Order order) {
    if (!_isDelivery) {
      final isCompleted =
          order.status == OrderStatus.completed ||
          order.status == OrderStatus.autoCompleted;
      return isCompleted
          ? 'Retirou no restaurante'
          : 'Levantamento no restaurante';
    }
    final resolved = _resolvedDeliveryAddress?.trim() ?? '';
    if (resolved.isNotEmpty && _order?.id == order.id) {
      return resolved;
    }
    final rawAddress = order.deliveryAddress.trim();
    if (LocationDisplay.isCoordinateText(rawAddress) ||
        RegExp(r'^-?\d{1,3}(?:\.\d+)?$').hasMatch(rawAddress)) {
      return 'Localizacao da entrega';
    }
    return LocationDisplay.displayAddress(
      address: order.deliveryAddress,
      fallback: 'Localizacao da entrega',
    );
  }

  Future<void> _resolveDeliveryAddressIfNeeded(Order? order) async {
    if (!mounted || order == null || !_isDelivery) return;

    final rawAddress = order.deliveryAddress.trim();
    final isCoordinateOnly =
        LocationDisplay.isCoordinateText(rawAddress) ||
        RegExp(r'^-?\d{1,3}(?:\.\d+)?$').hasMatch(rawAddress);
    if (!isCoordinateOnly) {
      if (_resolvedDeliveryAddress != null && mounted) {
        setState(() => _resolvedDeliveryAddress = null);
      }
      return;
    }

    final latitude = order.deliveryLatitude;
    final longitude = order.deliveryLongitude;
    if (latitude == null || longitude == null) return;

    try {
      final details = await reverseGeocodeGoogle(LatLng(latitude, longitude));
      if (!mounted || _order?.id != order.id) return;

      final readableParts = <String>[
        (details?.street ?? details?.route ?? '').trim(),
        (details?.neighborhood ?? '').trim(),
        (details?.city ?? '').trim(),
      ].where((part) => part.isNotEmpty).toList();
      final readable = readableParts.isNotEmpty
          ? readableParts.join(', ')
          : (details?.formattedAddress.trim() ?? '');
      if (readable.isEmpty) return;

      setState(() => _resolvedDeliveryAddress = readable);
    } catch (error) {
      debugPrint('[ORDER_LOCATION] reverse geocode failed: $error');
    }
  }

  Future<String?> _resolveCourierId() async {
    final directCourierId = _order?.courierId?.trim() ?? '';
    if (directCourierId.isNotEmpty) {
      return directCourierId;
    }

    try {
      final delivery = await _supabase
          .from('deliveries')
          .select('courier_id')
          .eq('order_id', widget.orderId)
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
      final refreshedOrder = await _orderService.getOrderById(widget.orderId);
      final refreshedCourierId = refreshedOrder?.courierId?.trim() ?? '';
      if (refreshedCourierId.isNotEmpty) {
        return refreshedCourierId;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _openCourierProfile() async {
    final courierId = await _resolveCourierId();
    if (!mounted) return;
    if (courierId == null || courierId.isEmpty) {
      _toast('Ainda nao encontramos o estafeta real deste pedido.');
      return;
    }
    context.push('/courier/$courierId?orderId=${widget.orderId}');
  }

  bool get _paymentPendingOrder {
    final order = _order;
    if (order == null) return false;
    return order.status == OrderStatus.pending &&
        !order.hasConfirmedPayment &&
        !order.fundsHeldInEscrow;
  }

  Duration _remainingPendingPaymentTimeout(Order order) {
    final deadline = order.createdAt.add(const Duration(minutes: 15));
    final remaining = deadline.difference(_now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration _remainingRestaurantConfirmation(Order order) {
    final baseTime = order.restaurantConfirmationStartedAt;
    final deadline = baseTime.add(const Duration(minutes: 3));
    final remaining = deadline.difference(_now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration _remainingPreparation(Order order) {
    final startedAt = order.preparationReference;
    final deadline = startedAt.add(
      Duration(minutes: order.estimatedPreparationMinutes),
    );
    final remaining = deadline.difference(_now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  bool _shouldLoadDeliveryOtp(Order order) {
    if (!_isDelivery) return false;
    return order.status == OrderStatus.inTransit ||
        order.status == OrderStatus.arrived;
  }

  bool get _deliveryWaitingForCustomerAction {
    final order = _order;
    if (order == null || !_isDelivery) return false;
    return order.requiresCustomerAction || order.blocksSettlement;
  }

  DateTime? _deliveryAutoCloseDeadline(Order order) {
    if (!_isDelivery) return null;
    return order.autoCloseDeadline;
  }

  Duration _remainingDeliveryAutoClose(Order order) {
    final deadline = _deliveryAutoCloseDeadline(order);
    if (deadline == null) return Duration.zero;
    final remaining = deadline.difference(_now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get _canRequestMoreTime {
    final order = _order;
    if (order == null || !_isDelivery) return false;
    if (order.status != OrderStatus.delivered) return false;
    if (order.deliveryExtensionCount > 0) return false;
    return _remainingDeliveryAutoClose(order) > Duration.zero;
  }

  bool get _canReportDeliveryProblem {
    final order = _order;
    if (order == null || !_isDelivery) return false;
    if (order.status != OrderStatus.delivered) return false;
    return _remainingDeliveryAutoClose(order) > Duration.zero;
  }

  bool _pickupReadyByTime(Order order) {
    if (_isDelivery) return false;
    // The database status is authoritative. Do not expose pickup actions just
    // because a local countdown reached zero while the order is still
    // preparing; process_preparing_orders must first move it to ready.
    return order.status == OrderStatus.ready ||
        order.status == OrderStatus.awaitingPickupConfirmation;
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
      case OrderStatus.paymentAuthorized:
      case OrderStatus.paid:
        return Colors.orange;
      case OrderStatus.accepted:
      case OrderStatus.preparing:
      case OrderStatus.ready:
      case OrderStatus.awaitingPickupConfirmation:
        return AppColors.primaryRed;
      case OrderStatus.pickedUp:
      case OrderStatus.inDelivery:
      case OrderStatus.courierAssigned:
      case OrderStatus.inTransit:
      case OrderStatus.onTheWay:
      case OrderStatus.arrived:
        return Colors.blue;
      case OrderStatus.deliveryFailedOtp:
        return Colors.deepOrange;
      case OrderStatus.delivered:
        return AppColors.successGreen;
      case OrderStatus.disputed:
        return Colors.deepOrange;
      case OrderStatus.autoCompleted:
      case OrderStatus.refunded:
      case OrderStatus.completed:
        return AppColors.successGreen;
      case OrderStatus.expired:
      case OrderStatus.paymentFailed:
      case OrderStatus.cancelled:
        return AppColors.alertRed;
    }
  }

  String _statusText(OrderStatus status) {
    final order = _order;
    final hasAssignedCourier = order?.courierId?.trim().isNotEmpty == true;
    final dispatchActive =
        _isDelivery &&
        order?.dispatchAttemptId?.trim().isNotEmpty == true &&
        order?.dispatchExpiresAt?.toUtc().isAfter(_now.toUtc()) == true;
    final paymentCompleted =
        order != null && (order.hasConfirmedPayment || order.fundsHeldInEscrow);
    switch (status) {
      case OrderStatus.pending:
        return paymentCompleted
            ? 'Pago e a espera do restaurante'
            : 'Pagamento pendente';
      case OrderStatus.paymentAuthorized:
      case OrderStatus.paid:
        return 'Pago e a espera do restaurante';
      case OrderStatus.accepted:
        return 'Pedido recebido';
      case OrderStatus.preparing:
        return 'Em preparo';
      case OrderStatus.ready:
        if (dispatchActive && !hasAssignedCourier) return 'A procurar estafeta';
        return _isDelivery ? 'Pronto para entrega' : 'Pronto para levantamento';
      case OrderStatus.awaitingPickupConfirmation:
        return 'Aguardando retirada';
      case OrderStatus.pickedUp:
      case OrderStatus.inDelivery:
      case OrderStatus.courierAssigned:
        return hasAssignedCourier
            ? 'Estafeta atribuido'
            : 'Pronto para entrega';
      case OrderStatus.inTransit:
      case OrderStatus.onTheWay:
        return hasAssignedCourier ? 'Em rota' : 'Pronto para entrega';
      case OrderStatus.arrived:
        return 'Estafeta chegou';
      case OrderStatus.deliveryFailedOtp:
        return 'Entrega em revisao admin';
      case OrderStatus.delivered:
        return 'Aguardando sua confirmacao';
      case OrderStatus.disputed:
        return 'Problema reportado';
      case OrderStatus.autoCompleted:
        return 'Concluido automaticamente';
      case OrderStatus.completed:
        return 'Concluido';
      case OrderStatus.refunded:
        return 'Reembolsado';
      case OrderStatus.expired:
        return 'Expirado';
      case OrderStatus.paymentFailed:
        return 'Falha no pagamento';
      case OrderStatus.cancelled:
        return 'Cancelado';
    }
  }

  Future<void> _confirmDelivery() async {
    if (_confirming) return;
    setState(() => _confirming = true);
    var result = const DeliveryConfirmationResult(
      success: false,
      message:
          'Ainda nao foi possivel confirmar o recebimento. Tente novamente em instantes.',
    );
    try {
      result = await _orderService.confirmDeliveryDetailed(widget.orderId);
    } catch (e) {
      debugPrint('Erro ao confirmar recebimento: $e');
    }
    if (!mounted) return;
    setState(() => _confirming = false);
    if (result.success) {
      _applyLocalConfirmedState(result.status);
    }
    _toast(result.message);
    await _load(silent: true);
  }

  Future<void> _convertUnavailableDeliveryToPickup() async {
    if (_convertingDelivery || !_deliveryUnavailable) return;
    setState(() => _convertingDelivery = true);
    if (_order?.deliveryStatus.trim().toLowerCase() == 'searching') {
      await _orderService.expireDeliverySearchForCustomer(widget.orderId);
    }
    final result = await _orderService.convertUnavailableDeliveryToPickup(
      widget.orderId,
    );
    if (!mounted) return;
    setState(() => _convertingDelivery = false);
    _toast(result.message);
    if (result.success) await _load(silent: true);
  }

  Future<void> _chooseAssignedDeliveryRecovery() async {
    if (_recoveringAssignedDelivery || !_assignedCourierHasNotPickedUp) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'O estafeta ainda não recolheu o pedido',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('Escolha como pretende continuar.'),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => Navigator.pop(sheetContext, 'retry'),
                icon: const Icon(Icons.person_search_outlined),
                label: const Text('Procurar outro estafeta'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(sheetContext, 'pickup'),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Recolher no restaurante'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(sheetContext, 'cancel'),
                icon: const Icon(Icons.close, color: Colors.red),
                label: const Text(
                  'Cancelar pedido',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    String? replacementReason;
    if (action == 'retry') {
      replacementReason = await _showCourierReplacementReasonDialog();
      if (replacementReason == null || !mounted) return;
    }
    if (action == 'cancel') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cancelar pedido?'),
          content: const Text(
            'O reembolso será calculado conforme o estado do pedido.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmar cancelamento'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _recoveringAssignedDelivery = true);
    final result = await _orderService.recoverAssignedDelivery(
      orderId: widget.orderId,
      action: action,
      replacementReason: replacementReason,
    );
    if (!mounted) return;
    setState(() => _recoveringAssignedDelivery = false);
    _toast(result.message);
    if (result.success) await _load(silent: true);
  }

  Future<String?> _showCourierReplacementReasonDialog() async {
    const reasons = <String, String>{
      'no_movement': 'O estafeta não avançou',
      'gps_unavailable': 'A localização deixou de actualizar',
      'other_delay': 'Outro atraso na recolha',
    };
    String selected = reasons.keys.first;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Por que deseja outro estafeta?'),
          content: DropdownButtonFormField<String>(
            value: selected,
            decoration: const InputDecoration(
              labelText: 'Motivo obrigatório',
              border: OutlineInputBorder(),
            ),
            items: reasons.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => selected = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _regenerateDeliveryOtp() async {
    if (_regeneratingDeliveryOtp) return;
    setState(() => _regeneratingDeliveryOtp = true);
    final result = await _orderService.regenerateDeliveryOtp(widget.orderId);
    if (!mounted) return;
    setState(() => _regeneratingDeliveryOtp = false);
    _toast(result.message);
    await _load(silent: true);
  }

  Future<void> _requestMoreTime() async {
    if (_requestingMoreTime) return;
    setState(() => _requestingMoreTime = true);
    final result = await _orderService.requestDeliveryExtension(widget.orderId);
    if (!mounted) return;
    setState(() => _requestingMoreTime = false);
    _toast(result.message);
    await _load(silent: true);
  }

  Future<void> _reportDeliveryProblem() async {
    final dispute = await _showDisputeDialog(
      title: 'Reportar problema',
      intro:
          'Este reporte bloqueia o fecho automatico da entrega e envia o caso para analise.',
      submitLabel: 'Reportar agora',
      defaultType: 'delivery_issue',
    );
    if (dispute == null) return;

    setState(() => _reportingDeliveryProblem = true);
    final result = await _orderService.reportDeliveryProblem(
      orderId: widget.orderId,
      reason: dispute.reason,
      disputeType: dispute.type,
    );
    if (!mounted) return;
    setState(() => _reportingDeliveryProblem = false);
    _toast(result.message);
    await _load(silent: true);
  }

  Future<void> _cancelOrder() async {
    setState(() => _cancelling = true);
    var success = await _orderService.cancelOrder(widget.orderId);
    if (!success) {
      await _load(silent: true);
      if (_order?.status == OrderStatus.cancelled) {
        success = true;
      }
    }
    if (!mounted) return;
    setState(() => _cancelling = false);
    _toast(
      success
          ? 'Pedido cancelado com sucesso.'
          : 'Nao foi possivel cancelar o pedido agora. Tente novamente em instantes.',
    );
    if (success) await _load(silent: true);
  }

  Future<void> _retryPendingPayment() async {
    final order = _order;
    if (order == null || _retryingPayment) return;
    if (order.status != OrderStatus.pending ||
        order.hasConfirmedPayment ||
        order.fundsHeldInEscrow) {
      return;
    }

    setState(() => _retryingPayment = true);
    try {
      final payment = await _paymentService.createPayment(
        amount: order.totalAmount,
        walletType: 'wallet',
        orderId: order.id,
      );
      if (!mounted) return;

      if (payment == null) {
        final message = _paymentService.lastErrorMessage?.trim();
        _toast(
          message != null && message.isNotEmpty
              ? message
              : 'Nao foi possivel concluir o pagamento agora.',
        );
        await _load(silent: true);
        return;
      }

      _toast('Pagamento confirmado. O restaurante ja pode aceitar o pedido.');
      await _load(silent: true);
    } catch (_) {
      if (!mounted) return;
      _toast('Nao foi possivel concluir o pagamento agora.');
    } finally {
      if (mounted) {
        setState(() => _retryingPayment = false);
      }
    }
  }

  Future<void> _openDispute() async {
    final dispute = await _showDisputeDialog();
    if (dispute == null) return;

    setState(() => _openingDispute = true);
    final success = await _orderService.openOrderDispute(
      orderId: widget.orderId,
      disputeType: dispute.type,
      reason: dispute.reason,
      openedByRole: 'customer',
      metadata: {
        'submitted_from': 'order_details_page',
        'category': dispute.type,
      },
    );
    if (!mounted) return;
    setState(() => _openingDispute = false);
    _toast(success ? 'Disputa aberta com sucesso.' : 'Falha ao abrir disputa.');
  }

  Future<_DisputeDraft?> _showDisputeDialog({
    String title = 'Abrir disputa',
    String intro =
        'Explique o problema para o painel administrativo resolver com mais contexto.',
    String submitLabel = 'Enviar disputa',
    String defaultType = 'general',
  }) async {
    const disputeTypes = <String, String>{
      'missing_items': 'Faltam itens',
      'wrong_order': 'Pedido errado',
      'quality_issue': 'Problema de qualidade',
      'delivery_issue': 'Problema de entrega',
      'general': 'Outro motivo',
    };

    final reasonController = TextEditingController();
    String selectedType = defaultType;
    String? errorText;

    final result = await showDialog<_DisputeDraft>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(intro),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Categoria',
                        border: OutlineInputBorder(),
                      ),
                      items: disputeTypes.entries
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => selectedType = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Motivo detalhado',
                        hintText:
                            'Ex.: faltou a bebida, pedido chegou frio ou o estafeta marcou como entregue sem entregar.',
                        border: const OutlineInputBorder(),
                        errorText: errorText,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final reason = reasonController.text.trim();
                    if (reason.length < 10) {
                      setModalState(() {
                        errorText =
                            'Descreva o problema com um pouco mais de detalhe.';
                      });
                      return;
                    }
                    Navigator.pop(
                      context,
                      _DisputeDraft(type: selectedType, reason: reason),
                    );
                  },
                  child: Text(submitLabel),
                ),
              ],
            );
          },
        );
      },
    );

    reasonController.dispose();
    return result;
  }

  Widget _buildCountdown() {
    final order = _order!;
    // O preparo terminou. A procura de estafeta é um estado operacional
    // diferente e não deve continuar a mostrar 00:00 ou tempo estimado.
    if (order.status == OrderStatus.ready ||
        order.status == OrderStatus.awaitingPickupConfirmation) {
      return const SizedBox.shrink();
    }
    final paymentCompleted =
        order.hasConfirmedPayment || order.fundsHeldInEscrow;
    final isPendingPayment =
        order.status == OrderStatus.pending && !paymentCompleted;
    final isAwaitingRestaurant =
        order.status == OrderStatus.paymentAuthorized ||
        order.status == OrderStatus.paid ||
        (order.status == OrderStatus.pending && paymentCompleted);
    if (!(isPendingPayment ||
        order.status == OrderStatus.accepted ||
        order.status == OrderStatus.preparing ||
        order.status == OrderStatus.ready ||
        isAwaitingRestaurant)) {
      return const SizedBox.shrink();
    }
    final paymentPendingRemaining = _remainingPendingPaymentTimeout(order);
    final confirmationRemaining = _remainingRestaurantConfirmation(order);
    final preparationRemaining = _remainingPreparation(order);
    final isPreparing =
        order.status == OrderStatus.accepted ||
        order.status == OrderStatus.preparing;
    final isReady = order.status == OrderStatus.ready;
    final totalPrepSeconds = (order.estimatedPreparationMinutes * 60).clamp(
      60,
      3600,
    );
    final remainingPrepSeconds = isReady ? 0 : preparationRemaining.inSeconds;
    final totalSeconds = isPendingPayment
        ? 900
        : isAwaitingRestaurant
        ? 180
        : totalPrepSeconds;
    final remaining = isReady
        ? 0
        : (isPendingPayment
                  ? paymentPendingRemaining
                  : isAwaitingRestaurant
                  ? confirmationRemaining
                  : preparationRemaining)
              .inSeconds
              .clamp(0, 1 << 31);
    final mm = (remaining ~/ 60).toString().padLeft(2, '0');
    final ss = (remaining % 60).toString().padLeft(2, '0');
    final progress = totalSeconds > 0
        ? (1 - (remaining / totalSeconds)).clamp(0.0, 1.0)
        : 0.0;
    String? microAsset;
    if (!_isDelivery && order.status == OrderStatus.ready) {
      microAsset = 'assets/micro_feedback/box_closing.gif';
    } else if (_isDelivery && order.status == OrderStatus.ready) {
      microAsset = 'assets/micro_feedback/courier_confirmed.gif';
    } else if (isPreparing) {
      if (remainingPrepSeconds > totalPrepSeconds * 0.4) {
        microAsset = 'assets/micro_feedback/oven_cooking.gif';
      } else if (remainingPrepSeconds > 0) {
        microAsset = 'assets/micro_feedback/box_closing.gif';
      }
    }
    String phaseLabel;
    if (isPendingPayment) {
      phaseLabel = remaining > 0
          ? 'Conclua o pagamento em ate 15 minutos para enviar o pedido ao restaurante.'
          : 'O tempo para pagar terminou. O sistema esta a cancelar o pedido.';
    } else if (isAwaitingRestaurant) {
      phaseLabel = remaining > 0
          ? 'O restaurante tem ate 3 minutos para confirmar este pedido.'
          : 'O tempo de confirmacao terminou. O sistema esta a devolver o valor para a sua conta.';
    } else if (isReady) {
      phaseLabel = _isDelivery
          ? 'Pronto para entrega'
          : 'Pronto para levantamento';
    } else if (remaining > (order.estimatedPreparationMinutes * 60 * 0.6)) {
      phaseLabel = 'Em preparacao';
    } else if (remaining > (order.estimatedPreparationMinutes * 60 * 0.3)) {
      phaseLabel = 'A cozinhar';
    } else if (remaining > 0) {
      phaseLabel = 'Quase pronto';
    } else {
      phaseLabel = _isDelivery
          ? 'Pronto para entrega'
          : 'Pronto para levantamento';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPendingPayment
                  ? 'Aguardando pagamento'
                  : (order.status == OrderStatus.paymentAuthorized ||
                        order.status == OrderStatus.paid)
                  ? 'Aguardando confirmacao do restaurante'
                  : 'Tempo estimado do preparo',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '$mm:$ss',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: _statusColor(order.status),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                phaseLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.neutralGray,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isPendingPayment || isAwaitingRestaurant || isPreparing) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.black12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _statusColor(order.status),
                  ),
                ),
              ),
            ],
            if (!isPendingPayment && order.status != OrderStatus.paid) ...[
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Tempo estimado: ${order.estimatedPreparationMinutes} min',
                  style: const TextStyle(
                    color: AppColors.neutralGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (microAsset != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Image.asset(
                  microAsset,
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleOrderProgress(Order order) {
    final status = order.status;
    final paymentCompleted =
        order.hasConfirmedPayment || order.fundsHeldInEscrow;
    final awaitingRestaurant =
        status == OrderStatus.paid ||
        status == OrderStatus.paymentAuthorized ||
        (status == OrderStatus.pending && paymentCompleted);
    var activeStep = 0;
    if (status == OrderStatus.accepted || status == OrderStatus.preparing) {
      activeStep = 1;
    } else if (status == OrderStatus.ready ||
        status == OrderStatus.awaitingPickupConfirmation ||
        status == OrderStatus.courierAssigned) {
      activeStep = 2;
    } else if (status == OrderStatus.pickedUp ||
        status == OrderStatus.inDelivery) {
      activeStep = _isDelivery ? 3 : 2;
    } else if (status == OrderStatus.inTransit ||
        status == OrderStatus.onTheWay ||
        status == OrderStatus.arrived) {
      // “A caminho” só é concluído depois da recolha e início do percurso.
      activeStep = _isDelivery ? 4 : 2;
    } else if (status == OrderStatus.delivered ||
        status == OrderStatus.completed ||
        status == OrderStatus.autoCompleted) {
      activeStep = _isDelivery ? 5 : 3;
    }
    final labels = _isDelivery
        ? [
            awaitingRestaurant ? 'Aguardando restaurante' : 'Restaurante',
            'Preparação',
            'Procurando estafeta',
            'Recolhido',
            'A caminho',
            'Entregue',
          ]
        : [
            awaitingRestaurant ? 'Aguardando confirmação' : 'Restaurante',
            'Preparação',
            'Pronto para recolha',
            'Recolhido',
          ];
    final icons = _isDelivery
        ? const [
            Icons.receipt_long_outlined,
            Icons.restaurant_outlined,
            Icons.search_rounded,
            Icons.inventory_2_outlined,
            Icons.delivery_dining_outlined,
            Icons.check_circle_outline,
          ]
        : const [
            Icons.receipt_long_outlined,
            Icons.restaurant_outlined,
            Icons.storefront_outlined,
            Icons.check_circle_outline,
          ];
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: List.generate(labels.length, (index) {
            final completed = index < activeStep;
            final current = index == activeStep;
            final highlighted = completed || current;
            return Expanded(
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: completed
                          ? const Color(0xFFE5F9EC)
                          : current
                          ? const Color(0xFFFFE8E8)
                          : const Color(0xFFF2F3F5),
                      border: Border.all(
                        color: completed
                            ? AppColors.successGreen
                            : current
                            ? AppColors.primaryRed
                            : const Color(0xFFE2E4E8),
                      ),
                    ),
                    child: Icon(
                      icons[index],
                      color: completed
                          ? AppColors.successGreen
                          : current
                          ? AppColors.primaryRed
                          : Colors.black26,
                      size: 21,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: highlighted
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: highlighted ? AppColors.darkGray : Colors.black38,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: completed
                          ? AppColors.successGreen
                          : current
                          ? AppColors.primaryRed
                          : Colors.black12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildCourierOrderCard(Order order) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Color(0xFFFFE8E6),
              child: Icon(
                Icons.delivery_dining_rounded,
                color: AppColors.primaryRed,
                size: 29,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estafeta',
                    style: TextStyle(
                      color: AppColors.neutralGray,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Estafeta DeliGo',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '★ 4,8 · Estafeta atribuido',
                    style: TextStyle(
                      color: AppColors.neutralGray,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _openCourierProfile,
              icon: const Icon(Icons.call_outlined, size: 18),
              label: const Text('Ligar'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.push('/tracking/${widget.orderId}'),
              icon: const Icon(Icons.location_on_outlined, size: 18),
              label: const Text('Ver mapa'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildPickupRestaurantCard(Order order) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        _buildRestaurantAvatar(order, size: 56),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Retirada no restaurante',
                style: TextStyle(
                  color: AppColors.neutralGray,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _restaurantDisplayName(order),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                _displayDeliveryAddress(order),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.neutralGray,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _openRestaurantMenu,
          icon: const Icon(
            Icons.location_on_outlined,
            color: AppColors.primaryRed,
          ),
        ),
      ],
    ),
  );

  Widget _buildRestaurantAvatar(Order order, {double size = 52}) {
    final url = order.restaurantImageUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * .24),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _restaurantAvatarFallback(size),
        ),
      );
    }
    return _restaurantAvatarFallback(size);
  }

  Widget _restaurantAvatarFallback(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFFFE8E6),
      borderRadius: BorderRadius.circular(size * .24),
    ),
    child: Icon(
      Icons.storefront_rounded,
      color: AppColors.primaryRed,
      size: size * .48,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final pickupReadyByTime = order != null && _pickupReadyByTime(order);
    final showCourierProfileAction = _canShowCourierProfileAction;
    final showRestaurantAction = _canShowRestaurantAction;
    final showTrackingAction = _canTrackOrder;
    final showPrimaryOrderAction =
        showTrackingAction || showCourierProfileAction || showRestaurantAction;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Detalhes do Pedido'),
        centerTitle: true,
        backgroundColor: AppColors.primaryRed,
        foregroundColor: Colors.white,
        surfaceTintColor: AppColors.primaryRed,
        leading: IconButton(
          tooltip: 'Voltar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: const [],
      ),
      body: _loading && order == null
          ? const Center(child: CircularProgressIndicator())
          : order == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.receipt_long, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      _loadError ?? 'Pedido ainda nao sincronizado',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_loadError != null) ...[
                    Card(
                      color: const Color(0xFFFFF7ED),
                      child: ListTile(
                        leading: const Icon(Icons.cloud_off_rounded),
                        title: Text(_loadError!),
                        trailing: IconButton(
                          tooltip: 'Tentar novamente',
                          onPressed: () => _load(silent: true),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if ((order.centralAction ?? '').isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: .35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Decisão administrativa da Central',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.deepOrange,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            order.centralReason?.trim().isNotEmpty == true
                                ? order.centralReason!
                                : 'O estado deste pedido foi alterado pela Central.',
                          ),
                          if (order.refundStatus != 'not_applicable')
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Reembolso: ${order.refundStatus.replaceAll('_', ' ')}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_deliveryUnavailable) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: .45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.delivery_dining_outlined,
                                color: Colors.deepOrange,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Nao encontramos um estafeta',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.deepOrange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Neste momento nao conseguimos encontrar um estafeta disponivel para entregar o teu pedido. O pedido continua disponivel no restaurante.',
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _convertingDelivery
                                  ? null
                                  : _convertUnavailableDeliveryToPickup,
                              icon: _convertingDelivery
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.storefront_outlined),
                              label: Text(
                                _convertingDelivery
                                    ? 'A confirmar recolha...'
                                    : 'Escolher recolha no restaurante',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_assignedCourierHasNotPickedUp &&
                      _assignedCourierRecoveryDue) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: .45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.schedule_outlined,
                                color: Colors.deepOrange,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'O estafeta ainda não recolheu o pedido',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Colors.deepOrange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Pode escolher outra forma de receber este pedido.',
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _recoveringAssignedDelivery
                                  ? null
                                  : _chooseAssignedDeliveryRecovery,
                              icon: _recoveringAssignedDelivery
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.alt_route_outlined),
                              label: Text(
                                _recoveringAssignedDelivery
                                    ? 'A atualizar pedido...'
                                    : 'Escolher outra opção',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildRestaurantAvatar(order, size: 72),
                              const SizedBox(width: 12),
                              /* Container(
                                width: 64,
                                height: 64,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primaryRed,
                                      Color(0xFFFF6A5D),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.shopping_bag_outlined,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ), */
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _restaurantDisplayName(order),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _orderRef(order.id),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.neutralGray,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          maxWidth: double.infinity,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _statusColor(
                                            order.status,
                                          ).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          _statusText(order.status),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: true,
                                          style: TextStyle(
                                            color: _statusColor(order.status),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isDelivery
                                ? 'Pedido com delivery'
                                : 'Pedido para retirada',
                            style: const TextStyle(
                              color: AppColors.neutralGray,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _displayDeliveryAddress(_order!),
                            style: const TextStyle(
                              color: AppColors.neutralGray,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_formatDate(order.createdAt)} · ${_formatTime(order.createdAt)}',
                            style: const TextStyle(
                              color: AppColors.neutralGray,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSimpleOrderProgress(order),
                  const SizedBox(height: 16),
                  if (showCourierProfileAction) ...[
                    _buildCourierOrderCard(order),
                    const SizedBox(height: 16),
                  ] else if (!_isDelivery) ...[
                    _buildPickupRestaurantCard(order),
                    const SizedBox(height: 16),
                  ],
                  _buildCountdown(),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Itens do pedido',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._items.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F3ED),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.primaryRed.withValues(
                                      alpha: 0.10,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    if (item.menuItem?.imageUrl != null &&
                                        item.menuItem!.imageUrl!
                                            .trim()
                                            .isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: CachedNetworkImage(
                                          imageUrl: item.menuItem!.imageUrl!,
                                          width: 54,
                                          height: 54,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 108,
                                          memCacheHeight: 108,
                                        ),
                                      )
                                    else
                                      Container(
                                        width: 54,
                                        height: 54,
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryRed
                                              .withValues(alpha: 0.10),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.fastfood_rounded,
                                          color: AppColors.primaryRed,
                                        ),
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.menuItem?.name ?? 'Item',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.darkGray,
                                              height: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Quantidade: ${item.quantity}  •  ${_money(item.unitPrice)}',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: AppColors.neutralGray,
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
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.darkGray,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_items.isEmpty)
                            const Text(
                              'Nenhum item encontrado.',
                              style: TextStyle(color: AppColors.neutralGray),
                            ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Subtotal dos itens'),
                              Text(
                                _money(
                                  _items.fold<double>(
                                    0,
                                    (sum, item) => sum + item.subtotal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Taxa de entrega'),
                              Text(_money(_order!.deliveryFee)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _money(_order!.totalAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryRed,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TapScale(
                          child: OrderChatButton(
                            orderId: widget.orderId,
                            onPressed: () =>
                                context.push('/chat/${widget.orderId}'),
                          ),
                        ),
                      ),
                      if (showPrimaryOrderAction) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: TapScale(
                            child: ElevatedButton.icon(
                              onPressed: showCourierProfileAction
                                  ? _openCourierProfile
                                  : showRestaurantAction
                                  ? _openRestaurantMenu
                                  : () => context.push(
                                      '/tracking/${widget.orderId}',
                                    ),
                              icon: Icon(
                                showCourierProfileAction
                                    ? Icons.badge_outlined
                                    : showRestaurantAction
                                    ? Icons.storefront_outlined
                                    : Icons.map_outlined,
                              ),
                              label: Text(
                                showCourierProfileAction
                                    ? 'Ver estafeta'
                                    : showRestaurantAction
                                    ? 'Ver restaurante'
                                    : 'Rastrear',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryRed,
                                foregroundColor: Colors.white,
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (showCourierProfileAction && showRestaurantAction) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openRestaurantMenu,
                        icon: const Icon(Icons.storefront_outlined),
                        label: const Text('Ver restaurante'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_isDelivery &&
                      (_order!.status == OrderStatus.inTransit ||
                          _order!.status == OrderStatus.arrived) &&
                      (_deliveryOtpCode?.isNotEmpty ?? false)) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9F5EF),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.primaryRed.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Diga este codigo ao estafeta',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _deliveryOtpCode!,
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8,
                              color: AppColors.primaryRed,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Nao partilhe este codigo antes de receber o pedido. Depois de o estafeta validar, confirme o recebimento abaixo para fechar o pedido com seguranca.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.neutralGray,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_order!.isDeliveryOtpSmsSentForCurrentCode) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Tambem enviamos este codigo por SMS para o teu numero.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.neutralGray,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (_order!.deliveryOtpRegenerationCount < 1) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _regeneratingDeliveryOtp
                                  ? null
                                  : _regenerateDeliveryOtp,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(
                                _regeneratingDeliveryOtp
                                    ? 'A gerar novo codigo...'
                                    : 'Gerar novo codigo (1x)',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else if (_isDelivery &&
                      (_order!.status == OrderStatus.inTransit ||
                          _order!.status == OrderStatus.arrived)) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F4F2),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'Estamos a preparar o teu codigo de entrega. Ele deve aparecer automaticamente assim que ficar disponivel.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.neutralGray,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else if (_isDelivery &&
                      _order!.status == OrderStatus.deliveryFailedOtp) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.deepOrange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.deepOrange.withValues(alpha: 0.20),
                        ),
                      ),
                      child: const Text(
                        'O OTP falhou nesta entrega. A equipa admin foi alertada para rever o caso com seguranca antes do fecho.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if ((_isDelivery &&
                          _order!.status == OrderStatus.delivered) ||
                      (!_isDelivery && _order!.status == OrderStatus.ready))
                    TapScale(
                      child: ElevatedButton(
                        onPressed: _confirming ? null : _confirmDelivery,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.successGreen,
                          foregroundColor: AppColors.cleanWhite,
                        ),
                        child: _confirming
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _isDelivery
                                    ? 'Confirmar recebimento e concluir'
                                    : 'Levantar pedido',
                              ),
                      ),
                    ),
                  if (_deliveryWaitingForCustomerAction) ...[
                    const SizedBox(height: 8),
                    Text(
                      _order!.status == OrderStatus.disputed
                          ? 'Recebemos o teu reporte e travamos o fecho automatico enquanto a equipa analisa.'
                          : 'Se nao fizeres nada, a entrega sera concluida automaticamente em ${_formatDuration(_remainingDeliveryAutoClose(_order!))}.',
                      style: TextStyle(
                        color: _order!.status == OrderStatus.disputed
                            ? Colors.deepOrange
                            : AppColors.neutralGray,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_paymentPendingOrder) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _retryingPayment ? null : _retryPendingPayment,
                      icon: _retryingPayment
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.account_balance_wallet_outlined),
                      label: Text(
                        _retryingPayment
                            ? 'A confirmar pagamento...'
                            : 'Concluir pagamento agora',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Enquanto o pagamento nao entrar, o restaurante nao consegue aceitar este pedido.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.neutralGray,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_order!.status == OrderStatus.pending ||
                      _order!.status == OrderStatus.paymentAuthorized ||
                      _order!.status == OrderStatus.paid ||
                      (_order!.status == OrderStatus.accepted &&
                          !pickupReadyByTime) ||
                      (_order!.status == OrderStatus.preparing &&
                          !pickupReadyByTime)) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _cancelling ? null : _cancelOrder,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: _cancelling
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Cancelar pedido'),
                    ),
                  ],
                  if (_canRequestMoreTime || _canReportDeliveryProblem) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_canReportDeliveryProblem)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _reportingDeliveryProblem
                                  ? null
                                  : _reportDeliveryProblem,
                              icon: const Icon(Icons.report_problem_outlined),
                              label: Text(
                                _reportingDeliveryProblem
                                    ? 'A reportar...'
                                    : 'Reportar problema',
                              ),
                            ),
                          ),
                        if (_canReportDeliveryProblem && _canRequestMoreTime)
                          const SizedBox(width: 12),
                        if (_canRequestMoreTime)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _requestingMoreTime
                                  ? null
                                  : _requestMoreTime,
                              icon: const Icon(Icons.more_time_rounded),
                              label: Text(
                                _requestingMoreTime
                                    ? 'A pedir mais tempo...'
                                    : 'Preciso de mais tempo (+10 min)',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (_order!.status == OrderStatus.completed ||
                      _order!.status == OrderStatus.autoCompleted) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _openingDispute ? null : _openDispute,
                      icon: const Icon(Icons.gavel),
                      label: Text(
                        _openingDispute
                            ? 'Abrindo disputa...'
                            : 'Abrir disputa',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildOrderTimelineCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildOrderTimelineCard() {
    final events = _timelineEvents();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history_edu_rounded, color: Color(0xFFB45309)),
              SizedBox(width: 10),
              Text(
                'Linha do tempo do pedido',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF92400E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Resumo simples dos principais passos deste pedido.',
            style: TextStyle(
              color: AppColors.neutralGray,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            const Text(
              'Ainda nao ha eventos detalhados para este pedido.',
              style: TextStyle(color: AppColors.neutralGray),
            )
          else
            ...events.map(_buildTimelineEventTile),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _timelineEvents() {
    final events = _events
        .where((event) {
          final type = event['event_type']?.toString().trim() ?? '';
          return type.isNotEmpty && !_isNoisyOrderEvent(type);
        })
        .map(Map<String, dynamic>.from)
        .toList();
    events.sort((a, b) {
      final left = DateTime.tryParse(a['created_at']?.toString() ?? '');
      final right = DateTime.tryParse(b['created_at']?.toString() ?? '');
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });
    if (events.length <= 12) return events;
    return events.sublist(events.length - 12);
  }

  bool _isNoisyOrderEvent(String type) {
    final normalized = type.toLowerCase();
    return normalized.contains('dispatch_retry') ||
        normalized.contains('notification_ack') ||
        normalized.contains('push_ack');
  }

  Widget _buildTimelineEventTile(Map<String, dynamic> event) {
    final type = event['event_type']?.toString() ?? '';
    final tone = _timelineEventColor(type);
    final description = _timelineEventDescription(event);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_timelineEventIcon(type), size: 18, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _timelineEventTitle(event),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.darkGray,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.neutralGray,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  _timelineEventTime(event),
                  style: TextStyle(
                    color: AppColors.neutralGray.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timelineEventTitle(Map<String, dynamic> event) {
    final type = event['event_type']?.toString().toLowerCase() ?? '';
    final newStatus = event['new_status']?.toString().toLowerCase() ?? '';
    if (type.contains('created')) return 'Pedido criado';
    if (type.contains('payment') || type.contains('paid')) {
      return 'Pagamento confirmado';
    }
    if (type.contains('accepted') || newStatus == 'accepted') {
      return 'Restaurante aceitou';
    }
    if (type.contains('preparing') || newStatus == 'preparing') {
      return 'Preparo iniciado';
    }
    if (type.contains('ready') || newStatus == 'ready') {
      return 'Pedido pronto';
    }
    if (type.contains('courier') ||
        type.contains('driver_assigned') ||
        newStatus == 'courier_assigned') {
      return 'Estafeta atribuido';
    }
    if (type.contains('arrived') || newStatus == 'arrived') {
      return 'Estafeta chegou';
    }
    if (type.contains('picked_up') ||
        type.contains('in_transit') ||
        newStatus == 'in_transit') {
      return 'Pedido levantado';
    }
    if (type.contains('otp') && type.contains('verified')) {
      return 'Codigo validado';
    }
    if (type.contains('otp')) return 'Codigo de entrega gerado';
    if (type.contains('delivered') || newStatus == 'delivered') {
      return 'Entrega validada';
    }
    if (type.contains('completed') || newStatus == 'completed') {
      return 'Pedido concluido';
    }
    if (type.contains('refund')) return 'Reembolso registado';
    if (type.contains('cancel') || newStatus == 'cancelled') {
      return 'Pedido cancelado';
    }
    if (type.contains('dispute')) return 'Disputa aberta';
    return _humanizeEventType(type);
  }

  String _timelineEventDescription(Map<String, dynamic> event) {
    final type = event['event_type']?.toString().toLowerCase() ?? '';
    final actorRole = event['actor_role']?.toString().trim() ?? '';
    final oldStatus = event['old_status']?.toString().trim() ?? '';
    final newStatus = event['new_status']?.toString().trim() ?? '';
    if (type.contains('payment') || type.contains('paid')) {
      return 'O pagamento ficou confirmado na plataforma.';
    }
    if (type.contains('accepted') || newStatus == 'accepted') {
      return 'O restaurante confirmou o pedido.';
    }
    if (type.contains('preparing') || newStatus == 'preparing') {
      return 'A cozinha iniciou o preparo.';
    }
    if (type.contains('ready') || newStatus == 'ready') {
      return 'O pedido terminou o preparo.';
    }
    if (type.contains('arrived') || newStatus == 'arrived') {
      return 'O estafeta chegou ao ponto indicado.';
    }
    if (type.contains('otp') && type.contains('verified')) {
      return 'O codigo de entrega foi confirmado.';
    }
    if (type.contains('otp')) {
      return 'O codigo de entrega ficou disponivel no app.';
    }
    if (oldStatus.isNotEmpty &&
        newStatus.isNotEmpty &&
        oldStatus != newStatus) {
      return '${_humanizeEventType(oldStatus)} -> ${_humanizeEventType(newStatus)}';
    }
    if (actorRole.isNotEmpty) {
      return 'Acao registada por ${_humanizeEventType(actorRole)}.';
    }
    return '';
  }

  String _timelineEventTime(Map<String, dynamic> event) {
    final parsed = DateTime.tryParse(event['created_at']?.toString() ?? '');
    if (parsed == null) return '';
    final local = MozambiqueTime.from(parsed);
    final now = MozambiqueTime.from(_now);
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    final label = day == today
        ? 'Hoje'
        : day == today.subtract(const Duration(days: 1))
        ? 'Ontem'
        : '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    return '$label, ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime value) {
    final local = MozambiqueTime.from(value);
    const months = [
      '',
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ];
    return '${local.day} de ${months[local.month]}';
  }

  String _formatTime(DateTime value) {
    final local = MozambiqueTime.from(value);
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  IconData _timelineEventIcon(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('payment') || normalized.contains('paid')) {
      return Icons.payments_outlined;
    }
    if (normalized.contains('ready')) return Icons.inventory_2_rounded;
    if (normalized.contains('courier') ||
        normalized.contains('driver') ||
        normalized.contains('picked') ||
        normalized.contains('arrived')) {
      return Icons.delivery_dining_rounded;
    }
    if (normalized.contains('otp')) return Icons.password_rounded;
    if (normalized.contains('cancel') || normalized.contains('refund')) {
      return Icons.undo_rounded;
    }
    if (normalized.contains('dispute')) return Icons.gavel_rounded;
    if (normalized.contains('completed') || normalized.contains('delivered')) {
      return Icons.task_alt_rounded;
    }
    return Icons.radio_button_checked_rounded;
  }

  Color _timelineEventColor(String type) {
    final normalized = type.toLowerCase();
    if (normalized.contains('cancel') ||
        normalized.contains('failed') ||
        normalized.contains('dispute')) {
      return Colors.orange.shade700;
    }
    if (normalized.contains('completed') ||
        normalized.contains('delivered') ||
        normalized.contains('accepted') ||
        normalized.contains('payment')) {
      return AppColors.successGreen;
    }
    if (normalized.contains('courier') ||
        normalized.contains('driver') ||
        normalized.contains('picked') ||
        normalized.contains('arrived')) {
      return const Color(0xFF0F766E);
    }
    return const Color(0xFFEA580C);
  }

  String _humanizeEventType(String value) {
    final cleaned = value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim()
        .toLowerCase();
    if (cleaned.isEmpty) return 'Evento registado';
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }
}

class _DisputeDraft {
  final String type;
  final String reason;

  const _DisputeDraft({required this.type, required this.reason});
}
