import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_env.dart';

class FieldVerificationService {
  FieldVerificationService(this._supabase);

  final SupabaseClient _supabase;

  static const Map<String, String> roleLabels = {
    'field_agent': 'Agente de Verificacao',
    'support_agent': 'Suporte ao Cliente',
    'ambassador': 'Embaixador',
    'marketing_agent': 'Marketing e Publicidade',
    'admin': 'Admin',
  };

  Future<Map<String, dynamic>?> fetchCurrentStaffProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return null;

    final profile = await _supabase
        .from('profiles')
        .select(
          'id, full_name, phone, role, city, staff_active, '
          'created_at, updated_at',
        )
        .eq('id', userId)
        .maybeSingle();
    if (profile == null) return null;
    return Map<String, dynamic>.from(profile);
  }

  Future<List<Map<String, dynamic>>> fetchVerificationCases({
    String status = 'pending',
    String role = 'all',
    String query = '',
    String city = 'all',
  }) async {
    var request = _supabase
        .from('profiles')
        .select(
          'id, full_name, phone, role, city, address, email, kyc_status, '
          'kyc_rejection_reason, kyc_docs, approval_submitted_at, '
          'approval_sla_deadline, verification_score, is_blocked, '
          'block_reason, created_at, updated_at',
        );

    if (role == 'restaurant' || role == 'courier') {
      request = request.eq('role', role);
    } else {
      request = request.inFilter('role', ['restaurant', 'courier']);
    }

    if (status != 'all') {
      request = request.eq('kyc_status', status);
    }

    if (city != 'all' && city.trim().isNotEmpty) {
      request = request.eq('city', city.trim());
    }

    final result = await request
        .order('approval_submitted_at', ascending: true)
        .order('updated_at', ascending: false)
        .limit(250);

    final rows = (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();

    final trimmedQuery = query.trim().toLowerCase();
    if (trimmedQuery.isEmpty) return rows;

    return rows.where((row) {
      final haystack = [
        row['full_name'],
        row['phone'],
        row['city'],
        row['address'],
        row['id'],
        row['role'],
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
      return haystack.contains(trimmedQuery);
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchAuditTrail({
    String? entityId,
    int limit = 50,
  }) async {
    var request = _supabase
        .from('admin_actions_log')
        .select('id, admin_id, user_id, action, reason, metadata, created_at');
    if (entityId != null && entityId.isNotEmpty) {
      request = request.eq('user_id', entityId);
    }
    final result = await request
        .order('created_at', ascending: false)
        .limit(limit);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchSupportActionsToday() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return const [];

    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).toUtc();
    final result = await _supabase
        .from('admin_actions_log')
        .select('id, admin_id, user_id, action, reason, metadata, created_at')
        .eq('admin_id', userId)
        .gte('created_at', start.toIso8601String())
        .order('created_at', ascending: false)
        .limit(100);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchSupportTickets() async {
    final rows = <Map<String, dynamic>>[];

    try {
      final result = await _supabase
          .from('order_disputes')
          .select(
            'id, order_id, opened_by, opened_by_role, dispute_type, reason, '
            'status, created_at, updated_at',
          )
          .order('created_at', ascending: false)
          .limit(100);
      rows.addAll(
        (result as List).cast<Map<String, dynamic>>().map(
          (row) => {
            ...Map<String, dynamic>.from(row),
            'external_source': 'order_disputes',
          },
        ),
      );
    } catch (_) {
      // Internal support tickets can still load if order disputes are unavailable.
    }

    try {
      final result = await _supabase
          .from('support_tickets')
          .select(
            'id, external_source, external_id, opened_by, opened_by_role, '
            'customer_name, customer_phone, customer_email, dispute_type, '
            'reason, status, assigned_to, resolution, resolved_at, metadata, '
            'created_at, updated_at',
          )
          .order('updated_at', ascending: false)
          .limit(150);
      rows.addAll(
        (result as List).cast<Map<String, dynamic>>().map(
          Map<String, dynamic>.from,
        ),
      );
    } catch (_) {
      // Older deployments may not have support_tickets yet.
    }

    rows.sort((a, b) {
      final aDate =
          DateTime.tryParse(
            a['updated_at']?.toString() ?? a['created_at']?.toString() ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          DateTime.tryParse(
            b['updated_at']?.toString() ?? b['created_at']?.toString() ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return _enrichSupportTicketsWithProfiles(rows);
  }

  Future<List<Map<String, dynamic>>> _enrichSupportTicketsWithProfiles(
    List<Map<String, dynamic>> rows,
  ) async {
    final openedByIds = rows
        .map((row) => row['opened_by']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (openedByIds.isEmpty) return rows;

    try {
      final profiles = await _supabase
          .from('profiles')
          .select('id, full_name, phone, email')
          .inFilter('id', openedByIds);
      final byId = {
        for (final row in (profiles as List).cast<Map<String, dynamic>>())
          row['id']?.toString() ?? '': row,
      };
      return rows.map((row) {
        final profile = byId[row['opened_by']?.toString() ?? ''];
        if (profile == null) return row;
        return {
          ...row,
          'customer_name':
              row['customer_name']?.toString().trim().isNotEmpty == true
              ? row['customer_name']
              : profile['full_name'],
          'customer_phone':
              row['customer_phone']?.toString().trim().isNotEmpty == true
              ? row['customer_phone']
              : profile['phone'],
          'customer_email':
              row['customer_email']?.toString().trim().isNotEmpty == true
              ? row['customer_email']
              : profile['email'],
        };
      }).toList();
    } catch (_) {
      return rows;
    }
  }

  Future<List<Map<String, dynamic>>> fetchSupportOrders() async {
    try {
      final result = await _supabase
          .from('orders')
          .select(
            'id, client_id, restaurant_id, courier_id, status, total_amount, '
            'delivery_address, dispute_reason, created_at, updated_at',
          )
          .order('created_at', ascending: false)
          .limit(80);
      return (result as List)
          .cast<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSupportRestaurants() async {
    try {
      final result = await _supabase
          .from('restaurants')
          .select(
            'id, owner_id, name, phone, city, neighborhood, is_open, updated_at',
          )
          .order('updated_at', ascending: false)
          .limit(80);
      return (result as List)
          .cast<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSupportCouriers() async {
    try {
      final result = await _supabase
          .from('couriers')
          .select(
            'id, full_name, phone, is_online, is_suspended, suspension_reason, updated_at',
          )
          .order('updated_at', ascending: false)
          .limit(80);
      return (result as List)
          .cast<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSupportClients() async {
    try {
      final result = await _supabase
          .from('profiles')
          .select(
            'id, full_name, phone, role, is_blocked, block_reason, updated_at',
          )
          .inFilter('role', ['client', 'customer'])
          .order('updated_at', ascending: false)
          .limit(80);
      return (result as List)
          .cast<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchStaffOperationalStatus() async {
    final staffRows = await _supabase
        .from('profiles')
        .select(
          'id, full_name, phone, role, staff_active, updated_at, created_at',
        )
        .inFilter('role', [
          'admin',
          'field_agent',
          'support_agent',
          'ambassador',
          'marketing_agent',
        ])
        .order('role', ascending: true)
        .order('updated_at', ascending: false)
        .limit(200);
    final staff = (staffRows as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
    final ids = staff
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return staff;

    final tokenRows = await _supabase
        .from('user_push_tokens')
        .select('user_id, platform, is_active, last_seen_at, updated_at')
        .inFilter('user_id', ids)
        .order('last_seen_at', ascending: false)
        .limit(500);
    final latestTokenByUser = <String, Map<String, dynamic>>{};
    for (final row in (tokenRows as List).cast<Map<String, dynamic>>()) {
      final token = Map<String, dynamic>.from(row);
      final userId = token['user_id']?.toString() ?? '';
      if (userId.isEmpty || latestTokenByUser.containsKey(userId)) continue;
      latestTokenByUser[userId] = token;
    }

    return staff.map((row) {
      final token = latestTokenByUser[row['id']?.toString() ?? ''];
      return {
        ...row,
        'push_token_active': token?['is_active'] == true,
        'push_platform': token?['platform'],
        'push_last_seen_at': token?['last_seen_at'] ?? token?['updated_at'],
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchInternalNotes(String entityId) async {
    final result = await _supabase
        .from('field_internal_notes')
        .select('id, entity_id, entity_type, note, created_by, created_at')
        .eq('entity_id', entityId)
        .order('created_at', ascending: false)
        .limit(50);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<void> addInternalNote({
    required String entityId,
    required String entityType,
    required String note,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw Exception('Sessao expirada. Entre novamente.');
    }

    await _supabase.from('field_internal_notes').insert({
      'entity_id': entityId,
      'entity_type': entityType,
      'note': note.trim(),
      'created_by': userId,
    });
  }

  Future<void> addSupportActivity({
    required String action,
    required String reason,
    Map<String, dynamic> metadata = const {},
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw Exception('Sessao expirada. Entre novamente.');
    }

    await _supabase.from('admin_actions_log').insert({
      'admin_id': userId,
      'user_id': userId,
      'action': action,
      'reason': reason.trim().isEmpty ? null : reason.trim(),
      'metadata': {'source': 'support_dashboard', ...metadata},
    });
  }

  Future<List<Map<String, dynamic>>> fetchKycDocuments({
    required String userId,
    required String subjectType,
  }) async {
    try {
      final response = await _invokeFunctionDirect(
        'get_kyc_docs',
        body: {'user_id': userId, 'subject_type': subjectType},
      );
      if (response.status >= 400) {
        throw Exception(response.json['error']?.toString() ?? response.json);
      }

      return ((response.json['document_items'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map<Map<String, dynamic>>(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          )
          .toList();
    } catch (_) {
      final profile = await _supabase
          .from('profiles')
          .select('kyc_docs')
          .eq('id', userId)
          .maybeSingle();
      final rawDocs =
          (profile?['kyc_docs'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return rawDocs.entries.map((entry) {
        final value =
            (entry.value as Map?)?.cast<String, dynamic>() ?? const {};
        return <String, dynamic>{
          'label': entry.key,
          'path': value['path']?.toString() ?? '',
          'bucket': value['bucket']?.toString() ?? 'kyc',
          'content_type': value['content_type']?.toString(),
          'url': '',
        };
      }).toList();
    }
  }

  Future<String> resolveDocumentUrl(Map<String, dynamic> document) async {
    final existingUrl = document['url']?.toString() ?? '';
    if (existingUrl.isNotEmpty) return existingUrl;

    final bucket = document['bucket']?.toString() ?? 'kyc';
    final path = document['path']?.toString() ?? '';
    if (path.isEmpty) return '';
    return _supabase.storage.from(bucket).createSignedUrl(path, 60 * 10);
  }

  Future<void> decideKyc({
    required Map<String, dynamic> profile,
    required String decision,
    String? reason,
    Map<String, bool> checklist = const {},
  }) async {
    final subjectId = profile['id']?.toString() ?? '';
    final subjectType = profile['role']?.toString() ?? '';
    final staffId = _supabase.auth.currentUser?.id;
    if (subjectId.isEmpty || subjectType.isEmpty || staffId == null) {
      throw Exception('Dados insuficientes para decidir o cadastro.');
    }

    final response = await _invokeFunctionDirect(
      'approve_kyc',
      body: {
        'admin_id': staffId,
        'user_id': subjectId,
        'subject_type': subjectType,
        'decision': decision,
        if (checklist.isNotEmpty) 'checklist': checklist,
        if (reason?.trim().isNotEmpty == true) 'reason': reason!.trim(),
      },
    );
    if (response.status >= 400) {
      throw Exception(response.json['error']?.toString() ?? response.json);
    }
  }

  Future<void> _logFieldAction({
    required String targetUserId,
    required String action,
    String? reason,
    Map<String, dynamic> metadata = const {},
  }) async {
    final staffId = _supabase.auth.currentUser?.id;
    if (staffId == null || staffId.isEmpty || targetUserId.isEmpty) return;

    await _supabase.from('admin_actions_log').insert({
      'admin_id': staffId,
      'user_id': targetUserId,
      'action': action,
      'reason': reason?.trim().isNotEmpty == true ? reason!.trim() : null,
      'metadata': metadata,
    });
  }

  Future<_DirectFunctionResponse> _invokeFunctionDirect(
    String functionName, {
    required Map<String, dynamic> body,
  }) async {
    final token = (_supabase.auth.currentSession?.accessToken ?? '').trim();
    if (token.isEmpty) {
      throw Exception('Sessao expirada. Entre novamente.');
    }

    final supabaseUrl = AppEnv.supabaseUrl.trim();
    final anonKey = AppEnv.supabaseAnonKey.trim();
    if (supabaseUrl.isEmpty || anonKey.isEmpty) {
      throw Exception('Configuracao do Supabase incompleta.');
    }

    final response = await http.post(
      Uri.parse('$supabaseUrl/functions/v1/$functionName'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'apikey': anonKey,
      },
      body: jsonEncode(body),
    );

    return _DirectFunctionResponse(
      status: response.statusCode,
      json: _parseFunctionJson(response.body),
    );
  }

  Map<String, dynamic> _parseFunctionJson(String body) {
    if (body.trim().isEmpty) return const <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{'data': decoded};
    } catch (_) {
      return <String, dynamic>{'error': body};
    }
  }
}

class _DirectFunctionResponse {
  const _DirectFunctionResponse({required this.status, required this.json});

  final int status;
  final Map<String, dynamic> json;
}
