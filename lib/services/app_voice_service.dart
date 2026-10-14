import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../shared/utils/notification_type_utils.dart';
import 'elevenlabs_audio_service.dart';

class AppVoiceService {
  AppVoiceService._();

  static final AppVoiceService instance = AppVoiceService._();
  static const String _cooldownPrefix = 'app_voice_cooldown_v1_';

  final AudioPlayer _player = AudioPlayer();
  final Set<String> _inFlightKeys = <String>{};
  bool _isPlaying = false;

  Future<void> speakNotification({
    required String type,
    required String title,
    required String body,
    String? notificationId,
    String? channel,
    String? priority,
  }) async {
    type = NotificationTypeUtils.canonicalize(type);
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    final profile = await client
        .from('profiles')
        .select('settings')
        .eq('id', user.id)
        .maybeSingle();
    final settings =
        (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final voiceMode = (settings['voice_mode'] as String? ?? 'important_only')
        .trim()
        .toLowerCase();
    if (voiceMode == 'off') return;

    final notifications =
        (settings['notifications'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    if (!_isAllowedByPreferences(type: type, notifications: notifications)) {
      return;
    }
    if (voiceMode == 'important_only' && !_isImportantType(type)) return;

    final dedupeKey = notificationId?.trim().isNotEmpty == true
        ? notificationId!.trim()
        : '${type}_${channel ?? 'system'}';
    if (await _isCoolingDown(dedupeKey, type)) return;

    final message = _buildMessage(
      type: type,
      title: title,
      body: body,
      channel: channel,
      priority: priority,
    );
    if (message.isEmpty) return;

    final languageCode = settings['language']?.toString() ?? 'pt';
    if (_isPlaying || _inFlightKeys.contains(dedupeKey)) return;

    _inFlightKeys.add(dedupeKey);
    try {
      final audioBytes = await ElevenLabsAudioService.instance.synthesize(
        text: message,
        languageCode: languageCode,
      );
      if (audioBytes == null || audioBytes.isEmpty) return;

      _isPlaying = true;
      await _player.stop();
      await _player.play(BytesSource(audioBytes));
      await _storeCooldown(dedupeKey, type);
    } catch (e) {
      debugPrint('AppVoiceService.speakNotification error: $e');
    } finally {
      _isPlaying = false;
      _inFlightKeys.remove(dedupeKey);
    }
  }

  bool _isAllowedByPreferences({
    required String type,
    required Map<String, dynamic> notifications,
  }) {
    if (_isPromotionType(type)) {
      return notifications['promotions'] != false;
    }
    if (_isOrderType(type)) {
      return notifications['order_status'] != false;
    }
    return true;
  }

  bool _isImportantType(String type) {
    switch (type) {
      case 'NEW_ORDER':
      case 'NEW_PAID_ORDER':
      case 'PAYMENT_CONFIRMED':
      case 'ORDER_ACCEPTED':
      case 'ORDER_PREPARING':
      case 'ORDER_READY':
      case 'ORDER_PICKED_UP':
      case 'ORDER_READY_FOR_PICKUP':
      case 'NEW_DRIVER_ORDER':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_ARRIVED':
      case 'ORDER_DELIVERED':
      case 'ORDER_COMPLETED':
      case 'ORDER_AUTO_COMPLETED':
      case 'DELIVERY_EXTENSION_REQUESTED':
      case 'ORDER_CANCELLED':
      case 'ORDER_EXPIRED':
      case 'ORDER_DISPUTED':
      case 'PAYMENT_RELEASED':
      case 'DELIVERY_OTP_ISSUED':
      case 'DELIVERY_OTP_REGENERATED':
      case 'DELIVERY_SLA_EXCEEDED':
      case 'REFUND_STARTED':
      case 'REFUND_COMPLETED':
      case 'SUPPORT_UPDATED':
      case 'ORDER_REJECTED':
      case 'PAYMENT_FAILED':
      case 'COURIER_OPERATIONAL_STATE':
        return true;
      default:
        return false;
    }
  }

  bool _isPromotionType(String type) {
    switch (type) {
      case 'PROMO_OFFER':
      case 'FREE_DELIVERY_PROMO':
      case 'RETENTION_REMINDER':
        return true;
      default:
        return false;
    }
  }

  bool _isOrderType(String type) {
    switch (type) {
      case 'NEW_ORDER':
      case 'NEW_PAID_ORDER':
      case 'PAYMENT_CONFIRMED':
      case 'ORDER_ACCEPTED':
      case 'ORDER_PREPARING':
      case 'ORDER_READY':
      case 'ORDER_PICKED_UP':
      case 'ORDER_READY_FOR_PICKUP':
      case 'NEW_DRIVER_ORDER':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_ARRIVED':
      case 'ORDER_DELIVERED':
      case 'ORDER_COMPLETED':
      case 'ORDER_AUTO_COMPLETED':
      case 'DELIVERY_EXTENSION_REQUESTED':
      case 'ORDER_CANCELLED':
      case 'ORDER_EXPIRED':
      case 'ORDER_DISPUTED':
      case 'PAYMENT_RELEASED':
      case 'DELIVERY_OTP_ISSUED':
      case 'DELIVERY_OTP_REGENERATED':
      case 'DELIVERY_SLA_EXCEEDED':
      case 'REFUND_STARTED':
      case 'REFUND_COMPLETED':
      case 'ORDER_REJECTED':
      case 'PAYMENT_FAILED':
      case 'COURIER_OPERATIONAL_STATE':
        return true;
      default:
        return false;
    }
  }

  String _buildMessage({
    required String type,
    required String title,
    required String body,
    String? channel,
    String? priority,
  }) {
    switch (type) {
      case 'NEW_ORDER':
      case 'NEW_PAID_ORDER':
        return 'Novo pedido recebido.';
      case 'PAYMENT_CONFIRMED':
        return 'Pagamento confirmado.';
      case 'ORDER_ACCEPTED':
        return 'Pedido confirmado.';
      case 'ORDER_PREPARING':
        return 'O restaurante ja esta a preparar o pedido.';
      case 'ORDER_READY':
        return 'Pedido pronto para recolha.';
      case 'ORDER_PICKED_UP':
        return 'O pedido foi levantado e ja esta a caminho.';
      case 'ORDER_READY_FOR_PICKUP':
      case 'NEW_DRIVER_ORDER':
        return 'Existe um pedido pronto para recolha.';
      case 'DRIVER_ASSIGNED':
        return 'Estafeta atribuido. A entrega ja esta em andamento.';
      case 'DRIVER_ARRIVED':
        return 'O estafeta esta a chegar.';
      case 'ORDER_DELIVERED':
        return _buildDeliveredMessage(
          title: title,
          body: body,
          channel: channel,
        );
      case 'ORDER_COMPLETED':
        return 'O pedido foi concluido com sucesso.';
      case 'ORDER_AUTO_COMPLETED':
        return 'O pedido foi concluido automaticamente.';
      case 'ORDER_CANCELLED':
        return 'O pedido foi cancelado.';
      case 'ORDER_EXPIRED':
        return 'O pedido expirou por falta de confirmacao.';
      case 'ORDER_DISPUTED':
        return 'O pedido entrou em disputa para revisao.';
      case 'DELIVERY_EXTENSION_REQUESTED':
        return 'Foi pedido mais tempo antes do fecho automatico desta entrega.';
      case 'DELIVERY_OTP_ISSUED':
        return 'O codigo OTP da entrega ja esta disponivel.';
      case 'DELIVERY_OTP_REGENERATED':
        return 'O codigo OTP da entrega foi atualizado.';
      case 'PAYMENT_RELEASED':
        return 'O pagamento foi libertado com sucesso.';
      case 'DELIVERY_SLA_EXCEEDED':
        return 'A entrega ultrapassou o tempo previsto e exige atencao.';
      case 'REFUND_STARTED':
        return 'O seu reembolso foi iniciado.';
      case 'REFUND_COMPLETED':
        return 'O valor do reembolso ja entrou na sua carteira.';
      case 'SUPPORT_UPDATED':
        return priority?.toUpperCase() == 'HIGH'
            ? 'Nova disputa aberta.'
            : 'Existe uma nova atualizacao no suporte.';
      case 'PROMO_OFFER':
      case 'FREE_DELIVERY_PROMO':
      case 'RETENTION_REMINDER':
        return priority?.toUpperCase() == 'HIGH'
            ? 'Nova promocao relevante disponivel para si no DeliGo.'
            : '';
      default:
        return title.trim().isNotEmpty ? '$title. $body' : body;
    }
  }

  String _buildDeliveredMessage({
    required String title,
    required String body,
    String? channel,
  }) {
    final normalizedTitle = title.trim().toLowerCase();
    final normalizedBody = body.trim().toLowerCase();
    final normalizedChannel = channel?.trim().toLowerCase() ?? '';

    final needsCustomerConfirmation =
        normalizedBody.contains('confirma no app') ||
        normalizedBody.contains('confirma no app quando receberes tudo') ||
        normalizedBody.contains('confirmacao final');
    if (needsCustomerConfirmation) {
      return 'A entrega foi validada. Falta a tua confirmacao final no app.';
    }

    final waitingForCustomer =
        normalizedBody.contains('cliente ainda pode confirmar') ||
        normalizedBody.contains('reportar um problema no app');
    if (waitingForCustomer) {
      return 'A entrega foi validada. O cliente ainda pode confirmar ou reportar um problema.';
    }

    final deliveryCompleted =
        normalizedBody.contains('confirmou o recebimento') ||
        normalizedTitle.contains('concluido') ||
        normalizedTitle.contains('concluida');
    if (deliveryCompleted) {
      if (normalizedChannel == 'restaurant') {
        return 'O cliente confirmou o recebimento. Pedido concluido com sucesso.';
      }
      if (normalizedChannel == 'delivery') {
        return 'O cliente confirmou o recebimento. Entrega concluida com sucesso.';
      }
      return 'O cliente confirmou o recebimento. Pedido concluido com sucesso.';
    }

    return title.trim().isNotEmpty ? '$title. $body' : body;
  }

  Future<bool> _isCoolingDown(String key, String type) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cooldownPrefix$key');
    if (raw == null) return false;
    final lastAt = DateTime.tryParse(raw);
    if (lastAt == null) return false;
    final cooldown = _cooldownForType(type);
    return DateTime.now().difference(lastAt) < cooldown;
  }

  Future<void> _storeCooldown(String key, String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_cooldownPrefix$key',
      DateTime.now().toIso8601String(),
    );
  }

  Duration _cooldownForType(String type) {
    if (_isPromotionType(type)) {
      return const Duration(minutes: 20);
    }
    return const Duration(seconds: 45);
  }
}

