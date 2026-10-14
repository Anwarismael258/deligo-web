import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/router/app_router.dart';
import '../shared/models/app_notification.dart';
import '../shared/utils/notification_type_utils.dart';
import 'delivery_service.dart';
import 'firebase_analytics_service.dart';
import 'sound_controller.dart';

class NotificationRouterService {
  NotificationRouterService._internal();
  static final NotificationRouterService _instance =
      NotificationRouterService._internal();
  factory NotificationRouterService() => _instance;

  final SupabaseClient _supabase = Supabase.instance.client;
  final DeliveryService _deliveryService = DeliveryService();

  static const String courierAcceptActionId = 'courier_accept_delivery';
  static const String courierDismissActionId = 'courier_dismiss_delivery';

  String _dispatchAttemptIdFromPayload(Map<String, dynamic> payload) {
    for (final key in const ['dispatch_attempt_id', 'dispatch_group_id']) {
      final value = payload[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
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
        final normalized = Map<String, dynamic>.fromEntries(
          nested.entries.map(
            (entry) => MapEntry(entry.key.toString(), entry.value),
          ),
        );
        final attemptId = _dispatchAttemptIdFromPayload(normalized);
        if (attemptId.isNotEmpty) return attemptId;
      }
    }
    return '';
  }

  String _restaurantOrderRoute(String orderId) => Uri(
    path: '/restaurant-dashboard',
    queryParameters: {'tab': 'orders', 'orderId': orderId},
  ).toString();

  Future<void> _openOrderDestination({
    required String entityId,
    String? channel,
  }) async {
    final normalizedChannel = channel?.trim().toLowerCase();
    final currentRole = await _currentUserRole();
    if (normalizedChannel == 'restaurant' || currentRole == 'restaurant') {
      AppRouter.router.go(_restaurantOrderRoute(entityId));
      return;
    }
    AppRouter.router.push('/order/$entityId');
  }

  Future<String?> _currentUserRole() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return null;
    try {
      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      return profile?['role']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<String> _trackingRoute(String orderId) async {
    final currentRole = await _currentUserRole();
    final viewer = currentRole == 'courier' ? 'courier' : 'client';
    return Uri(
      path: '/tracking/$orderId',
      queryParameters: {'viewer': viewer},
    ).toString();
  }

  Future<void> handleStoredNotificationTap(Map<String, dynamic> row) async {
    final notification = AppNotification.fromMap(row);
    if (notification.type == 'DELIVERY_OPPORTUNITY' ||
        notification.channel.trim().toLowerCase() == 'courier_dispatch') {
      // Offers are authoritative only through the active Home card. A stale
      // notification entry must never expose offer details or revive an old
      // attempt when opened from the bell.
      AppRouter.router.go('/courier-dashboard');
      return;
    }
    await markAsRead(notification.id);
    await handlePayloadMap({
      'id': notification.id,
      'type': notification.type,
      'title': notification.title,
      'body': notification.body,
      'action': notification.action,
      'entity_id': notification.entityId,
      'priority': notification.priority,
      'channel': notification.channel,
      'metadata': notification.metadata,
      'data': row['data'],
      ...notification.metadata,
    });
  }

  Future<void> handlePayloadString(String? payload) async {
    if (payload == null || payload.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        await handlePayloadMap(decoded);
      }
    } catch (e) {
      debugPrint('NotificationRouter: payload invalido $e');
    }
  }

