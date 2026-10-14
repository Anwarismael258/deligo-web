import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../config/theme/app_colors.dart';
import '../../shared/widgets/profile_image_viewer.dart';
import '../../services/cart_service.dart';
import '../../services/deligo_ai_service.dart';
import '../../services/order_service.dart';
import '../../services/notification_router_service.dart';
import '../../services/app_voice_service.dart';
import '../../services/marketing_service.dart';
import 'package:deligo_app/services/restaurant_service.dart';
import '../../services/restaurant_share_service.dart';
import '../../services/server_clock_service.dart';
import 'package:deligo_app/services/welcome_voice_service.dart';
import '../../services/sound_controller.dart';
import '../../services/weather_service.dart';
import '../../shared/models/order.dart';
import '../../shared/models/menu_item.dart';
import '../../shared/models/restaurant.dart';
import '../../shared/widgets/tap_scale.dart';
import '../../shared/widgets/deligo_pressable.dart';
import '../../shared/widgets/order_chat_button.dart';
import '../../shared/widgets/support_headset_button.dart';
import '../../shared/widgets/institutional_footer.dart';
import '../../services/push_notification_service.dart';
import '../../shared/utils/maps_route.dart';
import '../../shared/utils/location_display.dart';
import '../../shared/utils/mozambique_time.dart';
import '../../shared/utils/chat_notification_utils.dart';
import '../../shared/utils/guarded_navigation.dart';
import '../../shared/utils/notification_type_utils.dart';
import '../../shared/utils/ecosystem_test_persona.dart';
import '../../config/router/app_router.dart';
import '../categories/deligo_food_categories.dart';

enum _FeaturedCardVariant { fast, featured }

class _CourierSnapshot {
  final String name;
  final String phone;
  final String? avatarUrl;

  const _CourierSnapshot({
    required this.name,
    required this.phone,
    this.avatarUrl,
  });
}

class _WebBrandMark extends StatelessWidget {
  const _WebBrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryRed,
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Text(
        'D',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _WebTopAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _WebTopAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFE6E4DF)),
          ),
          child: Icon(icon, size: 21, color: const Color(0xFF333333)),
        ),
      ),
    );
  }
}

class _WebSectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String action;
  final VoidCallback onAction;

  const _WebSectionHeader({
    required this.eyebrow,
    required this.title,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: const TextStyle(
                  color: AppColors.primaryRed,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.35,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF1B1B1B),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.7,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onAction,
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF3C3C3C)),
          label: Text(
            action,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          icon: const Icon(Icons.arrow_forward_rounded, size: 17),
          iconAlignment: IconAlignment.end,
        ),
      ],
    );
  }
}

class _ClientSearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _ClientSearchHeaderDelegate({required this.child});

  @override
  double get minExtent => 78;

  @override
  double get maxExtent => 78;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: const Color(0xFFF8F9FB),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ClientSearchHeaderDelegate oldDelegate) =>
      oldDelegate.child != child;
}

class _SplashVideoAdDialog extends StatefulWidget {
  const _SplashVideoAdDialog({required this.campaign});

  final Map<String, dynamic> campaign;

  @override
  State<_SplashVideoAdDialog> createState() => _SplashVideoAdDialogState();
}

class _SplashVideoAdDialogState extends State<_SplashVideoAdDialog> {
  VideoPlayerController? _controller;
  bool _canSkip = false;
  bool _failed = false;
  bool _muted = true;
  bool _finished = false;
  Timer? _skipTimer;

  @override
  void initState() {
    super.initState();
    _initVideo();
    _skipTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _canSkip = true);
    });
  }

  Future<void> _initVideo() async {
    final url = _videoUrl(widget.campaign);
    if (url.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(0);
      await controller.play();
      controller.addListener(() {
        final value = controller.value;
        if (!mounted) return;
        if (value.isInitialized &&
            value.position >= value.duration &&
            value.duration > Duration.zero) {
          if (!_finished) setState(() => _finished = true);
        }
      });
      if (mounted) setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.campaign['title']?.toString() ?? 'DeliGo';
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: _failed
                  ? Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    )
                  : _controller?.value.isInitialized == true
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.campaign['subtitle']?.toString() ??
                      widget.campaign['description']?.toString() ??
                      '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
                if (_finished || _failed) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.explore_outlined),
                    label: Text(
                      widget.campaign['action_label']?.toString() ??
                          'Explorar DeliGo',
                    ),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            top: 40,
            left: 18,
            child: IconButton.filled(
              tooltip: _muted ? 'Ativar som' : 'Desativar som',
              onPressed: _controller == null
                  ? null
                  : () async {
                      final nextMuted = !_muted;
                      await _controller!.setVolume(nextMuted ? 0 : 1);
                      if (mounted) setState(() => _muted = nextMuted);
                    },
              icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
            ),
          ),
          Positioned(
            top: 40,
            right: 18,
            child: FilledButton(
              onPressed: _canSkip || _failed
                  ? () => Navigator.of(context).maybePop()
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primaryRed,
              ),
              child: Text(_canSkip || _failed ? 'Saltar' : 'Aguarde'),
            ),
          ),
        ],
      ),
    );
  }

  String _videoUrl(Map<String, dynamic> campaign) {
    final direct = campaign['video_url']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    final metadata =
        (campaign['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    return metadata['video_url']?.toString().trim() ?? '';
  }
}

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _SkyTheme {
  final LinearGradient gradient;
  final bool showClouds;
  final bool showStars;

  const _SkyTheme({
    required this.gradient,
    required this.showClouds,
    required this.showStars,
  });
}

class _SkyMover extends StatefulWidget {
  final double begin;
  final double end;
  final Duration duration;
  final Widget child;

  const _SkyMover({
    required this.begin,
    required this.end,
    required this.duration,
    required this.child,
  });

  @override
  State<_SkyMover> createState() => _SkyMoverState();
}

class _SkyMoverState extends State<_SkyMover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final dx =
            widget.begin + (widget.end - widget.begin) * _controller.value;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

class _SkyTwinkle extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const _SkyTwinkle({
    required this.child,
    this.duration = const Duration(milliseconds: 1800),
  });

  @override
  State<_SkyTwinkle> createState() => _SkyTwinkleState();
}

class _SkyTwinkleState extends State<_SkyTwinkle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.28,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

