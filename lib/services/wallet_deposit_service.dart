import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:convert';

import '../shared/utils/mozambique_wallet_validation.dart';

/// Servico para gerenciar depositos e levantamentos da wallet.
class WalletDepositService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const int depositTimeoutSeconds = 300;

  Future<Map<String, String>> _authHeaders() async {
    var session = _supabase.auth.currentSession;
    if (session == null || session.isExpired) {
      session = (await _supabase.auth.refreshSession()).session;
    }
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      return const {};
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<WalletDepositResult> createDeposit({
    required String walletId,
    required double amount,
    required String paymentMethod,
    required String phone,
  }) async {
    try {
      final normalizedPhone = MozambiqueWalletValidation.normalizeMsisdn(phone);
      if (!MozambiqueWalletValidation.isValidMsisdn(normalizedPhone)) {
        return WalletDepositResult(
          success: false,
          error: 'Número mKesh, M-Pesa ou e-Mola inválido.',
        );
      }
      if (!MozambiqueWalletValidation.methodMatches(
        normalizedPhone,
        paymentMethod,
      )) {
        return WalletDepositResult(
          success: false,
          error: 'A operadora escolhida nao corresponde ao numero informado.',
        );
      }
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return WalletDepositResult(
          success: false,
          error: 'Usuario nao autenticado',
        );
      }

      final normalizedMethod = paymentMethod == 'm-pesa'
          ? 'mpesa'
          : paymentMethod;

      final headers = await _authHeaders();
      final response = await _supabase.functions.invoke(
        'wallet-deposit-v2',
        headers: headers,
        body: {
          'wallet_id': walletId,
          'amount': amount,
          'payment_method': normalizedMethod,
          'phone_number': '+258$normalizedPhone',
        },
      );

      if (response.data == null) {
        return WalletDepositResult(
          success: false,
          error: 'Falha ao iniciar deposito',
        );
      }

      if (response.data['success'] == true) {
        return WalletDepositResult(
          success: true,
          depositId: response.data['deposit_id']?.toString(),
          reference: response.data['reference']?.toString(),
          transactionId: response.data['debito_reference']?.toString(),
          checkoutUrl:
              response.data['checkout_url']?.toString() ??
              response.data['payment_url']?.toString() ??
              response.data['payment_link']?.toString() ??
              response.data['url']?.toString(),
          message: response.data['message']?.toString(),
          requiresManualPayment: false,
          instructions: response.data['instructions']?.toString(),
        );
      }

      return WalletDepositResult(
        success: false,
        depositId: response.data['deposit_id']?.toString(),
        reference: response.data['reference']?.toString(),
        error:
            response.data['error']?.toString() ?? 'Falha ao iniciar deposito',
        providerStatus: response.data['provider_status']?.toString(),
        providerError: response.data['provider_error']?.toString(),
        providerHttpStatus: response.data['provider_http_status'] as int?,
      );
    } catch (e) {
      return WalletDepositResult(
        success: false,
        error: _friendlyFunctionError(e),
      );
    }
  }

  String _friendlyFunctionError(Object error) {
    final raw = error.toString();
    final extracted = RegExp(r'\{.*\}', dotAll: true).firstMatch(raw)?.group(0);

    if (extracted != null) {
      try {
        final decoded = _asMap(extracted);
        final message =
            decoded['error']?.toString() ??
            decoded['message']?.toString() ??
            decoded['detail']?.toString();
        if (message != null && message.trim().isNotEmpty) {
          return message.trim();
        }
      } catch (_) {
        // Ignore parse failures and fall back to the raw exception string.
      }
    }

    final normalized = raw.toLowerCase();
    if (normalized.contains('unauthorized') || normalized.contains('401')) {
      return 'A sua sessao terminou. Entre novamente e tente o deposito.';
    }
    if (normalized.contains('timeout') || normalized.contains('504')) {
      return 'O parceiro demorou a responder. Tente novamente em instantes.';
    }
    if (normalized.contains('socket') || normalized.contains('network')) {
      return 'Sem ligacao ao servidor. Verifique a internet e tente novamente.';
    }
    // Preserve the provider/function status during staging so the user and
    // support can distinguish auth, validation, and gateway failures.
    final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length > 220 ? compact.substring(0, 220) : compact;
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return <String, dynamic>{};
  }

  Future<WalletWithdrawResult> createWithdrawal({
    required double amount,
    required String method,
    required String phone,
    String? walletId,
  }) async {
    try {
      if (!MozambiqueWalletValidation.isValidMsisdn(phone)) {
        return WalletWithdrawResult(
          success: false,
          error: 'Numero M-Pesa ou e-Mola invalido.',
          normalizedError: 'Numero M-Pesa ou e-Mola invalido.',
        );
      }
      if (!MozambiqueWalletValidation.methodMatches(phone, method)) {
        return WalletWithdrawResult(
          success: false,
          error: 'A operadora escolhida nao corresponde ao numero informado.',
          normalizedError:
              'A operadora escolhida nao corresponde ao numero informado.',
        );
      }
      final headers = await _authHeaders();
      final response = await _supabase.functions.invoke(
        'wallet-withdraw-v2',
        headers: headers,
        body: {
          'amount': amount,
          'method': method == 'm-pesa' ? 'mpesa' : method,
          'phone_number': phone,
          if (walletId != null && walletId.trim().isNotEmpty)
            'wallet_id': walletId.trim(),
        },
      );

      final data = response.data;
      debugPrint('WalletWithdraw: status=${response.status} data=$data');
      if (data == null) {
        final fallback = response.status >= 500
            ? 'Gateway de levantamento indisponivel no backend.'
            : 'Falha ao solicitar levantamento';
        final normalized = _normalizeWithdrawError(fallback);
        return WalletWithdrawResult(
          success: false,
          error: fallback,
          normalizedError: normalized ?? fallback,
        );
      }
      if (response.status >= 200 &&
          response.status < 300 &&
          data is Map<String, dynamic> &&
          data['success'] == true) {
        return WalletWithdrawResult(
          success: true,
          requestId: data['request_id']?.toString(),
          status: data['status']?.toString().trim().toLowerCase(),
          message: data['message']?.toString(),
        );
      }

      return WalletWithdrawResult(
        success: false,
        status: data is Map<String, dynamic>
            ? data['status']?.toString().trim().toLowerCase()
            : null,
        error: data is Map<String, dynamic>
            ? (data['error']?.toString() ??
                  data['message']?.toString() ??
                  data['detail']?.toString() ??
                  'Falha ao solicitar levantamento')
            : 'Falha ao solicitar levantamento',
        normalizedError: _normalizeWithdrawError(
          data is Map<String, dynamic> ? data['error']?.toString() : null,
        ),
      );
    } catch (e) {
      final message = e.toString();
      debugPrint('WalletWithdraw: exception=$message');
      final normalized =
          _normalizeWithdrawError(message) ??
          'Nao foi possivel comunicar com o gateway de levantamento agora.';
      return WalletWithdrawResult(
        success: false,
        error: normalized,
        normalizedError: normalized,
      );
    }
  }

  Future<DepositStatus> checkDepositStatus(String depositId) async {
    try {
      final headers = await _authHeaders();
      final response = await _supabase.functions.invoke(
        'wallet-transaction-status',
        headers: headers,
        body: {'deposit_id': depositId},
      );

      final data = response.data;
      if (response.status >= 200 &&
          response.status < 300 &&
          data is Map<String, dynamic> &&
          data['success'] == true) {
        return DepositStatus(
          status: data['status']?.toString() ?? 'pending',
          amount: (data['amount'] as num?)?.toDouble() ?? 0,
          transactionId: data['transaction_id']?.toString(),
          updatedAt: data['updated_at'] != null
              ? DateTime.tryParse(data['updated_at'].toString())
              : null,
          message: data['message']?.toString(),
        );
      }

      final fallbackResponse = await _supabase
          .from('wallet_deposits')
          .select()
          .eq('id', depositId)
          .single();

      return DepositStatus(
        status: fallbackResponse['status'],
        amount: (fallbackResponse['amount'] as num).toDouble(),
        transactionId: fallbackResponse['transaction_id']?.toString(),
        providerStatus: fallbackResponse['provider_status']?.toString(),
        providerError: _providerErrorFromPayload(
          fallbackResponse['provider_payload'],
        ),
        updatedAt: DateTime.tryParse(
          fallbackResponse['updated_at']?.toString() ?? '',
        ),
      );
    } catch (e) {
      return DepositStatus(status: 'error', amount: 0, error: e.toString());
    }
  }

  Future<DepositStatus> waitForDepositConfirmation(
    String depositId, {
    Duration timeout = const Duration(minutes: 5),
    Duration interval = const Duration(seconds: 10),
  }) async {
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < timeout) {
      final status = await checkDepositStatus(depositId);

      if (status.status == 'completed' || status.status == 'failed') {
        return status;
      }

      await Future.delayed(interval);
    }

    return DepositStatus(
      status: 'timeout',
      amount: 0,
      error: 'Tempo limite excedido',
    );
  }

  Future<List<Map<String, dynamic>>> getUserDeposits({
    required String walletId,
  }) async {
    final response = await _supabase
        .from('wallet_deposits')
        .select()
        .eq('wallet_id', walletId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getUserWithdrawals() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return [];

    final response = await _supabase
        .from('withdrawal_requests')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<WalletTransferResult> transferToUser({
    required String targetPhone,
    required double amount,
    String? reason,
  }) async {
    try {
      final recipient = await findWalletRecipient(targetPhone);
      if (recipient == null) {
        return const WalletTransferResult(error: 'Utilizador não encontrado.');
      }
      final targetId = recipient.id;
      if (targetId.isEmpty) {
        return const WalletTransferResult(error: 'Destinatário inválido.');
      }
      final response = await _supabase.rpc(
        'transfer_wallet_balance',
        params: {
          'p_target_user_id': targetId,
          'p_amount': amount,
          'p_reason': reason?.trim().isEmpty == true ? null : reason?.trim(),
        },
      );
      final data = Map<String, dynamic>.from(response as Map);
      return WalletTransferResult(
        success: data['success'] == true,
        recipientName: recipient.name,
        recipientPhone: recipient.phone,
        message: data['success'] == true
            ? 'Transferência concluída com sucesso.'
            : null,
        error: data['error']?.toString(),
      );
    } catch (e) {
      debugPrint('Erro ao transferir saldo: $e');
      return const WalletTransferResult(
        error: 'Não foi possível concluir a transferência agora.',
      );
    }
  }

  Future<WalletRecipient?> findWalletRecipient(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final local = digits.startsWith('258') ? digits.substring(3) : digits;
    if (local.length != 9) return null;

    final rows = await _supabase
        .from('profiles')
        .select('id, phone, role, full_name')
        .ilike('phone', '%$local')
        .inFilter('role', ['client', 'customer', 'courier', 'restaurant'])
        .limit(2);
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first as Map);
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return WalletRecipient(
      id: id,
      phone: row['phone']?.toString() ?? '+258$local',
      role: row['role']?.toString() ?? 'utilizador',
      name: row['full_name']?.toString(),
    );
  }

  String? _providerErrorFromPayload(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final parsed = payload['parsed'];
      final raw = payload['raw']?.toString();
      final nested = _providerErrorFromPayload(parsed);
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }
      return payload['error']?.toString() ??
          payload['message']?.toString() ??
          payload['detail']?.toString() ??
          raw;
    }
    if (payload is Map) {
      return payload['error']?.toString() ??
          payload['message']?.toString() ??
          payload['detail']?.toString();
    }
    return null;
  }

  String? _normalizeWithdrawError(String? error) {
    final normalized = error?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) return null;

    if (normalized.contains('gateway de levantamento indisponivel')) {
      return 'PayTED indisponível no backend. Verifique a configuração segura do provedor.';
    }

    if (normalized.contains('carteira do gateway nao configurada')) {
      return 'PayTED não configurada para este método (M-Pesa/e-Mola).';
    }

    if (normalized.contains('ja existe um levantamento em processamento')) {
      return 'Ja existe um levantamento pendente para esta conta. Aguarde a conclusao antes de tentar novamente.';
    }

    if (normalized.contains('messages.insufficient_balance')) {
      return 'O parceiro de pagamento indicou saldo insuficiente na carteira de levantamento. Tente novamente mais tarde.';
    }

    if (normalized.contains('selected method is not available for payouts') ||
        normalized.contains('method is not available for payouts')) {
      return 'Levantamentos mKesh ainda não estão ativados na conta PaySuite. O número está correto; ative o canal mKesh para payouts no PaySuite.';
    }

    if (normalized.contains('temporariamente indispon') &&
        normalized.contains('emola')) {
      return 'Os levantamentos e-Mola estao temporariamente indisponiveis no parceiro de pagamento. Tente novamente mais tarde ou use M-Pesa.';
    }

    if (normalized.contains('gateway') || normalized.contains('503')) {
      return 'A PayTED está temporariamente indisponível. Tente novamente em alguns minutos.';
    }

    if (normalized.contains('failed to fetch') ||
        normalized.contains('network') ||
        normalized.contains('socket')) {
      return 'Nao foi possivel conectar ao servidor agora. Confirme a internet e tente novamente.';
    }

    if (normalized.contains('codigo expirado') ||
        normalized.contains('codigo invalido')) {
      return 'O codigo SMS expirou ou nao foi aceite. Peca um novo codigo e tente novamente.';
    }

    if (normalized.contains('falha ao solicitar levantamento')) {
      return 'O pedido de levantamento não foi aceite pelo servidor. Tente novamente ou verifique a PayTED.';
    }

    // Preserve provider validation details during PaySuite integration tests;
    // replacing them with a generic message hides the rejected field.
    if (error != null && error.trim().isNotEmpty) {
      final raw = error.trim();
      return raw.length > 320 ? raw.substring(0, 320) : raw;
    }
    return 'Nao foi possivel concluir o levantamento agora. O saldo sera devolvido automaticamente se o provedor nao aceitar o pedido.';
  }
}

