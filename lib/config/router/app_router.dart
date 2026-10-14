import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/kyc_pending_page.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/phone_otp_page.dart';
import '../../features/auth/register_page.dart';
import '../../features/auth/reset_password_page.dart';
import '../../features/auth/terms_page.dart';
import '../../features/admin/admin_dashboard.dart';
import '../../features/admin/social_moderation_page.dart';
import '../../features/auth/auth_callback_page.dart';
import '../../features/auth/blocked_account_page.dart';
import '../../features/auth/central_access_page.dart';
import '../../features/auth/create_password_page.dart';
import '../../features/auth/deligo_role_selection_page.dart';
import '../../features/auth/forgot_password_page.dart';
import '../../features/cart/cart_page.dart';
import '../../features/guest/guest_help_page.dart';
import '../../features/chat/chat_page.dart';
import '../../features/chat/chat_provider.dart';
import '../../features/couriers/courier_public_page.dart';
import '../../features/dashboards/client_dashboard.dart';
import '../../features/dashboards/courier_dashboard_enhanced.dart';
import '../../features/dashboards/restaurant_dashboard.dart';
import '../../features/dashboards/restaurant_qr_page.dart';
import '../../features/field/field_dashboard.dart';
import '../../features/legal/legal_documents_page.dart';
import '../../features/language/language_setup_page.dart';
import '../../features/marketing/marketing_dashboard.dart';
import '../../features/marketing/campaign_detail_page.dart';
import '../../features/marketing/official_home_page.dart';
import '../../features/marketing/restaurant_marketing_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/orders/order_details_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/promotions/promo_campaign_page.dart';
import '../../features/referrals/restaurant_invite_page.dart';
import '../../features/restaurants/restaurant_detail_page.dart';
import '../../features/restaurants/restaurant_public_page.dart';
import '../../shared/models/menu_item.dart';
import '../../features/reviews/review_thread_page.dart';
import '../../features/ai/deligo_ai_chat_page.dart';
import '../../features/splash/splash_page.dart';
import '../../features/guest/guest_home_page.dart';
import '../../features/tracking/tracking_map_page.dart';
import '../../features/tracking/tracking_provider.dart';
import '../../features/wallet/wallet_page.dart';
import '../../features/wallet/deligo_operational_finance_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/support/support_chat_page.dart';
import '../../services/app_variant_service.dart';
import '../../services/account_deletion_service.dart';
import '../../services/firebase_analytics_service.dart';

class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      _handleAuthChange();
    });
    _handleAuthChange();
  }

  late final StreamSubscription<AuthState> _sub;
  RealtimeChannel? _profileChannel;
  String? _subscribedUserId;
  bool _hadAuthenticatedSession =
      Supabase.instance.client.auth.currentUser != null;
  bool _sessionExpired = false;

  static bool _pendingIntentionalSignOut = false;

  static void markIntentionalSignOut() {
    _pendingIntentionalSignOut = true;
  }

  void _handleAuthChange() {
    final user = Supabase.instance.client.auth.currentUser;
    final previousUserId = _subscribedUserId;

    if (_pendingIntentionalSignOut) {
      _pendingIntentionalSignOut = false;
      _sessionExpired = false;
      _hadAuthenticatedSession = false;
    } else if (user == null && _hadAuthenticatedSession) {
      _sessionExpired = true;
      _hadAuthenticatedSession = false;
    } else if (user != null) {
      _hadAuthenticatedSession = true;
      _sessionExpired = false;
    }

    if (previousUserId != null && previousUserId != user?.id) {
      AppRouter.invalidateProfileCache(previousUserId);
    }

    _syncProfileSubscription(user?.id);
    notifyListeners();
  }

  void _syncProfileSubscription(String? userId) {
    if (_subscribedUserId == userId) return;

    final client = Supabase.instance.client;

    if (_profileChannel != null) {
      client.removeChannel(_profileChannel!);
      _profileChannel = null;
    }

    _subscribedUserId = userId;
    if (userId == null || userId.isEmpty) return;

    _profileChannel = client.channel('router-profile-$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'profiles',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: userId,
        ),
        callback: (_) {
          AppRouter.invalidateProfileCache(userId);
          notifyListeners();
        },
      )
      ..subscribe();
  }

  bool consumeSessionExpired() {
    final value = _sessionExpired;
    _sessionExpired = false;
    return value;
  }

  @override
  void dispose() {
    _sub.cancel();
    if (_profileChannel != null) {
      Supabase.instance.client.removeChannel(_profileChannel!);
    }
    super.dispose();
  }
}

