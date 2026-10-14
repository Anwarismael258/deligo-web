import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_env.dart';
import '../../config/theme/app_colors.dart';
import '../../services/delivery_service.dart';
import '../../services/notification_dispatch_service.dart';
import '../../services/notification_router_service.dart';
import '../../services/order_service.dart';
import '../../services/sound_controller.dart';
import 'admin_document_viewer_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final NotificationDispatchService _notificationDispatch =
      NotificationDispatchService.instance;
  final OrderService _orderService = OrderService();
  final DeliveryService _deliveryService = DeliveryService();
  final TextEditingController _searchController = TextEditingController();
  final List<RealtimeChannel> _realtimeChannels = <RealtimeChannel>[];

  bool _isLoading = true;
  bool _isProcessingDecision = false;
  int _tabIndex = 0;
  String _userFilter = 'all';
  String _kycFilter = 'pending';
  String _kycRoleFilter = 'all';
  String _searchQuery = '';
  int _reportPeriodDays = 30;
  int _visibleUsers = 20;
  int _visibleKyc = 20;
  int _visibleNotifications = 20;
  int _visibleActions = 20;
  int _visibleDeletionRequests = 20;
  int _visibleDisputes = 20;
  int _visibleFailedOtpOrders = 20;
  String _disputeRoleFilter = 'all';
  String? _currentUserId;
  String? _processingUserId;

  static const Map<String, String> _kycLabelOverrides = {
    'foto_loja': 'Foto da loja',
    'foto_nuit': 'Foto do NUIT',
    'foto_interior': 'Foto do interior',
    'bi_frente': 'BI frente',
    'bi_tras': 'BI verso',
    'selfie': 'Selfie com rosto visivel',
    'foto': 'Foto do estafeta',
    'foto_veiculo': 'Foto do veiculo',
    'foto_matricula': 'Foto da matricula/placa',
    'carta_conducao': 'Carta de conducao',
    'documento_veiculo': 'Documento do veiculo',
    'selfie_veiculo': 'Foto do estafeta com o veiculo',
  };

  String _kycLabel(String raw) {
    final key = raw.trim();
    if (key.isEmpty) return 'Documento';
    return _kycLabelOverrides[key] ?? key;
  }

  List<Map<String, dynamic>> _profiles = const [];
  List<Map<String, dynamic>> _notifications = const [];
  List<Map<String, dynamic>> _dispatchTimeline = const [];
  List<Map<String, dynamic>> _dispatchWebhooks = const [];
  List<Map<String, dynamic>> _accountDeletionRequests = const [];
  List<Map<String, dynamic>> _orderDisputes = const [];
  List<Map<String, dynamic>> _adminActions = const [];
  List<Map<String, dynamic>> _fieldStaffInvites = const [];
  List<Map<String, dynamic>> _recentOrders = const [];
  List<Map<String, dynamic>> _failedOtpOrders = const [];
  List<Map<String, dynamic>> _courierOtpRiskMetrics = const [];
  Map<String, dynamic> _otpOverrideSummary = const <String, dynamic>{};
  Map<String, dynamic> _dispatchHealth = const <String, dynamic>{};
  Map<String, Map<String, dynamic>> _walletsByUserId =
      const <String, Map<String, dynamic>>{};
  Timer? _refreshDebounce;

  List<Map<String, dynamic>> get _filteredDisputes {
    if (_disputeRoleFilter == 'all') return _orderDisputes;
    return _orderDisputes
        .where(
          (row) =>
              row['opened_by_role']?.toString().toLowerCase() ==
              _disputeRoleFilter,
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadDashboard());
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    for (final channel in _realtimeChannels) {
      _supabase.removeChannel(channel);
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _currentUserId = null;
      });
      return;
    }

    try {
      if (mounted) {
        setState(() => _isLoading = true);
      }

      final profiles = await _withRetry<List<Map<String, dynamic>>>(
        _fetchProfiles,
        fallback: const <Map<String, dynamic>>[],
      );
      final wallets = await _withRetry<List<Map<String, dynamic>>>(
        _loadWalletRows,
        fallback: const <Map<String, dynamic>>[],
      );
      final notifications = await _withRetry<List<Map<String, dynamic>>>(
        () => _fetchAdminNotifications(user.id),
        fallback: const <Map<String, dynamic>>[],
      );
      final dispatchObservability = await _withRetry<Map<String, dynamic>>(
        _fetchDispatchObservability,
        fallback: const <String, dynamic>{},
      );
      final adminActions = await _withRetry<List<Map<String, dynamic>>>(
        _fetchAdminActions,
        fallback: const <Map<String, dynamic>>[],
      );
      final fieldStaffInvites = await _withRetry<List<Map<String, dynamic>>>(
        _fetchFieldStaffInvites,
        fallback: const <Map<String, dynamic>>[],
      );
      final accountDeletionRequests =
          await _withRetry<List<Map<String, dynamic>>>(
            _fetchAccountDeletionRequests,
            fallback: const <Map<String, dynamic>>[],
          );
      final orderDisputes = await _withRetry<List<Map<String, dynamic>>>(
        _fetchOrderDisputes,
        fallback: const <Map<String, dynamic>>[],
      );
      final recentOrders = await _withRetry<List<Map<String, dynamic>>>(
        _fetchRecentOrders,
        fallback: const <Map<String, dynamic>>[],
      );
      final failedOtpOrders = await _withRetry<List<Map<String, dynamic>>>(
        _fetchFailedOtpOrders,
        fallback: const <Map<String, dynamic>>[],
      );
      final courierOtpRiskMetrics =
          await _withRetry<List<Map<String, dynamic>>>(
            _fetchCourierOtpRiskMetrics,
            fallback: const <Map<String, dynamic>>[],
          );
      final otpOverrideSummary = await _withRetry<Map<String, dynamic>>(
        _fetchOtpOverrideSummary,
        fallback: const <String, dynamic>{},
      );
      final walletMap = <String, Map<String, dynamic>>{};
      for (final wallet in wallets) {
        final userId = wallet['user_id']?.toString();
        if (userId == null || userId.isEmpty) continue;
        walletMap[userId] = wallet;
      }

      if (!mounted) return;
      setState(() {
        _currentUserId = user.id;
        _profiles = profiles;
        _walletsByUserId = walletMap;
        _notifications = notifications;
        _dispatchHealth = Map<String, dynamic>.from(
          (dispatchObservability['health'] as Map?) ??
              const <String, dynamic>{},
        );
        _dispatchTimeline =
            ((dispatchObservability['jobs'] as List?) ?? const [])
                .cast<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList();
        _dispatchWebhooks =
            ((dispatchObservability['webhooks'] as List?) ?? const [])
                .cast<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList();
        _accountDeletionRequests = accountDeletionRequests;
        _orderDisputes = orderDisputes;
        _adminActions = adminActions;
        _fieldStaffInvites = fieldStaffInvites;
        _recentOrders = recentOrders;
        _failedOtpOrders = failedOtpOrders;
        _courierOtpRiskMetrics = courierOtpRiskMetrics;
        _otpOverrideSummary = otpOverrideSummary;
        _isLoading = false;
      });
      await _ensureRealtime();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nao foi possivel carregar o app admin: $error'),
        ),
      );
    }
  }

  Future<T> _withRetry<T>(
    Future<T> Function() action, {
    required T fallback,
    int attempts = 3,
  }) async {
    for (var index = 0; index < attempts; index++) {
      try {
        return await action().timeout(const Duration(seconds: 20));
      } catch (_) {
        if (index == attempts - 1) {
          return fallback;
        }
        await Future<void>.delayed(Duration(milliseconds: 600 * (index + 1)));
      }
    }
    return fallback;
  }

  Future<List<Map<String, dynamic>>> _fetchProfiles() async {
    final result = await _supabase
        .from('profiles')
        .select(
          'id, full_name, phone, role, kyc_status, kyc_rejection_reason, '
          'kyc_docs, approval_submitted_at, approval_sla_deadline, block_reason, '
          'verification_score, is_blocked, created_at, updated_at',
        )
        .order('updated_at', ascending: false)
        .limit(500);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchAdminNotifications(
    String userId,
  ) async {
    final result = await _supabase
        .from('push_notifications')
        .select(
          'id, user_id, title, body, type, action, entity_id, priority, channel, metadata, created_at, read_at',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<Map<String, dynamic>> _fetchDispatchObservability() async {
    final response = await _invokeFunctionDirect(
      'dispatch-observability',
      body: {'limit': 12},
    );
    if (response.status < 200 || response.status >= 300) {
      return const <String, dynamic>{};
    }
    return Map<String, dynamic>.from(
      (response.json['data'] as Map?) ?? const <String, dynamic>{},
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAdminActions() async {
    final result = await _supabase
        .from('admin_actions_log')
        .select('id, admin_id, user_id, action, reason, metadata, created_at')
        .order('created_at', ascending: false)
        .limit(100);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchFieldStaffInvites() async {
    final result = await _supabase
        .from('field_staff_invites')
        .select(
          'id, full_name, phone, role, city, access_level, active, invited_by, '
          'invited_at, accepted_by, accepted_at',
        )
        .order('invited_at', ascending: false)
        .limit(100);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchAccountDeletionRequests() async {
    final result = await _supabase
        .from('account_deletion_requests')
        .select(
          'id, user_id, email, role, status, reason, source, requested_at, '
          'processed_at, metadata',
        )
        .order('requested_at', ascending: false)
        .limit(100);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchRecentOrders() async {
    final result = await _supabase
        .from('orders')
        .select(
          'id, total_amount, delivery_fee, platform_fee, payment_status, '
          'payment_method, status, created_at, updated_at, delivery_address, '
          'client_id, customer_id, restaurant_id, courier_id',
        )
        .order('created_at', ascending: false)
        .limit(50);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadWalletRows() async {
    try {
      final result = await _supabase
          .from('wallets')
          .select(
            'user_id, balance, available_balance, pending_balance, currency',
          );
      return (result as List)
          .cast<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      final result = await _supabase
          .from('wallets')
          .select('user_id, balance, currency');
      return (result as List)
          .cast<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    }
  }

  List<Map<String, dynamic>> get _clients {
    return _profiles.where((profile) {
      final role = profile['role']?.toString() ?? '';
      return role == 'client' || role == 'customer';
    }).toList();
  }

  List<Map<String, dynamic>> get _kycProfiles {
    return _profiles.where((profile) {
      final query = _searchQuery.trim().toLowerCase();
      if (query.isNotEmpty) {
        final name = profile['full_name']?.toString().toLowerCase() ?? '';
        final phone = profile['phone']?.toString().toLowerCase() ?? '';
        final roleText = profile['role']?.toString().toLowerCase() ?? '';
        if (!name.contains(query) &&
            !phone.contains(query) &&
            !roleText.contains(query)) {
          return false;
        }
      }
      final role = profile['role']?.toString() ?? '';
      if (role != 'courier' && role != 'restaurant') return false;
      if (_kycRoleFilter != 'all' && role != _kycRoleFilter) return false;
      final status = profile['kyc_status']?.toString() ?? 'pending';
      switch (_kycFilter) {
        case 'approved':
          return status == 'approved';
        case 'rejected':
          return status == 'rejected';
        case 'all':
          return true;
        case 'pending':
        default:
          return status == 'pending' && _hasKycDocuments(profile);
      }
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchOrderDisputes() async {
    final result = await _supabase
        .from('order_disputes')
        .select(
          'id, order_id, opened_by, opened_by_role, dispute_type, reason, status, created_at, '
          'orders(status, total_amount, restaurant_id)',
        )
        .order('created_at', ascending: false)
        .limit(100);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchFailedOtpOrders() async {
    final result = await _supabase
        .from('orders')
        .select(
          'id, total_amount, status, created_at, updated_at, delivery_address, '
          'client_id, customer_id, courier_id, restaurant_id',
        )
        .eq('status', 'delivery_failed_otp')
        .order('updated_at', ascending: false)
        .limit(100);
    return (result as List)
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<Map<String, dynamic>> _fetchOtpOverrideSummary() async {
    final result = await _supabase.rpc('get_delivery_otp_override_summary');
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return const <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> _fetchCourierOtpRiskMetrics() async {
    final result = await _supabase.rpc(
      'get_courier_delivery_otp_risk_metrics',
      params: {'p_limit': 8},
    );
    if (result is! List) return const <Map<String, dynamic>>[];
    return result
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _profiles.where((profile) {
      final query = _searchQuery.trim().toLowerCase();
      if (query.isNotEmpty) {
        final name = profile['full_name']?.toString().toLowerCase() ?? '';
        final phone = profile['phone']?.toString().toLowerCase() ?? '';
        final roleText = profile['role']?.toString().toLowerCase() ?? '';
        if (!name.contains(query) &&
            !phone.contains(query) &&
            !roleText.contains(query)) {
          return false;
        }
      }
      switch (_userFilter) {
        case 'clients':
          final role = profile['role']?.toString() ?? '';
          return role == 'client' || role == 'customer';
        case 'couriers':
          return profile['role'] == 'courier';
        case 'restaurants':
          return profile['role'] == 'restaurant';
        case 'admins':
          return profile['role'] == 'admin';
        case 'all':
        default:
          return true;
      }
    }).toList();
  }

  List<Map<String, dynamic>> get _visibleAccountDeletionRequests {
    return _accountDeletionRequests.where((request) {
      final email = request['email']?.toString().trim().toLowerCase() ?? '';
      return email.isEmpty || !email.endsWith('@example.com');
    }).toList();
  }

  bool _hasKycDocuments(Map<String, dynamic> profile) {
    return profile['kyc_docs'] is Map &&
        (profile['kyc_docs'] as Map).isNotEmpty;
  }

  bool _isActionableKycProfile(Map<String, dynamic> profile) {
    final role = profile['role']?.toString() ?? '';
    final status = profile['kyc_status']?.toString() ?? 'pending';
    if (role != 'courier' && role != 'restaurant') return false;
    if (status != 'pending') return false;
    return _hasKycDocuments(profile);
  }

  void _applySearch(String rawValue, {int? tabIndex}) {
    final value = rawValue.trim();
    _searchController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    setState(() {
      _searchQuery = value;
      if (tabIndex != null) {
        _tabIndex = tabIndex;
      }
    });
  }

  double _walletAmount(
    Map<String, dynamic>? wallet, {
    String field = 'balance',
  }) {
    if (wallet == null) return 0;
    return (wallet[field] as num?)?.toDouble() ??
        (wallet['balance'] as num?)?.toDouble() ??
        0;
  }

  double get _totalWalletBalance {
    return _walletsByUserId.values.fold<double>(
      0,
      (sum, wallet) => sum + _walletAmount(wallet),
    );
  }

  Map<String, dynamic>? get _adminWallet {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return null;
    return _walletsByUserId[currentUserId];
  }

  double get _adminAvailableBalance {
    return _walletAmount(
      _adminWallet,
      field: _adminWallet?['available_balance'] != null
          ? 'available_balance'
          : 'balance',
    );
  }

  int get _pendingKycCount {
    return _profiles.where(_isActionableKycProfile).length;
  }

  int get _pendingFieldInvitesCount {
    return _fieldStaffInvites.where((invite) {
      return invite['accepted_at'] == null && invite['active'] != false;
    }).length;
  }

  int get _unreadNotificationsCount {
    return _notifications.where((row) => row['read_at'] == null).length;
  }

  int get _pendingDeletionRequestsCount {
    return _visibleAccountDeletionRequests.where((row) {
      final status = row['status']?.toString().toLowerCase() ?? 'pending';
      return status == 'pending';
    }).length;
  }

  int get _approvedKycCount {
    return _profiles.where((profile) {
      final role = profile['role']?.toString() ?? '';
      final status = profile['kyc_status']?.toString() ?? 'pending';
      return (role == 'courier' || role == 'restaurant') &&
          status == 'approved';
    }).length;
  }

  int get _rejectedKycCount {
    return _profiles.where((profile) {
      final role = profile['role']?.toString() ?? '';
      final status = profile['kyc_status']?.toString() ?? 'pending';
      return (role == 'courier' || role == 'restaurant') &&
          status == 'rejected';
    }).length;
  }

  int _countByRole(String role) {
    return _profiles.where((profile) => profile['role'] == role).length;
  }

  int get _clientsCount => _countByRole('client') + _countByRole('customer');

  int get _couriersCount => _countByRole('courier');

  int get _restaurantsCount => _countByRole('restaurant');

  int get _adminsCount => _countByRole('admin');

  int get _fieldStaffCount {
    const roles = {
      'field_agent',
      'support_agent',
      'ambassador',
      'marketing_agent',
    };
    return _profiles.where((profile) {
      return roles.contains(profile['role']?.toString());
    }).length;
  }

  List<Map<String, dynamic>> get _walletDivergences {
    return const <Map<String, dynamic>>[];
  }

  int get _activeClientsCount {
    return _profiles.where((profile) {
      final role = profile['role']?.toString() ?? '';
      final blocked = profile['is_blocked'] == true;
      return !blocked && (role == 'client' || role == 'customer');
    }).length;
  }

  int get _otpFailedTodayCount =>
      (_otpOverrideSummary['otp_failed_today'] as num?)?.toInt() ?? 0;

  int get _otpOverridesTodayCount =>
      (_otpOverrideSummary['overrides_today'] as num?)?.toInt() ?? 0;

  int get _otpCouriersWithOverrideToday =>
      (_otpOverrideSummary['couriers_with_override_today'] as num?)?.toInt() ??
      0;

  int get _otpDisputedTodayCount =>
      (_otpOverrideSummary['disputed_overrides_today'] as num?)?.toInt() ?? 0;

  double get _topCourierOtpFailureRate {
    if (_courierOtpRiskMetrics.isEmpty) return 0;
    return _courierOtpRiskMetrics.fold<double>(0, (best, row) {
      final rate = (row['otp_failure_rate_30d'] as num?)?.toDouble() ?? 0;
      return rate > best ? rate : best;
    });
  }

  double _metric(String key) => 0;

  double get _selectedPeriodGmv =>
      _reportPeriodDays == 7 ? _metric('gmv_7') : _metric('gmv_30');

  double get _selectedPeriodFees =>
      _reportPeriodDays == 7 ? _metric('fees_7') : _metric('fees_30');

  double get _selectedPeriodDelivery =>
      _reportPeriodDays == 7 ? _metric('delivery_7') : _metric('delivery_30');

  double get _selectedPeriodOrders =>
      _reportPeriodDays == 7 ? _metric('orders_7') : _metric('orders_30');

  Future<void> _refresh() => _loadDashboard();

  Future<void> _logout() async {
    try {
      await _supabase.auth.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel sair agora: $error')),
      );
    }
  }

  Future<void> _ensureRealtime() async {
    if (_realtimeChannels.isNotEmpty) return;

    void scheduleRefresh() {
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(const Duration(milliseconds: 800), () {
        if (mounted) {
          unawaited(_loadDashboard());
        }
      });
    }

    final specs = <({String name, String schema, String table})>[
      (name: 'admin-profiles', schema: 'public', table: 'profiles'),
      (name: 'admin-wallets', schema: 'public', table: 'wallets'),
      (name: 'admin-push', schema: 'public', table: 'push_notifications'),
      (name: 'admin-actions', schema: 'public', table: 'admin_actions_log'),
      (name: 'admin-orders', schema: 'public', table: 'orders'),
      (
        name: 'admin-account-deletion',
        schema: 'public',
        table: 'account_deletion_requests',
      ),
      (name: 'admin-disputes', schema: 'public', table: 'order_disputes'),
      (name: 'admin-support-cases', schema: 'core', table: 'support_cases'),
      (
        name: 'admin-support-messages',
        schema: 'core',
        table: 'support_case_messages',
      ),
    ];

    for (final spec in specs) {
      final channel = _supabase
          .channel(spec.name)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: spec.schema,
            table: spec.table,
            callback: (payload) async {
              if (spec.table == 'push_notifications' &&
                  payload.eventType == PostgresChangeEvent.insert) {
                final row = Map<String, dynamic>.from(payload.newRecord);
                final channel = row['channel']?.toString() ?? '';
                final type = row['type']?.toString() ?? '';
                if (channel == 'admin_kyc' ||
                    type == 'KYC_SUBMITTED' ||
                    type == 'SUPPORT_MESSAGE_RECEIVED') {
                  await SoundController.instance.notification();
                }
              }
              scheduleRefresh();
            },
          )
          .subscribe();
      _realtimeChannels.add(channel);
    }
  }

  Future<void> _markNotificationAsRead(String notificationId) async {
    if (notificationId.trim().isEmpty) return;
    try {
      await _supabase
          .from('push_notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('id', notificationId);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications.map((notification) {
          if (notification['id']?.toString() == notificationId) {
            return {
              ...notification,
              'read_at': DateTime.now().toIso8601String(),
            };
          }
          return notification;
        }).toList();
      });
    } catch (_) {}
  }

  Future<void> _handleAdminNotificationTap(
    Map<String, dynamic> notification,
  ) async {
    final metadata =
        (notification['metadata'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final orderId =
        notification['entity_id']?.toString() ??
        metadata['order_id']?.toString() ??
        '';
    final notificationId = notification['id']?.toString() ?? '';
    final deliveryStatus = metadata['status']?.toString();

    if (deliveryStatus == 'delivery_failed_otp' && orderId.isNotEmpty) {
      if (notification['read_at'] == null && notificationId.isNotEmpty) {
        await _markNotificationAsRead(notificationId);
      }
      if (!mounted) return;
      await _showResolveFailedOtpDialog({'id': orderId, ...metadata});
      return;
    }

    await NotificationRouterService().handleStoredNotificationTap(notification);
  }

  Future<void> _markAllNotificationsAsRead() async {
    final unreadIds = _notifications
        .where((notification) => notification['read_at'] == null)
        .map((notification) => notification['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (unreadIds.isEmpty) return;

    try {
      await _supabase
          .from('push_notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .inFilter('id', unreadIds);
      if (!mounted) return;
      setState(() {
        _notifications = _notifications.map((notification) {
          return {...notification, 'read_at': DateTime.now().toIso8601String()};
        }).toList();
      });
    } catch (_) {}
  }

  Future<void> _decideKyc({
    required Map<String, dynamic> profile,
    required String decision,
    String? reason,
  }) async {
    final userId = profile['id']?.toString();
    final role = profile['role']?.toString();
    final adminId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty || role == null || role.isEmpty) {
      return;
    }

    setState(() {
      _isProcessingDecision = true;
      _processingUserId = userId;
    });

    try {
      final response = await _invokeFunctionDirect(
        'approve_kyc',
        body: {
          if (adminId != null && adminId.isNotEmpty) 'admin_id': adminId,
          'user_id': userId,
          'subject_type': role,
          'decision': decision,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );

      if (response.status >= 400) {
        throw Exception(
          response.json['error']?.toString() ?? response.json.toString(),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'approve'
                ? 'KYC aprovado com sucesso.'
                : 'KYC rejeitado com sucesso.',
          ),
        ),
      );
      await _loadDashboard();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao atualizar KYC: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingDecision = false;
          _processingUserId = null;
        });
      }
    }
  }

  Future<void> _showRejectDialog(Map<String, dynamic> profile) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rejeitar KYC'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Motivo da rejeicao',
              hintText: 'Explique o que precisa ser corrigido.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Rejeitar'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _decideKyc(
        profile: profile,
        decision: 'reject',
        reason: controller.text,
      );
    }
    controller.dispose();
  }

  Future<void> _toggleUserSuspension({
    required Map<String, dynamic> profile,
    required bool suspend,
    String? reason,
  }) async {
    final userId = profile['id']?.toString();
    final role = profile['role']?.toString() ?? '';
    if (userId == null || userId.isEmpty) return;

    setState(() {
      _isProcessingDecision = true;
      _processingUserId = userId;
    });

    try {
      final timestamp = DateTime.now().toIso8601String();
      final payload = <String, dynamic>{
        'is_blocked': suspend,
        'block_reason': suspend
            ? (reason?.trim().isNotEmpty == true
                  ? reason!.trim()
                  : 'Conta suspensa pelo admin.')
            : null,
        'updated_at': timestamp,
      };

      await _supabase.from('profiles').update(payload).eq('id', userId);

      if (role == 'courier') {
        await _supabase
            .from('couriers')
            .update({
              'is_suspended': suspend,
              'suspension_reason': suspend
                  ? (reason?.trim().isNotEmpty == true
                        ? reason!.trim()
                        : 'Conta suspensa pelo admin.')
                  : null,
              'suspension_until': null,
            })
            .eq('id', userId);
      }

      if (_currentUserId != null && _currentUserId!.isNotEmpty) {
        await _supabase.from('admin_actions_log').insert({
          'admin_id': _currentUserId,
          'user_id': userId,
          'action': suspend ? 'user_suspended' : 'user_unsuspended',
          'reason': reason?.trim().isNotEmpty == true
              ? reason!.trim()
              : (suspend
                    ? 'Suspensao manual via painel admin.'
                    : 'Reativacao manual via painel admin.'),
          'metadata': {'role': role, 'source': 'admin_dashboard'},
        });
      }

      final trimmedReason = reason?.trim() ?? '';
      await _notificationDispatch.sendToUser(
        userId: userId,
        type: suspend ? 'account_blocked' : 'account_unblocked',
        title: suspend ? 'Conta suspensa' : 'Conta reativada',
        body: suspend
            ? (trimmedReason.isNotEmpty
                  ? 'A sua conta foi suspensa: $trimmedReason'
                  : 'A sua conta foi suspensa pela equipa DeliGo.')
            : (trimmedReason.isNotEmpty
                  ? 'A sua conta foi reativada: $trimmedReason'
                  : 'A sua conta foi reativada pela equipa DeliGo.'),
        action: suspend ? 'OPEN_BLOCKED_ACCOUNT' : 'OPEN_LOGIN',
        priority: 'HIGH',
        channel: 'system',
        data: {'reason': trimmedReason, 'role': role, 'blocked': suspend},
        metadata: {'source': 'admin_dashboard', 'reason': trimmedReason},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            suspend
                ? 'Conta suspensa com sucesso.'
                : 'Conta reativada com sucesso.',
          ),
        ),
      );
      await _loadDashboard();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao atualizar a conta: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingDecision = false;
          _processingUserId = null;
        });
      }
    }
  }

  Future<void> _showSuspendDialog(Map<String, dynamic> profile) async {
    final controller = TextEditingController(
      text: profile['block_reason']?.toString() ?? '',
    );
    final isBlocked = profile['is_blocked'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isBlocked ? 'Reativar conta' : 'Suspender conta'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: isBlocked
                  ? 'Motivo da reativacao'
                  : 'Motivo da suspensao',
              hintText: isBlocked
                  ? 'Explique porque a conta pode voltar a operar.'
                  : 'Explique o motivo da suspensao.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(isBlocked ? 'Reativar' : 'Suspender'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _toggleUserSuspension(
        profile: profile,
        suspend: !isBlocked,
        reason: controller.text,
      );
    }
    controller.dispose();
  }

  Future<void> _showKycDocuments(Map<String, dynamic> profile) async {
    final userId = profile['id']?.toString();
    final role = profile['role']?.toString();
    if (userId == null || role == null) return;

    try {
      List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

      try {
        final response = await _invokeFunctionDirect(
          'get_kyc_docs',
          body: {'user_id': userId, 'subject_type': role},
        );

        if (response.status >= 400) {
          throw Exception(
            response.json['error']?.toString() ?? response.json.toString(),
          );
        }

        final data = response.json;
        items = ((data['document_items'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map<Map<String, dynamic>>(
              (item) =>
                  item.map((key, value) => MapEntry(key.toString(), value)),
            )
            .map((item) {
              final rawLabel = item['label']?.toString() ?? '';
              return {...item, 'label': _kycLabel(rawLabel)};
            })
            .toList();
      } catch (_) {
        final rawDocs =
            (profile['kyc_docs'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        items = rawDocs.entries.map((entry) {
          final value =
              (entry.value as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          final path = value['path']?.toString() ?? '';
          final bucket = value['bucket']?.toString() ?? 'kyc';
          return <String, dynamic>{
            'label': _kycLabel(entry.key),
            'url': '',
            'path': path,
            'bucket': bucket,
            'broken': path.trim().isEmpty,
          };
        }).toList();
      }

      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          final sheetNavigator = Navigator.of(context);

          bool isImageItem(Map<String, dynamic> item) {
            final contentType =
                item['content_type']?.toString().toLowerCase().trim() ?? '';
            if (contentType.startsWith('image/')) return true;
            final probe =
                '${item['path'] ?? ''} ${item['url'] ?? ''} ${item['label'] ?? ''}'
                    .toLowerCase();
            return probe.contains('.jpg') ||
                probe.contains('.jpeg') ||
                probe.contains('.png') ||
                probe.contains('.webp');
          }

          Future<void> openDocument(Map<String, dynamic> item) async {
            if (!mounted) return;
            final url = item['url']?.toString() ?? '';
            final path = item['path']?.toString() ?? '';
            final bucket = item['bucket']?.toString() ?? 'kyc';
            final broken =
                item['broken'] == true || (url.isEmpty && path.isEmpty);
            if (broken) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Este documento ainda nao esta disponivel para abrir.',
                  ),
                ),
              );
              return;
            }

            String resolvedUrl = url;
            if (resolvedUrl.isEmpty && path.isNotEmpty) {
              resolvedUrl = await _supabase.storage
                  .from(bucket)
                  .createSignedUrl(path, 60 * 10);
            }
            if (resolvedUrl.isEmpty) {
              if (!mounted) return;
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Nao foi possivel gerar o link deste documento.',
                  ),
                ),
              );
              return;
            }

            if (sheetNavigator.canPop()) {
              sheetNavigator.pop();
            }
            if (!mounted) return;
            await Future<void>.delayed(const Duration(milliseconds: 120));
            if (!mounted) return;
            await Navigator.of(this.context, rootNavigator: true).push(
              MaterialPageRoute<void>(
                builder: (_) => AdminDocumentViewerPage(
                  title: item['label']?.toString() ?? 'Documento',
                  url: resolvedUrl,
                  storagePath: path.isNotEmpty ? path : null,
                  contentType: item['content_type']?.toString(),
                ),
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Documentos de ${profile['full_name'] ?? 'utilizador'}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('Nenhum documento disponivel.'),
                    ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final url = item['url']?.toString() ?? '';
                        final path = item['path']?.toString() ?? '';
                        final previewImage = isImageItem(item);
                        final broken =
                            item['broken'] == true ||
                            (url.isEmpty && path.isEmpty);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                onTap: broken ? null : () => openDocument(item),
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: broken
                                      ? Colors.red.withValues(alpha: 0.12)
                                      : Colors.green.withValues(alpha: 0.12),
                                  child: Icon(
                                    broken
                                        ? Icons.error_outline
                                        : previewImage
                                        ? Icons.image_outlined
                                        : Icons.description,
                                    color: broken ? Colors.red : Colors.green,
                                  ),
                                ),
                                title: Text(
                                  item['label']?.toString() ?? 'Documento',
                                ),
                                subtitle: Text(
                                  broken
                                      ? 'Ficheiro indisponivel ou assinatura falhou.'
                                      : previewImage
                                      ? 'Toque para ampliar ou abrir externamente.'
                                      : 'Toque para abrir o documento.',
                                ),
                                trailing: broken
                                    ? null
                                    : IconButton(
                                        onPressed: () => openDocument(item),
                                        icon: const Icon(Icons.open_in_new),
                                      ),
                              ),
                              if (!broken && previewImage && url.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: GestureDetector(
                                    onTap: () => openDocument(item),
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        minHeight: 160,
                                        maxHeight: 260,
                                      ),
                                      width: double.infinity,
                                      color: Colors.black,
                                      child: Image.network(
                                        url,
                                        fit: BoxFit.contain,
                                        loadingBuilder:
                                            (context, child, progress) {
                                              if (progress == null) {
                                                return child;
                                              }
                                              return const Center(
                                                child: Padding(
                                                  padding: EdgeInsets.all(24),
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              );
                                            },
                                        errorBuilder: (context, error, stackTrace) {
                                          return Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.broken_image_outlined,
                                                  color: Colors.white70,
                                                  size: 40,
                                                ),
                                                const SizedBox(height: 8),
                                                const Text(
                                                  'Nao foi possivel mostrar a imagem aqui.',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 8),
                                                OutlinedButton(
                                                  onPressed: () =>
                                                      openDocument(item),
                                                  child: const Text(
                                                    'Abrir documento',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
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
                ],
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel abrir os documentos: $error')),
      );
    }
  }

  String _money(double value, {String currency = 'MZN'}) {
    return '$currency ${value.toStringAsFixed(2)}';
  }

  String _dateLabel(String? raw) {
    if (raw == null || raw.isEmpty) return 'Sem data';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hour:$minute';
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'restaurant':
        return 'Restaurante';
      case 'courier':
        return 'Estafeta';
      case 'customer':
      case 'client':
      default:
        return 'Cliente';
    }
  }

  String _actionLabel(String? action) {
    switch (action) {
      case 'approved':
      case 'auto_approved':
        return 'Aprovado';
      case 'rejected':
      case 'auto_rejected':
        return 'Rejeitado';
      case 'pending':
        return 'Pendente';
      default:
        return action?.replaceAll('_', ' ') ?? 'Acao';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      _overviewTab(),
      _usersTab(),
      _kycTab(),
      _fieldStaffTab(),
      _notificationsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin DeliGo'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _refresh, child: tabs[_tabIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) {
          setState(() => _tabIndex = index);
          unawaited(_refresh());
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Resumo',
          ),
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Clientes',
          ),
          NavigationDestination(
            icon: Badge.count(
              isLabelVisible: _pendingKycCount > 0,
              count: _pendingKycCount,
              child: const Icon(Icons.verified_user_outlined),
            ),
            selectedIcon: const Icon(Icons.verified_user),
            label: 'KYC',
          ),
          NavigationDestination(
            icon: Badge.count(
              isLabelVisible: _pendingFieldInvitesCount > 0,
              count: _pendingFieldInvitesCount,
              child: const Icon(Icons.badge_outlined),
            ),
            selectedIcon: const Icon(Icons.badge),
            label: 'Equipa',
          ),
          NavigationDestination(
            icon: Badge.count(
              isLabelVisible: _unreadNotificationsCount > 0,
              count: _unreadNotificationsCount,
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: const Icon(Icons.notifications),
            label: 'Alertas',
          ),
        ],
      ),
    );
  }

  Widget _overviewTab() {
    final adminWallet = _adminWallet;
    final currency = adminWallet?['currency']?.toString() ?? 'MZN';
    final couriers = _profiles.where((row) => row['role'] == 'courier').length;
    final restaurants = _profiles
        .where((row) => row['role'] == 'restaurant')
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _adminHeroCard(),
        const SizedBox(height: 16),
        _searchField(),
        const SizedBox(height: 16),
        _sectionHeader(
          'Suporte ao Cliente',
          'Todas as mensagens de suporte entram aqui para os agentes DeliGo Field.',
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.support_agent, color: AppColors.primaryRed),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Abrir a caixa dos agentes de suporte',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => context.push('/support/admin'),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Abrir'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metricCard(
              title: 'Clientes ativos',
              value: '$_activeClientsCount',
              subtitle: 'Clientes nao bloqueados no sistema',
              icon: Icons.people_alt_outlined,
            ),
            _metricCard(
              title: 'KYCs pendentes',
              value: '$_pendingKycCount',
              subtitle: 'Estafetas e restaurantes por rever',
              icon: Icons.fact_check_outlined,
            ),
            _metricCard(
              title: 'Exclusoes pendentes',
              value: '$_pendingDeletionRequestsCount',
              subtitle: 'Pedidos de conta aguardando revisao',
              icon: Icons.person_off_outlined,
            ),
            _metricCard(
              title: 'Valor geral',
              value: _money(_totalWalletBalance, currency: currency),
              subtitle: 'Soma das wallets conhecidas no sistema',
              icon: Icons.payments_outlined,
            ),
            _metricCard(
              title: 'Conta do admin',
              value: _money(_adminAvailableBalance, currency: currency),
              subtitle: 'Saldo disponivel do admin',
              icon: Icons.account_balance_wallet_outlined,
            ),
            _metricCard(
              title: 'Pedidos 7 dias',
              value: _metric('orders_7').toStringAsFixed(0),
              subtitle: 'Pedidos relevantes na ultima semana',
              icon: Icons.receipt_long_outlined,
            ),
            _metricCard(
              title: 'Lucro admin 7 dias',
              value: _money(_metric('fees_7'), currency: currency),
              subtitle: 'Lucro confirmado de fees',
              icon: Icons.trending_up_outlined,
            ),
            _metricCard(
              title: 'Estafetas',
              value: '$couriers',
              subtitle: 'Perfis com papel courier',
              icon: Icons.delivery_dining_outlined,
            ),
            _metricCard(
              title: 'Restaurantes',
              value: '$restaurants',
              subtitle: 'Perfis com papel restaurant',
              icon: Icons.storefront_outlined,
            ),
            _metricCard(
              title: 'GMV 30 dias',
              value: _money(_metric('gmv_30'), currency: currency),
              subtitle: 'Valor total processado',
              icon: Icons.show_chart_outlined,
            ),
            _metricCard(
              title: 'Lucro admin 30 dias',
              value: _money(_metric('fees_30'), currency: currency),
              subtitle: 'Total de lucros do admin',
              icon: Icons.savings_outlined,
            ),
            _metricCard(
              title: 'OTP falhou hoje',
              value: '$_otpFailedTodayCount',
              subtitle: 'Entregas que escalaram por falha de OTP hoje',
              icon: Icons.pin_outlined,
            ),
            _metricCard(
              title: 'Overrides hoje',
              value: '$_otpOverridesTodayCount',
              subtitle: 'Resolvidos manualmente pelo admin hoje',
              icon: Icons.rule_folder_outlined,
            ),
            _metricCard(
              title: 'Top taxa OTP',
              value: '${_topCourierOtpFailureRate.toStringAsFixed(1)}%',
              subtitle: 'Maior taxa de falha OTP por estafeta em 30 dias',
              icon: Icons.warning_amber_rounded,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionHeader(
          'Radar OTP e fraude',
          'Mostra falhas OTP, overrides e estafetas que merecem atencao.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _infoPill('OTP falhou hoje', '$_otpFailedTodayCount'),
            _infoPill('Overrides hoje', '$_otpOverridesTodayCount'),
            _infoPill('Disputas via override', '$_otpDisputedTodayCount'),
            _infoPill(
              'Estafetas com override hoje',
              '$_otpCouriersWithOverrideToday',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_courierOtpRiskMetrics.isEmpty)
          _emptyStateCard(
            'Ainda nao ha risco OTP suficiente para mostrar.',
            icon: Icons.insights_outlined,
          )
        else
          ..._courierOtpRiskMetrics.map(_courierOtpRiskCard),
        const SizedBox(height: 24),
        _sectionHeader(
          'Receitas da plataforma',
          'Visao financeira clara da conta admin, fees confirmadas e valores em transito.',
        ),
        const SizedBox(height: 12),
        _platformFinanceCard(currency),
        const SizedBox(height: 24),
        _sectionHeader(
          'Wallets com divergencia',
          'Compara saldo atual com depositos confirmados e destaca ajustes manuais ou inconsistencias.',
        ),
        const SizedBox(height: 12),
        _walletDivergenceCard(currency),
        const SizedBox(height: 24),
        _sectionHeader(
          'Mini relatorio',
          'Leitura rapida do sistema para apoiar decisoes.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip('7 dias', '7', '$_reportPeriodDays', (value) {
              setState(() => _reportPeriodDays = int.tryParse(value) ?? 30);
            }),
            _filterChip('30 dias', '30', '$_reportPeriodDays', (value) {
              setState(() => _reportPeriodDays = int.tryParse(value) ?? 30);
            }),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            if (compact) {
              return Column(
                children: [
                  _rolesChartCard(),
                  const SizedBox(height: 12),
                  _kycChartCard(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _rolesChartCard()),
                const SizedBox(width: 12),
                Expanded(child: _kycChartCard()),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _financeSummaryCard(currency),
        const SizedBox(height: 24),
        _sectionHeader(
          'Fila de aprovacao',
          'Perfis que precisam de uma decisao agora.',
        ),
        const SizedBox(height: 12),
        if (_kycProfiles.isEmpty)
          _emptyStateCard(
            'Nenhum KYC encontrado para o filtro atual.',
            icon: Icons.verified_user_outlined,
          )
        else
          ..._kycProfiles
              .take(_visibleKyc.clamp(0, _kycProfiles.length))
              .map(_kycCard),
        if (_kycProfiles.length > _visibleKyc)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _visibleKyc += 20),
                icon: const Icon(Icons.expand_more),
                label: const Text('Ver mais KYCs'),
              ),
            ),
          ),
        const SizedBox(height: 24),
        _sectionHeader(
          'Pedidos de exclusao de conta',
          'Pedidos sensiveis que merecem revisao administrativa.',
        ),
        const SizedBox(height: 12),
        if (_visibleAccountDeletionRequests.isEmpty)
          _emptyStateCard(
            'Ainda nao ha pedidos de exclusao de conta.',
            icon: Icons.person_off_outlined,
          )
        else
          ..._visibleAccountDeletionRequests
              .take(
                _visibleDeletionRequests.clamp(
                  0,
                  _visibleAccountDeletionRequests.length,
                ),
              )
              .map(_accountDeletionRequestCard),
        if (_visibleAccountDeletionRequests.length > _visibleDeletionRequests)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _visibleDeletionRequests += 20),
                icon: const Icon(Icons.expand_more),
                label: const Text('Ver mais pedidos'),
              ),
            ),
          ),
        const SizedBox(height: 24),
        _sectionHeader(
          'Entregas com OTP falhado',
          'Casos operacionais que precisam de decisao auditada do admin.',
        ),
        const SizedBox(height: 12),
        if (_failedOtpOrders.isEmpty)
          _emptyStateCard(
            'Nenhuma entrega com falha de OTP no momento.',
            icon: Icons.verified_user_outlined,
          )
        else
          ..._failedOtpOrders
              .take(_visibleFailedOtpOrders.clamp(0, _failedOtpOrders.length))
              .map(_failedOtpOrderCard),
        if (_failedOtpOrders.length > _visibleFailedOtpOrders)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _visibleFailedOtpOrders += 20),
                icon: const Icon(Icons.expand_more),
                label: const Text('Ver mais casos OTP'),
              ),
            ),
          ),
        const SizedBox(height: 24),
        _sectionHeader(
          'Disputas de pedidos',
          'Casos abertos por clientes para analise do admin.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip('Todos', 'all', _disputeRoleFilter, (value) {
              setState(() => _disputeRoleFilter = value);
            }),
            _filterChip('Clientes', 'client', _disputeRoleFilter, (value) {
              setState(() => _disputeRoleFilter = value);
            }),
            _filterChip('Restaurantes', 'restaurant', _disputeRoleFilter, (
              value,
            ) {
              setState(() => _disputeRoleFilter = value);
            }),
            _filterChip('Estafetas', 'courier', _disputeRoleFilter, (value) {
              setState(() => _disputeRoleFilter = value);
            }),
          ],
        ),
        const SizedBox(height: 12),
        if (_filteredDisputes.isEmpty)
          _emptyStateCard(
            'Nenhuma disputa aberta no momento.',
            icon: Icons.gavel_outlined,
          )
        else
          ..._filteredDisputes
              .take(_visibleDisputes.clamp(0, _filteredDisputes.length))
              .map(_orderDisputeCard),
        if (_filteredDisputes.length > _visibleDisputes)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _visibleDisputes += 20),
                icon: const Icon(Icons.expand_more),
                label: const Text('Ver mais disputas'),
              ),
            ),
          ),
        const SizedBox(height: 24),
        _sectionHeader(
          'Historico recente do admin',
          'Acoes e decisoes mais recentes no painel.',
        ),
        const SizedBox(height: 12),
        if (_adminActions.isEmpty)
          _emptyStateCard(
            'Ainda nao existem acoes administrativas registadas.',
            icon: Icons.history,
          )
        else
          ..._adminActions
              .take(_visibleActions.clamp(0, _adminActions.length))
              .map(_adminActionCard),
        if (_adminActions.length > _visibleActions)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _visibleActions += 20),
                icon: const Icon(Icons.expand_more),
                label: const Text('Ver mais historico'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _usersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader(
          'Utilizadores',
          'Pesquise, filtre e acompanhe rapidamente cada perfil.',
        ),
        const SizedBox(height: 12),
        _searchField(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip(
              'Todos (${_filteredUsers.length})',
              'all',
              _userFilter,
              (value) {
                setState(() => _userFilter = value);
              },
            ),
            _filterChip('Clientes ($_clientsCount)', 'clients', _userFilter, (
              value,
            ) {
              setState(() => _userFilter = value);
            }),
            _filterChip(
              'Estafetas ($_couriersCount)',
              'couriers',
              _userFilter,
              (value) {
                setState(() => _userFilter = value);
              },
            ),
            _filterChip(
              'Restaurantes ($_restaurantsCount)',
              'restaurants',
              _userFilter,
              (value) {
                setState(() => _userFilter = value);
              },
            ),
            _filterChip('Admins ($_adminsCount)', 'admins', _userFilter, (
              value,
            ) {
              setState(() => _userFilter = value);
            }),
          ],
        ),
        const SizedBox(height: 16),
        if (_filteredUsers.isEmpty)
          _emptyStateCard(
            'Nenhum utilizador encontrado para este filtro.',
            icon: Icons.groups_outlined,
          )
        else
          ..._filteredUsers
              .take(_visibleUsers.clamp(0, _filteredUsers.length))
              .map(_richUserCard),
        if (_filteredUsers.length > _visibleUsers)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _visibleUsers += 20),
                icon: const Icon(Icons.expand_more),
                label: const Text('Ver mais utilizadores'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _kycTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader(
          'Revisao de KYC',
          'Aqui entram os documentos e decisoes que destravam a operacao.',
        ),
        const SizedBox(height: 12),
        _searchField(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip('Pendentes', 'pending', _kycFilter, (value) {
              setState(() => _kycFilter = value);
            }),
            _filterChip('Aprovados', 'approved', _kycFilter, (value) {
              setState(() => _kycFilter = value);
            }),
            _filterChip('Rejeitados', 'rejected', _kycFilter, (value) {
              setState(() => _kycFilter = value);
            }),
            _filterChip('Todos', 'all', _kycFilter, (value) {
              setState(() => _kycFilter = value);
            }),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _filterChip('Todos os tipos', 'all', _kycRoleFilter, (value) {
              setState(() => _kycRoleFilter = value);
            }),
            _filterChip('Restaurantes', 'restaurant', _kycRoleFilter, (value) {
              setState(() => _kycRoleFilter = value);
            }),
            _filterChip('Estafetas', 'courier', _kycRoleFilter, (value) {
              setState(() => _kycRoleFilter = value);
            }),
          ],
        ),
        const SizedBox(height: 16),
        if (_kycProfiles.isEmpty)
          _emptyStateCard(
            'Nao ha itens KYC para este filtro.',
            icon: Icons.fact_check_outlined,
          )
        else
          ..._kycProfiles
              .take(_visibleKyc.clamp(0, _kycProfiles.length))
              .map(_kycCard),
        if (_kycProfiles.length > _visibleKyc)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _visibleKyc += 20),
                icon: const Icon(Icons.expand_more),
                label: const Text('Ver mais KYCs'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fieldStaffTab() {
    final staffProfiles = _profiles.where((profile) {
      const roles = {
        'field_agent',
        'support_agent',
        'ambassador',
        'marketing_agent',
      };
      return roles.contains(profile['role']?.toString());
    }).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionHeader(
                'Equipa DeliGo Field',
                'Convites para Field, Suporte, Embaixadores e Marketing.',
              ),
            ),
            FilledButton.icon(
              onPressed: _showCreateFieldStaffInviteDialog,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Adicionar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _infoPill('Colaboradores ativos', '$_fieldStaffCount'),
            _infoPill('Convites pendentes', '$_pendingFieldInvitesCount'),
          ],
        ),
        const SizedBox(height: 20),
        _sectionHeader(
          'Convites',
          'O colaborador recebe OTP por SMS e entra pelo telefone.',
        ),
        const SizedBox(height: 12),
        if (_fieldStaffInvites.isEmpty)
          _emptyStateCard(
            'Ainda nao ha convites de colaboradores.',
            icon: Icons.badge_outlined,
          )
        else
          ..._fieldStaffInvites.map(_fieldStaffInviteCard),
        const SizedBox(height: 20),
        _sectionHeader(
          'Produtividade',
          'Acoes registadas no historico administrativo.',
        ),
        const SizedBox(height: 12),
        if (staffProfiles.isEmpty)
          _emptyStateCard(
            'Nenhum colaborador Field ativo encontrado.',
            icon: Icons.insights_outlined,
          )
        else
          ...staffProfiles.map(_fieldStaffProductivityCard),
      ],
    );
  }

  Widget _notificationsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionHeader(
                'Notificacoes do admin',
                'Alertas importantes e sinais que merecem atencao.',
              ),
            ),
            TextButton.icon(
              onPressed: _unreadNotificationsCount == 0
                  ? null
                  : _markAllNotificationsAsRead,
              icon: const Icon(Icons.done_all),
              label: const Text('Marcar tudo'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _dispatchObservabilitySection(),
        const SizedBox(height: 24),
        _sectionHeader(
          'Pedidos novos em tempo real',
          'Movimento recente que pode exigir acompanhamento.',
        ),
        const SizedBox(height: 12),
        if (_recentOrders.isEmpty)
          _emptyStateCard(
            'Ainda nao ha pedidos novos para mostrar.',
            icon: Icons.receipt_long_outlined,
          )
        else
          ..._recentOrders.take(10).map(_orderAlertCard),
        const SizedBox(height: 24),
        _sectionHeader(
          'Exclusao de conta',
          'Pedidos de remocao que entraram no fluxo administrativo.',
        ),
        const SizedBox(height: 12),
        if (_accountDeletionRequests.isEmpty)
          _emptyStateCard(
            'Nenhum pedido de exclusao para mostrar.',
            icon: Icons.person_remove_alt_1_outlined,
          )
        else
          ..._accountDeletionRequests.take(10).map(_accountDeletionRequestCard),
        const SizedBox(height: 24),
        _sectionHeader(
          'Docs enviados e notificacoes para rever',
          'Quando entra novo KYC, o alerta aparece aqui e no dispositivo.',
        ),
        const SizedBox(height: 12),
        if (_notifications.isEmpty)
          _emptyStateCard(
            'Ainda nao ha notificacoes. Quando algum KYC for enviado, o app admin pode receber alertas mesmo fora do painel web.',
            icon: Icons.notifications_none_rounded,
          )
        else
          ..._notifications
              .take(_visibleNotifications.clamp(0, _notifications.length))
              .map((notification) {
                final unread = notification['read_at'] == null;
                return Card(
                  child: ListTile(
                    onTap: () => _handleAdminNotificationTap(notification),
                    leading: CircleAvatar(
                      backgroundColor: unread
                          ? Colors.blue.withValues(alpha: 0.12)
                          : Colors.grey.withValues(alpha: 0.12),
                      child: Icon(
                        unread
                            ? Icons.notifications_active
                            : Icons.notifications,
                        color: unread ? Colors.blue : Colors.grey[700],
                      ),
                    ),
                    title: Text(
                      notification['title']?.toString() ?? 'Notificacao',
                    ),
                    subtitle: Text(
                      '${notification['body']?.toString() ?? ''}\n${_dateLabel(notification['created_at']?.toString())}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      notification['channel']?.toString().toUpperCase() ??
                          'SYSTEM',
                    ),
                  ),
                );
              }),
        if (_notifications.length > _visibleNotifications)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _visibleNotifications += 20),
                icon: const Icon(Icons.expand_more),
                label: const Text('Ver mais notificacoes'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dispatchObservabilitySection() {
    final pending = (_dispatchHealth['pending_jobs'] as num?)?.toInt() ?? 0;
    final failed = (_dispatchHealth['failed_jobs'] as num?)?.toInt() ?? 0;
    final deadLetter =
        (_dispatchHealth['dead_letter_jobs'] as num?)?.toInt() ?? 0;
    final sent = (_dispatchHealth['sent_jobs'] as num?)?.toInt() ?? 0;
    final delivered =
        (_dispatchHealth['delivered_notifications'] as num?)?.toInt() ?? 0;
    final opened =
        (_dispatchHealth['opened_notifications'] as num?)?.toInt() ?? 0;
    final retrying = (_dispatchHealth['retrying_jobs'] as num?)?.toInt() ?? 0;
    final tokenInvalid =
        (_dispatchHealth['token_invalid_jobs'] as num?)?.toInt() ?? 0;
    final avgLatencySeconds = (_dispatchHealth['avg_latency_seconds'] as num?)
        ?.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Saude do dispatch',
          'Fila, retries e dead letters do push critico.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _infoPill('Sent', '$sent'),
            _infoPill('Pending', '$pending'),
            _infoPill('Failed', '$failed'),
            _infoPill('Retrying', '$retrying'),
            _infoPill('Dead', '$deadLetter'),
            _infoPill('Delivered app', '$delivered'),
            _infoPill('Opened', '$opened'),
            _infoPill('Token invalid', '$tokenInvalid'),
            if (avgLatencySeconds != null)
              _infoPill(
                'Latency media',
                '${avgLatencySeconds.toStringAsFixed(1)}s',
              ),
            _infoPill(
              'Proximo',
              _dateLabel(_dispatchHealth['next_due_at']?.toString()),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _showDispatchQueueDialog(),
          icon: const Icon(Icons.queue_outlined),
          label: const Text('Ver fila de dispatch'),
        ),
        const SizedBox(height: 12),
        if (_dispatchTimeline.isEmpty)
          _emptyStateCard(
            'Ainda nao ha jobs de dispatch para mostrar.',
            icon: Icons.notifications_paused_outlined,
          )
        else
          ..._dispatchTimeline.take(8).map(_dispatchTimelineCard),
        if (_dispatchWebhooks.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionHeader(
            'Eventos recentes do worker',
            'Ultimos sinais emitidos pelo pipeline de notificacoes.',
          ),
          const SizedBox(height: 12),
          ..._dispatchWebhooks.take(5).map(_dispatchWebhookCard),
        ],
      ],
    );
  }

  Widget _dispatchTimelineCard(Map<String, dynamic> row) {
    final status = row['status']?.toString().toUpperCase() ?? 'UNKNOWN';
    final eventTopic = row['event_topic']?.toString() ?? 'ORDER_EVENT';
    final retryCount = (row['retry_count'] as num?)?.toInt() ?? 0;
    final maxRetries = (row['max_retries'] as num?)?.toInt() ?? 0;
    final latency = row['latency_seconds'];
    final lastError = row['last_error']?.toString().trim() ?? '';
    final appDeliveryState =
        row['app_delivery_state']?.toString().trim().toUpperCase() ?? '';
    final subtitle = StringBuffer()
      ..write('Job $status')
      ..write(' • retries $retryCount/$maxRetries');
    if (latency != null) {
      subtitle.write(' • latency ${latency.toString()}s');
    }
    if (lastError.isNotEmpty) {
      subtitle.write('\n$lastError');
    }
    if (appDeliveryState.isNotEmpty) {
      subtitle.write('\napp $appDeliveryState');
    }
    subtitle.write('\n${_dateLabel(row['created_at']?.toString())}');

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _dispatchStatusColor(status).withValues(alpha: 0.12),
          child: Icon(
            Icons.sync_problem_rounded,
            color: _dispatchStatusColor(status),
          ),
        ),
        title: Text(eventTopic),
        subtitle: Text(subtitle.toString()),
        isThreeLine: true,
        trailing: Text(row['target_role']?.toString().toUpperCase() ?? 'USER'),
      ),
    );
  }

  Widget _dispatchWebhookCard(Map<String, dynamic> row) {
    final metadata = Map<String, dynamic>.from(
      (row['metadata'] as Map?) ?? const <String, dynamic>{},
    );
    final orderId = metadata['order_id']?.toString();
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0x14000000),
          child: Icon(Icons.monitor_heart_outlined),
        ),
        title: Text(row['event']?.toString() ?? 'worker_event'),
        subtitle: Text(
          '${orderId == null || orderId.isEmpty ? '' : 'Pedido $orderId\n'}${_dateLabel(row['created_at']?.toString())}',
        ),
        isThreeLine: orderId != null && orderId.isNotEmpty,
      ),
    );
  }

  Color _dispatchStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'SENT':
        return Colors.green;
      case 'FAILED':
        return Colors.orange;
      case 'DEAD_LETTER':
        return Colors.red;
      case 'PENDING':
      case 'PROCESSING':
        return Colors.blue;
      case 'SKIPPED':
        return Colors.grey;
      default:
        return Colors.black54;
    }
  }

  bool _hasAssignedCourier(Map<String, dynamic> order) {
    return order['courier_id']?.toString().trim().isNotEmpty == true;
  }

  bool _isPaymentProblem(Map<String, dynamic> order) {
    final status = order['payment_status']?.toString().toLowerCase() ?? '';
    return status == 'pending' ||
        status == 'failed' ||
        status == 'declined' ||
        status == 'cancelled' ||
        status == 'canceled';
  }

  bool _isOtpFailure(Map<String, dynamic> order) {
    return order['status']?.toString().toLowerCase() == 'delivery_failed_otp';
  }

  bool _isStuckOrder(Map<String, dynamic> order) {
    final status = order['status']?.toString().toLowerCase() ?? '';
    if (status == 'delivered' ||
        status == 'cancelled' ||
        status == 'canceled') {
      return false;
    }
    final raw =
        order['updated_at']?.toString() ?? order['created_at']?.toString();
    final date = DateTime.tryParse(raw ?? '')?.toLocal();
    if (date == null) return false;
    return DateTime.now().difference(date).inMinutes >= 30;
  }

  bool _hasOpenDisputeForOrder(String? orderId) {
    if (orderId == null || orderId.isEmpty) return false;
    return _orderDisputes.any((row) {
      final status = row['status']?.toString().toLowerCase() ?? 'open';
      return row['order_id']?.toString() == orderId && status != 'resolved';
    });
  }

  bool _rowMentionsOrder(Map<String, dynamic> row, String orderId) {
    if (orderId.isEmpty) return false;
    final direct =
        row['order_id']?.toString() == orderId ||
        row['entity_id']?.toString() == orderId ||
        row['target_id']?.toString() == orderId;
    if (direct) return true;
    final metadata = row['metadata'];
    if (metadata is Map && metadata['order_id']?.toString() == orderId) {
      return true;
    }
    return jsonEncode(row).contains(orderId);
  }

  bool _hasDispatchProblemForOrder(String? orderId) {
    if (orderId == null || orderId.isEmpty) return false;
    return _dispatchTimeline.any((row) {
      final status = row['status']?.toString().toUpperCase() ?? '';
      return _rowMentionsOrder(row, orderId) &&
          (status == 'FAILED' ||
              status == 'DEAD_LETTER' ||
              status == 'RETRYING' ||
              status == 'PENDING');
    });
  }

  Future<void> _reassignCourier(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString();
    if (orderId == null || orderId.isEmpty) return;
    try {
      await _deliveryService.notifyNearbyCouriers(orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Dispatch reaberto para ${_shortOrderRef(orderId)}. Estafetas proximos serao notificados.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _loadDashboard();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel reatribuir estafeta: $error')),
      );
    }
  }

  Future<Map<String, dynamic>> _fetchOperationalOrderDetail(
    Map<String, dynamic> seed,
  ) async {
    final orderId = seed['id']?.toString();
    var order = Map<String, dynamic>.from(seed);
    if (orderId == null || orderId.isEmpty) {
      return <String, dynamic>{'order': order};
    }

    try {
      final row = await _supabase
          .from('orders')
          .select('*')
          .eq('id', orderId)
          .maybeSingle();
      if (row != null) order = Map<String, dynamic>.from(row);
    } catch (_) {}

    Map<String, dynamic>? restaurant;
    final restaurantId = order['restaurant_id']?.toString();
    if (restaurantId != null && restaurantId.isNotEmpty) {
      try {
        final row = await _supabase
            .from('restaurants')
            .select('id, name, phone, address, neighborhood, city')
            .eq('id', restaurantId)
            .maybeSingle();
        if (row != null) restaurant = Map<String, dynamic>.from(row);
      } catch (_) {}
    }

    List<Map<String, dynamic>> orderItems = const [];
    try {
      final rows = await _supabase
          .from('order_items')
          .select('*')
          .eq('order_id', orderId)
          .limit(50);
      orderItems = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {}

    List<Map<String, dynamic>> pushEvents = const [];
    try {
      final rows = await _supabase
          .from('push_notifications')
          .select(
            'id, user_id, title, body, type, action, entity_id, priority, channel, metadata, created_at, read_at',
          )
          .eq('entity_id', orderId)
          .order('created_at', ascending: false)
          .limit(30);
      pushEvents = (rows as List)
          .cast<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {}

    final disputes = _orderDisputes
        .where((row) => row['order_id']?.toString() == orderId)
        .map(Map<String, dynamic>.from)
        .toList();
    final dispatchJobs = _dispatchTimeline
        .where((row) => _rowMentionsOrder(row, orderId))
        .map(Map<String, dynamic>.from)
        .toList();
    final dispatchWebhooks = _dispatchWebhooks
        .where((row) => _rowMentionsOrder(row, orderId))
        .map(Map<String, dynamic>.from)
        .toList();

    return <String, dynamic>{
      'order': order,
      'restaurant': restaurant,
      'items': orderItems,
      'push_events': pushEvents,
      'disputes': disputes,
      'dispatch_jobs': dispatchJobs,
      'dispatch_webhooks': dispatchWebhooks,
    };
  }

  Future<void> _showOperationalOrderDetails(
    Map<String, dynamic> order, {
    String focus = 'overview',
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _fetchOperationalOrderDetail(order),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data ?? <String, dynamic>{'order': order};
              return _operationalOrderDetailContent(
                sheetContext,
                data,
                focus: focus,
              );
            },
          ),
        );
      },
    );
  }

  Widget _operationalOrderDetailContent(
    BuildContext sheetContext,
    Map<String, dynamic> data, {
    required String focus,
  }) {
    final order = Map<String, dynamic>.from(
      (data['order'] as Map?) ?? const <String, dynamic>{},
    );
    final restaurant = (data['restaurant'] as Map?)?.cast<String, dynamic>();
    final orderId = order['id']?.toString();
    final clientId = (order['client_id'] ?? order['customer_id'])?.toString();
    final restaurantId = order['restaurant_id']?.toString();
    final courierId = order['courier_id']?.toString();
    final status = order['status']?.toString() ?? 'pending';
    final paymentStatus = order['payment_status']?.toString() ?? 'pending';
    final items = ((data['items'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final pushEvents = ((data['push_events'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final disputes = ((data['disputes'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final dispatchJobs = ((data['dispatch_jobs'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final dispatchWebhooks = ((data['dispatch_webhooks'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final delivery = (order['delivery_fee'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Operacao ${_shortOrderRef(orderId)}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Fechar',
                onPressed: () => Navigator.of(sheetContext).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _infoPill('Pedido', status),
              _infoPill('Pagamento', paymentStatus),
              _infoPill('Total', _money(total)),
              _infoPill('Entrega', _money(delivery)),
              if (focus != 'overview') _infoPill('Foco', focus),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _criticalOrderActions(order, compact: true),
          ),
          const SizedBox(height: 20),
          _detailSection('Pessoas', [
            _detailRow('Cliente', _profileNameById(clientId)),
            _detailRow(
              'Restaurante',
              restaurant?['name']?.toString() ?? _profileNameById(restaurantId),
            ),
            _detailRow(
              'Telefone restaurante',
              restaurant?['phone']?.toString() ?? 'Sem telefone',
            ),
            _detailRow(
              'Estafeta',
              _hasAssignedCourier(order)
                  ? _profileNameById(courierId)
                  : 'Sem estafeta atribuido',
            ),
          ]),
          _detailSection('Pagamento', [
            _detailRow('Estado', paymentStatus),
            _detailRow(
              'Metodo',
              order['payment_method']?.toString() ?? 'Nao informado',
            ),
            _detailRow('Total', _money(total)),
            _detailRow('Taxa entrega', _money(delivery)),
            _detailRow(
              'Fee admin',
              _money((order['platform_fee'] as num?)?.toDouble() ?? 0),
            ),
          ]),
          _detailSection('Historico do pedido', [
            _detailRow('Criado', _dateLabel(order['created_at']?.toString())),
            _detailRow(
              'Atualizado',
              _dateLabel(order['updated_at']?.toString()),
            ),
            _detailRow(
              'Endereco',
              order['delivery_address']?.toString() ?? 'Sem endereco',
            ),
            _detailRow(
              'Itens',
              items.isEmpty
                  ? 'Sem itens carregados'
                  : '${items.length} item(ns)',
            ),
          ]),
          _listSection(
            'Eventos push',
            pushEvents,
            empty: 'Sem eventos push ligados ao pedido.',
            builder: (row) =>
                '${row['type'] ?? row['title'] ?? 'Push'} - ${row['channel'] ?? 'canal'}\n${_dateLabel(row['created_at']?.toString())}',
          ),
          _listSection(
            'Dispatch',
            [...dispatchJobs, ...dispatchWebhooks],
            empty: 'Sem eventos de dispatch ligados ao pedido.',
            builder: (row) =>
                '${row['event_topic'] ?? row['event'] ?? row['status'] ?? 'Dispatch'}\n${row['last_error'] ?? _dateLabel(row['created_at']?.toString())}',
          ),
          _listSection(
            'Disputa / OTP',
            disputes,
            empty: _isOtpFailure(order)
                ? 'OTP falhou. Use Resolver para concluir com auditoria.'
                : 'Sem disputa aberta neste pedido.',
            builder: (row) =>
                '${row['dispute_type'] ?? 'Disputa'} - ${row['status'] ?? 'open'}\n${row['reason'] ?? ''}',
          ),
        ],
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderGray),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? 'Nao informado' : value)),
        ],
      ),
    );
  }

  Widget _listSection(
    String title,
    List<Map<String, dynamic>> rows, {
    required String empty,
    required String Function(Map<String, dynamic>) builder,
  }) {
    return _detailSection(
      title,
      rows.isEmpty
          ? [Align(alignment: Alignment.centerLeft, child: Text(empty))]
          : rows.take(8).map((row) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(builder(row)),
                ),
              );
            }).toList(),
    );
  }

  List<Widget> _criticalOrderActions(
    Map<String, dynamic> order, {
    bool compact = false,
  }) {
    final orderId = order['id']?.toString();
    final labelStyle = compact
        ? const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)
        : null;
    final actions = <Widget>[
      if (!_hasAssignedCourier(order))
        FilledButton.tonalIcon(
          onPressed: orderId == null ? null : () => _reassignCourier(order),
          icon: const Icon(Icons.delivery_dining_outlined),
          label: Text('Reatribuir estafeta', style: labelStyle),
        ),
      if (_isPaymentProblem(order))
        OutlinedButton.icon(
          onPressed: orderId == null
              ? null
              : () => _showOperationalOrderDetails(order, focus: 'pagamento'),
          icon: const Icon(Icons.payments_outlined),
          label: Text('Ver pagamento', style: labelStyle),
        ),
      if (_isStuckOrder(order))
        OutlinedButton.icon(
          onPressed: orderId == null
              ? null
              : () => _showOperationalOrderDetails(order, focus: 'parado'),
          icon: const Icon(Icons.manage_search_outlined),
          label: Text('Abrir detalhes', style: labelStyle),
        ),
      if (_isOtpFailure(order))
        FilledButton.icon(
          onPressed: orderId == null
              ? null
              : () => _showResolveFailedOtpDialog(order),
          icon: const Icon(Icons.verified_user_outlined),
          label: Text('Resolver OTP', style: labelStyle),
        ),
      if (_hasOpenDisputeForOrder(orderId))
        OutlinedButton.icon(
          onPressed: orderId == null
              ? null
              : () => _showOperationalOrderDetails(order, focus: 'disputa'),
          icon: const Icon(Icons.gavel_outlined),
          label: Text('Ver disputa', style: labelStyle),
        ),
      if (_hasDispatchProblemForOrder(orderId))
        OutlinedButton.icon(
          onPressed: () => _showDispatchQueueDialog(orderId: orderId),
          icon: const Icon(Icons.notification_important_outlined),
          label: Text('Ver fila dispatch', style: labelStyle),
        ),
    ];

    actions.add(
      TextButton.icon(
        onPressed: orderId == null
            ? null
            : () => _showOperationalOrderDetails(order),
        icon: const Icon(Icons.receipt_long_outlined),
        label: Text('Detalhe operacional', style: labelStyle),
      ),
    );
    return actions;
  }

  Future<void> _showDispatchQueueDialog({String? orderId}) async {
    final jobs = orderId == null || orderId.isEmpty
        ? _dispatchTimeline
        : _dispatchTimeline
              .where((row) => _rowMentionsOrder(row, orderId))
              .toList();
    final webhooks = orderId == null || orderId.isEmpty
        ? _dispatchWebhooks
        : _dispatchWebhooks
              .where((row) => _rowMentionsOrder(row, orderId))
              .toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            orderId == null || orderId.isEmpty
                ? 'Fila de dispatch'
                : 'Dispatch ${_shortOrderRef(orderId)}',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _infoPill('Jobs', '${jobs.length}'),
                      _infoPill('Worker', '${webhooks.length}'),
                      _infoPill(
                        'Failed',
                        '${jobs.where((row) => row['status']?.toString().toUpperCase() == 'FAILED').length}',
                      ),
                      _infoPill(
                        'Dead',
                        '${jobs.where((row) => row['status']?.toString().toUpperCase() == 'DEAD_LETTER').length}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (jobs.isEmpty && webhooks.isEmpty)
                    const Text('Sem eventos de dispatch para este filtro.'),
                  ...jobs.take(12).map(_dispatchTimelineCard),
                  ...webhooks.take(8).map(_dispatchWebhookCard),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: const Icon(Icons.close),
              ),
        hintText: 'Pesquisar por nome, telefone ou papel',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppColors.borderGray.withValues(alpha: 0.8),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: AppColors.primaryGreen,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _adminHeroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF121212), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Centro de controlo DeliGo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
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
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_pendingKycCount + _pendingDeletionRequestsCount} pendencias',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Visao rapida para decidir, desbloquear operacoes e acompanhar o estado do ecossistema.',
            style: TextStyle(color: Color(0xFFD1D5DB), height: 1.4),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroPill(
                Icons.fact_check_outlined,
                'KYCs pendentes',
                '$_pendingKycCount',
              ),
              _heroPill(
                Icons.person_off_outlined,
                'Exclusoes',
                '$_pendingDeletionRequestsCount',
              ),
              _heroPill(
                Icons.notifications_active_outlined,
                'Alertas',
                '$_unreadNotificationsCount',
              ),
              _heroPill(
                Icons.pin_outlined,
                'OTP falhou hoje',
                '$_otpFailedTodayCount',
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push('/admin/social-moderation'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
            ),
            icon: const Icon(Icons.forum_outlined),
            label: const Text('Abrir moderacao social'),
          ),
        ],
      ),
    );
  }

  Widget _heroPill(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.neutralGray, height: 1.35),
        ),
      ],
    );
  }

  Widget _emptyStateCard(String text, {required IconData icon}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primaryGreen),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
          ],
        ),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return SizedBox(
      width: 250,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 24, color: AppColors.primaryGreen),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.neutralGray,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountDeletionRequestCard(Map<String, dynamic> request) {
    final status = request['status']?.toString().toLowerCase() ?? 'pending';
    final email = request['email']?.toString().trim();
    final role = request['role']?.toString().trim();
    final reason = request['reason']?.toString().trim();
    final source = request['source']?.toString().trim();
    final metadata =
        (request['metadata'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final needsReview = metadata['requires_manual_review'] == true;
    final availableBalance =
        (metadata['wallet_available_balance'] as num?)?.toDouble() ?? 0;
    final pendingBalance =
        (metadata['wallet_pending_balance'] as num?)?.toDouble() ?? 0;
    final activeOrders =
        (metadata['active_orders_count'] as num?)?.toInt() ?? 0;
    Color chipColor;
    switch (status) {
      case 'processed':
      case 'completed':
        chipColor = Colors.green;
        break;
      case 'rejected':
      case 'cancelled':
        chipColor = Colors.red;
        break;
      default:
        chipColor = needsReview ? Colors.orange : Colors.blue;
        break;
    }
    final details = <String>[
      if (role != null && role.isNotEmpty) role,
      if (source != null && source.isNotEmpty) source,
      if (activeOrders > 0) ' pedidos ativos',
      if (availableBalance > 0) 'wallet ',
      if (pendingBalance > 0) 'pendente ',
    ];
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: chipColor.withValues(alpha: 0.12),
          child: Icon(Icons.person_off_outlined, color: chipColor),
        ),
        title: Text(email?.isNotEmpty == true ? email! : 'Pedido de exclusao'),
        subtitle: Text(
          [
            if (reason != null && reason.isNotEmpty) reason,
            if (details.isNotEmpty) details.join(' - '),
            _dateLabel(request['requested_at']?.toString()),
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: Chip(
          label: Text(status.toUpperCase()),
          backgroundColor: chipColor.withValues(alpha: 0.12),
          labelStyle: TextStyle(color: chipColor),
        ),
      ),
    );
  }

  Future<void> _showResolveFailedOtpDialog(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    var selectedReason = 'otp_failed';
    var selectedProofType = 'gps';
    var markAsDisputed = false;
    var callAttempted = false;
    final notesController = TextEditingController();
    final photoUrlController = TextEditingController();
    final latitudeController = TextEditingController();
    final longitudeController = TextEditingController();
    var submitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !submitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              setModalState(() => submitting = true);
              final gpsLatitude = double.tryParse(
                latitudeController.text.trim().replaceAll(',', '.'),
              );
              final gpsLongitude = double.tryParse(
                longitudeController.text.trim().replaceAll(',', '.'),
              );

              final result = await _orderService.adminResolveDeliveryOtpFailure(
                orderId: orderId,
                reason: selectedReason,
                proofType: selectedProofType,
                notes: notesController.text,
                proofUrl: photoUrlController.text.trim().isEmpty
                    ? null
                    : photoUrlController.text.trim(),
                gpsLatitude: gpsLatitude,
                gpsLongitude: gpsLongitude,
                callAttempted: callAttempted,
                markAsDisputed: markAsDisputed,
              );

              if (!mounted) return;
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(result.message),
                  backgroundColor: result.success ? Colors.green : null,
                ),
              );
              if (result.success) {
                await _loadDashboard();
              }
            }

            return AlertDialog(
              title: Text('Resolver ${_shortOrderRef(orderId)}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      decoration: const InputDecoration(
                        labelText: 'Motivo principal',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'otp_failed',
                          child: Text('OTP falhou'),
                        ),
                        DropdownMenuItem(
                          value: 'customer_unreachable',
                          child: Text('Cliente inacessivel'),
                        ),
                        DropdownMenuItem(
                          value: 'device_issue',
                          child: Text('Problema no dispositivo'),
                        ),
                        DropdownMenuItem(
                          value: 'customer_requested_manual',
                          child: Text('Cliente pediu resolucao manual'),
                        ),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setModalState(() => selectedReason = value);
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedProofType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de prova',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'gps', child: Text('GPS')),
                        DropdownMenuItem(value: 'photo', child: Text('Foto')),
                        DropdownMenuItem(value: 'call', child: Text('Chamada')),
                      ],
                      onChanged: submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setModalState(() => selectedProofType = value);
                            },
                    ),
                    const SizedBox(height: 12),
                    if (selectedProofType == 'photo')
                      TextField(
                        controller: photoUrlController,
                        enabled: !submitting,
                        decoration: const InputDecoration(
                          labelText:
                              'URL da foto (opcional se ja existir prova)',
                        ),
                      ),
                    if (selectedProofType == 'gps') ...[
                      TextField(
                        controller: latitudeController,
                        enabled: !submitting,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText:
                              'Latitude (opcional se o sistema ja tiver GPS)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: longitudeController,
                        enabled: !submitting,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText:
                              'Longitude (opcional se o sistema ja tiver GPS)',
                        ),
                      ),
                    ],
                    if (selectedProofType == 'call')
                      SwitchListTile(
                        value: callAttempted,
                        contentPadding: EdgeInsets.zero,
                        onChanged: submitting
                            ? null
                            : (value) {
                                setModalState(() => callAttempted = value);
                              },
                        title: const Text('Tentativa de chamada registada'),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      enabled: !submitting,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notas',
                        hintText:
                            'Contexto da decisao e evidencias adicionais.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: markAsDisputed,
                      contentPadding: EdgeInsets.zero,
                      onChanged: submitting
                          ? null
                          : (value) {
                              setModalState(() => markAsDisputed = value);
                            },
                      title: const Text(
                        'Enviar para disputa em vez de concluir',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: Text(
                    submitting
                        ? 'A guardar...'
                        : markAsDisputed
                        ? 'Abrir disputa'
                        : 'Concluir com auditoria',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    notesController.dispose();
    photoUrlController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
  }

  Widget _failedOtpOrderCard(Map<String, dynamic> order) {
    final orderId = order['id']?.toString();
    final clientId = (order['client_id'] ?? order['customer_id'])?.toString();
    final courierId = order['courier_id']?.toString();
    final totalAmount = (order['total_amount'] as num?)?.toDouble();
    final subtitleLines = <String>[
      if (clientId != null && clientId.isNotEmpty)
        'Cliente: ${_profileNameById(clientId)}',
      if (courierId != null && courierId.isNotEmpty)
        'Estafeta: ${_profileNameById(courierId)}',
      if (order['delivery_address']?.toString().trim().isNotEmpty == true)
        order['delivery_address'].toString().trim(),
      if (totalAmount != null) 'Total: ${_money(totalAmount, currency: 'MZN')}',
      _dateLabel(
        order['updated_at']?.toString() ?? order['created_at']?.toString(),
      ),
    ];

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.deepOrange.withValues(alpha: 0.12),
          child: const Icon(Icons.pin_outlined, color: Colors.deepOrange),
        ),
        title: Text('${_shortOrderRef(orderId)} - OTP falhou'),
        subtitle: Text(subtitleLines.join('\n')),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: orderId == null
                  ? null
                  : () => _showOperationalOrderDetails(order, focus: 'otp'),
              child: const Text('Ver pedido'),
            ),
            FilledButton.tonal(
              onPressed: orderId == null
                  ? null
                  : () => _showResolveFailedOtpDialog(order),
              child: const Text('Resolver'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _courierOtpRiskCard(Map<String, dynamic> row) {
    final courierId = row['courier_id']?.toString();
    final courierName = row['courier_name']?.toString().trim();
    final deliveryOrders = (row['delivery_orders_30d'] as num?)?.toInt() ?? 0;
    final otpFailures = (row['otp_failures_30d'] as num?)?.toInt() ?? 0;
    final overrides = (row['overrides_30d'] as num?)?.toInt() ?? 0;
    final disputedOverrides =
        (row['disputed_overrides_30d'] as num?)?.toInt() ?? 0;
    final failureRate = (row['otp_failure_rate_30d'] as num?)?.toDouble() ?? 0;
    final riskColor = failureRate >= 20 || overrides >= 3
        ? Colors.deepOrange
        : failureRate >= 10 || overrides >= 2
        ? Colors.orange
        : Colors.blueGrey;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: riskColor.withValues(alpha: 0.12),
          child: Icon(Icons.delivery_dining_outlined, color: riskColor),
        ),
        title: Text(
          courierName?.isNotEmpty == true
              ? courierName!
              : _profileNameById(courierId),
        ),
        subtitle: Text(
          'Falhas OTP 30d: $otpFailures em $deliveryOrders entregas\n'
          'Taxa: ${failureRate.toStringAsFixed(1)}% - Overrides: $overrides - Disputas: $disputedOverrides',
        ),
        isThreeLine: true,
        trailing: Chip(
          label: Text('${failureRate.toStringAsFixed(1)}%'),
          backgroundColor: riskColor.withValues(alpha: 0.12),
          labelStyle: TextStyle(color: riskColor),
        ),
      ),
    );
  }

  Widget _orderDisputeCard(Map<String, dynamic> dispute) {
    final status = dispute['status']?.toString().toLowerCase() ?? 'open';
    final orderId = dispute['order_id']?.toString();
    final openedBy = dispute['opened_by']?.toString();
    final openedByRole = dispute['opened_by_role']?.toString() ?? 'cliente';
    final disputeType = dispute['dispute_type']?.toString() ?? 'disputa';
    final reason = dispute['reason']?.toString() ?? '';
    final order = (dispute['orders'] as Map?)?.cast<String, dynamic>();
    final orderStatus = order?['status']?.toString() ?? '';
    final totalAmount = (order?['total_amount'] as num?)?.toDouble();
    final statusColor = status == 'open'
        ? Colors.orange
        : status == 'resolved'
        ? Colors.green
        : Colors.blueGrey;

    final title =
        '${_shortOrderRef(orderId)} · ${disputeType.replaceAll('_', ' ')}';
    final subtitleLines = <String>[
      'Aberto por: ${_profileNameById(openedBy)} ($openedByRole)',
      if (orderStatus.isNotEmpty) 'Status pedido: $orderStatus',
      if (totalAmount != null) 'Total: ${_money(totalAmount, currency: 'MZN')}',
      if (reason.trim().isNotEmpty) 'Motivo: $reason',
      _dateLabel(dispute['created_at']?.toString()),
    ];

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.12),
          child: Icon(Icons.gavel_outlined, color: statusColor),
        ),
        title: Text(title),
        subtitle: Text(subtitleLines.join('\n')),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Chip(
              label: Text(status.toUpperCase()),
              backgroundColor: statusColor.withValues(alpha: 0.12),
              labelStyle: TextStyle(color: statusColor),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: orderId == null
                  ? null
                  : () => _showOperationalOrderDetails(<String, dynamic>{
                      'id': orderId,
                      ...?order,
                    }, focus: 'disputa'),
              child: const Text('Ver disputa'),
            ),
          ],
        ),
      ),
    );
  }

  String _profileNameById(String? userId) {
    if (userId == null || userId.isEmpty) return 'Utilizador';
    final match = _profiles.firstWhere(
      (row) => row['id']?.toString() == userId,
      orElse: () => const <String, dynamic>{},
    );
    final name = match['full_name']?.toString().trim();
    return (name != null && name.isNotEmpty) ? name : 'Utilizador';
  }

  String _shortOrderRef(String? orderId) {
    if (orderId == null || orderId.isEmpty) return '#----';
    final compact = orderId.replaceAll('-', '').toUpperCase();
    final short = compact.length >= 6 ? compact.substring(0, 6) : compact;
    return '#$short';
  }

  Widget _rolesChartCard() {
    final clients = _clients.length.toDouble();
    final couriers = _countByRole('courier').toDouble();
    final restaurants = _countByRole('restaurant').toDouble();
    final admins = _countByRole('admin').toDouble();
    final values = [clients, couriers, restaurants, admins];
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final maxY = (maxValue + 1).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Utilizadores por perfil',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maxY <= 0 ? 4 : maxY,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          const labels = [
                            'Clientes',
                            'Estaf.',
                            'Rest.',
                            'Admin',
                          ];
                          final index = value.toInt();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              index >= 0 && index < labels.length
                                  ? labels[index]
                                  : '',
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    _barGroup(0, clients, Colors.blue),
                    _barGroup(1, couriers, Colors.orange),
                    _barGroup(2, restaurants, Colors.green),
                    _barGroup(3, admins, Colors.purple),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kycChartCard() {
    final sections = <PieChartSectionData>[
      PieChartSectionData(
        value: _pendingKycCount.toDouble(),
        color: Colors.orange,
        title: 'Pend.',
        radius: 56,
      ),
      PieChartSectionData(
        value: _approvedKycCount.toDouble(),
        color: Colors.green,
        title: 'Apr.',
        radius: 56,
      ),
      PieChartSectionData(
        value: _rejectedKycCount.toDouble(),
        color: Colors.red,
        title: 'Rej.',
        radius: 56,
      ),
    ].where((section) => section.value > 0).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estado dos KYCs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: sections.isEmpty
                  ? const Center(child: Text('Sem dados KYC para mostrar.'))
                  : PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 36,
                        sections: sections,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _legendDot(Colors.orange, 'Pendentes: $_pendingKycCount'),
                _legendDot(Colors.green, 'Aprovados: $_approvedKycCount'),
                _legendDot(Colors.red, 'Rejeitados: $_rejectedKycCount'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _financeSummaryCard(String currency) {
    final daysLabel = _reportPeriodDays == 7 ? '7d' : '30d';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Financeiro rapido',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _infoPill(
                  'Pedidos $daysLabel',
                  _selectedPeriodOrders.toStringAsFixed(0),
                ),
                _infoPill(
                  'GMV $daysLabel',
                  _money(_selectedPeriodGmv, currency: currency),
                ),
                _infoPill(
                  'Fees $daysLabel',
                  _money(_selectedPeriodFees, currency: currency),
                ),
                _infoPill(
                  'Delivery $daysLabel',
                  _money(_selectedPeriodDelivery, currency: currency),
                ),
                _infoPill(
                  'GMV 30d',
                  _money(_metric('gmv_30'), currency: currency),
                ),
                _infoPill(
                  'Fees 30d',
                  _money(_metric('fees_30'), currency: currency),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _platformFinanceCard(String currency) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Financeiro rapido',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Enquanto os fluxos reais consolidam, esta area deve mostrar apenas valores confirmados.',
              style: TextStyle(color: AppColors.neutralGray, height: 1.35),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _infoPill('Saldo da plataforma', _money(0, currency: currency)),
                _infoPill(
                  'Pendente da plataforma',
                  _money(0, currency: currency),
                ),
                _infoPill('Fees confirmadas', _money(0, currency: currency)),
                _infoPill('GMV do periodo', _money(0, currency: currency)),
                _infoPill('Delivery do periodo', _money(0, currency: currency)),
                _infoPill('Pedidos do periodo', '0'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletDivergenceCard(String currency) {
    if (_walletDivergences.isEmpty) {
      return _emptyStateCard(
        'Nenhuma divergencia real de wallet encontrada neste momento.',
        icon: Icons.verified_outlined,
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _infoPill(
                  'Wallets com divergencia',
                  _walletDivergences.length.toString(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._walletDivergences.take(8).map((row) {
              final diff =
                  (row['wallet_minus_confirmed_deposits'] as num?)
                      ?.toDouble() ??
                  0;
              final walletBalance =
                  (row['wallet_balance'] as num?)?.toDouble() ?? 0;
              final name = row['full_name']?.toString() ?? 'Sem nome';
              final phone = row['phone']?.toString() ?? 'Sem telefone';
              final role = _roleLabel(row['role']?.toString());

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name - $role',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phone,
                      style: const TextStyle(color: AppColors.neutralGray),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _infoPill(
                          'Saldo atual',
                          _money(walletBalance, currency: currency),
                        ),
                        _infoPill(
                          'Diferenca',
                          _money(diff, currency: currency),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  BarChartGroupData _barGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          width: 22,
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }

  Widget _richUserCard(Map<String, dynamic> profile) {
    final wallet = _walletsByUserId[profile['id']?.toString() ?? ''];
    final balance = _walletAmount(wallet);
    final currency = wallet?['currency']?.toString() ?? 'MZN';
    final role = profile['role']?.toString();
    final status = profile['kyc_status']?.toString() ?? 'approved';
    final isBlocked = profile['is_blocked'] == true;
    final userId = profile['id']?.toString();
    final isBusy = _isProcessingDecision && _processingUserId == userId;
    final displayName = profile['full_name']?.toString() ?? 'Sem nome';
    final phone = profile['phone']?.toString() ?? 'Sem telefone';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              onTap: () => _applySearch(displayName, tabIndex: 1),
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text(
                  displayName.trim().isNotEmpty == true
                      ? displayName.trim()[0].toUpperCase()
                      : '?',
                ),
              ),
              title: Text(displayName),
              subtitle: Text(
                '${_roleLabel(role)} - $phone\n'
                'KYC: $status - Wallet: ${_money(balance, currency: currency)}',
              ),
              isThreeLine: true,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.circle,
                    color: isBlocked ? Colors.red : _statusColor(status),
                    size: 12,
                  ),
                  const SizedBox(height: 4),
                  Text(isBlocked ? 'suspenso' : status),
                ],
              ),
            ),
            if ((profile['block_reason']?.toString().trim().isNotEmpty ??
                false))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'Motivo: ${profile['block_reason']}',
                  style: TextStyle(color: Colors.red[700]),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (role == 'courier' || role == 'restaurant')
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : () => _showKycDocuments(profile),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Ver docs'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _applySearch(displayName, tabIndex: 1),
                  icon: const Icon(Icons.search),
                  label: const Text('Pesquisar'),
                ),
                FilledButton.tonalIcon(
                  onPressed: isBusy ? null : () => _showSuspendDialog(profile),
                  icon: Icon(isBlocked ? Icons.lock_open : Icons.block),
                  label: Text(isBlocked ? 'Reativar' : 'Suspender'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kycCard(Map<String, dynamic> profile) {
    final userId = profile['id']?.toString();
    final isBusy = _isProcessingDecision && _processingUserId == userId;
    final status = profile['kyc_status']?.toString() ?? 'pending';
    final score = profile['verification_score']?.toString() ?? '0';
    final hasDocs = _hasKycDocuments(profile);
    final displayName = profile['full_name']?.toString() ?? 'Sem nome';
    final phone = profile['phone']?.toString() ?? 'Sem telefone';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              onTap: () => _applySearch(displayName, tabIndex: 2),
              contentPadding: EdgeInsets.zero,
              title: Text(
                displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(phone),
              trailing: Chip(
                label: Text(status),
                avatar: Icon(
                  Icons.shield_outlined,
                  color: _statusColor(status),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoPill('Score', score),
                _infoPill('Docs', hasDocs ? 'enviados' : 'vazios'),
                _infoPill(
                  'Submetido',
                  _dateLabel(profile['approval_submitted_at']?.toString()),
                ),
                _infoPill(
                  'SLA',
                  _dateLabel(profile['approval_sla_deadline']?.toString()),
                ),
              ],
            ),
            if ((profile['kyc_rejection_reason']
                    ?.toString()
                    .trim()
                    .isNotEmpty ??
                false)) ...[
              const SizedBox(height: 12),
              Text(
                'Motivo anterior: ${profile['kyc_rejection_reason']}',
                style: TextStyle(color: Colors.red[700]),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: isBusy ? null : () => _showKycDocuments(profile),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Ver documentos'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _applySearch(displayName, tabIndex: 2),
                  icon: const Icon(Icons.search),
                  label: const Text('Pesquisar'),
                ),
                FilledButton.icon(
                  onPressed: isBusy || status == 'approved'
                      ? null
                      : () => _decideKyc(profile: profile, decision: 'approve'),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(isBusy ? 'A processar...' : 'Aprovar'),
                ),
                if (status == 'pending')
                  FilledButton.tonalIcon(
                    onPressed: isBusy ? null : () => _showRejectDialog(profile),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Rejeitar'),
                  ),
                if (status == 'approved')
                  FilledButton.tonalIcon(
                    onPressed: isBusy
                        ? null
                        : () => _showSuspendDialog(profile),
                    icon: const Icon(Icons.block),
                    label: const Text('Suspender'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _adminActionCard(Map<String, dynamic> action) {
    final userId = action['user_id']?.toString();
    Map<String, dynamic>? profile;
    for (final item in _profiles) {
      if (item['id']?.toString() == userId) {
        profile = item;
        break;
      }
    }
    final subjectName =
        profile?['full_name']?.toString() ?? userId ?? 'Utilizador';
    final reason = action['reason']?.toString().trim();
    final actionText = _actionLabel(action['action']?.toString());
    final adminName = action['admin_name']?.toString().trim();
    final createdAt = _dateLabel(action['created_at']?.toString());
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.history)),
        title: Text('$actionText - $subjectName'),
        subtitle: Text(
          '${adminName?.isNotEmpty == true ? 'Por $adminName' : 'Acao administrativa'}\n'
          '${reason?.isNotEmpty == true ? reason : 'Sem motivo detalhado'}\n'
          '$createdAt',
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _orderAlertCard(Map<String, dynamic> order) {
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final fee = (order['platform_fee'] as num?)?.toDouble() ?? 0;
    final delivery = (order['delivery_fee'] as num?)?.toDouble() ?? 0;
    final status = order['status']?.toString() ?? 'pending';
    final paymentStatus = order['payment_status']?.toString() ?? 'pending';
    final shortId = (order['id']?.toString() ?? '').split('-').first;
    final restaurantName =
        order['restaurant_name']?.toString() ??
        order['restaurant']?['name']?.toString() ??
        'Restaurante';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Colors.orange.withValues(alpha: 0.12),
                child: const Icon(Icons.receipt_long, color: Colors.orange),
              ),
              title: Text('Pedido novo #$shortId'),
              subtitle: Text(
                'Status: $status - Pagamento: $paymentStatus\n'
                'Total: ${_money(total)} - Fee admin: ${_money(fee)} - Delivery: ${_money(delivery)}\n'
                '$restaurantName',
              ),
              isThreeLine: true,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _criticalOrderActions(order),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldStaffInviteCard(Map<String, dynamic> invite) {
    final accepted = invite['accepted_at'] != null;
    final active = invite['active'] != false;
    final status = accepted
        ? 'Aceite'
        : active
        ? 'Pendente'
        : 'Inativo';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accepted
              ? AppColors.primaryGreen.withValues(alpha: 0.12)
              : Colors.orange.withValues(alpha: 0.12),
          child: Icon(
            accepted ? Icons.check_circle_outline : Icons.mark_email_unread,
            color: accepted ? AppColors.primaryGreen : Colors.orange,
          ),
        ),
        title: Text(invite['full_name']?.toString() ?? 'Colaborador'),
        subtitle: Text(
          '${invite['phone']?.toString() ?? 'Sem telefone'}\n'
          '${_fieldRoleLabel(invite['role']?.toString())} - '
          '${invite['city']?.toString().trim().isNotEmpty == true ? invite['city'] : 'Sem cidade'}\n'
          'Convidado: ${_dateLabel(invite['invited_at']?.toString())}',
        ),
        isThreeLine: true,
        trailing: accepted
            ? Chip(label: Text(status))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: active
                        ? () => _resendFieldStaffInvite(invite)
                        : null,
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Reenviar'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Apagar convite',
                    onPressed: () => _deleteFieldStaffInvite(invite),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _fieldStaffProductivityCard(Map<String, dynamic> profile) {
    final staffId = profile['id']?.toString() ?? '';
    final actions = _adminActions.where((action) {
      return action['admin_id']?.toString() == staffId;
    }).toList();
    final approved = actions.where((action) {
      final value = action['action']?.toString();
      return value == 'approved' ||
          value == 'kyc_approved' ||
          value == 'field_approved_kyc';
    }).length;
    final rejected = actions.where((action) {
      final value = action['action']?.toString();
      return value == 'rejected' ||
          value == 'kyc_rejected' ||
          value == 'field_rejected_kyc';
    }).length;
    final suspended = actions.where((action) {
      return action['action']?.toString().contains('suspended') == true;
    }).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.badge)),
              title: Text(profile['full_name']?.toString() ?? 'Colaborador'),
              subtitle: Text(
                '${_fieldRoleLabel(profile['role']?.toString())} - '
                '${profile['phone']?.toString() ?? 'Sem telefone'}',
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoPill('Aprovados', '$approved'),
                _infoPill('Rejeitados', '$rejected'),
                _infoPill('Suspensoes', '$suspended'),
                _infoPill('Acoes', '${actions.length}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateFieldStaffInviteDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final cityController = TextEditingController(text: 'Maputo');
    String role = 'field_agent';
    bool saving = false;

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: !saving,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Adicionar colaborador'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome completo',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefone',
                        hintText: '84XXXXXXX',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: role,
                      decoration: const InputDecoration(labelText: 'Cargo'),
                      items: const [
                        DropdownMenuItem(
                          value: 'field_agent',
                          child: Text('Agente de Verificacao'),
                        ),
                        DropdownMenuItem(
                          value: 'support_agent',
                          child: Text('Suporte ao Cliente'),
                        ),
                        DropdownMenuItem(
                          value: 'ambassador',
                          child: Text('Embaixador'),
                        ),
                        DropdownMenuItem(
                          value: 'marketing_agent',
                          child: Text('Marketing e Publicidade'),
                        ),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setDialogState(
                              () => role = value ?? 'field_agent',
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cityController,
                      decoration: const InputDecoration(labelText: 'Cidade'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final phone = phoneController.text.trim();
                          final city = cityController.text.trim();
                          if (name.isEmpty || phone.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Informe nome e telefone.'),
                              ),
                            );
                            return;
                          }
                          setDialogState(() => saving = true);
                          try {
                            await _createFieldStaffInvite(
                              fullName: name,
                              phone: phone,
                              role: role,
                              city: city,
                            );
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          } catch (error) {
                            setDialogState(() => saving = false);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Falha ao criar convite/enviar OTP: $error',
                                ),
                              ),
                            );
                          }
                        },
                  child: Text(
                    saving ? 'A enviar OTP...' : 'Criar e enviar OTP',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    cityController.dispose();

    if (created == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convite criado e OTP enviado por SMS.')),
      );
      await _refresh();
    }
  }

  Future<void> _createFieldStaffInvite({
    required String fullName,
    required String phone,
    required String role,
    required String city,
  }) async {
    final adminId = _currentUserId ?? _supabase.auth.currentUser?.id;
    final normalizedPhone = _normalizeMozPhone(phone);
    final invite = await _supabase
        .from('field_staff_invites')
        .insert({
          'full_name': fullName,
          'phone': normalizedPhone,
          'role': role,
          'city': city.isEmpty ? null : city,
          'access_level': role,
          'invited_by': adminId,
        })
        .select('id')
        .single();
    final inviteId = invite['id']?.toString();

    final otpResponse = await _invokeFunctionDirect(
      'send-phone-otp',
      body: {
        'phone': normalizedPhone,
        'flow': 'login',
        'role': role,
        'full_name': fullName,
      },
    );
    if (otpResponse.status >= 400 ||
        otpResponse.json['success'] == false ||
        otpResponse.json['error'] != null) {
      if (inviteId != null && inviteId.isNotEmpty) {
        await _supabase.from('field_staff_invites').delete().eq('id', inviteId);
      }
      final message =
          otpResponse.json['error']?.toString() ??
          otpResponse.json['message']?.toString() ??
          'Convite criado, mas nao foi possivel enviar o OTP.';
      throw Exception(message);
    }
  }

  Future<void> _resendFieldStaffInvite(Map<String, dynamic> invite) async {
    final phone = _normalizeMozPhone(invite['phone']?.toString() ?? '');
    final role = invite['role']?.toString() ?? 'field_agent';
    final fullName = invite['full_name']?.toString() ?? 'Colaborador DeliGo';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convite sem telefone valido.')),
      );
      return;
    }

    try {
      final response = await _invokeFunctionDirect(
        'send-phone-otp',
        body: {
          'phone': phone,
          'flow': 'login',
          'role': role,
          'full_name': fullName,
        },
      );
      if (response.status >= 400 ||
          response.json['success'] == false ||
          response.json['error'] != null) {
        throw Exception(
          response.json['error']?.toString() ?? response.json.toString(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Convite reenviado para $phone.')));
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao reenviar convite: $error')),
      );
    }
  }

  Future<void> _deleteFieldStaffInvite(Map<String, dynamic> invite) async {
    final inviteId = invite['id']?.toString();
    final name = invite['full_name']?.toString() ?? 'este colaborador';
    if (inviteId == null || inviteId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Convite sem identificador valido.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar convite?'),
        content: Text('O convite pendente de $name sera removido.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _supabase.from('field_staff_invites').delete().eq('id', inviteId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Convite apagado.')));
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao apagar convite: $error')));
    }
  }

  String _normalizeMozPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('258')) return '+$digits';
    if (digits.length == 9) return '+258$digits';
    return raw.trim();
  }

  String _fieldRoleLabel(String? role) {
    switch (role) {
      case 'field_agent':
        return 'Agente de Verificacao';
      case 'support_agent':
        return 'Suporte ao Cliente';
      case 'ambassador':
        return 'Embaixador';
      case 'marketing_agent':
        return 'Marketing e Publicidade';
      case 'admin':
        return 'Admin';
      default:
        return role?.replaceAll('_', ' ') ?? 'Colaborador';
    }
  }

  Future<_DirectFunctionResponse> _invokeFunctionDirect(
    String functionName, {
    required Map<String, dynamic> body,
  }) async {
    final token = (_supabase.auth.currentSession?.accessToken ?? '').trim();
    if (token.isEmpty) {
      throw Exception('Sessao expirada no admin. Entre novamente.');
    }

    final supabaseUrl = AppEnv.supabaseUrl.trim();
    final anonKey = AppEnv.supabaseAnonKey.trim();
    if (supabaseUrl.isEmpty || anonKey.isEmpty) {
      throw Exception('Configuracao do Supabase incompleta no admin.');
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

  Widget _infoPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.10),
        ),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _filterChip(
    String label,
    String value,
    String selectedValue,
    ValueChanged<String> onSelected,
  ) {
    return ChoiceChip(
      label: Text(label),
      selected: selectedValue == value,
      selectedColor: AppColors.primaryGreen.withValues(alpha: 0.14),
      checkmarkColor: AppColors.primaryGreen,
      labelStyle: TextStyle(
        color: selectedValue == value ? AppColors.primaryGreen : null,
        fontWeight: selectedValue == value ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selectedValue == value
            ? AppColors.primaryGreen.withValues(alpha: 0.35)
            : AppColors.borderGray,
      ),
      onSelected: (_) => onSelected(value),
    );
  }
}

class _DirectFunctionResponse {
  const _DirectFunctionResponse({required this.status, required this.json});

  final int status;
  final Map<String, dynamic> json;
}
