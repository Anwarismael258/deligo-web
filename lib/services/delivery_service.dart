import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_env.dart';
import 'notification_dispatch_service.dart';
import 'trust_safety_service.dart';
import '../shared/models/order.dart';

class DeliveryOtpVerificationResult {
  final bool success;
  final String message;
  final String? status;

  const DeliveryOtpVerificationResult({
    required this.success,
    required this.message,
    this.status,
  });
}

class DeliveryOtpSmsResult {
  final bool success;
  final bool duplicate;
  final String message;

  const DeliveryOtpSmsResult({
    required this.success,
    required this.message,
    this.duplicate = false,
  });
}

class DeliveryAcceptResult {
  final bool success;
  final String message;
  final String? code;

  const DeliveryAcceptResult({
    required this.success,
    required this.message,
    this.code,
  });
}

class CourierOfferDetails {
  final double courierAmount;
  final int itemCount;
  final List<OrderItem> items;

  const CourierOfferDetails({
    required this.courierAmount,
    required this.itemCount,
    required this.items,
  });

  factory CourierOfferDetails.fromMap(Map<String, dynamic> map) {
    final rawAmount = map['courier_amount'];
    if (rawAmount is! num) {
      throw const FormatException('courier_offer_split_not_ready');
    }
    final rawItems = map['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((rawItem) {
                final item = Map<String, dynamic>.from(rawItem);
                return OrderItem.fromMap({
                  ...item,
                  'menu_items': {
                    'name': item['name'],
                    'image_url': item['image_url'],
                  },
                });
              })
              .toList(growable: false)
        : const <OrderItem>[];
    return CourierOfferDetails(
      courierAmount: rawAmount.toDouble(),
      itemCount:
          (map['item_count'] as num?)?.toInt() ??
          items.fold<int>(0, (count, item) => count + item.quantity),
      items: items,
    );
  }
}

