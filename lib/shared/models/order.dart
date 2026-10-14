/// Modelo de Status do Pedido
enum OrderStatus {
  pending('pending', 'Pendente'),
  paid('paid', 'Pago'),
  paymentAuthorized('payment_authorized', 'Pagamento autorizado'),
  accepted('accepted', 'Aceito'),
  preparing('preparing', 'Preparando'),
  ready('ready', 'Pronto'),
  awaitingPickupConfirmation(
    'awaiting_pickup_confirmation',
    'Aguardando confirmacao de retirada',
  ),
  pickedUp('picked_up', 'Pedido recolhido'),
  inDelivery('in_delivery', 'Em entrega'),
  courierAssigned('courier_assigned', 'Entregador atribuído'),
  inTransit('in_transit', 'Em Trânsito'),
  arrived('arrived', 'Chegou'),
  deliveryFailedOtp('delivery_failed_otp', 'Falha no OTP da entrega'),
  onTheWay('on_the_way', 'A caminho'),
  delivered('delivered', 'Entregue'),
  disputed('disputed', 'Em disputa'),
  completed('completed', 'Concluído'),
  autoCompleted('auto_completed', 'Concluido automaticamente'),
  expired('expired', 'Expirado'),
  paymentFailed('payment_failed', 'Falha no pagamento'),
  refunded('refunded', 'Reembolsado'),
  cancelled('cancelled', 'Cancelado');

  final String value;
  final String displayName;

  const OrderStatus(this.value, this.displayName);

  static OrderStatus fromString(String status) {
    return OrderStatus.values.firstWhere(
      (e) => e.value == status.toLowerCase(),
      orElse: () => OrderStatus.pending,
    );
  }
}

/// Modelo de Pedido
class Order {
  final String id;
  final String clientId;
  final String restaurantId;
  final OrderStatus status;
  final double totalAmount;
  final double deliveryFee;
  final double? courierAmount;
  final String deliveryAddress;
  final String deliveryType;
  final String fulfillmentMethod;
  final String deliveryStatus;
  final String paymentStatus;
  final String fundsStatus;
  final String refundStatus;
  final String? centralAction;
  final String? centralReason;
  final String currency;
  final int estimatedPreparationMinutes;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? preparationStartedAt;
  final DateTime? dispatchStartedAt;
  final DateTime? dispatchExpiresAt;
  final DateTime? courierAssignedAt;
  final String? dispatchAttemptId;
  final DateTime? acceptedAt;
  final DateTime? preparingAt;
  final DateTime? readyAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final String? courierId;
  final DateTime? scheduledFor;
  final String? groupCode;
  final String? comboId;
  final String? comboTitle;
  final double? comboDiscountPercentage;
  final double? comboDiscountAmount;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final String? pickupAddress;
  final DateTime? deliveryOtpExpiresAt;
  final DateTime? deliveryOtpGeneratedAt;
  final DateTime? deliveryOtpVerifiedAt;
  final DateTime? deliveryOtpSentAt;
  final int deliveryOtpRegenerationCount;
  final String? deliveryOtpChannel;
  final DateTime? deliveryExtensionUntil;
  final int deliveryExtensionCount;
  final String? disputeReason;
  final DateTime? disputeCreatedAt;
  // Propriedades adicionais
  final String? restaurantName;
  final String? restaurantImageUrl;
  final String? restaurantAddress;
  final String? restaurantNeighborhood;
  final String? restaurantLandmarkReference;
  final String? restaurantCity;
  final double? restaurantRating;
  final double? restaurantLatitude;
  final double? restaurantLongitude;
  final String? clientName;

