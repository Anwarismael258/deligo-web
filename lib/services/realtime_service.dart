import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servico de Realtime baseado em canais do Supabase.
class RealtimeService {
  static final RealtimeService _instance = RealtimeService._internal();
  factory RealtimeService() => _instance;
  RealtimeService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  RealtimeChannel? _deliveryChannel;
  RealtimeChannel? _orderChannel;
  RealtimeChannel? _chatChannel;

  Function(double lat, double lng)? onCourierLocationUpdate;
  Function(String status)? onOrderStatusUpdate;
  Function(Map<String, dynamic> message)? onNewMessage;

  double? _lastLat;
  double? _lastLng;
  String? _lastStatus;
  String? _lastMessageId;

  void initialize() {
    debugPrint('RealtimeService initialized - Supabase channels');
  }

  Future<void> startDeliveryTracking(String orderId) async {
    stopDeliveryTracking();

    _deliveryChannel = _supabase
        .channel('delivery_tracking_$orderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'deliveries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: orderId,
          ),
          callback: (payload) {
            final data = payload.newRecord;
            final lat = (data['current_latitude'] as num?)?.toDouble();
            final lng = (data['current_longitude'] as num?)?.toDouble();

            if (lat != null && lng != null && (lat != _lastLat || lng != _lastLng)) {
              _lastLat = lat;
              _lastLng = lng;
              onCourierLocationUpdate?.call(lat, lng);
            }
          },
        )
        .subscribe();

    debugPrint('Realtime delivery tracking started: $orderId');
  }

  Future<void> startOrderTracking(String orderId) async {
    stopOrderTracking();

    _orderChannel = _supabase
        .channel('order_tracking_$orderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: orderId,
          ),
          callback: (payload) {
            final status = payload.newRecord['status'] as String?;
            if (status != null && status != _lastStatus) {
              _lastStatus = status;
              onOrderStatusUpdate?.call(status);
            }
          },
        )
        .subscribe();

    debugPrint('Realtime order tracking started: $orderId');
  }

  Future<void> startChatListening(String orderId) async {
    stopChatListening();

    _chatChannel = _supabase
        .channel('chat_messages_$orderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: orderId,
          ),
          callback: (payload) {
            final data = Map<String, dynamic>.from(payload.newRecord);
            final messageId = data['id']?.toString();
            if (messageId != null && messageId != _lastMessageId) {
              _lastMessageId = messageId;
              onNewMessage?.call(data);
            }
          },
        )
        .subscribe();

    debugPrint('Realtime chat listening started: $orderId');
  }

  Future<void> updateDeliveryLocation(String orderId, double lat, double lng) async {
    try {
      await _supabase
          .from('deliveries')
          .update({
            'current_latitude': lat,
            'current_longitude': lng,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('order_id', orderId);
    } catch (e) {
      debugPrint('Erro ao atualizar localizacao: $e');
    }
  }

  void stopDeliveryTracking() {
    if (_deliveryChannel != null) {
      _supabase.removeChannel(_deliveryChannel!);
      _deliveryChannel = null;
    }
    _lastLat = null;
    _lastLng = null;
    debugPrint('Realtime delivery tracking stopped');
  }

  void stopOrderTracking() {
    if (_orderChannel != null) {
      _supabase.removeChannel(_orderChannel!);
      _orderChannel = null;
    }
    _lastStatus = null;
    debugPrint('Realtime order tracking stopped');
  }

  void stopChatListening() {
    if (_chatChannel != null) {
      _supabase.removeChannel(_chatChannel!);
      _chatChannel = null;
    }
    _lastMessageId = null;
    debugPrint('Realtime chat listening stopped');
  }

  void stopAll() {
    stopDeliveryTracking();
    stopOrderTracking();
    stopChatListening();
  }

  void dispose() {
    stopAll();
  }
}





