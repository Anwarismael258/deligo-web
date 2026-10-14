import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servico de pagamento que usa Edge Functions do Supabase.
///
/// Todas as chamadas ao provedor de pagamentos passam pelo backend para manter
/// os segredos e os calculos financeiros fora do frontend.
class PaymentService {
  final SupabaseClient _supabase = Supabase.instance.client;
  String? _lastErrorMessage;

  String? get lastErrorMessage => _lastErrorMessage;

  Future<Map<String, String>?> _authHeaders() async {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  bool _shouldRetryCreatePayment(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('unauthorized') ||
        normalized.contains('invalid token') ||
        normalized.contains('jwt') ||
        normalized.contains('session') ||
        normalized.contains('network') ||
        normalized.contains('socket') ||
        normalized.contains('timeout') ||
        normalized.contains('connection') ||
        normalized.contains('response null') ||
        normalized.contains('resposta nula');
  }

  Future<FunctionResponse> _invokeCreatePayment(
    double amount,
    String orderId,
  ) async {
    return _supabase.functions.invoke(
      'create-payment',
      headers: await _authHeaders(),
      body: {'amount': amount, 'payment_method': 'wallet', 'order_id': orderId},
    );
  }

  Future<void> _refreshAuthSessionIfNeeded() async {
    try {
      await _supabase.auth.refreshSession();
    } catch (error) {
      debugPrint(
        'Erro ao atualizar sessao antes do retry de pagamento: $error',
      );
    }
  }

  Future<ProviderPayment?> createPayment({
    required double amount,
    required String walletType,
    required String orderId,
  }) async {
    try {
      _lastErrorMessage = null;
      Future<ProviderPayment> parseResponse(FunctionResponse response) async {
        if (response.data == null) {
          throw Exception('Resposta nula da Edge Function');
        }

        if (response.data['success'] == true) {
          final data = response.data['data'];
          return ProviderPayment(
            id: data['payment_ref'] ?? '',
            referenceText: 'DELIGO_$orderId',
            amount: amount,
            status: data['status'] ?? 'pending',
            providerReference: data['provider_reference'],
            qrCode: data['qr_code'],
            paymentInstructions: data['payment_instructions'],
            createdAt: DateTime.now(),
          );
        }

        throw Exception(response.data['error'] ?? 'Erro desconhecido');
      }

      try {
        final response = await _invokeCreatePayment(amount, orderId);
        return await parseResponse(response);
      } catch (error) {
        final rawMessage = error
            .toString()
            .replaceFirst('Exception: ', '')
            .trim();
        if (!_shouldRetryCreatePayment(rawMessage)) {
          rethrow;
        }

        await _refreshAuthSessionIfNeeded();
        await Future<void>.delayed(const Duration(milliseconds: 650));
        final retryResponse = await _invokeCreatePayment(amount, orderId);
        return await parseResponse(retryResponse);
      }
    } catch (e) {
      debugPrint('Erro ao criar pagamento: $e');
      _lastErrorMessage = e.toString().replaceFirst('Exception: ', '').trim();
      final recovered = await _recoverConfirmedPayment(orderId, amount);
      if (recovered != null) {
        _lastErrorMessage = null;
        return recovered;
      }
      return null;
    }
  }

  Future<ProviderPayment?> _recoverConfirmedPayment(
    String orderId,
    double amount,
  ) async {
    try {
      final paymentRow = await _supabase
          .from('payments')
          .select(
            'payment_ref, transaction_id, status, provider_reference, qr_code',
          )
          .eq('order_id', orderId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final status = paymentRow?['status']?.toString().trim().toLowerCase();
      if (status == null ||
          (status != 'authorized' &&
              status != 'paid' &&
              status != 'completed' &&
              status != 'settled')) {
        return null;
      }

      return ProviderPayment(
        id:
            paymentRow?['payment_ref']?.toString() ??
            paymentRow?['transaction_id']?.toString() ??
            '',
        referenceText: 'DELIGO_$orderId',
        amount: amount,
        status: status,
        providerReference: paymentRow?['provider_reference']?.toString(),
        qrCode: paymentRow?['qr_code']?.toString(),
        paymentInstructions:
            'Pagamento confirmado no backend. A app recuperou o estado apos uma falha de rede.',
        createdAt: DateTime.now(),
      );
    } catch (recoveryError) {
      debugPrint('Erro ao recuperar pagamento confirmado: $recoveryError');
      return null;
    }
  }

  Future<String?> getPaymentStatus(String orderId) async {
    try {
      final response = await _supabase
          .from('payments')
          .select('status')
          .eq('order_id', orderId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return response['status'] as String?;
    } catch (e) {
      debugPrint('Erro ao buscar status: $e');
      return null;
    }
  }

  Future<bool> confirmDelivery(String orderId) async {
    try {
      final response = await _supabase.functions.invoke(
        'confirm-delivery',
        headers: await _authHeaders(),
        body: {'order_id': orderId},
      );

      if (response.data == null) {
        return false;
      }

      return response.data['success'] == true;
    } catch (e) {
      debugPrint('Erro ao confirmar entrega: $e');
      return false;
    }
  }
}

class ProviderPayment {
  final String id;
  final String referenceText;
  final double amount;
  final String status;
  final String? providerReference;
  final String? qrCode;
  final dynamic paymentInstructions;
  final DateTime createdAt;

  ProviderPayment({
    required this.id,
    required this.referenceText,
    required this.amount,
    required this.status,
    this.providerReference,
    this.qrCode,
    this.paymentInstructions,
    required this.createdAt,
  });

  bool get isCompleted => status == 'completed' || status == 'authorized';
  bool get isPending => status == 'pending';
  bool get isFailed => status == 'failed';
  bool get hasQrCode => qrCode != null && qrCode!.isNotEmpty;
  bool get hasInstructions => paymentInstructions != null;
}
