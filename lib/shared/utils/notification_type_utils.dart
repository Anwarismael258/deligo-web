class NotificationTypeUtils {
  static String canonicalize(String? rawType) {
    final type = (rawType ?? 'SYSTEM_ALERT').trim();
    switch (type) {
      case 'COURIER_ASSIGNED':
      case 'ORDER_DRIVER_ASSIGNED':
        return 'DRIVER_ASSIGNED';
      case 'ORDER_ARRIVED':
      case 'DRIVER_AT_RESTAURANT':
        return 'DRIVER_ARRIVED';
      case 'REFUND_INITIATED':
        return 'REFUND_STARTED';
      default:
        return type;
    }
  }

  static bool isOrderLifecycleType(String? rawType) {
    switch (canonicalize(rawType)) {
      case 'NEW_ORDER':
      case 'NEW_PAID_ORDER':
      case 'PAYMENT_CONFIRMED':
      case 'PAYMENT_FAILED':
      case 'ORDER_ACCEPTED':
      case 'ORDER_PREPARING':
      case 'ORDER_READY':
      case 'ORDER_PICKED_UP':
      case 'ORDER_DELIVERED':
      case 'ORDER_COMPLETED':
      case 'ORDER_AUTO_COMPLETED':
      case 'ORDER_CANCELLED':
      case 'ORDER_EXPIRED':
      case 'ORDER_DISPUTED':
      case 'ORDER_REJECTED':
      case 'ORDER_DELAYED':
      case 'DELIVERY_EXTENSION_REQUESTED':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_ARRIVED':
        return true;
      default:
        return false;
    }
  }
}
