import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_analytics_service.dart';

class NotificationDispatchService {
  NotificationDispatchService._();

  static final NotificationDispatchService instance =
      NotificationDispatchService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> sendToUser({
    required String userId,
    required String type,
    required String title,
    required String body,
    String? action,
    String? entityId,
    String priority = 'NORMAL',
    String channel = 'system',
    Map<String, dynamic>? data,
    Map<String, dynamic>? metadata,
    String? dispatchKey,
  }) async {
    if (userId.trim().isEmpty) return;

    final effectiveChannel =
        (type == 'ORDER_READY' || type == 'DRIVER_ASSIGNED') &&
            channel == 'system'
        ? 'client_alert'
        : channel;
    final payloadMetadata = <String, dynamic>{
      'dispatch_source': 'app_direct',
      'dispatch_retry_mode': 'backend_control',
      ...(metadata ?? const <String, dynamic>{}),
      ...(data ?? const <String, dynamic>{}),
    };

    if (_shouldQueueCriticalOrderNotification(
      type: type,
      channel: effectiveChannel,
      entityId: entityId,
    )) {
      final queued = await _sendCriticalOrderNotification(
        userId: userId,
        type: type,
        title: title,
        body: body,
        action: action,
        entityId: entityId!,
        priority: priority,
        channel: effectiveChannel,
        data: data,
        metadata: payloadMetadata,
      );
      if (!queued) {
        throw StateError(
          'Critical order notification queue failed for $type/$entityId',
        );
      }
      await FirebaseAnalyticsService.instance.logCampaignDelivery(
        type: type,
        campaignId:
            (metadata ?? const <String, dynamic>{})['campaign_id']?.toString(),
        restaurantId: (metadata ?? const <String, dynamic>{})['restaurant_id']
            ?.toString(),
      );
      return;
    }

    final headers = await _authHeaders();
    final response = await _supabase.functions.invoke(
      'notification-dispatch-control',
      headers: headers,
      body: {
        'user_id': userId,
        'type': type,
        'title': title,
        'body': body,
        'action': action,
        'entity_id': entityId,
        'priority': priority,
        'channel': effectiveChannel,
        'data': data ?? const <String, dynamic>{},
        'metadata': payloadMetadata,
        if (dispatchKey != null && dispatchKey.trim().isNotEmpty)
          'dispatch_key': dispatchKey.trim(),
      },
    );
    final responseData = response.data;
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        'notification-dispatch-control failed for $type/$entityId: ${response.data}',
      );
    }
    if (responseData is Map && responseData['success'] == false) {
      throw StateError(
        'notification-dispatch-control returned success=false for $type/$entityId',
      );
    }
    await FirebaseAnalyticsService.instance.logCampaignDelivery(
      type: type,
      campaignId: (metadata ?? const <String, dynamic>{})['campaign_id']
          ?.toString(),
      restaurantId: (metadata ?? const <String, dynamic>{})['restaurant_id']
          ?.toString(),
    );
  }

  Future<void> sendToAdmins({
    required String type,
    required String title,
    required String body,
    String? action,
    String? entityId,
    String priority = 'HIGH',
    String channel = 'admin',
    Map<String, dynamic>? data,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await _supabase.functions.invoke(
        'notification-dispatch-control',
        headers: headers,
        body: {
          'target_role': 'admin',
          'type': type,
          'title': title,
          'body': body,
          'action': action,
          'entity_id': entityId,
          'priority': priority,
          'channel': channel,
          'data': data ?? const <String, dynamic>{},
          'metadata': {
            'dispatch_source': 'app_direct',
            'dispatch_retry_mode': 'backend_control',
            ...(metadata ?? const <String, dynamic>{}),
            ...(data ?? const <String, dynamic>{}),
          },
        },
      );
      final responseData = response.data;
      if (response.status < 200 || response.status >= 300) {
        throw StateError(
          'notification-dispatch-control failed for admin broadcast: ${response.data}',
        );
      }
      if (responseData is Map && responseData['success'] == false) {
        throw StateError(
          'notification-dispatch-control returned success=false for admin broadcast',
        );
      }
    } catch (e) {
      debugPrint('Erro ao notificar admins: $e');
    }
  }

  Future<void> sendToRole({
    required String targetRole,
    required String type,
    required String title,
    required String body,
    String? action,
    String? entityId,
    String priority = 'HIGH',
    String channel = 'admin',
    Map<String, dynamic>? data,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await _supabase.functions.invoke(
        'notification-dispatch-control',
        headers: headers,
        body: {
          'target_role': targetRole,
          'type': type,
          'title': title,
          'body': body,
          'action': action,
          'entity_id': entityId,
          'priority': priority,
          'channel': channel,
          'data': data ?? const <String, dynamic>{},
          'metadata': {
            'dispatch_source': 'app_direct',
            'dispatch_retry_mode': 'backend_control',
            ...(metadata ?? const <String, dynamic>{}),
            ...(data ?? const <String, dynamic>{}),
          },
        },
      );
      final responseData = response.data;
      if (response.status < 200 || response.status >= 300) {
        throw StateError(
          'notification-dispatch-control failed for $targetRole broadcast: ${response.data}',
        );
      }
      if (responseData is Map && responseData['success'] == false) {
        throw StateError(
          'notification-dispatch-control returned success=false for $targetRole broadcast',
        );
      }
    } catch (e) {
      debugPrint('Erro ao notificar $targetRole: $e');
    }
  }

  Future<Map<String, String>?> _authHeaders() async {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  bool _shouldQueueCriticalOrderNotification({
    required String type,
    required String channel,
    required String? entityId,
  }) {
    final normalizedType = type.trim().toUpperCase();
    final normalizedChannel = channel.trim().toLowerCase();
    final orderId = entityId?.trim() ?? '';
    if (orderId.isEmpty) return false;

    if (normalizedType == 'DRIVER_AT_RESTAURANT') {
      return normalizedChannel == 'delivery' || normalizedChannel == 'restaurant';
    }

    if (normalizedType == 'ORDER_DELIVERED') {
      return normalizedChannel == 'delivery' || normalizedChannel == 'restaurant';
    }

    if (normalizedType == 'ORDER_READY_FOR_PICKUP') {
      return normalizedChannel == 'courier_dispatch';
    }

    if (normalizedType == 'ORDER_READY') {
      return normalizedChannel == 'client_alert' ||
          normalizedChannel == 'delivery' ||
          normalizedChannel == 'order' ||
          normalizedChannel == 'pickup';
    }

    if (normalizedType == 'DRIVER_ASSIGNED') {
      return normalizedChannel == 'client_alert' ||
          normalizedChannel == 'delivery' ||
          normalizedChannel == 'order' ||
          normalizedChannel == 'restaurant';
    }

    if (normalizedType == 'NEW_PAID_ORDER') {
      return normalizedChannel == 'restaurant';
    }

    if (normalizedType == 'ORDER_ACCEPTED' ||
        normalizedType == 'ORDER_PREPARING') {
      return normalizedChannel == 'order' || normalizedChannel == 'system';
    }

    return false;
  }

  String? _targetRoleForCriticalNotification({
    required String type,
    required String channel,
  }) {
    final normalizedType = type.trim().toUpperCase();
    final normalizedChannel = channel.trim().toLowerCase();

    if (normalizedType == 'DRIVER_AT_RESTAURANT') {
      return normalizedChannel == 'restaurant' ? 'restaurant_owner' : 'customer';
    }

    if (normalizedType == 'ORDER_DELIVERED') {
      if (normalizedChannel == 'restaurant') return 'restaurant_owner';
      if (normalizedChannel == 'delivery') return 'courier';
    }

    if (normalizedType == 'ORDER_READY_FOR_PICKUP') {
      return normalizedChannel == 'courier_dispatch' ? 'courier' : null;
    }

    if (normalizedType == 'ORDER_READY') {
      return normalizedChannel == 'client_alert' ||
              normalizedChannel == 'delivery' ||
              normalizedChannel == 'order' ||
              normalizedChannel == 'pickup'
          ? 'customer'
          : null;
    }

    if (normalizedType == 'DRIVER_ASSIGNED') {
      if (normalizedChannel == 'restaurant') return 'restaurant_owner';
      if (normalizedChannel == 'client_alert' ||
          normalizedChannel == 'delivery' ||
          normalizedChannel == 'order') {
        return 'customer';
      }
    }

    if (normalizedType == 'NEW_PAID_ORDER') {
      return normalizedChannel == 'restaurant' ? 'restaurant_owner' : null;
    }

    if (normalizedType == 'ORDER_ACCEPTED' ||
        normalizedType == 'ORDER_PREPARING') {
      return normalizedChannel == 'order' || normalizedChannel == 'system'
          ? 'customer'
          : null;
    }

    return null;
  }

  Future<bool> _sendCriticalOrderNotification({
    required String userId,
    required String type,
    required String title,
    required String body,
    required String entityId,
    String? action,
    required String priority,
    required String channel,
    Map<String, dynamic>? data,
    Map<String, dynamic>? metadata,
  }) async {
    final targetRole = _targetRoleForCriticalNotification(
      type: type,
      channel: channel,
    );
    if (targetRole == null) return false;

    try {
      final headers = await _authHeaders();
      final response = await _supabase.functions.invoke(
        'order-critical-notification-control',
        headers: headers,
        body: {
          'order_id': entityId,
          'target_role': targetRole,
          'target_user_id': userId,
          'type': type,
          'title': title,
          'body': body,
          'action': action,
          'priority': priority,
          'channel': channel,
          'data': data ?? const <String, dynamic>{},
          'metadata': metadata ?? const <String, dynamic>{},
        },
      );
      final payload = response.data;
      if (payload is Map) {
        return payload['success'] == true;
      }
      return false;
    } catch (error) {
      debugPrint(
        'NotificationDispatchService critical queue error for $type/$entityId: $error',
      );
      return false;
    }
  }
}