class _ClientDashboardState extends State<ClientDashboard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _popupDuration = Duration(milliseconds: 1000);
  static const Duration _briefCompletionPopupDuration = Duration(
    milliseconds: 450,
  );
  static const String _cartQuickAsset =
      'assets/bottom_nav/cliente/cart_quick.gif';

  final supabase = Supabase.instance.client;
  final RestaurantService _restaurantService = RestaurantService();
  final RestaurantShareService _restaurantShareService =
      RestaurantShareService();
  final OrderService _orderService = OrderService();
  final MarketingService _marketingService = MarketingService(
    Supabase.instance.client,
  );

  int _selectedIndex = 0;
  bool _emailConfirmed = true;

  bool _loadingRestaurants = true;
  bool _catalogLoaded = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _loadError = '';

  List<Restaurant> _restaurants = [];
  List<Restaurant> _featuredRestaurants = [];
  List<Restaurant> _fastRestaurants = [];
  List<Restaurant> _localRestaurants = [];
  bool _localRestaurantsLoaded = false;
  bool _localRestaurantsLoadFailed = false;
  List<Restaurant> _favoriteRestaurants = [];
  List<MenuItem> _favoriteDishes = [];
  List<Map<String, dynamic>> _activeDailyCombos = [];
  List<Map<String, dynamic>> _marketingCampaigns = [];
  List<Map<String, dynamic>> _marketingCampaignSections = [];
  bool _splashVideoShownThisSession = false;
  List<Map<String, dynamic>> _topSharedRestaurants = [];
  List<Map<String, dynamic>> _smartNotifications = [];
  bool _loadingSmartNotifications = true;
  bool _showOnlyUnreadNotifications = false;
  final Map<String, bool> _collapsedNotificationSections = {};
  final Set<String> _hiddenNotificationIds = {};
  final Set<String> _driverAssignedPopupOrderIds = {};
  final Set<String> _closedOrderPopupOrderIds = {};
  final Set<String> _shownClientPopupKeys = {};
  String _notificationSearchQuery = '';
  String _notificationTypeFilter = 'ALL';
  final ScrollController _restaurantsScroll = ScrollController();
  final int _pageSize = 10;
  int _page = 0;

  String _displayName = '';
  bool _profileHydrated = false;
  bool _profileLoadFailed = false;
  Future<void>? _summaryLoadInFlight;
  Future<void>? _dashboardLoadInFlight;
  bool _dashboardReloadQueued = false;
  String _queuedDashboardReloadReason = 'coalesced';
  String _address = '';
  String _addressNeighborhood = '';
  String _addressCity = '';
  double? _userLat;
  double? _userLng;
  String? _avatarUrl;
  WeatherSnapshot? _weather;
  bool _loadingWeather = false;
  bool _pushActive = false;
  double _walletBalance = 0;
  String _walletCurrency = 'MZN';
  bool _isTestWallet = false;
  DateTime _currentDateTime = ServerClockService.instance.now();

  Timer? _searchDebounce;
  Timer? _activeOrderTimer;
  Timer? _clockTimer;
  Timer? _ordersRefreshDebounce;
  Timer? _notificationsRefreshDebounce;
  Timer? _catalogRefreshDebounce;
  Timer? _profileRefreshDebounce;
  Timer? _favoritesRefreshDebounce;
  StreamSubscription<AuthState>? _authSub;
  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _ordersChannelSecondary;
  RealtimeChannel? _deliveriesChannel;
  RealtimeChannel? _notificationsChannel;
  RealtimeChannel? _catalogChannel;
  RealtimeChannel? _profileChannel;
  RealtimeChannel? _walletChannel;
  RealtimeChannel? _favoritesChannel;
  String _searchQuery = '';
  final String _sortBy = 'rating';

  String _orderStatusFilter = 'all';
  String _locationFilter =
      'all'; // all zones in the selected city, nearby or zone:<name>
  String _selectedFoodCategory = 'Todos';
  bool _exploreOpenNow = false;
  int? _exploreMaxDeliveryMinutes;
  double? _exploreMinimumRating;
  bool _exploreFreeDelivery = false;
  bool _exploreDishesMode = false;
  bool _explorePopularDishes = false;
  String _selectedSmartDiscovery = 'popular';
  Map<String, RouteInfo> _routeInfo = {};
  bool _loadingRouteInfo = false;
  List<Order> _clientOrders = const [];
  bool _loadingOrders = true;
  bool _ordersLoaded = false;
  bool _ordersLoadFailed = false;
  Future<void>? _ordersLoadInFlight;
  bool _ordersReloadQueued = false;
  int _ordersRefreshEpoch = 0;
  Order? _activeOrder;
  Map<String, dynamic>? _activeCourierMotionAssessment;
  final Map<String, List<OrderItem>> _orderItemsCache = {};
  final Map<String, Future<_CourierSnapshot>> _courierSnapshotFutures = {};
  final Set<String> _hiddenOrderIds = {};
  final Set<String> _timedOutHiddenOrderIds = {};
  final Set<String> _refreshedExpiredDispatchAttempts = {};
  final Map<String, DateTime> _optimisticDeliverySearchDeadlines = {};

  Set<String> _favorites = {};
  Set<String> _favoriteDishIds = {};
  Map<String, dynamic> _profileSettings = {};
  bool _loadingFavorites = true;
  bool _favoritesLoaded = false;
  bool _favoritesLoadFailed = false;
  Future<void>? _favoritesLoadInFlight;
  bool _favoritesReloadQueued = false;
  String _favoritesFilter = 'Todos';
  List<Map<String, dynamic>> _featuredDishes = [];
  bool _featuredDishesLoaded = false;
  bool _featuredDishesLoadFailed = false;
  bool _loadingFeaturedDishes = true;
  Map<String, Map<String, dynamic>> _shareStatsByRestaurantId = {};
  DateTime? _scheduledDelivery;
  String? _groupOrderCode;
  bool _initialTabApplied = false;
  int _loadVersion = 0;
  DateTime? _lastTimedOutRestaurantRefreshAt;
  DateTime? _lastExpiredCountdownRefreshAt;
  late final AnimationController _homeLogoMarqueeController;
  Timer? _homeLogoMarqueeRestartTimer;
  bool _homeLogoMarqueeReducedMotion = false;
  bool _homeLogoMarqueeAppPaused = false;
  bool _homeLogoMarqueeGoingForward = true;

  int get _unreadNotificationCount => _smartNotifications
      .where((notification) => notification['read_at'] == null)
      .length;

  DateTime get _serverNow => ServerClockService.instance.now();

  DateTime get _serverNowLocal => MozambiqueTime.from(_serverNow);

  String get _serverNowIsoUtc => ServerClockService.instance.nowIso8601Utc();

  List<DeligoSmartCategory> get _smartCategoryCards {
    final cards = <DeligoSmartCategory>[];
    if (_featuredDishes.isNotEmpty) {
      cards.add(
        DeligoFoodCategories.smart.firstWhere((item) => item.id == 'popular'),
      );
      cards.add(
        DeligoFoodCategories.smart.firstWhere(
          (item) => item.id == 'recommended',
        ),
      );
      cards.add(
        DeligoFoodCategories.smart.firstWhere((item) => item.id == 'new'),
      );
    }
    if (_activeDailyCombos.isNotEmpty) {
      cards.add(
        DeligoFoodCategories.smart.firstWhere(
          (item) => item.id == 'promotions',
        ),
      );
    }
    if (_fastRestaurants.isNotEmpty) {
      cards.add(
        DeligoFoodCategories.smart.firstWhere(
          (item) => item.id == 'fast_delivery',
        ),
      );
    }
    if (_localRestaurants.isNotEmpty || _restaurants.isNotEmpty) {
      cards.add(
        DeligoFoodCategories.smart.firstWhere((item) => item.id == 'nearby'),
      );
    }
    if (_restaurants.isNotEmpty) {
      cards.add(
        DeligoFoodCategories.smart.firstWhere((item) => item.id == 'budget'),
      );
      cards.add(
        DeligoFoodCategories.smart.firstWhere(
          (item) => item.id == 'top_restaurants',
        ),
      );
    }
    return DeligoFoodCategories.smart;
  }

  List<String> get _homeCategories {
    return [
      DeligoFoodCategories.all.label,
      ...DeligoFoodCategories.list.map((category) => category.label),
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _homeLogoMarqueeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..addStatusListener(_handleHomeLogoMarqueeStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncHomeLogoMarqueeAccessibility();
        _startHomeLogoMarqueeIfAllowed();
      }
    });
    final user = supabase.auth.currentUser;
    _emailConfirmed = user?.emailConfirmedAt != null;
    unawaited(_syncServerClock(force: true));
    _restaurantsScroll.addListener(_onScrollRestaurants);
    _authSub = supabase.auth.onAuthStateChange.listen((event) {
      final userId =
          event.session?.user.id ?? supabase.auth.currentUser?.id ?? '';
      // The current session is already hydrated synchronously above and its
      // channels are installed below. Supabase emits INITIAL_SESSION after a
      // listener is attached; handling it again duplicated the first loads.
      if (event.event == AuthChangeEvent.initialSession) return;
      unawaited(_loadUserSummary());
      if (userId.isEmpty) return;
      unawaited(_syncServerClock(force: true));
      unawaited(_subscribeToRealtimeOrders(userId));
      unawaited(_subscribeToRealtimeDeliveries(userId));
      unawaited(_subscribeToRealtimeNotifications(userId));
      unawaited(_subscribeToRealtimeCatalog());
      unawaited(_subscribeToRealtimeProfile(userId));
      unawaited(_refreshActiveOrder());
      unawaited(_loadSmartNotifications(showLoading: false));
    });
    _loadData(reason: 'init');
    if (user != null) {
      _subscribeToRealtimeOrders(user.id);
      _subscribeToRealtimeDeliveries(user.id);
      _subscribeToRealtimeNotifications(user.id);
      _subscribeToRealtimeCatalog();
      _subscribeToRealtimeProfile(user.id);
    }
    _activeOrderTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshActiveOrder(),
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _currentDateTime = _serverNow;
        _activeOrder = _sanitizeActiveOrder(_activeOrder);
      });
      _hideTimedOutOrdersIfNeeded();
      _maybeRefreshTimedOutRestaurantConfirmation();
      _maybeRefreshExpiredOrderCountdowns();
      _checkDeliverySearchDeadlines();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _homeLogoMarqueeRestartTimer?.cancel();
    _homeLogoMarqueeController.dispose();
    _restaurantsScroll.dispose();
    _searchDebounce?.cancel();
    _activeOrderTimer?.cancel();
    _clockTimer?.cancel();
    _ordersRefreshDebounce?.cancel();
    _notificationsRefreshDebounce?.cancel();
    _catalogRefreshDebounce?.cancel();
    _profileRefreshDebounce?.cancel();
    _favoritesRefreshDebounce?.cancel();
    _authSub?.cancel();
    _ordersChannel?.unsubscribe();
    _ordersChannelSecondary?.unsubscribe();
    _deliveriesChannel?.unsubscribe();
    _notificationsChannel?.unsubscribe();
    _catalogChannel?.unsubscribe();
    _profileChannel?.unsubscribe();
    _walletChannel?.unsubscribe();
    _favoritesChannel?.unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _homeLogoMarqueeAppPaused = state != AppLifecycleState.resumed;
    if (_homeLogoMarqueeAppPaused) {
      _homeLogoMarqueeRestartTimer?.cancel();
      _homeLogoMarqueeController.stop();
    } else {
      _startHomeLogoMarqueeIfAllowed();
    }
  }

  void _syncHomeLogoMarqueeAccessibility() {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (_homeLogoMarqueeReducedMotion == reducedMotion) return;
    _homeLogoMarqueeReducedMotion = reducedMotion;
    if (reducedMotion) {
      _homeLogoMarqueeRestartTimer?.cancel();
      _homeLogoMarqueeController.stop();
      _homeLogoMarqueeController.value = 0;
    } else {
      _startHomeLogoMarqueeIfAllowed();
    }
  }

  void _startHomeLogoMarqueeIfAllowed() {
    if (!mounted ||
        _homeLogoMarqueeReducedMotion ||
        _homeLogoMarqueeAppPaused ||
        _homeLogoMarqueeController.isAnimating) {
      return;
    }
    _homeLogoMarqueeRestartTimer?.cancel();
    if (_homeLogoMarqueeGoingForward) {
      _homeLogoMarqueeController.forward(from: 0);
    } else {
      _homeLogoMarqueeController.reverse(from: 1);
    }
  }

  void _handleHomeLogoMarqueeStatus(AnimationStatus status) {
    if (!mounted ||
        _homeLogoMarqueeReducedMotion ||
        _homeLogoMarqueeAppPaused) {
      return;
    }
    if (status == AnimationStatus.completed) {
      _homeLogoMarqueeGoingForward = false;
    } else if (status == AnimationStatus.dismissed) {
      _homeLogoMarqueeGoingForward = true;
    } else {
      return;
    }
    _homeLogoMarqueeRestartTimer?.cancel();
    _homeLogoMarqueeRestartTimer = Timer(
      const Duration(milliseconds: 700),
      _startHomeLogoMarqueeIfAllowed,
    );
  }

  Future<void> _syncServerClock({
    bool force = false,
    bool refreshUi = true,
  }) async {
    await ServerClockService.instance.sync(force: force);
    if (!mounted || !refreshUi) return;
    setState(() => _currentDateTime = _serverNow);
  }

  Future<void> _subscribeToRealtimeOrders(String userId) async {
    await _ordersChannel?.unsubscribe();
    await _ordersChannelSecondary?.unsubscribe();
    _ordersChannel = supabase.channel('client-orders-$userId');
    _ordersChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'client_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            if (payload.newRecord.isNotEmpty) {
              _applyRealtimeOrderRecord(
                Map<String, dynamic>.from(payload.newRecord),
              );
            }
            _scheduleOrdersRefresh();
            _loadUserSummary();
          },
        )
        .subscribe();

    _ordersChannelSecondary = supabase.channel('client-orders-alt-$userId');
    _ordersChannelSecondary!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            if (payload.newRecord.isNotEmpty) {
              _applyRealtimeOrderRecord(
                Map<String, dynamic>.from(payload.newRecord),
              );
            }
            _scheduleOrdersRefresh();
            _loadUserSummary();
          },
        )
        .subscribe();
  }

  Future<void> _subscribeToRealtimeDeliveries(String userId) async {
    await _deliveriesChannel?.unsubscribe();
    _deliveriesChannel = supabase.channel('client-deliveries-$userId');
    _deliveriesChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'deliveries',
          callback: (payload) {
            if (!mounted) return;
            final record = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            final orderId = record['order_id']?.toString().trim() ?? '';
            if (orderId.isEmpty) return;
            final known =
                _activeOrder?.id == orderId ||
                _clientOrders.any((order) => order.id == orderId);
            if (known) unawaited(_refreshActiveOrder());
          },
        )
        .subscribe();
  }

  Future<void> _subscribeToRealtimeNotifications(String userId) async {
    await _notificationsChannel?.unsubscribe();
    _notificationsChannel = supabase.channel('client-notifications-$userId');
    _notificationsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'push_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            if (payload.eventType == PostgresChangeEvent.insert &&
                payload.newRecord.isNotEmpty) {
              final notification = _normalizeNotification(
                Map<String, dynamic>.from(payload.newRecord),
              );
              _upsertRealtimeNotificationLocally(notification, moveToTop: true);
              if (notification['type']?.toString() == 'DELIVERY_UNAVAILABLE') {
                // The active-order card is the single place for this decision.
                // Refresh its authoritative state instead of stacking a modal
                // with the same pickup/retry actions.
                unawaited(_refreshActiveOrder());
              } else {
                _showRealtimeNotificationPopup(notification);
              }
              final type = notification['type']?.toString() ?? '';
              if (type == 'ORDER_ACCEPTED' ||
                  type == 'ORDER_PREPARING' ||
                  type == 'ORDER_CONFIRMED_BY_RESTAURANT' ||
                  type == 'DRIVER_ARRIVED' ||
                  type == 'ORDER_PICKED_UP') {
                unawaited(_refreshActiveOrder());
              }
            }
            _scheduleNotificationsRefresh();
          },
        )
        .subscribe();
  }

  Map<String, dynamic> _normalizeNotification(
    Map<String, dynamic> notification,
  ) {
    final normalized = Map<String, dynamic>.from(notification);
    normalized['type'] = NotificationTypeUtils.canonicalize(
      notification['type']?.toString(),
    );
    return normalized;
  }

  List<Map<String, dynamic>> _normalizeNotifications(
    Iterable<Map<String, dynamic>> notifications,
  ) {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final notification in notifications) {
      final normalized = _normalizeNotification(notification);
      final key = _notificationIdentityKey(normalized);
      if (seen.add(key)) result.add(normalized);
    }
    return result;
  }

  String _notificationIdentityKey(Map<String, dynamic> notification) {
    final type = notification['type']?.toString() ?? 'UNKNOWN';
    final entityId = notification['entity_id']?.toString().trim() ?? '';
    final metadata = notification['metadata'];
    final eventId = metadata is Map
        ? metadata['event_id']?.toString().trim() ?? ''
        : '';
    if (eventId.isNotEmpty) return 'event:$eventId';
    if (entityId.isNotEmpty && type != 'MESSAGE_RECEIVED') {
      return 'entity:$type:$entityId';
    }
    return 'id:${notification['id']}';
  }

  void _upsertRealtimeNotificationLocally(
    Map<String, dynamic> notification, {
    bool moveToTop = false,
  }) {
    if (!mounted) return;
    final normalized = _normalizeNotification(notification);
    final notificationId = normalized['id']?.toString() ?? '';
    final identity = _notificationIdentityKey(normalized);
    setState(() {
      final nextNotifications = _smartNotifications
          .where(
            (item) =>
                notificationId.isEmpty ||
                (item['id']?.toString() != notificationId &&
                    _notificationIdentityKey(item) != identity),
          )
          .toList();
      if (moveToTop) {
        _smartNotifications = [normalized, ...nextNotifications];
      } else {
        _smartNotifications = [...nextNotifications, normalized];
      }
    });
  }

  void _applyRealtimeOrderRecord(Map<String, dynamic> record) {
    final orderId = record['id']?.toString().trim() ?? '';
    if (orderId.isEmpty || !mounted) return;
    _ordersRefreshEpoch++;

    Order? previousOrder;
    for (final order in _clientOrders) {
      if (order.id == orderId) {
        previousOrder = order;
        break;
      }
    }

    final previousTrackedOrder = _activeOrder?.id == orderId
        ? _activeOrder
        : previousOrder;

    final merged = <String, dynamic>{};
    if (previousOrder != null) {
      merged.addAll(previousOrder.toMap());
    }
    merged.addAll(record);

    final fallbackClientId =
        (merged['client_id'] ?? merged['customer_id'])?.toString().trim() ?? '';
    if ((merged['client_id']?.toString().trim().isEmpty ?? true) &&
        fallbackClientId.isNotEmpty) {
      merged['client_id'] = fallbackClientId;
    }

    final nextOrder = Order.fromMap(merged);

    setState(() {
      var replaced = false;
      _clientOrders = _clientOrders.map((order) {
        if (order.id != orderId) return order;
        replaced = true;
        return nextOrder;
      }).toList();
      if (!replaced) {
        _clientOrders = [nextOrder, ..._clientOrders];
      }
      _loadingOrders = false;
      _ordersLoaded = true;
      _ordersLoadFailed = false;
    });

    if (previousTrackedOrder != null || _isActiveOrder(nextOrder)) {
      _applyActiveOrderUpdate(nextOrder, previousOrder: previousTrackedOrder);
    }
  }

  void _scheduleOrdersRefresh() {
    _ordersRefreshDebounce?.cancel();
    _ordersRefreshDebounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(_refreshActiveOrder());
    });
  }

  void _scheduleNotificationsRefresh() {
    _notificationsRefreshDebounce?.cancel();
    _notificationsRefreshDebounce = Timer(
      const Duration(milliseconds: 250),
      () {
        unawaited(_loadSmartNotifications(showLoading: false));
      },
    );
  }

  void _scheduleCatalogRefresh() {
    _catalogRefreshDebounce?.cancel();
    _catalogRefreshDebounce = Timer(const Duration(milliseconds: 700), () {
      unawaited(_loadData(reason: 'realtime/catalog'));
    });
  }

  void _scheduleProfileRefresh() {
    _profileRefreshDebounce?.cancel();
    _profileRefreshDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_loadUserSummary());
    });
  }

  void _scheduleFavoritesRefresh() {
    _favoritesRefreshDebounce?.cancel();
    _favoritesRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_loadFavoritesFromDb());
    });
  }

  Future<void> _subscribeToRealtimeCatalog() async {
    await _catalogChannel?.unsubscribe();
    _catalogChannel = supabase.channel('client-catalog');
    _catalogChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurants',
          callback: (_) {
            if (!mounted) return;
            _scheduleCatalogRefresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'daily_combos',
          callback: (_) {
            if (!mounted) return;
            _scheduleCatalogRefresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_shares',
          callback: (_) {
            if (!mounted) return;
            _scheduleCatalogRefresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'restaurant_share_events',
          callback: (_) {
            if (!mounted) return;
            _scheduleCatalogRefresh();
          },
        )
        .subscribe();
  }

  Future<void> _subscribeToRealtimeProfile(String userId) async {
    await _profileChannel?.unsubscribe();
    await _walletChannel?.unsubscribe();
    await _favoritesChannel?.unsubscribe();

    _profileChannel = supabase.channel('client-profile-$userId');
    _profileChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleProfileRefresh();
          },
        )
        .subscribe();

    _walletChannel = supabase.channel('client-wallet-$userId');
    _walletChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleProfileRefresh();
          },
        )
        .subscribe();

    _favoritesChannel = supabase.channel('client-favorites-$userId');
    _favoritesChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'favorites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleFavoritesRefresh();
          },
        )
        .subscribe();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncHomeLogoMarqueeAccessibility();
    if (_initialTabApplied) return;
    final tab = GoRouterState.of(context).uri.queryParameters['tab'];
    final index = _tabIndexFor(tab);
    if (index != null && index != _selectedIndex) {
      setState(() => _selectedIndex = index);
    }
    _initialTabApplied = true;
  }

  int? _tabIndexFor(String? tab) {
    switch (tab) {
      case 'home':
        return 0;
      case 'explore':
        return 1;
      case 'orders':
        return 2;
      case 'favorites':
        return 3;
      case 'profile':
        return 4;
      default:
        return null;
    }
  }

  Widget _buildBottomNavGif(String assetPath, {bool selected = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.all(selected ? 5 : 4),
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryRed.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Image.asset(
        assetPath,
        width: selected ? 26 : 22,
        height: selected ? 26 : 22,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
    );
  }

  Widget _buildCartQuickAction() {
    return Selector<CartService, int>(
      selector: (_, cart) => cart.itemCount,
      builder: (context, itemCount, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: () => context.push('/cart'),
              style: IconButton.styleFrom(
                backgroundColor: itemCount > 0
                    ? const Color(0xFFFFF4F2)
                    : const Color(0xFFF7F7F7),
              ),
              tooltip: 'Carrinho',
              icon: TweenAnimationBuilder<double>(
                key: ValueKey<int>(itemCount),
                tween: Tween<double>(
                  begin: itemCount > 0 ? 0.84 : 0.96,
                  end: 1,
                ),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: Image.asset(
                  _cartQuickAsset,
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                  ),
                  child: child,
                ),
                child: itemCount > 0
                    ? Container(
                        key: ValueKey<int>(itemCount),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryRed,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          itemCount > 99 ? '99+' : itemCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey<String>('empty')),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFloatingCartButton() {
    return Selector<CartService, int>(
      selector: (_, cart) => cart.itemCount,
      builder: (context, itemCount, _) {
        if (itemCount == 0) return const SizedBox.shrink();
        return FloatingActionButton.extended(
          heroTag: 'client-home-cart',
          onPressed: () => context.push('/cart'),
          backgroundColor: AppColors.primaryRed,
          foregroundColor: Colors.white,
          elevation: 8,
          icon: const Icon(Icons.shopping_cart_outlined),
          label: Text(
            '$itemCount ${itemCount == 1 ? 'item' : 'itens'} no carrinho',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        );
      },
    );
  }

  Future<void> _showDeligoAi() async {
    final controller = TextEditingController();
    String? answer;
    String? error;
    var loading = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFF7C3AED),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'DeliGo AI',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const Text(
                  'Encontra comida, explica taxas e acompanha pedidos.',
                  style: TextStyle(color: AppColors.neutralGray),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children:
                      [
                            'Tenho 300 MT. O que posso pedir?',
                            'Onde está o meu estafeta?',
                            'Porque a entrega custa este valor?',
                          ]
                          .map(
                            (prompt) => ActionChip(
                              label: Text(
                                prompt,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () => controller.text = prompt,
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Escreva ou fale com a DeliGo AI...',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (answer != null || error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: (error == null
                          ? const Color(0xFFF3E8FF)
                          : const Color(0xFFFFF1F2)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      answer ?? error!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: loading
                        ? null
                        : () async {
                            final message = controller.text.trim();
                            if (message.length < 2) return;
                            setModalState(() {
                              loading = true;
                              error = null;
                            });
                            try {
                              final tool =
                                  message.toLowerCase().contains('estafeta') ||
                                      message.toLowerCase().contains('pedido')
                                  ? 'get_order_status'
                                  : 'search_restaurants';
                              answer = await DeligoAiService.instance.ask(
                                message: message,
                                tool: tool,
                              );
                            } catch (e) {
                              error = e.toString().replaceFirst(
                                'Bad state: ',
                                '',
                              );
                            }
                            if (sheetContext.mounted) {
                              setModalState(() => loading = false);
                            }
                          },
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      loading ? 'A pensar...' : 'Perguntar à DeliGo AI',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _loadData({String reason = 'manual'}) {
    final activeLoad = _dashboardLoadInFlight;
    if (activeLoad != null) {
      _dashboardReloadQueued = true;
      _queuedDashboardReloadReason = reason;
      debugPrint('[CLIENT_LOAD] coalesced reason=$reason');
      return activeLoad;
    }

    final load = _performDashboardLoad(reason: reason);
    _dashboardLoadInFlight = load;
    return load.whenComplete(() {
      if (!identical(_dashboardLoadInFlight, load)) return;
      _dashboardLoadInFlight = null;
      if (!_dashboardReloadQueued || !mounted) return;
      final nextReason = _queuedDashboardReloadReason;
      _dashboardReloadQueued = false;
      unawaited(_loadData(reason: nextReason));
    });
  }

  Future<void> _performDashboardLoad({required String reason}) async {
    final loadVersion = ++_loadVersion;
    final loadStartedAt = DateTime.now();
    debugPrint('[CLIENT_LOAD] start request=$loadVersion reason=$reason');
    debugPrint('[EXPLORE] load start');
    debugPrint('[EXPLORE] source/reason=$reason');
    debugPrint('[EXPLORE] requestId=$loadVersion');
    debugPrint(
      '[EXPLORE] restaurants before=${_restaurants.length} dishes before=${_featuredDishes.length}',
    );
    unawaited(_syncServerClock(force: true, refreshUi: false));
    if (!mounted || loadVersion != _loadVersion) return;
    setState(() {
      _loadError = '';
      // Keep the last valid content during silent refreshes. Loading is only
      // shown for sections that have never produced a value yet.
      _loadingRestaurants = !_catalogLoaded && _restaurants.isEmpty;
      _loadingOrders = !_ordersLoaded && _activeOrder == null;
      if (_ordersLoaded) _ordersLoadFailed = false;
      if (!_catalogLoaded) {
        _page = 0;
        _hasMore = true;
      }
    });

    try {
      final summaryFuture = _loadUserSummary();
      // The active order is critical and must not wait for catalog/marketing
      // requests. It updates its own section as soon as the snapshot returns.
      final ordersFuture = _loadClientOrdersSnapshot().then((_) {
        debugPrint(
          '[CLIENT_LOAD] HOME_ACTIVE_ORDER_READY ms=${DateTime.now().difference(loadStartedAt).inMilliseconds}',
        );
      });
      unawaited(_loadSmartNotifications());
      unawaited(_loadHomeCombos(loadVersion));
      final catalogCoreFuture = Future.wait<dynamic>([
        _restaurantService.getFeaturedRestaurants(
          limit: 6,
          temperatureC: _weather?.temperatureC,
        ),
        _restaurantService.getRestaurants(
          temperatureC: _weather?.temperatureC,
          sortBy: _sortBy,
          limit: _pageSize,
          offset: 0,
        ),
      ]);

      final initialSnapshots = await Future.wait<dynamic>([
        summaryFuture,
        catalogCoreFuture,
      ]);
      unawaited(_restaurantShareService.hydratePendingInviteForCurrentUser());
      unawaited(_loadFavoritesFromDb());
      unawaited(_loadMarketingCampaignCenter());
      final core = initialSnapshots[1] as List<dynamic>;

      final featured = _visibleRestaurants(core[0] as List<Restaurant>);
      final all = _visibleRestaurants(core[1] as List<Restaurant>);

      debugPrint(
        '[EXPLORE] Supabase restaurants returned featured=${(core[0] as List).length} all=${(core[1] as List).length}',
      );

      final fast = List<Restaurant>.from(all.where((r) => r.isOpen));
      debugPrint(
        '[EXPLORE] after filters restaurants=${all.length} featured=${featured.length} fast=${fast.length}',
      );

      if (!mounted || loadVersion != _loadVersion) return;
      if (mounted) {
        setState(() {
          _featuredRestaurants = featured;
          _restaurants = all;
          _fastRestaurants = fast.take(6).toList();
          _hasMore = all.length >= _pageSize;
          _loadingRestaurants = false;
          _catalogLoaded = true;
        });
        debugPrint('[EXPLORE] state committed requestId=$loadVersion');
        unawaited(_loadLocalRestaurants(loadVersion));
        unawaited(_loadSecondaryHomeData(loadVersion, all));
        unawaited(_loadDeliveryEstimates(all, loadVersion));
      }

      // Orders are intentionally not awaited here: catalog refresh must not
      // delay or reset the already-rendered active-order card.
      unawaited(ordersFuture);
    } catch (e) {
      debugPrint('[EXPLORE] error requestId=$loadVersion error=$e');
      if (mounted && loadVersion == _loadVersion) {
        setState(() {
          _loadError = 'Nao foi possivel carregar. Verifique sua internet.';
          _loadingRestaurants = false;
        });
      }
    }
  }

  Future<void> _loadHomeCombos(int loadVersion) async {
    try {
      final combos = await _restaurantService.getActiveDailyCombosForHome(
        rethrowOnError: true,
      );
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() => _activeDailyCombos = combos);
    } catch (error) {
      debugPrint(
        '[CLIENT_LOAD] home combos request=$loadVersion failed: $error',
      );
      // Retain the last confirmed combo snapshot after a network failure.
    }
  }

  Future<void> _loadLocalRestaurants(int loadVersion) async {
    try {
      final local = await _restaurantService.getRestaurants(
        temperatureC: _weather?.temperatureC,
        sortBy: 'rating',
        neighborhood: _addressNeighborhood.isNotEmpty
            ? _addressNeighborhood
            : null,
        city: _addressCity.isNotEmpty ? _addressCity : null,
        limit: 6,
        offset: 0,
      );
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _localRestaurants = _visibleRestaurants(local);
        _localRestaurantsLoaded = true;
        _localRestaurantsLoadFailed = false;
      });
    } catch (error) {
      debugPrint(
        '[EXPLORE] local restaurants request=$loadVersion failed: $error',
      );
      if (mounted && loadVersion == _loadVersion) {
        setState(() {
          _localRestaurantsLoadFailed = !_localRestaurantsLoaded;
        });
      }
    }
  }

  Future<List<Order>> _loadClientOrdersSnapshot() async {
    try {
      final orders = await _orderService.getClientOrders(rethrowOnError: true);
      if (mounted) {
        setState(() {
          _clientOrders = orders;
          _activeOrder = _sanitizeActiveOrder(_selectHomeActiveOrder(orders));
          _loadingOrders = false;
          _ordersLoaded = true;
          _ordersLoadFailed = false;
        });
      }
      return orders;
    } catch (error) {
      debugPrint('[CLIENT_LOAD] orders failed: $error');
      if (mounted) {
        setState(() {
          _loadingOrders = false;
          _ordersLoadFailed = true;
        });
      }
      return _clientOrders;
    }
  }

  Future<void> _loadMarketingCampaignCenter() async {
    try {
      final sections = await _marketingService.fetchHomeCampaignSections(
        city: _addressCity,
        neighborhood: _addressNeighborhood,
        userId: supabase.auth.currentUser?.id,
        limit: 30,
      );
      final activeSections = _activeMarketingSections(sections);
      final campaigns = <Map<String, dynamic>>[];
      for (final section in activeSections) {
        final items = (section['items'] as List?) ?? const [];
        campaigns.addAll(
          items.whereType<Map>().map(
            (item) => item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
      final directCampaigns = await _marketingService.fetchClientCampaignCenter(
        city: _addressCity,
        neighborhood: _addressNeighborhood,
        userId: supabase.auth.currentUser?.id,
        limit: 30,
        homeSections: sections,
      );
      for (final campaign in directCampaigns.where(_isActiveMarketingItem)) {
        final id = campaign['id']?.toString();
        final eventId = campaign['event_id']?.toString();
        final exists = campaigns.any((item) {
          return (id != null &&
                  id.isNotEmpty &&
                  item['id']?.toString() == id) ||
              (eventId != null &&
                  eventId.isNotEmpty &&
                  item['event_id']?.toString() == eventId);
        });
        if (!exists) campaigns.add(campaign);
      }
      if (!mounted) return;
      setState(() {
        _marketingCampaignSections = activeSections;
        _marketingCampaigns = campaigns.where(_isActiveMarketingItem).toList();
      });
      // Campanhas permanecem disponíveis nos banners da página inicial.
      // Vídeos nunca interrompem automaticamente a entrada do cliente.
    } catch (error) {
      // A falha no refresh nao deve apagar campanhas anteriormente carregadas.
      debugPrint('[CLIENT_LOAD] campaign refresh failed: $error');
    }
  }

  void _maybeShowSplashVideoAd(List<Map<String, dynamic>> campaigns) {
    if (_splashVideoShownThisSession || !mounted) return;
    Map<String, dynamic>? selected;
    for (final campaign in campaigns) {
      final placement = campaign['placement']?.toString();
      final type = campaign['type']?.toString();
      final campaignType = campaign['campaign_type']?.toString();
      final videoUrl = _campaignVideoUrl(campaign);
      if (videoUrl.isEmpty) continue;
      if (placement == 'splash_screen' ||
          placement == 'video_ad' ||
          type == 'video' ||
          campaignType == 'video' ||
          ((campaign['metadata'] as Map?)?['autoplay_on_home'] == true)) {
        selected = campaign;
        break;
      }
    }
    if (selected == null) return;
    _splashVideoShownThisSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SplashVideoAdDialog(campaign: selected!),
      );
    });
  }

  String _campaignVideoUrl(Map<String, dynamic> campaign) {
    final direct = campaign['video_url']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    final metadata =
        (campaign['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    return metadata['video_url']?.toString().trim() ?? '';
  }

  Future<void> _loadSecondaryHomeData(
    int loadVersion,
    List<Restaurant> restaurants,
  ) async {
    try {
      final dishesFuture = _loadFeaturedDishes(restaurants);
      final shareStatsFuture = _restaurantShareService
          .getShareStatsForRestaurants(
            restaurants.map((restaurant) => restaurant.id).toList(),
          );
      final rankingFuture = _restaurantShareService.getTopSharedRestaurants(
        limit: 5,
      );
      try {
        final dishes = await dishesFuture;
        if (!mounted || loadVersion != _loadVersion) return;
        setState(() {
          _featuredDishes = dishes;
          _featuredDishesLoaded = true;
          _featuredDishesLoadFailed = false;
          _loadingFeaturedDishes = false;
        });
      } catch (error) {
        debugPrint('[EXPLORE] dishes refresh failed: $error');
        if (mounted && loadVersion == _loadVersion) {
          setState(() {
            _loadingFeaturedDishes = false;
            _featuredDishesLoadFailed = !_featuredDishesLoaded;
          });
        }
      }
      if (!mounted || loadVersion != _loadVersion) return;
      debugPrint(
        '[EXPLORE] Supabase dishes returned=${_featuredDishes.length} requestId=$loadVersion',
      );
      final shareResults = await Future.wait<dynamic>([
        shareStatsFuture,
        rankingFuture,
      ]);
      if (!mounted || loadVersion != _loadVersion) return;
      final shareStats = shareResults[0] as Map<String, Map<String, dynamic>>;
      final rankingRows = shareResults[1] as List<Map<String, dynamic>>;
      final restaurantNameById = {
        for (final restaurant in restaurants) restaurant.id: restaurant.name,
      };
      final ranking = rankingRows
          .map(
            (row) => {
              ...row,
              'restaurant_name':
                  restaurantNameById[row['restaurant_id']?.toString()] ??
                  'Restaurante',
            },
          )
          .toList();
      setState(() {
        _shareStatsByRestaurantId = shareStats;
        _topSharedRestaurants = ranking;
      });
      debugPrint(
        '[EXPLORE] after filters dishes=${_filteredFeaturedDishes.length}',
      );
      debugPrint('[EXPLORE] state committed secondary requestId=$loadVersion');
    } catch (_) {
      debugPrint('[EXPLORE] error secondary requestId=$loadVersion');
      // Dados secundarios nao devem bloquear a entrada no dashboard.
    }
  }

  Future<void> _loadUserSummary() {
    final active = _summaryLoadInFlight;
    if (active != null) return active;
    final future = _performUserSummaryLoad();
    _summaryLoadInFlight = future;
    return future.whenComplete(() {
      if (identical(_summaryLoadInFlight, future)) {
        _summaryLoadInFlight = null;
      }
    });
  }

  Future<void> _performUserSummaryLoad() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final results = await Future.wait<dynamic>([
        supabase
            .from('profiles')
            .select(
              'full_name, gender, address, fcm_token, avatar_url, settings',
            )
            .eq('id', user.id)
            .maybeSingle(),
        supabase
            .from('user_addresses')
            .select(
              'address, neighborhood, city, latitude, longitude, is_default',
            )
            .eq('user_id', user.id)
            .order('is_default', ascending: false)
            .limit(1)
            .maybeSingle(),
        supabase
            .from('wallets')
            .select(
              'balance,available_balance,pending_balance,currency,updated_at',
            )
            .eq('user_id', user.id)
            .order('updated_at', ascending: false)
            .limit(1)
            .maybeSingle(),
      ]);
      final profile = results[0] as Map<String, dynamic>?;
      final addressRow = results[1] as Map<String, dynamic>?;
      final wallet = results[2] as Map<String, dynamic>?;

      final settings =
          (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
      final favorites =
          (settings['favorites'] as List?)?.cast<String>() ??
          (user.userMetadata?['favorites'] as List?)?.cast<String>() ??
          <String>[];
      final hiddenOrderIds =
          (settings['hidden_orders'] as List?)?.cast<String>() ?? <String>[];
      final nextLat = (addressRow?['latitude'] as num?)?.toDouble();
      final nextLng = (addressRow?['longitude'] as num?)?.toDouble();
      final originChanged = nextLat != _userLat || nextLng != _userLng;
      if (originChanged) {
        MapsRouteService.clearCachedRoutes();
        _routeInfo = {};
      }

      if (mounted) {
        setState(() {
          _profileSettings = settings;
          _favorites = favorites.toSet();
          _hiddenOrderIds
            ..clear()
            ..addAll(hiddenOrderIds);
          _displayName =
              (profile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? (profile?['full_name'] as String)
              : (user.email?.split('@').first ?? 'cliente');
          _walletBalance =
              (wallet?['available_balance'] as num?)?.toDouble() ??
              (wallet?['balance'] as num?)?.toDouble() ??
              _walletBalance;
          _walletCurrency = (wallet?['currency'] as String?) ?? 'MZN';
          _isTestWallet = EcosystemTestPersona.matches(user);
          _address =
              (addressRow?['address'] as String?) ??
              (profile?['address'] as String?) ??
              '';
          _addressNeighborhood = (addressRow?['neighborhood'] as String?) ?? '';
          _addressCity = (addressRow?['city'] as String?) ?? '';
          _userLat = nextLat;
          _userLng = nextLng;
          _pushActive = (profile?['fcm_token'] as String?)?.isNotEmpty == true;
          _avatarUrl = profile?['avatar_url'] as String?;
          final scheduledRaw = settings['scheduled_for'] as String?;
          _scheduledDelivery = scheduledRaw != null
              ? DateTime.tryParse(scheduledRaw)
              : null;
          _groupOrderCode = settings['group_order_code'] as String?;
          _profileHydrated = true;
          _profileLoadFailed = false;
        });
      }

      unawaited(
        WelcomeVoiceService.instance.greetOnce(
          userId: user.id,
          name: (profile?['full_name'] as String?)?.trim().isNotEmpty == true
              ? (profile?['full_name'] as String)
              : (user.email?.split('@').first ?? 'cliente'),
          role: 'client',
          gender: profile?['gender']?.toString(),
          languageCode: settings['language']?.toString(),
          voiceMode: settings['voice_mode']?.toString(),
        ),
      );

      unawaited(_loadWeather());
    } catch (_) {
      if (mounted) setState(() => _profileLoadFailed = true);
    }
  }

  Future<void> _loadWeather() async {
    if (_loadingWeather) return;
    _loadingWeather = true;
    try {
      final weather = await WeatherService.instance.fetchWeather(
        latitude: _userLat,
        longitude: _userLng,
        city: _addressCity.isNotEmpty ? _addressCity : _addressNeighborhood,
      );
      if (!mounted) return;
      setState(() => _weather = weather);
    } finally {
      _loadingWeather = false;
    }
  }

  Future<List<Map<String, dynamic>>> _loadFeaturedDishes(
    List<Restaurant> restaurants,
  ) async {
    try {
      final rows = <Map<String, dynamic>>[];
      const pageSize = 500;
      for (var offset = 0; ; offset += pageSize) {
        final page = await supabase
            .from('menu_items')
            .select(
              'id,restaurant_id,name,description,price,image_url,category,item_rating,prep_time_minutes,is_available',
            )
            .eq('is_available', true)
            .range(offset, offset + pageSize - 1);
        final pageRows = (page as List).cast<Map<String, dynamic>>();
        rows.addAll(pageRows);
        if (pageRows.length < pageSize) break;
      }

      final restaurantById = {for (final r in restaurants) r.id: r};
      return rows
          .where((item) => restaurantById.containsKey(item['restaurant_id']))
          .map((item) {
            final restaurant = restaurantById[item['restaurant_id']]!;
            return {
              ...item,
              'restaurant_name': restaurant.name,
              'restaurant_image_url': restaurant.imageUrl,
              'restaurant_is_open': restaurant.isOpen,
              'delivery_fee': restaurant.deliveryFee ?? 100,
              'delivery_time': restaurant.deliveryTime ?? 25,
            };
          })
          .toList();
    } catch (_) {
      debugPrint('[EXPLORE] load dishes error; preserving previous result');
      rethrow;
    }
  }

  String _normalizeCategoryLabel(String label) {
    return DeligoFoodCategories.normalize(label);
  }

  List<Map<String, dynamic>> get _filteredFeaturedDishes {
    final normalized = _normalizeCategoryLabel(_selectedFoodCategory);
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _featuredDishes.where((dish) {
      final category = DeligoFoodCategories.resolve(
        dish['category'] as String?,
      ).label;
      final categoryMatches =
          _selectedFoodCategory == DeligoFoodCategories.all.label ||
          _normalizeCategoryLabel(category) == normalized;
      if (!categoryMatches) return false;
      if (query.isEmpty) return true;
      final haystack = [
        dish['name'],
        dish['description'],
        dish['category'],
        dish['restaurant_name'],
      ].whereType<Object>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    if (_explorePopularDishes) {
      filtered.sort(
        (a, b) => ((b['item_rating'] as num?) ?? 0).compareTo(
          (a['item_rating'] as num?) ?? 0,
        ),
      );
    }
    return filtered;
  }

  List<Restaurant> _visibleRestaurants(List<Restaurant> restaurants) =>
      List<Restaurant>.from(restaurants);

  Widget _buildActiveOrderLoadingSkeleton() {
    return Container(
      height: 132,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE9E9E9)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 14,
              width: 150,
              decoration: BoxDecoration(
                color: const Color(0xFFEDEDED),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 22,
              width: 230,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 12,
              width: 190,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F2),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshActiveOrder() async {
    final activeLoad = _ordersLoadInFlight;
    if (activeLoad != null) {
      _ordersReloadQueued = true;
      return activeLoad;
    }
    final load = _performOrdersRefresh();
    _ordersLoadInFlight = load;
    await load.whenComplete(() {
      if (!identical(_ordersLoadInFlight, load)) return;
      _ordersLoadInFlight = null;
      if (_ordersReloadQueued && mounted) {
        _ordersReloadQueued = false;
        unawaited(_refreshActiveOrder());
      }
    });
  }

  Future<void> _performOrdersRefresh() async {
    final refreshEpoch = ++_ordersRefreshEpoch;
    try {
      final previousOrder = _activeOrder;
      final orders = await _orderService.getClientOrders(rethrowOnError: true);
      final active = _selectHomeActiveOrder(orders);
      final motionAssessment = await _assessActiveCourierMotion(active);
      if (mounted && refreshEpoch == _ordersRefreshEpoch) {
        setState(() {
          _clientOrders = orders;
          _loadingOrders = false;
          _ordersLoaded = true;
          _ordersLoadFailed = false;
          _activeCourierMotionAssessment = motionAssessment;
        });
        _applyActiveOrderUpdate(
          _sanitizeActiveOrder(active),
          previousOrder: previousOrder,
        );
      }
    } catch (error) {
      debugPrint('[CLIENT_LOAD] orders refresh failed: $error');
      if (mounted && !_ordersLoaded) {
        setState(() {
          _loadingOrders = false;
          _ordersLoadFailed = true;
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _assessActiveCourierMotion(Order? order) async {
    if (order == null ||
        !order.isDelivery ||
        order.courierId?.trim().isEmpty != false ||
        order.pickedUpAt != null ||
        order.status != OrderStatus.courierAssigned) {
      return null;
    }
    try {
      final response = await Supabase.instance.client.rpc(
        'assess_courier_motion',
        params: {'p_order_id': order.id},
      );
      return response is Map ? Map<String, dynamic>.from(response) : null;
    } catch (error) {
      debugPrint('[CLIENT_MOTION] assessment unavailable: $error');
      return null;
    }
  }

  Order? _selectHomeActiveOrder(List<Order> orders) {
    final ranked = _activeOrdersByPriority(orders);
    return ranked.isEmpty ? null : ranked.first;
  }

  List<Order> _activeOrdersByPriority(Iterable<Order> orders) {
    final uniqueOrders = <String, Order>{};
    for (final order in orders) {
      if (_isActiveOrder(order)) uniqueOrders[order.id] = order;
    }
    final activeOrders = uniqueOrders.values.toList();
    activeOrders.sort((a, b) {
      final actionPriority = (_requiresImmediateCustomerAction(b) ? 1 : 0)
          .compareTo(_requiresImmediateCustomerAction(a) ? 1 : 0);
      if (actionPriority != 0) return actionPriority;

      final newestFirst = b.createdAt.compareTo(a.createdAt);
      if (newestFirst != 0) return newestFirst;
      final latestUpdateFirst = (b.updatedAt ?? b.createdAt).compareTo(
        a.updatedAt ?? a.createdAt,
      );
      if (latestUpdateFirst != 0) return latestUpdateFirst;
      return a.id.compareTo(b.id);
    });
    return activeOrders;
  }

  bool _requiresImmediateCustomerAction(Order order) {
    if (order.deliveryStatus.toLowerCase() == 'delivery_unavailable' &&
        order.courierId?.trim().isNotEmpty != true) {
      return true;
    }
    if (_isAwaitingPayment(order)) return true;
    if (order.isPickup &&
        (order.status == OrderStatus.ready ||
            order.status == OrderStatus.awaitingPickupConfirmation)) {
      return true;
    }
    return order.status == OrderStatus.delivered;
  }

  int _otherActiveOrderCount() {
    final visibleOrderId = _activeOrder?.id;
    final seenIds = <String>{};
    var count = 0;
    for (final order in _clientOrders) {
      if (order.id == visibleOrderId ||
          !seenIds.add(order.id) ||
          !_isActiveOrder(order)) {
        continue;
      }
      count++;
    }
    return count;
  }

  Widget _buildOtherActiveOrdersIndicator() {
    final count = _otherActiveOrderCount();
    if (count == 0) return const SizedBox.shrink();
    final label = count == 1 ? 'pedido ativo' : 'pedidos ativos';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => setState(() => _selectedIndex = 2),
          icon: const Icon(Icons.receipt_long_outlined, size: 17),
          label: Text('+ $count $label · Ver todos'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryRed,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
        ),
      ),
    );
  }

  bool _isActiveOrder(Order order) {
    if (_isTimedOutRestaurantConfirmationOrder(order)) return false;
    final status = order.status;
    final isActiveStatus =
        status == OrderStatus.pending ||
        status == OrderStatus.paymentAuthorized ||
        status == OrderStatus.paid ||
        status == OrderStatus.accepted ||
        status == OrderStatus.preparing ||
        status == OrderStatus.ready ||
        status == OrderStatus.courierAssigned ||
        status == OrderStatus.inTransit ||
        status == OrderStatus.onTheWay ||
        status == OrderStatus.arrived ||
        status == OrderStatus.deliveryFailedOtp ||
        status == OrderStatus.delivered ||
        status == OrderStatus.disputed;
    if (!isActiveStatus) return false;
    if (status == OrderStatus.ready &&
        order.deliveryType == 'pickup' &&
        (order.paymentStatus == 'completed' ||
            order.paymentStatus == 'authorized')) {
      final reference = order.updatedAt ?? order.createdAt;
      if (_serverNow.difference(reference) > const Duration(minutes: 30)) {
        return false;
      }
    }
    return true;
  }

  bool _isTimedOutRestaurantConfirmationOrder(Order order) {
    if (!_isAwaitingRestaurantConfirmation(order)) return false;
    final deadline = order.restaurantConfirmationStartedAt.add(
      const Duration(minutes: 3),
    );
    return !deadline.isAfter(_currentDateTime);
  }

  void _hideTimedOutOrdersIfNeeded() {
    final timedOutIds = _clientOrders
        .where(_isTimedOutRestaurantConfirmationOrder)
        .map((order) => order.id)
        .where((id) => !_timedOutHiddenOrderIds.contains(id))
        .toList(growable: false);
    if (timedOutIds.isEmpty) return;

    setState(() {
      _timedOutHiddenOrderIds.addAll(timedOutIds);
      _activeOrder = _sanitizeActiveOrder(_activeOrder);
    });
    _scheduleOrdersRefresh();
  }

  void _maybeRefreshTimedOutRestaurantConfirmation() {
    final now = _currentDateTime;
    final hasTimedOutAwaitingRestaurant = _clientOrders.any(
      _isTimedOutRestaurantConfirmationOrder,
    );
    if (!hasTimedOutAwaitingRestaurant) return;

    if (_lastTimedOutRestaurantRefreshAt != null &&
        now.difference(_lastTimedOutRestaurantRefreshAt!) <
            const Duration(seconds: 5)) {
      return;
    }

    _lastTimedOutRestaurantRefreshAt = now;
    unawaited(_refreshActiveOrder());
  }

  bool _hasExpiredPreparationCountdown(Order order) {
    if (order.status != OrderStatus.accepted &&
        order.status != OrderStatus.preparing) {
      return false;
    }
    return _preparationRemaining(order) == Duration.zero;
  }

  bool _hasExpiredPendingPaymentCountdown(Order order) {
    return _isAwaitingPayment(order) &&
        _pendingPaymentRemaining(order) == Duration.zero;
  }

  bool _hasExpiredOperationalCountdown(Order order) {
    return _hasExpiredPendingPaymentCountdown(order) ||
        _isTimedOutRestaurantConfirmationOrder(order) ||
        _hasExpiredPreparationCountdown(order);
  }

  void _maybeRefreshExpiredOrderCountdowns() {
    final now = _currentDateTime;
    final hasExpiredCountdown = _clientOrders.any(
      _hasExpiredOperationalCountdown,
    );
    if (!hasExpiredCountdown) return;

    if (_lastExpiredCountdownRefreshAt != null &&
        now.difference(_lastExpiredCountdownRefreshAt!) <
            const Duration(seconds: 5)) {
      return;
    }

    _lastExpiredCountdownRefreshAt = now;
    unawaited(_refreshActiveOrder());
  }

  Duration? _deliverySearchRemaining(Order order) {
    final deadline =
        _optimisticDeliverySearchDeadlines[order.id] ?? order.dispatchExpiresAt;
    if (deadline == null) return null;
    final remaining = deadline.difference(_currentDateTime);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _checkDeliverySearchDeadlines() {
    final active = _activeOrder;
    if (active == null || !_hasActiveCourierDispatch(active)) return;
    final remaining = _deliverySearchRemaining(active);
    if (remaining != null && remaining != Duration.zero) return;
    final attempt = active.dispatchAttemptId ?? 'missing-attempt';
    final refreshKey = '${active.id}:$attempt';
    if (_refreshedExpiredDispatchAttempts.add(refreshKey)) {
      // Ask the backend to finalize only after its own clock confirms expiry.
      // This RPC serializes against courier acceptance; the phone never writes
      // delivery_status or cancels dispatch locally.
      unawaited(_finalizeExpiredDispatchSearch(active, refreshKey));
    }
  }

  Future<void> _finalizeExpiredDispatchSearch(
    Order order,
    String refreshKey,
  ) async {
    final result = await _orderService.expireDeliverySearchForCustomer(
      order.id,
    );
    if (!mounted) return;

    if (result.data['code']?.toString() == 'search_not_expired') {
      _refreshedExpiredDispatchAttempts.remove(refreshKey);
      await _syncServerClock(force: true, refreshUi: false);
    }
    await _refreshActiveOrder();
  }

  Order? _sanitizeActiveOrder(Order? order) {
    if (order == null) return null;
    return _isActiveOrder(order) ? order : null;
  }

  bool _isDeliveryFlowClosed(OrderStatus status) {
    return status == OrderStatus.delivered ||
        status == OrderStatus.completed ||
        status == OrderStatus.autoCompleted;
  }

  String _notificationOrderId(Map<String, dynamic> notification) {
    final entityId = notification['entity_id']?.toString().trim() ?? '';
    if (entityId.isNotEmpty) return entityId;

    final metadata =
        (notification['metadata'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final data =
        (notification['data'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final metadataOrderId = metadata['order_id']?.toString().trim() ?? '';
    if (metadataOrderId.isNotEmpty) return metadataOrderId;

    return data['order_id']?.toString().trim() ?? '';
  }

  Order? _trackedOrderById(String orderId) {
    if (orderId.isEmpty) return null;
    if (_activeOrder?.id == orderId) return _activeOrder;
    for (final order in _clientOrders) {
      if (order.id == orderId) return order;
    }
    return null;
  }

  bool _markDriverAssignedPopupShown(String orderId) {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return true;
    return _driverAssignedPopupOrderIds.add(normalizedOrderId);
  }

  bool _shouldSuppressRealtimePopup(Map<String, dynamic> notification) {
    final orderId = _notificationOrderId(notification);
    final order = _trackedOrderById(orderId);
    if (order == null) {
      return false;
    }

    final status = order.status;
    final isClosed = _isDeliveryFlowClosed(status);

    switch (notification['type']?.toString()) {
      case 'DRIVER_ASSIGNED':
        return status == OrderStatus.courierAssigned ||
            status == OrderStatus.inTransit ||
            status == OrderStatus.onTheWay ||
            status == OrderStatus.arrived ||
            status == OrderStatus.delivered ||
            isClosed;
      case 'ORDER_PICKED_UP':
        return status == OrderStatus.inTransit ||
            status == OrderStatus.onTheWay ||
            status == OrderStatus.arrived ||
            status == OrderStatus.delivered ||
            isClosed;
      case 'DRIVER_ARRIVED':
        return status == OrderStatus.arrived ||
            status == OrderStatus.delivered ||
            isClosed;
      case 'ORDER_DELIVERED':
        return status == OrderStatus.delivered || isClosed;
      case 'ORDER_COMPLETED':
      case 'ORDER_AUTO_COMPLETED':
        return status == OrderStatus.completed ||
            status == OrderStatus.autoCompleted;
      default:
        return false;
    }
  }

  void _applyActiveOrderUpdate(
    Order? nextOrder, {
    Order? previousOrder,
    bool allowPopup = true,
  }) {
    final previous = previousOrder ?? _activeOrder;
    final rawNext = nextOrder;
    setState(() {
      _activeOrder = _sanitizeActiveOrder(
        _selectHomeActiveOrder(_clientOrders),
      );
    });

    if (!allowPopup || !mounted) return;

    if (rawNext != null && rawNext.status == OrderStatus.cancelled) {
      _showOrderPopupOnce(
        popupKey: 'cancelled:${rawNext.id}',
        title: 'Pedido cancelado',
        message: 'O pedido foi cancelado e o valor voltou para a sua conta.',
        backgroundColor: Colors.orange.shade700,
        icon: Icons.account_balance_wallet_rounded,
      );
      return;
    }

    if (previous == null || nextOrder == null) return;
    if (previous.id != nextOrder.id || previous.status == nextOrder.status) {
      return;
    }

    if (_isDeliveryFlowClosed(nextOrder.status)) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    if (nextOrder.status == OrderStatus.accepted ||
        nextOrder.status == OrderStatus.preparing) {
      _showOrderPopupOnce(
        popupKey: 'event:confirmed:${nextOrder.id}',
        title: 'Pedido confirmado',
        message: 'O restaurante confirmou o pedido e iniciou o preparo.',
        backgroundColor: AppColors.successGreen,
        icon: Icons.check_circle_outline_rounded,
        playSound: true,
      );
    } else if (nextOrder.status == OrderStatus.ready) {
      _showOrderPopupOnce(
        popupKey: 'event:ready:${nextOrder.id}',
        title: 'Pedido pronto para retirar',
        message: 'O pedido terminou o preparo e ja pode ser retirado.',
        backgroundColor: AppColors.primaryRed,
        icon: Icons.inventory_2_rounded,
      );
    } else if (nextOrder.status == OrderStatus.courierAssigned) {
      if (_markDriverAssignedPopupShown(nextOrder.id)) {
        _showOrderPopupOnce(
          popupKey: 'event:driver_assigned:${nextOrder.id}',
          title: 'Estafeta atribuido',
          message: 'Ja existe estafeta associado ao teu pedido.',
          backgroundColor: const Color(0xFF102A43),
          icon: Icons.delivery_dining_rounded,
          duration: _popupDuration,
        );
      }
    } else if (nextOrder.status == OrderStatus.inTransit) {
      _showOrderPopupOnce(
        popupKey: 'event:picked_up:${nextOrder.id}',
        title: 'Estafeta ja levantou o pedido',
        message: 'O teu codigo de entrega ja esta no app.',
        backgroundColor: const Color(0xFF102A43),
        icon: Icons.delivery_dining_rounded,
      );
    } else if (nextOrder.status == OrderStatus.arrived) {
      _showOrderPopupOnce(
        popupKey: 'arrived:${nextOrder.id}:${nextOrder.status.name}',
        title: 'Estafeta chegou',
        message:
            'O estafeta ja chegou ao destino. Abra o pedido para confirmar a entrega.',
        backgroundColor: const Color(0xFF0F766E),
        icon: Icons.location_on_rounded,
      );
    } else if (nextOrder.status == OrderStatus.delivered) {
      _showOrderPopupOnce(
        popupKey: 'delivered:${nextOrder.id}',
        title: 'Entrega validada',
        message:
            'O OTP ja foi confirmado. Falta apenas a sua confirmacao final no app.',
        backgroundColor: AppColors.successGreen,
        icon: Icons.verified_rounded,
      );
    } else if (nextOrder.status == OrderStatus.completed ||
        nextOrder.status == OrderStatus.autoCompleted) {
      if (_closedOrderPopupOrderIds.contains(nextOrder.id)) {
        return;
      }
      _closedOrderPopupOrderIds.add(nextOrder.id);
      _showOrderPopupOnce(
        popupKey: 'closed:${nextOrder.id}',
        title: 'Pedido concluido',
        message: 'A entrega foi fechada com sucesso.',
        backgroundColor: AppColors.successGreen,
        icon: Icons.task_alt_rounded,
        duration: _briefCompletionPopupDuration,
      );
    }
  }

  bool _isCourierSearchWindow(Order order) {
    final optimisticDeadline = _optimisticDeliverySearchDeadlines[order.id];
    if (optimisticDeadline != null &&
        optimisticDeadline.toUtc().isAfter(_currentDateTime.toUtc()) &&
        order.isDelivery &&
        order.courierId?.trim().isEmpty != false &&
        order.status == OrderStatus.ready) {
      return true;
    }
    return _hasActiveCourierDispatch(order) &&
        order.dispatchExpiresAt != null &&
        order.dispatchExpiresAt!.toUtc().isAfter(_currentDateTime.toUtc());
  }

  /// The attempt remains an active server-owned dispatch while the backend is
  /// finalizing its deadline. This must not fall back to "Pronto para
  /// entrega" merely because the local countdown reached zero.
  bool _hasActiveCourierDispatch(Order order) {
    final optimisticDeadline = _optimisticDeliverySearchDeadlines[order.id];
    if (optimisticDeadline != null &&
        optimisticDeadline.toUtc().isAfter(_currentDateTime.toUtc()) &&
        order.isDelivery &&
        order.courierId?.trim().isEmpty != false &&
        order.status == OrderStatus.ready) {
      return true;
    }
    return order.isDelivery &&
        order.deliveryStatus.toLowerCase() == 'searching' &&
        order.courierId?.trim().isEmpty != false &&
        order.status == OrderStatus.ready &&
        order.dispatchStartedAt != null &&
        order.dispatchAttemptId?.trim().isNotEmpty == true &&
        order.dispatchExpiresAt != null;
  }

  void _showOrderPopupOnce({
    required String popupKey,
    required String title,
    required String message,
    required Color backgroundColor,
    required IconData icon,
    bool playSound = false,
    Duration duration = _popupDuration,
  }) {
    if (!_shownClientPopupKeys.add(popupKey)) return;
    final voiceType = _voiceTypeForPopup(title, message);
    if (voiceType != null) {
      unawaited(
        AppVoiceService.instance.speakNotification(
          type: voiceType,
          title: title,
          body: message,
          notificationId: 'client_popup_$popupKey',
          channel: 'client_alert',
          priority: 'HIGH',
        ),
      );
    }
    _showOrderPopup(
      title: title,
      message: message,
      backgroundColor: backgroundColor,
      icon: icon,
      playSound: playSound,
      duration: duration,
    );
  }

  String? _voiceTypeForPopup(String title, String message) {
    final text = '$title $message'.toLowerCase();
    if (text.contains('pedido confirmado')) return 'ORDER_ACCEPTED';
    if (text.contains('pedido pronto')) return 'ORDER_READY';
    if (text.contains('estafeta atribuido')) return 'DRIVER_ASSIGNED';
    if (text.contains('levantou')) return 'ORDER_PICKED_UP';
    if (text.contains('chegou')) return 'DRIVER_ARRIVED';
    if (text.contains('entrega validada')) return 'ORDER_DELIVERED';
    if (text.contains('pedido concluido')) return 'ORDER_COMPLETED';
    if (text.contains('cancelado')) return 'ORDER_CANCELLED';
    return null;
  }

  void _showOrderPopup({
    required String title,
    required String message,
    required Color backgroundColor,
    required IconData icon,
    bool playSound = false,
    Duration duration = _popupDuration,
  }) {
    // O som pertence à chegada da notificação realtime, não à abertura,
    // atualização ou leitura do cartão de notificações.
    if (playSound) {
      unawaited(SoundController.instance.shortBang());
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: backgroundColor,
          duration: duration,
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(message, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _showRealtimeNotificationPopup(Map<String, dynamic> notification) {
    final normalizedNotification = _normalizeNotification(notification);
    if (_shouldSuppressRealtimePopup(normalizedNotification)) {
      return;
    }
    final type = normalizedNotification['type']?.toString() ?? '';
    final orderId = _notificationOrderId(normalizedNotification);
    final lifecyclePopupKey = orderId.isEmpty
        ? ''
        : switch (type) {
            'ORDER_ACCEPTED' || 'ORDER_PREPARING' => 'event:confirmed:$orderId',
            'ORDER_READY' => 'event:ready:$orderId',
            'DRIVER_ASSIGNED' => 'event:driver_assigned:$orderId',
            'ORDER_PICKED_UP' => 'event:picked_up:$orderId',
            'DRIVER_ARRIVED' => 'event:driver_arrived:$orderId',
            _ => '',
          };
    if (lifecyclePopupKey.isNotEmpty &&
        !_shownClientPopupKeys.add(lifecyclePopupKey)) {
      return;
    }
    if (lifecyclePopupKey.isEmpty) {
      final notificationId =
          normalizedNotification['id']?.toString().trim() ?? '';
      final realtimePopupKey = notificationId.isNotEmpty
          ? 'realtime:$notificationId'
          : 'realtime:$type:$orderId:${normalizedNotification['title']?.toString().trim() ?? ''}';
      if (!_shownClientPopupKeys.add(realtimePopupKey)) {
        return;
      }
    }
    if (type == 'DRIVER_ASSIGNED' && !_markDriverAssignedPopupShown(orderId)) {
      return;
    }
    final popup = _realtimePopupFor(type);
    if (popup == null) return;

    final title = normalizedNotification['title']?.toString().trim();
    final body = normalizedNotification['body']?.toString().trim();
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }

    unawaited(SoundController.instance.shortBang());
    final duration = switch (type) {
      'ORDER_DELIVERED' ||
      'ORDER_COMPLETED' ||
      'ORDER_AUTO_COMPLETED' => _briefCompletionPopupDuration,
      _ => _popupDuration,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: popup.backgroundColor,
          duration: duration,
          content: Row(
            children: [
              Icon(popup.icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title?.isNotEmpty == true ? title! : 'Nova mensagem',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (body?.isNotEmpty == true)
                      Text(body!, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _convertUnavailableDeliveryFromCard(Order order) async {
    final searchExpiredOnClientClock =
        order.deliveryStatus.toLowerCase() == 'searching' &&
        order.dispatchExpiresAt != null &&
        !order.dispatchExpiresAt!.toUtc().isAfter(_currentDateTime.toUtc());
    if (searchExpiredOnClientClock) {
      await _orderService.expireDeliverySearchForCustomer(order.id);
    }
    final result = await _orderService.convertUnavailableDeliveryToPickup(
      order.id,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) {
      unawaited(_refreshActiveOrder());
      if (mounted) context.push('/order/${order.id}');
    }
  }

  Future<void> _restartDeliverySearchFromCard(Order order) async {
    // Give immediate feedback while the server creates the authoritative
    // dispatch attempt. The deadline is replaced by the server response on
    // success, or removed again if the RPC rejects the restart.
    final optimisticDeadline = _currentDateTime.add(const Duration(minutes: 5));
    if (mounted) {
      setState(() {
        _optimisticDeliverySearchDeadlines[order.id] = optimisticDeadline;
      });
    }
    final result = await _orderService.restartDeliverySearch(order.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) {
      final searchWindowMinutes =
          int.tryParse(
            result.data['search_window_minutes']?.toString() ?? '',
          ) ??
          5;
      final minutes = searchWindowMinutes > 0 ? searchWindowMinutes : 5;
      setState(() {
        _optimisticDeliverySearchDeadlines[order.id] = _currentDateTime.add(
          Duration(minutes: minutes),
        );
      });
      unawaited(_refreshActiveOrder());
    } else {
      setState(() {
        _optimisticDeliverySearchDeadlines.remove(order.id);
      });
    }
  }

  ({Color backgroundColor, IconData icon})? _realtimePopupFor(String type) {
    switch (type) {
      case 'MESSAGE_RECEIVED':
        return (
          backgroundColor: const Color(0xFF1E293B),
          icon: Icons.chat_bubble_rounded,
        );
      case 'ORDER_CANCELLED':
      case 'ORDER_EXPIRED':
      case 'PAYMENT_FAILED':
      case 'ORDER_REJECTED':
        return (
          backgroundColor: Colors.orange.shade700,
          icon: Icons.cancel_outlined,
        );
      case 'ORDER_READY':
        return (
          backgroundColor: AppColors.primaryRed,
          icon: Icons.inventory_2_rounded,
        );
      case 'ORDER_ACCEPTED':
      case 'ORDER_PREPARING':
        return (
          backgroundColor: AppColors.successGreen,
          icon: Icons.receipt_long_rounded,
        );
      case 'DRIVER_ASSIGNED':
        return (
          backgroundColor: const Color(0xFF102A43),
          icon: Icons.delivery_dining_rounded,
        );
      case 'ORDER_PICKED_UP':
        return (
          backgroundColor: const Color(0xFF102A43),
          icon: Icons.delivery_dining_rounded,
        );
      case 'DRIVER_ARRIVED':
        return (
          backgroundColor: const Color(0xFF0F766E),
          icon: Icons.location_on_rounded,
        );
      case 'ORDER_DELIVERED':
      case 'ORDER_COMPLETED':
      case 'ORDER_AUTO_COMPLETED':
        return (
          backgroundColor: AppColors.successGreen,
          icon: Icons.task_alt_rounded,
        );
      case 'ORDER_DISPUTED':
      case 'DELIVERY_OTP_FAILED_AUDIT':
        return (
          backgroundColor: Colors.orange.shade700,
          icon: Icons.warning_amber_rounded,
        );
      default:
        return null;
    }
  }

  Duration _restaurantConfirmationRemaining(Order order) {
    final deadline = order.restaurantConfirmationStartedAt.add(
      const Duration(minutes: 3),
    );
    final remaining = deadline.difference(_currentDateTime);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration _preparationRemaining(Order order) {
    final startedAt = order.preparationReference;
    final deadline = startedAt.add(
      Duration(minutes: order.estimatedPreparationMinutes),
    );
    final remaining = deadline.difference(_currentDateTime);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration _pendingPaymentRemaining(Order order) {
    final deadline = order.createdAt.add(const Duration(minutes: 15));
    final remaining = deadline.difference(_currentDateTime);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool _isAwaitingPayment(Order order) {
    if (order.status != OrderStatus.pending) return false;
    return !order.hasConfirmedPayment && !order.fundsHeldInEscrow;
  }

  bool _isAwaitingRestaurantConfirmation(Order order) {
    return order.status == OrderStatus.paymentAuthorized ||
        order.status == OrderStatus.paid ||
        (order.status == OrderStatus.pending &&
            (order.hasConfirmedPayment || order.fundsHeldInEscrow));
  }

  double _progressForActiveOrder(
    Order order, {
    required bool isAwaitingRestaurant,
    required bool isAwaitingPayment,
  }) {
    final totalSeconds = isAwaitingPayment
        ? 900
        : isAwaitingRestaurant
        ? 180
        : (order.estimatedPreparationMinutes * 60).clamp(60, 3600);
    final remainingSeconds =
        (isAwaitingPayment
                ? _pendingPaymentRemaining(order)
                : isAwaitingRestaurant
                ? _restaurantConfirmationRemaining(order)
                : _preparationRemaining(order))
            .inSeconds
            .clamp(0, totalSeconds);
    final progress = 1 - (remainingSeconds / totalSeconds);
    return progress.clamp(0, 1);
  }

  String _formatRemaining(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 1 << 31);
    final mm = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _activeOrderStatusLabel(Order order) {
    if (order.deliveryStatus.toLowerCase() == 'delivery_unavailable' &&
        order.courierId?.trim().isNotEmpty != true) {
      return 'Não encontrámos estafeta disponível';
    }
    switch (order.status) {
      case OrderStatus.pending:
        return _isAwaitingPayment(order)
            ? 'Aguardando pagamento'
            : 'Pago e a espera do restaurante';
      case OrderStatus.paymentAuthorized:
      case OrderStatus.paid:
        return 'Pago e a espera do restaurante';
      case OrderStatus.accepted:
        return 'Em preparacao';
      case OrderStatus.preparing:
        return 'Em preparacao';
      case OrderStatus.ready:
      case OrderStatus.awaitingPickupConfirmation:
        return order.isPickup
            ? (order.isCustomerPickupFallback
                  ? 'Levantamento no restaurante'
                  : 'Pronto para retirada')
            : _isSearchingNearbyCourier(order)
            ? 'Pronto — a procurar estafeta'
            : 'Pronto para entrega';
      case OrderStatus.pickedUp:
      case OrderStatus.inDelivery:
        return _hasAssignedCourier(order)
            ? 'Entrega em andamento'
            : 'Aguardando atribuição do estafeta';
      case OrderStatus.courierAssigned:
        return _hasAssignedCourier(order)
            ? 'Estafeta a caminho do restaurante'
            : 'Aguardando atribuição do estafeta';
      case OrderStatus.inTransit:
      case OrderStatus.onTheWay:
        return _hasAssignedCourier(order)
            ? 'Pedido a caminho'
            : 'Aguardando atribuição do estafeta';
      case OrderStatus.arrived:
        return 'Estafeta chegou';
      case OrderStatus.deliveryFailedOtp:
        return 'Entrega em revisao admin';
      case OrderStatus.delivered:
        return 'Aguardando tua confirmacao';
      case OrderStatus.disputed:
        return 'Problema reportado';
      case OrderStatus.autoCompleted:
      case OrderStatus.completed:
        return 'Concluido';
      case OrderStatus.refunded:
        return 'Reembolsado';
      case OrderStatus.expired:
        return 'Expirado';
      case OrderStatus.paymentFailed:
        return 'Falha no pagamento';
      case OrderStatus.cancelled:
        return 'Cancelado';
    }
  }

  String _activeOrderSubtitle(Order order) {
    if (order.deliveryStatus.toLowerCase() == 'delivery_unavailable' &&
        order.courierId?.trim().isNotEmpty != true) {
      return 'Escolha levantar no restaurante ou iniciar uma nova procura de 5 minutos.';
    }
    switch (order.status) {
      case OrderStatus.pending:
        return _isAwaitingPayment(order)
            ? 'Conclua o pagamento para enviar o pedido ao restaurante.'
            : 'O pagamento ja entrou. Agora o restaurante precisa confirmar o pedido.';
      case OrderStatus.paymentAuthorized:
      case OrderStatus.paid:
        return 'O pagamento ja entrou. Agora o restaurante precisa confirmar o pedido.';
      case OrderStatus.accepted:
      case OrderStatus.preparing:
        return 'O restaurante confirmou o pedido. O preparo vai decrescendo ate ficar pronto.';
      case OrderStatus.ready:
      case OrderStatus.awaitingPickupConfirmation:
        return order.isPickup
            ? (order.isCustomerPickupFallback
                  ? 'Nao encontrámos um estafeta disponível. Levanta o pedido no restaurante quando estiver pronto.'
                  : 'O prato terminou o preparo e ja pode ser retirado.')
            : _isSearchingNearbyCourier(order)
            ? 'O prato terminou o preparo e Deligo esta a procurar estafetas proximos.'
            : 'O prato terminou o preparo e esta pronto para seguir.';
      case OrderStatus.pickedUp:
      case OrderStatus.inDelivery:
        return _hasAssignedCourier(order)
            ? 'Acompanhe o pedido em tempo real ate a entrega e abra os detalhes para ver o codigo OTP.'
            : 'O pedido esta pronto e aguarda a atribuicao de um estafeta.';
      case OrderStatus.courierAssigned:
        return _hasAssignedCourier(order)
            ? 'O estafeta aceitou o pedido e esta a seguir para o restaurante.'
            : 'A atribuicao do estafeta ainda nao foi confirmada.';
      case OrderStatus.inTransit:
      case OrderStatus.onTheWay:
        return _hasAssignedCourier(order)
            ? 'O estafeta ja levantou o pedido e a entrega esta a decorrer em tempo real.'
            : 'Ainda nao ha estafeta atribuido. A entrega ainda nao comecou.';
      case OrderStatus.arrived:
        return 'O estafeta ja chegou ao destino. Abra os detalhes para confirmar a entrega com o OTP.';
      case OrderStatus.deliveryFailedOtp:
        return 'O OTP falhou nesta entrega. A equipa admin foi alertada e o pedido segue em revisao segura.';
      case OrderStatus.delivered:
        return 'O pedido foi marcado como entregue. Confirma no app quando receberes tudo; se nao houver confirmacao em 10 minutos, concluiremos automaticamente.';
      case OrderStatus.disputed:
        return 'Reportaste um problema nesta entrega. O fecho automatico ficou bloqueado enquanto a equipa analisa.';
      case OrderStatus.autoCompleted:
      case OrderStatus.completed:
        return 'Pedido concluido com sucesso.';
      case OrderStatus.refunded:
        return 'O valor deste pedido foi devolvido.';
      case OrderStatus.expired:
        return 'O restaurante nao confirmou a tempo e o pedido expirou.';
      case OrderStatus.paymentFailed:
        return 'O pagamento nao foi autorizado.';
      case OrderStatus.cancelled:
        return 'Este pedido foi cancelado.';
    }
  }

  bool _isSearchingNearbyCourier(Order order) {
    return _isCourierSearchWindow(order);
  }

  bool _hasAssignedCourier(Order order) =>
      order.courierId?.trim().isNotEmpty == true;

  Future<void> _loadFavoritesFromDb() {
    final active = _favoritesLoadInFlight;
    if (active != null) {
      _favoritesReloadQueued = true;
      return active;
    }
    final future = _performFavoritesLoad();
    _favoritesLoadInFlight = future;
    return future.whenComplete(() {
      if (identical(_favoritesLoadInFlight, future)) {
        _favoritesLoadInFlight = null;
        if (_favoritesReloadQueued && mounted) {
          _favoritesReloadQueued = false;
          unawaited(_loadFavoritesFromDb());
        }
      }
    });
  }

  Future<void> _performFavoritesLoad() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    if (mounted && !_favoritesLoaded) {
      setState(() {
        _loadingFavorites = true;
        _favoritesLoadFailed = false;
      });
    }
    try {
      final response = await supabase
          .from('favorites')
          .select('restaurant_id, menu_item_id')
          .eq('user_id', user.id);
      final rows = (response as List).cast<Map<String, dynamic>>();
      final restaurantIds = rows
          .map((row) => row['restaurant_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final likedIds = rows
          .map((row) => row['menu_item_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final favoriteDishes = likedIds.isEmpty
          ? <MenuItem>[]
          : await _restaurantService.getMenuItemsByIds(
              likedIds.toList(),
              rethrowOnError: true,
            );

      final visibleRestaurants = restaurantIds.isEmpty
          ? <Restaurant>[]
          : await _restaurantService.getRestaurantsByIds(
              restaurantIds.toList(),
              temperatureC: _weather?.temperatureC,
            );
      final visibleById = {
        for (final restaurant in visibleRestaurants) restaurant.id: restaurant,
      };
      final filteredFavorites = restaurantIds
          .where(visibleById.containsKey)
          .map((id) => visibleById[id])
          .whereType<Restaurant>()
          .toList();

      if (mounted) {
        setState(() {
          _favoriteRestaurants = filteredFavorites;
          _favoriteDishes = favoriteDishes;
          _favoriteDishIds = likedIds;
          _favorites = restaurantIds;
          _loadingFavorites = false;
          _favoritesLoaded = true;
          _favoritesLoadFailed = false;
        });
      }
    } catch (error) {
      debugPrint('[CLIENT_LOAD] favorites failed: $error');
      if (mounted) {
        setState(() {
          _loadingFavorites = false;
          _favoritesLoadFailed = true;
        });
      }
    }
  }

  Future<void> _loadSmartNotifications({bool showLoading = true}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    if (showLoading && mounted) {
      setState(() => _loadingSmartNotifications = true);
    }
    try {
      final response = await supabase
          .from('push_notifications')
          .select(
            'id, user_id, type, title, body, action, entity_id, priority, channel, read_at, metadata, data, created_at',
          )
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);
      final notifications = _normalizeNotifications(
        List<Map<String, dynamic>>.from(response),
      );
      if (!_emailConfirmed &&
          !notifications.any(
            (item) => item['type'] == 'EMAIL_CONFIRMATION_REQUIRED',
          )) {
        notifications.insert(0, {
          'id': 'local-email-confirmation',
          'user_id': user.id,
          'type': 'EMAIL_CONFIRMATION_REQUIRED',
          'title': 'Confirme o seu email',
          'body':
              'Confirme o email da conta para manter o acesso e receber avisos importantes.',
          'action': 'OPEN_SETTINGS',
          'entity_id': null,
          'priority': 'HIGH',
          'channel': 'account',
          'read_at': null,
          'metadata': <String, dynamic>{'local_only': true},
          'created_at': _serverNowIsoUtc,
        });
      }
      if (!_pushActive &&
          !notifications.any((item) => item['type'] == 'PUSH_DISABLED')) {
        notifications.insert(0, {
          'id': 'local-push-disabled',
          'user_id': user.id,
          'type': 'PUSH_DISABLED',
          'title': 'Ative as notificacoes',
          'body':
              'Ative o push para acompanhar pedidos, entregas e mensagens em tempo real.',
          'action': 'OPEN_SETTINGS',
          'entity_id': null,
          'priority': 'MEDIUM',
          'channel': 'account',
          'read_at': null,
          'metadata': <String, dynamic>{'local_only': true},
          'created_at': _serverNowIsoUtc,
        });
      }
      if (mounted) {
        setState(() {
          _smartNotifications = notifications;
          _loadingSmartNotifications = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingSmartNotifications = false);
      }
    }
  }

  Future<void> _markAllNotificationsAsRead() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await HapticFeedback.lightImpact();
      await supabase
          .from('push_notifications')
          .update({'read_at': _serverNowIsoUtc})
          .eq('user_id', user.id)
          .isFilter('read_at', null);
      await _loadSmartNotifications();
    } catch (_) {}
  }

  Future<void> _markNotificationAsRead(String notificationId) async {
    if (notificationId.trim().isEmpty) return;
    try {
      await HapticFeedback.selectionClick();
      await NotificationRouterService().markAsRead(notificationId);
      await _loadSmartNotifications();
    } catch (_) {}
  }

  void _hideNotificationLocally(String notificationId) {
    if (notificationId.trim().isEmpty) return;
    setState(() => _hiddenNotificationIds.add(notificationId));
  }

  void _hideNotificationWithUndo(
    BuildContext context,
    String notificationId,
    String title,
  ) {
    if (notificationId.trim().isEmpty) return;
    HapticFeedback.selectionClick();
    _hideNotificationLocally(notificationId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title escondida da lista'),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () {
            if (!mounted) return;
            setState(() => _hiddenNotificationIds.remove(notificationId));
          },
        ),
      ),
    );
  }

  Future<void> _markSectionAsRead(
    List<Map<String, dynamic>> notifications,
  ) async {
    await HapticFeedback.lightImpact();
    for (final notification in notifications) {
      final id = notification['id']?.toString() ?? '';
      if (notification['read_at'] == null && id.isNotEmpty) {
        await NotificationRouterService().markAsRead(id);
      }
    }
    await _loadSmartNotifications();
  }

  Future<void> _loadMoreRestaurants() async {
    if (_isLoadingMore || !_hasMore) return;
    final loadVersion = _loadVersion;
    setState(() => _isLoadingMore = true);
    final nextOffset = (_page + 1) * _pageSize;
    try {
      final next = await _restaurantService.getRestaurants(
        temperatureC: _weather?.temperatureC,
        sortBy: _sortBy,
        limit: _pageSize,
        offset: nextOffset,
      );
      if (mounted && loadVersion == _loadVersion) {
        setState(() {
          _page += 1;
          _restaurants.addAll(next);
          _hasMore = next.length >= _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted && loadVersion == _loadVersion) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onScrollRestaurants() {
    if (!_restaurantsScroll.hasClients || _isLoadingMore || !_hasMore) return;
    final max = _restaurantsScroll.position.maxScrollExtent;
    final current = _restaurantsScroll.position.pixels;
    if (current > max - 200) {
      _loadMoreRestaurants();
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _searchQuery = value);
    });
  }

  Future<void> _activatePush() async {
    await PushNotificationService().initialize();
    final token = await PushNotificationService().registerFcmToken(token: null);
    if (mounted) {
      setState(() => _pushActive = token != null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            token != null ? 'Push ativo' : 'Falha ao registrar push',
          ),
        ),
      );
    }
  }

  Future<void> _logout() async {
    try {
      AuthRefreshNotifier.markIntentionalSignOut();
      await supabase.auth.signOut();
      if (mounted) {
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nao foi possivel sair agora. Tente novamente.'),
          ),
        );
      }
    }
  }

  Future<void> _saveFavorites() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      await supabase
          .from('favorites')
          .delete()
          .eq('user_id', user.id)
          .not('restaurant_id', 'is', null);
      if (_favorites.isNotEmpty) {
        final rows = _favorites
            .map((id) => {'user_id': user.id, 'restaurant_id': id})
            .toList();
        await supabase.from('favorites').insert(rows);
      }
    } catch (_) {
      try {
        await supabase.auth.updateUser(
          UserAttributes(data: {'favorites': _favorites.toList()}),
        );
      } catch (_) {}
    }
  }

  Future<void> _saveProfileSettings() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      _profileSettings['hidden_orders'] = _hiddenOrderIds.toList();
      await supabase
          .from('profiles')
          .update({
            'settings': _profileSettings,
            'updated_at': _serverNowIsoUtc,
          })
          .eq('id', user.id);
    } catch (_) {
      try {
        await supabase.auth.updateUser(
          UserAttributes(data: {'settings': _profileSettings}),
        );
      } catch (_) {}
    }
  }

  Future<void> _scheduleDelivery() async {
    final now = _serverNowLocal;
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
      initialDate: now,
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    final scheduled = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() => _scheduledDelivery = scheduled);
    _profileSettings['scheduled_for'] = scheduled.toIso8601String();
    await _saveProfileSettings();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entrega programada salva')));
    }
  }

  Future<void> _createGroupOrder() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final code =
        'GRP-${user.id.substring(0, 6)}-${_serverNow.millisecondsSinceEpoch.toString().substring(7)}';
    setState(() => _groupOrderCode = code);
    _profileSettings['group_order_code'] = code;
    await _saveProfileSettings();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pedido em grupo'),
        content: Text('Codigo do grupo: $code'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _toggleFavorite(Restaurant restaurant) {
    final id = restaurant.id;
    setState(() {
      if (_favorites.contains(id)) {
        _favorites.remove(id);
        _favoriteRestaurants.removeWhere((r) => r.id == id);
      } else {
        _favorites.add(id);
        _favoriteRestaurants.add(restaurant);
      }
    });
    _saveFavorites();
  }

  Future<void> _loadRouteInfoForLocalRestaurants() async {
    if (_userLat == null || _userLng == null || _localRestaurants.isEmpty) {
      return;
    }
    setState(() => _loadingRouteInfo = true);
    final origin = LatLng(_userLat!, _userLng!);
    final map = Map<String, RouteInfo>.from(_routeInfo);
    final top = _localRestaurants.take(3).toList();
    for (final r in top) {
      if (r.latitude == null || r.longitude == null) continue;
      final info = await MapsRouteService.getCachedRouteInfo(
        cacheKey: r.id,
        origin: origin,
        destination: LatLng(r.latitude!, r.longitude!),
      );
      if (info != null) {
        map[r.id] = info;
      }
    }
    if (mounted) {
      setState(() {
        _routeInfo = map;
        _loadingRouteInfo = false;
      });
    }
  }

  Future<void> _loadDeliveryEstimates(
    List<Restaurant> restaurants,
    int loadVersion,
  ) async {
    if (_userLat == null || _userLng == null) return;
    final origin = LatLng(_userLat!, _userLng!);
    final next = <String, RouteInfo>{};
    for (final restaurant in restaurants) {
      if (restaurant.latitude == null || restaurant.longitude == null) continue;
      final info = await MapsRouteService.getCachedRouteInfo(
        cacheKey: restaurant.id,
        origin: origin,
        destination: LatLng(restaurant.latitude!, restaurant.longitude!),
      );
      if (info != null && !info.isFallback) next[restaurant.id] = info;
      if (!mounted || loadVersion != _loadVersion) return;
    }
    if (!mounted || loadVersion != _loadVersion) return;
    final ranked =
        restaurants.where((r) {
          final info = next[r.id];
          return r.isOpen && info != null && !info.isFallback;
        }).toList()..sort((a, b) {
          final aTotal =
              (a.deliveryTime ?? 25) +
              ((next[a.id]!.durationSeconds ?? 0) / 60).ceil() +
              5;
          final bTotal =
              (b.deliveryTime ?? 25) +
              ((next[b.id]!.durationSeconds ?? 0) / 60).ceil() +
              5;
          return aTotal.compareTo(bTotal);
        });
    setState(() {
      _routeInfo = {..._routeInfo, ...next};
      _fastRestaurants = ranked.take(6).toList();
      _loadingRouteInfo = false;
    });
  }

  List<Restaurant> _applyLocationFilter(List<Restaurant> restaurants) {
    // “Todas as zonas” means the complete Mozambique catalogue. The user's
    // saved address is used for ranking/route hints, never as an implicit
    // city restriction that hides restaurants from other provinces.
    if (_locationFilter == 'all') return restaurants;
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .trim();

    final selectedCity = normalize(_addressCity);
    final selectedNeighborhood = normalize(_addressNeighborhood);
    final target = _locationFilter == 'nearby'
        ? selectedNeighborhood
        : _locationFilter.startsWith('zone:')
        ? normalize(_locationFilter.substring('zone:'.length))
        : selectedCity;
    if (target.isEmpty) return restaurants;
    return restaurants.where((r) {
      final city = normalize(r.city ?? '');
      final neighborhood = normalize(r.neighborhood ?? '');
      final address = normalize(r.address);
      if (_locationFilter == 'nearby' && _userLat != null && _userLng != null) {
        final nearbyByCoordinates = (r.distance ?? 999) <= 15;
        if (nearbyByCoordinates) return true;
      }
      return city == target ||
          city.contains(target) ||
          neighborhood == target ||
          neighborhood.contains(target) ||
          address.contains(target);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedIndex != 0 && _homeLogoMarqueeController.isAnimating) {
      _homeLogoMarqueeController.stop();
    }
    if (kIsWeb) return _buildWebDashboard();

    return Scaffold(
      backgroundColor: AppColors.clientBackground,
      appBar: _selectedIndex == 0 ? null : _buildClientGlobalHeader(),
      body: SafeArea(
        bottom: false,
        // Do not eagerly build every tab. Some tabs contain maps, media and
        // large data lists; building them offscreen could blank the first
        // client frame on constrained Android emulators.
        child: _buildSelectedClientTab(),
      ),
      floatingActionButton: _selectedIndex == 0
          ? _buildFloatingCartButton()
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
            selectedItemColor: AppColors.primaryRed,
            unselectedItemColor: AppColors.neutralGray,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
            elevation: 0,
            backgroundColor: Colors.transparent,
            type: BottomNavigationBarType.fixed,
            items: [
              BottomNavigationBarItem(
                icon: _buildBottomNavGif('assets/bottom_nav/cliente/home.gif'),
                activeIcon: _buildBottomNavGif(
                  'assets/bottom_nav/cliente/home.gif',
                  selected: true,
                ),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: _buildBottomNavGif(
                  'assets/bottom_nav/cliente/explorar.gif',
                ),
                activeIcon: _buildBottomNavGif(
                  'assets/bottom_nav/cliente/explorar.gif',
                  selected: true,
                ),
                label: 'Explorar',
              ),
              BottomNavigationBarItem(
                icon: _buildBottomNavGif(
                  'assets/bottom_nav/cliente/pedidos.gif',
                ),
                activeIcon: _buildBottomNavGif(
                  'assets/bottom_nav/cliente/pedidos.gif',
                  selected: true,
                ),
                label: 'Pedidos',
              ),
              BottomNavigationBarItem(
                icon: _buildBottomNavGif(
                  'assets/bottom_nav/cliente/favoritos.gif',
                ),
                activeIcon: _buildBottomNavGif(
                  'assets/bottom_nav/cliente/favoritos.gif',
                  selected: true,
                ),
                label: 'Favoritos',
              ),
              BottomNavigationBarItem(
                icon: _buildBottomNavGif(
                  'assets/bottom_nav/cliente/perfil.gif',
                ),
                activeIcon: _buildBottomNavGif(
                  'assets/bottom_nav/cliente/perfil.gif',
                  selected: true,
                ),
                label: 'Perfil',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedClientTab() {
    return switch (_selectedIndex) {
      0 => _buildHomeTab(),
      1 => _buildRestaurantsTab(),
      2 => _buildOrdersTab(),
      3 => _buildFavoritesTab(),
      _ => _buildProfileTab(),
    };
  }

  Widget _buildWebDashboard() {
    const canvas = Color(0xFFF7F7F5);
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: canvas,
      body: Row(
        children: [
          if (!isMobile) _buildWebSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildWebTopBar(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      _buildWebHome(),
                      _buildWebPageFrame(_buildRestaurantsTab()),
                      _buildWebPageFrame(_buildOrdersTab()),
                      _buildWebPageFrame(_buildFavoritesTab()),
                      _buildWebPageFrame(_buildProfileTab()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebSidebar() {
    final items = <({IconData icon, String label})>[
      (icon: Icons.home_rounded, label: 'Início'),
      (icon: Icons.explore_outlined, label: 'Explorar'),
      (icon: Icons.receipt_long_outlined, label: 'Pedidos'),
      (icon: Icons.favorite_border_rounded, label: 'Favoritos'),
      (icon: Icons.person_outline_rounded, label: 'Perfil'),
    ];
    return Container(
      width: 236,
      decoration: const BoxDecoration(
        color: Color(0xFF151515),
        border: Border(right: BorderSide(color: Color(0xFF242424))),
      ),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _WebBrandMark(),
                SizedBox(width: 11),
                Text(
                  'DeliGo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 38),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'DeliGo Cidade',
              style: TextStyle(
                color: Color(0xFF777777),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(items.length, (index) {
            final item = items[index];
            final selected = _selectedIndex == index;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _selectedIndex = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.icon,
                        size: 21,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF929292),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFFAAAAAA),
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      if (selected) ...[
                        const Spacer(),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryRed,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => context.push('/support'),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  SupportHeadsetButton(
                    onPressed: () => context.push('/support'),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Ajuda e suporte',
                    style: TextStyle(
                      color: Color(0xFFAAAAAA),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebWalletTile() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/wallet'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 18,
                  color: Color(0xFFBDBDBD),
                ),
                SizedBox(width: 8),
                Text(
                  'Carteira',
                  style: TextStyle(
                    color: Color(0xFFBDBDBD),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _profileHydrated
                ? Text(
                    '$_walletCurrency ${_walletBalance.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  )
                : const SizedBox(
                    height: 22,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 88,
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebTopBar() {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    return Container(
      height: 78,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 30),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F5),
        border: Border(bottom: BorderSide(color: Color(0xFFE9E8E4))),
      ),
      child: Row(
        children: [
          if (isMobile) ...[
            PopupMenuButton<int>(
              tooltip: 'Abrir menu',
              icon: const Icon(
                Icons.more_vert_rounded,
                color: Color(0xFF292929),
              ),
              onSelected: (index) => setState(() => _selectedIndex = index),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 0, child: Text('Início')),
                PopupMenuItem(value: 1, child: Text('Explorar')),
                PopupMenuItem(value: 2, child: Text('Pedidos')),
                PopupMenuItem(value: 3, child: Text('Favoritos')),
                PopupMenuItem(value: 4, child: Text('Perfil')),
              ],
            ),
            const SizedBox(width: 4),
          ],
          if (isMobile)
            const Text(
              'DeliGo',
              style: TextStyle(
                color: Color(0xFF191919),
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            )
          else
            const Text(
              'Tudo o que precisa na cidade.',
              style: TextStyle(
                color: Color(0xFF717171),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          const Spacer(),
          _WebTopAction(
            icon: Icons.search_rounded,
            tooltip: 'Pesquisar',
            onTap: () => setState(() => _selectedIndex = 1),
          ),
          const SizedBox(width: 10),
          Stack(
            clipBehavior: Clip.none,
            children: [
              _WebTopAction(
                icon: Icons.notifications_none_rounded,
                tooltip: 'Notificações',
                onTap: _showNotificationsSheet,
              ),
              if (_unreadNotificationCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 17,
                    height: 17,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryRed,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _unreadNotificationCount > 9
                          ? '9+'
                          : '$_unreadNotificationCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          SupportHeadsetButton(onPressed: () => context.push('/support')),
          const SizedBox(width: 10),
          _buildCartQuickAction(),
          const SizedBox(width: 14),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => setState(() => _selectedIndex = 4),
            child: ProfileImageViewer(
              imageUrl: _avatarUrl,
              size: 40,
              fallbackIcon: Icons.person,
              iconColor: const Color(0xFF292929),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebPageFrame(Widget child) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: ColoredBox(color: Colors.white, child: child),
      ),
    );
  }

  Widget _buildWebHome() {
    final now = _serverNowLocal;
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppColors.primaryRed,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(30, 34, 30, 56),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loadError.isNotEmpty) _buildErrorBanner(),
                if (!_emailConfirmed) _buildEmailWarning(),
                Text(
                  _profileHydrated
                      ? _greetingForHour(now.hour, _displayName)
                      : 'Olá',
                  style: const TextStyle(
                    color: Color(0xFF181818),
                    fontSize: 36,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _webContextLine(),
                  style: const TextStyle(
                    color: Color(0xFF747474),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 26),
                _buildWebSearch(),
                const SizedBox(height: 30),
                if (_activeOrder != null) ...[
                  _WebSectionHeader(
                    eyebrow: 'EM MOVIMENTO',
                    title: 'O seu pedido agora',
                    action: 'Ver pedidos',
                    onAction: () => setState(() => _selectedIndex = 2),
                  ),
                  const SizedBox(height: 14),
                  _buildActiveOrderCard(),
                  _buildOtherActiveOrdersIndicator(),
                  const SizedBox(height: 32),
                ] else if (_loadingOrders && !_ordersLoaded) ...[
                  _WebSectionHeader(
                    eyebrow: 'EM MOVIMENTO',
                    title: 'O seu pedido agora',
                    action: 'Ver pedidos',
                    onAction: () => setState(() => _selectedIndex = 2),
                  ),
                  const SizedBox(height: 14),
                  _buildActiveOrderLoadingSkeleton(),
                ],
                _WebSectionHeader(
                  eyebrow: 'DESCOBRIR',
                  title: 'Explore ao seu ritmo',
                  action: 'Ver tudo',
                  onAction: () => setState(() => _selectedIndex = 1),
                ),
                const SizedBox(height: 14),
                _buildCategoryShowcase(),
                if (_filteredFeaturedDishes.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  _buildFeaturedDishesSection(),
                ],
                if (_fastRestaurants.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  _buildHomeShowcaseSection(
                    title: 'Chega mais rápido',
                    subtitle: 'Boas escolhas quando cada minuto conta.',
                    icon: Icons.bolt_rounded,
                    accentColor: const Color(0xFFE76F3D),
                    restaurants: _fastRestaurants,
                    variant: _FeaturedCardVariant.fast,
                  ),
                ],
                if (_featuredRestaurants.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  _buildHomeShowcaseSection(
                    title: 'Escolhas que valem a pena',
                    subtitle: 'Restaurantes queridos pela comunidade DeliGo.',
                    icon: Icons.workspace_premium_outlined,
                    accentColor: AppColors.primaryRed,
                    restaurants: _featuredRestaurants,
                    variant: _FeaturedCardVariant.featured,
                  ),
                ],
                if (_smartCategoryCards.isNotEmpty) ...[
                  const SizedBox(height: 30),
                  _buildSmartCategoriesSection(),
                ],
                const SizedBox(height: 34),
                _WebSectionHeader(
                  eyebrow: 'PERTO DE SI',
                  title: 'Restaurantes para hoje',
                  action: 'Explorar',
                  onAction: () => setState(() => _selectedIndex = 1),
                ),
                const SizedBox(height: 14),
                if (_loadingRestaurants &&
                    !_catalogLoaded &&
                    _restaurants.isEmpty)
                  _buildRestaurantShimmers()
                else if (!_catalogLoaded && _restaurants.isEmpty)
                  const SizedBox.shrink()
                else if (_restaurants.isEmpty)
                  _buildWebEmptyRestaurants()
                else
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: _restaurants
                        .take(8)
                        .map(
                          (restaurant) => _buildFeaturedCardVariant(
                            restaurant,
                            variant: _FeaturedCardVariant.featured,
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _webContextLine() {
    if (!_profileHydrated) return 'A carregar os seus dados…';
    final location = _addressNeighborhood.isNotEmpty
        ? _addressNeighborhood
        : _addressCity.isNotEmpty
        ? _addressCity
        : 'Localização por definir';
    final weather = _weather == null
        ? ''
        : ' • ${_weather!.temperatureC.toStringAsFixed(0)}°';
    return '$location$weather • O que vamos fazer hoje?';
  }

  Widget _buildWebSearch() {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E2DD)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        onChanged: _onSearchChanged,
        onSubmitted: (_) => setState(() => _selectedIndex = 1),
        style: const TextStyle(
          color: Color(0xFF242424),
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 20, right: 12),
            child: Icon(Icons.search_rounded, size: 25),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 58),
          hintText: 'Pesquisar restaurantes, pratos e experiências...',
          hintStyle: const TextStyle(
            color: Color(0xFF999999),
            fontWeight: FontWeight.w500,
          ),
          suffixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ),
    );
  }

  Widget _buildWebQuickActions() {
    final actions =
        <({IconData icon, String label, Color color, VoidCallback tap})>[
          (
            icon: Icons.restaurant_rounded,
            label: 'Comer',
            color: AppColors.primaryRed,
            tap: () => setState(() => _selectedIndex = 1),
          ),
          (
            icon: Icons.receipt_long_outlined,
            label: 'Pedidos',
            color: const Color(0xFF266B5C),
            tap: () => setState(() => _selectedIndex = 2),
          ),
          (
            icon: Icons.favorite_border_rounded,
            label: 'Favoritos',
            color: const Color(0xFF9A4763),
            tap: () => setState(() => _selectedIndex = 3),
          ),
          (
            icon: Icons.support_agent_rounded,
            label: 'Suporte',
            color: const Color(0xFF405C8A),
            tap: () => context.push('/support'),
          ),
        ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 850;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: actions.map((action) {
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: action.tap,
              child: Container(
                width: compact
                    ? (constraints.maxWidth - 12) / 2
                    : (constraints.maxWidth - 36) / 4,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE8E6E1)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: action.color.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(action.icon, color: action.color, size: 20),
                    ),
                    const SizedBox(width: 11),
                    Flexible(
                      child: Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF292929),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildWebEmptyRestaurants() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8E6E1)),
      ),
      child: const Text(
        'Ainda não encontrámos restaurantes para esta zona.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF777777), fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildAnimatedEntrance({required int order, required Widget child}) {
    final begin = 24.0 + (order * 4);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + (order * 35)),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, builtChild) {
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * begin),
            child: builtChild,
          ),
        );
      },
    );
  }

  Widget _buildClientSearchBar() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: TextField(
        onChanged: _onSearchChanged,
        onSubmitted: (_) => setState(() => _selectedIndex = 1),
        decoration: InputDecoration(
          hintText: 'Restaurantes, pratos...',
          hintStyle: const TextStyle(
            color: Color(0xFF8A8F98),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF111827),
          ),
          suffixIcon: IconButton(
            tooltip: 'Explorar',
            onPressed: () => setState(() => _selectedIndex = 1),
            icon: const Icon(Icons.tune_rounded),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildSmartDiscoveryRail() {
    const items = [
      (Icons.local_fire_department_rounded, 'Mais vendidos', Color(0xFFE4572E)),
      (Icons.star_rounded, 'Melhor avaliados', Color(0xFFF5A623)),
      (Icons.bolt_rounded, 'Mais rapidos', Color(0xFF0F9D76)),
      (Icons.favorite_rounded, 'Para si', Color(0xFFD94870)),
      (Icons.new_releases_rounded, 'Novidades', Color(0xFF4F6BED)),
      (Icons.sell_rounded, 'Promocoes', Color(0xFF7B61FF)),
      (Icons.eco_rounded, 'Saudaveis', Color(0xFF299764)),
      (Icons.nightlight_round, 'Aberto agora', Color(0xFF495057)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _clientSectionTitle(
          'Descobertas inteligentes',
          'Escolhidas para o seu momento',
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _selectedIndex = 1),
                child: Container(
                  width: 112,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE8EAED)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(item.$1, color: item.$3, size: 22),
                      Text(
                        item.$2,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF20242A),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildClientValueCenter() {
    final rawCashback = _profileSettings['cashback_balance'];
    final cashback = rawCashback is num
        ? rawCashback.toDouble()
        : double.tryParse(rawCashback?.toString() ?? '') ?? 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Carteira DeliGo',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_walletCurrency ${_walletBalance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  cashback > 0
                      ? '+ ${cashback.toStringAsFixed(0)} MT de cashback'
                      : 'Cashback disponivel nas campanhas',
                  style: const TextStyle(
                    color: Color(0xFF8FE3BE),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Abrir carteira',
            onPressed: () => context.push('/wallet'),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildAiRecommendationCard() {
    final restaurant = _featuredRestaurants.isNotEmpty
        ? _featuredRestaurants.first
        : _restaurants.isNotEmpty
        ? _restaurants.first
        : null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD9E7FA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: _showDeligoAi,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF315E9B),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recomendacao DeliGo',
                  style: TextStyle(
                    color: Color(0xFF24466F),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  restaurant == null
                      ? 'Estamos a aprender as suas preferencias para sugerir algo especial.'
                      : 'Hoje recomendamos ${restaurant.name}, uma escolha em destaque perto de si.',
                  style: const TextStyle(
                    color: Color(0xFF48647F),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCityServicesRail() {
    final services = [
      (Icons.local_grocery_store_outlined, 'Supermercados'),
      (Icons.local_pharmacy_outlined, 'Farmacias'),
      (Icons.local_drink_outlined, 'Bebidas'),
      (Icons.bakery_dining_outlined, 'Padarias'),
      (Icons.pets_outlined, 'Pet shop'),
      (Icons.card_giftcard_outlined, 'Presentes'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _clientSectionTitle(
          'Tudo na sua cidade',
          'Comida e conveniencia numa so app',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: services
              .map(
                (service) => ActionChip(
                  avatar: Icon(
                    service.$1,
                    size: 18,
                    color: const Color(0xFF343A40),
                  ),
                  label: Text(service.$2),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFE1E4E8)),
                  onPressed: () => setState(() => _selectedIndex = 1),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildLoyaltyCard() {
    final completed = _clientOrders
        .where(
          (order) =>
              order.status == OrderStatus.completed ||
              order.status == OrderStatus.autoCompleted,
        )
        .length;
    final progressOrders = completed % 5;
    final remaining = 5 - progressOrders;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF4DFA4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.loyalty_outlined, color: Color(0xFFA36A00)),
              SizedBox(width: 9),
              Text(
                'Programa Fidelidade',
                style: TextStyle(
                  color: Color(0xFF704A00),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Faltam $remaining pedido(s) para desbloquear a proxima recompensa.',
            style: const TextStyle(color: Color(0xFF795D26)),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progressOrders / 5,
              minHeight: 9,
              color: const Color(0xFFE4A11B),
              backgroundColor: const Color(0xFFF1E3BE),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clientSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF191C20),
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF777D87),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildHomeTab() {
    // Keep the mobile home on one bounded scrollable.  The previous nested
    // sliver/pinned-header composition occasionally reached Android with an
    // unlaid RenderBox, leaving a visually blank client dashboard.
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          if (_loadError.isNotEmpty) _buildErrorBanner(),
          if (!_emailConfirmed) _buildEmailWarning(),
          _buildAnimatedEntrance(order: 0, child: _buildHomeHeaderCompact()),
          const SizedBox(height: 10),
          _buildClientSearchBar(),
          const SizedBox(height: 14),
          _buildAnimatedEntrance(order: 1, child: _buildHomeHeroBanner()),
          const SizedBox(height: 18),
          _buildAnimatedEntrance(order: 2, child: _buildHomeServiceTiles()),
          const SizedBox(height: 18),
          if (_activeOrder != null) ...[
            _buildAnimatedEntrance(order: 3, child: _buildActiveOrderCard()),
            _buildOtherActiveOrdersIndicator(),
            const SizedBox(height: 18),
          ] else if (_loadingOrders && !_ordersLoaded) ...[
            _buildAnimatedEntrance(
              order: 3,
              child: _buildActiveOrderLoadingSkeleton(),
            ),
          ],
          if (_activeDailyCombos.isNotEmpty ||
              _marketingCampaigns.isNotEmpty ||
              _marketingCampaignSections.isNotEmpty) ...[
            _buildAnimatedEntrance(
              order: 4,
              child: _buildMarketingCampaignCenter(),
            ),
            const SizedBox(height: 18),
          ],
          if (_filteredFeaturedDishes.isNotEmpty) ...[
            _buildAnimatedEntrance(
              order: 5,
              child: _buildFeaturedDishesSection(),
            ),
            const SizedBox(height: 20),
          ],
          _buildAnimatedEntrance(order: 6, child: _buildBanners()),
          if (_localRestaurantsLoadFailed && !_localRestaurantsLoaded)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _loadLocalRestaurants(_loadVersion),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Tentar carregar restaurantes próximos'),
              ),
            ),
          if (_localRestaurants.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildAnimatedEntrance(order: 7, child: _buildLocalTopSection()),
            const SizedBox(height: 20),
          ],
          if (_scheduledDelivery != null ||
              (_groupOrderCode?.isNotEmpty ?? false)) ...[
            _buildAnimatedEntrance(order: 8, child: _buildPlanningCard()),
            const SizedBox(height: 20),
          ],
          if (_loadingRestaurants &&
              !_catalogLoaded &&
              _fastRestaurants.isEmpty) ...[
            _buildAnimatedEntrance(
              order: 10,
              child: _buildShowcaseShimmer(
                title: 'Entrega mais rapida',
                accentColor: AppColors.primaryOrange,
              ),
            ),
            const SizedBox(height: 24),
          ] else if (_fastRestaurants.isNotEmpty) ...[
            _buildAnimatedEntrance(
              order: 10,
              child: _buildHomeShowcaseSection(
                title: 'Entrega mais rapida',
                subtitle:
                    'Os restaurantes com chegada mais agil para pedir agora.',
                icon: Icons.bolt_rounded,
                accentColor: AppColors.primaryOrange,
                restaurants: _fastRestaurants,
                variant: _FeaturedCardVariant.fast,
              ),
            ),
            const SizedBox(height: 24),
          ],

          if (_loadingRestaurants &&
              !_catalogLoaded &&
              _featuredRestaurants.isEmpty) ...[
            _buildAnimatedEntrance(
              order: 11,
              child: _buildShowcaseShimmer(
                title: 'Restaurantes em destaque',
                accentColor: AppColors.primaryRed,
              ),
            ),
            const SizedBox(height: 24),
          ] else if (_featuredRestaurants.isNotEmpty) ...[
            _buildAnimatedEntrance(
              order: 11,
              child: _buildHomeShowcaseSection(
                title: 'Restaurantes em destaque',
                subtitle:
                    'Mais bem avaliados, mais fortes no menu e com melhor presenca.',
                icon: Icons.workspace_premium_rounded,
                accentColor: AppColors.primaryRed,
                restaurants: _featuredRestaurants,
                variant: _FeaturedCardVariant.featured,
              ),
            ),
            const SizedBox(height: 24),
          ],

          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Restaurantes proximos',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () => setState(() => _selectedIndex = 1),
                child: const Text('Ver todos'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingRestaurants && !_catalogLoaded && _restaurants.isEmpty)
            _buildRestaurantShimmers()
          else if (!_catalogLoaded && _restaurants.isEmpty)
            const SizedBox.shrink()
          else if (_restaurants.isEmpty)
            const Center(
              child: Text('Ainda nao encontramos restaurantes para esta zona.'),
            )
          else
            ...(_restaurants.take(5).map((r) => _buildRestaurantCard(r))),
        ],
      ),
    );
  }

  Widget _buildHeroHeader() {
    final firstName = _displayName;
    final now = _serverNowLocal;
    final theme = _resolveSkyTheme(now.hour);
    final weatherLine = _weather != null
        ? '${_weather!.temperatureC.toStringAsFixed(0)} C - ${_weather!.condition}'
        : 'Tempo a carregar';

    return Container(
      height: 132,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 900),
              decoration: BoxDecoration(gradient: theme.gradient),
            ),
            if (theme.showClouds) ..._buildSkyClouds(),
            if (theme.showStars) ..._buildSkyStars(),
            if ((_weather?.condition.toLowerCase().contains('chuva') ??
                    false) ||
                (_weather?.condition.toLowerCase().contains('rain') ?? false))
              ..._buildRainDrops(),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.12),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _profileHydrated
                                  ? _greetingForHour(now.hour, _displayName)
                                  : 'Bem-vindo',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              weatherLine,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        backgroundImage: _avatarUrl != null
                            ? NetworkImage(_avatarUrl!)
                            : null,
                        child: _avatarUrl == null
                            ? Text(
                                firstName.isNotEmpty
                                    ? firstName[0].toUpperCase()
                                    : 'D',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _selectedIndex = 1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primaryRed,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.flash_on),
                      label: const Text('PEDIR RAPIDO'),
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

  void _showNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.55,
        maxChildSize: 0.94,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Centro de notificacoes',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (!_pushActive)
                      TextButton.icon(
                        onPressed: _activatePush,
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('Ativar'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _pushActive
                      ? 'As ultimas notificacoes ficam concentradas aqui.'
                      : 'Ative as notificacoes para receber alertas em tempo real.',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                _buildSmartNotifications(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _joinGroupOrder() async {
    final controller = TextEditingController(text: _groupOrderCode ?? '');
    final joined = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Entrar em pedido em grupo'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'Ex: GRP-ABC123-456',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim().toUpperCase()),
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
    if (joined == null || joined.isEmpty) return;
    setState(() => _groupOrderCode = joined);
    _profileSettings['group_order_code'] = joined;
    await _saveProfileSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Pedido em grupo $joined pronto para checkout.')),
    );
  }

  Future<void> _clearPlanningState() async {
    setState(() {
      _scheduledDelivery = null;
      _groupOrderCode = null;
    });
    _profileSettings.remove('scheduled_for');
    _profileSettings.remove('group_order_code');
    await _saveProfileSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Planeamento removido do dashboard.')),
    );
  }

  Future<void> _copyGroupOrderCode() async {
    final code = _groupOrderCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Codigo do grupo copiado.')));
  }

  _SkyTheme _resolveSkyTheme(int hour) {
    if (hour >= 6 && hour < 17) {
      return const _SkyTheme(
        gradient: LinearGradient(
          colors: [Color(0xFF4FACFE), Color(0xFF00C8FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        showClouds: true,
        showStars: false,
      );
    }
    if (hour >= 17 && hour < 19) {
      return const _SkyTheme(
        gradient: LinearGradient(
          colors: [Color(0xFFFF7E5F), Color(0xFFFEB47B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        showClouds: false,
        showStars: false,
      );
    }
    return const _SkyTheme(
      gradient: LinearGradient(
        colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      showClouds: false,
      showStars: true,
    );
  }

  String _greetingForHour(int hour, String name) {
    if (hour >= 5 && hour < 12) return 'Bom dia, $name';
    if (hour >= 12 && hour < 18) return 'Boa tarde, $name';
    return 'Boa noite, $name';
  }

  Widget _heroChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSkyClouds() {
    const specs = [
      (
        top: 18.0,
        width: 86.0,
        height: 28.0,
        begin: -110.0,
        end: 260.0,
        seconds: 34,
      ),
      (
        top: 58.0,
        width: 120.0,
        height: 42.0,
        begin: -170.0,
        end: 300.0,
        seconds: 42,
      ),
      (
        top: 94.0,
        width: 70.0,
        height: 24.0,
        begin: -130.0,
        end: 240.0,
        seconds: 29,
      ),
    ];

    return specs.map((spec) {
      return Positioned(
        top: spec.top,
        child: _SkyMover(
          begin: spec.begin,
          end: spec.end,
          duration: Duration(seconds: spec.seconds),
          child: Container(
            width: spec.width,
            height: spec.height,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.34),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Restaurant> _applyExploreSearchAndCategory(
    List<Restaurant> restaurants,
  ) {
    final categoryFiltered = restaurants.where((restaurant) {
      if (_selectedFoodCategory == DeligoFoodCategories.all.label) {
        return true;
      }
      final category = _selectedFoodCategory.toLowerCase();
      final haystack =
          '${restaurant.name} ${restaurant.description ?? ''} ${restaurant.address}'
              .toLowerCase();
      return haystack.contains(category);
    }).toList();
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return categoryFiltered;
    return categoryFiltered.where((restaurant) {
      final haystack = [
        restaurant.name,
        restaurant.address,
        restaurant.description ?? '',
      ].join(' ').toLowerCase();
      if (haystack.contains(query)) return true;
      return _featuredDishes.any((dish) {
        if (dish['restaurant_id']?.toString() != restaurant.id) return false;
        final dishHaystack = [
          dish['name'],
          dish['description'],
          dish['category'],
        ].whereType<Object>().join(' ').toLowerCase();
        return dishHaystack.contains(query);
      });
    }).toList();
  }

  List<Widget> _buildSkyStars() {
    const stars = [
      (top: 22.0, left: 28.0, size: 2.6),
      (top: 34.0, left: 120.0, size: 2.0),
      (top: 48.0, left: 220.0, size: 2.8),
      (top: 78.0, left: 80.0, size: 2.4),
      (top: 96.0, left: 180.0, size: 2.2),
      (top: 112.0, left: 40.0, size: 2.6),
      (top: 120.0, left: 250.0, size: 2.1),
    ];

    return stars.map((star) {
      return Positioned(
        top: star.top,
        left: star.left,
        child: _SkyTwinkle(
          child: Container(
            width: star.size,
            height: star.size,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildRainDrops() {
    const drops = [
      (left: 36.0, top: 32.0),
      (left: 86.0, top: 26.0),
      (left: 132.0, top: 54.0),
      (left: 178.0, top: 40.0),
      (left: 226.0, top: 28.0),
      (left: 274.0, top: 52.0),
    ];

    return drops.map((drop) {
      return Positioned(
        left: drop.left,
        top: drop.top,
        child: _SkyTwinkle(
          duration: const Duration(milliseconds: 800),
          child: Container(
            width: 2,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(999),
            ),
            transform: Matrix4.rotationZ(0.35),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildCategoryShowcase() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categorias',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.darkGray,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _homeCategories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final category = _homeCategories[index];
              final selected = category == _selectedFoodCategory;
              final categoryMeta = category == DeligoFoodCategories.all.label
                  ? DeligoFoodCategories.all
                  : DeligoFoodCategories.list.firstWhere(
                      (item) => item.label == category,
                      orElse: () => DeligoFoodCategories.all,
                    );
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selectedFoodCategory = category),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 68,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: selected
                        ? categoryMeta.color.withValues(alpha: 0.10)
                        : Colors.transparent,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        scale: selected ? 1.08 : 1,
                        duration: const Duration(milliseconds: 160),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: _buildCategoryShowcaseIcon(categoryMeta),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        categoryMeta.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? categoryMeta.color
                              : AppColors.darkGray,
                          fontWeight: selected
                              ? FontWeight.w900
                              : FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: selected ? 18 : 0,
                        height: 2,
                        decoration: BoxDecoration(
                          color: categoryMeta.color,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryShowcaseIcon(DeligoFoodCategory category) {
    final asset = _categoryAssetPath(category.id);
    if (asset == null) {
      return Icon(category.icon, size: 23, color: category.color);
    }
    return Image.asset(
      asset,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          Icon(category.icon, size: 25, color: category.color),
    );
  }

  String? _categoryAssetPath(String id) {
    const base = 'assets/assets de categoria]';
    return switch (id) {
      'local_traditional' => '$base/local.png',
      'meat_protein' => '$base/carnes.png',
      'seafood_fish' => '$base/mariscos.png',
      'fast_food' => '$base/fast-food.png',
      'international' => '$base/international.png',
      'healthy_diet' => '$base/saudavel.png',
      'breakfast_snacks' => '$base/lanches.png',
      'soups_light' => '$base/sopas.png',
      'full_meals' => '$base/refeicoes.png',
      'family_groups' => '$base/familia.png',
      'drinks' => '$base/bebidas.png',
      'desserts' => '$base/sobre mesas].png',
      _ => null,
    };
  }

  Widget _buildFeaturedDishesSection({List<Map<String, dynamic>>? items}) {
    final visibleDishes = items ?? _filteredFeaturedDishes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Pratos em destaque',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              '${visibleDishes.length} opcoes',
              style: const TextStyle(color: AppColors.neutralGray),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          // 16:9 image + compact content + 10-12px breathing room.
          height: 214,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: visibleDishes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) =>
                _buildDishCard(visibleDishes[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildSmartCategoriesSection() {
    final selected = _smartCategoryCards.firstWhere(
      (item) => item.id == _selectedSmartDiscovery,
      orElse: () => _smartCategoryCards.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Descoberta inteligente',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Atalhos rapidos para encontrar o que mais faz sentido agora.',
          style: TextStyle(color: AppColors.neutralGray),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: selected.id,
          decoration: InputDecoration(
            filled: true,
            fillColor: selected.color.withValues(alpha: 0.08),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: selected.color.withValues(alpha: 0.24),
              ),
            ),
            prefixIcon: Icon(selected.icon, color: selected.color),
          ),
          items: _smartCategoryCards
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item.id,
                  child: Row(
                    children: [
                      Icon(item.icon, color: item.color, size: 20),
                      const SizedBox(width: 10),
                      Text(item.label),
                    ],
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedSmartDiscovery = value);
          },
        ),
        const SizedBox(height: 12),
        _buildSmartDiscoveryResults(selected),
      ],
    );
  }

  Widget _buildSmartDiscoveryResults(DeligoSmartCategory selected) {
    if (selected.id == 'promotions') {
      final cards = _marketingCampaigns
          .where(
            (item) =>
                item['campaign_type'] == 'promotion' ||
                item['placement'] == 'daily_offer' ||
                item['coupon_code']?.toString().isNotEmpty == true,
          )
          .take(8)
          .map(_buildMarketingCampaignCard)
          .toList();
      return _buildSmartResultFrame(
        selected: selected,
        emptyText: 'Ainda nao ha promocoes ativas.',
        child: cards.isEmpty
            ? null
            : SizedBox(
                height: 210,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => cards[index],
                ),
              ),
      );
    }

    final restaurants = _smartRestaurantsFor(selected.id);
    if (restaurants.isNotEmpty) {
      return _buildSmartResultFrame(
        selected: selected,
        emptyText: '',
        child: Column(
          children: restaurants.take(4).map(_buildRestaurantCard).toList(),
        ),
      );
    }

    final dishes = _smartDishesFor(selected.id);
    return _buildSmartResultFrame(
      selected: selected,
      emptyText: 'Ainda nao ha resultados reais para esta descoberta.',
      child: dishes.isEmpty
          ? null
          : SizedBox(
              height: 214,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: dishes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _buildDishCard(dishes[index]),
              ),
            ),
    );
  }

  Widget _buildSmartResultFrame({
    required DeligoSmartCategory selected,
    required String emptyText,
    Widget? child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected.color.withValues(alpha: 0.16)),
      ),
      child:
          child ??
          Text(emptyText, style: const TextStyle(color: AppColors.neutralGray)),
    );
  }

  List<Map<String, dynamic>> _smartDishesFor(String id) {
    final dishes = List<Map<String, dynamic>>.from(_featuredDishes);
    switch (id) {
      case 'popular':
        dishes.sort(
          (a, b) => ((b['item_rating'] as num?) ?? 0).compareTo(
            ((a['item_rating'] as num?) ?? 0),
          ),
        );
        return dishes.take(10).toList();
      case 'recommended':
        return _filteredFeaturedDishes.take(10).toList();
      case 'new':
        return dishes.reversed.take(10).toList();
      default:
        return const [];
    }
  }

  List<Restaurant> _smartRestaurantsFor(String id) {
    switch (id) {
      case 'fast_delivery':
        return _fastRestaurants;
      case 'nearby':
        return _localRestaurants;
      case 'budget':
        final restaurants = List<Restaurant>.from(_restaurants);
        restaurants.sort(
          (a, b) =>
              (a.deliveryFee ?? 999999).compareTo(b.deliveryFee ?? 999999),
        );
        return restaurants;
      case 'top_restaurants':
        return _featuredRestaurants;
      default:
        return const [];
    }
  }

  Widget _buildDishCard(Map<String, dynamic> dish) {
    final imageUrl = dish['image_url'] as String?;
    final rating = (dish['item_rating'] as num?)?.toDouble() ?? 4.6;
    final prepTime = (dish['prep_time_minutes'] as num?)?.toInt() ?? 25;
    final price = (dish['price'] as num?)?.toDouble() ?? 0;
    final restaurantId = dish['restaurant_id']?.toString() ?? '';
    final dishId = dish['id']?.toString() ?? '';

    return GestureDetector(
      onTap: restaurantId.isEmpty
          ? null
          : () {
              final route = dishId.isEmpty
                  ? '/restaurant/$restaurantId'
                  : '/restaurant/$restaurantId?dish=${Uri.encodeComponent(dishId)}';
              GuardedNavigation.push(context, route);
            },
      child: Container(
        width: 172,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
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
                top: Radius.circular(22),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: imageUrl?.isNotEmpty == true
                    ? CachedNetworkImage(
                        imageUrl: imageUrl!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: AppColors.lightGray,
                        child: const Center(
                          child: Icon(Icons.fastfood, size: 34),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dish['name']?.toString() ?? 'Prato',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dish['restaurant_name']?.toString() ?? 'Restaurante',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.neutralGray),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildInfoChip(
                        Icons.star,
                        rating.toStringAsFixed(1),
                        Colors.amber,
                      ),
                      const SizedBox(width: 5),
                      _buildInfoChip(
                        Icons.access_time,
                        '$prepTime min',
                        AppColors.primaryRed,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildInfoChip(
                    Icons.payments,
                    '${price.toStringAsFixed(0)} MZN',
                    AppColors.successGreen,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestaurantsTab() {
    final filteredRestaurants = _applyExploreSearchAndCategory(_restaurants);
    final filteredDishes = _filteredFeaturedDishes;
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        controller: _restaurantsScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (_loadError.isNotEmpty) _buildErrorBanner(),
          TextField(
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Buscar restaurantes, pratos ou zona...',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: AppColors.primaryRed.withValues(alpha: .16),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                  color: AppColors.primaryRed.withValues(alpha: .16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.restaurant_rounded),
                label: Text('Restaurantes'),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.restaurant_menu_rounded),
                label: Text('Pratos'),
              ),
            ],
            selected: {_exploreDishesMode},
            onSelectionChanged: (selection) {
              setState(() => _exploreDishesMode = selection.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              minimumSize: const MaterialStatePropertyAll(Size.fromHeight(42)),
            ),
          ),
          const SizedBox(height: 14),
          _buildCategoryShowcase(),
          const SizedBox(height: 16),
          if (!_exploreDishesMode) const SizedBox(height: 20),
          if (!_exploreDishesMode &&
              _loadingRestaurants &&
              filteredRestaurants.isEmpty)
            _buildRestaurantShimmers()
          else if (!_exploreDishesMode &&
              !_catalogLoaded &&
              filteredRestaurants.isEmpty)
            const SizedBox.shrink()
          else if (!_exploreDishesMode && filteredRestaurants.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('Nenhum restaurante encontrado nesta zona.'),
              ),
            )
          else if (!_exploreDishesMode) ...[
            _buildExploreSectionTitle(
              '${filteredRestaurants.length} restaurantes encontrados',
              'Os melhores restaurantes na sua zona',
            ),
            const SizedBox(height: 10),
            _buildExploreRestaurantList(filteredRestaurants),
          ],
          if (_exploreDishesMode &&
              _loadingRestaurants &&
              !_featuredDishesLoaded &&
              filteredDishes.isEmpty)
            _buildRestaurantShimmers()
          else if (_exploreDishesMode &&
              _featuredDishesLoadFailed &&
              !_featuredDishesLoaded &&
              filteredDishes.isEmpty)
            Center(
              child: TextButton.icon(
                onPressed: () => unawaited(
                  _loadSecondaryHomeData(_loadVersion, _restaurants),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(
                  'Não foi possível carregar pratos. Tentar novamente',
                ),
              ),
            )
          else if (_exploreDishesMode &&
              !_featuredDishesLoaded &&
              filteredDishes.isEmpty)
            const SizedBox.shrink()
          else if (_exploreDishesMode && filteredDishes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Não encontramos pratos. Tente outro termo ou filtro.',
                ),
              ),
            ),
          if (_exploreDishesMode && filteredDishes.isNotEmpty) ...[
            const SizedBox(height: 22),
            _buildExploreSectionTitle(
              '${filteredDishes.length} pratos encontrados',
              'Pratos disponíveis no catálogo real',
            ),
            const SizedBox(height: 10),
            _buildExploreDishList(filteredDishes),
          ],
          if (!_exploreDishesMode && _activeDailyCombos.isNotEmpty) ...[
            const SizedBox(height: 22),
            _buildExploreSectionTitle(
              'Ofertas e promoções',
              'Aproveite as melhores campanhas',
            ),
            const SizedBox(height: 10),
            _buildMarketingCampaignCenter(),
          ],
        ],
      ),
    );
  }

  Widget _buildExploreDiscoveryHero() => Container(
    height: 160,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFFFE8E6)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      border: Border.all(color: const Color(0xFFFFD7D2)),
    ),
    child: Stack(
      children: [
        const Positioned(
          right: -12,
          top: -24,
          child: Icon(
            Icons.lunch_dining_rounded,
            size: 220,
            color: Color(0xFFEED4C8),
          ),
        ),
        const Positioned(
          right: 14,
          bottom: 10,
          child: Icon(
            Icons.local_fire_department_rounded,
            size: 72,
            color: Color(0xFFEE2D31),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Descubra novos sabores\ncom DeliGo',
                style: TextStyle(
                  fontSize: 24,
                  height: 1.06,
                  fontWeight: FontWeight.w900,
                  color: AppColors.deepBlack,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Os melhores restaurantes mais perto de si.',
                style: TextStyle(
                  color: AppColors.neutralGray,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _restaurantsScroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Explorar agora'),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildExploreRestaurantRail(List<Restaurant> restaurants) => SizedBox(
    height: 214,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: restaurants.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final restaurant = restaurants[index];
        return SizedBox(
          width: 222,
          child: DeligoPressable(
            onTap: () =>
                GuardedNavigation.push(context, '/restaurant/${restaurant.id}'),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: restaurant.isOpen
                    ? const Color(0xFFF0FFF5)
                    : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: restaurant.isOpen
                      ? const Color(0xFFB9F2D0)
                      : const Color(0xFFE9EAF0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: restaurant.imageUrl?.isNotEmpty == true
                            ? CachedNetworkImage(
                                imageUrl: restaurant.imageUrl!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 52,
                                height: 52,
                                color: AppColors.primaryRed,
                                child: const Icon(
                                  Icons.storefront,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                      const Spacer(),
                      _buildFavoriteButton(restaurant),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    restaurant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    LocationDisplay.smartLocation(
                      address: restaurant.address,
                      neighborhood: restaurant.neighborhood,
                      city: restaurant.city,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.neutralGray,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Wrap(
                    spacing: 6,
                    children: [
                      _buildInfoChip(
                        Icons.star_rounded,
                        restaurant.rating?.toStringAsFixed(1) ?? 'Novo',
                        Colors.amber,
                      ),
                      _buildInfoChip(
                        Icons.access_time_rounded,
                        '${restaurant.deliveryTime ?? 25} min',
                        AppColors.primaryRed,
                      ),
                      _buildInfoChip(
                        Icons.storefront_rounded,
                        restaurant.isOpen ? 'Aberto' : 'Fechado',
                        restaurant.isOpen
                            ? AppColors.successGreen
                            : AppColors.alertRed,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _buildExploreRestaurantList(List<Restaurant> restaurants) {
    return Column(
      children: restaurants.map(_buildRestaurantCard).toList(growable: false),
    );
  }

  Widget _buildExploreDishList(List<Map<String, dynamic>> dishes) {
    return Column(
      children: dishes
          .map((dish) {
            final imageUrl = dish['image_url'] as String?;
            final rating = (dish['item_rating'] as num?)?.toDouble() ?? 4.6;
            final prepTime = (dish['prep_time_minutes'] as num?)?.toInt() ?? 25;
            final price = (dish['price'] as num?)?.toDouble() ?? 0;
            final restaurantId = dish['restaurant_id']?.toString() ?? '';
            final dishId = dish['id']?.toString() ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: restaurantId.isEmpty
                    ? null
                    : () {
                        final route = dishId.isEmpty
                            ? '/restaurant/$restaurantId'
                            : '/restaurant/$restaurantId?dish=${Uri.encodeComponent(dishId)}';
                        context.push(route);
                      },
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: imageUrl?.isNotEmpty == true
                            ? CachedNetworkImage(
                                imageUrl: imageUrl!,
                                width: 82,
                                height: 82,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 82,
                                height: 82,
                                color: AppColors.lightGray,
                                child: const Icon(Icons.fastfood, size: 28),
                              ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dish['name']?.toString() ?? 'Prato',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              dish['restaurant_name']?.toString() ??
                                  'Restaurante',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.neutralGray,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                _buildInfoChip(
                                  Icons.star,
                                  rating.toStringAsFixed(1),
                                  Colors.amber,
                                ),
                                _buildInfoChip(
                                  Icons.access_time,
                                  '$prepTime min',
                                  AppColors.primaryRed,
                                ),
                                _buildInfoChip(
                                  Icons.payments,
                                  '${price.toStringAsFixed(0)} MZN',
                                  AppColors.successGreen,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.neutralGray,
                      ),
                    ],
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildExploreSectionTitle(String title, String subtitle) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.neutralGray),
            ),
          ],
        ),
      ),
      TextButton(
        onPressed: () => setState(() {
          _locationFilter = 'all';
          _exploreOpenNow = false;
          _exploreMaxDeliveryMinutes = null;
          _exploreMinimumRating = null;
          _exploreFreeDelivery = false;
        }),
        child: const Text('Limpar'),
      ),
    ],
  );

  Widget _buildLocalTopSection() {
    final label = _addressNeighborhood.isNotEmpty
        ? _addressNeighborhood
        : (_addressCity.isNotEmpty ? _addressCity : 'sua zona');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Top do $label',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_loadingRouteInfo)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ..._localRestaurants.take(6).map(_buildLocalRestaurantCard),
      ],
    );
  }

  Widget _buildLocalRestaurantCard(Restaurant restaurant) {
    final info = _routeInfo[restaurant.id];
    final distanceKm =
        info != null && !info.isFallback && info.distanceMeters != null
        ? info.distanceMeters! / 1000
        : null;
    final etaMin =
        info != null && !info.isFallback && info.durationSeconds != null
        ? (info.durationSeconds! / 60).round()
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: restaurant.imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: restaurant.imageUrl!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Shimmer.fromColors(
                    baseColor: Colors.grey.shade300,
                    highlightColor: Colors.grey.shade100,
                    child: Container(
                      width: 56,
                      height: 56,
                      color: Colors.white,
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 56,
                    height: 56,
                    color: Colors.grey[200],
                    child: const Icon(Icons.restaurant, color: Colors.grey),
                  ),
                )
              : Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(gradient: AppColors.splashGradient),
                  child: const Icon(Icons.restaurant, color: Colors.white),
                ),
        ),
        title: Text(restaurant.name),
        subtitle: Row(
          children: [
            _buildInfoChip(
              Icons.star,
              restaurant.rating?.toStringAsFixed(1) ?? 'Novo',
              Colors.amber,
            ),
            const SizedBox(width: 8),
            if (distanceKm != null)
              _buildInfoChip(
                Icons.directions,
                '${distanceKm.toStringAsFixed(1)} km',
                AppColors.neutralGray,
              ),
            const SizedBox(width: 8),
            if (etaMin != null)
              _buildInfoChip(
                Icons.access_time,
                '$etaMin min',
                AppColors.primaryRed,
              ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () =>
            GuardedNavigation.push(context, '/restaurant/${restaurant.id}'),
      ),
    );
  }

  Widget _buildOrdersTab() {
    if (!_ordersLoaded && _ordersLoadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 42),
              const SizedBox(height: 10),
              const Text('Não foi possível carregar os pedidos.'),
              TextButton.icon(
                onPressed: () => unawaited(_refreshActiveOrder()),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_loadingOrders && !_ordersLoaded && _clientOrders.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 3,
        itemBuilder: (context, _) => Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    final allOrders = [..._clientOrders];
    if (_activeOrder != null &&
        !allOrders.any((order) => order.id == _activeOrder!.id)) {
      allOrders.insert(0, _activeOrder!);
    }
    final filtered = _orderStatusFilter == 'all'
        ? allOrders
        : allOrders.where(_matchesOrderStatusFilter).toList();
    final visible = filtered
        .where(
          (order) =>
              !_hiddenOrderIds.contains(order.id) &&
              !_timedOutHiddenOrderIds.contains(order.id),
        )
        .toList();

    if (visible.isEmpty) {
      String title = 'Nenhum pedido ainda';
      String subtitle = 'Faca seu primeiro pedido!';
      switch (_orderStatusFilter) {
        case 'pending':
          title = 'Sem pedidos pendentes';
          subtitle = 'Quando houver pedido a espera, ele aparece aqui.';
          break;
        case 'in_transit':
          title = 'Nao tem pedidos em rota';
          subtitle =
              'O rastreamento aparece aqui quando o estafeta estiver a caminho.';
          break;
        case 'completed':
          title = 'Nao tem pedidos concluidos';
          subtitle = 'Os pedidos entregues ou retirados aparecem aqui.';
          break;
        case 'cancelled':
          title = 'Nao tem pedidos cancelados';
          subtitle = 'Se algum pedido for cancelado, ele fica guardado aqui.';
          break;
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: AppColors.neutralGray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_orderStatusFilter != 'all') ...[
              TapScale(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _orderStatusFilter = 'all'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Voltar para todos'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TapScale(
              child: ElevatedButton(
                onPressed: () => setState(() => _selectedIndex = 1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: AppColors.cleanWhite,
                ),
                child: const Text('Ver Restaurantes'),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Spacer(),
              IconButton.outlined(
                onPressed: () => setState(() => _selectedIndex = 1),
                icon: const Icon(Icons.search_rounded),
              ),
              if (_orderStatusFilter != 'all')
                TextButton.icon(
                  onPressed: () => setState(() => _orderStatusFilter = 'all'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Todos'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusChip('all', 'Todos'),
                _buildStatusChip('pending', 'Pendentes'),
                _buildStatusChip('in_transit', 'Em rota'),
                _buildStatusChip('completed', 'Concluidos'),
                _buildStatusChip('cancelled', 'Cancelados'),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final order = visible[index];
              final canDelete =
                  order.status == OrderStatus.cancelled ||
                  order.status == OrderStatus.completed ||
                  order.status == OrderStatus.autoCompleted;
              return _buildAnimatedEntrance(
                order: index,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.push('/order/${order.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FutureBuilder<List<OrderItem>>(
                        future: _loadOrderItemsFor(order.id),
                        builder: (context, snapshot) {
                          final items = snapshot.data ?? const <OrderItem>[];
                          final itemHeadline = _orderHeadline(items);
                          final hasItemHeadline =
                              itemHeadline != 'Pedido DeliGo';
                          final unreadChats = _unreadChatCountFor(order.id);
                          final showCourierAction =
                              _shouldShowCourierActionForOrder(order);
                          final showRestaurantAction =
                              _shouldShowRestaurantActionForOrder(order);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _restaurantDisplayName(order),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${order.totalAmount.toStringAsFixed(0)} MZN',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.primaryRed,
                                    ),
                                  ),
                                  if (canDelete)
                                    PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'delete') {
                                          _hideOrder(order.id);
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Apagar da lista'),
                                        ),
                                      ],
                                    )
                                  else
                                    const Icon(Icons.arrow_forward),
                                ],
                              ),
                              if (hasItemHeadline) ...[
                                const SizedBox(height: 6),
                                Text(
                                  itemHeadline,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.neutralGray,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                              if (unreadChats > 0) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryRed.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '$unreadChats mensagem(ns) novas',
                                    style: const TextStyle(
                                      color: AppColors.primaryRed,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                '${order.status.displayName} · ${_formatDateTime(order.updatedAt ?? order.createdAt)}',
                                style: const TextStyle(
                                  color: AppColors.neutralGray,
                                ),
                              ),
                              if (order.status == OrderStatus.completed ||
                                  order.status ==
                                      OrderStatus.autoCompleted) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.successGreen.withValues(
                                      alpha: 0.10,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 16,
                                        color: AppColors.successGreen,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Concluido',
                                        style: TextStyle(
                                          color: AppColors.successGreen,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                _deliveryDestinationLabel(order),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.neutralGray,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 7),
                              if (items.isEmpty)
                                const Text(
                                  'Itens indisponiveis no momento.',
                                  style: TextStyle(
                                    color: AppColors.neutralGray,
                                  ),
                                )
                              else
                                _buildOrderItemsPreview(items),
                              const SizedBox(height: 8),
                              Text(
                                'Total: ${order.totalAmount.toStringAsFixed(0)} MZN',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkGray,
                                ),
                              ),
                              if (showCourierAction ||
                                  showRestaurantAction) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    if (showCourierAction)
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _openCourierProfileForOrder(order),
                                        icon: const Icon(Icons.badge_outlined),
                                        label: const Text('Ver estafeta'),
                                      ),
                                    if (showRestaurantAction)
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _openRestaurantMenuForOrder(order),
                                        icon: const Icon(
                                          Icons.storefront_outlined,
                                        ),
                                        label: const Text('Ver restaurante'),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String value, String label) {
    final selected = _orderStatusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(
          switch (value) {
            'all' => Icons.list_rounded,
            'pending' => Icons.access_time_rounded,
            'in_transit' => Icons.delivery_dining_rounded,
            'completed' => Icons.check_circle_outline_rounded,
            _ => Icons.cancel_outlined,
          },
          size: 18,
          color: selected ? Colors.white : AppColors.darkGray,
        ),
        label: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.darkGray,
          ),
        ),
        selected: selected,
        selectedColor: AppColors.primaryRed,
        backgroundColor: Colors.white,
        side: BorderSide(
          color: selected ? AppColors.primaryRed : const Color(0xFFE0E3E8),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (_) => setState(() => _orderStatusFilter = value),
      ),
    );
  }

  int _unreadChatCountFor(String orderId) {
    return _smartNotifications.where((notification) {
      return ChatNotificationUtils.isUnreadChatNotification(notification) &&
          ChatNotificationUtils.matchesOrder(notification, orderId);
    }).length;
  }

  Widget _buildOrderItemsPreview(List<OrderItem> items) {
    final visibleItems = items.take(3).toList();
    return Column(
      children: [
        ...visibleItems.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F3ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primaryRed.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                children: [
                  if (item.menuItem?.imageUrl != null &&
                      item.menuItem!.imageUrl!.trim().isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: item.menuItem!.imageUrl!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.primaryRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.fastfood_rounded,
                        color: AppColors.primaryRed,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.menuItem?.name ?? 'Item',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.darkGray,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Quantidade ${item.quantity} • ${item.unitPrice.toStringAsFixed(0)} MZN',
                          style: const TextStyle(
                            color: AppColors.neutralGray,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${item.subtotal.toStringAsFixed(0)} MZN',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkGray,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (items.length > visibleItems.length)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '+${items.length - visibleItems.length} itens',
              style: const TextStyle(color: AppColors.neutralGray),
            ),
          ),
      ],
    );
  }

  Widget _buildFavoritesTab() {
    if (_loadingFavorites && !_favoritesLoaded) {
      return _buildFavoritesShimmer();
    }
    if (!_favoritesLoaded && _favoritesLoadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 42),
              const SizedBox(height: 10),
              const Text('Não foi possível carregar os favoritos.'),
              TextButton.icon(
                onPressed: _loadFavoritesFromDb,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_favoriteRestaurants.isEmpty && _favoriteDishes.isEmpty) {
      return _buildFavoritesEmptyState();
    }
    return RefreshIndicator(
      onRefresh: _loadFavoritesFromDb,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        children: [
          const SizedBox(height: 4),
          _buildFavoritesFilterBar(),
          const SizedBox(height: 22),
          if (_favoritesFilter != 'Pratos')
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Restaurantes favoritos',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                if (_favoritesFilter == 'Todos')
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _favoritesFilter = 'Restaurantes'),
                    icon: const Text('Ver todos'),
                    label: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 15,
                    ),
                  ),
                /*Text(
                  '${_favoriteRestaurants.length}',
                  style: const TextStyle(
                    color: AppColors.primaryRed,
                    fontWeight: FontWeight.w900,
                  ),
                ),*/
              ],
            ),
          if (_favoritesFilter != 'Pratos') const SizedBox(height: 12),
          if (_favoritesFilter != 'Pratos')
            _buildFavoriteRestaurantList(
              _favoriteRestaurants,
              limited: _favoritesFilter == 'Todos',
            ),
          if (_favoritesFilter != 'Restaurantes' &&
              _favoriteDishes.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pratos favoritos',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                if (_favoritesFilter == 'Todos')
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _favoritesFilter = 'Pratos'),
                    icon: const Text('Ver todos'),
                    label: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 15,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _buildFavoriteDishList(limited: _favoritesFilter == 'Todos'),
          ],
          const SizedBox(height: 10),
          _buildFavoritesExploreCard(),
        ],
      ),
    );
  }

  Widget _buildFavoritesHeader() => Row(
    children: [
      Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: Colors.pink.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(19),
        ),
        child: const Icon(
          Icons.favorite_rounded,
          color: AppColors.primaryRed,
          size: 32,
        ),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meus Favoritos',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 3),
            Text(
              'Tudo o que guardaste num só lugar.',
              style: TextStyle(color: AppColors.neutralGray, fontSize: 15),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildFavoriteDishCard(MenuItem item) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () =>
          GuardedNavigation.push(context, '/restaurant/${item.restaurantId}'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 82,
                height: 82,
                child: item.imageUrl?.isNotEmpty == true
                    ? CachedNetworkImage(
                        imageUrl: item.imageUrl!,
                        fit: BoxFit.cover,
                      )
                    : const ColoredBox(
                        color: Color(0xFFFFE9E7),
                        child: Icon(
                          Icons.restaurant_menu_rounded,
                          color: AppColors.primaryRed,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.category ?? 'Prato DeliGo',
                    style: const TextStyle(color: AppColors.neutralGray),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'MZN ${item.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.primaryRed,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Abrir prato',
              onPressed: () => GuardedNavigation.push(
                context,
                '/restaurant/${item.restaurantId}',
              ),
              icon: const Icon(
                Icons.add_circle_rounded,
                color: AppColors.primaryRed,
                size: 32,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildFavoriteRestaurantList(
    List<Restaurant> restaurants, {
    required bool limited,
  }) {
    final visible = limited ? restaurants.take(3) : restaurants;
    return Column(children: visible.map(_buildRestaurantCard).toList());
  }

  Future<void> _toggleFavoriteDish(MenuItem item) async {
    final id = item.id;
    setState(() {
      if (_favoriteDishIds.remove(id)) {
        _favoriteDishes.removeWhere((dish) => dish.id == id);
      } else {
        _favoriteDishIds.add(id);
        if (!_favoriteDishes.any((dish) => dish.id == id)) {
          _favoriteDishes.insert(0, item);
        }
      }
    });
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final exists = await supabase
          .from('favorites')
          .select('id')
          .eq('user_id', user.id)
          .eq('menu_item_id', id)
          .maybeSingle();
      if (exists == null) {
        await supabase.from('favorites').insert({
          'user_id': user.id,
          'menu_item_id': id,
        });
      } else {
        await supabase
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('menu_item_id', id);
      }
    } catch (_) {
      await _loadFavoritesFromDb();
    }
  }

  Widget _buildFavoriteDishList({required bool limited}) {
    final visible = limited ? _favoriteDishes.take(3) : _favoriteDishes;
    return Column(
      children: visible
          .map((item) {
            return Stack(
              children: [
                _buildFavoriteDishCard(item),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: 'Remover dos favoritos',
                    onPressed: () => _toggleFavoriteDish(item),
                    icon: const Icon(
                      Icons.favorite_rounded,
                      color: AppColors.primaryRed,
                      size: 20,
                    ),
                  ),
                ),
              ],
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildFavoriteDishesRail() => SizedBox(
    height: 230,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _favoriteDishes.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        final item = _favoriteDishes[index];
        return SizedBox(
          width: 184,
          child: InkWell(
            onTap: () => GuardedNavigation.push(
              context,
              '/restaurant/${item.restaurantId}',
            ),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .04),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 112,
                        child: item.imageUrl?.isNotEmpty == true
                            ? CachedNetworkImage(
                                imageUrl: item.imageUrl!,
                                fit: BoxFit.cover,
                              )
                            : const ColoredBox(
                                color: Color(0xFFFFE9E7),
                                child: Icon(
                                  Icons.restaurant_menu_rounded,
                                  color: AppColors.primaryRed,
                                ),
                              ),
                      ),
                      const Positioned(
                        right: 8,
                        top: 8,
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.white,
                          child: Icon(
                            Icons.favorite_rounded,
                            color: AppColors.primaryRed,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.category ?? 'Prato DeliGo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.neutralGray,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'MZN ${item.price.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppColors.primaryRed,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: Color(0xFFFFE8E6),
                              child: Icon(
                                Icons.add,
                                color: AppColors.primaryRed,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _buildFavoritesFilterBar() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: ['Todos', 'Restaurantes', 'Pratos']
          .map(
            (filter) => Padding(
              padding: const EdgeInsets.only(right: 9),
              child: ChoiceChip(
                label: Text(filter),
                selected: _favoritesFilter == filter,
                selectedColor: AppColors.primaryRed,
                labelStyle: TextStyle(
                  color: _favoritesFilter == filter
                      ? Colors.white
                      : AppColors.darkGray,
                  fontWeight: FontWeight.w800,
                ),
                onSelected: (_) => setState(() => _favoritesFilter = filter),
              ),
            ),
          )
          .toList(),
    ),
  );

  Widget _buildFavoritesEmptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: Colors.pink.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              size: 46,
              color: AppColors.primaryRed,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Ainda não tens favoritos',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          const Text(
            'Guarda restaurantes para pedir mais rápido da próxima vez.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.neutralGray),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => setState(() => _selectedIndex = 1),
            icon: const Icon(Icons.explore_outlined),
            label: const Text('Explorar restaurantes'),
          ),
        ],
      ),
    ),
  );

  Widget _buildFavoritesExploreCard() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F0),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.favorite_outline_rounded,
          color: AppColors.primaryRed,
          size: 32,
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Descobre mais sabores',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 3),
              Text(
                'Adiciona restaurantes aos favoritos e pede mais rápido.',
                style: TextStyle(color: AppColors.neutralGray, fontSize: 12),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _selectedIndex = 1),
          child: const Text('Explorar'),
        ),
      ],
    ),
  );

  Widget _buildProfileTab() {
    if (!_profileHydrated) {
      return Center(
        child: _profileLoadFailed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Não foi possível carregar o perfil.'),
                  TextButton.icon(
                    onPressed: _loadUserSummary,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      );
    }
    final location = _addressNeighborhood.isNotEmpty
        ? _addressNeighborhood
        : _addressCity.isNotEmpty
        ? _addressCity
        : _address.isNotEmpty
        ? _address
        : 'Localização por definir';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildClientProfileSummary(location),
          const SizedBox(height: 14),
          _buildClientWalletProfileCard(),
          const SizedBox(height: 14),
          _buildClientProfileMenuCard(
            children: [
              _clientProfileMenuItem(
                icon: Icons.location_on_outlined,
                title: 'Meus endereços',
                subtitle: 'Casa, trabalho e outros endereços',
                onTap: () async {
                  await context.push('/profile?section=addresses');
                  await _loadUserSummary();
                },
              ),
              _clientProfileMenuItem(
                icon: Icons.credit_card_outlined,
                title: 'Métodos de pagamento',
                subtitle: 'M-Pesa, e-Mola, cartões e outros',
                onTap: () => context.push('/wallet'),
              ),
              _clientProfileMenuItem(
                icon: Icons.confirmation_number_outlined,
                title: 'Cupões e promoções',
                subtitle: 'Descontos e ofertas especiais',
                onTap: _showApplyCouponDialog,
              ),
              _clientProfileMenuItem(
                icon: Icons.notifications_none_rounded,
                title: 'Notificações',
                subtitle: 'Alertas e preferências',
                onTap: _showNotificationsSheet,
              ),
              _clientProfileMenuItem(
                icon: Icons.shield_outlined,
                title: 'Segurança e privacidade',
                subtitle: 'PIN, dados e permissões',
                onTap: () => context.push('/settings'),
              ),
              _clientProfileMenuItem(
                icon: Icons.support_agent_outlined,
                title: 'Suporte',
                subtitle: 'Central de ajuda e contacto',
                onTap: () => context.push('/support'),
              ),
              _clientProfileMenuItem(
                icon: Icons.settings_outlined,
                title: 'Configurações',
                subtitle: 'Idioma, tema e outras preferências',
                onTap: () => context.push('/settings'),
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildClientProfileMenuCard(
            children: [
              _clientProfileMenuItem(
                icon: Icons.logout_rounded,
                title: 'Sair',
                subtitle: 'Terminar sessão na sua conta',
                danger: true,
                onTap: _logout,
                showDivider: false,
              ),
            ],
          ),
          const InstitutionalFooter(),
        ],
      ),
    );
  }

  Widget _buildClientProfileSummary(String location) {
    return _clientProfileCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 39,
            backgroundColor: AppColors.primaryRed.withValues(alpha: 0.10),
            backgroundImage: _avatarUrl?.trim().isNotEmpty == true
                ? NetworkImage(_avatarUrl!)
                : null,
            child: _avatarUrl?.trim().isNotEmpty == true
                ? null
                : const Icon(
                    Icons.person_rounded,
                    size: 40,
                    color: AppColors.primaryRed,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 17,
                      color: AppColors.primaryRed,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.neutralGray,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                const Text(
                  'Cliente DeliGo',
                  style: TextStyle(color: AppColors.neutralGray),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              await context.push('/profile');
              await _loadUserSummary();
            },
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Ver perfil'),
          ),
        ],
      ),
    );
  }

  Widget _buildClientWalletProfileCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF423D), Color(0xFFB7101A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Carteira DeliGo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Saldo disponível',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${_walletBalance.toStringAsFixed(2)} $_walletCurrency',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 29,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _clientWalletAction(
                icon: Icons.add_circle_outline_rounded,
                label: 'Depositar',
                onTap: () => context.push('/wallet?section=deposit'),
              ),
              _clientWalletAction(
                icon: Icons.payments_outlined,
                label: 'Levantar',
                onTap: () => context.push('/wallet?section=withdraw'),
              ),
              _clientWalletAction(
                icon: Icons.receipt_long_outlined,
                label: 'Histórico',
                onTap: () => context.push('/wallet?section=history'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _clientWalletModeChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    ),
  );

  Widget _clientWalletAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          children: [
            Icon(
              icon,
              color: onTap == null ? Colors.grey : AppColors.primaryRed,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: onTap == null ? Colors.grey : const Color(0xFF25272B),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildClientProfileMenuCard({required List<Widget> children}) =>
      _clientProfileCard(child: Column(children: children));

  Widget _clientProfileCard({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.035),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );

  Widget _clientProfileMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
    bool showDivider = true,
  }) {
    final color = danger ? AppColors.primaryRed : const Color(0xFF161A22);
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: 2,
          ),
          onTap: onTap,
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (danger ? AppColors.primaryRed : AppColors.primaryRed)
                  .withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color),
          ),
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w900, color: color),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.neutralGray),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        if (showDivider) const Divider(height: 1, indent: 56),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _loadError.isNotEmpty
                  ? _loadError
                  : 'Ocorreu um erro ao carregar.',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: _loadData,
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.mark_email_unread, color: Colors.orange),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Confirme seu email para liberar todas as funcoes.'),
          ),
          TextButton(
            onPressed: () async {
              final email = supabase.auth.currentUser?.email;
              if (email == null) return;
              try {
                await supabase.auth.resend(type: OtpType.signup, email: email);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Email reenviado.')),
                  );
                }
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nao foi possivel reenviar agora.'),
                    ),
                  );
                }
              }
            },
            child: const Text('Reenviar'),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeHeaderCompact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildHomeLogoMarquee()),
            const Spacer(),
            _clientHeaderAction(
              icon: Icons.notifications_none_rounded,
              badge: _unreadNotificationCount,
              tooltip: 'Notificacoes',
              onTap: _showNotificationsSheet,
            ),
            SupportHeadsetButton(onPressed: () => context.push('/support')),
            const SizedBox(width: 8),
            _buildCartQuickAction(),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: _profileHydrated
              ? InkWell(
                  onTap: () => context.push('/wallet'),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3F1),
                      border: Border.all(color: const Color(0xFFFFDAD5)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Olá, $_displayName  •  $_walletCurrency ${_walletBalance.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.primaryRed,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                )
              : _profileLoadFailed
              ? TextButton.icon(
                  onPressed: _loadUserSummary,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Tentar carregar os seus dados'),
                )
              : Container(
                  height: 34,
                  width: math
                      .min(MediaQuery.sizeOf(context).width * .62, 240)
                      .toDouble(),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .055),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHomeLogoMarquee() {
    return _buildDeliGoMarquee(fontSize: 28, fadeAtEdges: true);
  }

  Widget _buildDeliGoMarquee({
    required double fontSize,
    required bool fadeAtEdges,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final logoStyle = TextStyle(
          fontSize: fontSize,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: fontSize >= 28 ? -1.2 : -1,
        );
        final logoPainter = TextPainter(
          text: TextSpan(text: 'DeliGo', style: logoStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        // The real rendered width, not a fixed phone-specific estimate, defines
        // the right edge of the available header travel path.
        final renderedLogoWidth = logoPainter.width;
        final travelDistance = math.max(
          0.0,
          constraints.maxWidth - renderedLogoWidth,
        );
        return ClipRect(
          child: AnimatedBuilder(
            animation: _homeLogoMarqueeController,
            builder: (context, child) {
              final progress = _homeLogoMarqueeReducedMotion
                  ? 0.0
                  : _homeLogoMarqueeController.value;
              final gradientShift = (progress * 0.8) - 0.2;
              final gradientColors = fadeAtEdges
                  ? const [
                      Colors.transparent,
                      AppColors.primaryRed,
                      Color(0xFFFF8A3D),
                      AppColors.successGreen,
                      Color(0xFF2563EB),
                      Color(0xFF7C3AED),
                      Colors.transparent,
                    ]
                  : const [
                      AppColors.primaryRed,
                      Color(0xFFFF8A3D),
                      AppColors.successGreen,
                      Color(0xFF2563EB),
                      Color(0xFF7C3AED),
                    ];
              return ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment(-1 + gradientShift, 0),
                  end: Alignment(1 + gradientShift, 0),
                  colors: gradientColors,
                  stops: fadeAtEdges
                      ? const [0.0, 0.16, 0.32, 0.50, 0.68, 0.84, 1.0]
                      : null,
                ).createShader(bounds),
                child: Transform.translate(
                  offset: Offset(travelDistance * progress, 0),
                  child: child,
                ),
              );
            },
            child: SizedBox(
              width: renderedLogoWidth,
              child: Text(
                'DeliGo',
                maxLines: 1,
                softWrap: false,
                style: logoStyle,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHomeHeroBanner() => Container(
    height: 160,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      image: const DecorationImage(
        image: AssetImage('assets/marketing/deligo-food-hero.png'),
        fit: BoxFit.cover,
        alignment: Alignment.centerRight,
      ),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF9D0508).withValues(alpha: .92),
                  const Color(0xFFE92A2E).withValues(alpha: .52),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'SABORES\nQUE TE FAZEM\nSORRIR.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  height: .95,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: () => setState(() => _selectedIndex = 1),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Pede agora'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primaryRed,
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildHomeServiceTiles() {
    const items = [
      (Icons.restaurant_rounded, 'Restaurantes', 'Perto de ti'),
      (Icons.local_pizza_rounded, 'Pizzas', 'Sabores favoritos'),
      (Icons.lunch_dining_rounded, 'Hambúrgueres', 'Feitos na hora'),
      (Icons.local_fire_department_rounded, 'Mais pedidos', 'Em destaque'),
      (Icons.local_offer_rounded, 'Promoções', 'Ofertas especiais'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // About 2.2 cards are visible on a phone, with part of the next one
        // acting as the horizontal-scroll affordance.
        final cardWidth = (constraints.maxWidth * .43).clamp(142.0, 158.0);
        return SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              final category = switch (index) {
                1 => 'Pizza',
                2 => 'Hambúrgueres',
                _ => null,
              };
              return SizedBox(
                width: cardWidth,
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      if (index == 0) {
                        _selectedIndex = 1;
                        _exploreDishesMode = false;
                        _explorePopularDishes = false;
                      } else if (index == 1 || index == 2) {
                        _selectedIndex = 1;
                        _exploreDishesMode = true;
                        _selectedFoodCategory = DeligoFoodCategories.all.label;
                        _searchQuery = category == 'Pizza'
                            ? 'pizza'
                            : 'hamburguer';
                        _explorePopularDishes = false;
                      } else if (index == 3) {
                        _selectedIndex = 1;
                        _exploreDishesMode = true;
                        _selectedFoodCategory = DeligoFoodCategories.all.label;
                        _searchQuery = '';
                        _explorePopularDishes = true;
                      } else {
                        _selectedIndex = 0;
                        _explorePopularDishes = false;
                      }
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    side: const BorderSide(color: Color(0xFFE7E8EE)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primaryRed.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          item.$1,
                          color: AppColors.primaryRed,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.$2,
                              style: const TextStyle(
                                color: AppColors.deepBlack,
                                fontSize: 13,
                                height: 1.1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              item.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.neutralGray,
                                fontSize: 10,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _clientHeaderAction({
    required IconData icon,
    required int badge,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton.filledTonal(onPressed: onTap, icon: Icon(icon)),
          if (badge > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryRed,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildClientGlobalHeader() {
    final title = switch (_selectedIndex) {
      1 => 'Explorar',
      2 => 'Pedidos',
      3 => 'Favoritos',
      _ => 'Perfil',
    };
    return AppBar(
      titleSpacing: 12,
      toolbarHeight: 56,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      foregroundColor: AppColors.darkGray,
      title: Row(
        children: [
          SizedBox(width: 76, child: _buildCompactAnimatedLogo()),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      actions: [
        _buildCompactWalletAction(),
        _clientHeaderAction(
          icon: Icons.notifications_none_rounded,
          badge: _unreadNotificationCount,
          tooltip: 'Notificacoes',
          onTap: _showNotificationsSheet,
        ),
        SupportHeadsetButton(onPressed: () => context.push('/support')),
        const SizedBox(width: 6),
        _buildCartQuickAction(),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildCompactAnimatedLogo() {
    return _buildDeliGoMarquee(fontSize: 22, fadeAtEdges: false);
  }

  Widget _buildCompactWalletAction() {
    return Tooltip(
      message: 'Saldo da carteira',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => context.push('/wallet'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: _profileHydrated
              ? Text(
                  '$_walletCurrency ${_walletBalance.toStringAsFixed(0)}',
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.primaryRed,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : const SizedBox(
                  width: 42,
                  height: 3,
                  child: LinearProgressIndicator(minHeight: 3),
                ),
        ),
      ),
    );
  }

  Widget _buildBanners() {
    final items = <Widget>[];
    if (_address.isEmpty) {
      items.add(
        _buildBannerCard(
          title: 'Defina seu endereco',
          subtitle: 'Veja restaurantes proximos de voce',
          actionText: 'Ver enderecos',
          onTap: () async {
            await context.push('/profile?section=addresses');
            await _loadUserSummary();
          },
        ),
      );
    }
    if (!_pushActive) {
      items.add(
        _buildBannerCard(
          title: 'Ative notificacoes',
          subtitle: 'Acompanhe seus pedidos em tempo real',
          actionText: 'Ativar',
          onTap: _activatePush,
        ),
      );
    }
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(children: items);
  }

  Widget _buildBannerCard({
    required String title,
    required String subtitle,
    required String actionText,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: TextButton(onPressed: onTap, child: Text(actionText)),
      ),
    );
  }

  Widget _buildActiveOrderCard() {
    final order = _activeOrder;
    if (order == null) return const SizedBox.shrink();

    // Keep the Home focused on one compact operational summary. Products,
    // payment, chat, support and OTP remain available from order details.
    return _buildCompactActiveOrderCard(order);
    /*

    final screenWidth = MediaQuery.of(context).size.width;
    final compact = screenWidth < 380;
    final isCompletedOrder =
        order.status == OrderStatus.completed ||
        order.status == OrderStatus.autoCompleted;
    final confirmationRemaining = _restaurantConfirmationRemaining(order);
    final preparationRemaining = _preparationRemaining(order);
    final pendingPaymentRemaining = _pendingPaymentRemaining(order);
    final isAwaitingPayment = _isAwaitingPayment(order);
    final isAwaitingRestaurant = _isAwaitingRestaurantConfirmation(order);
    final isPreparing =
        order.status == OrderStatus.accepted ||
        order.status == OrderStatus.preparing;
    final isPickup = order.isPickup;
    final hasAssignedCourier = order.courierId?.trim().isNotEmpty == true;
    final showTrackingAction =
        !isPickup && hasAssignedCourier && !isCompletedOrder;
    final isSearchingNearbyCourier = _isCourierSearchWindow(order);
    final deliverySearchRemaining = _deliverySearchRemaining(order);
    final deliverySearchExpired =
        order.deliveryStatus.toLowerCase() == 'delivery_unavailable' &&
        order.courierId?.trim().isNotEmpty != true;
    final deliverySearchAwaitingServer =
        _hasActiveCourierDispatch(order) &&
        (deliverySearchRemaining == null ||
            deliverySearchRemaining == Duration.zero);
    // A recovery action must remain visible when the backend has left the
    // order in READY without setting the legacy delivery_status flag.
    final showPickupRecoveryActions =
        !isPickup &&
        !hasAssignedCourier &&
        order.status == OrderStatus.ready &&
        !isSearchingNearbyCourier &&
        !deliverySearchAwaitingServer;
    final canConfirmReceived =
        (isPickup &&
            (order.status == OrderStatus.ready ||
                order.status == OrderStatus.awaitingPickupConfirmation)) ||
        (!isPickup && order.status == OrderStatus.delivered);
    final progress = _progressForActiveOrder(
      order,
      isAwaitingRestaurant: isAwaitingRestaurant,
      isAwaitingPayment: isAwaitingPayment,
    );
    final totalPrepSeconds = (order.estimatedPreparationMinutes * 60).clamp(
      60,
      3600,
    );
    final remainingPrepSeconds = _preparationRemaining(order).inSeconds;

    final countdownLabel = isAwaitingPayment
        ? _formatRemaining(pendingPaymentRemaining)
        : isAwaitingRestaurant
        ? _formatRemaining(confirmationRemaining)
        : isPreparing
        ? _formatRemaining(preparationRemaining)
        : isSearchingNearbyCourier
        ? deliverySearchRemaining == null
              ? 'A procurar...'
              : _formatRemaining(deliverySearchRemaining)
        : '00:00';
    final countdownTitle = isAwaitingPayment
        ? 'Concluir pagamento em'
        : isAwaitingRestaurant
        ? 'Restaurante confirma em'
        : isPreparing
        ? 'Tempo de preparo'
        : isSearchingNearbyCourier
        ? deliverySearchRemaining == null
              ? 'A procurar estafetas proximos'
              : 'Tempo para encontrar estafeta'
        : isPickup
        ? (order.isCustomerPickupFallback
              ? 'Levantamento no restaurante'
              : 'Pronto para retirada')
        : 'Pedido em andamento';

    final accentColor = isAwaitingPayment
        ? AppColors.primaryRed
        : isAwaitingRestaurant
        ? Colors.orange
        : isPreparing
        ? AppColors.primaryRed
        : isSearchingNearbyCourier
        ? const Color(0xFF0F766E)
        : AppColors.successGreen;
    final unreadChats = _unreadChatCountFor(order.id);

    // Once the server marks dispatch unavailable, render a terminal state
    // instead of the normal searching/tracking card (timer, route and journey).
    if (deliverySearchExpired) {
      return _buildDeliveryUnavailableCard(order, compact: compact);
    }
    if (deliverySearchAwaitingServer) {
      return _buildDispatchFinalizingCard(order, compact: compact);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, accentColor.withValues(alpha: 0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  deliverySearchAwaitingServer
                      ? deliverySearchRemaining == null
                            ? 'A confirmar estado da procura...'
                            : 'A finalizar a procura de estafeta...'
                      : _activeOrderStatusLabel(order),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 15 : 16,
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isPickup || isCompletedOrder || showTrackingAction)
                Flexible(
                  child: OutlinedButton(
                    onPressed: isPickup
                        ? () => _openRestaurantMenuForOrder(order)
                        : isCompletedOrder
                        ? () => _openCourierProfileForOrder(order)
                        : () => context.push(
                            '/tracking/${order.id}?viewer=client',
                          ),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 12,
                        vertical: compact ? 8 : 10,
                      ),
                    ),
                    child: Text(
                      isPickup
                          ? 'Ver restaurante'
                          : isCompletedOrder
                          ? 'Ver estafeta'
                          : 'Ver rota',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
          if (!hasAssignedCourier) const SizedBox(height: 10),
          if (!hasAssignedCourier) Row(
            children: [
              const Icon(
                Icons.storefront_outlined,
                size: 17,
                color: AppColors.neutralGray,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _restaurantDisplayName(order),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.darkGray,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (!hasAssignedCourier) ...[
            const SizedBox(height: 8),
            Text(
              _activeOrderSubtitle(order),
              style: const TextStyle(
                color: AppColors.neutralGray,
                height: 1.35,
              ),
            ),
          ],
          if (!isPickup && order.status == OrderStatus.arrived) ...[
            const SizedBox(height: 10),
            _buildClientDeliveryOtp(order, compact),
          ],
          const SizedBox(height: 12),
          if (isAwaitingPayment ||
              isAwaitingRestaurant ||
              isPreparing ||
              (isSearchingNearbyCourier && !deliverySearchAwaitingServer))
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 10 : 12,
              ),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    countdownTitle,
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 12 : 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    countdownLabel,
                    style: TextStyle(
                      fontSize: compact ? 22 : 24,
                      fontWeight: FontWeight.w900,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value:
                          isSearchingNearbyCourier &&
                              deliverySearchRemaining == null
                          ? null
                          : progress,
                      minHeight: compact ? 5 : 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.45),
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  ),
                  if (isPreparing) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Preparo estimado: ${order.estimatedPreparationMinutes} min',
                      style: const TextStyle(
                        color: AppColors.neutralGray,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (deliverySearchExpired || showPickupRecoveryActions) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Desculpa, nao encontramos nenhum estafeta disponivel.',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.deepOrange,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Dirija-se ao restaurante para levantar o seu pedido ou inicie uma nova procura.',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            _convertUnavailableDeliveryFromCard(order),
                        icon: const Icon(Icons.storefront_outlined),
                        label: const Text('Recolher no restaurante'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _restartDeliverySearchFromCard(order),
                        icon: const Icon(Icons.timer_outlined),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (deliverySearchAwaitingServer) ...[
            const SizedBox(height: 10),
            Text(
              deliverySearchRemaining == null
                  ? 'A confirmar o estado da procura no servidor...'
                  : 'A finalizar a procura no servidor...',
              style: TextStyle(
                color: AppColors.neutralGray,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          // Courier identity/journey only exists after dispatch is active or a
          // courier was actually assigned. Preparation must remain a pure
          // restaurant state and cannot show a placeholder courier card.
          if (!isPickup && isSearchingNearbyCourier) ...[
            const SizedBox(height: 12),
            _buildCourierIdentityCard(order, compact),
            const SizedBox(height: 10),
            _buildDeliveryJourney(order, compact),
          ],
          if (!isPickup && hasAssignedCourier && !isCompletedOrder) ...[
            const SizedBox(height: 12),
            _buildCompactAssignedCourierCard(order, compact),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 360;
              final detailButton = Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push('/order/${order.id}'),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text(
                    'Detalhes do pedido',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
              final confirmButton = Expanded(
                child: FilledButton.icon(
                  onPressed: () => _confirmActiveOrderReceived(order.id),
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isPickup ? 'Confirmar retirada' : 'Confirmar',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
              final chatButton = SizedBox(
                width: double.infinity,
                child: OrderChatButton(
                  orderId: order.id,
                  onPressed: () => context.push('/chat/${order.id}'),
                  unreadCount: unreadChats,
                ),
              );

              final firstRow = canConfirmReceived
                  ? narrow
                        ? Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: detailButton.child,
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: confirmButton.child,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              detailButton,
                              const SizedBox(width: 8),
                              confirmButton,
                            ],
                          )
                  : SizedBox(width: double.infinity, child: detailButton.child);

              return Column(
                children: [
                  firstRow,
                  if (!isAwaitingRestaurant && !isAwaitingPayment) ...[
                    const SizedBox(height: 8),
                    chatButton,
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryUnavailableCard(Order order, {required bool compact}) {
    final restaurantName = _restaurantDisplayName(order);
    final unreadChats = _unreadChatCountFor(order.id);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.borderGray),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Não encontrámos estafeta disponível',
            style: TextStyle(
              color: AppColors.darkGray,
              fontSize: compact ? 17 : 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: 'O teu pedido está pronto no ',
              children: [
                TextSpan(
                  text: restaurantName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            style: TextStyle(
              color: AppColors.neutralGray,
              fontSize: compact ? 14 : 15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final pickupButton = FilledButton.icon(
                onPressed: () => _convertUnavailableDeliveryFromCard(order),
                icon: const Icon(Icons.storefront_outlined, size: 19),
                label: const Text('Recolher no restaurante'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              );
              final retryButton = OutlinedButton.icon(
                onPressed: () => _restartDeliverySearchFromCard(order),
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('Tentar novamente'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: AppColors.primaryRed,
                  side: const BorderSide(color: AppColors.primaryRed),
                ),
              );

              if (constraints.maxWidth < 390) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    pickupButton,
                    const SizedBox(height: 8),
                    retryButton,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: pickupButton),
                  const SizedBox(width: 10),
                  Expanded(child: retryButton),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push('/order/${order.id}'),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text('Detalhes do pedido'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.neutralGray,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
          OrderChatButton(
            orderId: order.id,
            onPressed: () => context.push('/chat/${order.id}'),
            unreadCount: unreadChats,
          ),
        ],
      ),
    );
  }
*/
  }

  Widget _buildCompactActiveOrderCard(Order order) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    final completed =
        order.status == OrderStatus.completed ||
        order.status == OrderStatus.autoCompleted;
    final assigned = order.courierId?.trim().isNotEmpty == true;
    final searching = _isCourierSearchWindow(order);
    final expired =
        !assigned &&
        (order.deliveryStatus.toLowerCase() == 'delivery_unavailable' ||
            (order.deliveryStatus.toLowerCase() == 'searching' &&
                order.dispatchExpiresAt != null &&
                !order.dispatchExpiresAt!.toUtc().isAfter(
                  _currentDateTime.toUtc(),
                )));
    final preparing =
        order.status == OrderStatus.accepted ||
        order.status == OrderStatus.preparing;
    final pickedUp =
        order.status == OrderStatus.pickedUp ||
        order.status == OrderStatus.inDelivery ||
        order.status == OrderStatus.inTransit ||
        order.status == OrderStatus.onTheWay ||
        order.status == OrderStatus.arrived;
    final motion = _activeCourierMotionAssessment;
    final locationUnavailable =
        assigned && motion?['state'] == 'location_unavailable';
    final motionRecoveryDue =
        assigned &&
        motion?['state'] == 'no_progress_confirmed' &&
        motion?['recovery_due'] == true &&
        order.pickedUpAt == null;
    final remaining = _deliverySearchRemaining(order);
    final title = motionRecoveryDue
        ? 'Atraso confirmado'
        : assigned
        ? (pickedUp ? 'Entrega em rota' : 'Estafeta encontrado')
        : _activeOrderStatusLabel(order);
    final description = motionRecoveryDue
        ? 'A tua entrega está a demorar mais do que o previsto.'
        : locationUnavailable
        ? 'Estamos a actualizar a localização da tua entrega.'
        : assigned
        ? (pickedUp
              ? 'Acompanha a entrega em tempo real.'
              : 'O estafeta está a caminho do restaurante.')
        : preparing
        ? 'O restaurante está a preparar o teu pedido.'
        : searching
        ? 'A procurar um estafeta disponível.'
        : _activeOrderSubtitle(order);
    final primaryLabel = assigned
        ? (pickedUp ? 'Acompanhar no mapa' : 'Ver estafeta no mapa')
        : null;

    if (expired) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(compact ? 13 : 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Não encontrámos estafeta disponível',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text('Pedido pronto no ${_restaurantDisplayName(order)}.'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _restartDeliverySearchFromCard(order),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tentar novamente'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _convertUnavailableDeliveryFromCard(order),
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('Recolher no restaurante'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: EdgeInsets.all(compact ? 13 : 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _restaurantDisplayName(order),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (preparing) ...[
              const SizedBox(height: 7),
              Text(
                'Tempo de preparo: ${_formatRemaining(_preparationRemaining(order))}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (searching && !assigned) ...[
              const SizedBox(height: 7),
              Text(
                remaining == null
                    ? 'A procurar...'
                    : 'Procura: ${_formatRemaining(remaining)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (primaryLabel != null) ...[
              const SizedBox(height: 11),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      context.push('/tracking/${order.id}?viewer=client'),
                  icon: const Icon(Icons.location_on_outlined, size: 18),
                  label: Text(primaryLabel),
                ),
              ),
            ],
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push('/order/${order.id}'),
                child: const Text('Detalhes do pedido'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDispatchFinalizingCard(Order order, {required bool compact}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A confirmar o resultado da procura',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            _restaurantDisplayName(order),
            style: const TextStyle(color: AppColors.neutralGray),
          ),
          const SizedBox(height: 2),
          TextButton.icon(
            onPressed: () => context.push('/order/${order.id}'),
            icon: const Icon(Icons.visibility_outlined, size: 17),
            label: const Text('Detalhes do pedido'),
          ),
        ],
      ),
    );
  }

  Widget _buildClientDeliveryOtp(Order order, bool compact) {
    return FutureBuilder<String?>(
      future: _orderService.getDeliveryOtpCode(order.id),
      builder: (context, snapshot) {
        final otp = snapshot.data?.trim() ?? '';
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'A carregar o codigo OTP da entrega...',
              style: TextStyle(color: AppColors.neutralGray),
            ),
          );
        }
        if (otp.isEmpty) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.primaryRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primaryRed.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.password_rounded, color: AppColors.primaryRed),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Codigo OTP da entrega',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Diga este codigo ao estafeta',
                      style: TextStyle(
                        color: AppColors.neutralGray,
                        fontSize: compact ? 11 : 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                otp,
                style: TextStyle(
                  color: AppColors.primaryRed,
                  fontSize: compact ? 24 : 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _orderHeadline(List<OrderItem> items) {
    if (items.isEmpty) return 'Pedido DeliGo';
    final names = items
        .map((item) => item.menuItem?.name?.trim() ?? '')
        .where((name) => name.isNotEmpty)
        .take(2)
        .toList();
    if (names.isEmpty) return 'Pedido DeliGo';
    if (items.length > 2) {
      return '${names.join(' + ')} +${items.length - 2}';
    }
    return names.join(' + ');
  }

  String _restaurantDisplayName(Order order) {
    final directName = order.restaurantName?.trim() ?? '';
    if (directName.isNotEmpty) {
      return directName;
    }

    for (final collection in [
      _restaurants,
      _localRestaurants,
      _featuredRestaurants,
      _favoriteRestaurants,
      _fastRestaurants,
    ]) {
      for (final restaurant in collection) {
        if (restaurant.id == order.restaurantId &&
            restaurant.name.trim().isNotEmpty) {
          return restaurant.name.trim();
        }
      }
    }

    return 'Restaurante';
  }

  // ignore: unused_element
  String _orderDeliveryLabel(Order order) {
    final isPickup = order.deliveryType == 'pickup';
    if (isPickup) {
      final isCompleted =
          order.status == OrderStatus.completed ||
          order.status == OrderStatus.autoCompleted;
      return isCompleted
          ? 'Retirou no restaurante'
          : 'Levantamento no restaurante';
    }
    return 'Delivery • ${order.deliveryAddress}';
  }

  String _deliveryDestinationLabel(Order order) {
    final isPickup = order.deliveryType == 'pickup';
    if (isPickup) {
      final isCompleted =
          order.status == OrderStatus.completed ||
          order.status == OrderStatus.autoCompleted;
      return isCompleted
          ? 'Retirou no restaurante'
          : 'Levantamento no restaurante';
    }
    final destination = LocationDisplay.displayAddress(
      address: order.deliveryAddress,
      fallback: 'Endereco do cliente confirmado no mapa',
    );
    return 'Delivery • $destination';
  }

  Future<String?> _resolveCourierIdForOrder(Order order) async {
    final directCourierId = order.courierId?.trim() ?? '';
    if (directCourierId.isNotEmpty) {
      return directCourierId;
    }

    try {
      final delivery = await supabase
          .from('deliveries')
          .select('courier_id')
          .eq('order_id', order.id)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final fallbackCourierId =
          delivery?['courier_id']?.toString().trim() ?? '';
      if (fallbackCourierId.isNotEmpty) {
        return fallbackCourierId;
      }
    } catch (_) {}

    try {
      final refreshedOrder = await _orderService.getOrderById(order.id);
      final refreshedCourierId = refreshedOrder?.courierId?.trim() ?? '';
      if (refreshedCourierId.isNotEmpty) {
        return refreshedCourierId;
      }
    } catch (_) {}

    return null;
  }

  Future<void> _openCourierProfileForOrder(Order order) async {
    final courierId = await _resolveCourierIdForOrder(order);
    if (!mounted) return;
    if (courierId == null || courierId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ainda nao encontramos o estafeta real deste pedido.'),
        ),
      );
      return;
    }
    context.push('/courier/$courierId?orderId=${order.id}');
  }

  void _openRestaurantMenuForOrder(Order order) {
    final restaurantId = order.restaurantId.trim();
    if (restaurantId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ainda nao encontramos o restaurante deste pedido.'),
        ),
      );
      return;
    }
    // This is a deliberate one-step action from the active-order card. Do
    // not reuse the burst-tap guard here: a previous restaurant page can
    // remain in the navigation future while the client is already back on
    // the dashboard, making the button appear inert on the next tap.
    context.push('/restaurant/${Uri.encodeComponent(restaurantId)}');
  }

  bool _isAutoCancelledOrder(Order order) {
    return order.status == OrderStatus.expired;
  }

  bool _shouldShowRestaurantActionForOrder(Order order) {
    if (order.restaurantId.trim().isEmpty) return false;
    if (order.isPickup) return true;
    if (_isAutoCancelledOrder(order)) return true;
    return order.isDelivery && order.isCompletedState;
  }

  bool _shouldShowCourierActionForOrder(Order order) {
    if (!order.isDelivery || !order.isCompletedState) return false;
    final courierId = order.courierId?.trim() ?? '';
    return courierId.isNotEmpty;
  }

  Future<List<OrderItem>> _loadOrderItemsFor(String orderId) async {
    final cached = _orderItemsCache[orderId];
    if (cached != null) return cached;
    final items = await _orderService.getOrderItems(orderId);
    if (items.isNotEmpty) {
      _orderItemsCache[orderId] = items;
    }
    return items;
  }

  void _hideOrder(String orderId) {
    if (orderId.isEmpty) return;
    setState(() => _hiddenOrderIds.add(orderId));
    _saveProfileSettings();
  }

  Future<void> _confirmActiveOrderReceived(String orderId) async {
    final result = await _orderService.confirmDeliveryDetailed(orderId);
    if (!mounted) return;
    if (result.success) {
      setState(() {
        _clientOrders = _clientOrders.map((order) {
          if (order.id != orderId) return order;
          final updated = order.toMap()
            ..['status'] = (result.status ?? 'completed')
            ..['payment_status'] = 'settled'
            ..['funds_status'] = 'released'
            ..['confirmed_by_customer'] = true
            ..['order_completed_at'] = DateTime.now().toUtc().toIso8601String()
            ..['settlement_processed_at'] = DateTime.now()
                .toUtc()
                .toIso8601String()
            ..['updated_at'] = DateTime.now().toUtc().toIso8601String();
          return Order.fromMap(updated);
        }).toList();
        if (_activeOrder?.id == orderId) {
          _activeOrder = null;
        }
      });
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
    await _refreshActiveOrder();
    if (result.success) {
      await _loadData();
    }
  }

  Future<_CourierSnapshot> _loadCourierSnapshot(String courierId) async {
    final trimmedId = courierId.trim();
    if (trimmedId.isEmpty) {
      return const _CourierSnapshot(name: 'Estafeta DeliGo', phone: '');
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select('full_name, phone, avatar_url')
          .eq('id', trimmedId)
          .maybeSingle();
      final courier = await supabase
          .from('couriers')
          .select('*')
          .eq('id', trimmedId)
          .maybeSingle();

      final name = profile?['full_name']?.toString().trim().isNotEmpty == true
          ? profile!['full_name'].toString().trim()
          : courier?['full_name']?.toString().trim().isNotEmpty == true
          ? courier!['full_name'].toString().trim()
          : 'Estafeta DeliGo';
      final phone = profile?['phone']?.toString().trim().isNotEmpty == true
          ? profile!['phone'].toString().trim()
          : courier?['phone']?.toString().trim() ?? '';
      final avatarUrl =
          profile?['avatar_url']?.toString().trim().isNotEmpty == true
          ? profile!['avatar_url'].toString().trim()
          : courier?['avatar_url']?.toString().trim();

      return _CourierSnapshot(
        name: name,
        phone: phone,
        avatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl : null,
      );
    } catch (_) {
      return const _CourierSnapshot(name: 'Estafeta DeliGo', phone: '');
    }
  }

  Future<_CourierSnapshot> _courierSnapshotFor(String courierId) {
    final trimmedId = courierId.trim();
    return _courierSnapshotFutures.putIfAbsent(
      trimmedId,
      () => _loadCourierSnapshot(trimmedId),
    );
  }

  bool _hasDialablePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), '').length >= 9;

  Future<void> _callPhoneNumber(
    String rawPhone, {
    String contactLabel = 'estafeta',
  }) async {
    final trimmed = rawPhone.trim();
    if (trimmed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Numero do $contactLabel indisponivel.')),
      );
      return;
    }

    final uri = Uri(
      scheme: 'tel',
      path: trimmed.replaceAll(RegExp(r'[^0-9+]'), ''),
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel abrir a chamada agora.'),
        ),
      );
    }
  }

  Widget _buildCompactAssignedCourierCard(Order order, bool compact) {
    final courierId = order.courierId?.trim() ?? '';
    if (courierId.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<_CourierSnapshot>(
      future: _courierSnapshotFor(courierId),
      builder: (context, snapshot) {
        final courier =
            snapshot.data ??
            const _CourierSnapshot(name: 'Estafeta DeliGo', phone: '');
        final phone = courier.phone.trim();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7F8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDFE7EA)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: compact ? 22 : 24,
                backgroundColor: AppColors.primaryRed.withValues(alpha: .12),
                backgroundImage: courier.avatarUrl != null
                    ? CachedNetworkImageProvider(courier.avatarUrl!)
                    : null,
                child: courier.avatarUrl == null
                    ? Text(
                        courier.name.isEmpty
                            ? 'E'
                            : courier.name.characters.first.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primaryRed,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  courier.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton(
                onPressed: () =>
                    context.push('/tracking/${order.id}?viewer=client'),
                child: const Text('Ver rota'),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Ligar',
                onPressed: _hasDialablePhone(phone)
                    ? () => _callPhoneNumber(phone, contactLabel: 'estafeta')
                    : null,
                icon: const Icon(Icons.call_outlined),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCourierIdentityCard(Order order, bool compact) {
    final courierId = order.courierId?.trim() ?? '';
    if (courierId.isEmpty) {
      // No placeholder courier card: before a server-authoritative dispatch
      // or assignment, the order must remain in restaurant preparation.
      return const SizedBox.shrink();
    }

    return FutureBuilder<_CourierSnapshot>(
      future: _courierSnapshotFor(courierId),
      builder: (context, snapshot) {
        final courier =
            snapshot.data ??
            const _CourierSnapshot(name: 'Estafeta DeliGo', phone: '');
        final avatarSize = compact ? 42.0 : 48.0;
        final phone = courier.phone.trim();

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7F8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDFE7EA)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: avatarSize / 2,
                    backgroundColor: AppColors.primaryRed.withValues(
                      alpha: 0.12,
                    ),
                    backgroundImage: courier.avatarUrl != null
                        ? CachedNetworkImageProvider(courier.avatarUrl!)
                        : null,
                    child: courier.avatarUrl == null
                        ? Text(
                            courier.name.isNotEmpty
                                ? courier.name.characters.first.toUpperCase()
                                : 'E',
                            style: const TextStyle(
                              color: AppColors.primaryRed,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          courier.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 14 : 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          phone.isNotEmpty
                              ? phone
                              : 'Numero ainda indisponivel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.neutralGray,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openCourierProfileForOrder(order),
                      icon: const Icon(Icons.badge_outlined, size: 18),
                      label: const Text('Ver estafeta'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _hasDialablePhone(phone)
                          ? () => _callPhoneNumber(
                              phone,
                              contactLabel: 'estafeta',
                            )
                          : null,
                      icon: const Icon(Icons.call_outlined, size: 18),
                      label: const Text('Ligar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeliveryJourney(Order order, bool compact) {
    final currentStep = switch (order.status) {
      OrderStatus.ready => 0,
      OrderStatus.courierAssigned => 1,
      OrderStatus.inTransit || OrderStatus.onTheWay => 2,
      OrderStatus.arrived ||
      OrderStatus.delivered ||
      OrderStatus.completed ||
      OrderStatus.autoCompleted => 3,
      _ => 0,
    };

    final steps = <({IconData icon, String title, String subtitle})>[
      (
        icon: Icons.storefront_outlined,
        title: 'Restaurante',
        subtitle: 'Pedido pronto',
      ),
      (
        icon: Icons.delivery_dining_outlined,
        title: 'Estafeta atribuido',
        subtitle: 'Vai levantar',
      ),
      (
        icon: Icons.route_outlined,
        title: 'Em rota',
        subtitle: 'Do restaurante ate ti',
      ),
      (
        icon: Icons.home_outlined,
        title: 'Chegada',
        subtitle: 'Entrega no teu endereco',
      ),
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            order.status == OrderStatus.courierAssigned
                ? 'O estafeta segue primeiro ao restaurante e depois vem ate ti.'
                : order.status == OrderStatus.inTransit ||
                      order.status == OrderStatus.onTheWay
                ? 'O pedido ja saiu do restaurante e segue para a tua morada.'
                : order.status == OrderStatus.arrived
                ? 'O estafeta ja chegou ao teu local.'
                : 'A rota da entrega fica visivel aqui, do restaurante ate ao cliente.',
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              color: AppColors.neutralGray,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(steps.length * 2 - 1, (index) {
              if (index.isOdd) {
                final connectorActive = index ~/ 2 < currentStep;
                return Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: connectorActive
                          ? AppColors.primaryRed
                          : AppColors.borderGray,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                );
              }

              final stepIndex = index ~/ 2;
              final step = steps[stepIndex];
              final active = stepIndex <= currentStep;
              return Column(
                children: [
                  Container(
                    width: compact ? 30 : 34,
                    height: compact ? 30 : 34,
                    decoration: BoxDecoration(
                      color: active ? AppColors.primaryRed : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active
                            ? AppColors.primaryRed
                            : AppColors.borderGray,
                      ),
                    ),
                    child: Icon(
                      step.icon,
                      size: compact ? 16 : 18,
                      color: active ? Colors.white : AppColors.neutralGray,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: compact ? 68 : 78,
                    child: Column(
                      children: [
                        Text(
                          step.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 11 : 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          step.subtitle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 10 : 11,
                            color: AppColors.neutralGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLocationDropdown() {
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: 'all',
        child: Text(
          _addressCity.isEmpty
              ? 'Todas as zonas disponíveis'
              : 'Todas as zonas de $_addressCity',
        ),
      ),
    ];

    if (_addressNeighborhood.isNotEmpty) {
      items.add(
        DropdownMenuItem(
          value: 'nearby',
          child: Text('Perto de mim · $_addressNeighborhood'),
        ),
      );
    }
    final zones =
        _restaurants
            .map((restaurant) => restaurant.neighborhood?.trim() ?? '')
            .where((zone) => zone.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    for (final zone in zones) {
      items.add(DropdownMenuItem(value: 'zone:$zone', child: Text(zone)));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.14)),
      ),
      child: DropdownButtonFormField<String>(
        value: _locationFilter,
        isExpanded: true,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          labelText: 'Filtrar restaurantes',
          prefixIcon: Icon(Icons.place_outlined),
        ),
        items: items,
        onChanged: (value) {
          if (value == null) return;
          setState(() => _locationFilter = value);
        },
      ),
    );
  }

  Future<void> _showExploreFilters() async {
    var openNow = _exploreOpenNow;
    var maxEta = _exploreMaxDeliveryMinutes;
    var minRating = _exploreMinimumRating;
    var freeDelivery = _exploreFreeDelivery;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Wrap(
              runSpacing: 14,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderGray,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const Text(
                  'Filtros de exploração',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                Text(
                  _addressCity.isEmpty
                      ? 'Defina a cidade no seu endereço para ver zonas disponíveis.'
                      : 'Cidade: $_addressCity · os resultados respeitam a área de entrega.',
                  style: const TextStyle(color: AppColors.neutralGray),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aberto agora'),
                  value: openNow,
                  onChanged: (value) => setModalState(() => openNow = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Entrega grátis'),
                  value: freeDelivery,
                  onChanged: (value) =>
                      setModalState(() => freeDelivery = value),
                ),
                const Text(
                  'Tempo de entrega',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Wrap(
                  spacing: 8,
                  children: [null, 25, 35, 45]
                      .map(
                        (minutes) => ChoiceChip(
                          label: Text(
                            minutes == null ? 'Qualquer' : 'Até $minutes min',
                          ),
                          selected: maxEta == minutes,
                          onSelected: (_) =>
                              setModalState(() => maxEta = minutes),
                        ),
                      )
                      .toList(),
                ),
                const Text(
                  'Avaliação',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Wrap(
                  spacing: 8,
                  children: [null, 4.0, 4.5]
                      .map(
                        (rating) => ChoiceChip(
                          label: Text(
                            rating == null
                                ? 'Qualquer'
                                : '★ ${rating.toStringAsFixed(1)}+',
                          ),
                          selected: minRating == rating,
                          onSelected: (_) =>
                              setModalState(() => minRating = rating),
                        ),
                      )
                      .toList(),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _exploreOpenNow = openNow;
                        _exploreMaxDeliveryMinutes = maxEta;
                        _exploreMinimumRating = minRating;
                        _exploreFreeDelivery = freeDelivery;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Ver resultados'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMarketingCampaignCenter() {
    if (_marketingCampaignSections.isNotEmpty) {
      final sectionEventIds = <String>{};
      for (final section in _marketingCampaignSections) {
        final items = (section['items'] as List?) ?? const [];
        for (final item in items.whereType<Map>()) {
          final eventId = item['event_id']?.toString();
          if (eventId != null && eventId.isNotEmpty) {
            sectionEventIds.add(eventId);
          }
        }
      }
      final extraEvents = _marketingCampaigns
          .where((item) {
            final eventId = item['event_id']?.toString() ?? '';
            if (eventId.isEmpty || sectionEventIds.contains(eventId)) {
              return false;
            }
            return _isEventMarketingItem(item) && _isActiveMarketingItem(item);
          })
          .map(_buildMarketingCampaignCard)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _showApplyCouponDialog,
              icon: const Icon(Icons.card_giftcard),
              label: const Text('Tenho um codigo'),
            ),
          ),
          ..._marketingCampaignSections.map(_buildMarketingSectionFromEngine),
          if (extraEvents.isNotEmpty)
            _buildHorizontalMarketingSection(
              title: 'Eventos e Bilhetes',
              subtitle: 'Eventos publicados diretamente no DeliGo',
              cards: extraEvents,
            ),
        ],
      );
    }

    final banners = _marketingCampaigns
        .where((item) => item['placement'] == 'home_banner')
        .take(3)
        .toList();
    final featured = _marketingCampaigns
        .where((item) => item['placement'] == 'featured_restaurant')
        .take(5)
        .map(_buildMarketingCampaignCard)
        .toList();
    final events = _marketingCampaigns
        .where(
          (item) => _isEventMarketingItem(item) && _isActiveMarketingItem(item),
        )
        .map(_buildMarketingCampaignCard)
        .toList();
    final smart = _marketingCampaigns
        .where((item) => item['placement'] == 'smart_discovery')
        .take(6)
        .map(_buildMarketingCampaignCard)
        .toList();
    final coupons = _marketingCampaigns
        .where((item) => item['coupon_code']?.toString().isNotEmpty == true)
        .take(6)
        .map(_buildMarketingCampaignCard)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _showApplyCouponDialog,
            icon: const Icon(Icons.card_giftcard),
            label: const Text('Tenho um codigo'),
          ),
        ),
        if (banners.isNotEmpty) _buildMarketingHeroBanner(banners.first),
        if (banners.isNotEmpty) const SizedBox(height: 14),
        if (coupons.isNotEmpty)
          _buildHorizontalMarketingSection(
            title: 'Cupoes e Promocoes',
            subtitle: 'Codigos criados pela equipa de Marketing',
            cards: coupons,
          ),
        if (coupons.isNotEmpty) const SizedBox(height: 14),
        if (featured.isNotEmpty)
          _buildHorizontalMarketingSection(
            title: 'Restaurantes em Destaque',
            subtitle: 'Escolhas patrocinadas e Restaurante do Dia',
            cards: featured,
          ),
        if (featured.isNotEmpty) const SizedBox(height: 14),
        if (events.isNotEmpty)
          _buildHorizontalMarketingSection(
            title: 'Eventos e Bilhetes',
            subtitle: 'Compre bilhetes e receba QR Code unico',
            cards: events,
          ),
        if (events.isNotEmpty) const SizedBox(height: 14),
        if (smart.isNotEmpty)
          _buildHorizontalMarketingSection(
            title: 'Descoberta Inteligente',
            subtitle: 'Recomendacoes por horario, zona e preferencia',
            cards: smart,
          ),
        if (banners.isEmpty &&
            coupons.isEmpty &&
            featured.isEmpty &&
            events.isEmpty &&
            smart.isEmpty)
          _buildMarketingEmptyState(),
      ],
    );
  }

  Widget _buildMarketingEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGray),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.campaign_outlined,
              color: AppColors.primaryRed,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sem campanhas ativas agora',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  'Cupons, promocoes, eventos e bilhetes aparecem aqui quando forem publicados.',
                  style: TextStyle(color: AppColors.neutralGray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketingSectionFromEngine(Map<String, dynamic> section) {
    final key = section['key']?.toString() ?? '';
    final title = section['title']?.toString() ?? 'Campanhas';
    final rawItems = (section['items'] as List?) ?? const [];
    final items = rawItems
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final cards = items.map(_buildMarketingCampaignCard).toList();
    final subtitle = switch (key) {
      'daily_offers' => 'Expiram automaticamente conforme regras do Marketing',
      'restaurant_of_day' =>
        'Mais destaque, selo especial e prioridade no feed',
      'promotions' => 'Promocoes ativas para a sua zona e perfil',
      'events' => 'Eventos perto de si e bilhetes com QR Code',
      'coupons' => 'Codigos promocionais criados pela equipa Marketing',
      'banners' => 'Destaques principais do app',
      'smart_discovery' => 'Pontuado por localizacao, hora e historico',
      'sponsored' => 'Campanhas patrocinadas relevantes',
      _ => 'Selecionado pelo Centro de Campanhas',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: key == 'banners'
          ? _buildMarketingHeroBanner(items.first)
          : _buildHorizontalMarketingSection(
              title: title,
              subtitle: subtitle,
              cards: cards,
            ),
    );
  }

  Widget _buildMarketingHeroBanner(Map<String, dynamic> campaign) {
    final imageUrl = campaign['image_url']?.toString() ?? '';
    final isSponsored = _isSponsoredCampaign(campaign);
    return GestureDetector(
      onTap: () => _openMarketingCampaign(campaign),
      child: Container(
        height: 168,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFB71C1C), Color(0xFFFF7043)],
          ),
          image: imageUrl.isEmpty
              ? null
              : DecorationImage(
                  image: CachedNetworkImageProvider(imageUrl),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.25),
                    BlendMode.darken,
                  ),
                ),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (isSponsored) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Patrocinado',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
            ],
            Text(
              campaign['title']?.toString() ?? 'Destaque DeliGo',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              campaign['subtitle']?.toString() ??
                  campaign['description']?.toString() ??
                  'Promocao ativa agora',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalMarketingSection({
    required String title,
    required String subtitle,
    required List<Widget> cards,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: AppColors.neutralGray)),
        const SizedBox(height: 10),
        SizedBox(
          height: 154,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => cards[index],
          ),
        ),
      ],
    );
  }

  Widget _buildMarketingCampaignCard(Map<String, dynamic> campaign) {
    final restaurant = campaign['restaurants'] is Map
        ? Map<String, dynamic>.from(campaign['restaurants'] as Map)
        : const <String, dynamic>{};
    final coupon = campaign['coupon_code']?.toString() ?? '';
    final isSponsored = _isSponsoredCampaign(campaign);
    return GestureDetector(
      onTap: () => _openMarketingCampaign(campaign),
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderGray),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _marketingCampaignIcon(campaign),
                  color: AppColors.primaryRed,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    campaign['title']?.toString() ?? 'Campanha DeliGo',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (isSponsored) ...[
                  const SizedBox(width: 6),
                  const Text(
                    'Patrocinado',
                    style: TextStyle(
                      color: AppColors.neutralGray,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              campaign['subtitle']?.toString() ??
                  restaurant['name']?.toString() ??
                  campaign['description']?.toString() ??
                  'Ver agora',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.darkGray),
            ),
            const Spacer(),
            Row(
              children: [
                if (coupon.isNotEmpty)
                  Chip(
                    label: Text(coupon),
                    visualDensity: VisualDensity.compact,
                  ),
                const Spacer(),
                Text(
                  campaign['action_label']?.toString() ?? 'Ver',
                  style: const TextStyle(
                    color: AppColors.primaryRed,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _isSponsoredCampaign(Map<String, dynamic> campaign) {
    final metadata = campaign['metadata'] is Map
        ? Map<String, dynamic>.from(campaign['metadata'] as Map)
        : const <String, dynamic>{};
    return campaign['campaign_type']?.toString() == 'sponsored' ||
        campaign['placement']?.toString() == 'sponsored' ||
        metadata['is_sponsored'] == true;
  }

  IconData _marketingCampaignIcon(Map<String, dynamic> campaign) {
    switch (campaign['campaign_type']?.toString()) {
      case 'coupon':
        return Icons.card_giftcard;
      case 'event':
      case 'ticket':
        return Icons.confirmation_number_outlined;
      case 'featured_restaurant':
        return Icons.workspace_premium_outlined;
      case 'daily_offer':
        return Icons.local_fire_department_outlined;
      case 'smart_discovery':
        return Icons.auto_awesome;
      default:
        return Icons.campaign_outlined;
    }
  }

  Future<void> _showApplyCouponDialog() async {
    final controller = TextEditingController();
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Inserir codigo promocional'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'BEMVINDO50'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (apply != true || controller.text.trim().isEmpty) return;
    try {
      final result = await _marketingService.applyCouponCode(controller.text);
      final success = result['success'] == true;
      final value = result['discount_value']?.toString() ?? '';
      final type = result['discount_type']?.toString() ?? '';
      _showAppSnack(
        success
            ? "Cupao aplicado: $value ${type == 'percent' ? '%' : 'MZN'}"
            : 'Codigo invalido ou expirado.',
        success: success,
      );
    } catch (error) {
      _showAppSnack('Nao foi possivel aplicar o codigo.');
    }
  }

  void _openMarketingCampaign(Map<String, dynamic> campaign) {
    if (_isEventMarketingItem(campaign)) {
      unawaited(_openEventDetails(campaign));
      return;
    }
    final eventId = campaign['event_id']?.toString() ?? '';
    final id = campaign['id']?.toString() ?? '';
    final detailId = eventId.isNotEmpty ? 'event-$eventId' : id;
    if (detailId.isEmpty) return;
    context.push('/campaign/$detailId', extra: campaign);
  }

  Future<void> _openEventDetails(Map<String, dynamic> campaign) async {
    final eventId = campaign['event_id']?.toString() ?? '';
    Map<String, dynamic> event = campaign;
    if (eventId.isNotEmpty) {
      final fetched = await _marketingService.fetchEventById(eventId);
      if (fetched != null) event = {...campaign, ...fetched};
    }
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildEventDetailsSheet(event),
    );
  }

  Widget _buildEventDetailsSheet(Map<String, dynamic> event) {
    final metadata = event['metadata'] is Map
        ? Map<String, dynamic>.from(event['metadata'] as Map)
        : const <String, dynamic>{};
    final imageUrl = event['banner_url']?.toString().trim().isNotEmpty == true
        ? event['banner_url']!.toString()
        : event['poster_url']?.toString().trim().isNotEmpty == true
        ? event['poster_url']!.toString()
        : event['image_url']?.toString() ?? '';
    final title = event['title']?.toString() ?? 'Evento DeliGo';
    final description = event['description']?.toString() ?? '';
    final location =
        event['location']?.toString() ?? metadata['location']?.toString() ?? '';
    final schedule = _eventScheduleLabel(event, metadata);
    final sellsTickets =
        event['sells_tickets'] == true ||
        event['campaign_type']?.toString() == 'ticket';
    final ticketPrice = event['ticket_price']?.toString() ?? '';
    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.94,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.zero,
            children: [
              if (imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _eventInfoRow(Icons.schedule_rounded, schedule),
                    if (location.isNotEmpty)
                      _eventInfoRow(Icons.place_outlined, location),
                    if (sellsTickets)
                      _eventInfoRow(
                        Icons.confirmation_number_outlined,
                        ticketPrice.isNotEmpty
                            ? 'Bilhetes a partir de $ticketPrice MZN'
                            : 'Bilhetes disponiveis no DeliGo',
                      ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Detalhes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: const TextStyle(
                          color: AppColors.darkGray,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Entendi'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _eventInfoRow(IconData icon, String text) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primaryRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _activeMarketingSections(
    List<Map<String, dynamic>> sections,
  ) {
    return sections
        .map((section) {
          final items = ((section['items'] as List?) ?? const [])
              .whereType<Map>()
              .map(
                (item) =>
                    item.map((key, value) => MapEntry(key.toString(), value)),
              )
              .where(_isActiveMarketingItem)
              .toList();
          return {...section, 'items': items};
        })
        .where(
          (section) => ((section['items'] as List?) ?? const []).isNotEmpty,
        )
        .toList();
  }

  bool _isEventMarketingItem(Map<String, dynamic> item) {
    return item['placement'] == 'tickets' ||
        item['placement'] == 'events_today' ||
        item['campaign_type'] == 'event' ||
        item['campaign_type'] == 'ticket';
  }

  bool _isActiveMarketingItem(Map<String, dynamic> item) {
    if (!_isEventMarketingItem(item)) return true;
    final status = item['status']?.toString().toLowerCase();
    if (status == 'completed' || status == 'cancelled') return false;
    final metadata = item['metadata'] is Map
        ? Map<String, dynamic>.from(item['metadata'] as Map)
        : const <String, dynamic>{};
    final end = item['ends_at']?.toString();
    final parsedEnd = end == null || end.isEmpty
        ? _eventDateTimeFromMetadata(metadata)
        : DateTime.tryParse(end);
    if (parsedEnd == null) return true;
    return parsedEnd.isAfter(DateTime.now());
  }

  DateTime? _eventDateTimeFromMetadata(Map<String, dynamic> metadata) {
    final date = metadata['event_date']?.toString().trim();
    if (date == null || date.isEmpty) return null;
    final endTime = metadata['event_end_time']?.toString().trim();
    final startTime = metadata['event_time']?.toString().trim();
    final time = (endTime != null && endTime.isNotEmpty)
        ? endTime
        : (startTime != null && startTime.isNotEmpty ? startTime : '23:59');
    return DateTime.tryParse('${date}T$time');
  }

  String _eventScheduleLabel(
    Map<String, dynamic> event,
    Map<String, dynamic> metadata,
  ) {
    final date =
        event['event_date']?.toString() ?? metadata['event_date']?.toString();
    final start =
        event['event_time']?.toString() ?? metadata['event_time']?.toString();
    final end =
        event['event_end_time']?.toString() ??
        metadata['event_end_time']?.toString();
    if (date == null || date.isEmpty) return 'Horario a confirmar';
    final parsed = DateTime.tryParse(date);
    final day = parsed == null
        ? date
        : '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
    if (start == null || start.isEmpty) return day;
    return end == null || end.isEmpty ? '$day as $start' : '$day, $start-$end';
  }

  void _showAppSnack(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? AppColors.successGreen
            : AppColors.primaryRed,
        content: Text(message),
      ),
    );
  }

  Widget _buildPlanningCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Planeamento do seu pedido',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (_scheduledDelivery != null)
            Text(
              'Entrega agendada para ${_formatDateTime(_scheduledDelivery!)}',
            ),
          if (_groupOrderCode != null && _groupOrderCode!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Pedido em grupo ativo: $_groupOrderCode'),
            const SizedBox(height: 4),
            const Text(
              'Partilhe o codigo e depois o host finaliza e paga tudo no checkout.',
              style: TextStyle(color: AppColors.neutralGray),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_groupOrderCode != null && _groupOrderCode!.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _copyGroupOrderCode,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copiar codigo'),
                ),
              OutlinedButton.icon(
                onPressed: _joinGroupOrder,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Entrar com codigo'),
              ),
              TextButton.icon(
                onPressed: _clearPlanningState,
                icon: const Icon(Icons.close),
                label: const Text('Limpar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _matchesOrderStatusFilter(Order order) {
    switch (_orderStatusFilter) {
      case 'pending':
        return order.status == OrderStatus.pending ||
            order.status == OrderStatus.paymentAuthorized ||
            order.status == OrderStatus.paid;
      case 'in_transit':
        return order.status == OrderStatus.accepted ||
            order.status == OrderStatus.preparing ||
            order.status == OrderStatus.ready ||
            order.status == OrderStatus.courierAssigned ||
            order.status == OrderStatus.inTransit ||
            order.status == OrderStatus.onTheWay ||
            order.status == OrderStatus.arrived ||
            order.status == OrderStatus.delivered ||
            order.status == OrderStatus.disputed;
      case 'completed':
        return order.status == OrderStatus.completed ||
            order.status == OrderStatus.autoCompleted;
      case 'cancelled':
        return order.status == OrderStatus.cancelled;
      default:
        return true;
    }
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y as $h:$min';
  }

  String _formatLiveClock(DateTime value) {
    final local = value.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final sec = local.second.toString().padLeft(2, '0');
    return '$d/$m/$y - $h:$min:$sec';
  }

  int _shareCountFor(String restaurantId) {
    final stats = _shareStatsByRestaurantId[restaurantId];
    return (stats?['total_shares'] as num?)?.toInt() ?? 0;
  }

  Widget _buildShareTrendSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
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
          const Row(
            children: [
              Icon(Icons.local_fire_department, color: Color(0xFFFF6A3D)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trend local de partilhas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Os restaurantes que mais estao circulando hoje no DeliGo.',
            style: TextStyle(color: AppColors.neutralGray),
          ),
          const SizedBox(height: 14),
          ..._topSharedRestaurants.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            final totalShares = (row['total_shares'] as num?)?.toInt() ?? 0;
            final channelOpens = (row['channel_opens'] as num?)?.toInt() ?? 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primaryRed.withValues(
                      alpha: 0.12,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: AppColors.primaryRed,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['restaurant_name']?.toString() ?? 'Restaurante',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '$totalShares partilhas - $channelOpens aberturas',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.neutralGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.trending_up, color: Color(0xFFFF6A3D)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHomeShowcaseSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required List<Restaurant> restaurants,
    required _FeaturedCardVariant variant,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 0, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkGray,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AppColors.neutralGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // The card contains a wrapping row of badges.  265px was too tight
          // on the client home and caused "BOTTOM OVERFLOWED BY 21 PIXELS"
          // for the DeliGo restaurant card on smaller Android screens.
          SizedBox(
            // The rail needs a viewport height, but the card itself remains
            // intrinsic and ends immediately after its last information row.
            height: 256,
            child: ListView.separated(
              padding: const EdgeInsets.only(right: 18),
              scrollDirection: Axis.horizontal,
              itemCount: restaurants.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _buildFeaturedCardVariant(
                restaurants[index],
                variant: variant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedCardVariant(
    Restaurant restaurant, {
    required _FeaturedCardVariant variant,
  }) {
    final deliveryTime = restaurant.deliveryTime ?? 25;
    final bool isFast = variant == _FeaturedCardVariant.fast;
    final Color accentColor = isFast
        ? AppColors.primaryOrange
        : AppColors.primaryRed;
    final String badgeLabel = isFast ? 'Rota agil' : 'Em destaque';
    final IconData badgeIcon = isFast
        ? Icons.bolt_rounded
        : Icons.workspace_premium_rounded;
    final locationLabel = LocationDisplay.smartLocation(
      address: restaurant.address,
      neighborhood: restaurant.neighborhood,
      city: restaurant.city,
    );

    return DeligoPressable(
      onTap: () {
        debugPrint(
          '[HOME] restaurant card tapped id=${restaurant.id} name=${restaurant.name}',
        );
        GuardedNavigation.push(context, '/restaurant/${restaurant.id}');
      },
      borderRadius: BorderRadius.circular(16),
      splashColor: accentColor.withValues(alpha: 0.16),
      child: SizedBox(
        width: 224,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: restaurant.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: restaurant.imageUrl!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    accentColor.withValues(alpha: 0.9),
                                    AppColors.primaryRed.withValues(
                                      alpha: 0.75,
                                    ),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.restaurant_menu_rounded,
                                  color: Colors.white,
                                  size: 42,
                                ),
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(badgeIcon, color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            badgeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: _buildFavoriteButton(restaurant),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkGray,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      locationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _buildInfoChip(
                          Icons.star,
                          restaurant.rating?.toStringAsFixed(1) ?? 'Novo',
                          Colors.amber,
                        ),
                        _buildInfoChip(
                          Icons.access_time_filled_rounded,
                          '$deliveryTime min',
                          accentColor,
                        ),
                        _buildInfoChip(
                          Icons.delivery_dining_rounded,
                          '100-200 MZN',
                          AppColors.successGreen,
                        ),
                        _buildInfoChip(
                          restaurant.isOpen
                              ? Icons.storefront_rounded
                              : Icons.storefront_outlined,
                          restaurant.isOpen ? 'Aberto' : 'Fechado',
                          restaurant.isOpen
                              ? AppColors.successGreen
                              : AppColors.alertRed,
                        ),
                      ],
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

  Widget _buildRestaurantShimmers() {
    return Column(
      children: List.generate(3, (index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: List.generate(
                          2,
                          (_) => Container(
                            margin: const EdgeInsets.only(right: 6),
                            height: 20,
                            width: 64,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        height: 11,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 11,
                        width: 170,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildShowcaseShimmer({
    required String title,
    required Color accentColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 11,
                    width: 220,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 248,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 2,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(
                  width: 276,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFavoritesShimmer() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            height: 18,
            width: 180,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildRestaurantShimmers(),
      ],
    );
  }

  Widget _buildRestaurantCard(Restaurant restaurant) {
    final route = _routeInfo[restaurant.id];
    final hasRealRoute = route != null && !route.isFallback;
    final routeDistanceKm = hasRealRoute && route.distanceMeters != null
        ? route.distanceMeters! / 1000
        : null;
    final distanceKm = routeDistanceKm ?? _straightLineDistanceKm(restaurant);
    final routeMinutes = hasRealRoute && route.durationSeconds != null
        ? (route.durationSeconds! / 60).ceil()
        : null;
    final accentColor = restaurant.isOpen
        ? AppColors.primaryGreen
        : AppColors.primaryRed;
    final locationLabel = LocationDisplay.smartLocation(
      address: restaurant.address,
      neighborhood: restaurant.neighborhood,
      city: restaurant.city,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: DeligoPressable(
        onTap: () {
          debugPrint(
            '[HOME] restaurant card tapped id=${restaurant.id} name=${restaurant.name}',
          );
          GuardedNavigation.push(context, '/restaurant/${restaurant.id}');
        },
        borderRadius: BorderRadius.circular(22),
        splashColor: accentColor.withValues(alpha: 0.14),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.cleanWhite,
                accentColor.withValues(alpha: 0.035),
              ],
            ),
            border: Border.all(color: accentColor.withValues(alpha: 0.10)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: restaurant.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: restaurant.imageUrl!,
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    accentColor.withValues(alpha: 0.90),
                                    AppColors.primaryRed.withValues(
                                      alpha: 0.72,
                                    ),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.restaurant_rounded,
                                size: 30,
                                color: Colors.white,
                              ),
                            ),
                    ),
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          restaurant.isOpen
                              ? 'A pedir agora'
                              : 'Fecha por agora',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
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
                                  restaurant.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  locationLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.neutralGray,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildFavoriteButton(restaurant),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          _buildInfoChip(
                            Icons.star,
                            restaurant.rating?.toStringAsFixed(1) ?? 'Novo',
                            Colors.amber,
                          ),
                          if (routeMinutes != null)
                            _buildInfoChip(
                              Icons.access_time,
                              '${routeMinutes}-${routeMinutes + 5} min',
                              AppColors.primaryRed,
                            ),
                          _buildInfoChip(
                            Icons.delivery_dining,
                            '100-200 MZN',
                            AppColors.successGreen,
                          ),
                          _buildInfoChip(
                            restaurant.isOpen
                                ? Icons.storefront_rounded
                                : Icons.storefront_outlined,
                            restaurant.isOpen ? 'Aberto' : 'Fechado',
                            restaurant.isOpen
                                ? AppColors.successGreen
                                : AppColors.alertRed,
                          ),
                          if (distanceKm != null)
                            _buildInfoChip(
                              Icons.near_me,
                              _formatDistance(distanceKm),
                              AppColors.neutralGray,
                            ),
                          if (distanceKm == null)
                            _buildInfoChip(
                              Icons.sync_rounded,
                              'A calcular',
                              AppColors.neutralGray,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double? _straightLineDistanceKm(Restaurant restaurant) {
    final knownDistance = restaurant.distance;
    if (knownDistance != null && knownDistance.isFinite) {
      return knownDistance;
    }
    final originLat = _userLat;
    final originLng = _userLng;
    final destinationLat = restaurant.latitude;
    final destinationLng = restaurant.longitude;
    if (originLat == null ||
        originLng == null ||
        destinationLat == null ||
        destinationLng == null) {
      return null;
    }
    const earthRadiusKm = 6371.0;
    double radians(double value) => value * math.pi / 180;
    final dLat = radians(destinationLat - originLat);
    final dLng = radians(destinationLng - originLng);
    final lat1 = radians(originLat);
    final lat2 = radians(destinationLat);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String _formatDistance(double distanceKm) {
    if (distanceKm < 1) return '${(distanceKm * 1000).round()} m';
    if (distanceKm < 10) return '${distanceKm.toStringAsFixed(1)} km';
    return '${distanceKm.round()} km';
  }

  Widget _buildFavoriteButton(Restaurant restaurant) {
    final isFavorite = _favorites.contains(restaurant.id);
    return DeligoPressable(
      onTap: () => _toggleFavorite(restaurant),
      borderRadius: BorderRadius.circular(999),
      pressedScale: 0.90,
      splashColor: (isFavorite ? Colors.pink : AppColors.accentYellow)
          .withValues(alpha: 0.18),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (isFavorite ? Colors.pink : Colors.grey).withValues(
            alpha: 0.10,
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 18,
          color: isFavorite ? Colors.pink : AppColors.neutralGray,
        ),
      ),
    );
  }

  Widget _buildSmartNotifications() {
    if (_loadingSmartNotifications) {
      return _buildNotificationSkeleton(
        accent: const Color(0xFFFF7A45),
        title: 'A preparar sua inbox',
      );
    }
    if (_smartNotifications.isEmpty) {
      return _buildNotificationEmptyState(
        icon: Icons.local_shipping_rounded,
        accent: const Color(0xFFFF7A45),
        title: 'Sua central de pedidos esta pronta',
        body:
            'Quando houver novidades de pedidos, entregas, carteira ou chat, elas vao aparecer aqui com prioridade e acao rapida.',
      );
    }
    final visibleNotifications = _smartNotifications.where((n) {
      final id = n['id']?.toString() ?? '';
      if (_hiddenNotificationIds.contains(id)) return false;
      final createdAt = DateTime.tryParse(n['created_at']?.toString() ?? '');
      if (createdAt != null && _serverNow.difference(createdAt).inDays > 30) {
        return false;
      }
      if (_showOnlyUnreadNotifications && n['read_at'] != null) return false;
      if (_notificationTypeFilter != 'ALL' &&
          _notificationSection(n['type']?.toString()) !=
              _notificationTypeFilter) {
        return false;
      }
      final query = _notificationSearchQuery.trim().toLowerCase();
      if (query.isEmpty) return true;
      final haystack = [
        n['title']?.toString() ?? '',
        n['body']?.toString() ?? '',
        n['type']?.toString() ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    final orderedNotifications = List<Map<String, dynamic>>.from(
      visibleNotifications,
    )..sort(_sortNotifications);
    final groupedNotifications = _groupNotificationsByType(
      orderedNotifications,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Ultimas notificacoes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: _markAllNotificationsAsRead,
              child: const Text('Marcar todas como lidas'),
            ),
          ],
        ),
        Row(
          children: [
            FilterChip(
              label: const Text('So nao lidas'),
              selected: _showOnlyUnreadNotifications,
              onSelected: (value) {
                setState(() => _showOnlyUnreadNotifications = value);
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          onChanged: (value) {
            setState(() => _notificationSearchQuery = value);
          },
          decoration: InputDecoration(
            hintText: 'Buscar nas notificacoes',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('Todos'),
                selected: _notificationTypeFilter == 'ALL',
                onSelected: (_) {
                  setState(() => _notificationTypeFilter = 'ALL');
                },
              ),
              const SizedBox(width: 8),
              ...['Pedidos', 'Mensagens', 'Conta'].map(
                (type) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(type),
                    selected: _notificationTypeFilter == type,
                    onSelected: (_) {
                      setState(() => _notificationTypeFilter = type);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (visibleNotifications.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Nao ha notificacoes nao lidas agora.',
              style: TextStyle(color: AppColors.neutralGray),
            ),
          ),
        ...groupedNotifications.entries.expand(
          (entry) => [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _collapsedNotificationSections[entry.key] =
                      !(_collapsedNotificationSections[entry.key] ?? false);
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: _sectionColor(
                        entry.key,
                      ).withValues(alpha: 0.14),
                      child: Icon(
                        _sectionIcon(entry.key),
                        size: 16,
                        color: _sectionColor(entry.key),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${entry.key} (${entry.value.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _sectionColor(entry.key),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _markSectionAsRead(entry.value),
                      child: const Text('Ler secao'),
                    ),
                    if (entry.value.any((n) => n['read_at'] == null))
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${entry.value.where((n) => n["read_at"] == null).length} novas',
                          style: const TextStyle(
                            color: AppColors.primaryRed,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    Icon(
                      (_collapsedNotificationSections[entry.key] ?? false)
                          ? Icons.expand_more
                          : Icons.expand_less,
                      color: AppColors.neutralGray,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: entry.value.map((n) {
                  final isUnread = n['read_at'] == null;
                  return Dismissible(
                    key: ValueKey('client-notification-${n['id']}'),
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.successGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.mark_email_read_rounded,
                            color: AppColors.successGreen,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Marcar como lida',
                            style: TextStyle(
                              color: AppColors.successGreen,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    secondaryBackground: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Esconder',
                            style: TextStyle(
                              color: Colors.blueGrey,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.visibility_off_rounded,
                            color: Colors.blueGrey,
                          ),
                        ],
                      ),
                    ),
                    onDismissed: (direction) async {
                      if (direction == DismissDirection.startToEnd) {
                        await _markNotificationAsRead(
                          n['id']?.toString() ?? '',
                        );
                      } else {
                        _hideNotificationWithUndo(
                          context,
                          n['id']?.toString() ?? '',
                          n['title']?.toString() ?? 'Notificacao',
                        );
                      }
                    },
                    child: Card(
                      elevation: 0,
                      color: Colors.transparent,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isUnread ? Colors.white : Colors.grey.shade50,
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _notificationColor(
                              n,
                            ).withValues(alpha: 0.12),
                            child: Icon(
                              _notificationIcon(n),
                              color: _notificationColor(n),
                              size: 20,
                            ),
                          ),
                          title: _buildHighlightedText(
                            n['title']?.toString() ?? 'Notificacao',
                            _notificationSearchQuery,
                            TextStyle(
                              fontWeight: isUnread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHighlightedText(
                                n['body']?.toString() ?? '',
                                _notificationSearchQuery,
                                const TextStyle(color: Colors.black87),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatNotificationDate(n['created_at']),
                                style: const TextStyle(
                                  color: Colors.black45,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          trailing: SizedBox(
                            width: 76,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isUnread)
                                  AnimatedScale(
                                    duration: const Duration(milliseconds: 180),
                                    scale: isUnread ? 1 : 0.8,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primaryRed,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          onTap: () async {
                            await NotificationRouterService()
                                .handleStoredNotificationTap(n);
                            await _loadSmartNotifications();
                          },
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              crossFadeState:
                  (_collapsedNotificationSections[entry.key] ?? false)
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
            ),
          ],
        ),
      ],
    );
  }

  int _sortNotifications(Map<String, dynamic> a, Map<String, dynamic> b) {
    final unreadA = a['read_at'] == null ? 0 : 1;
    final unreadB = b['read_at'] == null ? 0 : 1;
    if (unreadA != unreadB) return unreadA.compareTo(unreadB);
    final createdAtA = DateTime.tryParse(a['created_at']?.toString() ?? '');
    final createdAtB = DateTime.tryParse(b['created_at']?.toString() ?? '');
    if (createdAtA == null && createdAtB == null) return 0;
    if (createdAtA == null) return 1;
    if (createdAtB == null) return -1;
    return createdAtB.compareTo(createdAtA);
  }

  String _formatNotificationDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final now = DateTime.now();
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    if (now.year == date.year &&
        now.month == date.month &&
        now.day == date.day) {
      return 'Hoje, $hh:$mm';
    }
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} $hh:$mm';
  }

  Map<String, List<Map<String, dynamic>>> _groupNotificationsByType(
    List<Map<String, dynamic>> notifications,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final notification in notifications) {
      final section = _notificationSection(notification['type']?.toString());
      grouped.putIfAbsent(section, () => []).add(notification);
    }
    return grouped;
  }

  String _notificationSection(String? type) {
    switch (NotificationTypeUtils.canonicalize(type)) {
      case 'PAYMENT_CONFIRMED':
      case 'PAYMENT_FAILED':
      case 'ORDER_ACCEPTED':
      case 'ORDER_PREPARING':
      case 'ORDER_READY':
      case 'ORDER_PICKED_UP':
      case 'ORDER_DELIVERED':
      case 'ORDER_AUTO_COMPLETED':
      case 'DELIVERY_EXTENSION_REQUESTED':
      case 'ORDER_DELAYED':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_ARRIVED':
      case 'ORDER_REJECTED':
        return 'Pedidos';
      case 'MESSAGE_RECEIVED':
      case 'SUPPORT_UPDATED':
      case 'TICKET_RESOLVED':
        return 'Mensagens';
      case 'REFUND_STARTED':
      case 'REFUND_COMPLETED':
      case 'CASHBACK_RECEIVED':
      case 'EMAIL_CONFIRMATION_REQUIRED':
      case 'SESSION_EXPIRED':
      case 'PUSH_DISABLED':
        return 'Conta';
      case 'PROMO_OFFER':
      case 'FREE_DELIVERY_PROMO':
      case 'RETENTION_REMINDER':
        return 'Promocoes';
      default:
        return 'Geral';
    }
  }

  Widget _buildPriorityChip(String priority) {
    return _buildInfoChip(
      priority == 'HIGH'
          ? Icons.priority_high
          : priority == 'LOW'
          ? Icons.low_priority
          : Icons.tune,
      priority,
      _priorityColor(priority),
    );
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'HIGH':
        return Colors.redAccent;
      case 'LOW':
        return Colors.blueGrey;
      case 'MEDIUM':
      default:
        return Colors.orange;
    }
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSkeleton({
    required Color accent,
    required String title,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, accent.withValues(alpha: 0.06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: accent.withValues(alpha: 0.14),
                child: Icon(Icons.notifications_active_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: accent,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Shimmer.fromColors(
                baseColor: Colors.grey.shade200,
                highlightColor: Colors.grey.shade100,
                child: Container(
                  height: 82,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationEmptyState({
    required IconData icon,
    required Color accent,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, accent.withValues(alpha: 0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: accent.withValues(alpha: 0.14),
            child: Icon(icon, size: 30, color: accent),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.neutralGray, height: 1.4),
          ),
        ],
      ),
    );
  }

  Color _sectionColor(String section) {
    switch (section) {
      case 'Pedidos':
        return AppColors.primaryRed;
      case 'Carteira':
        return AppColors.successGreen;
      case 'Chat':
        return Colors.indigo;
      case 'Suporte':
        return Colors.teal;
      case 'Conta':
        return Colors.blueGrey;
      case 'Promocoes':
      default:
        return AppColors.neutralGray;
    }
  }

  IconData _sectionIcon(String section) {
    switch (section) {
      case 'Pedidos':
        return Icons.receipt_long_rounded;
      case 'Carteira':
        return Icons.account_balance_wallet_rounded;
      case 'Chat':
        return Icons.chat_bubble_outline_rounded;
      case 'Suporte':
        return Icons.support_agent_rounded;
      case 'Conta':
        return Icons.settings_outlined;
      case 'Promocoes':
      default:
        return Icons.notifications_none_rounded;
    }
  }

  IconData _notificationIcon(Map<String, dynamic> notification) {
    switch (NotificationTypeUtils.canonicalize(
      notification['type']?.toString(),
    )) {
      case 'PAYMENT_CONFIRMED':
        return Icons.payments_rounded;
      case 'PAYMENT_FAILED':
        return Icons.error_outline_rounded;
      case 'ORDER_REJECTED':
        return Icons.cancel_outlined;
      case 'ORDER_ACCEPTED':
      case 'ORDER_PREPARING':
      case 'ORDER_READY':
        return Icons.receipt_long_rounded;
      case 'ORDER_PICKED_UP':
        return Icons.delivery_dining_rounded;
      case 'DELIVERY_EXTENSION_REQUESTED':
        return Icons.more_time_rounded;
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_ARRIVED':
        return Icons.delivery_dining_rounded;
      case 'ORDER_DELIVERED':
        return Icons.verified_rounded;
      case 'ORDER_AUTO_COMPLETED':
        return Icons.task_alt_rounded;
      case 'MESSAGE_RECEIVED':
        return Icons.chat_bubble_outline_rounded;
      case 'REFUND_COMPLETED':
      case 'CASHBACK_RECEIVED':
        return Icons.account_balance_wallet_rounded;
      case 'REFUND_STARTED':
        return Icons.hourglass_bottom_rounded;
      case 'ORDER_DELAYED':
        return Icons.warning_amber_rounded;
      case 'EMAIL_CONFIRMATION_REQUIRED':
        return Icons.mark_email_unread_outlined;
      case 'SESSION_EXPIRED':
        return Icons.lock_clock_outlined;
      case 'SUPPORT_UPDATED':
      case 'TICKET_RESOLVED':
        return Icons.support_agent_rounded;
      case 'PUSH_DISABLED':
        return Icons.notifications_off_outlined;
      case 'PROMO_OFFER':
        return Icons.local_offer_outlined;
      case 'FREE_DELIVERY_PROMO':
        return Icons.delivery_dining_outlined;
      case 'RETENTION_REMINDER':
        return Icons.favorite_border_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color _notificationColor(Map<String, dynamic> notification) {
    switch (NotificationTypeUtils.canonicalize(
      notification['type']?.toString(),
    )) {
      case 'PAYMENT_CONFIRMED':
      case 'REFUND_COMPLETED':
      case 'CASHBACK_RECEIVED':
        return AppColors.successGreen;
      case 'PAYMENT_FAILED':
        return AppColors.alertRed;
      case 'ORDER_REJECTED':
        return Colors.redAccent;
      case 'ORDER_DELAYED':
        return Colors.deepOrange;
      case 'REFUND_STARTED':
        return Colors.orange;
      case 'ORDER_ACCEPTED':
      case 'ORDER_PREPARING':
      case 'ORDER_READY':
        return AppColors.primaryRed;
      case 'ORDER_PICKED_UP':
      case 'DRIVER_ASSIGNED':
      case 'DRIVER_ARRIVED':
        return Colors.indigo;
      case 'ORDER_DELIVERED':
      case 'ORDER_AUTO_COMPLETED':
        return AppColors.successGreen;
      case 'DELIVERY_EXTENSION_REQUESTED':
        return Colors.orangeAccent;
      case 'MESSAGE_RECEIVED':
        return Colors.deepPurple;
      case 'EMAIL_CONFIRMATION_REQUIRED':
        return Colors.blueGrey;
      case 'SESSION_EXPIRED':
        return Colors.redAccent;
      case 'SUPPORT_UPDATED':
        return Colors.teal;
      case 'TICKET_RESOLVED':
        return AppColors.successGreen;
      case 'PUSH_DISABLED':
        return Colors.amber.shade800;
      case 'PROMO_OFFER':
        return Colors.pinkAccent;
      case 'FREE_DELIVERY_PROMO':
        return Colors.blueAccent;
      case 'RETENTION_REMINDER':
        return Colors.deepPurpleAccent;
      default:
        return AppColors.neutralGray;
    }
  }

  Widget _buildHighlightedText(String text, String query, TextStyle style) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return Text(text, style: style);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = normalizedQuery.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + normalizedQuery.length),
          style: style.copyWith(
            backgroundColor: Colors.amberAccent.withValues(alpha: 0.45),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      start = index + normalizedQuery.length;
    }
    return RichText(
      text: TextSpan(style: style, children: spans),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
