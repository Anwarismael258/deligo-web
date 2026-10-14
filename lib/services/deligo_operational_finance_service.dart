import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class DeligoOperationalFinanceService {
  DeligoOperationalFinanceService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const _uuid = Uuid();

  Future<Map<String, dynamic>> load({
    required String beneficiaryType,
    DateTime? from,
    DateTime? to,
  }) async {
    final response = await _client.rpc(
      'deligo_partner_finance_summary_v1',
      params: {
        'p_beneficiary_type': beneficiaryType,
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> requestWithdrawal({
    required String beneficiaryType,
    required double amount,
    String? reason,
  }) async {
    // Per-attempt idempotency key: retries of a submitted request must reuse
    // this key at the caller layer if the network outcome is uncertain.
    final response = await _client.rpc(
      'deligo_partner_request_withdrawal_v1',
      params: {
        'p_beneficiary_type': beneficiaryType,
        'p_amount': amount,
        'p_idempotency_key': 'mobile-${_uuid.v4()}',
        'p_reason': reason,
        'p_session_metadata': {
          'source': 'deligo_mobile_operational_finance',
          'requested_at': DateTime.now().toUtc().toIso8601String(),
        },
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  RealtimeChannel subscribe({
    required String beneficiaryType,
    required void Function() onChanged,
  }) {
    final userId = _client.auth.currentUser?.id;
    final channel = _client.channel('operational-finance-$beneficiaryType-$userId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deligo_financial_ledger',
          callback: (_) => onChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deligo_withdrawals',
          callback: (_) => onChanged(),
        )
        .subscribe();
    return channel;
  }
}
