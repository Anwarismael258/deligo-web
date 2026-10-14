import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_env.dart';
import '../shared/models/cart_item.dart';
import '../shared/models/menu_item.dart';

class CartService extends ChangeNotifier {
  CartService() : _deliveryFee = _resolveConfiguredDeliveryFee() {
    _authSubscription = _supabase.auth.onAuthStateChange.listen((event) {
      final nextUserId = event.session?.user.id;
      unawaited(_syncAuthUser(nextUserId));
    });
    unawaited(_syncAuthUser(_supabase.auth.currentUser?.id));
  }

  final SupabaseClient _supabase = Supabase.instance.client;
  late final StreamSubscription<AuthState> _authSubscription;

  final List<CartItem> _items = [];
  String? _restaurantId;
  String? _restaurantName;
  int _deliveryFee;
  bool _isLoading = false;
  String? _userId;
  bool _hasLoadedRemoteCart = false;
  bool _hasLoadedGuestCart = false;
  static const _guestCartStorageKey = 'deligo_guest_cart_v1';

  List<CartItem> get items => List.unmodifiable(_items);
  String? get restaurantId => _restaurantId;
  String? get restaurantName => _restaurantName;
  int get deliveryFee => _deliveryFee;
  bool get isEmpty => _items.isEmpty;
  bool get isLoading => _isLoading;
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => _items.fold(0.0, (sum, item) => sum + item.subtotal);
  double get total => subtotal + _deliveryFee;

  static int parseDeliveryFee(String? raw, {int fallback = 150}) {
    if (raw == null) return fallback;

    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0) return fallback;

