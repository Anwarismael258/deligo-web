import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_env.dart';
import '../shared/models/restaurant.dart';

class RestaurantShareInvite {
  final String shareId;
  final String shareToken;
  final String inviterName;
  final String referralCode;
  final String magicLink;
  final String landingTitle;
  final String landingSubtitle;
  final String friendBenefit;
  final String inviterBenefit;
  final String message;
  final String marketingCopy;

  const RestaurantShareInvite({
    required this.shareId,
    required this.shareToken,
    required this.inviterName,
    required this.referralCode,
    required this.magicLink,
    required this.landingTitle,
    required this.landingSubtitle,
    required this.friendBenefit,
    required this.inviterBenefit,
    required this.message,
    required this.marketingCopy,
  });
}

class RestaurantShareService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _pendingInvitePrefsKey = 'pending_restaurant_invite_v1';
  static const double refereeDiscountPercent = 10;
  static const double refereeDiscountCapMzn = 100;
  static const double referrerBonusPercent = 3;
  static const double referrerBonusCapMzn = 50;
  static const double minimumEligibleOrderMzn = 300;

  bool get hasWebShareBaseUrl {
    final configuredBaseUrl = AppEnv.deligoShareBaseUrl.isNotEmpty
        ? AppEnv.deligoShareBaseUrl
        : AppEnv.appShareBaseUrl;
    return configuredBaseUrl.isNotEmpty;
  }

  String _buildMagicLink({
    required String shareToken,
    required String restaurantId,
    required String referralCode,
  }) {
    final configuredBaseUrl = hasWebShareBaseUrl
        ? (AppEnv.deligoShareBaseUrl.isNotEmpty
              ? AppEnv.deligoShareBaseUrl
              : AppEnv.appShareBaseUrl)
        : '';
    final query = 'restaurant_id=$restaurantId&ref=$referralCode';

    if (configuredBaseUrl.isNotEmpty) {
      final normalizedBase = configuredBaseUrl.endsWith('/')
          ? configuredBaseUrl.substring(0, configuredBaseUrl.length - 1)
          : configuredBaseUrl;
      return '$normalizedBase/invite/$shareToken?$query';
    }

    return 'deligo://invite/open?share_token=$shareToken&$query';
  }

  Future<RestaurantShareInvite> createInvite({
    required Restaurant restaurant,
    required String source,
    String? channel,
    String? topDishName,
  }) async {
    final user = _supabase.auth.currentUser;
    final inviterName = await _resolveInviterName(user?.id, user?.email);
    final shareToken = _buildShareToken(restaurant.id, user?.id);
    final referralCode = _buildReferralCode(inviterName, user?.id);

    final inserted = await _supabase
        .from('restaurant_shares')
        .insert({
          'restaurant_id': restaurant.id,
          'referrer_user_id': user?.id,
          'share_token': shareToken,
          'referral_code': referralCode,
          'source': source,
          'channel': channel,
          'status': 'active',
          'metadata': {
            'restaurant_name': restaurant.name,
            'restaurant_image_url': restaurant.imageUrl,
            'restaurant_address': restaurant.address,
            'estimated_delivery_time': restaurant.deliveryTime,
            'inviter_name': inviterName,
            'top_dish_name': topDishName,
          },
        })
        .select('id')
        .single();

    final invite = _buildInviteFromData(
      shareId: inserted['id'].toString(),
      shareToken: shareToken,
      inviterName: inviterName,
      referralCode: referralCode,
      restaurant: restaurant,
      topDishName: topDishName,
    );

    await recordEvent(
      shareId: invite.shareId,
      eventType: 'share_created',
      metadata: {'source': source, 'channel': channel},
    );

    return invite;
  }

  Future<void> recordEvent({
    required String shareId,
    required String eventType,
    String? sessionToken,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      await _supabase.from('restaurant_share_events').insert({
        'share_id': shareId,
        'event_type': eventType,
        'actor_user_id': user?.id,
        'session_token': sessionToken,
        'metadata': metadata ?? <String, dynamic>{},
      });
    } catch (e) {
      debugPrint('Erro ao registrar evento de share: $e');
    }
  }

  Future<Map<String, dynamic>?> getLandingDataByToken(String shareToken) async {
    try {
      final response = await _supabase
          .from('restaurant_shares')
          .select(
            'id, share_token, referral_code, metadata, restaurant:restaurants(id, owner_id, name, description, phone, address, latitude, longitude, neighborhood, city, is_open, created_at, image_url)',
          )
          .eq('share_token', shareToken)
          .eq('status', 'active')
          .maybeSingle();
      if (response == null) return null;

      final restaurantMap = Map<String, dynamic>.from(
        response['restaurant'] as Map,
      );
      final metadata = Map<String, dynamic>.from(
        (response['metadata'] as Map?) ?? {},
      );
      final restaurant = Restaurant.fromMap({
        ...restaurantMap,
        'image_url': restaurantMap['image_url'],
      });

      return {
        'share_id': response['id']?.toString() ?? '',
        'share_token': response['share_token']?.toString() ?? '',
        'referral_code': response['referral_code']?.toString() ?? '',
        'metadata': metadata,
        'restaurant': restaurant,
      };
    } catch (e) {
      debugPrint('Erro ao carregar landing do share: $e');
      return null;
    }
  }

  Future<void> bindInviteToCurrentUser({
    required String shareToken,
    required String restaurantId,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final share = await _supabase
        .from('restaurant_shares')
        .select('id, share_token, referral_code, referrer_user_id')
        .eq('share_token', shareToken)
        .eq('status', 'active')
        .maybeSingle();
    if (share == null) return;

    final referrerUserId = share['referrer_user_id']?.toString();
    if (referrerUserId != null && referrerUserId == user.id) return;

    final profile = await _supabase
        .from('profiles')
        .select('settings')
        .eq('id', user.id)
        .maybeSingle();
    final settings = Map<String, dynamic>.from(
      (profile?['settings'] as Map?) ?? {},
    );
    settings['pending_referral'] = {
      'share_id': share['id']?.toString(),
      'share_token': share['share_token']?.toString(),
      'referral_code': share['referral_code']?.toString(),
      'restaurant_id': restaurantId,
      'bound_at': DateTime.now().toIso8601String(),
      'discount_percent': refereeDiscountPercent,
      'discount_cap_mzn': refereeDiscountCapMzn,
      'bonus_percent': referrerBonusPercent,
      'bonus_cap_mzn': referrerBonusCapMzn,
      'minimum_order_amount': minimumEligibleOrderMzn,
    };
    await _supabase
        .from('profiles')
        .update({'settings': settings})
        .eq('id', user.id);

    final shareId = share['id']?.toString() ?? '';
    if (shareId.isNotEmpty) {
      await recordEvent(
        shareId: shareId,
        eventType: 'invite_bound_to_user',
        metadata: {'restaurant_id': restaurantId},
      );
    }

    await clearPendingInviteLocally();
  }

  Future<void> attachPendingReferralToOrder({
    required String orderId,
    required String restaurantId,
    required double orderTotalAmount,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final profile = await _supabase
        .from('profiles')
        .select('settings')
        .eq('id', user.id)
        .maybeSingle();
    final settings = Map<String, dynamic>.from(
      (profile?['settings'] as Map?) ?? {},
    );
    final pending = Map<String, dynamic>.from(
      (settings['pending_referral'] as Map?) ?? {},
    );
    if (pending.isEmpty) return;
    if (pending['restaurant_id']?.toString() != restaurantId) return;

    final minimumOrder =
        (pending['minimum_order_amount'] as num?)?.toDouble() ??
        minimumEligibleOrderMzn;
    if (orderTotalAmount < minimumOrder) return;

    final previousOrders = await _supabase
        .from('orders')
        .select('id')
        .or('client_id.eq.${user.id},customer_id.eq.${user.id}')
        .neq('id', orderId)
        .inFilter('status', [
          'paid',
          'accepted',
          'preparing',
          'ready',
          'courier_assigned',
          'in_transit',
          'arrived',
          'delivered',
          'completed',
        ])
        .limit(1);

    if ((previousOrders as List).isNotEmpty) {
      settings.remove('pending_referral');
      await _supabase
          .from('profiles')
          .update({'settings': settings})
          .eq('id', user.id);
      return;
    }

    final shareId = pending['share_id']?.toString() ?? '';
    if (shareId.isEmpty) return;

    final share = await _supabase
        .from('restaurant_shares')
        .select('referrer_user_id')
        .eq('id', shareId)
        .maybeSingle();
    final referrerUserId = share?['referrer_user_id']?.toString();
    if (referrerUserId == null || referrerUserId.isEmpty) return;

    await _supabase.from('restaurant_referral_rewards').insert({
      'share_id': shareId,
      'order_id': orderId,
      'referrer_user_id': referrerUserId,
      'referee_user_id': user.id,
      'referrer_reward_type': 'wallet_bonus_percent',
      'referrer_reward_value': referrerBonusPercent,
      'referrer_reward_cap': referrerBonusCapMzn,
      'referee_reward_type': 'first_order_discount_percent',
      'referee_reward_value': refereeDiscountPercent,
      'referee_reward_cap': refereeDiscountCapMzn,
      'minimum_order_amount': minimumEligibleOrderMzn,
      'status': 'pending',
      'metadata': {
        'order_total_amount': orderTotalAmount,
        'restaurant_id': restaurantId,
        'share_token': pending['share_token'],
        'referral_code': pending['referral_code'],
      },
    });

    settings.remove('pending_referral');
    await _supabase
        .from('profiles')
        .update({'settings': settings})
        .eq('id', user.id);

    await recordEvent(
      shareId: shareId,
      eventType: 'referral_attached_to_order',
      metadata: {
        'order_id': orderId,
        'restaurant_id': restaurantId,
        'order_total_amount': orderTotalAmount,
      },
    );
  }

  Future<Map<String, dynamic>> getRestaurantShareStats(
    String restaurantId,
  ) async {
    try {
      final row = await _supabase
          .from('restaurant_share_stats')
          .select()
          .eq('restaurant_id', restaurantId)
          .maybeSingle();
      return Map<String, dynamic>.from(row ?? <String, dynamic>{});
    } catch (e) {
      debugPrint('Erro ao buscar share stats do restaurante: $e');
      return <String, dynamic>{};
    }
  }

  Future<Map<String, Map<String, dynamic>>> getShareStatsForRestaurants(
    List<String> restaurantIds,
  ) async {
    if (restaurantIds.isEmpty) return <String, Map<String, dynamic>>{};
    try {
      final response = await _supabase
          .from('restaurant_share_stats')
          .select()
          .inFilter('restaurant_id', restaurantIds);
      final rows = (response as List).cast<Map<String, dynamic>>();
      return {for (final row in rows) row['restaurant_id'].toString(): row};
    } catch (e) {
      debugPrint('Erro ao buscar share stats em lote: $e');
      return <String, Map<String, dynamic>>{};
    }
  }

  Future<List<Map<String, dynamic>>> getTopSharedRestaurants({
    int limit = 5,
  }) async {
    try {
      final response = await _supabase
          .from('restaurant_share_stats')
          .select('restaurant_id, total_shares, channel_opens, last_share_at')
          .order('total_shares', ascending: false)
          .limit(limit);
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Erro ao buscar ranking de shares: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> stashPendingInviteLocally({
    required String shareToken,
    required String restaurantId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pendingInvitePrefsKey, [
        shareToken,
        restaurantId,
      ]);
    } catch (e) {
      debugPrint('Erro ao guardar convite pendente localmente: $e');
    }
  }

  Future<void> clearPendingInviteLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingInvitePrefsKey);
    } catch (e) {
      debugPrint('Erro ao limpar convite pendente local: $e');
    }
  }

  Future<bool> hydratePendingInviteForCurrentUser() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(_pendingInvitePrefsKey);
      if (pending == null || pending.length < 2) return false;

      final shareToken = pending[0].trim();
      final restaurantId = pending[1].trim();
      if (shareToken.isEmpty || restaurantId.isEmpty) {
        await prefs.remove(_pendingInvitePrefsKey);
        return false;
      }

      await bindInviteToCurrentUser(
        shareToken: shareToken,
        restaurantId: restaurantId,
      );
      return true;
    } catch (e) {
      debugPrint('Erro ao hidratar convite pendente: $e');
      return false;
    }
  }

  RestaurantShareInvite buildPreviewInvite({
    required Restaurant restaurant,
    String? topDishName,
  }) {
    final user = _supabase.auth.currentUser;
    final inviterName = _fallbackInviterName(user?.email);
    final shareToken = _buildShareToken(restaurant.id, user?.id);
    final referralCode = _buildReferralCode(inviterName, user?.id);

    return _buildInviteFromData(
      shareId: 'preview-${restaurant.id}',
      shareToken: shareToken,
      inviterName: inviterName,
      referralCode: referralCode,
      restaurant: restaurant,
      topDishName: topDishName,
    );
  }

  RestaurantShareInvite _buildInviteFromData({
    required String shareId,
    required String shareToken,
    required String inviterName,
    required String referralCode,
    required Restaurant restaurant,
    String? topDishName,
  }) {
    final magicLink = _buildMagicLink(
      shareToken: shareToken,
      restaurantId: restaurant.id,
      referralCode: referralCode,
    );
    final dishName = (topDishName ?? '').trim().isNotEmpty
        ? topDishName!.trim()
        : 'o prato mais pedido';
    const friendBenefit = '10% OFF na primeira compra (max. 100 MZN)';
    const inviterBenefit = '3% de bonus na wallet (max. 50 MZN)';

    return RestaurantShareInvite(
      shareId: shareId,
      shareToken: shareToken,
      inviterName: inviterName,
      referralCode: referralCode,
      magicLink: magicLink,
      landingTitle: 'Voce foi convidado para comer no ${restaurant.name}',
      landingSubtitle:
          'Veja $dishName e outros pratos no DeliGo. Entrega estimada em ${restaurant.deliveryTime ?? 25} min.',
      friendBenefit: friendBenefit,
      inviterBenefit: inviterBenefit,
      message:
          'Olha o ${restaurant.name} no DeliGo 🍽️\n'
          '$dishName e muito mais. Abre aqui 👇\n'
          '$magicLink',
      marketingCopy:
          'Hoje tem destaque no ${restaurant.name}.\n'
          'Experimente $dishName.\n'
          'Abre aqui: $magicLink',
    );
  }

  Future<String> _resolveInviterName(String? userId, String? email) async {
    final fallback = _fallbackInviterName(email);
    if (userId == null || userId.isEmpty) return fallback;

    try {
      final profile = await _supabase
          .from('profiles')
          .select('full_name, username')
          .eq('id', userId)
          .maybeSingle();
      final candidates = [
        profile?['full_name']?.toString(),
        profile?['username']?.toString(),
        email,
      ];
      for (final candidate in candidates) {
        final normalized = _normalizeInviteName(candidate);
        if (normalized != null) return normalized;
      }
      return fallback;
    } catch (e) {
      debugPrint(
        'RestaurantShareService: erro ao resolver nome do convidante userId=$userId email=$email: $e',
      );
      return fallback;
    }
  }

  String _fallbackInviterName(String? email) {
    return _normalizeInviteName(email) ?? 'um cliente DeliGo';
  }

  String? _normalizeInviteName(String? rawValue) {
    final raw = (rawValue ?? '').trim();
    if (raw.isEmpty) return null;
    final cleaned = raw.contains('@')
        ? raw.split('@').first.replaceAll('.', ' ').replaceAll('_', ' ')
        : raw;
    final normalized = cleaned.trim();
    if (normalized.isEmpty) return null;
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String _buildReferralCode(String inviterName, String? userId) {
    final cleanName = inviterName
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    final prefix = cleanName.isEmpty ? 'DELIGO' : cleanName;
    final suffix = (userId ?? '000000')
        .replaceAll('-', '')
        .toUpperCase()
        .padRight(6, '0')
        .substring(0, 6);
    final prefixLength = prefix.length > 6 ? 6 : prefix.length;
    return '${prefix.substring(0, prefixLength)}$suffix';
  }

  String _buildShareToken(String restaurantId, String? userId) {
    final restaurantPart = restaurantId
        .replaceAll('-', '')
        .padRight(6, '0')
        .substring(0, 6);
    final userPart = (userId ?? 'guest')
        .replaceAll('-', '')
        .padRight(6, '0')
        .substring(0, 6);
    final timePart = DateTime.now().millisecondsSinceEpoch.toString().substring(
      6,
      13,
    );
    return 'sh$restaurantPart$userPart$timePart'.toLowerCase();
  }
}