class AppRouter {
  static const Set<String> _publicRoutes = {
    '/',
    '/app',
    '/home',
    '/cart',
    '/support',
    '/help',
    '/delivery-maputo',
    '/restaurantes-em-maputo',
    '/cadastro-restaurante',
    '/estafetas',
    '/onboarding',
    '/language-setup',
    '/login',
    '/register',
    '/forgot-password',
    '/create-password',
    '/terms',
    '/privacy',
    '/refund-policy',
    '/auth/callback',
    '/reset-password',
    '/phone-otp',
    '/invite',
    '/promo',
    '/restaurant',
    '/courier',
  };

  static final _profileCache = <String, Map<String, dynamic>>{};
  static final _profileCacheAt = <String, DateTime>{};
  static const _profileTtl = Duration(seconds: 5);

  static final AuthRefreshNotifier authNotifier = AuthRefreshNotifier();
  static bool get isFieldBuild => AppVariantService.isField;
  static bool get isMarketingBuild => AppVariantService.isMarketing;
  static bool get isStaffBuild => AppVariantService.isStaff;

  static final GoRouter router = GoRouter(
    initialLocation: AppVariantService.isMarketing
        ? '/marketing-dashboard'
        : AppVariantService.isField
        ? '/field-dashboard'
        : '/',
    refreshListenable: authNotifier,
    observers: FirebaseAnalyticsService.instance.observer == null
        ? const <NavigatorObserver>[]
        : [FirebaseAnalyticsService.instance.observer!],
    redirect: (context, state) async {
      final location = state.matchedLocation;
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) {
        if (_requiresAuth(location)) {
          if (AccountDeletionService.consumeSuccessfulDeletionRedirect()) {
            return '/login?status=account_deleted';
          }
          if (authNotifier.consumeSessionExpired()) {
            return '/login?status=session_expired';
          }
          return '/login';
        }
        return null;
      }

      // Account deletion removes the backend profile before the function
      // response returns. Do not route that short-lived, intentional state to
      // role selection (which is not valid for an identity being deleted).
      if (AccountDeletionService.isDeletionInProgress(user.id) &&
          _requiresAuth(location)) {
        return null;
      }

      final profile = await _getProfile(user.id);
      if (profile == null &&
          location != '/role-selection' &&
          // A transient profile read failure must not trap an already
          // authenticated customer in a redirect loop between role selection
          // and the client dashboard. The dashboard can render its own
          // loading/empty state while the profile cache recovers.
          location != '/client-dashboard' &&
          !AppVariantService.isField &&
          !AppVariantService.isMarketing) {
        return '/role-selection';
      }
      final role = profile?['role'] as String? ?? 'client';
      final kycStatus = profile?['kyc_status'] as String?;
      final settings =
          (profile?['settings'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if (settings['account_deletion_completed'] == true) {
        invalidateProfileCache(user.id);
        AuthRefreshNotifier.markIntentionalSignOut();
        await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
        return '/login?status=account_deleted';
      }
      final passwordSetupRequired = settings['password_setup_required'] == true;
      final isBlocked = profile?['is_blocked'] == true;
      final emailConfirmed = user.emailConfirmedAt != null;
      final needsPhoneVerification = requiresPhoneVerification(
        profile: profile,
        user: user,
      );
      final intendedDestination = destinationForRole(
        role,
        kycStatus: kycStatus,
        emailConfirmed: emailConfirmed,
        phoneVerificationRequired: needsPhoneVerification,
      );
      final isWrongStaffAppAccount =
          (AppVariantService.isField && !_isFieldBuildRole(role)) ||
          (AppVariantService.isMarketing && !_isMarketingBuildRole(role));

      if (location == '/auth/callback') {
        return null;
      }

      if (location == '/phone-otp') {
        return null;
      }

      if (passwordSetupRequired && location != '/create-password') {
        return '/create-password';
      }

      if (isWrongStaffAppAccount) {
        await Supabase.instance.client.auth.signOut();
        return '/login?status=wrong_app';
      }

      // Staff identities belong to the dedicated Field/Marketing apps. The
      // customer DeliGo app must never route them into an internal dashboard.
      if (!AppVariantService.isStaff && _isStaffOnlyRole(role)) {
        await Supabase.instance.client.auth.signOut();
        return '/login?status=wrong_app';
      }

      if (_isPublicRoute(location)) {
        if (_isMarketingRoute(location) ||
            location == '/app' ||
            location.startsWith('/invite/') ||
            location.startsWith('/restaurant/') ||
            location.startsWith('/courier/') ||
            location == '/terms' ||
            location == '/privacy' ||
            location == '/refund-policy' ||
            location == '/reset-password' ||
            location == '/create-password') {
          return null;
        }
        return intendedDestination;
      }

      if (isBlocked) {
        if (location != '/blocked-account') return '/blocked-account';
        return null;
      }

      if (needsPhoneVerification) {
        if (location != '/phone-otp') return '/phone-otp';
        return null;
      }

      if (location == '/phone-otp' && !needsPhoneVerification) {
        return destinationForRole(
          role,
          kycStatus: kycStatus,
          emailConfirmed: emailConfirmed,
        );
      }

      if ((role == 'courier' || role == 'restaurant') &&
          kycStatus != 'approved') {
        if (location != '/kyc-pending') return '/kyc-pending';
      }

      if (location == '/kyc-pending' &&
          role != 'courier' &&
          role != 'restaurant') {
        return dashboardForRole(role);
      }

      if (!isRouteAllowedForRole(location, role)) {
        return dashboardForRole(role);
      }

      return null;
    },
    routes: [
      // Web, Android and iOS now enter through the same mobile app flow.
      GoRoute(path: '/', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/app', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/home', builder: (context, state) => const GuestHomePage()),
      GoRoute(path: '/help', builder: (context, state) => const GuestHelpPage()),
      GoRoute(
        path: '/delivery-maputo',
        builder: (context, state) => const OfficialHomePage(),
      ),
      GoRoute(
        path: '/restaurantes-em-maputo',
        builder: (context, state) => const OfficialHomePage(),
      ),
      GoRoute(
        path: '/cadastro-restaurante',
        builder: (context, state) => const OfficialHomePage(),
      ),
      GoRoute(
        path: '/estafetas',
        builder: (context, state) => const OfficialHomePage(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/language-setup',
        builder: (context, state) => const LanguageSetupPage(),
      ),
      GoRoute(
        path: '/deligo-ai',
        builder: (context, state) => const DeligoAiChatPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginPage(
          status: state.uri.queryParameters['status'],
          initialPhone: state.uri.queryParameters['phone'],
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) =>
            RegisterPage(initialRole: state.uri.queryParameters['role']),
      ),
      GoRoute(
        path: '/role-selection',
        builder: (context, state) => const DeligoRoleSelectionPage(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/create-password',
        builder: (context, state) => const CreatePasswordPage(),
      ),
      GoRoute(
        path: '/phone-otp',
        builder: (context, state) => PhoneOtpPage(
          phone: state.uri.queryParameters['phone'],
          flow: state.uri.queryParameters['flow'] ?? 'session',
          role: state.uri.queryParameters['role'],
          fullName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordPage(),
      ),
      GoRoute(path: '/terms', builder: (context, state) => const TermsPage()),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const PrivacyPolicyPage(),
      ),
      GoRoute(
        path: '/refund-policy',
        builder: (context, state) => const RefundPolicyPage(),
      ),
      GoRoute(
        path: '/auth/callback',
        builder: (context, state) => const AuthCallbackPage(),
      ),
      GoRoute(
        path: '/kyc-pending',
        builder: (context, state) => const KycPendingPage(),
      ),
      GoRoute(
        path: '/blocked-account',
        builder: (context, state) => const BlockedAccountPage(),
      ),
      GoRoute(
        path: '/invite/:shareToken',
        builder: (context, state) {
          final shareToken = state.pathParameters['shareToken']!;
          return RestaurantInvitePage(shareToken: shareToken);
        },
      ),
      GoRoute(
        path: '/promo',
        builder: (context, state) => PromoCampaignPage(
          campaignId:
              state.uri.queryParameters['campaign_id'] ?? 'firebase_campaign',
          restaurantId: state.uri.queryParameters['restaurant_id'],
          title: state.uri.queryParameters['title'],
          body: state.uri.queryParameters['body'],
          source: state.uri.queryParameters['source'],
        ),
      ),
      GoRoute(
        path: '/campaign/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final initialCampaign = state.extra is Map
              ? Map<String, dynamic>.from(state.extra as Map)
              : null;
          return CampaignDetailPage(
            campaignId: id,
            initialCampaign: initialCampaign,
          );
        },
      ),
      GoRoute(
        path: '/client-dashboard',
        builder: (context, state) => const ClientDashboard(),
      ),
      GoRoute(
        path: '/central-access',
        builder: (context, state) => const CentralAccessPage(),
      ),
      GoRoute(
        path: '/admin-dashboard',
        builder: (context, state) => const AdminDashboard(),
      ),
      GoRoute(
        path: '/admin/social-moderation',
        builder: (context, state) => const SocialModerationPage(),
      ),
      GoRoute(
        path: '/field-dashboard',
        builder: (context, state) => const FieldDashboard(),
      ),
      GoRoute(
        path: '/marketing-dashboard',
        builder: (context, state) => const MarketingDashboard(),
      ),
      GoRoute(
        path: '/restaurant-marketing',
        builder: (context, state) => const RestaurantMarketingPage(),
      ),
      GoRoute(
        path: '/restaurant-dashboard',
        builder: (context, state) => RestaurantDashboard(
          initialTab: state.uri.queryParameters['tab'],
          initialOrderId: state.uri.queryParameters['orderId'],
        ),
      ),
      GoRoute(
        path: '/restaurant-dashboard/qr',
        builder: (context, state) {
          final data = state.extra as Map<String, dynamic>? ?? const {};
          return RestaurantQrPage(
            restaurantId: data['restaurantId']?.toString() ?? '',
            restaurantName: data['restaurantName']?.toString() ?? 'Restaurante',
            imageUrl: data['imageUrl']?.toString() ?? '',
            dishes: (data['dishes'] as List<MenuItem>?) ?? const [],
          );
        },
      ),
      GoRoute(
        path: '/courier-dashboard',
        builder: (context, state) => const CourierDashboardEnhanced(),
      ),
      GoRoute(
        path: '/restaurant-profile/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return RestaurantPublicPage(
            restaurantId: id,
            orderId: state.uri.queryParameters['orderId'],
          );
        },
      ),
      GoRoute(
        path: '/restaurant/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return RestaurantDetailPage(
            restaurantId: id,
            highlightDishId: state.uri.queryParameters['dish'],
          );
        },
      ),
      GoRoute(
        path: '/courier/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return CourierPublicPage(
            courierId: id,
            orderId: state.uri.queryParameters['orderId'],
          );
        },
      ),
      GoRoute(
        path: '/review/:type/:id',
        builder: (context, state) => ReviewThreadPage(
          reviewType: state.pathParameters['type']!,
          reviewId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(path: '/cart', builder: (context, state) => const CartPage()),
      GoRoute(
        path: '/order/:orderId',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          return OrderDetailsPage(orderId: orderId);
        },
      ),
      GoRoute(
        path: '/tracking/:orderId',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          final viewerRole =
              state.uri.queryParameters['viewer']?.trim().isNotEmpty == true
              ? state.uri.queryParameters['viewer']!.trim()
              : 'client';
          return ChangeNotifierProvider(
            create: (_) => TrackingProvider(),
            child: TrackingMapPage(orderId: orderId, viewerRole: viewerRole),
          );
        },
      ),
      GoRoute(
        path: '/chat/:orderId',
        builder: (context, state) {
          final orderId = state.pathParameters['orderId']!;
          final viewerRole = state.uri.queryParameters['viewer'];
          return ChangeNotifierProvider(
            create: (_) => ChatProvider(),
            child: ChatPage(orderId: orderId, viewerRole: viewerRole),
          );
        },
      ),
      GoRoute(
        path: '/wallet',
        builder: (context, state) => WalletPage(
          initialSection: state.uri.queryParameters['section'],
          initialDepositId: state.uri.queryParameters['deposit_id'],
        ),
      ),
      GoRoute(
        path: '/operational-finance/:beneficiaryType',
        builder: (context, state) => DeligoOperationalFinancePage(
          beneficiaryType: state.pathParameters['beneficiaryType']!,
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) =>
            ProfilePage(initialSection: state.uri.queryParameters['section']),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/support-ticket/:ticketId',
        builder: (context, state) {
          final role = _currentRole();
          return SupportChatPage(
            title: 'Suporte DeliGo',
            role: role,
            ticketId: state.pathParameters['ticketId'],
          );
        },
      ),
      GoRoute(
        path: '/support/:role',
        builder: (context, state) {
          final role = state.pathParameters['role'] ?? _currentRole();
          return SupportChatPage(title: 'Suporte DeliGo', role: role);
        },
      ),
      GoRoute(
        path: '/support',
        builder: (context, state) {
          final role = _currentRole();
          return SupportChatPage(title: 'Suporte DeliGo', role: role);
        },
      ),
    ],
  );

  static String _currentRole() {
    final user = Supabase.instance.client.auth.currentUser;
    final meta = user?.userMetadata ?? const {};
    final appMeta = user?.appMetadata ?? const {};
    final role = meta['role'] ?? appMeta['role'] ?? 'client';
    return role.toString();
  }

  static String destinationForRole(
    String role, {
    String? kycStatus,
    bool emailConfirmed = true,
    bool phoneVerificationRequired = false,
  }) {
    if (phoneVerificationRequired) {
      return '/phone-otp';
    }
    if (role == 'restaurant' || role == 'courier') {
      if (kycStatus != 'approved') {
        return '/kyc-pending';
      }
    }
    return dashboardForRole(role);
  }

  static Future<Map<String, dynamic>?> _getProfile(String userId) async {
    final now = DateTime.now();
    final cached = _profileCache[userId];
    final cachedAt = _profileCacheAt[userId];
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _profileTtl) {
      return cached;
    }
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('role, kyc_status, is_blocked, block_reason, settings')
          .eq('id', userId)
          .maybeSingle();
      if (response != null) {
        final data = Map<String, dynamic>.from(response);
        _profileCache[userId] = data;
        _profileCacheAt[userId] = now;
        return data;
      }
    } catch (error) {
      debugPrint('AppRouter.getProfile error for $userId: $error');
    }
    return null;
  }

  static String dashboardForRole(String role) {
    switch (role) {
      case 'admin':
        return '/central-access';
      case 'field_agent':
      case 'support_agent':
      case 'ambassador':
        return '/field-dashboard';
      case 'marketing_agent':
        return '/marketing-dashboard';
      case 'restaurant':
        return '/restaurant-dashboard';
      case 'courier':
        return '/courier-dashboard';
      case 'client':
      default:
        return '/client-dashboard';
    }
  }

  static bool _isFieldBuildRole(String role) {
    return role == 'admin' ||
        role == 'field_agent' ||
        role == 'support_agent' ||
        role == 'ambassador';
  }

  static bool _isMarketingBuildRole(String role) {
    return role == 'admin' || role == 'marketing_agent';
  }

  static bool _isStaffOnlyRole(String role) {
    return role == 'field_agent' ||
        role == 'support_agent' ||
        role == 'ambassador' ||
        role == 'marketing_agent';
  }

  static bool isRouteAllowedForRole(String location, String role) {
    final commonPrefixes = ['/phone-otp'];
    if (_matchesAnyPrefix(location, commonPrefixes)) {
      return true;
    }

    switch (role) {
      case 'admin':
        return _matchesAnyPrefix(location, [
          '/central-access',
          '/admin/social-moderation',
        ]);
      case 'field_agent':
      case 'ambassador':
        return _matchesAnyPrefix(location, [
          '/field-dashboard',
          '/profile',
          '/settings',
          '/kyc-pending',
        ]);
      case 'support_agent':
        return _matchesAnyPrefix(location, [
          '/field-dashboard',
          '/support-ticket/',
          '/support/',
          '/support',
          '/order/',
          '/kyc-pending',
        ]);
      case 'marketing_agent':
        return _matchesAnyPrefix(location, [
          '/marketing-dashboard',
          '/profile',
          '/settings',
        ]);
      case 'restaurant':
        return _matchesAnyPrefix(location, [
          '/restaurant-dashboard',
          '/restaurant-marketing',
          '/chat/',
          '/profile',
          '/wallet',
          '/order/',
          '/tracking/',
          '/settings',
          '/support/',
          '/support',
          '/kyc-pending',
          '/review/',
        ]);
      case 'courier':
        return _matchesAnyPrefix(location, [
          '/courier-dashboard',
          '/chat/',
          '/profile',
          '/wallet',
          '/order/',
          '/settings',
          '/support/',
          '/support',
          '/tracking/',
          '/kyc-pending',
        ]);
      case 'client':
      default:
        return _matchesAnyPrefix(location, [
          '/client-dashboard',
          '/campaign/',
          '/restaurant/',
          '/chat/',
          '/profile',
          '/wallet',
          '/order/',
          '/settings',
          '/support/',
          '/support',
          '/cart',
          '/tracking/',
          '/review/',
        ]);
    }
  }

  static bool _matchesAnyPrefix(String location, List<String> prefixes) {
    for (final prefix in prefixes) {
      if (location == prefix || location.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  static bool _requiresAuth(String location) => !_isPublicRoute(location);

  static bool _isPublicRoute(String location) {
    if (_publicRoutes.contains(location)) return true;
    return location.startsWith('/invite/') ||
        location == '/deligo-ai' ||
        location.startsWith('/restaurant/') ||
        location.startsWith('/courier/');
  }

  static bool _isMarketingRoute(String location) {
    return location == '/' ||
        location == '/delivery-maputo' ||
        location == '/restaurantes-em-maputo' ||
        location == '/cadastro-restaurante' ||
        location == '/estafetas';
  }

  static Future<Map<String, dynamic>?> getProfile(String userId) {
    return _getProfile(userId);
  }

  static void primeProfileCache(String userId, Map<String, dynamic> profile) {
    _profileCache[userId] = Map<String, dynamic>.from(profile);
    _profileCacheAt[userId] = DateTime.now();
  }

  static void invalidateProfileCache(String userId) {
    _profileCache.remove(userId);
    _profileCacheAt.remove(userId);
  }

  static bool requiresPhoneVerification({
    required User? user,
    Map<String, dynamic>? profile,
  }) {
    final settings =
        (profile?['settings'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final required = settings['phone_verification_required'] == true;
    final verifiedAt = settings['phone_verified_at']?.toString().trim();
    final alreadyVerified =
        user?.phoneConfirmedAt != null ||
        (verifiedAt != null && verifiedAt.isNotEmpty);
    return required && !alreadyVerified;
  }
}
