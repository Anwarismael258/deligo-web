import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servico para gerenciar timeout de pagamentos
/// Cancela automaticamente pedidos nao pagos apos tempo limite
class PaymentTimeoutService {
  static final PaymentTimeoutService _instance =
      PaymentTimeoutService._internal();
  factory PaymentTimeoutService() => _instance;
  PaymentTimeoutService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  // Timer para verificar pagamentos pendentes
  Timer? _checkTimer;

  // Tempo limite padrao: 15 minutos (em segundos)
  static const int defaultTimeoutSeconds = 900; // 15 minutos

  // Intervalo de verificacao: 30 segundos
  static const int checkIntervalSeconds = 30;

  /// Iniciar o servico de verificacao de timeout
  void start() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(
      const Duration(seconds: checkIntervalSeconds),
      (_) => _checkPendingPayments(),
    );
    debugPrint('PaymentTimeoutService started');
  }

  /// Parar o servico
  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
    debugPrint('PaymentTimeoutService stopped');
  }

  /// Verificar pagamentos pendentes e cancelar os expirados
  Future<void> _checkPendingPayments() async {
    try {
      final now = DateTime.now();

      // Buscar pedidos pendentes com mais de 15 minutos
      final timeoutThreshold = now.subtract(
        const Duration(seconds: defaultTimeoutSeconds),
      );

      final response = await _supabase
          .from('orders')
          .select('id, created_at, status')
          .eq('status', 'pending')
          .lt('created_at', timeoutThreshold.toIso8601String());

      if (response.isNotEmpty) {
        debugPrint('Encontrados ${response.length} pedidos pendentes para cancelar');

        for (final order in response) {
          await _cancelOrder(order['id']);
        }
      }
    } catch (e) {
      debugPrint('Erro ao verificar pagamentos pendentes: $e');
    }
  }

  /// Cancelar pedido por timeout
  Future<void> _cancelOrder(String orderId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) return;

      // State, payment and refund mutations must go through the guarded RPC.
      await _supabase.rpc(
        'process_order_cancellation',
        params: {
          'p_order_id': orderId,
          'p_user_id': userId,
          'p_reason': 'system_timeout',
        },
      );

      debugPrint('Pedido $orderId cancelado por timeout');
    } catch (e) {
      debugPrint('Erro ao cancelar pedido $orderId: $e');
    }
  }

  /// Criar timer especifico para um pedido
  /// Retorna um Timer que pode ser cancelado
  Timer? startOrderTimeout(String orderId, {int? customTimeoutSeconds}) {
    final timeout = customTimeoutSeconds ?? defaultTimeoutSeconds;

    return Timer(Duration(seconds: timeout), () async {
      // Verificar se ainda esta pendente
      try {
        final order = await _supabase
            .from('orders')
            .select('status')
            .eq('id', orderId)
            .maybeSingle();

        if (order != null && order['status'] == 'pending') {
          await _cancelOrder(orderId);
        }
      } catch (e) {
        debugPrint('Erro ao verificar status do pedido: $e');
      }
    });
  }

  /// Cancelar timeout de um pedido especifico
  void cancelOrderTimeout(String orderId) {
    // Esta funcao pode ser usada se o pagamento for confirmado
    // antes do timeout, para limpar o timer
    debugPrint('Timeout cancelado para pedido $orderId');
  }

  /// Dispose
  void dispose() {
    stop();
  }
}