    return parsed;
  }

  static int _resolveConfiguredDeliveryFee() {
    return parseDeliveryFee(AppEnv.deliveryFeeDefault);
  }

  Future<void> initialize() async {
    await _ensureReady();
  }

  Future<void> loadCartFromSupabase() async {
    if (_userId == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final response = await _supabase
          .from('cart_items')
          .select('''
            id,
            quantity,
            observations,
            extras,
            extras_price,
            menu_item:menu_items(*)
          ''')
          .eq('user_id', _userId!);

      _items.clear();
      _restaurantId = null;

      for (final item in response) {
        final menuItemData = item['menu_item'];
        if (menuItemData != null) {
          final menuItem = MenuItem.fromMap(menuItemData);
          _items.add(
            CartItem(
              menuItem: menuItem,
              quantity: item['quantity'] as int,
              observations: item['observations'] as String?,
              extras: List<String>.from(item['extras'] ?? []),
              extrasPrice: (item['extras_price'] as num?)?.toDouble() ?? 0.0,
            ),
          );

          _restaurantId ??= menuItem.restaurantId;
        }
      }
      _hasLoadedRemoteCart = true;
    } catch (e) {
      debugPrint('Erro ao carregar carrinho: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveToSupabase(CartItem item) async {
    if (_userId == null) return;

    try {
      final existingRow = await _findPersistedCartRow(item);
      final payload = {
        'user_id': _userId,
        'menu_item_id': item.menuItem.id,
        'quantity': item.quantity,
        'observations': _normalizeObservations(item.observations),
        'extras': item.extras,
        'extras_price': item.extrasPrice,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existingRow != null) {
        await _supabase
            .from('cart_items')
            .update(payload)
            .eq('id', existingRow['id']);
        return;
      }

      await _supabase.from('cart_items').insert(payload);
    } catch (e) {
      debugPrint('Erro ao salvar carrinho: $e');
    }
  }

  Future<void> _removeFromSupabase(CartItem item) async {
    if (_userId == null) return;

    try {
      final existingRow = await _findPersistedCartRow(item);
      if (existingRow == null) return;
      await _supabase
          .from('cart_items')
          .delete()
          .eq('id', existingRow['id']);
    } catch (e) {
      debugPrint('Erro ao remover do carrinho: $e');
    }
  }

  Future<void> _clearSupabaseCart() async {
    if (_userId == null) return;

    try {
      await _supabase.from('cart_items').delete().eq('user_id', _userId!);
    } catch (e) {
      debugPrint('Erro ao limpar carrinho: $e');
    }
  }

  void setDeliveryFee(int fee) {
    if (fee < 0) return;
    _deliveryFee = fee;
    notifyListeners();
  }

  Future<void> addItem(
    MenuItem menuItem, {
    int quantity = 1,
    String? observations,
    List<String> extras = const [],
    double extrasPrice = 0.0,
    String? restaurantName,
  }) async {
    await _ensureReady();

    if (_restaurantId != null && _restaurantId != menuItem.restaurantId) {
      await clearCart();
    }

    _restaurantId = menuItem.restaurantId;
    _restaurantName ??= restaurantName;

    final existingIndex = _items.indexWhere(
      (item) =>
          item.menuItem.id == menuItem.id &&
          item.observations == observations &&
          _listEquals(item.extras, extras),
    );

    if (existingIndex >= 0) {
      _items[existingIndex] = _items[existingIndex].copyWith(
        quantity: _items[existingIndex].quantity + quantity,
      );
      await _saveToSupabase(_items[existingIndex]);
    } else {
      final newItem = CartItem(
        menuItem: menuItem,
        quantity: quantity,
        observations: observations,
        extras: extras,
        extrasPrice: extrasPrice,
      );
      _items.add(newItem);
      await _saveToSupabase(newItem);
    }

    await _persistGuestCartIfNeeded();
    notifyListeners();
  }

  Future<void> updateQuantity(int index, int quantity) async {
    await _ensureReady();

    if (quantity <= 0) {
      await removeItem(index);
    } else if (index >= 0 && index < _items.length) {
      _items[index] = _items[index].copyWith(quantity: quantity);
      await _saveToSupabase(_items[index]);
      await _persistGuestCartIfNeeded();
      notifyListeners();
    }
  }

  Future<void> removeItem(int index) async {
    await _ensureReady();

    if (index >= 0 && index < _items.length) {
      final item = _items[index];
      await _removeFromSupabase(item);
      _items.removeAt(index);

      if (_items.isEmpty) {
        _restaurantId = null;
        _restaurantName = null;
      }

      await _persistGuestCartIfNeeded();
      notifyListeners();
    }
  }

  Future<void> clearCart() async {
    await _ensureReady();
    await _clearSupabaseCart();
    _items.clear();
    _restaurantId = null;
    _restaurantName = null;
    _deliveryFee = _resolveConfiguredDeliveryFee();
    await _persistGuestCartIfNeeded();
    notifyListeners();
  }

  bool hasItemsFromRestaurant(String restaurantId) =>
      _restaurantId == restaurantId;

  Future<void> _ensureReady() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (_userId != currentUserId) {
      await _syncAuthUser(currentUserId);
    }
    if (_userId != null && !_hasLoadedRemoteCart) {
      await loadCartFromSupabase();
    }
    if (_userId == null && !_hasLoadedGuestCart) {
      await _loadGuestCart();
    }
  }

  Future<void> _loadGuestCart() async {
    _hasLoadedGuestCart = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getStringList(_guestCartStorageKey) ?? const [];
      final loaded = <CartItem>[];
      for (final encoded in raw) {
        try {
          final data = jsonDecode(encoded) as Map<String, dynamic>;
          final menuItem = MenuItem.fromMap(
            Map<String, dynamic>.from(data['menu_item'] as Map),
          );
          loaded.add(
            CartItem(
              menuItem: menuItem,
              quantity: (data['quantity'] as num?)?.toInt() ?? 1,
              observations: data['observations']?.toString(),
              extras: List<String>.from(data['extras'] ?? const []),
              extrasPrice: (data['extras_price'] as num?)?.toDouble() ?? 0,
            ),
          );
        } catch (_) {
          // Ignore only malformed local entries; never affect remote data.
        }
      }
      _items
        ..clear()
        ..addAll(loaded);
      if (loaded.isNotEmpty) {
        _restaurantId = loaded.first.menuItem.restaurantId;
      }
      notifyListeners();
    } catch (error) {
      debugPrint('Erro ao carregar carrinho visitante: $error');
    }
  }

  Future<void> _persistGuestCartIfNeeded() async {
    if (_userId != null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = _items
          .map(
            (item) => jsonEncode({
              'menu_item': item.menuItem.toMap(),
              'quantity': item.quantity,
              'observations': item.observations,
              'extras': item.extras,
              'extras_price': item.extrasPrice,
            }),
          )
          .toList();
      await preferences.setStringList(_guestCartStorageKey, encoded);
    } catch (error) {
      debugPrint('Erro ao guardar carrinho visitante: $error');
    }
  }

  Future<void> _clearGuestCart() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_guestCartStorageKey);
    } catch (error) {
      debugPrint('Erro ao limpar carrinho visitante: $error');
    }
  }

  Future<void> _syncAuthUser(String? nextUserId) async {
    if (_userId == nextUserId) {
      if (nextUserId != null && !_hasLoadedRemoteCart) {
        await loadCartFromSupabase();
      }
      return;
    }

    final guestItems = _userId == null && nextUserId != null
        ? List<CartItem>.from(_items)
        : const <CartItem>[];

    _userId = nextUserId;
    _hasLoadedRemoteCart = false;
    if (nextUserId == null) _hasLoadedGuestCart = false;
    _items.clear();
    _restaurantId = null;
    _restaurantName = null;
    _deliveryFee = _resolveConfiguredDeliveryFee();
    _notifyStateChanged();

    if (_userId != null) {
      await loadCartFromSupabase();
      for (final item in guestItems) {
        final alreadyPresent = _items.any(
          (current) => current.menuItem.id == item.menuItem.id &&
              _listEquals(current.extras, item.extras) &&
              current.observations == item.observations,
        );
        if (alreadyPresent) continue;
        _items.add(item);
        _restaurantId ??= item.menuItem.restaurantId;
        await _saveToSupabase(item);
      }
      if (guestItems.isNotEmpty) await _clearGuestCart();
    }
  }

  void _notifyStateChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String? _normalizeObservations(String? observations) {
    final normalized = observations?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<Map<String, dynamic>?> _findPersistedCartRow(CartItem item) async {
    final response = await _supabase
        .from('cart_items')
        .select('id, observations, extras, extras_price')
        .eq('user_id', _userId!)
        .eq('menu_item_id', item.menuItem.id);

    final targetObservations = _normalizeObservations(item.observations);
    final targetExtrasJson = jsonEncode(item.extras);
    final targetExtrasPrice = item.extrasPrice;

    for (final row in response) {
      final rowMap = Map<String, dynamic>.from(row as Map);
      final rowObservations = _normalizeObservations(
        rowMap['observations']?.toString(),
      );
      final rowExtrasJson = jsonEncode(List<String>.from(rowMap['extras'] ?? []));
      final rowExtrasPrice = (rowMap['extras_price'] as num?)?.toDouble() ?? 0.0;

      if (rowObservations == targetObservations &&
          rowExtrasJson == targetExtrasJson &&
          rowExtrasPrice == targetExtrasPrice) {
        return rowMap;
      }
    }

    return null;
  }
}
