class CourierDispatchUtils {
  CourierDispatchUtils._();

  static const Set<String> availableOrderStatuses = {
    'pending',
    'confirmed',
    'restaurant_confirmed',
    'accepted',
    'preparing',
    'ready',
  };

  static bool isAvailableStatus(String? status) {
    final normalized = status?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;
    return availableOrderStatuses.contains(normalized);
  }

  static bool isAvailableDeliveryRecord(Map<String, dynamic> record) {
    if (record.isEmpty) return false;
    final status = record['status']?.toString().trim().toLowerCase();
    final deliveryStatus = record['delivery_status']
        ?.toString()
        .trim()
        .toLowerCase();
    // A disponibilidade vem do estado do servidor; expiry é apenas uma
    // proteção visual adicional. O aceite valida o mesmo prazo atomicamente.
    if (deliveryStatus != 'searching') return false;
    final expiresAt = DateTime.tryParse(
      record['dispatch_expires_at']?.toString() ?? '',
    );
    if (!isAvailableStatus(status) || expiresAt == null) return false;
    if (!expiresAt.isAfter(DateTime.now().toUtc())) {
      return false;
    }
    final attemptId = record['dispatch_attempt_id']?.toString().trim();
    if (attemptId == null || attemptId.isEmpty) return false;

    final courierId = record['courier_id']?.toString().trim();
    if (courierId != null && courierId.isNotEmpty) {
      return false;
    }

    final deliveryType = record['delivery_type']
        ?.toString()
        .trim()
        .toLowerCase();
    // Entrega grátis continua a exigir estafeta; fee=0 não significa pickup.
    final isPickup = deliveryType == 'pickup';
    return !isPickup;
  }

  static bool belongsToCourier(Map<String, dynamic> record, String? courierId) {
    if (record.isEmpty) return false;
    final normalizedCourierId = courierId?.trim();
    if (normalizedCourierId == null || normalizedCourierId.isEmpty) {
      return false;
    }
    return record['courier_id']?.toString().trim() == normalizedCourierId;
  }

  static bool affectsCourierDashboardOrderChange({
    required Map<String, dynamic> previousRecord,
    required Map<String, dynamic> nextRecord,
    required String? currentCourierId,
  }) {
    return isAvailableDeliveryRecord(previousRecord) ||
        isAvailableDeliveryRecord(nextRecord) ||
        belongsToCourier(previousRecord, currentCourierId) ||
        belongsToCourier(nextRecord, currentCourierId);
  }

  static bool becameAvailableDelivery({
    required Map<String, dynamic> previousRecord,
    required Map<String, dynamic> nextRecord,
  }) {
    return !isAvailableDeliveryRecord(previousRecord) &&
        isAvailableDeliveryRecord(nextRecord);
  }

  static bool leftAvailableDelivery({
    required Map<String, dynamic> previousRecord,
    required Map<String, dynamic> nextRecord,
  }) {
    return isAvailableDeliveryRecord(previousRecord) &&
        !isAvailableDeliveryRecord(nextRecord);
  }
}
