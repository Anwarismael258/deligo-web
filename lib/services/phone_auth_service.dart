import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_session_bootstrap_service.dart';

class PhoneOtpRequestResult {
  const PhoneOtpRequestResult({this.expiresAt});

  final String? expiresAt;
}

class PhoneAuthVerificationResult {
  const PhoneAuthVerificationResult({
    required this.user,
    required this.profile,
  });

  final User user;
  final Map<String, dynamic>? profile;
}

class PhoneAuthService {
  PhoneAuthService._();

  static final PhoneAuthService instance = PhoneAuthService._();

  final SupabaseClient _supabase = Supabase.instance.client;
  String? _pendingResetTicket;

  bool get hasPendingPasswordReset =>
      (_pendingResetTicket ?? '').trim().isNotEmpty;

  Future<PhoneOtpRequestResult> requestOtp({
    required String phone,
    required String flow,
    String? role,
    String? fullName,
  }) async {
    try {
      final body = {
        'phone': phone,
        'flow': flow,
        if (role?.trim().isNotEmpty == true) 'role': role!.trim(),
        if (fullName?.trim().isNotEmpty == true) 'full_name': fullName!.trim(),
      };
      final response = await _invokeOtpRequest(body);
      final payload = _asMap(response.data);
      _throwIfFunctionError(payload, response.status);

      final data = _nestedData(payload);
      return PhoneOtpRequestResult(expiresAt: data['expires_at']?.toString());
    } catch (error) {
      throw AuthException(_friendlyFunctionError(error));
    }
  }

  Future<FunctionResponse> _invokeOtpRequest(Map<String, dynamic> body) async {
    return await _supabase.functions.invoke('send-phone-otp', body: body);
  }