class DeliveryService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final NotificationDispatchService _notificationDispatch =
      NotificationDispatchService.instance;
  static const double _notifyRadiusKm = 5;
  static const int _defaultAvailableDeliveryLimit = 30;
  static const int _maxCourierNotificationCandidates = 75;
  static const int _maxNearbyCourierNotifications = 20;
  static const Duration _courierLocationFreshness = Duration(minutes: 20);

  Future<void> _syncOrderCourierAssignment({
    required String orderId,
    required String courierId,
  }) async {
    final normalizedCourierId = courierId.trim();
    if (normalizedCourierId.isEmpty) return;
    try {
      await _supabase
          .from('orders')
          .update({
            'courier_id': normalizedCourierId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);
    } catch (error) {
      debugPrint(
        'DeliveryService._syncOrderCourierAssignment error for $orderId: $error',
      );
    }
  }

  Future<Map<String, String>?> _authHeaders() async {
    final headers = <String, String>{};
    final token = _supabase.auth.currentSession?.accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final anonKey = AppEnv.supabaseAnonKey;
    if (anonKey.isNotEmpty) {
      headers['apikey'] = anonKey;
    }
    return headers.isEmpty ? null : headers;
  }

  Future<Map<String, dynamic>?> _invokeFunctionDirect(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    final headers = await _authHeaders();
    final supabaseUrl = AppEnv.supabaseUrl;
    if (headers == null || supabaseUrl.isEmpty) return null;

    final response = await http
        .post(
          Uri.parse('$supabaseUrl/functions/v1/$functionName'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body ?? const <String, dynamic>{}),
        )
        .timeout(const Duration(seconds: 12));

    if (response.body.trim().isEmpty) {
      return <String, dynamic>{
        'success': response.statusCode >= 200 && response.statusCode < 300,
      };
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{
      'success': response.statusCode >= 200 && response.statusCode < 300,
      'data': decoded,
    };
  }

  Future<bool> _enqueueCourierDispatchBroadcast({
    required String orderId,
    required String orderRef,
    required String dispatchAttemptId,
    required List<Map<String, dynamic>> targets,
  }) async {
    final response = await _invokeFunctionDirect(
      'courier-dispatch-control',
      body: {
        'action': 'enqueue',
        'order_id': orderId,
        'dispatch_attempt_id': dispatchAttemptId,
        'dispatch_group_id': dispatchAttemptId,
        'order_ref': orderRef,
        'targets': targets,
      },
    );
    return response?['success'] == true;
  }

  Future<bool> enqueueCustomerRetry({
    required String orderId,
    required String dispatchAttemptId,
  }) async {
    try {
      final response = await _invokeFunctionDirect(
        'courier-dispatch-control',
        body: {
          'action': 'enqueue',
          'order_id': orderId,
          'dispatch_attempt_id': dispatchAttemptId,
          'dispatch_group_id': dispatchAttemptId,
          'dispatch_source': 'customer_retry',
          'targets': const <Map<String, dynamic>>[],
        },
      );
      return response?['success'] == true;
    } catch (error) {
      debugPrint('DeliveryService.enqueueCustomerRetry error: $error');
      return false;
    }
  }

  Future<void> _cancelCourierDispatchBroadcast({
    required String orderId,
    required String reason,
  }) async {
    try {
      await _invokeFunctionDirect(
        'courier-dispatch-control',
        body: {'action': 'cancel', 'order_id': orderId, 'reason': reason},
      );
    } catch (error) {
      debugPrint(
        'DeliveryService._cancelCourierDispatchBroadcast error for $orderId: $error',
      );
    }
  }

  String _orderRef(String orderId) {
    final compact = orderId.replaceAll('-', '').toUpperCase();
    final short = compact.length >= 6 ? compact.substring(0, 6) : compact;
    return '#$short';
  }

  String _courierDisplayName(String rawName) {
    final trimmed = rawName.trim();
    return trimmed.isNotEmpty ? trimmed : 'Um estafeta';
  }

  Future<void> _notifyParticipantsAfterCourierAccepted({
    required String orderId,
    required String courierName,
  }) async {
    try {
      final orderRow = await _supabase
          .from('orders')
          .select('client_id, customer_id, restaurant_id')
          .eq('id', orderId)
          .maybeSingle();
      if (orderRow == null) return;

      final orderRef = _orderRef(orderId);
      final courierLabel = _courierDisplayName(courierName);
      final clientId = (orderRow['client_id'] ?? orderRow['customer_id'])
          ?.toString()
          .trim();
      if (clientId != null && clientId.isNotEmpty) {
        await _notificationDispatch.sendToUser(
          userId: clientId,
          type: 'DRIVER_ASSIGNED',
          title: 'Estafeta a caminho do restaurante',
          body:
              '$courierLabel aceitou o pedido e ja esta a caminho do restaurante.',
          action: 'OPEN_ORDER_TRACKING',
          entityId: orderId,
          priority: 'HIGH',
          channel: 'order',
          data: {
            'order_id': orderId,
            'order_ref': orderRef,
            'courier_name': courierLabel,
          },
          metadata: {
            'order_id': orderId,
            'order_ref': orderRef,
            'courier_name': courierLabel,
          },
        );
      }

      final restaurantId = orderRow['restaurant_id']?.toString().trim();
      if (restaurantId != null && restaurantId.isNotEmpty) {
        final restaurant = await _supabase
            .from('restaurants')
            .select('owner_id')
            .eq('id', restaurantId)
            .maybeSingle();
        final ownerId = restaurant?['owner_id']?.toString().trim();
        if (ownerId != null && ownerId.isNotEmpty) {
          await _notificationDispatch.sendToUser(
            userId: ownerId,
            type: 'DRIVER_ASSIGNED',
            title: 'Estafeta a caminho do restaurante',
            body:
                '$courierLabel aceitou o pedido e ja esta a caminho do restaurante.',
            action: 'OPEN_ORDER_TRACKING',
            entityId: orderId,
            priority: 'HIGH',
            channel: 'restaurant',
            data: {
              'order_id': orderId,
              'order_ref': orderRef,
              'courier_name': courierLabel,
            },
            metadata: {
              'order_id': orderId,
              'order_ref': orderRef,
              'courier_name': courierLabel,
              'restaurant_id': restaurantId,
            },
          );
        }
      }
    } catch (error) {
      debugPrint(
        'DeliveryService._notifyParticipantsAfterCourierAccepted error: $error',
      );
    }
  }

  /// Buscar entregas disponíveis para o entregador
  Future<List<Order>> getAvailableDeliveries({
    int limit = _defaultAvailableDeliveryLimit,
  }) async {
    try {
      // The backend returns only offers targeted to this authenticated,
      // eligible courier. It deliberately excludes customer/address/payment
      // fields; the official split and items come from the detail RPC below.
      final response = await _supabase.rpc('get_courier_available_offers');
      final rows = response is List
          ? response.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : <Map<String, dynamic>>[];
      final availableRows = rows.take(limit).toList(growable: false);

      debugPrint(
        '[COURIER] targeted offer rows=${rows.length} '
        'eligible=${availableRows.length} '
        'ids=${availableRows.map((row) => row['id']).join(',')}',
      );

      return availableRows.map(Order.fromMap).toList();
    } catch (e) {
      debugPrint('[COURIER] available query error: $e');
      return [];
    }
  }

  Future<CourierOfferDetails?> getCourierOfferDetails(String orderId) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return null;
    final response = await _supabase.rpc(
      'get_courier_offer_details',
      params: {'p_order_id': normalizedOrderId},
    );
    if (response is! Map) return null;
    final map = Map<String, dynamic>.from(response);
    if (map['order_id']?.toString() != normalizedOrderId) return null;
    return CourierOfferDetails.fromMap(map);
  }

  /// Aceitar uma entrega
  Future<DeliveryAcceptResult> acceptDelivery({
    required String orderId,
    required String courierId,
    required String dispatchAttemptId,
  }) async {
    try {
      final expectedAttemptId = dispatchAttemptId.trim();
      if (expectedAttemptId.isEmpty) {
        return const DeliveryAcceptResult(
          success: false,
          code: 'dispatch_attempt_required',
          message: 'Esta oferta expirou. Atualize a lista de entregas.',
        );
      }
      final orderRow = await _supabase
          .from('orders')
          .select('delivery_type, delivery_fee')
          .eq('id', orderId)
          .maybeSingle();
      final deliveryType = orderRow?['delivery_type']?.toString();
      // A taxa pode ser zero quando existe entrega grátis. O método real do
      // pedido é determinado por delivery_type, não pelo valor da taxa.
      final isPickup = deliveryType == 'pickup';
      if (isPickup) {
        return const DeliveryAcceptResult(
          success: false,
          code: 'order_not_delivery',
          message: 'Este pedido nao precisa de estafeta.',
        );
      }

      final rpcResponse = await _supabase.rpc(
        'courier_accept_delivery',
        params: {
          'p_order_id': orderId,
          'p_dispatch_attempt_id': expectedAttemptId,
        },
      );
      final updated = rpcResponse is Map
          ? Map<String, dynamic>.from(rpcResponse)
          : null;

      if (updated == null) {
        return const DeliveryAcceptResult(
          success: false,
          code: 'accept_delivery_failed',
          message: 'Nao foi possivel aceitar a entrega agora.',
        );
      }

      final assignedCourierId = updated['courier_id']?.toString() ?? courierId;

      // The RPC above is the authoritative acceptance. Everything below is
      // enrichment/notification and must not turn a successful acceptance
      // into a false failure shown to the courier.
      try {
        Map<String, dynamic>? restaurant;
        Map<String, dynamic>? courierPresence;
        try {
          // Restaurant coordinates are still needed for pickup tracking even
          // though assignment notifications now come from the event worker.
          restaurant = await _supabase
              .from('restaurants')
              .select('latitude, longitude')
              .eq('id', updated['restaurant_id'])
              .maybeSingle();
        } catch (error) {
          debugPrint(
            'DeliveryService.acceptDelivery restaurant lookup error: $error',
          );
        }
        try {
          courierPresence = await _supabase
              .from('couriers')
              .select('current_latitude, current_longitude')
              .eq('id', assignedCourierId)
              .maybeSingle();
        } catch (error) {
          debugPrint(
            'DeliveryService.acceptDelivery courier presence lookup error: $error',
          );
        }

        final deliveryLat = (updated['delivery_latitude'] as num?)?.toDouble();
        final deliveryLng = (updated['delivery_longitude'] as num?)?.toDouble();
        final pickupLat = (restaurant?['latitude'] as num?)?.toDouble();
        final pickupLng = (restaurant?['longitude'] as num?)?.toDouble();
        final currentLat = (courierPresence?['current_latitude'] as num?)
            ?.toDouble();
        final currentLng = (courierPresence?['current_longitude'] as num?)
            ?.toDouble();

        // Criar ou atualizar o registro de entrega sem falhar em retry.
        final deliveryPayload = <String, dynamic>{
          'order_id': orderId,
          'courier_id': assignedCourierId,
          'status': 'courier_assigned',
          'pickup_latitude': pickupLat,
          'pickup_longitude': pickupLng,
          'delivery_latitude': deliveryLat,
          'delivery_longitude': deliveryLng,
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (currentLat != null) {
          deliveryPayload['current_latitude'] = currentLat;
        }
        if (currentLng != null) {
          deliveryPayload['current_longitude'] = currentLng;
        }
        await _supabase
            .from('deliveries')
            .upsert(deliveryPayload, onConflict: 'order_id');
        await _syncOrderCourierAssignment(
          orderId: orderId,
          courierId: assignedCourierId,
        );
        await _cancelCourierDispatchBroadcast(
          orderId: orderId,
          reason: 'claimed_by_courier',
        );

        // Inserir mensagem automática no chat
        String courierName = 'Entregador';
        try {
          final profile = await _supabase
              .from('profiles')
              .select('full_name')
              .eq('id', assignedCourierId)
              .maybeSingle();
          courierName = profile?['full_name'] ?? courierName;
        } catch (error) {
          debugPrint(
            'DeliveryService.acceptDelivery courier profile error: $error',
          );
        }

        try {
          await _supabase.from('messages').insert({
            'order_id': orderId,
            'sender_id': assignedCourierId,
            'sender_name': courierName,
            'sender_role': 'courier',
            'text':
                'Aceitei a entrega. Vou agora para o restaurante recolher o pedido.',
          });
        } catch (error) {
          debugPrint(
            'DeliveryService.acceptDelivery auto-message error: $error',
          );
        }

        // Assignment notifications are emitted by the canonical order-event
        // worker. Do not dispatch them again from the client after the
        // authoritative acceptance RPC, otherwise the customer/restaurant
        // can receive duplicate alerts.
      } catch (error) {
        debugPrint(
          'DeliveryService.acceptDelivery post-accept enrichment error: $error',
        );
      }

      return const DeliveryAcceptResult(
        success: true,
        message: 'Entrega aceite! Siga agora para o restaurante.',
      );
    } on PostgrestException catch (e) {
      debugPrint('Erro ao aceitar entrega (Postgrest): ${e.message}');
      final rawMessage = e.message.trim();
      switch (rawMessage) {
        case 'courier_already_assigned':
          return const DeliveryAcceptResult(
            success: false,
            code: 'courier_already_assigned',
            message: 'Outro estafeta ja ficou com este pedido.',
          );
        case 'invalid_order_status':
          return const DeliveryAcceptResult(
            success: false,
            code: 'invalid_order_status',
            message: 'Este pedido ja nao esta disponivel para aceite.',
          );
        case 'order_not_found':
          return const DeliveryAcceptResult(
            success: false,
            code: 'order_not_found',
            message: 'O pedido ja nao foi encontrado.',
          );
        case 'order_not_delivery':
          return const DeliveryAcceptResult(
            success: false,
            code: 'order_not_delivery',
            message: 'Este pedido nao precisa de estafeta.',
          );
        case 'not_courier':
          return const DeliveryAcceptResult(
            success: false,
            code: 'not_courier',
            message: 'Esta conta nao esta autorizada como estafeta.',
          );
        case 'dispatch_attempt_expired':
        case 'courier_not_targeted_for_dispatch_attempt':
          return const DeliveryAcceptResult(
            success: false,
            code: 'dispatch_attempt_expired',
            message:
                'Esta oferta ja expirou ou nao foi atribuida a esta conta.',
          );
        default:
          return DeliveryAcceptResult(
            success: false,
            code: rawMessage.isEmpty ? 'accept_delivery_failed' : rawMessage,
            message: rawMessage.isEmpty
                ? 'Nao foi possivel aceitar a entrega agora.'
                : 'Falha ao aceitar entrega: $rawMessage',
          );
      }
    } catch (e) {
      debugPrint('Erro ao aceitar entrega: $e');
      return const DeliveryAcceptResult(
        success: false,
        code: 'accept_delivery_failed',
        message: 'Algo nao correu bem ao aceitar a entrega. Tente novamente.',
      );
    }
  }

  /// Atualizar status da entrega
  Future<bool> updateDeliveryStatus(String orderId, String status) async {
    try {
      final rpcResponse = await _supabase.rpc(
        'courier_update_order_status',
        params: {'p_order_id': orderId, 'p_status': status},
      );
      final updated = rpcResponse is Map
          ? Map<String, dynamic>.from(rpcResponse)
          : null;
      final updatedStatus = updated?['status']?.toString();
      if (updated == null || updatedStatus != status) {
        return false;
      }

      // The RPC is the authoritative, transactional order transition. The
      // deliveries row is a legacy/read-model mirror and may be protected by
      // a stricter RLS policy. Its failure must not turn a confirmed order
      // transition into a false negative in the Home UI.
      try {
        await _supabase
            .from('deliveries')
            .update({
              'status': status,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('order_id', orderId);
      } catch (mirrorError) {
        debugPrint(
          'DeliveryService.updateDeliveryStatus mirror warning for $orderId: $mirrorError',
        );
      }
      final activeCourierId = updated['courier_id']?.toString().trim() ?? '';
      if (activeCourierId.isNotEmpty) {
        await _syncOrderCourierAssignment(
          orderId: orderId,
          courierId: activeCourierId,
        );
      }

      if (status == 'in_transit') {
        try {
          // Push notifications for this status now flow through the
          // event-dispatch worker. Keep OTP SMS here.
          final smsResult = await sendDeliveryOtpSms(orderId: orderId);
          if (!smsResult.success && !smsResult.duplicate) {
            debugPrint(
              'DeliveryService.updateDeliveryStatus sendDeliveryOtpSms warning: ${smsResult.message}',
            );
          }
        } catch (error) {
          debugPrint(
            'DeliveryService.updateDeliveryStatus in_transit notification error: $error',
          );
        }
      }

      return true;
    } catch (e) {
      debugPrint('Erro ao atualizar status: $e');
      return false;
    }
  }

  Future<void> updateCourierLocation({
    required String orderId,
    required double latitude,
    required double longitude,
    double? speedMetersPerSecond,
    double? headingDegrees,
    double? accuracyMeters,
    int? batteryPercent,
    DateTime? recordedAt,
  }) async {
    try {
      await _supabase
          .from('deliveries')
          .update({
            'current_latitude': latitude,
            'current_longitude': longitude,
            'current_speed_mps': speedMetersPerSecond,
            'current_heading_degrees': headingDegrees,
            'current_accuracy_meters': accuracyMeters,
            'courier_battery_percent': batteryPercent,
            'location_recorded_at': (recordedAt ?? DateTime.now())
                .toUtc()
                .toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('order_id', orderId);
      final courierId = _supabase.auth.currentUser?.id;
      if (courierId != null && courierId.isNotEmpty) {
        await _supabase
            .from('orders')
            .update({'updated_at': DateTime.now().toIso8601String()})
            .eq('id', orderId)
            .eq('courier_id', courierId);
      }
      await TrustSafetyService.instance.logEvent(
        'location_update',
        metadata: {
          'order_id': orderId,
          'latitude': latitude,
          'longitude': longitude,
          'speed_mps': speedMetersPerSecond,
          'heading_degrees': headingDegrees,
          'accuracy_meters': accuracyMeters,
          'battery_percent': batteryPercent,
        },
      );
    } catch (e) {
      debugPrint('Erro ao atualizar localizacao: $e');
    }
  }

  /// Marcar entregador como chegou
  Future<bool> courierArrived(String orderId) async {
    return updateDeliveryStatus(orderId, 'arrived');
  }

  Future<bool> notifyCourierArrivedAtRestaurant(String orderId) async {
    try {
      final confirmation = await _supabase.rpc(
        'courier_confirm_restaurant_arrival',
        params: {'p_order_id': orderId},
      );
      if (confirmation is! Map || confirmation['success'] != true) {
        debugPrint('Cheguei recusado [$orderId]: resposta RPC inválida');
        return false;
      }
      final delivery = await _supabase
          .from('deliveries')
          .select(
            'courier_arrived_at, current_latitude, current_longitude, current_accuracy_meters',
          )
          .eq('order_id', orderId)
          .maybeSingle();
      if (delivery?['courier_arrived_at'] != null) return true;

      final orderRow = await _supabase
          .from('orders')
          .select('client_id, customer_id, restaurant_id')
          .eq('id', orderId)
          .maybeSingle();
      final restaurantId = orderRow?['restaurant_id']?.toString().trim() ?? '';
      if (restaurantId.isEmpty) {
        debugPrint(
          'Cheguei recusado [$orderId]: restaurant_id ausente',
        );
        return false;
      }

      final restaurant = await _supabase
          .from('restaurants')
          .select('latitude, longitude')
          .eq('id', restaurantId)
          .maybeSingle();
      final restaurantLat = (restaurant?['latitude'] as num?)?.toDouble();
      final restaurantLng = (restaurant?['longitude'] as num?)?.toDouble();
      final courierLat = (delivery?['current_latitude'] as num?)?.toDouble();
      final courierLng = (delivery?['current_longitude'] as num?)?.toDouble();
      final accuracy =
          (delivery?['current_accuracy_meters'] as num?)?.toDouble();

      if (restaurantLat == null ||
          restaurantLng == null ||
          courierLat == null ||
          courierLng == null) {
        debugPrint(
          'Cheguei recusado [$orderId]: coordenadas ausentes '
          'restaurant=($restaurantLat,$restaurantLng) '
          'courier=($courierLat,$courierLng)',
        );
        return false;
      }
      if (accuracy != null && accuracy > 100) {
        debugPrint(
          'Cheguei recusado [$orderId]: GPS impreciso accuracy=$accuracy m',
        );
        return false;
      }

      final distanceMeters =
          _distanceKm(courierLat, courierLng, restaurantLat, restaurantLng) *
          1000;
      debugPrint(
        'Cheguei [$orderId]: restaurant=($restaurantLat,$restaurantLng) '
        'courier=($courierLat,$courierLng) distance=${distanceMeters.toStringAsFixed(1)}m '
        'accuracy=${accuracy ?? 'unknown'}m',
      );
      if (distanceMeters > 50) {
        return false;
      }

      await _supabase
          .from('deliveries')
          .update({
            'courier_arrived_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('order_id', orderId);

      final orderRef = _orderRef(orderId);
      final clientId = (orderRow?['client_id'] ?? orderRow?['customer_id'])
          ?.toString();
      if (clientId != null && clientId.isNotEmpty) {
        await _notificationDispatch.sendToUser(
          userId: clientId,
          type: 'DRIVER_AT_RESTAURANT',
          title: 'Estafeta chegou ao restaurante',
          body: 'O estafeta ja esta no restaurante para recolher o produto.',
          action: 'OPEN_ORDER_TRACKING',
          entityId: orderId,
          priority: 'HIGH',
          channel: 'delivery',
          data: {'order_id': orderId, 'order_ref': orderRef},
          metadata: {'order_id': orderId, 'order_ref': orderRef},
        );
      }

      final courierId = _supabase.auth.currentUser?.id;
      if (courierId != null && courierId.isNotEmpty) {
        await _supabase.from('messages').insert({
          'order_id': orderId,
          'sender_id': courierId,
          'sender_name': 'Estafeta',
          'sender_role': 'courier',
          'text': 'Cheguei ao restaurante e estou a aguardar a recolha.',
        });
      }

      final restaurantIdForOwner = orderRow?['restaurant_id']?.toString();
      if (restaurantIdForOwner != null && restaurantIdForOwner.isNotEmpty) {
        final restaurant = await _supabase
            .from('restaurants')
            .select('owner_id, name')
            .eq('id', restaurantIdForOwner)
            .maybeSingle();
        final ownerId = restaurant?['owner_id']?.toString();
        if (ownerId != null && ownerId.isNotEmpty) {
          await _notificationDispatch.sendToUser(
            userId: ownerId,
            type: 'DRIVER_AT_RESTAURANT',
            title: 'Estafeta chegou ao restaurante',
            body: 'O estafeta ja esta no restaurante para recolher o produto.',
            action: 'OPEN_ORDER',
            entityId: orderId,
            priority: 'HIGH',
            channel: 'restaurant',
            data: {'order_id': orderId, 'order_ref': orderRef},
            metadata: {
              'order_id': orderId,
              'order_ref': orderRef,
              'restaurant_id': restaurantIdForOwner,
            },
          );
        }
      }
      return true;
    } catch (e) {
      debugPrint('Erro ao notificar chegada ao restaurante: $e');
      return false;
    }
  }

  /// Marcar entrega como concluida
  Future<bool> completeDelivery(String orderId) async {
    return updateDeliveryStatus(orderId, 'delivered');
  }

  Future<DeliveryOtpSmsResult> sendDeliveryOtpSms({
    required String orderId,
    bool force = false,
    String reason = 'initial',
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'twilio-sms',
        headers: await _authHeaders(),
        body: {
          'kind': 'delivery_otp',
          'order_id': orderId,
          'force': force,
          'reason': reason,
        },
      );

      final payload = response.data;
      if (payload is! Map) {
        return const DeliveryOtpSmsResult(
          success: false,
          message: 'Nao foi possivel enviar o SMS do codigo agora.',
        );
      }

      final data = Map<String, dynamic>.from(payload);
      final nested = data['data'] is Map
          ? Map<String, dynamic>.from(data['data'] as Map)
          : const <String, dynamic>{};
      final success = data['success'] == true;

      return DeliveryOtpSmsResult(
        success: success,
        duplicate: nested['duplicate'] == true,
        message: success
            ? (nested['message']?.toString() ??
                  'Codigo enviado por SMS com sucesso.')
            : (data['error']?.toString() ??
                  'Nao foi possivel enviar o SMS do codigo agora.'),
      );
    } catch (e) {
      debugPrint('Erro ao enviar OTP de entrega por SMS: $e');
      return const DeliveryOtpSmsResult(
        success: false,
        message: 'Nao foi possivel enviar o SMS do codigo agora.',
      );
    }
  }

  Future<DeliveryOtpVerificationResult> verifyDeliveryOtp({
    required String orderId,
    required String otpCode,
  }) async {
    try {
      Map<String, dynamic>? data;

      try {
        final response = await _supabase.functions
            .invoke(
              'verify-delivery-otp',
              headers: await _authHeaders(),
              body: {'order_id': orderId, 'otp_code': otpCode},
            )
            .timeout(const Duration(seconds: 12));

        final payload = response.data;
        if (payload is Map) {
          data = Map<String, dynamic>.from(payload);
        }
      } catch (sdkError) {
        debugPrint(
          'Erro ao chamar Edge Function verify-delivery-otp via SDK para $orderId: $sdkError',
        );
      }

      data ??= await _invokeFunctionDirect(
        'verify-delivery-otp',
        body: {'order_id': orderId, 'otp_code': otpCode},
      );
      if (data == null) {
        return const DeliveryOtpVerificationResult(
          success: false,
          message: 'Nao foi possivel validar o codigo agora.',
        );
      }

      final nested = data['data'] is Map
          ? Map<String, dynamic>.from(data['data'] as Map)
          : const <String, dynamic>{};
      final success = data['success'] == true;

      return DeliveryOtpVerificationResult(
        success: success,
        message: success
            ? (nested['message']?.toString() ??
                  'Codigo validado e entrega concluida.')
            : (data['error']?.toString() ??
                  'Nao foi possivel validar o codigo agora.'),
        status: nested['status']?.toString(),
      );
    } catch (e) {
      debugPrint('Erro ao validar OTP da entrega: $e');
      return const DeliveryOtpVerificationResult(
        success: false,
        message: 'Nao foi possivel validar o codigo agora.',
      );
    }
  }

  Future<bool> submitDeliveryProof({
    required String orderId,
    required String courierId,
    String? photoUrl,
    String? notes,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final response = await _supabase.rpc(
        'submit_delivery_proof',
        params: {
          'p_order_id': orderId,
          'p_courier_id': courierId,
          'p_photo_url': photoUrl,
          'p_notes': notes,
          'p_latitude': latitude,
          'p_longitude': longitude,
        },
      );

      if (response == null) return false;
      final data = Map<String, dynamic>.from(response as Map);
      return data['success'] == true;
    } catch (e) {
      debugPrint('Erro ao enviar prova de entrega: $e');
      return false;
    }
  }

  /// Buscar entrega atual do entregador
  Future<Order?> getCurrentDelivery(String courierId) async {
    try {
      final response = await _supabase
          .from('orders')
          .select(
            '*, restaurants(name,address,neighborhood,city,latitude,longitude,estimated_delivery_time)',
          )
          .eq('courier_id', courierId)
          .filter(
            'status',
            'in',
            '(accepted,preparing,courier_assigned,ready,in_transit,on_the_way,arrived,delivery_failed_otp)',
          )
          .limit(1)
          .single();

      return Order.fromMap(response);
    } catch (_) {}

    try {
      final delivery = await _supabase
          .from('deliveries')
          .select(
            'order_id, courier_id, status, delivery_latitude, delivery_longitude',
          )
          .eq('courier_id', courierId)
          .inFilter('status', [
            'accepted',
            'preparing',
            'courier_assigned',
            'ready',
            'in_transit',
            'on_the_way',
            'arrived',
            'delivery_failed_otp',
          ])
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final orderId = delivery?['order_id']?.toString().trim() ?? '';
      if (orderId.isEmpty) return null;

      final response = await _supabase
          .from('orders')
          .select(
            '*, restaurants(name,address,neighborhood,city,latitude,longitude,estimated_delivery_time)',
          )
          .eq('id', orderId)
          .inFilter('status', [
            'accepted',
            'preparing',
            'courier_assigned',
            'ready',
            'in_transit',
            'on_the_way',
            'arrived',
            'delivery_failed_otp',
          ])
          .maybeSingle();
      if (response == null) return null;

      final deliveryLatitude = (delivery!['delivery_latitude'] as num?)
          ?.toDouble();
      final deliveryLongitude = (delivery['delivery_longitude'] as num?)
          ?.toDouble();
      if ((response['delivery_latitude'] == null ||
              response['delivery_longitude'] == null) &&
          deliveryLatitude != null &&
          deliveryLongitude != null) {
        response['delivery_latitude'] = deliveryLatitude;
        response['delivery_longitude'] = deliveryLongitude;
      }

      await _syncOrderCourierAssignment(orderId: orderId, courierId: courierId);
      final repaired = Map<String, dynamic>.from(response);
      repaired['courier_id'] = courierId;
      return Order.fromMap(repaired);
    } catch (error) {
      debugPrint('Erro ao recuperar entrega ativa pelo tracking: $error');
      return null;
    }
  }

  Future<bool> declineDispatchOpportunity({
    required String orderId,
    String? dispatchGroupId,
  }) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return false;
    try {
      final response = await _invokeFunctionDirect(
        'courier-dispatch-control',
        body: {
          'action': 'decline',
          'order_id': normalizedOrderId,
          'dispatch_group_id': dispatchGroupId?.trim(),
          'reason': 'declined_by_courier',
        },
      );
      if (response == null) return false;
      return response['success'] == true;
    } catch (error) {
      debugPrint(
        'DeliveryService.declineDispatchOpportunity error for $normalizedOrderId: $error',
      );
      return false;
    }
  }

  /// Inscrever entregador em topic de notificações
  Future<void> subscribeToDeliveryNotifications(String courierId) async {
    // Esta função seria chamada pelo FCM service
    // Subscribe to 'deliveries' topic for all couriers
    // or 'courier_{id}' for specific courier
  }

  /// Notificar entregadores próximos (broadcast)
  Future<void> notifyNearbyCouriers(String orderId) async {
    try {
      final startResponse = await _supabase.rpc(
        'start_delivery_search',
        params: {'p_order_id': orderId},
      );
      final startData = startResponse is Map
          ? Map<String, dynamic>.from(startResponse)
          : const <String, dynamic>{};
      final attemptId =
          startData['dispatch_attempt_id']?.toString().trim() ?? '';
      if (startData['success'] != true || attemptId.isEmpty) {
        debugPrint(
          'Dispatch start denied for $orderId: ${startData['code'] ?? 'no_attempt'}',
        );
        return;
      }

      final order = await _supabase
          .from('orders')
          .select('restaurant_id, delivery_fee')
          .eq('id', orderId)
          .maybeSingle();
      if (order == null) return;

      final restaurant = await _supabase
          .from('restaurants')
          .select('latitude, longitude, name')
          .eq('id', order['restaurant_id'])
          .maybeSingle();
      if (restaurant == null) return;

      final restLat = (restaurant['latitude'] as num?)?.toDouble();
      final restLng = (restaurant['longitude'] as num?)?.toDouble();
      if (restLat == null || restLng == null) return;

      final freshnessCutoff = DateTime.now()
          .subtract(_courierLocationFreshness)
          .toIso8601String();
      final couriers = await _supabase
          .from('couriers')
          .select(
            'id, user_id, current_latitude, current_longitude, is_online, updated_at',
          )
          .eq('is_online', true)
          .gte('updated_at', freshnessCutoff)
          .order('updated_at', ascending: false)
          .limit(_maxCourierNotificationCandidates);

      final now = DateTime.now().toIso8601String();
      final nearbyCouriers = <Map<String, dynamic>>[];
      for (final c in (couriers as List).cast<Map<String, dynamic>>()) {
        final lat = (c['current_latitude'] as num?)?.toDouble();
        final lng = (c['current_longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        final dist = _distanceKm(restLat, restLng, lat, lng);
        if (dist <= _notifyRadiusKm) {
          nearbyCouriers.add({
            'id': (c['user_id'] ?? c['id'])?.toString() ?? '',
            'distance_km': dist,
          });
        }
      }

      nearbyCouriers.sort((a, b) {
        final distanceA =
            (a['distance_km'] as num?)?.toDouble() ?? double.infinity;
        final distanceB =
            (b['distance_km'] as num?)?.toDouble() ?? double.infinity;
        return distanceA.compareTo(distanceB);
      });

      final notificationTargets = nearbyCouriers
          .take(_maxNearbyCourierNotifications)
          .where((courier) => (courier['id'] as String).isNotEmpty)
          .toList();
      if (notificationTargets.isEmpty) return;

      final orderRef = _orderRef(orderId);
      final deliveryFee = (order['delivery_fee'] as num?)?.toDouble() ?? 0.0;
      final queued = await _enqueueCourierDispatchBroadcast(
        orderId: orderId,
        orderRef: orderRef,
        dispatchAttemptId: attemptId,
        targets: notificationTargets.asMap().entries.map((entry) {
          final courier = entry.value;
          final dist = (courier['distance_km'] as num?)?.toDouble() ?? 0.0;
          final etaMinutes = ((dist * 4).round() < 6) ? 6 : (dist * 4).round();
          return <String, dynamic>{
            'user_id': courier['id'],
            'distance_km': dist,
            'eta_minutes': etaMinutes,
            'delivery_fee': deliveryFee,
            'fallback_rank': entry.key + 1,
            'restaurant_name': restaurant['name'],
            'created_at': now,
          };
        }).toList(),
      );
      if (!queued) {
        debugPrint(
          'DeliveryService.notifyNearbyCouriers queue dispatch failed for $orderId; skipping direct fallback to preserve single source of truth.',
        );
      }
      return;

      /*
      await Future.wait(
        notificationTargets.map((courier) {
          final userId = courier['id'] as String;
          final dist = (courier['distance_km'] as num?)?.toDouble() ?? 0.0;
          final orderRef = _orderRef(orderId);
          final deliveryFee =
              (order['delivery_fee'] as num?)?.toDouble() ?? 0.0;
          final etaMinutes = ((dist * 4).round() < 6) ? 6 : (dist * 4).round();
          return _notificationDispatch.sendToUser(
            userId: userId,
            type: 'DELIVERY_OPPORTUNITY',
            title: 'Novo pedido perto de você $orderRef',
            body:
                'Valor ${deliveryFee.toStringAsFixed(0)} MZN • ${dist.toStringAsFixed(1)} km • ETA $etaMinutes min',
            action: 'OPEN_ORDER',
            entityId: orderId,
            priority: 'HIGH',
            channel: 'courier_dispatch',
            data: {
              'order_id': orderId,
              'order_ref': orderRef,
              'dispatch_style': 'ringing',
            },
            metadata: {
              'order_id': orderId,
              'order_ref': orderRef,
              'restaurant_name': restaurant['name'],
              'delivery_fee': deliveryFee,
              'distance_km': dist,
              'eta_minutes': etaMinutes,
              'created_at': now,
              'dispatch_style': 'ringing',
            },
          );
        }),
      );
      */
    } catch (error) {
      debugPrint('DeliveryService.notifyNearbyCouriers error: $error');
    }
  }

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degree) => degree * 3.141592653589793 / 180;
}
