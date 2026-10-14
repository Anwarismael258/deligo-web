import 'package:supabase_flutter/supabase_flutter.dart';

class AccountDeletionResult {
  const AccountDeletionResult({
    required this.requestId,
    required this.requiresManualReview,
    required this.message,
    required this.deleted,
    required this.accountDeactivated,
  });

  final String requestId;
  final bool requiresManualReview;
  final String message;
  final bool deleted;
  final bool accountDeactivated;
}

class AccountDeletionPreview {
  const AccountDeletionPreview({
    required this.canDelete,
    required this.transferableAmount,
    required this.availableBalance,
    required this.pendingBalance,
    required this.currency,
    this.message,
  });

  final bool canDelete;
  final double transferableAmount;
  final double availableBalance;
  final double pendingBalance;
  final String currency;
  final String? message;

  String get confirmationDisclosure => transferableAmount > 0
      ? 'A carteira tem ${transferableAmount.toStringAsFixed(2)} ${currency == 'MZN' ? 'MT' : currency} disponíveis. Ao continuar, este valor será transferido para a Administração DeliGo.'
      : 'A carteira não tem saldo disponível para transferência.';
}

class AccountDeletionService {
  AccountDeletionService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static final Set<String> _deletingUserIds = <String>{};
  static bool _successfulDeletionRedirectPending = false;

  static bool isDeletionInProgress(String userId) =>
      _deletingUserIds.contains(userId);

  static bool consumeSuccessfulDeletionRedirect() {
    final pending = _successfulDeletionRedirectPending;
    _successfulDeletionRedirectPending = false;
    return pending;
  }

  Future<AccountDeletionPreview> previewDeletion() async {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Sessão não encontrada. Inicie sessão novamente.');
    }
    final response = await _client.functions.invoke(
      'request-account-deletion',
      headers: {'Authorization': 'Bearer $token'},
      body: const {'action': 'preview'},
    );
    if (response.status != 200 || response.data is! Map) {
      throw Exception('Não foi possível consultar o saldo da carteira.');
    }
    final data = Map<String, dynamic>.from(response.data as Map);
    return AccountDeletionPreview(
      canDelete: data['can_delete'] == true,
      transferableAmount:
          (data['transferable_amount'] as num?)?.toDouble() ?? 0,
      availableBalance:
          (data['wallet_available_balance'] as num?)?.toDouble() ?? 0,
      pendingBalance:
          (data['wallet_pending_balance'] as num?)?.toDouble() ?? 0,
      currency: data['wallet_currency']?.toString() ?? 'MZN',
      message: data['message']?.toString(),
    );
  }

  Future<AccountDeletionResult> requestDeletion({
    required String confirmationText,
    String? reason,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw Exception('Sessão não encontrada. Inicie sessão novamente.');
    }
    if (!_deletingUserIds.add(userId)) {
      throw Exception('A eliminação da conta já está em curso.');
    }

    try {
      final token = _client.auth.currentSession?.accessToken;
      Map<String, dynamic>? data;
      try {
        final response = await _client.functions.invoke(
          'request-account-deletion',
          headers: token != null && token.isNotEmpty
              ? {'Authorization': 'Bearer $token'}
              : null,
          body: {'confirm_text': confirmationText, 'reason': reason?.trim()},
        );
        final payload = response.data;
        if (response.status == 200 && payload is Map) {
          data = Map<String, dynamic>.from(payload);
        } else {
          throw Exception('request_account_deletion_failed');
        }
      } catch (e) {
        final message = e.toString().toLowerCase();
        if (message.contains('404') || message.contains('not found')) {
          final fallback = await _client.rpc(
            'request_account_deletion_rpc',
            params: {
              'p_confirm_text': confirmationText,
              'p_reason': reason?.trim(),
            },
          );
          if (fallback is Map) {
            data = Map<String, dynamic>.from(fallback);
          }
        }
      }

      if (data == null) {
        throw Exception('Não foi possível eliminar a conta.');
      }

      final deleted =
          data['deleted'] == true &&
          (data['status']?.toString().toLowerCase() == 'completed');
      final accountDeactivated = data['account_deactivated'] == true;
      if (!deleted && !accountDeactivated) {
        final message = data['message']?.toString().trim();
        throw Exception(
          message == null || message.isEmpty
              ? 'A conta não foi eliminada. Nenhuma sessão foi encerrada.'
              : message,
        );
      }

      // Keep the router guard active until the local session has been cleared.
      _successfulDeletionRedirectPending = true;
      try {
        await _client.auth.signOut(scope: SignOutScope.global);
      } catch (_) {
        // Auth may already have removed the user server-side. Always clear the
        // local credentials so a deleted identity cannot render protected pages.
        try {
          await _client.auth.signOut(scope: SignOutScope.local);
        } catch (_) {
          _successfulDeletionRedirectPending = false;
          rethrow;
        }
      }

      return AccountDeletionResult(
        requestId: data['request_id']?.toString() ?? '',
        requiresManualReview: data['requires_manual_review'] == true,
        message:
            data['message']?.toString() ??
            'Pedido de exclusao enviado com sucesso.',
        deleted: deleted,
        accountDeactivated: accountDeactivated,
      );
    } finally {
      _deletingUserIds.remove(userId);
    }
  }
}
