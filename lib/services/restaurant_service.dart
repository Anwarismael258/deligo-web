import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'server_clock_service.dart';
import '../shared/models/menu_item_review.dart';
import '../shared/models/restaurant.dart';
import '../shared/models/menu_item.dart';

class RestaurantService {
  String? lastAssetUploadError;
  String? lastMenuItemError;
  String? lastCatalogError;

  final SupabaseClient _supabase = Supabase.instance.client;
  static const int _inFilterChunkSize = 100;

  Future<List<Restaurant>> _filterVisibleRestaurants(
    List<Restaurant> restaurants,
  ) async {
    // A restaurant is a catalog entity, not a menu item. Keep every open
    // restaurant returned by the canonical public RPC visible even when its
    // menu is temporarily empty or all items are out of stock. Menu
    // availability is enforced by the menu/cart flow; hiding the whole
    // restaurant here made legitimate restaurants (including test venues)
    // disappear from Home and Explorer.
    return restaurants.where((restaurant) => restaurant.isOpen).toList();
  }

  bool _isComboActiveNow(Map<String, dynamic> combo) {
    final isActive = combo['is_active'] != false;
    if (!isActive) return false;
    final now = ServerClockService.instance.now().toLocal();
    final start = DateTime.tryParse(combo['start_date']?.toString() ?? '');
    final end = DateTime.tryParse(combo['end_date']?.toString() ?? '');
    if (start != null && now.isBefore(start)) return false;
    if (end != null && now.isAfter(end)) return false;
    return true;
  }

  String _resolveProfileDisplayName(
    Map<String, dynamic>? profile, {
    String fallback = 'Cliente',
    String? emailFallback,
  }) {
    final candidates = [
      profile?['display_name'],
      profile?['full_name'],
      profile?['username'],
      profile?['first_name'],
      profile?['name'],
      emailFallback != null && emailFallback.contains('@')
          ? emailFallback.split('@').first
          : null,
      fallback,
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = _supabase.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      return const {};
    }
    return {'Authorization': 'Bearer $token'};
  }