  Future<void> handleNotificationAction({
    required String actionId,
    Map<String, dynamic>? payload,
  }) async {
    final normalizedActionId = actionId.trim();
    if (normalizedActionId.isEmpty) return;

    final resolvedPayload = payload ?? const <String, dynamic>{};
    final orderId =
        resolvedPayload['entity_id']?.toString() ??
        resolvedPayload['order_id']?.toString() ??
        '';
    final dispatchAttemptId = _dispatchAttemptIdFromPayload(resolvedPayload);
    final dispatchGroupId =
        resolvedPayload['dispatch_group_id']?.toString().trim().isNotEmpty ==
            true
        ? resolvedPayload['dispatch_group_id'].toString().trim()
        : dispatchAttemptId;

    switch (normalizedActionId) {
      case courierAcceptActionId:
        await _handleCourierAcceptFromNotification(orderId, dispatchAttemptId);
        return;
      case courierDismissActionId:
        if (orderId.trim().isNotEmpty &&
            dispatchAttemptId.isNotEmpty &&
            dispatchGroupId == dispatchAttemptId) {
          await SoundController.instance.stopCourierDispatchLoop(
            orderId: orderId,
            attemptId: dispatchAttemptId,
          );
          await _deliveryService.declineDispatchOpportunity(
            orderId: orderId,
            dispatchGroupId: dispatchGroupId,
          );
        } else {
          debugPrint(
            'NotificationRouter: stale/legacy courier decline ignored without current attempt identity',
          );
        }
        AppRouter.router.go('/courier-dashboard');
        return;
      default:
        return handlePayloadMap(resolvedPayload);
    }
  }

