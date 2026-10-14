import 'dart:convert';

enum NotificationPriority { critical, high, normal, silent }

enum NotificationSound {
  none,
  message,
  notification,
  success,
  error,
  urgent,
  restaurantOrder,
  courierOffer,
}

class NotificationEvent {
  const NotificationEvent({
    required this.type,
    required this.entityId,
    required this.priority,
    required this.sound,
    this.channel,
    this.attemptId,
    this.offerExpiresAt,
    this.dispatchExpiresAt,
  });

  final String type;
  final String? entityId;
  final String? channel;
  final String? attemptId;
  final NotificationPriority priority;
  final NotificationSound sound;
  final DateTime? offerExpiresAt;
  final DateTime? dispatchExpiresAt;

  bool get isCourierOffer => sound == NotificationSound.courierOffer;

  static NotificationEvent fromPayload(Map<dynamic, dynamic> payload) {
    final type =
        _string(payload, 'type') ?? _string(payload, 'event_type') ?? '';
    final channel = _string(payload, 'channel');
    final entityId =
        _string(payload, 'entity_id') ?? _string(payload, 'order_id');
    final attemptId = _string(payload, 'dispatch_attempt_id');
    final canonicalType = type.toUpperCase();
    final courier =
        canonicalType == 'DELIVERY_OPPORTUNITY' ||
        canonicalType == 'NEW_DRIVER_ORDER' ||
        channel == 'courier_dispatch';
    final restaurant =
        canonicalType == 'NEW_ORDER' ||
        canonicalType == 'NEW_PAID_ORDER' ||
        channel == 'restaurant_order_alert';
    final sound = canonicalType == 'ORDER_READY_FOR_PICKUP'
        ? NotificationSound.urgent
        : courier
        ? NotificationSound.courierOffer
        : restaurant
        ? NotificationSound.restaurantOrder
        : _soundFor(canonicalType);
    final priority = courier || restaurant
        ? NotificationPriority.critical
        : _priorityFor(canonicalType);
    return NotificationEvent(
      type: canonicalType,
      channel: channel,
      entityId: entityId,
      attemptId: attemptId,
      priority: priority,
      sound: sound,
      offerExpiresAt: _date(payload, 'offer_expires_at'),
      dispatchExpiresAt: _date(payload, 'dispatch_expires_at'),
    );
  }

  static String? _string(Map<dynamic, dynamic> payload, String key) {
    final direct = payload[key];
    if (direct != null && direct.toString().trim().isNotEmpty)
      return direct.toString().trim();
    for (final nestedKey in const ['metadata', 'data']) {
      var nested = payload[nestedKey];
      if (nested is String && nested.trim().startsWith('{')) {
        try {
          nested = jsonDecode(nested);
        } catch (_) {}
      }
      if (nested is Map) {
        final value = _string(nested, key);
        if (value != null) return value;
      }
    }
    return null;
  }

  static DateTime? _date(Map<dynamic, dynamic> payload, String key) {
    final value = _string(payload, key);
    return value == null ? null : DateTime.tryParse(value)?.toUtc();
  }

  static NotificationSound _soundFor(String type) {
    if (type == 'MESSAGE_RECEIVED' || type == 'SUPPORT_MESSAGE_RECEIVED')
      return NotificationSound.notification;
    if (type == 'PAYMENT_CONFIRMED' ||
        type == 'ORDER_COMPLETED' ||
        type == 'ORDER_DELIVERED')
      return NotificationSound.notification;
    if (type == 'PAYMENT_FAILED' ||
        type == 'ORDER_REJECTED' ||
        type == 'ORDER_CANCELLED' ||
        type == 'ORDER_EXPIRED')
      return NotificationSound.error;
    if (type == 'SILENT_SYNC') return NotificationSound.none;
    return NotificationSound.notification;
  }

  static NotificationPriority _priorityFor(String type) {
    if (type == 'MESSAGE_RECEIVED' || type == 'SUPPORT_MESSAGE_RECEIVED')
      return NotificationPriority.normal;
    if (type == 'SILENT_SYNC') return NotificationPriority.silent;
    if (type == 'ORDER_CANCELLED' ||
        type == 'PAYMENT_CONFIRMED' ||
        type == 'ORDER_READY' ||
        type == 'DRIVER_ARRIVED')
      return NotificationPriority.high;
    return NotificationPriority.normal;
  }
}