  Order({
    required this.id,
    required this.clientId,
    required this.restaurantId,
    required this.status,
    required this.totalAmount,
    required this.deliveryFee,
    this.courierAmount,
    required this.deliveryAddress,
    this.deliveryType = 'delivery',
    this.fulfillmentMethod = 'delivery',
    this.deliveryStatus = 'pending',
    this.paymentStatus = 'pending',
    this.fundsStatus = 'none',
    this.refundStatus = 'not_applicable',
    this.centralAction,
    this.centralReason,
    this.currency = 'MZN',
    this.estimatedPreparationMinutes = 25,
    required this.createdAt,
    this.updatedAt,
    this.preparationStartedAt,
    this.dispatchStartedAt,
    this.dispatchExpiresAt,
    this.courierAssignedAt,
    this.dispatchAttemptId,
    this.acceptedAt,
    this.preparingAt,
    this.readyAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.courierId,
    this.scheduledFor,
    this.groupCode,
    this.comboId,
    this.comboTitle,
    this.comboDiscountPercentage,
    this.comboDiscountAmount,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.pickupLatitude,
    this.pickupLongitude,
    this.pickupAddress,
    this.deliveryOtpExpiresAt,
    this.deliveryOtpGeneratedAt,
    this.deliveryOtpVerifiedAt,
    this.deliveryOtpSentAt,
    this.deliveryOtpRegenerationCount = 0,
    this.deliveryOtpChannel,
    this.deliveryExtensionUntil,
    this.deliveryExtensionCount = 0,
    this.disputeReason,
    this.disputeCreatedAt,
    this.restaurantName,
    this.restaurantImageUrl,
    this.restaurantAddress,
    this.restaurantNeighborhood,
    this.restaurantLandmarkReference,
    this.restaurantCity,
    this.restaurantRating,
    this.restaurantLatitude,
    this.restaurantLongitude,
    this.clientName,
  });

