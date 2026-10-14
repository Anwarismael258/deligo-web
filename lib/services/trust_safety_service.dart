import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class TrustSafetyService {
  TrustSafetyService._();

  static final TrustSafetyService instance = TrustSafetyService._();
  static const _deviceFingerprintKey = 'deligo_device_fingerprint_v1';
  final SupabaseClient _supabase = Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  Future<String> getDeviceFingerprint() => _getOrCreateDeviceFingerprint();

  Future<String> _getOrCreateDeviceFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceFingerprintKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;

    final platformPrefix = kIsWeb ? 'web' : defaultTargetPlatform.name;
    final fingerprint = '$platformPrefix-${_uuid.v4()}';
    await prefs.setString(_deviceFingerprintKey, fingerprint);
    return fingerprint;
  }

  Future<void> registerCurrentDevice({
    String? appVersion,
    String? ipAddress,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final fingerprint = await _getOrCreateDeviceFingerprint();
      await _supabase.rpc(
        'register_user_device',
        params: {
          'p_user_id': userId,
          'p_device_fingerprint': fingerprint,
          'p_device_model': kIsWeb ? 'web-client' : defaultTargetPlatform.name,
          'p_os_name': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'p_app_version': appVersion,
          'p_ip_address': ipAddress,
        },
      );
    } catch (e) {
      debugPrint('Erro ao registrar dispositivo no trust engine: $e');
    }
  }

  Future<void> logEvent(
    String eventType, {
    Map<String, dynamic>? metadata,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _supabase.rpc(
        'register_user_event',
        params: {
          'p_user_id': userId,
          'p_event_type': eventType,
          'p_metadata': metadata ?? <String, dynamic>{},
        },
      );
    } catch (e) {
      debugPrint('Erro ao registrar evento de trust: $e');
    }
  }

  Future<Map<String, dynamic>> checkRegistrationGuard({
    required String email,
    required String phone,
  }) async {
    try {
      final fingerprint = await _getOrCreateDeviceFingerprint();
      final response = await _supabase.rpc(
        'check_registration_guard',
        params: {
          'p_email': email.trim().toLowerCase(),
          'p_phone': phone.trim(),
          'p_device_fingerprint': fingerprint,
        },
      );
      if (response is Map<String, dynamic>) {
        return response;
      }
    } catch (e) {
      debugPrint('Erro ao verificar guard de registo: $e');
    }
    return const {
      'allowed': true,
      'email_exists': false,
      'phone_exists': false,
      'device_blocked': false,
      'attempt_count': 0,
    };
  }

  Future<void> recordRegistrationAttempt({
    required String email,
    required String phone,
    required String result,
    String? reason,
    String? role,
  }) async {
    try {
      final fingerprint = await _getOrCreateDeviceFingerprint();
      await _supabase.rpc(
        'record_registration_attempt',
        params: {
          'p_email': email.trim().toLowerCase(),
          'p_phone': phone.trim(),
          'p_device_fingerprint': fingerprint,
          'p_result': result,
          'p_reason': reason,
          'p_role': role,
        },
      );
    } catch (e) {
      debugPrint('Erro ao registrar tentativa de registo: $e');
    }
  }
}
