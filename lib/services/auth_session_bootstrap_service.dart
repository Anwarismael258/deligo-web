import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

import '../config/router/app_router.dart';
import 'notification_dispatch_service.dart';

class AuthSessionBootstrapService {
  AuthSessionBootstrapService._();

  static final AuthSessionBootstrapService instance =
      AuthSessionBootstrapService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> prepareAuthenticatedUser(
    User user, {
    bool forcePhoneVerified = false,
  }) async {
    final profile = await _ensureProfileBootstrap(
      user,
      forcePhoneVerified: forcePhoneVerified,
    );
    // Ensure the wallet record exists for every authenticated profile. The
    // backend still blocks real financial operations until phone verification.
    await _ensureWalletAndUser(user);
    return profile;
  }

  Future<void> _ensureWalletAndUser(User user) async {
    try {
      final userMetadata = user.userMetadata ?? const <String, dynamic>{};
      await _supabase.functions.invoke('ensure-wallet', body: {
        'role': userMetadata['role'],
        'full_name': userMetadata['full_name'],
        'phone': user.phone ?? userMetadata['phone'],
        'email': user.email,
      });
    } catch (error) {
      debugPrint('AuthSessionBootstrapService.ensureWallet error: $error');
    }
  }

  Future<Map<String, dynamic>?> _ensureProfileBootstrap(
    User user, {
    required bool forcePhoneVerified,
  }) async {
    final userMetadata = user.userMetadata ?? const <String, dynamic>{};
    final appMetadata = user.appMetadata;
    final role =
        (userMetadata['role'] as String?) ??
        (appMetadata['role'] as String?) ??
        'client';
    final phone =
        user.phone?.trim().isNotEmpty == true
            ? user.phone!.trim()
            : (userMetadata['phone'] as String?)?.trim();
    final fullName =
        (userMetadata['full_name'] as String?)?.trim().isNotEmpty == true
            ? (userMetadata['full_name'] as String).trim()
            : (user.email?.split('@').first ?? phone ?? 'Novo utilizador');
    Map<String, dynamic>? existingProfile;
    try {
      final existing = await _supabase
          .from('profiles')
          .select(
            'id, role, kyc_status, is_blocked, block_reason, is_suspicious, settings, kyc_completed, kyc_docs',
          )
          .eq('id', user.id)
          .maybeSingle();
      if (existing != null) {
        existingProfile = Map<String, dynamic>.from(existing);
      }
    } catch (error) {
      debugPrint('AuthSessionBootstrapService.loadProfile error: $error');
    }

    final settings =
        (existingProfile?['settings'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final existingVerifiedAt = settings['phone_verified_at']?.toString().trim();
    final computedVerifiedAt =
        forcePhoneVerified
            ? DateTime.now().toIso8601String()
            : user.phoneConfirmedAt?.toString() ??
                ((existingVerifiedAt?.isNotEmpty ?? false)
                    ? existingVerifiedAt
                    : null);
    final phoneVerificationRequired =
        forcePhoneVerified
            ? false
            : computedVerifiedAt == null && phone?.isNotEmpty == true;
    final nextSettings = <String, dynamic>{
      'language': 'pt',
      'currency': 'MZN',
      'sound_enabled': true,
      'voice_mode': 'important_only',
      ...settings,
      'phone_verification_required': phoneVerificationRequired,
      'phone_verified_at': computedVerifiedAt,
    };

    final profilePayload = <String, dynamic>{
      'id': user.id,
      'user_id': user.id,
      'full_name': fullName,
      'phone': phone,
      'role': existingProfile?['role'] ?? role,
      'settings': nextSettings,
      'kyc_completed':
          existingProfile?['kyc_completed'] ?? ((existingProfile?['role'] ?? role) == 'client'),
      'kyc_status':
          existingProfile?['kyc_status'] ?? (((existingProfile?['role'] ?? role) == 'client') ? 'approved' : 'pending'),
      'kyc_docs': existingProfile?['kyc_docs'],
    };

    try {
      if (existingProfile == null) {
        await _supabase.from('profiles').insert(profilePayload);
      } else {
        await _supabase.from('profiles').update({
          'full_name': fullName,
          'phone': phone,
          'role': existingProfile['role'] ?? role,
          'settings': nextSettings,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', user.id);
      }
    } catch (error) {
      debugPrint('AuthSessionBootstrapService.upsertProfile error: $error');
      throw StateError(
        'Nao foi possivel preparar o perfil autenticado neste momento.',
      );
    }

    final effectiveRole = existingProfile?['role'] ?? role;
    var createdRestaurant = false;
    var createdCourier = false;

    if (effectiveRole == 'restaurant') {
      try {
        final existingRestaurant = await _supabase
            .from('restaurants')
            .select('owner_id')
            .eq('owner_id', user.id)
            .maybeSingle();
        if (existingRestaurant == null) {
          await _supabase.from('restaurants').insert({
            'owner_id': user.id,
            'name': fullName,
            'description': 'Parceiro DeliGo MZ',
            'phone': phone,
            'is_open': false,
          });
          createdRestaurant = true;
        }
      } catch (error) {
        debugPrint('AuthSessionBootstrapService.ensureRestaurant error: $error');
      }
    }

    if (effectiveRole == 'courier') {
      try {
        final existingCourier = await _supabase
            .from('couriers')
            .select('id')
            .eq('id', user.id)
            .maybeSingle();
        if (existingCourier == null) {
          await _supabase.from('couriers').insert({
            'id': user.id,
            'full_name': fullName,
            'phone': phone,
            'is_online': false,
            'vehicle_type': 'motorbike',
            'rating': 5.0,
            'total_deliveries': 0,
            'earnings_today': 0,
            'acceptance_rate': 100,
            'cancellation_rate': 0,
          });
          createdCourier = true;
        }
      } catch (error) {
        debugPrint('AuthSessionBootstrapService.ensureCourier error: $error');
      }
    }

    if (existingProfile == null || createdRestaurant || createdCourier) {
      await _notifyFieldReviewersOfNewRegistration(
        userId: user.id,
        role: effectiveRole,
        fullName: fullName,
      );
    }

    final primedProfile = <String, dynamic>{
      'role': existingProfile?['role'] ?? role,
      'kyc_status':
          existingProfile?['kyc_status'] ?? ((role == 'client') ? 'approved' : 'pending'),
      'is_blocked': existingProfile?['is_blocked'] ?? false,
      'block_reason': existingProfile?['block_reason'],
      'is_suspicious': existingProfile?['is_suspicious'] ?? false,
      'settings': nextSettings,
      'kyc_completed':
          existingProfile?['kyc_completed'] ?? (role == 'client'),
      'kyc_docs': existingProfile?['kyc_docs'],
    };
    AppRouter.primeProfileCache(user.id, primedProfile);
    return primedProfile;
  }

  Future<void> _notifyFieldReviewersOfNewRegistration({
    required String userId,
    required String role,
    required String fullName,
  }) async {
    if (role != 'restaurant' && role != 'courier') return;
    final title = role == 'restaurant'
        ? 'Novo cadastro de restaurante'
        : 'Novo cadastro de estafeta';
    final body = '$fullName entrou para revisao no DeliGo Field.';
    final data = {
      'user_id': userId,
      'subject_type': role,
      'subject_name': fullName,
      'kyc_status': 'pending',
    };
    await NotificationDispatchService.instance.sendToRole(
      targetRole: 'admin',
      type: 'KYC_SUBMITTED',
      title: title,
      body: body,
      action: 'OPEN_KYC_REVIEW',
      entityId: userId,
      priority: 'HIGH',
      channel: 'admin_kyc',
      data: data,
      metadata: {'source': 'auth_session_bootstrap'},
    );
    await NotificationDispatchService.instance.sendToRole(
      targetRole: 'field_agent',
      type: 'KYC_SUBMITTED',
      title: title,
      body: body,
      action: 'OPEN_KYC_REVIEW',
      entityId: userId,
      priority: 'HIGH',
      channel: 'admin_kyc',
      data: data,
      metadata: {'source': 'auth_session_bootstrap'},
    );
  }

  bool _hasVerifiedPhone({
    required User user,
    required Map<String, dynamic>? profile,
  }) {
    if (user.phoneConfirmedAt != null) return true;
    final settings = (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final verifiedAt = settings['phone_verified_at']?.toString().trim() ?? '';
    return verifiedAt.isNotEmpty;
  }
}
