import 'dart:convert';

class CourierOfferFeedbackDeadline {
  const CourierOfferFeedbackDeadline._();

  static DateTime? effective({
    required DateTime now,
    required Duration individualTimeout,
    DateTime? offerExpiresAt,
    DateTime? dispatchExpiresAt,
  }) {
    var deadline = now.add(individualTimeout);
    if (offerExpiresAt != null && offerExpiresAt.isBefore(deadline)) {
      deadline = offerExpiresAt;
    }
    if (dispatchExpiresAt != null && dispatchExpiresAt.isBefore(deadline)) {
      deadline = dispatchExpiresAt;
    }
    return deadline.isAfter(now) ? deadline : null;
  }

  /// Returns a local alert deadline only when the server supplied an
  /// identifiable, bounded courier offer. Legacy/malformed offers fail closed.
  static DateTime? fromCourierOfferPayload(
    Map<dynamic, dynamic> payload, {
    required DateTime now,
    Duration individualTimeout = const Duration(seconds: 25),
  }) {
    final type = _field(payload, const ['type', 'event_type'])?.toUpperCase();
    final channel = _field(payload, const ['channel'])?.toLowerCase();
    if (type != 'DELIVERY_OPPORTUNITY' && channel != 'courier_dispatch') {
      return null;
    }

    final attemptId = _field(payload, const ['dispatch_attempt_id']);
    final rawOfferExpiry = _field(payload, const ['offer_expires_at']);
    final rawDispatchExpiry = _field(payload, const ['dispatch_expires_at']);
    if (attemptId == null ||
        rawOfferExpiry == null ||
        rawDispatchExpiry == null) {
      return null;
    }

    final offerExpiry = DateTime.tryParse(rawOfferExpiry);
    final dispatchExpiry = DateTime.tryParse(rawDispatchExpiry);
    if (offerExpiry == null || dispatchExpiry == null) return null;

    return effective(
      now: now,
      individualTimeout: individualTimeout,
      offerExpiresAt: offerExpiry,
      dispatchExpiresAt: dispatchExpiry,
    );
  }

  static String? attemptIdFromPayload(Map<dynamic, dynamic> payload) =>
      _field(payload, const ['dispatch_attempt_id']);

  static bool isCourierOfferPayload(Map<dynamic, dynamic> payload) {
    final type = _field(payload, const ['type', 'event_type'])?.toUpperCase();
    final channel = _field(payload, const ['channel'])?.toLowerCase();
    return type == 'DELIVERY_OPPORTUNITY' || channel == 'courier_dispatch';
  }

  static String? _field(Map<dynamic, dynamic> payload, List<String> keys) {
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
        final value = _field(nested, keys);
        if (value != null) return value;
      }
    }
    return null;
  }
}
