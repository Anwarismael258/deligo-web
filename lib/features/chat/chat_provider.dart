import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_dispatch_service.dart';
import '../../services/sound_controller.dart';
import '../../shared/models/message.dart';
import '../../shared/utils/chat_notification_utils.dart';

class ChatProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? _currentOrderId;
  List<Message> _messages = [];
  bool _isLoading = false;
  RealtimeChannel? _messagesChannel;

  String? get currentOrderId => _currentOrderId;
  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;

  Future<void> loadMessages(String orderId) async {
    if (_currentOrderId != orderId) {
      await _messagesChannel?.unsubscribe();
      _messagesChannel = null;
    }
    _currentOrderId = orderId;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _supabase
          .from('messages')
          .select()
          .eq('order_id', orderId)
          .order('created_at', ascending: true);

      _messages = (response as List)
          .map((data) => Message.fromMap(data))
          .toList();
      await _markMessagesRead(orderId);
      await _markChatNotificationsRead(orderId);
      await _subscribeToMessages(orderId);
    } catch (e) {
      debugPrint('Erro ao carregar mensagens: $e');
      _messages = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> sendMessage(
    String text,
    String senderName,
    String senderRole,
    String? attachmentUrl,
    String? attachmentType,
  ) async {
    if (_currentOrderId == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty && (attachmentUrl == null || attachmentUrl.isEmpty)) {
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final messageData = {
        'order_id': _currentOrderId,
        'sender_id': user.id,
        'sender_name': senderName,
        'sender_role': senderRole,
        'text': trimmed,
        'attachment_url': attachmentUrl,
        'attachment_type': attachmentType,
      };

      final response = await _supabase
          .from('messages')
          .insert(messageData)
          .select()
          .single();

      _upsertMessage(Message.fromMap(response));
      await SoundController.instance.messageSent();
      await _notifyChatParticipants(
        orderId: _currentOrderId!,
        senderId: user.id,
        senderName: senderName,
        text: trimmed.isNotEmpty
            ? trimmed
            : (attachmentType == 'image' ? 'Foto enviada' : 'Anexo enviado'),
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao enviar mensagem: $e');
    }
  }

  Future<void> _notifyChatParticipants({
    required String orderId,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    try {
      final order = await _supabase
          .from('orders')
          .select('client_id, customer_id, courier_id, restaurant_id')
          .eq('id', orderId)
          .maybeSingle();
      if (order == null) return;

      final recipients = <String>{
        order['client_id']?.toString() ?? '',
        order['customer_id']?.toString() ?? '',
        order['courier_id']?.toString() ?? '',
      }..removeWhere((id) => id.isEmpty || id == senderId);

      final restaurantId = order['restaurant_id']?.toString();
      if (restaurantId != null && restaurantId.isNotEmpty) {
        try {
          final restaurant = await _supabase
              .from('restaurants')
              .select('owner_id')
              .eq('id', restaurantId)
              .maybeSingle();
          final ownerId = restaurant?['owner_id']?.toString() ?? '';
          if (ownerId.isNotEmpty && ownerId != senderId) {
            recipients.add(ownerId);
          }
        } catch (_) {}
      }

      if (recipients.isEmpty) return;

      final now = DateTime.now().toIso8601String();
      for (final userId in recipients) {
        await NotificationDispatchService.instance.sendToUser(
          userId: userId,
          type: 'MESSAGE_RECEIVED',
          title: 'Nova mensagem',
          body: '$senderName: $text',
          action: 'OPEN_CHAT',
          entityId: orderId,
          priority: 'HIGH',
          channel: 'chat',
          data: {
            'order_id': orderId,
          },
          metadata: {
            'order_id': orderId,
            'sender_id': senderId,
            'sender_name': senderName,
            'created_at': now,
          },
        );
      }
    } catch (e) {
      debugPrint('Erro ao notificar participantes do chat: $e');
    }
  }

  Future<void> _subscribeToMessages(String orderId) async {
    if (_messagesChannel != null) return;
    _messagesChannel = _supabase.channel('chat-messages-$orderId');
    _messagesChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: orderId,
          ),
          callback: (payload) {
            switch (payload.eventType) {
              case PostgresChangeEvent.insert:
              case PostgresChangeEvent.update:
                if (payload.newRecord.isEmpty) return;
                final incoming = Message.fromMap(
                  Map<String, dynamic>.from(payload.newRecord),
                );
                Message? previous;
                for (final message in _messages) {
                  if (message.id == incoming.id) {
                    previous = message;
                    break;
                  }
                }
                _upsertMessage(incoming);
                if (payload.eventType == PostgresChangeEvent.insert &&
                    incoming.senderId != _supabase.auth.currentUser?.id) {
                  unawaited(_markMessagesRead(orderId));
                  unawaited(_markChatNotificationsRead(orderId));
                }
                if (previous == null ||
                    previous.readAt != incoming.readAt ||
                    previous.deliveredAt != incoming.deliveredAt ||
                    previous.text != incoming.text ||
                    previous.attachmentUrl != incoming.attachmentUrl) {
                  notifyListeners();
                }
                return;
              case PostgresChangeEvent.delete:
                final deletedId = payload.oldRecord['id']?.toString() ?? '';
                if (deletedId.isEmpty) return;
                final updated = _messages
                    .where((message) => message.id != deletedId)
                    .toList();
                if (updated.length == _messages.length) return;
                _messages = updated;
                notifyListeners();
                return;
              default:
                return;
            }
          },
        )
        .subscribe();
  }

  Future<void> _markMessagesRead(String orderId) async {
    try {
      await _supabase.rpc(
        'mark_messages_read',
        params: {'p_order_id': orderId},
      );
    } catch (e) {
      debugPrint('Erro ao marcar mensagens como lidas: $e');
    }
  }

  Future<void> _markChatNotificationsRead(String orderId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final unreadNotifications = await _supabase
          .from('push_notifications')
          .select('id, entity_id, metadata, data, type, read_at')
          .eq('user_id', user.id)
          .eq('type', 'MESSAGE_RECEIVED')
          .isFilter('read_at', null);
      final notificationIds = (unreadNotifications as List)
          .cast<Map<String, dynamic>>()
          .where((notification) => notification['id'] != null)
          .where((notification) => ChatNotificationUtils.matchesOrder(
                notification,
                orderId,
              ))
          .map((notification) => notification['id'].toString())
          .where((id) => id.isNotEmpty)
          .toList();
      if (notificationIds.isEmpty) return;
      await _supabase
          .from('push_notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .inFilter('id', notificationIds);
    } catch (e) {
      debugPrint('Erro ao marcar notificacoes do chat como lidas: $e');
    }
  }

  void _upsertMessage(Message next) {
    final updated = [..._messages];
    final index = updated.indexWhere((message) => message.id == next.id);
    if (index >= 0) {
      updated[index] = next;
    } else {
      updated.add(next);
    }
    updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _messages = updated;
  }

  void clearChat() {
    _currentOrderId = null;
    _messages = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _messagesChannel?.unsubscribe();
    super.dispose();
  }
}