class WalletTransferResult {
  final bool success;
  final String? message;
  final String? error;
  final String? recipientName;
  final String? recipientPhone;

  const WalletTransferResult({
    this.success = false,
    this.message,
    this.error,
    this.recipientName,
    this.recipientPhone,
  });
}

class WalletRecipient {
  final String id;
  final String phone;
  final String role;
  final String? name;

  const WalletRecipient({
    required this.id,
    required this.phone,
    required this.role,
    this.name,
  });
}

class WalletDepositResult {
  final bool success;
  final String? depositId;
  final String? reference;
  final String? transactionId;
  final String? message;
  final String? error;
  final bool requiresManualPayment;
  final String? instructions;
  final String? providerStatus;
  final String? providerError;
  final int? providerHttpStatus;
  final String? checkoutUrl;

  WalletDepositResult({
    required this.success,
    this.depositId,
    this.reference,
    this.transactionId,
    this.message,
    this.error,
    this.requiresManualPayment = false,
    this.instructions,
    this.providerStatus,
    this.providerError,
    this.providerHttpStatus,
    this.checkoutUrl,
  });
}

enum WalletWithdrawalOutcome { completed, pending, failed, unknown }

class WalletWithdrawResult {
  final bool success;
  final String? requestId;
  final String? status;
  final String? message;
  final String? error;
  final String? normalizedError;

  WalletWithdrawResult({
    required this.success,
    this.requestId,
    this.status,
    this.message,
    this.error,
    this.normalizedError,
  });

  WalletWithdrawalOutcome get outcome => switch (status?.trim().toLowerCase()) {
    'completed' => WalletWithdrawalOutcome.completed,
    'pending' ||
    'processing' ||
    'in_progress' => WalletWithdrawalOutcome.pending,
    'failed' ||
    'cancelled' ||
    'canceled' ||
    'rejected' ||
    'declined' => WalletWithdrawalOutcome.failed,
    _ => WalletWithdrawalOutcome.unknown,
  };
}

class DepositStatus {
  final String status;
  final double amount;
  final String? transactionId;
  final String? error;
  final DateTime? updatedAt;
  final String? message;
  final String? providerStatus;
  final String? providerError;

  DepositStatus({
    required this.status,
    required this.amount,
    this.transactionId,
    this.error,
    this.updatedAt,
    this.message,
    this.providerStatus,
    this.providerError,
  });
}