  Future<PhoneAuthVerificationResult> verifyOtp({
    required String phone,
    required String flow,
    required String code,
    String? role,
    String? fullName,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'verify-phone-otp',
        body: {
          'phone': phone,
          'flow': flow,
          'code': code,
          if (role?.trim().isNotEmpty == true) 'role': role!.trim(),
          if (fullName?.trim().isNotEmpty == true)
            'full_name': fullName!.trim(),
        },
      );

      final payload = _asMap(response.data);
      _throwIfFunctionError(payload, response.status);

      final data = _nestedData(payload);
      await _supabase.auth.signOut();
      final user = await _openSessionFromPayload(data);
      if (user == null) {
        throw const AuthException('Nao foi possivel abrir a sessao agora.');
      }

      final profile = await AuthSessionBootstrapService.instance
          .prepareAuthenticatedUser(user, forcePhoneVerified: true);

      return PhoneAuthVerificationResult(user: user, profile: profile);
    } catch (error) {
      if (error is AuthException) rethrow;
      throw AuthException(_friendlyFunctionError(error));
    }
  }

  Future<void> verifyPasswordResetOtp({
    required String phone,
    required String code,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'verify-phone-otp',
        body: {'phone': phone, 'flow': 'reset', 'code': code},
      );
      final payload = _asMap(response.data);
      _throwIfFunctionError(payload, response.status);
      final ticket = _nestedData(payload)['reset_ticket']?.toString().trim();
      if (ticket == null || ticket.isEmpty) {
        throw const AuthException(
          'Nao foi possivel preparar a recuperacao segura agora.',
        );
      }
      _pendingResetTicket = ticket;
    } catch (error) {
      if (error is AuthException) rethrow;
      throw AuthException(_friendlyFunctionError(error));
    }
  }

  Future<void> resetPasswordWithVerifiedOtp(String password) async {
    final ticket = _pendingResetTicket?.trim();
    if (ticket == null || ticket.isEmpty) {
      throw const AuthException(
        'A verificacao expirou. Peca um novo codigo SMS.',
      );
    }
    try {
      final response = await _supabase.functions.invoke(
        'reset-password-with-ticket',
        body: {'reset_ticket': ticket, 'password': password},
      );
      final payload = _asMap(response.data);
      _throwIfFunctionError(payload, response.status);
      _pendingResetTicket = null;
    } catch (error) {
      if (error is AuthException) rethrow;
      throw AuthException(_friendlyFunctionError(error));
    }
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

  Map<String, dynamic> _nestedData(Map<String, dynamic> payload) {
    final raw = payload['data'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return payload;
  }

  Future<User?> _openSessionFromPayload(Map<String, dynamic> data) async {
    final session = _sessionPayload(data['session']);
    if (session == null) {
      debugPrint(
        'PhoneAuthService: OTP response did not include a valid session payload.',
      );
      return null;
    }
    final recovered = await _supabase.auth.recoverSession(jsonEncode(session));
    return recovered.user ?? _supabase.auth.currentUser;
  }

  Map<String, dynamic>? _sessionPayload(dynamic raw) {
    if (raw is Map<String, dynamic>) return _validatedSessionMap(raw);
    if (raw is Map) {
      return _validatedSessionMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return _validatedSessionMap(decoded);
        }
        if (decoded is Map) {
          return _validatedSessionMap(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      } catch (error) {
        debugPrint(
          'PhoneAuthService: failed to decode OTP session payload: $error',
        );
      }
    }
    return null;
  }

  Map<String, dynamic>? _validatedSessionMap(Map<String, dynamic> session) {
    final accessToken = session['access_token']?.toString().trim() ?? '';
    final refreshToken = session['refresh_token']?.toString().trim() ?? '';
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      debugPrint(
        'PhoneAuthService: OTP session payload missing access_token or refresh_token.',
      );
      return null;
    }
    return session;
  }

  void _throwIfFunctionError(Map<String, dynamic> payload, int status) {
    final success = payload['success'];
    final message =
        payload['message']?.toString() ??
        payload['error']?.toString() ??
        'Nao foi possivel continuar agora.';
    if ((success is bool && !success) || status >= 400) {
      throw AuthException(message);
    }
  }

  String _friendlyFunctionError(Object error) {
    if (error is AuthException) {
      return error.message;
    }

    // supabase_flutter devolve erros HTTP das Edge Functions com o payload em
    // `details`/`context` em versões diferentes do SDK. Não depender de uma
    // classe concreta evita perder a explicação do backend e cair na mensagem
    // genérica de verificação por SMS.
    try {
      final dynamic functionError = error;
      for (final candidate in <dynamic>[
        functionError.details,
        functionError.context,
        functionError.response,
      ]) {
        final message = _messageFromFunctionPayload(candidate);
        if (message != null) return message;
      }
    } catch (_) {
      // O erro pode não ser uma FunctionException; use o fallback abaixo.
    }

    final raw = error.toString();
    final normalized = raw.toLowerCase();

    if (normalized.contains('http status error')) {
      final extracted = RegExp(
        r'\{.*\}',
        dotAll: true,
      ).firstMatch(raw)?.group(0);
      if (extracted != null) {
        try {
          final decoded = jsonDecode(extracted);
          final payload = _asMap(decoded);
          final message =
              payload['message']?.toString() ?? payload['error']?.toString();
          if (message != null && message.trim().isNotEmpty) {
            return message.trim();
          }
        } catch (error) {
          debugPrint(
            'PhoneAuthService: failed to parse function error payload: $error',
          );
        }
      }
    }

    if (normalized.contains('endpoint_not_found')) {
      return 'O envio de SMS da MozeSMS ainda nao esta disponivel. Tente novamente em instantes.';
    }

    return raw.trim().isEmpty
        ? 'Nao foi possivel continuar agora.'
        : raw.replaceFirst('Exception: ', '').trim();
  }

  String? _messageFromFunctionPayload(dynamic raw) {
    if (raw == null) return null;
    try {
      final payload = _asMap(raw);
      final message =
          payload['message']?.toString() ??
          payload['error']?.toString() ??
          (payload['data'] is Map
              ? _asMap(payload['data'])['message']?.toString() ??
                    _asMap(payload['data'])['error']?.toString()
              : null);
      return message?.trim().isNotEmpty == true ? message!.trim() : null;
    } catch (_) {
      return null;
    }
  }
}
