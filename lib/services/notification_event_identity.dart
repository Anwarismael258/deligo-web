import 'dart:convert';

/// Stable identity used to deduplicate user-facing feedback across FCM and
/// Realtime delivery paths.
class NotificationEventIdentity {
  const NotificationEventIdentity._();

  static String? fromPayload(Map<dynamic, dynamic> payload) {
    final rawType = _value(payload, const ['type', 'event_type']);
    final type = rawType?.toUpperCase();
    final entityId = _value(payload, const [
      'entity_id',
      'order_id',
      'pedido_id',
    ]);
    final eventId =
        (type == 'DELIVERY_OPPORTUNITY'
            ? _value(payload, const ['dispatch_offer_id'])
            : null) ??
        _value(payload, const [
          'event_id',
          'source_event_id',
          'dispatch_attempt_id',
          'support_message_id',
          'message_id',
        ]) ??
        _value(payload, const ['id']);
    if (type == null || entityId == null || eventId == null) return null;
    return '${eventId.trim()}|$type|${entityId.trim()}';
  }

  static String? _value(Map<dynamic, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    for (final key in const ['metadata', 'data']) {
      var nested = payload[key];
      if (nested is String && nested.trim().startsWith('{')) {
        try {
          nested = jsonDecode(nested);
        } catch (_) {}
      }
      if (nested is Map) {
        final value = _value(nested, keys);
        if (value != null) return value;
      }
    }
    return null;
  }
}

class NotificationFeedbackDeduplicator {
  NotificationFeedbackDeduplicator({
    this.ttl = const Duration(minutes: 10),
    this.maxEntries = 512,
  });

  final Duration ttl;
  final int maxEntries;
  final Map<String, DateTime> _seen = <String, DateTime>{};

  void clear() => _seen.clear();

  int get length => _seen.length;

  bool claim(String? identity, {DateTime? now}) {
    final key = identity?.trim() ?? '';
    if (key.isEmpty) return true;
    final timestamp = now ?? DateTime.now();
    _seen.removeWhere((_, seenAt) => timestamp.difference(seenAt) > ttl);
    if (_seen.containsKey(key)) return false;
    _seen[key] = timestamp;
    while (_seen.length > maxEntries) {
      _seen.remove(_seen.keys.first);
    }
    return true;
  }
}

/// Runs one asynchronous initialization at a time, and allows retry after a
/// failed attempt rather than leaving the service permanently marked ready.
class AsyncSingleFlight {
  Future<void>? _inFlight;

  Future<void> run(Future<void> Function() operation) {
    final current = _inFlight;
    if (current != null) return current;

    final future = operation();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }
}