  factory Order.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      final raw = value.toString().trim();
      if (raw.isEmpty) return null;
      final hasTimezone = RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw);
      final candidate = hasTimezone ? raw : '${raw}Z';
      return DateTime.tryParse(candidate)?.toUtc();
    }

    final clientId = (map['client_id'] ?? map['customer_id'] ?? '').toString();
    final restaurantId = (map['restaurant_id'] ?? '').toString().trim();
    final totalAmount =
        (map['total_amount'] as num?)?.toDouble() ??
        (map['total'] as num?)?.toDouble() ??
        0.0;
    final rawRestaurant = map['restaurants'];
    final restaurant = rawRestaurant is Map
        ? rawRestaurant.cast<String, dynamic>()
        : rawRestaurant is List &&
              rawRestaurant.isNotEmpty &&
              rawRestaurant.first is Map
        ? (rawRestaurant.first as Map).cast<String, dynamic>()
        : null;
    Map<String, dynamic>? paymentSplit;
    final rawPaymentSplit = map['payment_splits'];
    if (rawPaymentSplit is Map) {
      paymentSplit = Map<String, dynamic>.from(rawPaymentSplit);
    } else if (rawPaymentSplit is List && rawPaymentSplit.isNotEmpty) {
      final firstSplit = rawPaymentSplit.first;
      if (firstSplit is Map) {
        paymentSplit = Map<String, dynamic>.from(firstSplit);
      }
    }
    final estimatedPreparationMinutes =
        (map['estimated_delivery_time'] as num?)?.toInt() ??
        (restaurant?['estimated_delivery_time'] as num?)?.toInt() ??
        25;

    return Order(
      id: map['id'] ?? '',
      clientId: clientId,
      restaurantId: restaurantId,
      status: OrderStatus.fromString(map['status'] ?? 'pending'),
      totalAmount: totalAmount,
      deliveryFee: (map['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      courierAmount: _courierAmountFromMap(map),
      deliveryAddress: map['delivery_address'] ?? '',
      deliveryType: (map['delivery_type'] as String?)?.trim().isNotEmpty == true
          ? map['delivery_type'].toString()
          : ((map['delivery_fee'] as num?)?.toDouble() ?? 0) > 0
          ? 'delivery'
          : 'pickup',
      fulfillmentMethod:
          (map['fulfillment_method'] as String?)?.trim().isNotEmpty == true
          ? map['fulfillment_method'].toString()
          : ((map['delivery_type'] as String?) == 'pickup'
                ? 'customer_pickup'
                : 'delivery'),
      // Missing legacy delivery_status must never imply an active dispatch.
      // Dispatch is authoritative only after READY and only when the server
      // has created an attempt.
      deliveryStatus:
          (map['delivery_status'] as String?)?.trim().isNotEmpty == true
          ? map['delivery_status'].toString()
          : ((map['courier_id'] == null &&
                    (map['status']?.toString().toLowerCase() == 'ready'))
                ? 'pending'
                : (map['courier_id'] == null ? 'pending' : 'assigned')),
      paymentStatus:
          (map['payment_status'] as String?)?.trim().isNotEmpty == true
          ? map['payment_status'].toString()
          : 'pending',
      fundsStatus: (map['funds_status'] as String?)?.trim().isNotEmpty == true
          ? map['funds_status'].toString()
          : 'none',
      refundStatus: (map['refund_status'] as String?)?.trim().isNotEmpty == true
          ? map['refund_status'].toString()
          : 'not_applicable',
      centralAction: map['central_action']?.toString(),
      centralReason: map['central_reason']?.toString(),
      currency: (map['currency'] as String?)?.trim().isNotEmpty == true
          ? map['currency'].toString()
          : 'MZN',
      estimatedPreparationMinutes: estimatedPreparationMinutes > 0
          ? estimatedPreparationMinutes
          : 25,
      deliveryLatitude: (map['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (map['delivery_longitude'] as num?)?.toDouble(),
      pickupLatitude: (map['pickup_latitude'] as num?)?.toDouble(),
      pickupLongitude: (map['pickup_longitude'] as num?)?.toDouble(),
      pickupAddress: map['pickup_address']?.toString(),
      createdAt: parseDate(map['created_at']) ?? DateTime.now().toUtc(),
      updatedAt: parseDate(map['updated_at']),
      preparationStartedAt:
          parseDate(map['preparing_at']) ??
          parseDate(map['preparation_started_at']) ??
          parseDate(paymentSplit?['restaurant_confirmed_at']),
      dispatchStartedAt: parseDate(map['dispatch_started_at']),
      dispatchExpiresAt: parseDate(map['dispatch_expires_at']),
      courierAssignedAt: parseDate(map['courier_assigned_at']),
      dispatchAttemptId: map['dispatch_attempt_id']?.toString(),
      acceptedAt: parseDate(map['accepted_at']),
      preparingAt: parseDate(map['preparing_at']),
      readyAt: parseDate(map['ready_at']),
      pickedUpAt: parseDate(map['picked_up_at']),
      deliveredAt: parseDate(map['delivered_at']),
      courierId: map['courier_id'],
      scheduledFor: parseDate(map['scheduled_for']),
      groupCode: map['group_code'],
      comboId: map['combo_id']?.toString(),
      comboTitle: map['combo_title']?.toString(),
      comboDiscountPercentage: (map['combo_discount_percentage'] as num?)
          ?.toDouble(),
      comboDiscountAmount: (map['combo_discount_amount'] as num?)?.toDouble(),
      deliveryOtpExpiresAt: parseDate(map['delivery_otp_expires_at']),
      deliveryOtpGeneratedAt: parseDate(map['delivery_otp_generated_at']),
      deliveryOtpVerifiedAt: parseDate(map['delivery_otp_verified_at']),
      deliveryOtpSentAt: parseDate(map['delivery_otp_sent_at']),
      deliveryOtpRegenerationCount:
          (map['delivery_otp_regeneration_count'] as num?)?.toInt() ?? 0,
      deliveryOtpChannel: map['delivery_otp_channel']?.toString(),
      deliveryExtensionUntil: parseDate(map['delivery_extension_until']),
      deliveryExtensionCount:
          (map['delivery_extension_count'] as num?)?.toInt() ?? 0,
      disputeReason: map['dispute_reason']?.toString(),
      disputeCreatedAt: parseDate(map['dispute_created_at']),
      restaurantName:
          map['restaurant_name']?.toString() ?? restaurant?['name']?.toString(),
      restaurantImageUrl:
          map['restaurant_image_url']?.toString() ??
          restaurant?['image_url']?.toString(),
      restaurantAddress: restaurant?['address']?.toString(),
      restaurantNeighborhood: restaurant?['neighborhood']?.toString(),
      restaurantLandmarkReference: restaurant?['landmark_reference']
          ?.toString(),
      restaurantCity: restaurant?['city']?.toString(),
      restaurantRating: (restaurant?['rating'] as num?)?.toDouble(),
      restaurantLatitude: (restaurant?['latitude'] as num?)?.toDouble(),
      restaurantLongitude: (restaurant?['longitude'] as num?)?.toDouble(),
      clientName: map['client_name'],
    );
  }

  static double? _courierAmountFromMap(Map<String, dynamic> map) {
    final direct = (map['courier_amount'] as num?)?.toDouble();
    if (direct != null) return direct;
    final splits = map['payment_splits'];
    if (splits is List && splits.isNotEmpty && splits.first is Map) {
      return ((splits.first as Map)['courier_amount'] as num?)?.toDouble();
    }
    if (splits is Map) return (splits['courier_amount'] as num?)?.toDouble();
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'client_id': clientId,
      'restaurant_id': restaurantId,
      'status': status.value,
      'total_amount': totalAmount,
      'delivery_fee': deliveryFee,
      'delivery_address': deliveryAddress,
      'delivery_type': deliveryType,
      'fulfillment_method': fulfillmentMethod,
      'delivery_status': deliveryStatus,
      'dispatch_started_at': dispatchStartedAt?.toIso8601String(),
      'dispatch_expires_at': dispatchExpiresAt?.toIso8601String(),
      'dispatch_attempt_id': dispatchAttemptId,
      'payment_status': paymentStatus,
      'funds_status': fundsStatus,
      'refund_status': refundStatus,
      'central_action': centralAction,
      'central_reason': centralReason,
      'currency': currency,
      'estimated_delivery_time': estimatedPreparationMinutes,
      'delivery_latitude': deliveryLatitude,
      'delivery_longitude': deliveryLongitude,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'preparing_at': (preparingAt ?? preparationStartedAt)?.toIso8601String(),
      'accepted_at': acceptedAt?.toIso8601String(),
      'ready_at': readyAt?.toIso8601String(),
      'picked_up_at': pickedUpAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'courier_id': courierId,
      'scheduled_for': scheduledFor?.toIso8601String(),
      'group_code': groupCode,
      'combo_id': comboId,
      'combo_title': comboTitle,
      'combo_discount_percentage': comboDiscountPercentage,
      'combo_discount_amount': comboDiscountAmount,
      'delivery_otp_expires_at': deliveryOtpExpiresAt?.toIso8601String(),
      'delivery_otp_generated_at': deliveryOtpGeneratedAt?.toIso8601String(),
      'delivery_otp_verified_at': deliveryOtpVerifiedAt?.toIso8601String(),
      'delivery_otp_sent_at': deliveryOtpSentAt?.toIso8601String(),
      'delivery_otp_regeneration_count': deliveryOtpRegenerationCount,
      'delivery_otp_channel': deliveryOtpChannel,
      'delivery_extension_until': deliveryExtensionUntil?.toIso8601String(),
      'delivery_extension_count': deliveryExtensionCount,
      'dispute_reason': disputeReason,
      'dispute_created_at': disputeCreatedAt?.toIso8601String(),
      'restaurant_name': restaurantName,
      'restaurant_image_url': restaurantImageUrl,
      'restaurant_address': restaurantAddress,
      'restaurant_neighborhood': restaurantNeighborhood,
      'restaurant_city': restaurantCity,
      'restaurant_latitude': restaurantLatitude,
      'restaurant_longitude': restaurantLongitude,
    };
  }

  DateTime get restaurantConfirmationStartedAt {
    final normalizedStatus = status.value.toLowerCase();
    final normalizedPayment = paymentStatus.toLowerCase();
    final paymentCompleted =
        normalizedPayment == 'completed' ||
        normalizedPayment == 'paid' ||
        normalizedPayment == 'authorized';
    if (normalizedStatus == 'paid' ||
        normalizedStatus == 'payment_authorized' ||
        (normalizedStatus == 'pending' && paymentCompleted)) {
      return updatedAt ?? createdAt;
    }
    return createdAt;
  }

  DateTime get preparationReference =>
      acceptedAt ?? preparationStartedAt ?? updatedAt ?? createdAt;

  DateTime get deliveryConfirmationReference =>
      deliveredAt ?? updatedAt ?? createdAt;

  bool get isPaymentAuthorized {
    final normalizedPayment = paymentStatus.toLowerCase();
    return status == OrderStatus.paymentAuthorized ||
        status == OrderStatus.paid ||
        normalizedPayment == 'authorized' ||
        normalizedPayment == 'completed' ||
        normalizedPayment == 'paid';
  }

  bool get isPaymentSettled {
    final normalizedPayment = paymentStatus.toLowerCase();
    final normalizedFunds = fundsStatus.toLowerCase();
    return normalizedPayment == 'settled' || normalizedFunds == 'released';
  }

  bool get hasConfirmedPayment => isPaymentAuthorized || isPaymentSettled;

  bool get fundsHeldInEscrow => fundsStatus.toLowerCase() == 'held_in_escrow';

  bool get isDelivery =>
      deliveryType.toLowerCase() == 'delivery' && !isCustomerPickupFallback ||
      deliveryFee > 0 && !isCustomerPickupFallback;

  bool get isCustomerPickupFallback =>
      fulfillmentMethod.toLowerCase() == 'customer_pickup' &&
      deliveryType.toLowerCase() == 'delivery';

  bool get isPickup => !isDelivery;

  bool get isFinalState =>
      status == OrderStatus.completed ||
      status == OrderStatus.autoCompleted ||
      status == OrderStatus.cancelled ||
      status == OrderStatus.refunded ||
      status == OrderStatus.expired ||
      status == OrderStatus.paymentFailed;

  bool get isCompletedState =>
      status == OrderStatus.completed || status == OrderStatus.autoCompleted;

  bool get blocksSettlement => status == OrderStatus.disputed;

  bool get isOperationallyActive => !isFinalState;

  bool get requiresCustomerAction => isDelivery
      ? status == OrderStatus.delivered
      : status == OrderStatus.ready ||
            status == OrderStatus.awaitingPickupConfirmation;

  bool get isDeliveryOtpPending =>
      isDelivery &&
      (status == OrderStatus.inTransit || status == OrderStatus.arrived) &&
      deliveryOtpVerifiedAt == null;

  bool get isDeliveryOtpSmsSentForCurrentCode =>
      deliveryOtpChannel?.toLowerCase() == 'sms' &&
      deliveryOtpSentAt != null &&
      deliveryOtpGeneratedAt != null &&
      !deliveryOtpSentAt!.isBefore(deliveryOtpGeneratedAt!);

  bool get hasDeliveryExtension =>
      deliveryExtensionUntil != null &&
      deliveryExtensionUntil!.isAfter(deliveryConfirmationReference);

  DateTime? get autoCloseDeadline {
    if (isDelivery &&
        (status == OrderStatus.delivered || status == OrderStatus.disputed)) {
      final baseDeadline =
          deliveredAt?.add(const Duration(minutes: 10)) ??
          deliveryConfirmationReference.add(const Duration(minutes: 10));
      if (deliveryExtensionUntil != null &&
          deliveryExtensionUntil!.isAfter(baseDeadline)) {
        return deliveryExtensionUntil;
      }
      return baseDeadline;
    }

    if (isPickup &&
        (status == OrderStatus.ready ||
            status == OrderStatus.awaitingPickupConfirmation)) {
      return (readyAt ?? updatedAt ?? createdAt).add(
        const Duration(minutes: 20),
      );
    }

    return null;
  }
}

/// Modelo de Item do Pedido
class OrderItem {
  final String id;
  final String orderId;
  final String menuItemId;
  final int quantity;
  final double unitPrice;
  final double subtotal;
  final dynamic menuItem;

  OrderItem({
    required this.id,
    required this.orderId,
    required this.menuItemId,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.menuItem,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    final unitPrice =
        (map['unit_price'] as num?)?.toDouble() ??
        (map['price'] as num?)?.toDouble() ??
        0.0;
    final subtotal =
        (map['subtotal'] as num?)?.toDouble() ??
        (unitPrice * ((map['quantity'] as num?)?.toInt() ?? 0));

    return OrderItem(
      id: map['id'] ?? '',
      orderId: map['order_id'] ?? '',
      menuItemId: map['menu_item_id'] ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: unitPrice,
      subtotal: subtotal,
      menuItem: map['menu_items'],
    );
  }
}