  Future<void> handlePayloadMap(Map<String, dynamic> payload) async {
    final notificationId = payload['id']?.toString();
    if (notificationId != null && notificationId.isNotEmpty) {
      await markAsRead(notificationId);
    }

    final action = payload['action']?.toString();
    final type = NotificationTypeUtils.canonicalize(
      payload['type']?.toString(),
    );
    final entityId = _orderEntityIdFromPayload(payload);
    final channel = payload['channel']?.toString();
    final status = payload['status']?.toString();
    final reviewId =
        payload['review_id']?.toString() ??
        (payload['metadata'] is Map
            ? (payload['metadata'] as Map)['review_id']?.toString()
            : null) ??
        (payload['data'] is Map
            ? (payload['data'] as Map)['review_id']?.toString()
            : null) ??
        payload['entity_id']?.toString();
    final reviewType =
        payload['review_type']?.toString() ??
        (payload['metadata'] is Map
            ? (payload['metadata'] as Map)['review_type']?.toString()
            : null) ??
        (payload['data'] is Map
            ? (payload['data'] as Map)['review_type']?.toString()
            : null) ??
        'menu_item';

    await FirebaseAnalyticsService.instance.logNotificationOpen(
      type: type,
      entityId: entityId,
      action: action,
    );
    switch (action) {
      case 'OPEN_REVIEW':
        if (reviewId != null && reviewId.isNotEmpty) {
          AppRouter.router.push('/review/$reviewType/$reviewId');
        }
        return;
      case 'OPEN_DISH':
        final dishId = payload['menu_item_id']?.toString() ?? entityId;
        final restaurantId = payload['restaurant_id']?.toString();
        if (dishId != null && dishId.isNotEmpty) {
          if (restaurantId != null && restaurantId.isNotEmpty) {
            AppRouter.router.push('/restaurant/$restaurantId?dish=$dishId');
          } else {
            AppRouter.router.go('/restaurant-dashboard?tab=menu');
          }
        }
        return;
      case 'OPEN_ORDER':
        if (entityId != null && entityId.isNotEmpty) {
          if (channel?.trim().toLowerCase() == 'support' &&
              status == 'delivery_failed_otp') {
            final currentRole = await _currentUserRole();
            if (currentRole == 'admin') {
              AppRouter.router.go('/admin-dashboard');
              return;
            }
          }
          await _openOrderDestination(entityId: entityId, channel: channel);
        }
        return;
      case 'OPEN_ORDER_TRACKING':
        if (entityId != null && entityId.isNotEmpty) {
          final currentRole = await _currentUserRole();
          if (currentRole == 'restaurant') {
            AppRouter.router.go(_restaurantOrderRoute(entityId));
            return;
          }
          AppRouter.router.push(await _trackingRoute(entityId));
        }
        return;
      case 'OPEN_CHAT':
        if (entityId != null && entityId.isNotEmpty) {
          AppRouter.router.push('/chat/$entityId');
        }
        return;
      case 'OPEN_WALLET':
        AppRouter.router.push('/wallet');
        return;
      case 'OPEN_RESTAURANT_MARKETING':
        AppRouter.router.go('/restaurant-dashboard?tab=marketing');
        return;
      case 'OPEN_SUPPORT':
        AppRouter.router.push('/support');
        return;
      case 'OPEN_SUPPORT_DASHBOARD':
        AppRouter.router.go('/field-dashboard');
        return;
      case 'OPEN_SUPPORT_CHAT':
        if (entityId != null && entityId.isNotEmpty) {
          AppRouter.router.push('/support-ticket/$entityId');
        } else {
          AppRouter.router.push('/support');
        }
        return;
      case 'OPEN_KYC_REVIEW':
        final currentRole = await _currentUserRole();
        if (currentRole == 'admin' ||
            currentRole == 'field_agent' ||
            currentRole == 'support_agent' ||
            currentRole == 'ambassador') {
          AppRouter.router.go('/field-dashboard');
        } else {
          AppRouter.router.go('/kyc-pending');
        }
        return;
      case 'OPEN_KYC_PENDING':
        AppRouter.router.go('/kyc-pending');
        return;
      case 'OPEN_SETTINGS':
        AppRouter.router.push('/settings');
        return;
      case 'OPEN_HOME':
        AppRouter.router.go('/client-dashboard?tab=home');
        return;
      case 'OPEN_EXPLORE':
        AppRouter.router.go('/client-dashboard?tab=explore');
        return;
      case 'OPEN_PROMO':
        final campaignId =
            payload['campaign_id']?.toString() ?? 'firebase_campaign';
        final restaurantId = payload['restaurant_id']?.toString();
        final title = Uri.encodeComponent(
          payload['title']?.toString() ??
              payload['promo_title']?.toString() ??
              '',
        );
        final body = Uri.encodeComponent(
          payload['body']?.toString() ??
              payload['promo_body']?.toString() ??
              '',
        );
        final restaurantParam = restaurantId != null && restaurantId.isNotEmpty
            ? '&restaurant_id=$restaurantId'
            : '';
        AppRouter.router.go(
          '/promo?campaign_id=$campaignId$restaurantParam&title=$title&body=$body&source=push',
        );
        return;
    }

    switch (type) {
      case 'ORDER_ACCEPTED':
      case 'ORDER_PREPARING':
      case 'PAYMENT_CONFIRMED':
      case 'NEW_ORDER':
      case 'NEW_PAID_ORDER':
      case 'PAYMENT_FAILED':
      case 'ORDER_READY':
      case 'ORDER_DELIVERED':
      case 'ORDER_COMPLETED':
      case 'ORDER_AUTO_COMPLETED':
      case 'ORDER_CANCELLED':
      case 'ORDER_EXPIRED':
      case 'ORDER_DISPUTED':
      case 'DELIVERY_EXTENSION_REQUESTED':
      case 'ORDER_DELAYED':
      case 'REFUND_COMPLETED':
      case 'REFUND_STARTED':
      case 'PAYMENT_RELEASED':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_ARRIVED':
      case 'MESSAGE_RECEIVED':
      case 'ORDER_REJECTED':
        if (entityId != null && entityId.isNotEmpty) {
          await _openOrderDestination(entityId: entityId, channel: channel);
        }
        break;
      case 'ORDER_PICKED_UP':
      case 'ORDER_READY_FOR_PICKUP':
      case 'NEW_DRIVER_ORDER':
        if (entityId != null && entityId.isNotEmpty) {
          AppRouter.router.push(await _trackingRoute(entityId));
        }
        break;
      case 'SUPPORT_UPDATED':
      case 'TICKET_RESOLVED':
      case 'SUPPORT_MESSAGE_RECEIVED':
      case 'EVENT_TICKET_SOLD':
      case 'PUSH_DISABLED':
        if (type == 'EVENT_TICKET_SOLD') {
          AppRouter.router.go('/restaurant-dashboard?tab=marketing');
          break;
        }
        final currentRole = await _currentUserRole();
        if (type == 'SUPPORT_MESSAGE_RECEIVED' &&
            entityId != null &&
            entityId.isNotEmpty) {
          AppRouter.router.push('/support-ticket/$entityId');
        } else if (currentRole == 'support_agent' || currentRole == 'admin') {
          AppRouter.router.go('/field-dashboard');
        } else {
          AppRouter.router.push('/support');
        }
        break;
      case 'kyc_approved':
      case 'kyc_rejected':
        AppRouter.router.go('/kyc-pending');
        break;
      case 'OPEN_BLOCKED_ACCOUNT':
        AppRouter.router.go('/blocked-account');
        break;
      case 'OPEN_LOGIN':
        AppRouter.router.go('/login?status=unblocked');
        break;
      case 'EMAIL_CONFIRMATION_REQUIRED':
      case 'SESSION_EXPIRED':
        AppRouter.router.push('/settings');
        break;
      case 'CASHBACK_RECEIVED':
        AppRouter.router.push('/wallet');
        break;
      case 'PROMO_OFFER':
      case 'FREE_DELIVERY_PROMO':
      case 'RETENTION_REMINDER':
        final campaignId =
            payload['campaign_id']?.toString() ?? 'firebase_campaign';
        final restaurantId = payload['restaurant_id']?.toString();
        final title = Uri.encodeComponent(payload['title']?.toString() ?? '');
        final body = Uri.encodeComponent(payload['body']?.toString() ?? '');
        final restaurantParam = restaurantId != null && restaurantId.isNotEmpty
            ? '&restaurant_id=$restaurantId'
            : '';
        AppRouter.router.go(
          '/promo?campaign_id=$campaignId$restaurantParam&title=$title&body=$body&source=notification_type',
        );
        break;
      default:
        break;
    }
  }

