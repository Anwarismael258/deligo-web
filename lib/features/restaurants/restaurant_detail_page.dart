import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme/app_colors.dart';
import '../../services/cart_service.dart';
import '../../services/public_share_service.dart';
import '../../services/restaurant_service.dart';
import '../../services/restaurant_share_service.dart';
import '../../services/sound_controller.dart';
import '../../services/social_review_service.dart';
import '../../shared/models/menu_item.dart';
import '../../shared/models/menu_item_review.dart';
import '../../shared/utils/compact_number.dart';
import '../../shared/models/restaurant.dart';
import '../../shared/utils/location_display.dart';
import '../../shared/utils/maps_route.dart';
import '../categories/deligo_food_categories.dart';

class RestaurantDetailPage extends StatefulWidget {
  final String restaurantId;
  final String? highlightDishId;

  const RestaurantDetailPage({
    super.key,
    required this.restaurantId,
    this.highlightDishId,
  });

  @override
  State<RestaurantDetailPage> createState() => _RestaurantDetailPageState();
}

class _RestaurantDetailPageState extends State<RestaurantDetailPage> {
  final RestaurantService _restaurantService = RestaurantService();
  final SocialReviewService _socialReviewService = SocialReviewService();
  final RestaurantShareService _restaurantShareService =
      RestaurantShareService();
  final PublicShareService _publicShareService = PublicShareService.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  Restaurant? _restaurant;
  List<MenuItem> _menuItems = [];
  List<String> _categories = [];
  String? _selectedCategory;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isFavorite = false;
  bool _favoriteBusy = false;
  RouteInfo? _restaurantRouteInfo;
  bool _loadingRestaurantRoute = false;
  final Map<String, List<MenuItemReview>> _menuItemReviews = {};
  final Map<String, List<Map<String, dynamic>>> _menuItemOptions = {};
  final Map<String, List<String>> _menuItemGallery = {};
  final Set<String> _activeDishDetailIds = <String>{};
  Map<String, Map<String, dynamic>> _menuItemEngagement = {};
  String? _weeklyDishId;
  final Set<String> _engagementBusyItems = <String>{};
  RealtimeChannel? _dishEngagementChannel;
  final Set<String> _loadingReviewItems = <String>{};
  final Map<String, List<Map<String, dynamic>>> _menuItemReplies = {};
  final Set<String> _loadingReplyReviews = <String>{};
  final Set<String> _expandedReviewReplies = <String>{};
  String? _activeReplyReviewId;
  String? _activeReplyToName;
  String _replyDraft = '';
  bool _replySending = false;
  Map<String, dynamic>? _activeCombo;
  String? _autoOpenedDishId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _dishEngagementChannel?.unsubscribe();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RestaurantDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightDishId != widget.highlightDishId) {
      _autoOpenedDishId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeOpenHighlightedDish();
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final restaurant = await _restaurantService.getRestaurantById(
        widget.restaurantId,
      );
      if (restaurant == null) throw StateError('Restaurante não encontrado.');
      List<MenuItem> menuItems = const [];
      List<String> categories = const [];
      Map<String, dynamic>? combo;
      Map<String, Map<String, dynamic>> engagement = {};
      try {
        menuItems = await _restaurantService.getMenuItems(widget.restaurantId);
      } catch (_) {}
      try {
        categories = await _restaurantService.getCategories(
          widget.restaurantId,
        );
      } catch (_) {}
      try {
        combo = await _restaurantService.getActiveDailyCombo(
          widget.restaurantId,
        );
      } catch (_) {}
      try {
        engagement = await _restaurantService.getMenuItemEngagement(
          menuItems.map((item) => item.id).toList(),
        );
      } catch (_) {}
      try {
        await _loadFavoriteState();
      } catch (_) {}

      if (!mounted) return;
      String? weeklyDishId;
      var weeklyLikes = 0;
      for (final item in menuItems) {
        final likes = (engagement[item.id]?['likes'] as num?)?.toInt() ?? 0;
        if (likes > weeklyLikes) {
          weeklyLikes = likes;
          weeklyDishId = item.id;
        }
      }
      setState(() {
        _restaurant = restaurant;
        _menuItems = menuItems;
        _categories = categories;
        _activeCombo = combo;
        _menuItemEngagement = engagement;
        _weeklyDishId = weeklyDishId;
        _isLoading = false;
      });
      unawaited(_loadRestaurantRouteEstimate());
    } catch (error) {
      debugPrint('Erro ao carregar detalhes do restaurante: $error');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível carregar este restaurante. Tente novamente.',
          ),
        ),
      );
    }
    _subscribeToDishEngagement();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOpenHighlightedDish();
    });
  }

  Future<void> _loadRestaurantRouteEstimate() async {
    final restaurant = _restaurant;
    final user = _supabase.auth.currentUser;
    if (restaurant == null ||
        user == null ||
        restaurant.latitude == null ||
        restaurant.longitude == null) {
      return;
    }

    setState(() => _loadingRestaurantRoute = true);
    try {
      final address = await _supabase
          .from('user_addresses')
          .select('latitude, longitude, is_default, updated_at')
          .eq('user_id', user.id)
          .order('is_default', ascending: false)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final originLat = (address?['latitude'] as num?)?.toDouble();
      final originLng = (address?['longitude'] as num?)?.toDouble();
      if (originLat == null || originLng == null) return;

      final route = await MapsRouteService.getCachedRouteInfo(
        cacheKey: 'restaurant-detail-${restaurant.id}',
        origin: LatLng(originLat, originLng),
        destination: LatLng(restaurant.latitude!, restaurant.longitude!),
      );
      if (!mounted) return;
      setState(() {
        _restaurantRouteInfo = route?.isFallback == true ? null : route;
      });
    } catch (error) {
      debugPrint('Erro ao calcular rota do restaurante: $error');
    } finally {
      if (mounted) setState(() => _loadingRestaurantRoute = false);
    }
  }

  void _subscribeToDishEngagement() {
    _dishEngagementChannel?.unsubscribe();
    final itemIds = _menuItems.map((item) => item.id).toSet();
    if (itemIds.isEmpty) return;
    _dishEngagementChannel = _supabase.channel(
      'restaurant-dish-engagement-${widget.restaurantId}',
    );

    void refresh(PostgresChangePayload payload, String key) {
      final row = payload.newRecord.isNotEmpty
          ? payload.newRecord
          : payload.oldRecord;
      final itemId = row[key]?.toString() ?? '';
      if (itemIds.contains(itemId)) {
        unawaited(_refreshDishEngagement(itemId));
      }
    }

    _dishEngagementChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'menu_item_reviews',
          callback: (payload) => refresh(payload, 'menu_item_id'),
        )
        .subscribe();
  }

  Future<void> _refreshDishEngagement(String itemId) async {
    if (_engagementBusyItems.contains(itemId)) return;
    final engagement = await _restaurantService.getMenuItemEngagement([itemId]);
    if (!mounted) return;
    setState(() {
      _menuItemEngagement[itemId] = engagement[itemId] ?? {};
    });
  }

  void _maybeOpenHighlightedDish() {
    if (!mounted || _isLoading) return;

    final dishId = widget.highlightDishId?.trim();
    if (dishId == null || dishId.isEmpty || _autoOpenedDishId == dishId) {
      return;
    }

    MenuItem? matchedItem;
    for (final item in _menuItems) {
      if (item.id == dishId) {
        matchedItem = item;
        break;
      }
    }
    if (matchedItem == null) return;

    _autoOpenedDishId = dishId;
    unawaited(_showMenuItemDetails(matchedItem));
  }

  Future<void> _loadFavoriteState() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final favorite = await _supabase
          .from('favorites')
          .select('restaurant_id')
          .eq('user_id', user.id)
          .eq('restaurant_id', widget.restaurantId)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _isFavorite = favorite != null);
    } catch (_) {
      try {
        final profile = await _supabase
            .from('profiles')
            .select('settings')
            .eq('id', user.id)
            .maybeSingle();
        final settings =
            (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
        final favorites =
            (settings['favorites'] as List?)?.cast<String>() ?? <String>[];
        if (!mounted) return;
        setState(() => _isFavorite = favorites.contains(widget.restaurantId));
      } catch (_) {}
    }
  }

  Future<void> _toggleFavorite() async {
    final user = _supabase.auth.currentUser;
    if (user == null || _favoriteBusy) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _favoriteBusy = true);
    final nextValue = !_isFavorite;
    try {
      if (nextValue) {
        await _supabase.from('favorites').insert({
          'user_id': user.id,
          'restaurant_id': widget.restaurantId,
        });
      } else {
        await _supabase
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('restaurant_id', widget.restaurantId);
      }
      if (!mounted) return;
      setState(() => _isFavorite = nextValue);
      await SoundController.instance.click();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            nextValue
                ? 'Restaurante adicionado aos favoritos'
                : 'Restaurante removido dos favoritos',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível atualizar os favoritos agora.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _favoriteBusy = false);
      }
    }
  }

  List<MenuItem> get _filteredMenuItems {
    final query = _searchQuery.trim().toLowerCase();
    return _menuItems.where((item) {
      final matchesCategory =
          _selectedCategory == null || item.category == _selectedCategory;
      final matchesSearch =
          query.isEmpty || item.name.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  Future<void> _addToCart(
    MenuItem item, {
    int quantity = 1,
    List<String> extras = const [],
    double extrasPrice = 0,
    String? observations,
  }) async {
    if (_restaurant?.isOpen == false) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este restaurante esta fechado no momento.'),
        ),
      );
      return;
    }

    final cartService = Provider.of<CartService>(context, listen: false);
    await cartService.addItem(
      item,
      quantity: quantity,
      extras: extras,
      extrasPrice: extrasPrice,
      observations: observations,
      restaurantName: _restaurant?.name,
    );
    await SoundController.instance.click();
    if (!mounted) return;
    _showMiniCartSheet(cartService);
  }

  Future<void> _toggleDishFavorite(MenuItem item) async {
    if (_engagementBusyItems.contains(item.id)) return;
    if (_supabase.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Entre na sua conta para guardar o prato nos favoritos.',
          ),
        ),
      );
      return;
    }
    final previous = Map<String, dynamic>.from(
      _menuItemEngagement[item.id] ?? const {},
    );
    final wasLiked = previous['favorite_by_current_user'] == true;
    setState(() {
      _engagementBusyItems.add(item.id);
      _menuItemEngagement[item.id] = {
        ...previous,
        'favorite_by_current_user': !wasLiked,
      };
    });
    final ok = await _restaurantService.toggleMenuItemFavorite(item.id);
    if (ok) {
      final engagement = await _restaurantService.getMenuItemEngagement([
        item.id,
      ]);
      if (mounted) {
        setState(() {
          _menuItemEngagement[item.id] = engagement[item.id] ?? {};
          _recalculateWeeklyDish();
        });
      }
    } else if (mounted) {
      setState(() => _menuItemEngagement[item.id] = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel atualizar os favoritos agora.'),
        ),
      );
    }
    if (mounted) setState(() => _engagementBusyItems.remove(item.id));
  }

  Future<bool> _toggleDishLike(MenuItem item) async {
    if (_engagementBusyItems.contains(item.id)) return false;
    final user = _supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entre na sua conta para gostar do prato.'),
        ),
      );
      return false;
    }
    final previous = Map<String, dynamic>.from(
      _menuItemEngagement[item.id] ?? const {},
    );
    final liked = previous['liked_by_current_user'] == true;
    final count = (previous['likes'] as num?)?.toInt() ?? 0;
    setState(() {
      _engagementBusyItems.add(item.id);
      _menuItemEngagement[item.id] = {
        ...previous,
        'likes': (count + (liked ? -1 : 1)).clamp(0, 1 << 30),
        'liked_by_current_user': !liked,
      };
    });
    final ok = await _restaurantService.toggleMenuItemLike(item.id);
    if (mounted && ok) {
      // Realtime can notify before the committed row is visible to SELECT.
      // Reconcile only after the write completes so zero cannot overwrite the
      // optimistic state.
      final refreshed = await _restaurantService.getMenuItemEngagement([
        item.id,
      ]);
      if (mounted) {
        setState(() {
          _menuItemEngagement[item.id] =
              refreshed[item.id] ?? _menuItemEngagement[item.id] ?? previous;
        });
      }
    } else if (mounted && !ok) {
      setState(() => _menuItemEngagement[item.id] = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível registrar o gosto agora.'),
        ),
      );
    }
    if (mounted) setState(() => _engagementBusyItems.remove(item.id));
    return ok;
  }

  void _recalculateWeeklyDish() {
    String? bestId;
    var bestLikes = 0;
    for (final item in _menuItems) {
      final likes =
          (_menuItemEngagement[item.id]?['likes'] as num?)?.toInt() ?? 0;
      if (likes > bestLikes) {
        bestLikes = likes;
        bestId = item.id;
      }
    }
    _weeklyDishId = bestId;
  }

  Future<void> _openDishComment(MenuItem item) async {
    await _showDishReviewDialog(item);
    final engagement = await _restaurantService.getMenuItemEngagement([
      item.id,
    ]);
    if (!mounted) return;
    setState(() {
      _menuItemEngagement[item.id] = engagement[item.id] ?? {};
    });
  }

  String? get _topDishName {
    if (_menuItems.isEmpty) return null;
    final ranked = List<MenuItem>.from(_menuItems)
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return ranked.first.name;
  }

  Future<void> _showShareRestaurantSheet() async {
    final restaurant = _restaurant;
    if (restaurant == null) return;

    final invite = await _restaurantShareService.createInvite(
      restaurant: restaurant,
      source: 'restaurant_page',
      topDishName: _topDishName,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Compartilhar este restaurante',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderGray),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invite.landingTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(invite.landingSubtitle),
                    const SizedBox(height: 10),
                    const Text(
                      'Partilhe o restaurante com os seus amigos pelo DeliGo.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _shareRestaurantNative(invite),
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('Partilhar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyRestaurantLink(invite),
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('Copiar link'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRestaurantActions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Sobre o restaurante'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _showRestaurantAboutSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Partilhar restaurante'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showShareRestaurantSheet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('Ver QR Code'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showRestaurantQrCode();
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('Ver localização'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openRestaurantLocation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.report_problem_outlined),
              title: const Text('Denunciar problema'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showRestaurantReport();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openRestaurantAbout() {
    final id = widget.restaurantId.trim();
    if (id.isEmpty) return;
    context.push('/restaurant-profile/$id');
  }

  Future<void> _showRestaurantAboutSheet() async {
    final restaurant = _restaurant;
    if (restaurant == null || !mounted) return;
    final location = LocationDisplay.smartLocation(
      address: restaurant.address,
      neighborhood: restaurant.neighborhood,
      city: restaurant.city,
    );
    final reference = LocationDisplay.compactReference(
      address: restaurant.address,
      neighborhood: restaurant.neighborhood,
      city: restaurant.city,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundImage:
                        restaurant.imageUrl?.trim().isNotEmpty == true
                        ? NetworkImage(restaurant.imageUrl!.trim())
                        : null,
                    child: restaurant.imageUrl?.trim().isNotEmpty == true
                        ? null
                        : const Icon(Icons.storefront_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          restaurant.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '⭐ ${restaurant.rating?.toStringAsFixed(1) ?? 'Novo'}  ·  ${restaurant.isOpen ? 'Aberto' : 'Fechado'}  ·  ${restaurant.deliveryTime ?? 10} min preparo',
                          style: const TextStyle(
                            color: AppColors.neutralGray,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _aboutSection(
                'Sobre',
                restaurant.description?.trim().isNotEmpty == true
                    ? restaurant.description!.trim()
                    : 'Parceiro DeliGo MZ',
              ),
              _aboutSection(
                'Informações',
                '🍽️ Restaurante\n💰 \$\$ · Preço médio acessível\n🕐 ${restaurant.deliveryTime ?? 10} min · preparação média',
              ),
              _aboutSection(
                'Horário',
                '${restaurant.isOpen ? '🟢 Aberto agora' : '🔴 Fechado'}\nHoje: 08:00 – 22:00\nVer todos os horários ›',
              ),
              _aboutSection(
                'Localização',
                '📍 $location\nReferência: $reference',
              ),
              _aboutSection(
                'Contacto',
                '📞 ${restaurant.phone?.trim().isNotEmpty == true ? restaurant.phone!.trim() : 'Contacto não disponível'}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aboutSection(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(height: 1.45, color: AppColors.neutralGray),
          ),
        ],
      ),
    );
  }

  Future<void> _showRestaurantQrCode() async {
    final restaurant = _restaurant;
    if (restaurant == null || !mounted) return;
    final link = _publicShareService.restaurantLink(restaurant.id);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(restaurant.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Leia para consultar o menu'),
            const SizedBox(height: 16),
            QrImageView(data: link, size: 220),
            const SizedBox(height: 12),
            SelectableText(link, textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Copiar link'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openRestaurantLocation() async {
    final restaurant = _restaurant;
    if (restaurant == null) return;
    final uri = restaurant.latitude != null && restaurant.longitude != null
        ? Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=${restaurant.latitude},${restaurant.longitude}',
          )
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(restaurant.address)}',
          );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showRestaurantReport() async {
    final descriptionController = TextEditingController();
    XFile? selectedImage;
    String selectedReason = 'Outro problema';
    final picker = ImagePicker();
    final report = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Denunciar problema'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Motivo'),
                  // Use the dialog's real width. Without this, the longest
                  // menu item can force a Row inside the dropdown past the
                  // available width on small Android screens.
                  isExpanded: true,
                  items:
                      const [
                            'Restaurante fechado permanentemente',
                            'Localização incorreta',
                            'Horário incorreto',
                            'Informação ou fotografia incorreta',
                            'Comportamento inadequado',
                            'Outro problema',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  value: selectedReason,
                  onChanged: (value) => setDialogState(
                    () => selectedReason = value ?? selectedReason,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Descrição (opcional)',
                    hintText: 'Explique o problema',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final image = await picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (image != null) {
                      setDialogState(() => selectedImage = image);
                    }
                  },
                  icon: const Icon(Icons.photo_camera_back_outlined),
                  label: Text(
                    selectedImage == null
                        ? 'Adicionar fotografia'
                        : 'Fotografia seleccionada',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, {
                  'reason': selectedReason,
                  'description': descriptionController.text.trim(),
                  'image': selectedImage,
                });
              },
              child: const Text('Enviar denúncia'),
            ),
          ],
        ),
      ),
    );
    descriptionController.dispose();
    if (!mounted || report == null) return;
    try {
      final restaurant = _restaurant;
      if (restaurant == null) return;
      final reason = report['reason']?.toString() ?? 'Outro problema';
      final description = report['description']?.toString() ?? '';
      final caseId = await _supabase
          .schema('core')
          .rpc(
            'create_support_case',
            params: {
              'p_app_slug': 'deligo',
              'p_subject': 'Denúncia sobre restaurante: $reason',
              'p_description': '${restaurant.name}\n$description',
              'p_category': 'restaurant_report',
              'p_priority': 'normal',
              'p_entity_schema': 'public',
              'p_entity_table': 'restaurants',
              'p_entity_id': restaurant.id,
            },
          );
      final image = report['image'] as XFile?;
      final attachments = <Map<String, dynamic>>[];
      final userId = _supabase.auth.currentUser?.id;
      if (image != null && userId != null) {
        final path =
            '$userId/support/$caseId/${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        await _supabase.storage
            .from('chat-attachments')
            .uploadBinary(path, await image.readAsBytes());
        attachments.add({
          'path': path,
          'name': image.name,
          'mime_type': image.mimeType ?? 'image/*',
        });
      }
      await _supabase
          .schema('core')
          .rpc(
            'add_support_message_with_attachments',
            params: {
              'p_case_id': caseId,
              'p_body':
                  'Motivo: $reason\n${description.isEmpty ? 'Sem descrição adicional.' : description}',
              'p_is_internal': false,
              'p_attachments': attachments,
            },
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Denúncia enviada ao suporte.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível enviar a denúncia agora.'),
        ),
      );
    }
  }

  Widget _shareActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: AppColors.primaryRed),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: const Color(0xFFF8F1F1),
      side: const BorderSide(color: Color(0xFFFFD7D7)),
    );
  }

  Future<void> _copyRestaurantLink(RestaurantShareInvite invite) async {
    await Clipboard.setData(ClipboardData(text: invite.magicLink));
    await _restaurantShareService.recordEvent(
      shareId: invite.shareId,
      eventType: 'magic_link_copied',
      metadata: {'share_token': invite.shareToken},
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copiado.')));
  }

  Future<void> _shareRestaurantNative(RestaurantShareInvite invite) async {
    await _restaurantShareService.recordEvent(
      shareId: invite.shareId,
      eventType: 'share_sheet_opened',
      metadata: {'share_token': invite.shareToken},
    );
    await Share.share(invite.message, subject: 'Restaurante no DeliGo');
  }

  Future<void> _copyPublicLink(String link, String successMessage) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  Future<void> _sharePublicLinkToChannel({
    required String channel,
    required String text,
    required String link,
  }) async {
    final encodedText = Uri.encodeComponent(text);
    final encodedLink = Uri.encodeComponent(link);
    Uri? uri;

    switch (channel) {
      case 'whatsapp':
        uri = Uri.parse('https://wa.me/?text=$encodedText');
        break;
      case 'facebook':
        if (!_publicShareService.hasWebBaseUrl) {
          await _copyPublicLink(
            text,
            'Configure um dominio publico de share. Texto copiado por enquanto.',
          );
          return;
        }
        uri = Uri.parse(
          'https://www.facebook.com/sharer/sharer.php?u=$encodedLink',
        );
        break;
      case 'instagram':
      case 'tiktok':
        await _copyPublicLink(
          text,
          channel == 'instagram'
              ? 'Texto e link do prato copiados para o story.'
              : 'Texto e link do prato copiados para o post/video.',
        );
        return;
    }

    if (uri != null) {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        await _copyPublicLink(text, 'Nao abriu o app externo. Texto copiado.');
      }
    }
  }

  Future<void> _showShareDishSheet(MenuItem item) async {
    final restaurant = _restaurant;
    if (restaurant == null) return;

    final link = _publicShareService.dishLink(
      restaurantId: restaurant.id,
      dishId: item.id,
    );
    final text = _publicShareService.dishMessage(
      dishName: item.name,
      restaurantName: restaurant.name,
      link: link,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Compartilhar ${item.name}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderGray),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item.price.toStringAsFixed(0)} MZN • ${restaurant.name}',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      link,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.neutralGray,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _shareActionChip(
                    icon: Icons.chat,
                    label: 'WhatsApp',
                    onTap: () => _sharePublicLinkToChannel(
                      channel: 'whatsapp',
                      text: text,
                      link: link,
                    ),
                  ),
                  _shareActionChip(
                    icon: Icons.facebook,
                    label: 'Facebook',
                    onTap: () => _sharePublicLinkToChannel(
                      channel: 'facebook',
                      text: text,
                      link: link,
                    ),
                  ),
                  _shareActionChip(
                    icon: Icons.auto_awesome,
                    label: 'Instagram',
                    onTap: () => _sharePublicLinkToChannel(
                      channel: 'instagram',
                      text: text,
                      link: link,
                    ),
                  ),
                  _shareActionChip(
                    icon: Icons.play_circle_outline,
                    label: 'TikTok',
                    onTap: () => _sharePublicLinkToChannel(
                      channel: 'tiktok',
                      text: text,
                      link: link,
                    ),
                  ),
                  _shareActionChip(
                    icon: Icons.link_rounded,
                    label: 'Copiar link',
                    onTap: () =>
                        _copyPublicLink(link, 'Link do prato copiado.'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ensureMenuItemReviewsLoaded(String menuItemId) async {
    if (_menuItemReviews.containsKey(menuItemId) ||
        _loadingReviewItems.contains(menuItemId)) {
      return;
    }
    _loadingReviewItems.add(menuItemId);
    final reviews = await _restaurantService.getMenuItemReviews(menuItemId);
    _loadingReviewItems.remove(menuItemId);
    if (!mounted) return;
    setState(() {
      _menuItemReviews[menuItemId] = reviews;
    });
  }

  Future<void> _loadFirstMenuItemReviews(String menuItemId) async {
    if (_loadingReviewItems.contains(menuItemId)) return;
    _loadingReviewItems.add(menuItemId);
    final reviews = await _restaurantService.getMenuItemReviews(
      menuItemId,
      page: 0,
      pageSize: 20,
    );
    _loadingReviewItems.remove(menuItemId);
    if (!mounted) return;
    setState(() => _menuItemReviews[menuItemId] = reviews);
  }

  Future<void> _loadReviewReplies(String reviewId) async {
    if (_menuItemReplies.containsKey(reviewId) ||
        !_loadingReplyReviews.add(reviewId)) {
      return;
    }
    try {
      final replies = await _socialReviewService.getReplies(
        'menu_item',
        reviewId,
      );
      if (!mounted) return;
      setState(() => _menuItemReplies[reviewId] = replies);
    } finally {
      _loadingReplyReviews.remove(reviewId);
    }
  }

  Future<void> _openReviewRepliesOrComposer(MenuItemReview review) async {
    final cachedReplies = _menuItemReplies[review.id];
    if (cachedReplies == null) {
      try {
        await _loadReviewReplies(review.id);
      } catch (error) {
        debugPrint('Erro ao carregar respostas: $error');
        if (mounted) {
          setState(() {
            _menuItemReplies[review.id] = const <Map<String, dynamic>>[];
          });
        }
      }
    }
    if (!mounted) return;
    final replies =
        _menuItemReplies[review.id] ?? const <Map<String, dynamic>>[];
    setState(() {
      _expandedReviewReplies.add(review.id);
      if (replies.isEmpty) {
        _activeReplyReviewId = review.id;
        _activeReplyToName = review.reviewerName;
        _replyDraft = '';
      }
    });
  }

  Future<void> _showDishReviewDialog(MenuItem item) async {
    final pageContext = context;
    int rating = 5;
    bool submitting = false;
    final selectedTags = <String>{};
    final commentController = TextEditingController();
    XFile? selectedImage;
    final picker = ImagePicker();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, dialogSetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Avaliar o prato',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        item.name,
                        style: const TextStyle(
                          color: AppColors.neutralGray,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: submitting ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 2,
                    children: List.generate(5, (index) {
                      return IconButton(
                        onPressed: submitting
                            ? null
                            : () => dialogSetState(() => rating = index + 1),
                        icon: Icon(
                          index < rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 30,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$rating de 5  •  ${rating >= 4 ? 'Muito bom!' : 'Conte-nos como podemos melhorar'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: commentController,
                    minLines: 3,
                    maxLines: 4,
                    maxLength: 500,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Partilhe a sua opinião sobre este prato...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.primaryRed,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.primaryRed,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children:
                          [
                            'Sabor',
                            'Qualidade',
                            'Tamanho',
                            'Apresentação',
                            'Preço',
                            'Entrega',
                          ].map((tag) {
                            return FilterChip(
                              label: Text(
                                tag,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: selectedTags.contains(tag),
                              onSelected: submitting
                                  ? null
                                  : (_) {
                                      dialogSetState(() {
                                        if (!selectedTags.add(tag)) {
                                          selectedTags.remove(tag);
                                        }
                                      });
                                    },
                            );
                          }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (selectedImage != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FutureBuilder<Uint8List>(
                        future: selectedImage!.readAsBytes(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Container(
                              height: 84,
                              width: double.infinity,
                              color: AppColors.lightGray,
                              alignment: Alignment.center,
                              child: const CircularProgressIndicator(),
                            );
                          }
                          return Image.memory(
                            snapshot.data!,
                            height: 84,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(38),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: submitting
                              ? null
                              : () async {
                                  final picked = await picker.pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 85,
                                    maxWidth: 1600,
                                  );
                                  if (picked == null) return;
                                  dialogSetState(() => selectedImage = picked);
                                },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(
                            selectedImage == null
                                ? 'Adicionar foto (opcional)'
                                : 'Trocar foto',
                          ),
                        ),
                      ),
                      if (selectedImage != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: submitting
                              ? null
                              : () =>
                                    dialogSetState(() => selectedImage = null),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                ),
                onPressed: submitting
                    ? null
                    : () async {
                        bool closedDialog = false;
                        String? feedbackMessage;
                        Color? feedbackColor;
                        final focusScope = FocusScope.of(pageContext);
                        final messenger = ScaffoldMessenger.of(pageContext);
                        final navigator = Navigator.of(pageContext);
                        focusScope.unfocus();
                        try {
                          dialogSetState(() => submitting = true);
                          String? imageUrl;
                          if (selectedImage != null) {
                            final user = _supabase.auth.currentUser;
                            if (user != null) {
                              imageUrl = await _restaurantService
                                  .uploadMenuItemReviewImage(
                                    file: selectedImage!,
                                    reviewerId: user.id,
                                  )
                                  .timeout(const Duration(seconds: 20));
                            }
                          }
                          final success = await _restaurantService
                              .submitMenuItemReview(
                                menuItemId: item.id,
                                rating: rating,
                                comment: [
                                  commentController.text.trim(),
                                  ...selectedTags.map((tag) => '#$tag'),
                                ].where((part) => part.isNotEmpty).join(' '),
                                imageUrl: imageUrl,
                              )
                              .timeout(const Duration(seconds: 20));
                          if (!mounted) return;
                          if (success) {
                            final reviews = await _restaurantService
                                .getMenuItemReviews(item.id)
                                .timeout(const Duration(seconds: 20));
                            if (!mounted) return;
                            setState(() {
                              _menuItemReviews[item.id] = reviews;
                            });
                            await SoundController.instance.success();
                            feedbackMessage = 'Avaliacao enviada com sucesso.';
                            feedbackColor = AppColors.successGreen;
                            navigator.pop();
                            closedDialog = true;
                          } else {
                            await SoundController.instance.error();
                            feedbackMessage =
                                'Nao foi possivel enviar a sua avaliacao agora.';
                          }
                        } on TimeoutException {
                          await SoundController.instance.error();
                          feedbackMessage =
                              'A publicacao demorou demais. Tente novamente.';
                        } catch (_) {
                          await SoundController.instance.error();
                          feedbackMessage =
                              'Nao foi possivel enviar a sua avaliacao agora.';
                        } finally {
                          if (mounted && !closedDialog) {
                            dialogSetState(() => submitting = false);
                          }
                          final message = feedbackMessage;
                          if (mounted && message != null) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(message),
                                backgroundColor: feedbackColor,
                              ),
                            );
                          }
                        }
                      },
                child: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Publicar avaliação'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMenuItemDetails(MenuItem item) async {
    final dishId = item.id.trim();
    debugPrint('[DISH_NAV] request dishId=$dishId');
    if (dishId.isEmpty || !_activeDishDetailIds.add(dishId)) {
      debugPrint('[DISH_NAV] blocked already active dishId=$dishId');
      return;
    }
    debugPrint('[DISH_NAV] opening dishId=$dishId');
    try {
      await _loadFirstMenuItemReviews(item.id);
      if (!_menuItemOptions.containsKey(item.id)) {
        final options = await _restaurantService.getMenuItemOptions(item.id);
        if (mounted) {
          setState(() => _menuItemOptions[item.id] = options);
        }
      }
      if (!_menuItemGallery.containsKey(item.id)) {
        final gallery = await _restaurantService.getMenuItemGallery(item.id);
        if (mounted) {
          setState(() => _menuItemGallery[item.id] = gallery);
        }
      }
      if (!mounted) return;

      int sortIndex = 0;
      bool onlyWithPhotos = false;
      int reviewPage = 0;
      bool loadingMoreReviews = false;
      bool hasMoreReviews = true;
      int quantity = 1;
      final selectedChoiceIds = <String>{};
      final observationsController = TextEditingController();
      var modalDishLikes =
          (_menuItemEngagement[item.id]?['likes'] as num?)?.toInt() ?? 0;
      var modalDishLiked =
          _menuItemEngagement[item.id]?['liked_by_current_user'] == true;
      final dishReviewsKey = GlobalKey();

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.96,
          minChildSize: 0.62,
          maxChildSize: 0.98,
          builder: (context, scrollController) => StatefulBuilder(
            builder: (context, modalSetState) {
              final reviews =
                  _menuItemReviews[item.id] ?? const <MenuItemReview>[];
              final optionGroups =
                  _menuItemOptions[item.id] ?? const <Map<String, dynamic>>[];
              final engagement = _menuItemEngagement[item.id] ?? const {};
              final selectedChoices = optionGroups
                  .expand((group) => (group['choices'] as List? ?? const []))
                  .whereType<Map>()
                  .where(
                    (choice) =>
                        selectedChoiceIds.contains(choice['id'].toString()),
                  )
                  .toList();
              final extrasPrice = selectedChoices.fold<double>(
                0,
                (sum, choice) =>
                    sum + ((choice['price_delta'] as num?)?.toDouble() ?? 0),
              );
              final totalPrice = (item.price + extrasPrice) * quantity;
              final dishLikes = modalDishLikes;
              final dishLiked = modalDishLiked;
              final galleryUrls = <String>{
                if (item.imageUrl?.trim().isNotEmpty == true)
                  item.imageUrl!.trim(),
                ...(_menuItemGallery[item.id] ?? const <String>[]),
                ...reviews
                    .map((review) => review.imageUrl?.trim() ?? '')
                    .where((url) => url.isNotEmpty),
              }.toList();
              final averageRating = reviews.isNotEmpty
                  ? reviews
                            .map((review) => review.rating.toDouble())
                            .reduce((a, b) => a + b) /
                        reviews.length
                  : item.rating;
              List<MenuItemReview> visibleReviews = List.of(reviews);
              if (onlyWithPhotos) {
                visibleReviews = visibleReviews
                    .where(
                      (review) =>
                          review.imageUrl != null &&
                          review.imageUrl!.trim().isNotEmpty,
                    )
                    .toList();
              }
              if (sortIndex == 0) {
                visibleReviews.sort(
                  (a, b) => b.createdAt.compareTo(a.createdAt),
                );
              } else if (sortIndex == 1) {
                visibleReviews.sort((a, b) {
                  final verifiedCompare =
                      (b.isVerifiedReviewer ? 1 : 0) -
                      (a.isVerifiedReviewer ? 1 : 0);
                  if (verifiedCompare != 0) return verifiedCompare;
                  final likesCompare = b.likesCount.compareTo(a.likesCount);
                  if (likesCompare != 0) return likesCompare;
                  final ratingCompare = b.rating.compareTo(a.rating);
                  if (ratingCompare != 0) return ratingCompare;
                  return b.createdAt.compareTo(a.createdAt);
                });
              }

              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollUpdateNotification &&
                              notification.metrics.pixels >=
                                  notification.metrics.maxScrollExtent - 420 &&
                              !loadingMoreReviews &&
                              hasMoreReviews) {
                            loadingMoreReviews = true;
                            final nextPage = reviewPage + 1;
                            unawaited(() async {
                              final next = await _restaurantService
                                  .getMenuItemReviews(
                                    item.id,
                                    page: nextPage,
                                    pageSize: 20,
                                    onlyWithPhotos: onlyWithPhotos,
                                  );
                              if (!context.mounted) return;
                              modalSetState(() {
                                loadingMoreReviews = false;
                                if (next.isEmpty) {
                                  hasMoreReviews = false;
                                } else {
                                  reviewPage = nextPage;
                                  final current =
                                      _menuItemReviews[item.id] ?? const [];
                                  _menuItemReviews[item.id] = [
                                    ...current,
                                    ...next.where(
                                      (review) => !current.any(
                                        (r) => r.id == review.id,
                                      ),
                                    ),
                                  ];
                                }
                              });
                            }());
                          }
                          return false;
                        },
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
                          children: [
                            Stack(
                              children: [
                                GestureDetector(
                                  onTap: galleryUrls.isEmpty
                                      ? null
                                      : () => _showDishPhotoViewer(
                                          galleryUrls,
                                          0,
                                        ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child:
                                        item.imageUrl != null &&
                                            item.imageUrl!.isNotEmpty
                                        ? Container(
                                            constraints: const BoxConstraints(
                                              minHeight: 220,
                                              maxHeight: 320,
                                            ),
                                            width: double.infinity,
                                            color: const Color(0xFFF7F7F7),
                                            child: CachedNetworkImage(
                                              imageUrl: item.imageUrl!,
                                              fit: BoxFit.contain,
                                              errorWidget:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) =>
                                                      _buildItemImageFallback(),
                                            ),
                                          )
                                        : _buildItemImageFallback(),
                                  ),
                                ),
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: _buildDishFavoriteButton(
                                    item,
                                    compact: false,
                                  ),
                                ),
                              ],
                            ),
                            if (galleryUrls.length > 1) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 64,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: galleryUrls.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) => InkWell(
                                    onTap: () => _showDishPhotoViewer(
                                      galleryUrls,
                                      index,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        width: 72,
                                        color: const Color(0xFFF2F2F2),
                                        child: CachedNetworkImage(
                                          imageUrl: galleryUrls[index],
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    final previousLiked = modalDishLiked;
                                    final previousLikes = modalDishLikes;
                                    modalSetState(() {
                                      modalDishLiked = !previousLiked;
                                      modalDishLikes =
                                          previousLikes +
                                          (modalDishLiked ? 1 : -1);
                                    });
                                    final ok = await _toggleDishLike(item);
                                    if (!ok) {
                                      modalSetState(() {
                                        modalDishLiked = previousLiked;
                                        modalDishLikes = previousLikes;
                                      });
                                    }
                                  },
                                  icon: Icon(
                                    dishLiked
                                        ? Icons.thumb_up_alt_rounded
                                        : Icons.thumb_up_alt_outlined,
                                    color: dishLiked
                                        ? AppColors.primaryRed
                                        : AppColors.neutralGray,
                                  ),
                                  label: Text(
                                    '${formatCompactNumber(dishLikes)} gostos',
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () async {
                                    await _openDishComment(item);
                                    modalSetState(() {});
                                  },
                                  icon: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                  ),
                                  label: Text(
                                    '${formatCompactNumber(reviews.length)} comentarios',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              key: dishReviewsKey,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        item.description?.trim().isNotEmpty ==
                                                true
                                            ? item.description!
                                            : 'Prato preparado com carinho pelo restaurante.',
                                        style: const TextStyle(
                                          color: AppColors.neutralGray,
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryRed.withValues(
                                      alpha: 0.10,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    '${item.price.toStringAsFixed(0)} MZN',
                                    style: const TextStyle(
                                      color: AppColors.primaryRed,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildInfoChip(
                                  Icons.star,
                                  averageRating > 0
                                      ? averageRating.toStringAsFixed(1)
                                      : 'Novo',
                                  Colors.amber,
                                ),
                                GestureDetector(
                                  onTap: () {
                                    final target =
                                        dishReviewsKey.currentContext;
                                    if (target != null) {
                                      Scrollable.ensureVisible(
                                        target,
                                        duration: const Duration(
                                          milliseconds: 350,
                                        ),
                                        curve: Curves.easeOut,
                                      );
                                    }
                                  },
                                  child: _buildInfoChip(
                                    Icons.rate_review,
                                    '${reviews.length} avaliações',
                                    AppColors.primaryRed,
                                  ),
                                ),
                                _buildInfoChip(
                                  Icons.access_time,
                                  '${item.prepTimeMinutes} min',
                                  AppColors.darkGray,
                                ),
                                if ((item.category ?? '').trim().isNotEmpty)
                                  _buildInfoChip(
                                    Icons.category,
                                    item.category!,
                                    AppColors.darkGray,
                                  ),
                                if (item.stockQuantity <= 0)
                                  _buildInfoChip(
                                    Icons.warning_amber_rounded,
                                    'Indisponível',
                                    AppColors.alertRed,
                                  ),
                              ],
                            ),
                            if (optionGroups.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              const Text(
                                'Personaliza o teu pedido',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...optionGroups.map((group) {
                                final groupId = group['id'].toString();
                                final min =
                                    (group['min_selections'] as num?)
                                        ?.toInt() ??
                                    0;
                                final max =
                                    (group['max_selections'] as num?)
                                        ?.toInt() ??
                                    1;
                                final choices =
                                    (group['choices'] as List? ?? const [])
                                        .map(
                                          (raw) => Map<String, dynamic>.from(
                                            raw as Map,
                                          ),
                                        )
                                        .toList();
                                final selectedForGroup = choices
                                    .where(
                                      (choice) => selectedChoiceIds.contains(
                                        choice['id'].toString(),
                                      ),
                                    )
                                    .length;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${group['name']}${min > 0 ? ' · obrigatório' : ' · opcional'}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: choices.map((choice) {
                                          final choiceId = choice['id']
                                              .toString();
                                          final selected = selectedChoiceIds
                                              .contains(choiceId);
                                          final delta =
                                              (choice['price_delta'] as num?)
                                                  ?.toDouble() ??
                                              0;
                                          return FilterChip(
                                            label: Text(
                                              '${choice['name']}${delta > 0 ? ' +${delta.toStringAsFixed(0)} MZN' : ''}',
                                            ),
                                            selected: selected,
                                            onSelected: (_) =>
                                                modalSetState(() {
                                                  if (selected) {
                                                    selectedChoiceIds.remove(
                                                      choiceId,
                                                    );
                                                  } else if (selectedForGroup <
                                                      max) {
                                                    selectedChoiceIds.add(
                                                      choiceId,
                                                    );
                                                  }
                                                }),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text(
                                  'Quantidade',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: quantity > 1
                                      ? () => modalSetState(() => quantity -= 1)
                                      : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                Text(
                                  '$quantity',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      modalSetState(() => quantity += 1),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                            TextField(
                              controller: observationsController,
                              maxLength: 180,
                              decoration: InputDecoration(
                                labelText: 'Alguma observação?',
                                hintText: 'Ex.: sem cebola, pouco sal',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (reviews.isNotEmpty) ...[
                              _buildReviewSummary(
                                reviews: reviews,
                                averageRating: averageRating,
                              ),
                              const SizedBox(height: 12),
                            ],
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Avaliações e críticas',
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () async {
                                    await _showDishReviewDialog(item);
                                    if (!mounted) return;
                                    modalSetState(() {});
                                  },
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Avaliar prato'),
                                ),
                              ],
                            ),
                            if (reviews.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Mais recentes'),
                                    selected: sortIndex == 0,
                                    onSelected: (value) {
                                      modalSetState(() {
                                        sortIndex = 0;
                                        reviewPage = 0;
                                        hasMoreReviews = true;
                                      });
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text('Mais úteis'),
                                    selected: sortIndex == 1,
                                    onSelected: (value) {
                                      modalSetState(() {
                                        sortIndex = 1;
                                        reviewPage = 0;
                                        hasMoreReviews = true;
                                      });
                                    },
                                  ),
                                  FilterChip(
                                    label: const Text('Com foto'),
                                    selected: onlyWithPhotos,
                                    onSelected: (value) {
                                      modalSetState(() {
                                        onlyWithPhotos = value;
                                        reviewPage = 0;
                                        hasMoreReviews = true;
                                        _menuItemReviews[item.id] = const [];
                                      });
                                      unawaited(() async {
                                        final first = await _restaurantService
                                            .getMenuItemReviews(
                                              item.id,
                                              page: 0,
                                              pageSize: 20,
                                              onlyWithPhotos: value,
                                            );
                                        if (!context.mounted) return;
                                        modalSetState(() {
                                          _menuItemReviews[item.id] = first;
                                          hasMoreReviews = first.length == 20;
                                        });
                                      }());
                                    },
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            if (visibleReviews.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF9F9F9),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Text(
                                  'Este prato ainda não tem comentários. O cliente já pode deixar a primeira avaliação.',
                                  style: TextStyle(
                                    color: AppColors.neutralGray,
                                    height: 1.4,
                                  ),
                                ),
                              )
                            else
                              ...visibleReviews.map(
                                (review) => _buildReviewCard(review, item),
                              ),
                            const SizedBox(height: 8),
                            const SizedBox(height: 96),
                          ],
                        ),
                      ),
                    ),
                    AnimatedPadding(
                      duration: const Duration(milliseconds: 160),
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 16,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed:
                                item.isAvailable && _restaurant?.isOpen != false
                                ? () async {
                                    final missingRequired = optionGroups.any((
                                      group,
                                    ) {
                                      final min =
                                          (group['min_selections'] as num?)
                                              ?.toInt() ??
                                          0;
                                      final choices =
                                          (group['choices'] as List? ??
                                                  const [])
                                              .whereType<Map>()
                                              .where(
                                                (choice) =>
                                                    selectedChoiceIds.contains(
                                                      choice['id'].toString(),
                                                    ),
                                              )
                                              .length;
                                      return choices < min;
                                    });
                                    if (missingRequired) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Selecione as opções obrigatórias antes de continuar.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    final extras = selectedChoices
                                        .map(
                                          (choice) =>
                                              choice['name']?.toString() ?? '',
                                        )
                                        .where((name) => name.isNotEmpty)
                                        .toList();
                                    Navigator.pop(context);
                                    await _addToCart(
                                      item,
                                      quantity: quantity,
                                      extras: extras,
                                      extrasPrice: extrasPrice,
                                      observations:
                                          observationsController.text
                                              .trim()
                                              .isEmpty
                                          ? null
                                          : observationsController.text.trim(),
                                    );
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryRed,
                              foregroundColor: AppColors.cleanWhite,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            icon: const Icon(Icons.add_shopping_cart),
                            label: Text(
                              'Adicionar · ${totalPrice.toStringAsFixed(0)} MZN',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      debugPrint('[DISH_NAV] closed dishId=$dishId');
    } finally {
      _activeDishDetailIds.remove(dishId);
      debugPrint('[DISH_NAV] released dishId=$dishId');
    }
  }

  void _showMiniCartSheet(CartService cart) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => AnimatedBuilder(
        animation: cart,
        builder: (context, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Seu carrinho',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  '${cart.itemCount} itens deste restaurante',
                  style: const TextStyle(color: AppColors.neutralGray),
                ),
                const SizedBox(height: 16),
                if (cart.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'O carrinho ficou vazio.',
                      style: TextStyle(color: AppColors.neutralGray),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: cart.items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 18),
                      itemBuilder: (context, index) {
                        final cartItem = cart.items[index];
                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cartItem.menuItem.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${cartItem.quantity} x ${cartItem.menuItem.price.toStringAsFixed(0)} MZN',
                                    style: const TextStyle(
                                      color: AppColors.neutralGray,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                await SoundController.instance.click();
                                await cart.updateQuantity(
                                  index,
                                  cartItem.quantity + 1,
                                );
                              },
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            Text(
                              '${cartItem.quantity}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                await SoundController.instance.click();
                                if (cartItem.quantity > 1) {
                                  await cart.updateQuantity(
                                    index,
                                    cartItem.quantity - 1,
                                  );
                                } else {
                                  await cart.removeItem(index);
                                }
                              },
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Subtotal dos pratos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${cart.subtotal.toStringAsFixed(0)} MZN',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryRed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: cart.items.isEmpty
                        ? null
                        : () {
                            Navigator.pop(context);
                            this.context.push('/cart');
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: AppColors.cleanWhite,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('Abrir carrinho'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020817),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _restaurant == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Restaurante não encontrado'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            )
          : Consumer<CartService>(
              builder: (context, cart, child) => Stack(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => SizedBox(
                      width: constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : MediaQuery.sizeOf(context).width,
                      child: CustomScrollView(
                        slivers: [
                          SliverAppBar(
                            automaticallyImplyLeading: false,
                            expandedHeight: 180,
                            pinned: true,
                            backgroundColor: const Color(0xFF07152D),
                            foregroundColor: AppColors.cleanWhite,
                            flexibleSpace: FlexibleSpaceBar(
                              title: const SizedBox.shrink(),
                              titlePadding: const EdgeInsets.only(
                                left: 20,
                                right: 76,
                                bottom: 16,
                              ),
                              background: Stack(
                                fit: StackFit.expand,
                                children: [
                                  _restaurant!.imageUrl != null
                                      ? Container(
                                          color: const Color(0xFF111827),
                                          child: CachedNetworkImage(
                                            imageUrl: _restaurant!.imageUrl!,
                                            fit: BoxFit.contain,
                                          ),
                                        )
                                      : _buildHeaderPlaceholder(),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withValues(alpha: 0.10),
                                          Colors.black.withValues(alpha: 0.50),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 16,
                                    top: 52,
                                    child: IconButton.filled(
                                      onPressed: () => context.pop(),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.94),
                                        foregroundColor: AppColors.primaryRed,
                                        elevation: 10,
                                      ),
                                      icon: const Icon(
                                        Icons.arrow_back_rounded,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 70,
                                    top: 52,
                                    child: IconButton.filled(
                                      onPressed: _toggleFavorite,
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.white
                                            .withValues(alpha: .94),
                                        foregroundColor: AppColors.primaryRed,
                                      ),
                                      icon: _favoriteBusy
                                          ? const SizedBox(
                                              width: 19,
                                              height: 19,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Icon(
                                              _isFavorite
                                                  ? Icons.favorite
                                                  : Icons.favorite_border,
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 16,
                                    top: 52,
                                    child: PopupMenuButton<String>(
                                      tooltip: 'Mais opções',
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'about':
                                            unawaited(
                                              _showRestaurantAboutSheet(),
                                            );
                                            break;
                                          case 'share':
                                            _showShareRestaurantSheet();
                                            break;
                                          case 'qr':
                                            _showRestaurantQrCode();
                                            break;
                                          case 'location':
                                            _openRestaurantLocation();
                                            break;
                                          case 'report':
                                            _showRestaurantReport();
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'about',
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(Icons.info_outline),
                                            title: Text('Sobre o restaurante'),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'share',
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(Icons.share_outlined),
                                            title: Text(
                                              'Partilhar restaurante',
                                            ),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'qr',
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(Icons.qr_code_2),
                                            title: Text('Ver QR Code'),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'location',
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(
                                              Icons.location_on_outlined,
                                            ),
                                            title: Text('Ver localização'),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'report',
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(
                                              Icons.report_problem_outlined,
                                            ),
                                            title: Text('Denunciar problema'),
                                          ),
                                        ),
                                      ],
                                      child: const CircleAvatar(
                                        backgroundColor: Colors.white,
                                        foregroundColor: AppColors.primaryRed,
                                        child: Icon(Icons.more_vert),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    transform: Matrix4.translationValues(
                                      0,
                                      0,
                                      0,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 13,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                          color: const Color(0xFF0B1D3A),
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: .10,
                                          ),
                                          blurRadius: 22,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _restaurant!.name,
                                            style: const TextStyle(
                                              fontSize: 27,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (_restaurant!.isOpen
                                                        ? AppColors.successGreen
                                                        : AppColors.neutralGray)
                                                    .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            _restaurant!.isOpen
                                                ? 'Aberto'
                                                : 'Fechado',
                                            style: TextStyle(
                                              color: _restaurant!.isOpen
                                                  ? AppColors.successGreen
                                                  : AppColors.neutralGray,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Menu, pratos e ofertas deste restaurante',
                                    style: TextStyle(
                                      color: AppColors.neutralGray,
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  Wrap(
                                    spacing: 7,
                                    runSpacing: 7,
                                    children: [
                                      _buildInfoChip(
                                        Icons.star,
                                        _restaurant!.rating != null
                                            ? _restaurant!.rating!
                                                  .toStringAsFixed(1)
                                            : 'Novo',
                                        Colors.amber,
                                      ),
                                      _buildInfoChip(
                                        Icons.access_time,
                                        '${_restaurant!.deliveryTime ?? 25} min',
                                        AppColors.primaryRed,
                                      ),
                                      _buildInfoChip(
                                        Icons.delivery_dining,
                                        _restaurant!.deliveryFee == null
                                            ? 'Taxa no checkout'
                                            : '${_restaurant!.deliveryFee} MZN',
                                        AppColors.successGreen,
                                      ),
                                      if (_restaurantRouteInfo
                                              ?.distanceMeters !=
                                          null)
                                        _buildInfoChip(
                                          Icons.location_on_outlined,
                                          '${(_restaurantRouteInfo!.distanceMeters! / 1000).toStringAsFixed(1)} km',
                                          AppColors.primaryRed,
                                        ),
                                      if (_restaurantRouteInfo == null &&
                                          _loadingRestaurantRoute)
                                        _buildInfoChip(
                                          Icons.sync_rounded,
                                          'A calcular rota',
                                          AppColors.neutralGray,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 9),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        size: 18,
                                        color: AppColors.primaryRed,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          LocationDisplay.smartLocation(
                                            address: _restaurant!.address,
                                            neighborhood:
                                                _restaurant!.neighborhood,
                                            city: _restaurant!.city,
                                          ),
                                          style: const TextStyle(
                                            color: AppColors.neutralGray,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 7),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.place_outlined,
                                        size: 18,
                                        color: AppColors.primaryRed,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Referência: ${LocationDisplay.compactReference(address: _restaurant!.address, neighborhood: _restaurant!.neighborhood, city: _restaurant!.city)}',
                                          style: const TextStyle(
                                            color: AppColors.neutralGray,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if ((_restaurant!.description ?? '')
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    Text(
                                      LocationDisplay.smartDescription(
                                        description: _restaurant!.description,
                                        deliveryTimeMinutes:
                                            _restaurant!.deliveryTime,
                                        neighborhood: _restaurant!.neighborhood,
                                        city: _restaurant!.city,
                                        address: _restaurant!.address,
                                      ),
                                      style: const TextStyle(
                                        color: AppColors.neutralGray,
                                        height: 1.4,
                                      ),
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 14),
                                    Text(
                                      LocationDisplay.smartDescription(
                                        description: _restaurant!.description,
                                        deliveryTimeMinutes:
                                            _restaurant!.deliveryTime,
                                        neighborhood: _restaurant!.neighborhood,
                                        city: _restaurant!.city,
                                        address: _restaurant!.address,
                                      ),
                                      style: const TextStyle(
                                        color: AppColors.neutralGray,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                  if (_activeCombo != null) ...[
                                    const SizedBox(height: 14),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.green.shade200,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '🎉 ${_activeCombo!['title'] ?? 'Combo do Dia'} - ${((_activeCombo!['discount_percentage'] as num?)?.toDouble() ?? 20).toStringAsFixed(0)}% OFF',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.successGreen,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _activeCombo!['description']
                                                    ?.toString() ??
                                                'Desconto aplicado automaticamente no carrinho.',
                                            style: const TextStyle(
                                              color: AppColors.neutralGray,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 15,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFFF4EE),
                                          Colors.white,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: AppColors.primaryRed.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Pratos já disponíveis',
                                          style: TextStyle(
                                            fontSize: 21,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${_menuItems.length} itens ligados a este restaurante',
                                          style: const TextStyle(
                                            color: AppColors.neutralGray,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    onChanged: (value) {
                                      setState(() => _searchQuery = value);
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'Pesquisar prato pelo nome',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon: _searchQuery.trim().isEmpty
                                          ? null
                                          : IconButton(
                                              onPressed: () {
                                                setState(
                                                  () => _searchQuery = '',
                                                );
                                              },
                                              icon: const Icon(Icons.close),
                                            ),
                                      filled: true,
                                      fillColor: const Color(0xFF07152D),
                                      hintStyle: const TextStyle(color: Color(0xFF8BA4C6)),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_categories.isNotEmpty)
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: 56,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  itemCount: _categories.length + 1,
                                  itemBuilder: (context, index) {
                                    final isAll = index == 0;
                                    final label = isAll
                                        ? 'Todos'
                                        : _categories[index - 1];
                                    final selected = isAll
                                        ? _selectedCategory == null
                                        : _selectedCategory == label;
                                    final categoryMeta = isAll
                                        ? DeligoFoodCategories.all
                                        : DeligoFoodCategories.resolve(label);
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        avatar: Icon(
                                          categoryMeta.icon,
                                          size: 17,
                                          color: selected
                                              ? AppColors.primaryRed
                                              : categoryMeta.color,
                                        ),
                                        label: Text(label),
                                        selected: selected,
                                        onSelected: (_) {
                                          setState(() {
                                            _selectedCategory = isAll
                                                ? null
                                                : label;
                                          });
                                        },
                                        selectedColor: const Color(0xFFFF4D0A),
                                        side: BorderSide(
                                          color: selected
                                              ? const Color(0xFFFF4D0A)
                                              : const Color(0xFF2D5A91),
                                        ),
                                        labelStyle: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : const Color(0xFFB9D7FF),
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              12,
                              16,
                              cart.items.isNotEmpty &&
                                      cart.restaurantId == widget.restaurantId
                                  ? 120
                                  : 24,
                            ),
                            sliver: _filteredMenuItems.isEmpty
                                ? SliverToBoxAdapter(
                                    child: Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'Ainda não há pratos nesta categoria.',
                                        ),
                                      ),
                                    ),
                                  )
                                : SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) => SizedBox(
                                        // Sliver children can receive an
                                        // unbounded cross-axis constraint on
                                        // some Flutter/Android combinations.
                                        // Keep the card (and its buttons) on a
                                        // concrete viewport width.
                                        width:
                                            MediaQuery.sizeOf(context).width -
                                            32,
                                        child: _buildPublicCompactMenuItemCard(
                                          _filteredMenuItems[index],
                                        ),
                                      ),
                                      childCount: _filteredMenuItems.length,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (cart.items.isNotEmpty &&
                      cart.restaurantId == widget.restaurantId)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 18,
                      child: GestureDetector(
                        onTap: () => _showMiniCartSheet(cart),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryRed,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryRed.withValues(
                                  alpha: 0.28,
                                ),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Text(
                                    '${cart.itemCount}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Ver carrinho',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      '${cart.items.length} pratos selecionados',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${cart.subtotal.toStringAsFixed(0)} MZN',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.keyboard_arrow_up,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderPlaceholder() {
    return Container(
      decoration: BoxDecoration(gradient: AppColors.splashGradient),
      child: const Center(
        child: Icon(Icons.storefront, size: 72, color: Colors.white),
      ),
    );
  }

  Future<void> _showDishPhotoViewer(List<String> urls, int initialIndex) async {
    final controller = PageController(initialPage: initialIndex);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: controller,
              itemCount: urls.length,
              itemBuilder: (context, index) => InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    urls[index],
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton.filled(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Fechar galeria',
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Widget _buildDishFavoriteButton(MenuItem item, {required bool compact}) {
    final favorite =
        _menuItemEngagement[item.id]?['favorite_by_current_user'] == true;
    return Material(
      color: Colors.white.withValues(alpha: .92),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: favorite ? 'Remover dos favoritos' : 'Guardar nos favoritos',
        visualDensity: compact ? VisualDensity.compact : null,
        iconSize: compact ? 19 : 23,
        onPressed: () => _toggleDishFavorite(item),
        icon: Icon(
          favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: favorite ? AppColors.primaryRed : AppColors.darkGray,
        ),
      ),
    );
  }

  Widget _buildPublicCompactMenuItemCard(MenuItem item) {
    final rating = item.rating.toStringAsFixed(1);
    final engagement = _menuItemEngagement[item.id] ?? const {};
    final likes = (engagement['likes'] as num?)?.toInt() ?? 0;
    final comments = (engagement['comments'] as num?)?.toInt() ?? 0;
    final liked = engagement['liked_by_current_user'] == true;
    final available = item.isAvailable && _restaurant?.isOpen != false;
    final description = item.description?.trim().isNotEmpty == true
        ? item.description!.trim()
        : 'Prato disponível para entrega imediata.';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF07152D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGray.withValues(alpha: .45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showMenuItemDetails(item),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: SizedBox(
                      width: 84,
                      height: 84,
                      child: item.imageUrl?.isNotEmpty == true
                          ? CachedNetworkImage(
                              imageUrl: item.imageUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth:
                                  (84 * MediaQuery.devicePixelRatioOf(context))
                                      .round(),
                              memCacheHeight:
                                  (84 * MediaQuery.devicePixelRatioOf(context))
                                      .round(),
                              errorWidget: (_, __, ___) =>
                                  _buildItemImageFallback(
                                    width: 84,
                                    height: 84,
                                  ),
                            )
                          : _buildItemImageFallback(width: 84, height: 84),
                    ),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: _buildDishFavoriteButton(item, compact: true),
                  ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${item.price.toStringAsFixed(0)} MZN',
                          style: const TextStyle(
                            color: Color(0xFFFF7A45),
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                        color: Color(0xFFB9D7FF),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 3,
                      children: [
                        _buildInfoChip(Icons.star, rating, Colors.amber),
                        _buildInfoChip(
                          Icons.access_time,
                          '${item.prepTimeMinutes} min',
                          AppColors.primaryRed,
                        ),
                        if ((item.category ?? '').trim().isNotEmpty)
                          _buildInfoChip(
                            Icons.category_outlined,
                            item.category!,
                            AppColors.darkGray,
                          ),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _engagementBusyItems.contains(item.id)
                              ? null
                              : () => _toggleDishLike(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  liked
                                      ? Icons.thumb_up_alt_rounded
                                      : Icons.thumb_up_alt_outlined,
                                  size: 16,
                                  color: liked
                                      ? AppColors.primaryRed
                                      : AppColors.neutralGray,
                                ),
                                const SizedBox(width: 2),
                                Text('$likes'),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _openDishComment(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 16,
                                ),
                                const SizedBox(width: 2),
                                Text('$comments'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    SizedBox(
                      height: 32,
                      child: FilledButton.icon(
                        onPressed: available ? () => _addToCart(item) : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryRed,
                          disabledBackgroundColor: AppColors.neutralGray,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.add_shopping_cart, size: 16),
                        label: Text(
                          available
                              ? 'Adicionar'
                              : _restaurant?.isOpen == false
                              ? 'Fechado'
                              : 'Indisponível',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItemCard(MenuItem item) {
    final rating = item.rating.toStringAsFixed(1);
    final prepTime = item.prepTimeMinutes;
    final engagement = _menuItemEngagement[item.id] ?? const {};
    final likes = (engagement['likes'] as num?)?.toInt() ?? 0;
    final comments = (engagement['comments'] as num?)?.toInt() ?? 0;
    final favorite = engagement['favorite_by_current_user'] == true;
    final liked = engagement['liked_by_current_user'] == true;
    final isHighlighted =
        widget.highlightDishId == item.id ||
        (_weeklyDishId == item.id && likes > 0);

    return GestureDetector(
      onTap: () => _showMenuItemDetails(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: isHighlighted ? const Color(0xFFFFF7EE) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: isHighlighted
              ? Border.all(color: const Color(0xFFFFC278), width: 1.4)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: const Color(0xFFF7F7F7),
                  child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (context, error, stackTrace) =>
                              _buildItemImageFallback(),
                        )
                      : _buildItemImageFallback(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.description?.trim().isNotEmpty == true
                                  ? item.description!
                                  : 'Prato disponível para entrega imediata.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.neutralGray,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successGreen.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          '${item.price.toStringAsFixed(0)} MZN',
                          style: const TextStyle(
                            color: Color(0xFF087A3B),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      _buildInfoChip(Icons.star, rating, Colors.amber),
                      _buildInfoChip(
                        Icons.access_time,
                        '$prepTime min',
                        AppColors.primaryRed,
                      ),
                      if ((item.category ?? '').trim().isNotEmpty)
                        _buildInfoChip(
                          Icons.category,
                          item.category!,
                          AppColors.darkGray,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: _engagementBusyItems.contains(item.id)
                            ? null
                            : () => _toggleDishLike(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                liked
                                    ? Icons.thumb_up_alt_rounded
                                    : Icons.thumb_up_alt_outlined,
                                size: 21,
                                color: liked
                                    ? AppColors.primaryRed
                                    : AppColors.neutralGray,
                              ),
                              const SizedBox(width: 6),
                              Text('${formatCompactNumber(likes)} gostos'),
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: _engagementBusyItems.contains(item.id)
                            ? null
                            : () => _toggleDishFavorite(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 7,
                          ),
                          child: Icon(
                            favorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 22,
                            color: favorite
                                ? AppColors.primaryRed
                                : AppColors.neutralGray,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _openDishComment(item),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chat_bubble_outline_rounded),
                            const SizedBox(width: 6),
                            Text(
                              comments == 1
                                  ? '1 comentario'
                                  : '${formatCompactNumber(comments)} comentarios',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 8,
                    children: [
                      if (isHighlighted)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE4BF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _weeklyDishId == item.id && likes > 0
                                ? 'Prato da semana'
                                : 'Link partilhado',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF8A4B00),
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: () => _showShareDishSheet(item),
                        child: Container(
                          padding: EdgeInsets.zero,
                          child: const Icon(Icons.share_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: item.isAvailable && _restaurant?.isOpen != false
                        ? () => _addToCart(item)
                        : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: item.isAvailable && _restaurant?.isOpen != false
                            ? AppColors.primaryRed
                            : AppColors.neutralGray,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.add_shopping_cart,
                            color: AppColors.cleanWhite,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.isAvailable && _restaurant?.isOpen != false
                                ? 'Adicionar ao carrinho'
                                : _restaurant?.isOpen == false
                                ? 'Restaurante fechado'
                                : 'Indisponível',
                            style: const TextStyle(
                              color: AppColors.cleanWhite,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewSummary({
    required List<MenuItemReview> reviews,
    required double averageRating,
  }) {
    final total = reviews.length;
    final counts = List<int>.filled(5, 0);
    for (final review in reviews) {
      final rating = review.rating.clamp(1, 5);
      counts[rating - 1] += 1;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderGray.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  averageRating > 0 ? averageRating.toStringAsFixed(1) : 'Novo',
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                _buildStarRow(averageRating),
                const SizedBox(height: 6),
                Text(
                  '$total avaliações',
                  style: const TextStyle(
                    color: AppColors.neutralGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                for (int i = 5; i >= 1; i--)
                  _buildRatingBarRow(i, counts[i - 1], total),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStarRow(double rating) {
    final fullStars = rating.floor();
    return Row(
      children: List.generate(
        5,
        (index) => Icon(
          index < fullStars ? Icons.star_rounded : Icons.star_border_rounded,
          size: 16,
          color: Colors.amber,
        ),
      ),
    );
  }

  Widget _buildRatingBarRow(int rating, int count, int total) {
    final value = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rating',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primaryRed,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.neutralGray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(MenuItemReview review, MenuItem item) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final canDelete =
        currentUserId != null && currentUserId == review.reviewerId;
    final initials = review.reviewerName.trim().isNotEmpty
        ? review.reviewerName.trim()[0].toUpperCase()
        : 'C';
    final isUseful = review.likesCount >= 2;
    final isVerified = review.isVerifiedReviewer;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderGray.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryRed.withValues(alpha: 0.10),
                backgroundImage:
                    review.reviewerAvatarUrl != null &&
                        review.reviewerAvatarUrl!.trim().isNotEmpty
                    ? NetworkImage(review.reviewerAvatarUrl!)
                    : null,
                child:
                    review.reviewerAvatarUrl == null ||
                        review.reviewerAvatarUrl!.trim().isEmpty
                    ? Text(
                        initials,
                        style: const TextStyle(
                          color: AppColors.primaryRed,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            review.reviewerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: AppColors.successGreen,
                          ),
                          const SizedBox(width: 2),
                          const Text(
                            'Verificado',
                            style: TextStyle(
                              color: AppColors.successGreen,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          review.rating.toString(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _formatReviewDate(review.createdAt),
                      style: const TextStyle(
                        color: AppColors.neutralGray,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (canDelete)
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value != 'delete') return;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Apagar avaliação'),
                        content: const Text(
                          'Tem certeza que deseja apagar esta avaliação?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Apagar'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    final ok = await _restaurantService.deleteMenuItemReview(
                      review.id,
                    );
                    if (!mounted) return;
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Nao foi possivel apagar a sua avaliacao.',
                          ),
                        ),
                      );
                      return;
                    }
                    final refreshed = await _restaurantService
                        .getMenuItemReviews(item.id);
                    if (!mounted) return;
                    setState(() {
                      _menuItemReviews[item.id] = refreshed;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Avaliacao apagada com sucesso.'),
                        backgroundColor: AppColors.successGreen,
                      ),
                    );
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Apagar avaliação'),
                    ),
                  ],
                ),
            ],
          ),
          if ((review.comment ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              review.comment!,
              style: const TextStyle(color: AppColors.darkGray, height: 1.4),
            ),
          ],
          const SizedBox(height: 4),
          if (review.imageUrl != null &&
              review.imageUrl!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: review.imageUrl!,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorWidget: (context, error, stackTrace) => Container(
                  height: 150,
                  width: double.infinity,
                  color: const Color(0xFFF3F4F6),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.image_not_supported_outlined,
                    color: AppColors.neutralGray,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              if (isUseful)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successGreen.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Mais util',
                    style: TextStyle(
                      color: AppColors.successGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () async {
                  if (_supabase.auth.currentUser == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Entre na sua conta para curtir.'),
                      ),
                    );
                    return;
                  }
                  final index =
                      _menuItemReviews[item.id]?.indexWhere(
                        (entry) => entry.id == review.id,
                      ) ??
                      -1;
                  final current = review;
                  if (index >= 0) {
                    final nextLiked = !current.likedByCurrentUser;
                    final nextCount =
                        (current.likesCount + (nextLiked ? 1 : -1)).clamp(
                          0,
                          1 << 30,
                        );
                    final optimistic = MenuItemReview(
                      id: current.id,
                      menuItemId: current.menuItemId,
                      menuItemName: current.menuItemName,
                      reviewerId: current.reviewerId,
                      reviewerName: current.reviewerName,
                      reviewerAvatarUrl: current.reviewerAvatarUrl,
                      rating: current.rating,
                      comment: current.comment,
                      imageUrl: current.imageUrl,
                      likesCount: nextCount,
                      likedByCurrentUser: nextLiked,
                      isVerifiedReviewer: current.isVerifiedReviewer,
                      createdAt: current.createdAt,
                    );
                    final optimisticReviews = List<MenuItemReview>.from(
                      _menuItemReviews[item.id]!,
                    );
                    optimisticReviews[index] = optimistic;
                    setState(
                      () => _menuItemReviews[item.id] = optimisticReviews,
                    );
                  }
                  try {
                    final ok = await _restaurantService
                        .toggleMenuItemReviewLike(review.id);
                    if (!ok) throw StateError('like_failed');
                    final refreshed = await _restaurantService
                        .getMenuItemReviews(item.id);
                    if (!mounted) return;
                    setState(() => _menuItemReviews[item.id] = refreshed);
                  } catch (_) {
                    final refreshed = await _restaurantService
                        .getMenuItemReviews(item.id);
                    if (mounted) {
                      setState(() => _menuItemReviews[item.id] = refreshed);
                    }
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Nao foi possivel curtir este comentario agora.',
                        ),
                      ),
                    );
                  }
                },
                icon: Icon(
                  review.likedByCurrentUser
                      ? Icons.thumb_up_alt_rounded
                      : Icons.thumb_up_alt_outlined,
                  size: 18,
                  color: review.likedByCurrentUser
                      ? AppColors.primaryRed
                      : AppColors.neutralGray,
                ),
                label: Text(
                  review.likesCount > 0
                      ? 'Curtir (${formatCompactNumber(review.likesCount)})'
                      : 'Curtir',
                ),
              ),
              Builder(
                builder: (context) {
                  final replies = _menuItemReplies[review.id];
                  final count = replies?.length ?? 0;
                  final expanded = _expandedReviewReplies.contains(review.id);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          if (replies == null) {
                            unawaited(_openReviewRepliesOrComposer(review));
                            return;
                          }
                          if (count == 0) {
                            setState(() {
                              _activeReplyReviewId = review.id;
                              _activeReplyToName = review.reviewerName;
                              _replyDraft = '';
                            });
                            return;
                          }
                          setState(() {
                            if (expanded) {
                              _expandedReviewReplies.remove(review.id);
                            } else {
                              _expandedReviewReplies.add(review.id);
                            }
                          });
                        },
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 18,
                        ),
                        label: Text(
                          count > 0
                              ? (expanded
                                    ? 'Ocultar respostas'
                                    : 'Ver $count ${count == 1 ? 'resposta' : 'respostas'}')
                              : (replies == null
                                    ? 'Ver respostas'
                                    : 'Responder'),
                        ),
                      ),
                      if (count > 0)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => setState(() {
                            _expandedReviewReplies.add(review.id);
                            _activeReplyReviewId = review.id;
                            _activeReplyToName = review.reviewerName;
                            _replyDraft = '';
                          }),
                          icon: const Icon(Icons.reply_rounded, size: 18),
                          label: const Text('Responder'),
                        ),
                      if (expanded && replies != null)
                        Container(
                          margin: const EdgeInsets.only(left: 12, top: 2),
                          padding: const EdgeInsets.only(left: 12),
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: Color(0xFFD1D5DB),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...replies.map(
                                (reply) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${reply['author_name'] ?? 'Utilizador'} · ${reply['created_at'] ?? ''}',
                                        style: const TextStyle(
                                          color: AppColors.darkGray,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '${reply['body'] ?? ''}',
                                        style: const TextStyle(
                                          color: AppColors.darkGray,
                                          fontSize: 13,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => setState(() {
                                          _activeReplyReviewId = review.id;
                                          _activeReplyToName =
                                              reply['author_name']?.toString();
                                          _replyDraft = '';
                                        }),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(0, 24),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          '👍 Curtir · Responder',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_activeReplyReviewId == review.id)
                                _buildInlineReplyComposer(review),
                            ],
                          ),
                        ),
                      if (!expanded && _activeReplyReviewId == review.id)
                        _buildInlineReplyComposer(review),
                    ],
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInlineReplyComposer(MenuItemReview review) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              autofocus: true,
              maxLines: 2,
              maxLength: 500,
              onChanged: (value) => _replyDraft = value,
              decoration: InputDecoration(
                isDense: true,
                hintText:
                    '↪ Respondendo a ${_activeReplyToName ?? review.reviewerName}',
                suffixIcon: IconButton(
                  tooltip: 'Fechar',
                  onPressed: () => setState(() {
                    _activeReplyReviewId = null;
                    _activeReplyToName = null;
                    _replyDraft = '';
                  }),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Enviar',
            onPressed: _replySending
                ? null
                : () async {
                    final body = _replyDraft.trim();
                    if (body.isEmpty) return;
                    setState(() => _replySending = true);
                    try {
                      await _socialReviewService.addReply(
                        'menu_item',
                        review.id,
                        body,
                      );
                      if (!mounted) return;
                      List<Map<String, dynamic>> refreshedReplies;
                      try {
                        refreshedReplies = await _socialReviewService
                            .getReplies('menu_item', review.id);
                      } catch (error) {
                        debugPrint('Erro ao atualizar respostas: $error');
                        refreshedReplies =
                            _menuItemReplies[review.id] ?? const [];
                      }
                      if (!mounted) return;
                      setState(() {
                        _menuItemReplies[review.id] = refreshedReplies;
                        _expandedReviewReplies.add(review.id);
                        _replySending = false;
                        _activeReplyReviewId = null;
                        _activeReplyToName = null;
                        _replyDraft = '';
                      });
                    } catch (error) {
                      debugPrint('Erro ao publicar resposta inline: $error');
                      if (mounted) setState(() => _replySending = false);
                    }
                  },
            icon: _replySending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _showInlineReviewReply(
    MenuItemReview review,
    MenuItem item,
  ) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entre na sua conta para responder.')),
      );
      return;
    }
    var draft = '';
    var sending = false;
    String? validationMessage;
    final published = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A responder a ${review.reviewerName}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  autofocus: true,
                  maxLength: 500,
                  maxLines: 2,
                  onChanged: (value) => draft = value,
                  decoration: const InputDecoration(
                    hintText: 'Escreva a sua resposta...',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (validationMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    validationMessage!,
                    style: const TextStyle(color: AppColors.alertRed),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: sending
                        ? null
                        : () async {
                            final body = draft.trim();
                            if (body.isEmpty) {
                              setSheetState(
                                () => validationMessage =
                                    'Escreva uma resposta antes de publicar.',
                              );
                              return;
                            }
                            setSheetState(() {
                              validationMessage = null;
                              sending = true;
                            });
                            try {
                              await _socialReviewService.addReply(
                                'menu_item',
                                review.id,
                                body,
                              );
                              if (sheetContext.mounted) {
                                // Remove focus before disposing the sheet. On
                                // Android the focused TextField can still be
                                // a dependent of the sheet for one frame.
                                FocusManager.instance.primaryFocus?.unfocus();
                                await Future<void>.delayed(Duration.zero);
                              }
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop(true);
                              }
                            } catch (error) {
                              debugPrint('Erro ao publicar resposta: $error');
                              if (sheetContext.mounted) {
                                setSheetState(() {
                                  sending = false;
                                  validationMessage =
                                      'Não foi possível publicar. Verifique a ligação e tente novamente.';
                                });
                              }
                            }
                          },
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      sending ? 'A publicar...' : 'Publicar resposta',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (published == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resposta publicada.'),
          backgroundColor: AppColors.successGreen,
        ),
      );
    }
  }

  Widget _buildItemImageFallback({double height = 180, double? width}) {
    return Container(
      height: height,
      width: width ?? double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFEFE8), Color(0xFFFFD9C9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.fastfood,
          size: height <= 60 ? 22 : 48,
          color: AppColors.primaryRed,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _formatReviewDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/$year às $hour:$minute';
  }
}