  Iterable<List<T>> _chunked<T>(List<T> values, int size) sync* {
    if (values.isEmpty) return;
    for (var index = 0; index < values.length; index += size) {
      final end = (index + size > values.length) ? values.length : index + size;
      yield values.sublist(index, end);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPaymentSplitsForOrderIds(
    List<String> orderIds,
  ) async {
    if (orderIds.isEmpty) return const [];
    final rows = <Map<String, dynamic>>[];
    for (final chunk in _chunked(orderIds, _inFilterChunkSize)) {
      final response = await _supabase
          .from('payment_splits')
          .select('order_id, restaurant_amount, created_at')
          .inFilter('order_id', chunk)
          .order('created_at', ascending: false);
      rows.addAll((response as List).cast<Map<String, dynamic>>());
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> _fetchOrderItemsForOrderIds(
    List<String> orderIds,
  ) async {
    if (orderIds.isEmpty) return const [];
    final rows = <Map<String, dynamic>>[];
    for (final chunk in _chunked(orderIds, _inFilterChunkSize)) {
      final response = await _supabase
          .from('order_items')
          .select('order_id, menu_item_id, quantity, menu_items(name)')
          .inFilter('order_id', chunk);
      rows.addAll((response as List).cast<Map<String, dynamic>>());
    }
    return rows;
  }

  Future<double> _sumDeliveredRevenueForRange(
    String restaurantId, {
    required DateTime start,
    DateTime? end,
  }) async {
    var query = _supabase
        .from('orders')
        .select('total_amount')
        .eq('restaurant_id', restaurantId)
        .eq('status', 'delivered')
        .gte('created_at', start.toIso8601String());

    if (end != null) {
      query = query.lt('created_at', end.toIso8601String());
    }

    final response = await query;
    return (response as List).fold<double>(
      0.0,
      (sum, order) =>
          sum + ((order['total_amount'] as num?)?.toDouble() ?? 0.0),
    );
  }

  /// Buscar todos os restaurantes disponÃ­veis
  Future<List<Restaurant>> getRestaurants({
    String? category,
    double? userLatitude,
    double? userLongitude,
    double? temperatureC,
    String? searchQuery,
    String? sortBy, // 'rating', 'distance', 'delivery_fee', 'time'
    String? neighborhood,
    String? city,
    int? limit,
    int? offset,
  }) async {
    try {
      final usesComputedSorting =
          sortBy == 'distance' || sortBy == 'delivery_fee' || sortBy == 'time';
      final response = await _supabase.rpc(
        'get_public_restaurants',
        params: {
          'p_search': searchQuery,
          'p_category': category,
          'p_neighborhood': neighborhood,
          'p_city': city,
          'p_sort_by': usesComputedSorting ? 'rating' : (sortBy ?? 'rating'),
          // Computed sorting is performed locally after distance/fee/time are
          // calculated. Fetch the current page window without exposing the
          // restaurants table directly to the client.
          'p_limit': usesComputedSorting ? 100 : (limit ?? 100),
          'p_offset': usesComputedSorting ? 0 : (offset ?? 0),
        },
      );

      List<Restaurant> restaurants = (response as List)
          .map(
            (data) => _parseRestaurantWithDistance(
              data,
              userLatitude,
              userLongitude,
              temperatureC: temperatureC,
            ),
          )
          .toList();

      restaurants = await _filterVisibleRestaurants(restaurants);

      // Ordenação
      if (sortBy != null) {
        switch (sortBy) {
          case 'rating':
            restaurants.sort(
              (a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0),
            );
            break;
          case 'distance':
            restaurants.sort(
              (a, b) => (a.distance ?? 999).compareTo(b.distance ?? 999),
            );
            break;
          case 'delivery_fee':
            restaurants.sort(
              (a, b) => (a.deliveryFee ?? 999).compareTo(b.deliveryFee ?? 999),
            );
            break;
          case 'time':
            restaurants.sort(
              (a, b) =>
                  (a.deliveryTime ?? 999).compareTo(b.deliveryTime ?? 999),
            );
            break;
        }
      }

      if (usesComputedSorting && offset != null && offset > 0) {
        if (offset < restaurants.length) {
          restaurants = restaurants.skip(offset).toList();
        } else {
          restaurants = [];
        }
      }

      if (usesComputedSorting && limit != null && restaurants.length > limit) {
        restaurants = restaurants.take(limit).toList();
      }

      return restaurants;
    } catch (e) {
      debugPrint('Erro ao buscar restaurantes: $e');
      rethrow;
    }
  }

  /// Buscar restaurante por ID
  Future<Restaurant?> getRestaurantById(String id) async {
    try {
      final response = await _supabase.rpc(
        'get_public_restaurants',
        params: {
          'p_restaurant_ids': [id],
          'p_sort_by': 'rating',
          'p_limit': 1,
          'p_offset': 0,
        },
      );
      final rows = (response as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return null;
      return _parseRestaurantWithDistance(rows.first, null, null);
    } catch (e) {
      debugPrint('Erro ao buscar restaurante: $e');
      rethrow;
    }
  }

  /// Leitura mínima anónima para links, QR e páginas públicas.
  /// Não inclui coordenadas nem campos operacionais privados.
  Future<Restaurant?> getPublicRestaurantById(String id) async {
    try {
      final response = await _supabase.rpc(
        'get_public_restaurant',
        params: {'p_restaurant_id': id},
      );
      final rows = (response as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return null;
      return _parseRestaurantWithDistance(rows.first, null, null);
    } catch (e) {
      debugPrint('Erro ao buscar restaurante público: $e');
      rethrow;
    }
  }

  /// Buscar cardÃ¡pio de um restaurante
  Future<List<MenuItem>> getMenuItems(
    String restaurantId, {
    String? category,
  }) async {
    try {
      var query = _supabase
          .from('menu_items')
          .select()
          .eq('restaurant_id', restaurantId);

      if (category != null && category.isNotEmpty) {
        query = query.eq('category', category);
      }

      final response = await query;

      return (response as List)
          .map((data) => MenuItem.fromMap(data))
          .where((item) => item.isAvailable && item.stockQuantity > 0)
          .toList();
    } catch (e) {
      debugPrint('Erro ao buscar cardÃ¡pio: $e');
      return [];
    }
  }

  Future<List<MenuItem>> getMenuItemsByIds(
    List<String> itemIds, {
    bool rethrowOnError = false,
  }) async {
    if (itemIds.isEmpty) return const [];
    try {
      final response = await _supabase
          .from('menu_items')
          .select()
          .inFilter('id', itemIds);
      return (response as List)
          .map((row) => MenuItem.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (error) {
      debugPrint('RestaurantService.getMenuItemsByIds error: $error');
      if (rethrowOnError) rethrow;
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> getMenuItemOptions(
    String menuItemId,
  ) async {
    try {
      final groups = await _supabase
          .from('menu_item_option_groups')
          .select('id, name, min_selections, max_selections, sort_order')
          .eq('menu_item_id', menuItemId)
          .eq('is_active', true)
          .order('sort_order');
      final groupRows = (groups as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (groupRows.isEmpty) return const [];
      final groupIds = groupRows.map((row) => row['id'].toString()).toList();
      final choices = await _supabase
          .from('menu_item_option_choices')
          .select('id, option_group_id, name, price_delta, sort_order')
          .inFilter('option_group_id', groupIds)
          .eq('is_available', true)
          .order('sort_order');
      final byGroup = <String, List<Map<String, dynamic>>>{};
      for (final raw in choices as List) {
        final choice = Map<String, dynamic>.from(raw as Map);
        byGroup
            .putIfAbsent(choice['option_group_id'].toString(), () => [])
            .add(choice);
      }
      return groupRows
          .map(
            (group) => {
              ...group,
              'choices': byGroup[group['id'].toString()] ?? const [],
            },
          )
          .toList();
    } catch (error) {
      debugPrint('RestaurantService.getMenuItemOptions error: $error');
      return const [];
    }
  }

  /// Buscar categorias de um restaurante
  Future<List<String>> getCategories(String restaurantId) async {
    try {
      final response = await _supabase
          .from('menu_items')
          .select('category')
          .eq('restaurant_id', restaurantId);

      final categories = (response as List)
          .map((data) => data['category'] as String?)
          .where((cat) => cat != null && cat.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();

      return categories;
    } catch (e) {
      debugPrint('Erro ao buscar categorias: $e');
      return [];
    }
  }

  /// Buscar restaurantes em destaque (com melhor avaliação)
  Future<List<Restaurant>> getFeaturedRestaurants({
    int limit = 5,
    double? temperatureC,
  }) async {
    final restaurants = await getRestaurants(
      sortBy: 'rating',
      temperatureC: temperatureC,
      limit: limit,
      offset: 0,
    );
    return restaurants.take(limit).toList();
  }

  /// Calcular distância e taxa de entrega
  ///
  /// Mantém a regra global:
  /// - mínimo 100 MZN
  /// - máximo 200 MZN
  ///
  /// A variação usa:
  /// - distância
  /// - zona operacional (bairros/cidades mais movimentados)
  /// - temperatura operacional (horários mais quentes e de pico)
  static int calculateDeliveryFee(
    double? distance, {
    String? neighborhood,
    String? city,
    double? temperatureC,
    DateTime? at,
  }) {
    final now = (at ?? ServerClockService.instance.now()).toLocal();
    final normalizedNeighborhood = (neighborhood ?? '').trim().toLowerCase();
    final normalizedCity = (city ?? '').trim().toLowerCase();

    int baseFee;
    if (distance == null) {
      baseFee = 150;
    } else if (distance <= 1) {
      baseFee = 100;
    } else if (distance <= 3) {
      baseFee = 140;
    } else if (distance <= 5) {
      baseFee = 170;
    } else {
      baseFee = 190;
    }

    int zoneBoost = 0;
    const premiumZones = {
      'coop',
      'sommerschield',
      'polana',
      'central',
      'baixa',
    };
    const mediumZones = {
      'malhangalene',
      'alto mae',
      'alto-mae',
      'triunfo',
      'mafalala',
    };

    if (premiumZones.contains(normalizedNeighborhood)) {
      zoneBoost = 10;
    } else if (mediumZones.contains(normalizedNeighborhood)) {
      zoneBoost = 5;
    } else if (normalizedCity == 'maputo') {
      zoneBoost = 5;
    }

    int temperatureBoost = 0;
    if (temperatureC != null) {
      if (temperatureC >= 33) {
        temperatureBoost += 10;
      } else if (temperatureC >= 28) {
        temperatureBoost += 5;
      }
    }

    final hour = now.hour;
    if (hour >= 11 && hour <= 15) {
      temperatureBoost += 10;
    } else if (hour >= 18 && hour <= 21) {
      temperatureBoost += 5;
    }

    final finalFee = baseFee + zoneBoost + temperatureBoost;
    return finalFee.clamp(100, 200);
  }

  Future<List<Restaurant>> getRestaurantsByIds(
    List<String> ids, {
    double? userLatitude,
    double? userLongitude,
    double? temperatureC,
  }) async {
    final normalizedIds = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedIds.isEmpty) return [];

    try {
      final response = await _supabase.rpc(
        'get_public_restaurants',
        params: {
          'p_restaurant_ids': normalizedIds,
          'p_sort_by': 'rating',
          'p_limit': normalizedIds.length,
          'p_offset': 0,
        },
      );

      var restaurants = (response as List)
          .map(
            (data) => _parseRestaurantWithDistance(
              data,
              userLatitude,
              userLongitude,
              temperatureC: temperatureC,
            ),
          )
          .toList();

      restaurants = await _filterVisibleRestaurants(restaurants);
      final byId = {
        for (final restaurant in restaurants) restaurant.id: restaurant,
      };
      return normalizedIds
          .where(byId.containsKey)
          .map((id) => byId[id]!)
          .toList();
    } catch (e) {
      debugPrint('Erro ao buscar restaurantes por ids: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getRestaurantDailyCombos(
    String restaurantId,
  ) async {
    try {
      final response = await _supabase
          .from('daily_combos')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('created_at', ascending: false);

      return (response as List)
          .cast<Map<String, dynamic>>()
          .map((row) => {...row, 'is_currently_active': _isComboActiveNow(row)})
          .toList();
    } catch (e) {
      debugPrint('Erro ao buscar combos do restaurante: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getActiveDailyCombo(String restaurantId) async {
    try {
      final response = await _supabase
          .from('daily_combos')
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      for (final row in (response as List).cast<Map<String, dynamic>>()) {
        if (_isComboActiveNow(row)) {
          return {...row, 'is_currently_active': true};
        }
      }
      return null;
    } catch (e) {
      debugPrint('Erro ao buscar combo ativo: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getActiveDailyCombosForHome({
    bool rethrowOnError = false,
  }) async {
    try {
      final response = await _supabase
          .from('daily_combos')
          .select('*, restaurants(id, name, image_url)')
          .eq('is_active', true)
          .order('created_at', ascending: false);

      return (response as List)
          .cast<Map<String, dynamic>>()
          .where(_isComboActiveNow)
          .toList();
    } catch (e) {
      debugPrint('Erro ao buscar combos ativos para home: $e');
      if (rethrowOnError) rethrow;
      return [];
    }
  }

  Future<bool> createDailyCombo({
    required String restaurantId,
    required String title,
    required String description,
    required double discountPercentage,
    required DateTime startDate,
    required DateTime endDate,
    bool isActive = true,
  }) async {
    lastCatalogError = null;
    try {
      final created = await _supabase
          .from('daily_combos')
          .insert({
            'restaurant_id': restaurantId,
            'title': title,
            'description': description,
            'discount_percentage': discountPercentage,
            'start_date': startDate.toIso8601String(),
            'end_date': endDate.toIso8601String(),
            'is_active': isActive,
          })
          .select('id')
          .maybeSingle();
      if (created == null) {
        throw StateError('A promoção não foi guardada.');
      }
      return true;
    } catch (e) {
      debugPrint('Erro ao criar combo do dia: $e');
      lastCatalogError =
          _readServiceError(e) ?? 'Não foi possível criar a promoção.';
      return _manageCatalogWithFallback(
        action: 'create_combo',
        restaurantId: restaurantId,
        payload: {
          'title': title,
          'description': description,
          'discount_percentage': discountPercentage,
          'start_date': startDate.toIso8601String(),
          'end_date': endDate.toIso8601String(),
          'is_active': isActive,
        },
      );
    }
  }

  Future<bool> updateDailyCombo({
    required String comboId,
    required String restaurantId,
    String? title,
    String? description,
    double? discountPercentage,
    DateTime? startDate,
    DateTime? endDate,
    bool? isActive,
  }) async {
    lastCatalogError = null;
    final updates = <String, dynamic>{};
    try {
      if (title != null) updates['title'] = title;
      if (description != null) updates['description'] = description;
      if (discountPercentage != null) {
        updates['discount_percentage'] = discountPercentage;
      }
      if (startDate != null) {
        updates['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) updates['end_date'] = endDate.toIso8601String();
      if (isActive != null) updates['is_active'] = isActive;

      final updated = await _supabase
          .from('daily_combos')
          .update(updates)
          .eq('id', comboId)
          .select('id')
          .maybeSingle();
      if (updated == null) {
        throw StateError(
          'A promoção não foi encontrada ou não pode ser editada.',
        );
      }
      return true;
    } catch (e) {
      debugPrint('Erro ao atualizar combo do dia: $e');
      lastCatalogError =
          _readServiceError(e) ?? 'Não foi possível atualizar a promoção.';
      return _manageCatalogWithFallback(
        action: 'update_combo',
        restaurantId: restaurantId,
        payload: {'combo_id': comboId, ...updates},
      );
    }
  }

  Future<bool> deleteDailyCombo(String comboId) async {
    try {
      await _supabase.from('daily_combos').delete().eq('id', comboId);
      return true;
    } catch (e) {
      debugPrint('Erro ao apagar combo do dia: $e');
      return false;
    }
  }

  /// Calcular tempo estimado de entrega
  static int calculateDeliveryTime(double? distance, {int? baseMinutes}) {
    final normalizedBase = (baseMinutes ?? 25).clamp(15, 120);
    if (distance == null) return normalizedBase;

    // Soma o tempo base configurado pelo restaurante com o deslocamento estimado.
    return (normalizedBase + (distance * 5).round()).clamp(15, 180);
  }

  /// Parse do restaurante com cálculo de distância
  Restaurant _parseRestaurantWithDistance(
    Map<String, dynamic> data,
    double? userLat,
    double? userLng, {
    double? temperatureC,
  }) {
    final restaurant = Restaurant.fromMap(data);

    double? distance;
    if (userLat != null &&
        userLng != null &&
        restaurant.latitude != null &&
        restaurant.longitude != null) {
      distance = _calculateDistance(
        userLat,
        userLng,
        restaurant.latitude!,
        restaurant.longitude!,
      );
    }

    return Restaurant(
      id: restaurant.id,
      ownerId: restaurant.ownerId,
      name: restaurant.name,
      description: restaurant.description,
      phone: restaurant.phone,
      address: restaurant.address,
      latitude: restaurant.latitude,
      longitude: restaurant.longitude,
      neighborhood: data['neighborhood'] as String?,
      city: data['city'] as String?,
      isOpen: restaurant.isOpen,
      createdAt: restaurant.createdAt,
      distance: distance,
      rating: data['rating'] as double?,
      deliveryFee: calculateDeliveryFee(
        distance,
        neighborhood: data['neighborhood'] as String?,
        city: data['city'] as String?,
        temperatureC: temperatureC,
      ),
      deliveryTime: calculateDeliveryTime(
        distance,
        baseMinutes: (data['estimated_delivery_time'] as num?)?.toInt(),
      ),
      imageUrl: data['image_url'] as String?,
      freeDelivery: restaurant.freeDelivery || data['free_delivery'] == true,
    );
  }

  /// Calcular distância entre dois pontos (fórmula de Haversine)
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371; // km

    double dLat = _toRadians(lat2 - lat1);
    double dLng = _toRadians(lng2 - lng1);

    double a =
        _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRadians(lat1)) *
            _cos(_toRadians(lat2)) *
            _sin(dLng / 2) *
            _sin(dLng / 2);

    double c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));

    return earthRadius * c;
  }

  double _toRadians(double degree) => degree * 3.141592653589793 / 180;
  double _sin(double x) => _taylorSin(x);
  double _cos(double x) => _taylorCos(x);
  double _sqrt(double x) => _newtonSqrt(x);
  double _atan2(double y, double x) => _approximateAtan2(y, x);

  double _taylorSin(double x) {
    // Normalizar x para [-pi, pi]
    while (x > 3.141592653589793) {
      x -= 2 * 3.141592653589793;
    }
    while (x < -3.141592653589793) {
      x += 2 * 3.141592653589793;
    }

    double result = x;
    double term = x;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i) * (2 * i + 1));
      result += term;
    }
    return result;
  }

  double _taylorCos(double x) {
    while (x > 3.141592653589793) {
      x -= 2 * 3.141592653589793;
    }
    while (x < -3.141592653589793) {
      x += 2 * 3.141592653589793;
    }

    double result = 1;
    double term = 1;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  double _newtonSqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 20; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  double _approximateAtan2(double y, double x) {
    if (x == 0) {
      if (y > 0) return 3.141592653589793 / 2;
      if (y < 0) return -3.141592653589793 / 2;
      return 0;
    }
    double atan = _approximateAtan(y / x);
    if (x < 0) {
      if (y >= 0) return atan + 3.141592653589793;
      return atan - 3.141592653589793;
    }
    return atan;
  }

  double _approximateAtan(double x) {
    // Aproximação para |x| <= 1
    if (x.abs() > 1) {
      return (3.141592653589793 / 2) * x.sign - _approximateAtan(1 / x);
    }
    double result = 0;
    double term = x;
    for (int i = 0; i < 20; i++) {
      result += term / (2 * i + 1) * (i % 2 == 0 ? 1 : -1);
      term *= x * x;
    }
    return result;
  }

  // ========== GERENCIAMENTO DE MENU ==========

  /// Adicionar novo item ao cardÃ¡pio
  Future<MenuItem?> addMenuItem({
    required String restaurantId,
    required String name,
    required double price,
    required int stockQuantity,
    required int prepTimeMinutes,
    String? description,
    String? category,
    String? imageUrl,
    List<String>? imageUrls,
  }) async {
    final normalizedStock = stockQuantity < 0 ? 0 : stockQuantity;
    final normalizedPrepTime = prepTimeMinutes <= 0 ? 25 : prepTimeMinutes;
    final isAvailable = normalizedStock > 0;
    lastMenuItemError = null;
    try {
      final response = await _supabase
          .from('menu_items')
          .insert({
            'restaurant_id': restaurantId,
            'name': name,
            'price': price,
            'description': description,
            'category': category ?? 'Geral',
            'image_url': imageUrl,
            'image_urls':
                imageUrls ?? (imageUrl == null ? <String>[] : [imageUrl]),
            'is_available': isAvailable,
            'stock_quantity': normalizedStock,
            'prep_time_minutes': normalizedPrepTime,
          })
          .select()
          .single();

      return MenuItem.fromMap(response);
    } catch (e) {
      debugPrint('Erro ao adicionar item diretamente: $e');
      lastMenuItemError =
          _readServiceError(e) ?? 'Não foi possível criar o prato.';

      try {
        final headers = await _authHeaders();
        final fallback = await _supabase.functions.invoke(
          'restaurant-menu-create',
          headers: headers,
          body: {
            'restaurant_id': restaurantId,
            'name': name,
            'price': price,
            'description': description,
            'category': category ?? 'Geral',
            'image_url': imageUrl,
            'stock_quantity': normalizedStock,
            'prep_time_minutes': normalizedPrepTime,
            'is_available': isAvailable,
          },
        );

        final data = fallback.data;
        if (fallback.status >= 200 && fallback.status < 300 && data != null) {
          final itemMap = data is Map<String, dynamic>
              ? (data['item'] as Map<String, dynamic>? ?? data)
              : null;
          if (itemMap != null) {
            lastMenuItemError = null;
            return MenuItem.fromMap(itemMap);
          }
        }

        debugPrint('Fallback edge function falhou: ${fallback.data}');
        final managed = await _supabase.functions.invoke(
          'restaurant-catalog-manage',
          headers: headers,
          body: {
            'action': 'create_menu_item',
            'restaurant_id': restaurantId,
            'name': name,
            'price': price,
            'description': description,
            'category': category ?? 'Geral',
            'image_url': imageUrl,
            'stock_quantity': normalizedStock,
            'prep_time_minutes': normalizedPrepTime,
            'is_available': isAvailable,
          },
        );
        final managedData = managed.data;
        if (managed.status >= 200 &&
            managed.status < 300 &&
            managedData is Map) {
          final itemMap = managedData['item'];
          if (itemMap is Map<String, dynamic>) {
            lastMenuItemError = null;
            return MenuItem.fromMap(itemMap);
          }
        }
        lastMenuItemError =
            _readServiceError(managedData) ??
            _readServiceError(fallback.data) ??
            'Não foi possível criar o prato. Confirme as permissões da conta do restaurante.';
        return null;
      } catch (fallbackError) {
        debugPrint('Erro no fallback restaurant-menu-create: $fallbackError');
        lastMenuItemError =
            _readServiceError(fallbackError) ??
            'Não foi possível criar o prato agora. Tente novamente.';
        return null;
      }
    }
  }

  String? _readServiceError(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) {
      final message = raw['error'] ?? raw['message'];
      final value = message?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }
    final value = raw.toString().trim();
    if (value.isEmpty || value == 'null') return null;
    final match = RegExp(
      r'(?:error|message)[:=]\\s*([^,}]+)',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1)?.trim() ?? value;
  }

  /// Atualizar item do cardÃ¡pio
  Future<bool> updateMenuItem({
    required String itemId,
    required String restaurantId,
    String? name,
    double? price,
    int? stockQuantity,
    int? prepTimeMinutes,
    String? description,
    String? category,
    String? imageUrl,
    List<String>? imageUrls,
    bool updateImage = false,
    bool? isAvailable,
  }) async {
    lastMenuItemError = null;
    final Map<String, dynamic> updates = {};
    try {
      if (name != null) updates['name'] = name;
      if (price != null) updates['price'] = price;
      if (stockQuantity != null) {
        final normalizedStock = stockQuantity < 0 ? 0 : stockQuantity;
        updates['stock_quantity'] = normalizedStock;
        updates['is_available'] = isAvailable ?? (normalizedStock > 0);
      } else if (isAvailable != null) {
        updates['is_available'] = isAvailable;
      }
      if (prepTimeMinutes != null) {
        updates['prep_time_minutes'] = prepTimeMinutes;
      }
      if (description != null) updates['description'] = description;
      if (category != null) updates['category'] = category;
      if (updateImage) {
        final normalizedImageUrl = imageUrl?.trim();
        updates['image_url'] =
            (normalizedImageUrl == null || normalizedImageUrl.isEmpty)
            ? null
            : normalizedImageUrl;
        updates['image_urls'] =
            imageUrls ??
            (normalizedImageUrl == null || normalizedImageUrl.isEmpty
                ? <String>[]
                : [normalizedImageUrl]);
      }

      final updated = await _supabase
          .from('menu_items')
          .update(updates)
          .eq('id', itemId)
          .select('id')
          .maybeSingle();
      if (updated == null) {
        throw StateError('O prato não foi encontrado ou não pode ser editado.');
      }

      return true;
    } catch (e) {
      debugPrint('Erro ao atualizar item: $e');
      lastMenuItemError =
          _readServiceError(e) ?? 'Não foi possível atualizar o prato.';
      return _manageCatalogWithFallback(
        action: 'update_menu_item',
        restaurantId: restaurantId,
        payload: {'item_id': itemId, ...updates},
        menuOperation: true,
      );
    }
  }

  Future<bool> _manageCatalogWithFallback({
    required String action,
    required String restaurantId,
    required Map<String, dynamic> payload,
    bool menuOperation = false,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'restaurant-catalog-manage',
        headers: await _authHeaders(),
        body: {'action': action, 'restaurant_id': restaurantId, ...payload},
      );
      final data = response.data;
      if (response.status >= 200 &&
          response.status < 300 &&
          data is Map &&
          data['success'] == true) {
        if (menuOperation) {
          lastMenuItemError = null;
        } else {
          lastCatalogError = null;
        }
        return true;
      }
      final message =
          _readServiceError(data) ?? 'Não foi possível concluir a alteração.';
      if (menuOperation) {
        lastMenuItemError = message;
      } else {
        lastCatalogError = message;
      }
      return false;
    } catch (error) {
      debugPrint('Fallback restaurant-catalog-manage falhou: $error');
      final message =
          _readServiceError(error) ??
          'Não foi possível concluir a alteração agora.';
      if (menuOperation) {
        lastMenuItemError = message;
      } else {
        lastCatalogError = message;
      }
      return false;
    }
  }

  /// Excluir item do cardÃ¡pio
  Future<bool> deleteMenuItem(
    String itemId, {
    required String restaurantId,
  }) async {
    lastMenuItemError = null;
    try {
      final deleted = await _supabase
          .from('menu_items')
          .delete()
          .eq('id', itemId)
          .select('id')
          .maybeSingle();
      if (deleted != null) return true;
      throw StateError('O prato não foi encontrado ou não pode ser removido.');
    } catch (e) {
      debugPrint('Erro ao excluir item: $e');
      return _manageCatalogWithFallback(
        action: 'delete_menu_item',
        restaurantId: restaurantId,
        payload: {'item_id': itemId},
        menuOperation: true,
      );
    }
  }

  /// Imagens secundárias do prato. A imagem principal continua em
  /// menu_items.image_url; esta tabela limita as posições 2-4.
  Future<List<String>> getMenuItemGallery(String itemId) async {
    try {
      final rows = await _supabase
          .from('menu_item_images')
          .select('image_url')
          .eq('menu_item_id', itemId)
          .order('position');
      return (rows as List)
          .map((row) => row['image_url']?.toString().trim() ?? '')
          .where((url) => url.isNotEmpty)
          .toList();
    } catch (error) {
      debugPrint('Erro ao obter galeria do prato: $error');
      return const [];
    }
  }

  Future<bool> replaceMenuItemGallery({
    required String itemId,
    required List<String> imageUrls,
  }) async {
    final normalized = imageUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .take(4)
        .toList();
    try {
      await _supabase
          .from('menu_item_images')
          .delete()
          .eq('menu_item_id', itemId);
      if (normalized.isNotEmpty) {
        await _supabase.from('menu_item_images').insert([
          for (var index = 0; index < normalized.length; index++)
            {
              'menu_item_id': itemId,
              'image_url': normalized[index],
              'position': index + 2,
            },
        ]);
      }
      return true;
    } catch (error) {
      debugPrint('Erro ao guardar galeria do prato: $error');
      return false;
    }
  }

  /// Buscar todos os itens do cardÃ¡pio (incluindo indisponÃ­veis)
  Future<List<MenuItem>> getAllMenuItems(String restaurantId) async {
    try {
      final response = await _supabase
          .from('menu_items')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('category')
          .order('name');

      return (response as List).map((data) => MenuItem.fromMap(data)).toList();
    } catch (e) {
      debugPrint('Erro ao buscar todos os itens: $e');
      return [];
    }
  }

  Future<List<MenuItemReview>> getMenuItemReviews(
    String menuItemId, {
    int? page,
    int pageSize = 20,
    bool onlyWithPhotos = false,
  }) async {
    try {
      dynamic directQuery = _supabase
          .from('menu_item_reviews')
          .select(
            'id, menu_item_id, reviewer_id, reviewer_name, rating, comment, image_url, created_at',
          )
          .eq('menu_item_id', menuItemId);
      if (onlyWithPhotos) {
        directQuery = directQuery.not('image_url', 'is', null);
      }
      directQuery = directQuery.order('created_at', ascending: false);
      if (page != null) {
        directQuery = directQuery.range(
          page * pageSize,
          page * pageSize + pageSize - 1,
        );
      }
      final directResponse = await directQuery;

      final directRows = (directResponse as List).cast<Map<String, dynamic>>();
      final reviewerIds = directRows
          .map((row) => row['reviewer_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final reviewerProfiles = <String, Map<String, dynamic>>{};
      if (reviewerIds.isNotEmpty) {
        try {
          final profilesResponse = await _supabase
              .from('profiles')
              .select()
              .inFilter('id', reviewerIds);
          for (final row
              in (profilesResponse as List).cast<Map<String, dynamic>>()) {
            final id = row['id']?.toString() ?? '';
            if (id.isNotEmpty) {
              reviewerProfiles[id] = row;
            }
          }
        } catch (error) {
          debugPrint(
            'RestaurantService.getMenuItemReviews reviewer profile lookup error: $error',
          );
        }
      }

      final currentUserId = _supabase.auth.currentUser?.id;
      final reviewIds = directRows
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final likeCounts = <String, int>{};
      final likedByCurrentUser = <String>{};
      if (reviewIds.isNotEmpty) {
        try {
          final likesResponse = await _supabase
              .from('menu_item_review_likes')
              .select('review_id, user_id')
              .inFilter('review_id', reviewIds);
          for (final row
              in (likesResponse as List).cast<Map<String, dynamic>>()) {
            final reviewId = row['review_id']?.toString() ?? '';
            final userId = row['user_id']?.toString() ?? '';
            if (reviewId.isEmpty) continue;
            likeCounts[reviewId] = (likeCounts[reviewId] ?? 0) + 1;
            if (currentUserId != null && userId == currentUserId) {
              likedByCurrentUser.add(reviewId);
            }
          }
        } catch (error) {
          debugPrint(
            'RestaurantService.getMenuItemReviews likes lookup error: $error',
          );
        }
      }

      final directReviews =
          directRows.map((row) {
            final reviewId = row['id']?.toString() ?? '';
            final reviewerId = row['reviewer_id']?.toString() ?? '';
            final reviewerProfile = reviewerProfiles[reviewerId];
            final reviewerName = _resolveProfileDisplayName(
              reviewerProfile,
              fallback: row['reviewer_name']?.toString() ?? 'Cliente',
            );

            return MenuItemReview.fromMap({
              ...row,
              'menu_item_name': row['menu_item_name'] ?? 'Prato',
              'reviewer_name': reviewerName,
              'reviewer_avatar_url': reviewerProfile?['avatar_url'],
              'reviewer_verified':
                  reviewerProfile?['is_verified'] == true ||
                  reviewerProfile?['verification_score'] != null,
              'likes_count': likeCounts[reviewId] ?? 0,
              'liked_by_current_user': likedByCurrentUser.contains(reviewId),
            });
          }).toList()..sort((a, b) {
            final likesCompare = b.likesCount.compareTo(a.likesCount);
            if (likesCompare != 0) return likesCompare;
            final ratingCompare = b.rating.compareTo(a.rating);
            if (ratingCompare != 0) return ratingCompare;
            return b.createdAt.compareTo(a.createdAt);
          });
      if (directReviews.isNotEmpty) {
        return directReviews;
      }
    } catch (error) {
      debugPrint(
        'RestaurantService.getMenuItemReviews primary query error: $error',
      );
    }

    try {
      final orderItems = await _supabase
          .from('order_items')
          .select('order_id')
          .eq('menu_item_id', menuItemId);

      final orderIds = (orderItems as List)
          .map((row) => row['order_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();

      if (orderIds.isEmpty) {
        return [];
      }

      final reviewsResponse = await _supabase
          .from('reviews')
          .select(
            'id, order_id, reviewer_id, user_id, rating, comment, created_at',
          )
          .inFilter('order_id', orderIds)
          .order('created_at', ascending: false);

      final rawReviews = (reviewsResponse as List).cast<Map<String, dynamic>>();
      if (rawReviews.isEmpty) {
        return [];
      }

      final reviewerIds = rawReviews
          .map(
            (row) =>
                row['reviewer_id']?.toString() ?? row['user_id']?.toString(),
          )
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();

      final reviewerNames = <String, String>{};
      final reviewerProfiles = <String, Map<String, dynamic>>{};
      if (reviewerIds.isNotEmpty) {
        try {
          final profiles = await _supabase
              .from('profiles')
              .select()
              .inFilter('id', reviewerIds);

          for (final profile
              in (profiles as List).cast<Map<String, dynamic>>()) {
            final profileId = profile['id']?.toString() ?? '';
            reviewerProfiles[profileId] = profile;
            reviewerNames[profileId] = _resolveProfileDisplayName(profile);
          }
        } catch (error) {
          debugPrint(
            'RestaurantService.getMenuItemReviews fallback profile lookup error: $error',
          );
        }
      }

      return rawReviews.map((row) {
        final reviewerId =
            row['reviewer_id']?.toString() ?? row['user_id']?.toString() ?? '';
        final reviewerProfile = reviewerProfiles[reviewerId];
        return MenuItemReview(
          id: row['id']?.toString() ?? '',
          menuItemId: menuItemId,
          menuItemName: 'Prato',
          reviewerId: reviewerId,
          reviewerName: reviewerNames[reviewerId] ?? 'Cliente',
          reviewerAvatarUrl: reviewerProfiles[reviewerId]?['avatar_url']
              ?.toString(),
          rating: (row['rating'] as num?)?.toInt() ?? 5,
          comment: row['comment']?.toString(),
          isVerifiedReviewer:
              reviewerProfile?['is_verified'] == true ||
              reviewerProfile?['verification_score'] != null,
          createdAt:
              DateTime.tryParse(row['created_at']?.toString() ?? '') ??
              ServerClockService.instance.now(),
        );
      }).toList();
    } catch (e) {
      debugPrint('Erro ao buscar reviews do prato: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRestaurantMenuItemReviewInsights(
    String restaurantId,
  ) async {
    try {
      final menuItemsResponse = await _supabase
          .from('menu_items')
          .select('id, name, image_url')
          .eq('restaurant_id', restaurantId);

      final menuItems = (menuItemsResponse as List)
          .cast<Map<String, dynamic>>();
      if (menuItems.isEmpty) return [];

      final itemMeta = <String, Map<String, dynamic>>{
        for (final item in menuItems)
          item['id']?.toString() ?? '': {
            'name': item['name']?.toString() ?? 'Prato',
            'image_url': item['image_url']?.toString(),
          },
      };

      final itemIds = itemMeta.keys.where((id) => id.isNotEmpty).toList();
      if (itemIds.isEmpty) return [];

      final reviewsResponse = await _supabase
          .from('menu_item_reviews')
          .select()
          .inFilter('menu_item_id', itemIds)
          .order('created_at', ascending: false);

      final reviewRows = (reviewsResponse as List).cast<Map<String, dynamic>>();
      final reviewIds = reviewRows
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final reviewerIds = reviewRows
          .map((row) => row['reviewer_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final reviewerProfiles = <String, Map<String, dynamic>>{};
      final likeCounts = <String, int>{};
      final responsesByReview = <String, Map<String, dynamic>>{};
      if (reviewerIds.isNotEmpty) {
        try {
          final profilesResponse = await _supabase
              .from('profiles')
              .select()
              .inFilter('id', reviewerIds);
          for (final row
              in (profilesResponse as List).cast<Map<String, dynamic>>()) {
            final id = row['id']?.toString() ?? '';
            if (id.isNotEmpty) {
              reviewerProfiles[id] = row;
            }
          }
        } catch (error) {
          debugPrint(
            'RestaurantService.getRestaurantMenuItemReviewInsights profile lookup error: $error',
          );
        }
      }

      if (reviewIds.isNotEmpty) {
        try {
          final likesResponse = await _supabase
              .from('menu_item_review_likes')
              .select('review_id')
              .inFilter('review_id', reviewIds);
          for (final row
              in (likesResponse as List).cast<Map<String, dynamic>>()) {
            final reviewId = row['review_id']?.toString() ?? '';
            if (reviewId.isNotEmpty) {
              likeCounts[reviewId] = (likeCounts[reviewId] ?? 0) + 1;
            }
          }
        } catch (error) {
          debugPrint(
            'RestaurantService.getRestaurantMenuItemReviewInsights likes lookup error: $error',
          );
        }
        try {
          final responses = await _supabase
              .from('restaurant_menu_review_responses')
              .select(
                'review_id, body, author_id, created_at, updated_at, edited_at',
              )
              .inFilter('review_id', reviewIds);
          for (final raw in (responses as List).cast<Map<String, dynamic>>()) {
            final reviewId = raw['review_id']?.toString() ?? '';
            if (reviewId.isNotEmpty) responsesByReview[reviewId] = raw;
          }
        } catch (error) {
          debugPrint(
            'RestaurantService.getRestaurantMenuItemReviewInsights response lookup error: $error',
          );
        }
      }

      return reviewRows.map((row) {
        final reviewerId = row['reviewer_id']?.toString() ?? '';
        final reviewerProfile = reviewerProfiles[reviewerId];
        final menuMeta =
            itemMeta[row['menu_item_id']?.toString() ?? ''] ?? const {};
        final response = responsesByReview[row['id']?.toString() ?? ''];
        return {
          ...row,
          'menu_item_name': menuMeta['name']?.toString() ?? 'Prato',
          'menu_item_image_url': menuMeta['image_url']?.toString(),
          'reviewer_name': _resolveProfileDisplayName(
            reviewerProfile,
            fallback: row['reviewer_name']?.toString() ?? 'Cliente',
          ),
          'reviewer_avatar_url': reviewerProfile?['avatar_url'],
          'likes_count': likeCounts[row['id']?.toString() ?? ''] ?? 0,
          'restaurant_response': response?['body'],
          'restaurant_response_created_at': response?['created_at'],
          'restaurant_response_edited_at': response?['edited_at'],
        };
      }).toList()..sort((a, b) {
        final likesCompare = ((b['likes_count'] as num?)?.toInt() ?? 0)
            .compareTo((a['likes_count'] as num?)?.toInt() ?? 0);
        if (likesCompare != 0) return likesCompare;
        final createdAtB = DateTime.tryParse(b['created_at']?.toString() ?? '');
        final createdAtA = DateTime.tryParse(a['created_at']?.toString() ?? '');
        return (createdAtB ?? ServerClockService.instance.now()).compareTo(
          createdAtA ?? ServerClockService.instance.now(),
        );
      });
    } catch (e) {
      debugPrint('Erro ao carregar reviews por prato do restaurante: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getRestaurantMenuReviewMetrics(
    String restaurantId,
  ) async {
    try {
      final data = await _supabase.rpc(
        'get_restaurant_menu_review_metrics',
        params: {'p_restaurant_id': restaurantId},
      );
      return data is Map ? Map<String, dynamic>.from(data) : const {};
    } catch (error) {
      debugPrint('Erro ao obter métricas de avaliações: $error');
      return const {};
    }
  }

  Future<bool> upsertRestaurantMenuReviewResponse({
    required String reviewId,
    required String body,
  }) async {
    try {
      await _supabase.rpc(
        'upsert_restaurant_menu_review_response',
        params: {'p_review_id': reviewId, 'p_body': body.trim()},
      );
      return true;
    } catch (error) {
      debugPrint('Erro ao responder à avaliação: $error');
      return false;
    }
  }

  Future<bool> reportRestaurantMenuReview({
    required String reviewId,
    required String reason,
  }) async {
    try {
      await _supabase.rpc(
        'report_restaurant_menu_review',
        params: {'p_review_id': reviewId, 'p_reason': reason.trim()},
      );
      return true;
    } catch (error) {
      debugPrint('Erro ao denunciar avaliação: $error');
      return false;
    }
  }

  Future<bool> submitMenuItemReview({
    required String menuItemId,
    required int rating,
    String? comment,
    String? imageUrl,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final roleRow = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      final role = roleRow?['role']?.toString().toLowerCase();
      if (role != null && role != 'client' && role != 'customer') {
        return false;
      }
    } catch (error) {
      debugPrint(
        'RestaurantService.createMenuItemReview role lookup error: $error',
      );
    }

    String reviewerName = 'Cliente';
    try {
      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      reviewerName = _resolveProfileDisplayName(
        profile,
        fallback: 'Cliente',
        emailFallback: user.email,
      );
    } catch (e) {
      debugPrint('Erro ao buscar perfil da review: $e');
    }

    try {
      await _supabase.from('menu_item_reviews').insert({
        'menu_item_id': menuItemId,
        'reviewer_id': user.id,
        'reviewer_name': reviewerName,
        'rating': rating,
        'comment': (comment ?? '').trim().isEmpty ? null : comment!.trim(),
        'image_url': (imageUrl ?? '').trim().isEmpty ? null : imageUrl!.trim(),
      });
    } catch (e) {
      debugPrint('Erro ao inserir review do prato diretamente: $e');
      try {
        final headers = await _authHeaders();
        final fallback = await _supabase.functions.invoke(
          'menu-item-review-create',
          headers: headers,
          body: {
            'menu_item_id': menuItemId,
            'rating': rating,
            'comment': (comment ?? '').trim(),
            'image_url': (imageUrl ?? '').trim(),
          },
        );
        if (fallback.status < 200 || fallback.status >= 300) {
          return false;
        }
      } catch (fallbackError) {
        debugPrint('Erro no fallback menu-item-review-create: $fallbackError');
        return false;
      }
    }

    try {
      final aggregate = await _supabase
          .from('menu_item_reviews')
          .select('rating')
          .eq('menu_item_id', menuItemId);
      final ratings = (aggregate as List)
          .map((row) => (row['rating'] as num?)?.toDouble())
          .whereType<double>()
          .toList();
      if (ratings.isNotEmpty) {
        final average = ratings.reduce((a, b) => a + b) / ratings.length;
        await _supabase
            .from('menu_items')
            .update({'item_rating': average})
            .eq('id', menuItemId);
      }
    } catch (e) {
      debugPrint('Erro ao recalcular media do prato: $e');
    }

    return true;
  }

  Future<bool> deleteMenuItemReview(String reviewId) async {
    try {
      await _supabase.from('menu_item_reviews').delete().eq('id', reviewId);
      return true;
    } catch (e) {
      debugPrint('Erro ao apagar review do prato: $e');
      return false;
    }
  }

  Future<bool> toggleMenuItemReviewLike(String reviewId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final existing = await _supabase
          .from('menu_item_review_likes')
          .select('id')
          .eq('review_id', reviewId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing != null) {
        await _supabase
            .from('menu_item_review_likes')
            .delete()
            .eq('review_id', reviewId)
            .eq('user_id', user.id);
      } else {
        await _supabase.from('menu_item_review_likes').insert({
          'review_id': reviewId,
          'user_id': user.id,
        });
      }
      return true;
    } catch (e) {
      debugPrint('Erro ao curtir review do prato: $e');
      return false;
    }
  }

  Future<String?> uploadMenuItemReviewImage({
    required XFile file,
    required String reviewerId,
  }) async {
    return uploadRestaurantAsset(
      file: file,
      ownerId: reviewerId,
      folder: 'menu_item_reviews',
    );
  }

  Future<String?> uploadRestaurantAsset({
    required XFile file,
    required String ownerId,
    required String folder,
  }) async {
    try {
      lastAssetUploadError = null;
      const bucket = 'restaurant-assets';
      var session = _supabase.auth.currentSession;
      if (session == null || session.isExpired) {
        final refreshed = await _supabase.auth.refreshSession();
        session = refreshed.session;
      }
      final authenticatedUserId =
          session?.user.id ?? _supabase.auth.currentUser?.id;
      if (authenticatedUserId == null) {
        lastAssetUploadError =
            'A sua sessao terminou. Entre novamente antes de carregar a imagem.';
        return null;
      }
      final mimeType = file.mimeType?.toLowerCase().trim();
      final extension = _assetExtension(file.path, mimeType);
      final contentType = _assetContentType(mimeType, extension);
      final fileName =
          '${folder}_${ServerClockService.instance.now().millisecondsSinceEpoch}.$extension';
      final path = '$authenticatedUserId/$folder/$fileName';

      await _supabase.storage
          .from(bucket)
          .uploadBinary(
            path,
            await file.readAsBytes(),
            fileOptions: FileOptions(upsert: true, contentType: contentType),
          );

      final publicUrl = _supabase.storage.from(bucket).getPublicUrl(path);
      // Evita que Image.network reutilize uma capa antiga do cache do dispositivo.
      return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      lastAssetUploadError = _assetUploadMessage(e);
      debugPrint('Erro ao fazer upload do asset do restaurante: $e');
      return null;
    }
  }

  /// Atualizar informaÃ§Ãµes do restaurante
  Future<String?> uploadRestaurantAssetBytes({
    required List<int> bytes,
    required String ownerId,
    required String folder,
    String extension = 'jpg',
    String contentType = 'image/jpeg',
  }) async {
    try {
      lastAssetUploadError = null;
      const bucket = 'restaurant-assets';
      var session = _supabase.auth.currentSession;
      if (session == null || session.isExpired) {
        final refreshed = await _supabase.auth.refreshSession();
        session = refreshed.session;
      }
      final authenticatedUserId =
          session?.user.id ?? _supabase.auth.currentUser?.id;
      if (authenticatedUserId == null) {
        lastAssetUploadError =
            'A sua sessao terminou. Entre novamente antes de carregar a imagem.';
        return null;
      }
      final normalizedExtension = extension.replaceAll('.', '').trim().isEmpty
          ? 'jpg'
          : extension.replaceAll('.', '').trim();
      final fileName =
          '${folder}_${ServerClockService.instance.now().millisecondsSinceEpoch}.$normalizedExtension';
      final path = '$authenticatedUserId/$folder/$fileName';

      await _supabase.storage
          .from(bucket)
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(upsert: true, contentType: contentType),
          );

      final publicUrl = _supabase.storage.from(bucket).getPublicUrl(path);
      // Evita que Image.network reutilize uma capa antiga do cache do dispositivo.
      return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      lastAssetUploadError = _assetUploadMessage(e);
      debugPrint('Erro ao fazer upload otimizado do asset do restaurante: $e');
      return null;
    }
  }

  Future<Map<String, Map<String, dynamic>>> getMenuItemEngagement(
    List<String> menuItemIds,
  ) async {
    if (menuItemIds.isEmpty) return {};
    final result = <String, Map<String, dynamic>>{
      for (final id in menuItemIds)
        id: {'likes': 0, 'comments': 0, 'liked_by_current_user': false},
    };
    final currentUserId = _supabase.auth.currentUser?.id;

    try {
      final likes = await _supabase
          .from('menu_item_likes')
          .select('menu_item_id, user_id')
          .inFilter('menu_item_id', menuItemIds);
      for (final row in (likes as List).cast<Map<String, dynamic>>()) {
        final id = row['menu_item_id']?.toString() ?? '';
        final engagement = result[id];
        if (engagement == null) continue;
        engagement['likes'] = (engagement['likes'] as int) + 1;
        if (row['user_id']?.toString() == currentUserId) {
          engagement['liked_by_current_user'] = true;
        }
      }
    } catch (error) {
      debugPrint('RestaurantService.getMenuItemEngagement likes: $error');
    }

    try {
      final comments = await _supabase
          .from('menu_item_reviews')
          .select('menu_item_id')
          .inFilter('menu_item_id', menuItemIds);
      for (final row in (comments as List).cast<Map<String, dynamic>>()) {
        final id = row['menu_item_id']?.toString() ?? '';
        final engagement = result[id];
        if (engagement != null) {
          engagement['comments'] = (engagement['comments'] as int) + 1;
        }
      }
    } catch (error) {
      debugPrint('RestaurantService.getMenuItemEngagement comments: $error');
    }

    if (currentUserId != null) {
      try {
        final favorites = await _supabase
            .from('favorites')
            .select('menu_item_id')
            .eq('user_id', currentUserId)
            .inFilter('menu_item_id', menuItemIds);
        for (final row in (favorites as List).cast<Map<String, dynamic>>()) {
          final id = row['menu_item_id']?.toString() ?? '';
          if (result.containsKey(id)) {
            result[id]!['favorite_by_current_user'] = true;
          }
        }
      } catch (error) {
        debugPrint('RestaurantService.getMenuItemEngagement favorites: $error');
      }
    }
    return result;
  }

  Future<bool> toggleMenuItemFavorite(String menuItemId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final existing = await _supabase
          .from('favorites')
          .select('id')
          .eq('user_id', userId)
          .eq('menu_item_id', menuItemId)
          .maybeSingle();
      if (existing == null) {
        await _supabase.from('favorites').insert({
          'user_id': userId,
          'menu_item_id': menuItemId,
        });
      } else {
        await _supabase
            .from('favorites')
            .delete()
            .eq('user_id', userId)
            .eq('menu_item_id', menuItemId);
      }
      return true;
    } catch (error) {
      debugPrint('RestaurantService.toggleMenuItemFavorite: $error');
      return false;
    }
  }

  Future<bool> toggleMenuItemLike(String menuItemId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      final existing = await _supabase
          .from('menu_item_likes')
          .select('menu_item_id')
          .eq('menu_item_id', menuItemId)
          .eq('user_id', userId)
          .maybeSingle();
      if (existing == null) {
        await _supabase.from('menu_item_likes').insert({
          'menu_item_id': menuItemId,
          'user_id': userId,
        });
      } else {
        await _supabase
            .from('menu_item_likes')
            .delete()
            .eq('menu_item_id', menuItemId)
            .eq('user_id', userId);
      }
      return true;
    } catch (error) {
      debugPrint('RestaurantService.toggleMenuItemLike: $error');
      return false;
    }
  }

  String _assetUploadMessage(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('row-level security') ||
        value.contains('unauthorized') ||
        value.contains('403')) {
      return 'O servidor recusou a imagem (sessao ou permissao). Termine a sessao, entre novamente e tente outra vez. Detalhe: ${error.toString()}';
    }
    if (value.contains('socket') ||
        value.contains('network') ||
        value.contains('timeout')) {
      return 'Sem ligacao ao servidor. Verifique a internet e tente novamente.';
    }
    return 'O servidor nao conseguiu guardar a imagem. Detalhe: ${error.toString()}';
  }

  String _assetExtension(String path, String? mimeType) {
    final fromMime = switch (mimeType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      'image/jpg' || 'image/jpeg' => 'jpg',
      _ => '',
    };
    if (fromMime.isNotEmpty) return fromMime;
    final value = path.split('.').last.toLowerCase().trim();
    return {'png', 'webp', 'heic', 'heif', 'jpg', 'jpeg'}.contains(value)
        ? (value == 'jpeg' ? 'jpg' : value)
        : 'jpg';
  }

  String _assetContentType(String? mimeType, String extension) {
    if (mimeType == 'image/png' || extension == 'png') return 'image/png';
    if (mimeType == 'image/webp' || extension == 'webp') return 'image/webp';
    if (mimeType == 'image/heic' || extension == 'heic') return 'image/heic';
    if (mimeType == 'image/heif' || extension == 'heif') return 'image/heif';
    return 'image/jpeg';
  }

  Future<bool> updateRestaurant({
    required String restaurantId,
    String? name,
    String? category,
    String? description,
    String? phone,
    String? address,
    String? neighborhood,
    String? city,
    String? landmarkReference,
    String? priceRange,
    String? paymentWalletNumber,
    double? latitude,
    double? longitude,
    bool? isOpen,
    String? imageUrl,
    String? openingTime,
    String? closingTime,
    int? estimatedDeliveryTime,
  }) async {
    try {
      final Map<String, dynamic> updates = {};
      if (name != null) updates['name'] = name;
      if (category != null) updates['category'] = category;
      if (description != null) updates['description'] = description;
      if (phone != null) updates['phone'] = phone;
      if (address != null) updates['address'] = address;
      if (neighborhood != null) updates['neighborhood'] = neighborhood;
      if (city != null) updates['city'] = city;
      if (landmarkReference != null) {
        updates['landmark_reference'] = landmarkReference;
      }
      if (priceRange != null) updates['price_range'] = priceRange;
      if (paymentWalletNumber != null) {
        updates['payment_wallet_number'] = paymentWalletNumber;
      }
      if (latitude != null) updates['latitude'] = latitude;
      if (longitude != null) updates['longitude'] = longitude;
      if (latitude != null && longitude != null) {
        updates['location_status'] = 'confirmed';
      }
      if (isOpen != null) updates['is_open'] = isOpen;
      if (imageUrl != null) updates['image_url'] = imageUrl;
      if (openingTime != null) updates['opening_time'] = openingTime;
      if (closingTime != null) updates['closing_time'] = closingTime;
      if (estimatedDeliveryTime != null) {
        updates['estimated_delivery_time'] = estimatedDeliveryTime;
      }

      if (updates.isEmpty) return true;

      await _supabase
          .from('restaurants')
          .update(updates)
          .eq('id', restaurantId)
          .select('id')
          .single();

      return true;
    } catch (e) {
      debugPrint('Erro ao atualizar restaurante: $e');

      try {
        final headers = await _authHeaders();
        final fallbackUpdates = <String, dynamic>{
          ...?name == null ? null : {'name': name},
          ...?category == null ? null : {'category': category},
          ...?description == null ? null : {'description': description},
          ...?phone == null ? null : {'phone': phone},
          ...?address == null ? null : {'address': address},
          ...?neighborhood == null ? null : {'neighborhood': neighborhood},
          ...?city == null ? null : {'city': city},
          ...?landmarkReference == null
              ? null
              : {'landmark_reference': landmarkReference},
          ...?priceRange == null ? null : {'price_range': priceRange},
          ...?paymentWalletNumber == null
              ? null
              : {'payment_wallet_number': paymentWalletNumber},
          ...?latitude == null ? null : {'latitude': latitude},
          ...?longitude == null ? null : {'longitude': longitude},
          ...?latitude == null || longitude == null
              ? null
              : {'location_status': 'confirmed'},
          ...?isOpen == null ? null : {'is_open': isOpen},
          ...?imageUrl == null ? null : {'image_url': imageUrl},
          ...?openingTime == null ? null : {'opening_time': openingTime},
          ...?closingTime == null ? null : {'closing_time': closingTime},
          ...?estimatedDeliveryTime == null
              ? null
              : {'estimated_delivery_time': estimatedDeliveryTime},
        };
        final fallback = await _supabase.functions.invoke(
          'restaurant-profile-update',
          headers: headers,
          body: {'restaurant_id': restaurantId, 'updates': fallbackUpdates},
        );

        if (fallback.status >= 200 && fallback.status < 300) {
          final data = fallback.data;
          if (data is Map<String, dynamic> && data['success'] == true) {
            return true;
          }
        }

        debugPrint(
          'Fallback restaurant-profile-update falhou: ${fallback.data}',
        );
        return false;
      } catch (fallbackError) {
        debugPrint(
          'Erro no fallback restaurant-profile-update: $fallbackError',
        );
        return false;
      }
    }
  }

  /// Buscar informaÃ§Ãµes do restaurante pelo owner
  Future<Map<String, dynamic>?> getRestaurantByOwnerId(String ownerId) async {
    try {
      final response = await _supabase
          .from('restaurants')
          .select()
          .eq('owner_id', ownerId)
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Erro ao buscar restaurante: $e');
      return null;
    }
  }

  /// Buscar saldo da wallet do restaurante
  Future<double> getRestaurantBalance(String restaurantId) async {
    try {
      final restaurant = await _supabase
          .from('restaurants')
          .select('owner_id, wallet_balance')
          .eq('id', restaurantId)
          .single();

      final ownerId = restaurant['owner_id']?.toString();
      if (ownerId != null && ownerId.isNotEmpty) {
        final wallets = await _supabase
            .from('wallets')
            .select('balance')
            .eq('user_id', ownerId)
            .order('updated_at', ascending: false)
            .limit(1);

        if (wallets.isNotEmpty) {
          final wallet = Map<String, dynamic>.from(wallets.first as Map);
          return (wallet['balance'] as num?)?.toDouble() ??
              (restaurant['wallet_balance'] as num?)?.toDouble() ??
              0.0;
        }
      }

      return (restaurant['wallet_balance'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      debugPrint('Erro ao buscar saldo: $e');
      return 0.0;
    }
  }

  /// Solicitar levantamento de saldo
  Future<bool> requestWithdrawal({
    required String restaurantId,
    required double amount,
    required String phoneNumber,
  }) async {
    try {
      final headers = await _authHeaders();
      final response = await _supabase.functions.invoke(
        'wallet-withdraw-v2',
        headers: headers,
        body: {
          'amount': amount,
          'method': 'm-pesa',
          'phone_number': phoneNumber,
          'notes': 'restaurant_id=$restaurantId',
        },
      );

      if (response.status >= 200 && response.status < 300) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['success'] == true) {
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('Erro ao solicitar levantamento: $e');
      return false;
    }
  }

  /// Buscar histÃ³rico de transaÃ§Ãµes do restaurante
  Future<List<Map<String, dynamic>>> getTransactionHistory(
    String restaurantId, {
    int limit = 20,
  }) async {
    try {
      final ordersResponse = await _supabase
          .from('orders')
          .select('id, total_amount, status, created_at')
          .eq('restaurant_id', restaurantId)
          .order('created_at', ascending: false)
          .limit(limit);

      final orderRows = (ordersResponse as List).cast<Map<String, dynamic>>();
      final orderIds = orderRows.map((o) => o['id'] as String).toList();

      if (orderIds.isEmpty) return [];

      final splitsResponse = await _fetchPaymentSplitsForOrderIds(orderIds);
      final splitByOrderId = <String, Map<String, dynamic>>{};
      for (final split in splitsResponse) {
        final orderId = split['order_id']?.toString();
        if (orderId == null ||
            orderId.isEmpty ||
            splitByOrderId.containsKey(orderId)) {
          continue;
        }
        splitByOrderId[orderId] = split;
      }

      return orderRows.map((order) {
        final split = splitByOrderId[order['id']?.toString() ?? ''];
        return {
          'id': order['id'],
          'type': 'order',
          'amount': split?['restaurant_amount'] ?? order['total_amount'],
          'status': order['status'],
          'date': order['created_at'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Erro ao buscar histÃ³rico: $e');
      return [];
    }
  }

  // ========== ANALYTICS ==========

  /// Buscar receita Ãºltimos 7 dias
  Future<List<Map<String, dynamic>>> getWeeklyRevenue(
    String restaurantId,
  ) async {
    try {
      final now = ServerClockService.instance.now().toLocal();
      final weekAgo = now.subtract(const Duration(days: 7));

      final response = await _supabase
          .from('orders')
          .select('created_at, total_amount')
          .eq('restaurant_id', restaurantId)
          .eq('status', 'delivered')
          .gte('created_at', weekAgo.toIso8601String());

      // Agrupar por dia
      final Map<String, double> dailyRevenue = {};
      for (var i = 0; i < 7; i++) {
        final day = now.subtract(Duration(days: i));
        final key =
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        dailyRevenue[key] = 0;
      }

      for (var order in response) {
        final date = DateTime.parse(order['created_at']);
        final key =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        dailyRevenue[key] =
            (dailyRevenue[key] ?? 0) +
            (order['total_amount'] as num).toDouble();
      }

      return dailyRevenue.entries
          .map((e) => {'date': e.key, 'revenue': e.value})
          .toList()
          .reversed
          .toList();
    } catch (e) {
      debugPrint('Erro ao buscar receita semanal: $e');
      return [];
    }
  }

  /// Buscar prato mais vendido
  Future<Map<String, dynamic>?> getBestSellingItem(String restaurantId) async {
    try {
      final ordersResponse = await _supabase
          .from('orders')
          .select('id')
          .eq('restaurant_id', restaurantId)
          .eq('status', 'delivered');

      final orderIds = (ordersResponse as List)
          .map((o) => o['id'] as String)
          .toList();
      if (orderIds.isEmpty) return null;

      final itemsResponse = await _fetchOrderItemsForOrderIds(orderIds);

      final Map<String, int> itemCounts = {};
      final Map<String, String> itemNames = {};

      for (var item in itemsResponse) {
        final itemId = item['menu_item_id'] as String;
        itemCounts[itemId] =
            (itemCounts[itemId] ?? 0) + (item['quantity'] as int);
        final menuItem = item['menu_items'];
        if (menuItem is Map<String, dynamic> && menuItem['name'] != null) {
          itemNames[itemId] = menuItem['name'].toString();
        }
      }

      if (itemCounts.isEmpty) return null;

      final bestItemId = itemCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
      return {
        'item_id': bestItemId,
        'name': itemNames[bestItemId] ?? 'Desconhecido',
        'quantity': itemCounts[bestItemId],
      };
    } catch (e) {
      debugPrint('Erro ao buscar prato mais vendido: $e');
      return null;
    }
  }

  /// Calcular crescimento vs semana passada
  Future<double> getGrowthPercentage(String restaurantId) async {
    try {
      final now = ServerClockService.instance.now().toLocal();
      final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));
      final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));

      final revenues = await Future.wait<double>([
        _sumDeliveredRevenueForRange(restaurantId, start: thisWeekStart),
        _sumDeliveredRevenueForRange(
          restaurantId,
          start: lastWeekStart,
          end: thisWeekStart,
        ),
      ]);
      final thisWeekRevenue = revenues[0];
      final lastWeekRevenue = revenues[1];

      if (lastWeekRevenue == 0) return thisWeekRevenue > 0 ? 100.0 : 0.0;

      return ((thisWeekRevenue - lastWeekRevenue) / lastWeekRevenue) * 100;
    } catch (e) {
      debugPrint('Erro ao calcular crescimento: $e');
      return 0.0;
    }
  }
}