  String? _orderEntityIdFromPayload(Map<String, dynamic> payload) {
    String? read(Object? value) {
      if (value == null) return null;
      if (value is Map) {
        for (final key in const ['entity_id', 'order_id', 'pedido_id']) {
          final candidate = value[key]?.toString().trim() ?? '';
          if (candidate.isNotEmpty) return candidate;
        }
        for (final key in const ['data', 'metadata', 'payload']) {
          final nested = read(value[key]);
          if (nested != null && nested.isNotEmpty) return nested;
        }
        return null;
      }
      final raw = value.toString().trim();
      if (raw.isEmpty) return null;
      if (raw.startsWith('{') && raw.endsWith('}')) {
        try {
          final decoded = jsonDecode(raw);
          return read(decoded);
        } catch (_) {}
      }
      return null;
    }

    return read(payload);
  }

  Future<void> markAsRead(String notificationId) async {
    if (notificationId.trim().isEmpty) return;
    try {
      await _supabase.rpc(
        'ack_push_notification_delivery',
        params: {
          'p_notification_id': notificationId,
          'p_state': 'opened',
          'p_context': const <String, dynamic>{
            'ack_source': 'notification_open',
          },
        },
      );
    } catch (e) {
      debugPrint('NotificationRouter: erro ao marcar como aberta $e');
      try {
        await _supabase
            .from('push_notifications')
            .update({'read_at': DateTime.now().toIso8601String()})
            .eq('id', notificationId)
            .isFilter('read_at', null);
      } catch (inner) {
        debugPrint('NotificationRouter: fallback read_at error $inner');
      }
    }
  }

  Future<void> _handleCourierAcceptFromNotification(
    String orderId,
    String dispatchAttemptId,
  ) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) {
      AppRouter.router.go('/courier-dashboard');
      return;
    }
    if (dispatchAttemptId.trim().isEmpty) {
      debugPrint(
        'NotificationRouter: courier quick accept blocked because the notification has no dispatch attempt id',
      );
      AppRouter.router.go('/courier-dashboard');
      return;
    }

    await SoundController.instance.stopCourierDispatchLoop(
      orderId: normalizedOrderId,
      attemptId: dispatchAttemptId,
    );
    final courierId = _supabase.auth.currentUser?.id.trim() ?? '';
    if (courierId.isEmpty) {
      AppRouter.router.go('/login');
      return;
    }

    final result = await _deliveryService.acceptDelivery(
      orderId: normalizedOrderId,
      courierId: courierId,
      dispatchAttemptId: dispatchAttemptId,
    );

    if (result.success) {
      AppRouter.router.push(await _trackingRoute(normalizedOrderId));
      return;
    }

    debugPrint(
      'NotificationRouter: courier quick accept failed for $normalizedOrderId: ${result.code ?? result.message}',
    );
    AppRouter.router.go('/courier-dashboard');
  }
}
