import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

import '../../config/theme/app_colors.dart';
import '../../shared/widgets/tap_scale.dart';
import '../../services/wallet_deposit_service.dart';
import '../../shared/utils/ecosystem_test_persona.dart';
import '../../shared/utils/mozambique_wallet_validation.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key, this.initialSection, this.initialDepositId});

  final String? initialSection;
  final String? initialDepositId;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  static const double _minimumDepositMzn = 10;
  static const List<String> _supportedMethods = ['mpesa', 'emola', 'mkesh'];
  static const double _depositFeePercent = 0.03;
  static const double _withdrawFeePercent = 0.03;
  static const List<double> _quickWithdrawAmounts = [50, 100, 500, 1000, 2500];

  final supabase = Supabase.instance.client;
  final WalletDepositService _depositService = WalletDepositService();
  RealtimeChannel? _walletChannel;
  RealtimeChannel? _depositChannel;
  RealtimeChannel? _ledgerChannel;
  RealtimeChannel? _withdrawalChannel;
  Timer? _realtimeRefreshDebounce;
  String? _subscribedUserId;
  String? _subscribedWalletId;

  bool _loading = true;
  bool _walletDataLoaded = false;
  String? _walletLoadError;
  int _walletLoadVersion = 0;
  int _activeWalletLoadRequest = 0;
  bool _walletReloadQueued = false;
  bool _depositing = false;
  String? _walletId;
  bool _walletIsCanonical = false;
  double _balance = 0;
  double _availableBalance = 0;
  double _pendingBalance = 0;
  String _currency = 'MZN';
  String? _fullName;
  String _phone = '';
  String _method = 'm-pesa';
  String _role = 'client';
  List<Map<String, dynamic>> _orderPayments = [];
  List<Map<String, dynamic>> _deposits = [];
  List<Map<String, dynamic>> _withdrawals = [];
  List<Map<String, dynamic>> _ledgerEntries = [];
  List<Map<String, dynamic>> _tickets = [];
  bool _withdrawing = false;
  bool _isTestWallet = false;
  String? _checkingDepositId;
  String _depositStatusFilter = 'all';
  String _withdrawalStatusFilter = 'all';
  String _ticketStatusFilter = 'upcoming';

  final _amountController = TextEditingController();
  final _phoneController = TextEditingController();
  final _withdrawAmountController = TextEditingController();
  final _transferPhoneController = TextEditingController();
  final _transferAmountController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _depositSectionKey = GlobalKey();
  final GlobalKey _withdrawSectionKey = GlobalKey();
  final GlobalKey _historySectionKey = GlobalKey();
  final GlobalKey _ticketsSectionKey = GlobalKey();

  String get _initialSection =>
      widget.initialSection?.trim().toLowerCase() ?? '';

  bool get _showOnlyDeposit => _initialSection == 'deposit';

  bool get _showOnlyWithdraw => _initialSection == 'withdraw';

  bool get _showOnlyHistory => _initialSection == 'history';

  bool get _showOnlyTickets => _initialSection == 'tickets';

  bool get _hasFocusedSection =>
      _showOnlyDeposit ||
      _showOnlyWithdraw ||
      _showOnlyHistory ||
      _showOnlyTickets;

  bool get _isClientRole => _role == 'client' || _role == 'customer';

  double _netDepositAmount(Map<String, dynamic> deposit) {
    final amount = (deposit['amount'] as num?)?.toDouble() ?? 0;
    final net = (deposit['net_amount'] as num?)?.toDouble();
    if (net != null && net > 0) return net;
    final fee =
        (deposit['gateway_fee'] as num?)?.toDouble() ?? _depositFee(amount);
    return (amount - fee).clamp(0, double.infinity);
  }

  bool _isConfirmedDeposit(String status) {
    switch (status) {
      case 'completed':
      case 'confirmed':
      case 'paid':
      case 'success':
      case 'succeeded':
        return true;
      default:
        return false;
    }
  }

  bool _isPendingDeposit(String status) {
    switch (status) {
      case 'pending':
      case 'processing':
      case 'in_progress':
        return true;
      default:
        return false;
    }
  }

  ({double confirmed, double pending}) _depositTotals(
    List<Map<String, dynamic>> deposits,
  ) {
    double confirmed = 0;
    double pending = 0;
    for (final deposit in deposits) {
      final status = (deposit['status']?.toString() ?? '').toLowerCase();
      final value = _netDepositAmount(deposit);
      if (_isConfirmedDeposit(status)) {
        confirmed += value;
      } else if (_isPendingDeposit(status)) {
        pending += value;
      }
    }
    return (confirmed: confirmed, pending: pending);
  }

  String get _registeredWalletPhone {
    final fromProfile = _phone.trim();
    if (fromProfile.isNotEmpty) return fromProfile;
    final fromField = _phoneController.text.trim();
    if (fromField.isNotEmpty) return fromField;
    return supabase.auth.currentUser?.phone?.trim() ?? '';
  }

  String get _lockedWalletMethod =>
      _inferMethodFromPhone(_registeredWalletPhone);

  bool get _hasRegisteredWalletPhone =>
      _registeredWalletPhone.trim().length >= 9;

  @override
  void initState() {
    super.initState();
    _loadWallet();
    final depositId = widget.initialDepositId?.trim();
    if (depositId != null && depositId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_checkDepositStatusById(depositId));
      });
    }
  }

  @override
  void dispose() {
    _teardownRealtimeSubscriptions();
    _realtimeRefreshDebounce?.cancel();
    _amountController.dispose();
    _phoneController.dispose();
    _withdrawAmountController.dispose();
    _transferPhoneController.dispose();
    _transferAmountController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _fetchWalletByUserId(String userId) async {
    try {
      final rows = await supabase
          .from('wallets')
          .select('id, balance, available_balance, pending_balance, currency')
          .eq('user_id', userId)
          .order('updated_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        return {
          ...Map<String, dynamic>.from(rows.first as Map),
          'canonical': false,
        };
      }
      final canonicalRows = await supabase
          .schema('payments')
          .from('wallet_accounts')
          .select(
            'id, available_balance_minor, pending_balance_minor, currency_code',
          )
          .eq('owner_user_id', userId)
          .isFilter('app_id', null)
          .eq('account_type', 'user')
          .eq('status', 'active')
          .limit(1);
      if (canonicalRows.isNotEmpty) {
        final row = Map<String, dynamic>.from(canonicalRows.first as Map);
        final available =
            (row['available_balance_minor'] as num?)?.toDouble() ?? 0;
        final pending = (row['pending_balance_minor'] as num?)?.toDouble() ?? 0;
        return {
          'id': row['id'],
          'balance': (available + pending) / 100,
          'available_balance': available / 100,
          'pending_balance': pending / 100,
          'currency': row['currency_code'] ?? 'MZN',
          'canonical': true,
        };
      }
      return null;
    } catch (e) {
      debugPrint(
        'WalletPage: fallback ao buscar carteira resumida para userId=$userId: $e',
      );
      final rows = await supabase
          .from('wallets')
          .select('id, balance, available_balance, pending_balance, currency')
          .eq('user_id', userId)
          .order('updated_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        return Map<String, dynamic>.from(rows.first as Map);
      }
      return null;
    }
  }

  void _scheduleRealtimeRefresh() {
    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      unawaited(_loadWallet(showLoader: false));
    });
  }

  void _removeChannel(RealtimeChannel? channel) {
    if (channel == null) return;
    supabase.removeChannel(channel);
  }

  void _teardownRealtimeSubscriptions() {
    _removeChannel(_walletChannel);
    _removeChannel(_depositChannel);
    _removeChannel(_ledgerChannel);
    _removeChannel(_withdrawalChannel);
    _walletChannel = null;
    _depositChannel = null;
    _ledgerChannel = null;
    _withdrawalChannel = null;
    _subscribedUserId = null;
    _subscribedWalletId = null;
  }

  void _ensureRealtimeSubscriptions({
    required String userId,
    String? walletId,
  }) {
    if (_subscribedUserId == userId && _subscribedWalletId == walletId) {
      return;
    }

    _teardownRealtimeSubscriptions();
    _subscribedUserId = userId;
    _subscribedWalletId = walletId;

    _walletChannel = supabase.channel('wallet-page-wallet-$userId');
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
            _scheduleRealtimeRefresh();
          },
        )
        .subscribe();

    _ledgerChannel = supabase.channel('wallet-page-ledger-$userId');
    _ledgerChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallet_ledger',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleRealtimeRefresh();
          },
        )
        .subscribe();

    _withdrawalChannel = supabase.channel('wallet-page-withdrawals-$userId');
    _withdrawalChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'withdrawal_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleRealtimeRefresh();
          },
        )
        .subscribe();

    if (walletId == null || walletId.isEmpty) {
      return;
    }

    _depositChannel = supabase.channel('wallet-page-deposits-$walletId');
    _depositChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallet_deposits',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'wallet_id',
            value: walletId,
          ),
          callback: (_) {
            if (!mounted) return;
            _scheduleRealtimeRefresh();
          },
        )
        .subscribe();
  }

  Future<void> _loadWallet({bool showLoader = true}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (_activeWalletLoadRequest != 0) {
      _walletReloadQueued = true;
      debugPrint(
        '[WALLET_LOAD] request coalesced active=$_activeWalletLoadRequest',
      );
      return;
    }

    final requestId = ++_walletLoadVersion;
    final hasSnapshot = _walletDataLoaded;
    _activeWalletLoadRequest = requestId;
    debugPrint(
      '[WALLET_LOAD] init request=$requestId refresh=${!showLoader} snapshot=$hasSnapshot',
    );
    if (!hasSnapshot && showLoader && mounted) {
      setState(() {
        _loading = true;
        _walletLoadError = null;
      });
    }
    try {
      debugPrint('[WALLET_LOAD] profile request=$requestId start');
      final baseData = await Future.wait<Object?>([
        supabase
            .from('profiles')
            .select(
              'full_name, phone, preferred_payment_method, payment_contact, role',
            )
            .eq('id', user.id)
            .maybeSingle(),
        _fetchWalletByUserId(user.id),
      ]);
      final profile = baseData[0] as Map<String, dynamic>?;
      Map<String, dynamic>? wallet = baseData[1] as Map<String, dynamic>?;
      debugPrint('[WALLET_LOAD] profile request=$requestId complete');
      debugPrint(
        '[WALLET_LOAD] wallet request=$requestId complete exists=${wallet != null}',
      );

      if (wallet == null) {
        debugPrint('[WALLET_LOAD] wallet request=$requestId ensure start');
        await _ensureWallet(updateState: false);
        wallet = await _fetchWalletByUserId(user.id);
        debugPrint(
          '[WALLET_LOAD] wallet request=$requestId ensure complete exists=${wallet != null}',
        );
      }
      final loadedWallet = wallet;
      if (loadedWallet == null || loadedWallet['balance'] is! num) {
        throw StateError('A carteira ainda não devolveu um saldo válido.');
      }

      final name = (profile?['full_name'] as String?)?.trim();
      final role =
          (profile?['role'] as String?)?.trim().toLowerCase() ?? 'client';
      final isClientRole = role == 'client' || role == 'customer';
      _walletIsCanonical = loadedWallet['canonical'] == true;
      String? restaurantWalletPhone;
      if (role == 'restaurant') {
        try {
          final restaurant = await supabase
              .from('restaurants')
              .select('payment_wallet_number')
              .eq('owner_id', user.id)
              .order('created_at', ascending: true)
              .limit(1)
              .maybeSingle();
          restaurantWalletPhone = restaurant?['payment_wallet_number']
              ?.toString()
              .trim();
        } catch (e) {
          debugPrint(
            'WalletPage: erro ao carregar payment_wallet_number do restaurante: $e',
          );
          restaurantWalletPhone = null;
        }
      }

      final phoneCandidates = <String>[
        (profile?['payment_contact'] as String?)?.trim() ?? '',
        restaurantWalletPhone ?? '',
        (profile?['phone'] as String?)?.trim() ?? '',
        (user.userMetadata?['phone'] as String?)?.trim() ?? '',
        user.phone?.trim() ?? '',
      ];
      final phone = phoneCandidates.firstWhere(
        (candidate) =>
            candidate.isNotEmpty &&
            MozambiqueWalletValidation.isValidMsisdn(candidate),
        orElse: () => phoneCandidates.firstWhere(
          (candidate) => candidate.isNotEmpty,
          orElse: () => '',
        ),
      );
      final preferredMethod = (profile?['preferred_payment_method'] as String?)
          ?.trim()
          .toLowerCase();
      final walletId = loadedWallet['id']?.toString();
      debugPrint('[WALLET_LOAD] withdrawals/history request=$requestId start');
      final history = await Future.wait<List<Map<String, dynamic>>>([
        if (walletId != null)
          _depositService.getUserDeposits(walletId: walletId)
        else
          Future.value(<Map<String, dynamic>>[]),
        _loadOrderPayments(user.id),
        if (isClientRole)
          _loadTickets(user.id)
        else
          Future.value(<Map<String, dynamic>>[]),
        _depositService.getUserWithdrawals(),
        _loadLedgerEntries(user.id, walletId),
      ]);
      final deposits = history[0];
      final orderPayments = history[1];
      final tickets = history[2];
      final withdrawals = history[3];
      final ledgerEntries = history[4];
      debugPrint(
        '[WALLET_LOAD] withdrawals/history request=$requestId complete withdrawals=${withdrawals.length}',
      );
      if (requestId != _walletLoadVersion) {
        debugPrint('[WALLET_LOAD] request=$requestId stale; commit skipped');
        return;
      }
      _ensureRealtimeSubscriptions(userId: user.id, walletId: walletId);
      if (!mounted) return;
      setState(() {
        _fullName = name?.isNotEmpty == true ? name : null;
        _phone = phone;
        _phoneController.text = phone;
        _role = role;
        _method = _isClientRole
            ? _inferMethodFromPhone(phone)
            : (_supportedMethods.contains(preferredMethod)
                  ? preferredMethod!
                  : _inferMethodFromPhone(phone));
        _walletId = walletId;
        _isTestWallet = EcosystemTestPersona.matches(user);
        _balance = (loadedWallet['balance'] as num).toDouble();
        _availableBalance =
            (loadedWallet['available_balance'] as num?)?.toDouble() ?? _balance;
        _pendingBalance =
            (loadedWallet['pending_balance'] as num?)?.toDouble() ??
            (isClientRole ? _depositTotals(deposits).pending : 0);
        _currency = (loadedWallet['currency'] as String?) ?? 'MZN';
        _orderPayments = orderPayments;
        _tickets = tickets;
        _deposits = deposits;
        _withdrawals = withdrawals;
        _ledgerEntries = ledgerEntries;
        _loading = false;
        _walletDataLoaded = true;
        _walletLoadError = null;
      });
      debugPrint(
        '[WALLET_LOAD] render final request=$requestId nameAvailable=${name?.isNotEmpty == true} walletAvailable=true withdrawals=${withdrawals.length}',
      );
      // Reconcile recent pending deposits after returning from PaySuite. The
      // webhook remains authoritative, while this repairs a missed webhook
      // when the user reopens the wallet.
      unawaited(_reconcilePendingDeposits(deposits));
      _scrollToInitialSection();
    } catch (e) {
      debugPrint('[WALLET_LOAD] error request=$requestId: $e');
      if (requestId != _walletLoadVersion) return;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _walletLoadError = 'Não foi possível atualizar a carteira.';
      });
    } finally {
      if (_activeWalletLoadRequest == requestId) {
        _activeWalletLoadRequest = 0;
      }
      if (_walletReloadQueued && mounted) {
        _walletReloadQueued = false;
        scheduleMicrotask(() {
          if (mounted) unawaited(_loadWallet(showLoader: false));
        });
      }
    }
  }

  Future<void> _reconcilePendingDeposits(
    List<Map<String, dynamic>> deposits,
  ) async {
    final pending = deposits
        .where(
          (row) => (row['status']?.toString().toLowerCase() ?? '') == 'pending',
        )
        .take(3);
    var reconciled = false;
    for (final deposit in pending) {
      final id = deposit['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      final status = await _depositService.checkDepositStatus(id);
      if (status.status == 'completed') reconciled = true;
    }
    if (reconciled && mounted) {
      await _loadWallet(showLoader: false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadOrderPayments(String userId) async {
    final response = await supabase
        .from('orders')
        .select('id,total_amount,status,created_at,delivery_fee')
        .or('client_id.eq.$userId,customer_id.eq.$userId')
        .order('created_at', ascending: false)
        .limit(20);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> _loadTickets(String userId) async {
    final response = await supabase
        .from('marketing_event_tickets')
        .select(
          'id,event_id,buyer_id,ticket_code,qr_code,ticket_type_id,ticket_type_name,price,status,sold_at,used_at,'
          'marketing_events(title,event_date,event_time,location,poster_url,banner_url,restaurants(name,phone))',
        )
        .eq('buyer_id', userId)
        .order('sold_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> _loadLedgerEntries(
    String userId,
    String? walletId,
  ) async {
    // The private `payments` schema is not exposed through PostgREST.
    // Use the public ledger here so PGRST106 cannot break wallet refreshes.
    final response = await supabase
        .from('wallet_ledger')
        .select()
        .or(
          walletId != null
              ? 'user_id.eq.$userId,wallet_id.eq.$walletId'
              : 'user_id.eq.$userId',
        )
        .order('created_at', ascending: false)
        .limit(30);

    return List<Map<String, dynamic>>.from(response);
  }

  String _inferMethodFromPhone(String phone) {
    switch (MozambiqueWalletValidation.inferMethod(phone)) {
      case MozambiqueWalletMethod.mkesh:
        return 'mkesh';
      case MozambiqueWalletMethod.mpesa:
        return 'm-pesa';
      case MozambiqueWalletMethod.emola:
        return 'emola';
      case null:
        return _method;
    }
  }

  String _operatorLabel(String phone) {
    final normalized = phone
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^258'), '');
    if (normalized.startsWith('82') || normalized.startsWith('83')) {
      return 'mCel/Tmcel';
    }
    if (normalized.startsWith('84') || normalized.startsWith('85')) {
      return 'Vodacom';
    }
    if (normalized.startsWith('86') || normalized.startsWith('87')) {
      return 'e-Mola';
    }
    return 'não identificada';
  }

  String _operatorAsset(String phone) {
    final normalized = phone
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^258'), '');
    if (normalized.startsWith('82') || normalized.startsWith('83')) {
      return 'assets/payments/mkesh.jpg';
    }
    if (normalized.startsWith('84') || normalized.startsWith('85')) {
      return 'assets/payments/mpesa.png';
    }
    if (normalized.startsWith('86') || normalized.startsWith('87')) {
      return 'assets/payments/emola.png';
    }
    return 'assets/payments/emola.png';
  }

  Widget _buildDetectedOperator(String phone) {
    final label = _operatorLabel(phone);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            _operatorAsset(phone),
            width: 48,
            height: 34,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.phone_android),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Operadora detectada: $label',
            style: const TextStyle(
              color: AppColors.neutralGray,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _normalizeMozPhone(String value) {
    final digits = MozambiqueWalletValidation.normalizeMsisdn(value);
    if (digits.length == 9 &&
        MozambiqueWalletValidation.isValidMsisdn(digits)) {
      return '+258$digits';
    }
    return value.trim();
  }

  double _minWithdrawForRole() {
    return 10;
  }

  double _maxWithdrawForRole() {
    switch (_role) {
      case 'courier':
        return 1500;
      case 'restaurant':
        return 25000;
      case 'client':
      case 'customer':
      default:
        return 100;
    }
  }

  double _feeForAmount(double amount) {
    return (amount * _withdrawFeePercent);
  }

  double _netForAmount(double amount) {
    return amount - _feeForAmount(amount);
  }

  double get minLimit => _minWithdrawForRole();

  double get maxLimit => _maxWithdrawForRole();

  String get methodLabel => _method == 'm-pesa'
      ? 'M-Pesa'
      : _method == 'mkesh'
      ? 'm-Kesh'
      : 'e-Mola';

  String _methodLabelFor(String method) => method == 'm-pesa'
      ? 'M-Pesa'
      : method == 'mkesh'
      ? 'm-Kesh'
      : 'e-Mola';

  Future<bool> _confirmWithdrawal({
    required double amount,
    required double fee,
    required double net,
    required String method,
  }) async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar levantamento?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Valor: $_currency ${amount.toStringAsFixed(2)}'),
              const SizedBox(height: 6),
              Text('Comissao (3%): $_currency ${fee.toStringAsFixed(2)}'),
              const SizedBox(height: 6),
              Text('Total a receber: $_currency ${net.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              Text('O valor sera enviado para: ${_methodLabelFor(method)}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sim, continuar'),
            ),
          ],
        );
      },
    );
    return decision == true;
  }

  Future<void> _submitDeposit() async {
    final messenger = ScaffoldMessenger.of(context);

    if (_walletId == null || _walletIsCanonical) {
      await _ensureWallet();
      final user = supabase.auth.currentUser;
      if (user != null) {
        try {
          final wallet = await supabase
              .from('wallets')
              .select(
                'id, balance, available_balance, pending_balance, currency',
              )
              .eq('user_id', user.id)
              .maybeSingle();
          if (wallet != null) {
            setState(() {
              _walletId = wallet['id']?.toString();
              _walletIsCanonical = false;
              _balance = (wallet['balance'] as num?)?.toDouble() ?? 0;
              _availableBalance =
                  (wallet['available_balance'] as num?)?.toDouble() ?? _balance;
              _pendingBalance =
                  (wallet['pending_balance'] as num?)?.toDouble() ?? 0;
              _currency = (wallet['currency'] as String?) ?? 'MZN';
            });
          } else {
            setState(() {
              _walletId = null;
              _walletIsCanonical = false;
            });
          }
        } catch (e) {
          debugPrint(
            'WalletPage: erro ao recarregar carteira apos ensure-wallet: $e',
          );
        }
      }
    }

    if (!mounted) return;
    if (_walletId == null) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Carteira nao criada'),
          content: const Text(
            'Nao foi possivel criar sua carteira agora. Tente novamente em instantes ou saia e entre novamente na conta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    final phone = _registeredWalletPhone;

    if (amount == null || amount < _minimumDepositMzn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O depósito mínimo é 10 MT.')),
      );
      return;
    }
    final normalizedPhone = _normalizeMozPhone(phone);
    if (normalizedPhone.isEmpty ||
        !MozambiqueWalletValidation.isValidMsisdn(normalizedPhone)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Informe um numero valido de Mocambique.'),
        ),
      );
      return;
    }

    final inferredMethod = _inferMethodFromPhone(normalizedPhone);
    if (inferredMethod != _method) {
      setState(() => _method = inferredMethod);
    }
    setState(() => _depositing = true);
    final result = await _depositService.createDeposit(
      walletId: _walletId!,
      amount: amount,
      paymentMethod: inferredMethod,
      phone: normalizedPhone,
    );
    if (!mounted) return;
    setState(() => _depositing = false);

    if (result.success) {
      _amountController.clear();
      // Open the provider checkout immediately. The provider still owns the
      // payment confirmation; this screen never credits the wallet locally.
      final checkoutUrl = result.checkoutUrl;
      if (checkoutUrl != null && checkoutUrl.trim().isNotEmpty) {
        final uri = Uri.tryParse(checkoutUrl);
        if (uri != null) {
          final opened = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (!opened && mounted) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Não foi possível abrir o checkout.')),
            );
          }
        }
      } else if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              result.instructions ??
                  result.message ??
                  'Depósito iniciado. Confirme o pagamento no telemóvel.',
            ),
          ),
        );
      }

      // Reconcile with the backend; a provider-confirmed deposit is the only
      // event allowed to update the canonical wallet balance.
      if (result.depositId != null) {
        final depositId = result.depositId!;
        await _depositService.checkDepositStatus(depositId);
        unawaited(_monitorDepositConfirmation(depositId));
      }
      await _loadWallet();
    } else {
      final failedMessage = _friendlyDepositFailureMessage(
        result.error,
        providerStatus: result.providerStatus,
        providerError: result.providerError,
      );

      messenger.showSnackBar(SnackBar(content: Text(failedMessage)));

      if (result.depositId != null) {
        await _loadWallet();
      }
    }
  }

  Future<void> _monitorDepositConfirmation(String depositId) async {
    const interval = Duration(seconds: 10);
    final deadline = DateTime.now().add(
      const Duration(seconds: WalletDepositService.depositTimeoutSeconds),
    );

    while (mounted && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(interval);
      if (!mounted) return;

      final status = await _depositService.checkDepositStatus(depositId);
      if (status.status == 'completed') {
        await _loadWallet(showLoader: false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Deposito confirmado. O saldo ja foi atualizado.'),
            backgroundColor: AppColors.successGreen,
          ),
        );
        return;
      }
      if (status.status == 'failed') return;
    }
  }

  String _friendlyDepositFailureMessage(
    String? fallback, {
    String? providerStatus,
    String? providerError,
  }) {
    final normalizedProviderError = providerError?.trim().toLowerCase() ?? '';
    final normalizedFallback = fallback?.trim().toLowerCase() ?? '';

    if (normalizedProviderError.contains('504')) {
      return 'O parceiro de pagamento demorou a responder. Tente novamente em instantes ou confirme se o pedido apareceu no telemovel.';
    }

    if (normalizedFallback.contains('conta ainda nao confirmada')) {
      return 'A sua conta ainda nao foi confirmada para carteira. Entre novamente com o codigo SMS para verificar o telefone e tente o deposito outra vez.';
    }

    if (normalizedProviderError.contains('temporariamente indispon')) {
      return 'O canal de pagamento esta temporariamente indisponivel no parceiro. Tente novamente mais tarde.';
    }

    if (normalizedProviderError.contains('transaction failed')) {
      return 'O provedor recusou a cobranca. Confirme saldo, PIN e se o numero esta ativo para ${_method.toUpperCase()}.';
    }

    if ((providerStatus ?? '').trim().toUpperCase() == 'FAILED') {
      return 'O deposito foi recusado pelo provedor. Tente novamente ou use outro numero movel.';
    }

    if (normalizedFallback.contains('sessao') ||
        normalizedFallback.contains('unauthorized')) {
      return 'A sua sessao terminou. Entre novamente e tente o deposito.';
    }
    if (normalizedFallback.contains('gateway') ||
        normalizedFallback.contains('servidor') ||
        normalizedFallback.contains('function')) {
      return fallback?.trim().isNotEmpty == true
          ? fallback!.trim()
          : 'Nao foi possivel iniciar o deposito agora. Tente novamente.';
    }
    if (fallback?.trim().isNotEmpty == true &&
        fallback!.trim().toLowerCase() != 'falha ao iniciar deposito') {
      return fallback.trim();
    }
    return 'O deposito nao foi iniciado. Confirme o numero verificado e tente novamente.';
  }

  Future<void> _ensureWallet({bool updateState = true}) async {
    try {
      var session = supabase.auth.currentSession;
      if (session == null || session.isExpired) {
        session = (await supabase.auth.refreshSession()).session;
      }
      final token = session?.accessToken;
      final response = await supabase.functions.invoke(
        'ensure-wallet',
        headers: token != null && token.isNotEmpty
            ? {'Authorization': 'Bearer $token'}
            : null,
        body: {
          'phone': _phoneController.text.trim().isEmpty
              ? _phone
              : _phoneController.text.trim(),
        },
      );
      if (response.data?['wallet'] != null) {
        final wallet = response.data['wallet'] as Map<String, dynamic>;
        if (mounted && updateState) {
          setState(() {
            _walletId = wallet['id']?.toString();
            _walletIsCanonical = false;
            _balance = (wallet['balance'] as num?)?.toDouble() ?? _balance;
            _availableBalance =
                (wallet['available_balance'] as num?)?.toDouble() ?? _balance;
            _pendingBalance =
                (wallet['pending_balance'] as num?)?.toDouble() ??
                _pendingBalance;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('WalletPage: erro ao garantir carteira via ensure-wallet: $e');
    }

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final wallet = await _fetchWalletByUserId(user.id);
      if (wallet != null && mounted && updateState) {
        final walletMap = wallet;
        setState(() {
          _walletId = walletMap['id']?.toString();
          _balance = (walletMap['balance'] as num?)?.toDouble() ?? 0;
          _availableBalance =
              (walletMap['available_balance'] as num?)?.toDouble() ?? _balance;
          _pendingBalance =
              (walletMap['pending_balance'] as num?)?.toDouble() ?? 0;
          _currency = (walletMap['currency'] as String?) ?? 'MZN';
        });
      }
    } catch (e) {
      debugPrint(
        'WalletPage: erro ao buscar carteira existente como fallback: $e',
      );
    }
  }

  Future<void> _showOperatorDialog() async {
    final phone = _registeredWalletPhone;
    setState(() => _method = _inferMethodFromPhone(phone));
    await _submitDeposit();
  }

  // Show the withdrawal flow for every wallet. The backend still validates
  // the registered/confirmed phone before creating the PaySuite payout.
  bool get _canWithdraw => _walletId != null;

  void _scrollToInitialSection() {
    final section = widget.initialSection?.trim().toLowerCase();
    if (section == null || section.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetKey = switch (section) {
        'deposit' => _depositSectionKey,
        'withdraw' => _withdrawSectionKey,
        'history' => _historySectionKey,
        'tickets' => _ticketsSectionKey,
        _ => null,
      };
      final targetContext = targetKey?.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _dashboardRouteForRole() {
    switch (_role) {
      case 'courier':
        return '/courier-dashboard';
      case 'restaurant':
        return '/restaurant-dashboard';
      case 'admin':
        return '/admin-dashboard';
      case 'client':
      case 'customer':
      default:
        return '/client-dashboard';
    }
  }

  Future<void> _submitWithdrawal() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_walletId == null) {
      await _ensureWallet();
      if (!mounted) return;
      if (_walletId == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Estamos a preparar a carteira. Tente novamente em instantes.',
            ),
          ),
        );
        return;
      }
    }
    final amount = double.tryParse(
      _withdrawAmountController.text.replaceAll(',', '.'),
    );
    final phone = _registeredWalletPhone;

    final minLimit = _minWithdrawForRole();
    final maxLimit = _maxWithdrawForRole();

    if (amount != null && (amount < minLimit || amount > maxLimit)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Valor invalido. Limites: ${minLimit.toStringAsFixed(0)} a ${maxLimit.toStringAsFixed(0)} MZN por dia.',
          ),
        ),
      );
      return;
    }

    if (amount == null || amount <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Informe um valor valido para levantar.')),
      );
      return;
    }

    if (amount > _availableBalance) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Saldo disponivel insuficiente para este levantamento.',
          ),
        ),
      );
      return;
    }

    if (phone.isEmpty || phone.length < 9) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Informe um numero valido para receber.')),
      );
      return;
    }

    final normalizedPhone = _normalizeMozPhone(phone);
    if (!MozambiqueWalletValidation.isValidMsisdn(normalizedPhone)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Numero invalido. Use +258XXXXXXXXX.')),
      );
      return;
    }

    final inferredMethod = _inferMethodFromPhone(normalizedPhone);
    if (inferredMethod != _method) {
      setState(() => _method = inferredMethod);
    }
    final resolvedMethod = inferredMethod;

    setState(() => _withdrawing = true);
    final result = await _depositService.createWithdrawal(
      amount: amount,
      method: resolvedMethod,
      phone: normalizedPhone,
      walletId: _walletId,
    );
    if (!mounted) return;
    setState(() => _withdrawing = false);

    if (result.success) {
      final outcome = result.outcome;
      if (outcome != WalletWithdrawalOutcome.failed) {
        _withdrawAmountController.clear();
      }
      await _loadWallet(showLoader: false);
      if (!mounted) return;
      final String message;
      final Color? backgroundColor;
      switch (outcome) {
        case WalletWithdrawalOutcome.completed:
          message = 'Levantamento realizado com sucesso.';
          backgroundColor = AppColors.successGreen;
        case WalletWithdrawalOutcome.pending:
          message =
              'Levantamento pendente. Aguardando confirmação do parceiro.';
          backgroundColor = Colors.orange.shade800;
        case WalletWithdrawalOutcome.failed:
          message =
              'Levantamento não concluído. Consulte o histórico para ver o estado.';
          backgroundColor = Colors.red.shade700;
        case WalletWithdrawalOutcome.unknown:
          message =
              'Estado do levantamento não confirmado. Consulte o histórico antes de tentar novamente.';
          backgroundColor = Colors.orange.shade800;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: backgroundColor),
      );
      return;
    }

    await _loadWallet(showLoader: false);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.normalizedError ??
              result.error ??
              'Falha ao solicitar levantamento.',
        ),
      ),
    );
  }

  Future<void> _showTransferDialog() async {
    _transferPhoneController.clear();
    _transferAmountController.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transferir saldo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _transferPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Número do destinatário',
              ),
            ),
            TextField(
              controller: _transferAmountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Valor (MT)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final amount = double.tryParse(
      _transferAmountController.text.replaceAll(',', '.'),
    );
    final phone = _transferPhoneController.text.trim();
    if (phone.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o número e um valor válido.')),
      );
      return;
    }
    WalletRecipient? recipient;
    try {
      recipient = await _depositService.findWalletRecipient(phone);
    } catch (_) {
      recipient = null;
    }
    if (!mounted) return;
    if (recipient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não encontramos um utilizador activo com esse número.',
          ),
        ),
      );
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar destinatário'),
        content: Text(
          'Enviar ${amount.toStringAsFixed(2)} MT para\n'
          '${recipient!.name?.trim().isNotEmpty == true ? '${recipient.name}\n' : ''}'
          '${recipient.phone}\n'
          'Perfil: ${recipient.role}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    final result = await _depositService.transferToUser(
      targetPhone: phone,
      amount: amount,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? result.message!
              : (result.error ?? 'Falha na transferência.'),
        ),
      ),
    );
    if (result.success) await _loadWallet(showLoader: false);
  }

  Future<void> _checkDepositStatusById(String depositId) async {
    setState(() => _checkingDepositId = depositId);
    final status = await _depositService.checkDepositStatus(depositId);
    await _loadWallet();
    if (!mounted) return;
    setState(() => _checkingDepositId = null);

    final message =
        status.message ??
        switch (status.status) {
          'completed' => 'Deposito confirmado com sucesso.',
          'failed' => 'O deposito falhou ou foi cancelado.',
          'pending' =>
            'O deposito ainda esta pendente. Confirme o PIN no telemovel e tente novamente.',
          'timeout' =>
            'Ainda nao houve confirmacao. Tente novamente em instantes.',
          _ => status.error ?? 'Nao foi possivel verificar o deposito agora.',
        };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: status.status == 'completed'
            ? AppColors.successGreen
            : null,
      ),
    );
  }

  String? _checkoutUrlFromDeposit(Map<String, dynamic> deposit) {
    final payload = deposit['provider_payload'];
    final parsed = payload is Map ? payload['parsed'] : null;
    final candidates = [
      payload is Map ? payload['checkout_url'] : null,
      payload is Map ? payload['payment_url'] : null,
      payload is Map ? payload['payment_link'] : null,
      parsed is Map ? parsed['checkout_url'] : null,
      parsed is Map ? parsed['payment_url'] : null,
      parsed is Map ? parsed['payment_link'] : null,
      parsed is Map ? parsed['url'] : null,
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<void> _resumeDepositCheckout(String checkoutUrl) async {
    final uri = Uri.tryParse(checkoutUrl);
    if (uri == null || !uri.hasScheme) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link PaySuite indisponível para esta operação.'),
          ),
        );
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carteira Digital'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            context.go(_dashboardRouteForRole());
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadWallet,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: !_walletDataLoaded
              ? [
                  if (_walletLoadError != null)
                    _buildInitialLoadError()
                  else
                    _buildInitialWalletSkeleton(),
                ]
              : [
                  if (_walletLoadError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Sem atualização no momento. A mostrar os últimos dados carregados.',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  _buildHeader(),
                  if (_fullName != null) const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _showTransferDialog,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Transferir saldo'),
                  ),
                  const SizedBox(height: 6),
                  const SizedBox(height: 16),
                  if (!_showOnlyHistory) _buildBalanceCard(),
                  if (_isClientRole &&
                      (!_hasFocusedSection || _showOnlyTickets)) ...[
                    const SizedBox(height: 16),
                    KeyedSubtree(
                      key: _ticketsSectionKey,
                      child: _buildTicketsCard(),
                    ),
                  ],
                  if (!_hasFocusedSection || _showOnlyDeposit) ...[
                    const SizedBox(height: 16),
                    KeyedSubtree(
                      key: _depositSectionKey,
                      child: _buildDepositCard(),
                    ),
                  ],
                  // Keep the withdrawal action visible for every role. If a legacy
                  // account has no wallet yet, the action provisions it and shows a
                  // clear message instead of silently removing the button.
                  if (!_hasFocusedSection || _showOnlyWithdraw) ...[
                    const SizedBox(height: 16),
                    KeyedSubtree(
                      key: _withdrawSectionKey,
                      child: _buildWithdrawalCard(),
                    ),
                  ],
                  if (!_hasFocusedSection || _showOnlyHistory) ...[
                    const SizedBox(height: 16),
                    KeyedSubtree(
                      key: _historySectionKey,
                      child: _buildHistoryCard(),
                    ),
                  ],
                  if (!_hasFocusedSection) ...[
                    const SizedBox(height: 16),
                    _buildLedgerCard(),
                  ],
                ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final name = _fullName;
    if (name == null || name.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ola, $name',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildInitialWalletSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 150,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(9),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          height: 118,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialLoadError() {
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined),
            const SizedBox(height: 8),
            Text(_walletLoadError!),
            TextButton.icon(
              onPressed: () => _loadWallet(),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    if (_loading) {
      return Container(
        height: 118,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.splashGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Saldo disponível',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                '$_currency ${_availableBalance.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Pendente: $_currency ${_pendingBalance.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                _isClientRole
                    ? 'Total (confirmado + pendente): $_currency ${_balance.toStringAsFixed(2)}'
                    : 'Total em carteira: $_currency ${_balance.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const Icon(
            Icons.account_balance_wallet,
            color: Colors.white,
            size: 40,
          ),
        ],
      ),
    );
  }

  Widget _buildDepositCard() {
    final amount =
        double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;
    final gatewayFee = _depositFee(amount);
    final netAmount = _depositNet(amount);

    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Depositar saldo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Valor (MZN)',
                helperText: 'Mínimo para depósito: 10 MT',
                prefixIcon: Icon(Icons.payments),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _phoneController.text.isEmpty
                  ? 'Número registado não disponível'
                  : _phoneController.text,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _buildDetectedOperator(_registeredWalletPhone),
            const SizedBox(height: 12),
            const SizedBox(height: 16),
            _buildDepositBreakdown(
              grossAmount: amount,
              gatewayFee: gatewayFee,
              netAmount: netAmount,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TapScale(
                child: ElevatedButton.icon(
                  onPressed: _depositing ? null : _showOperatorDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: AppColors.cleanWhite,
                  ),
                  icon: _depositing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.add),
                  label: Text(
                    _depositing ? 'Processando...' : 'Depositar agora',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketsCard() {
    final visibleTickets = _tickets.where((ticket) {
      final status = ticket['status']?.toString().toLowerCase() ?? '';
      switch (_ticketStatusFilter) {
        case 'used':
          return status == 'used';
        case 'cancelled':
          return status == 'cancelled';
        case 'upcoming':
        default:
          return status == 'sold' || status == 'available' || status == 'valid';
      }
    }).toList();

    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Os meus bilhetes',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/client-dashboard'),
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('Eventos'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Bilhetes comprados com saldo da Wallet DeliGo ficam guardados aqui.',
              style: TextStyle(color: AppColors.neutralGray, fontSize: 12),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'upcoming', label: Text('Proximos')),
                ButtonSegment(value: 'used', label: Text('Utilizados')),
                ButtonSegment(value: 'cancelled', label: Text('Cancelados')),
              ],
              selected: {_ticketStatusFilter},
              onSelectionChanged: (value) =>
                  setState(() => _ticketStatusFilter = value.first),
            ),
            const SizedBox(height: 12),
            if (visibleTickets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Nenhum bilhete nesta categoria.',
                  style: TextStyle(color: AppColors.neutralGray),
                ),
              )
            else
              ...visibleTickets.map(_buildTicketItem),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketItem(Map<String, dynamic> ticket) {
    final event = ticket['marketing_events'] is Map
        ? Map<String, dynamic>.from(ticket['marketing_events'] as Map)
        : const <String, dynamic>{};
    final restaurant = event['restaurants'] is Map
        ? Map<String, dynamic>.from(event['restaurants'] as Map)
        : const <String, dynamic>{};
    final title = event['title']?.toString() ?? 'Evento DeliGo';
    final status = ticket['status']?.toString() ?? 'sold';
    return Card(
      elevation: 0,
      color: const Color(0xFFF8FAFC),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFFEBEE),
          child: Icon(Icons.confirmation_number, color: AppColors.primaryRed),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            _ticketStatusLabel(status),
            ticket['ticket_type_name']?.toString(),
            event['event_date']?.toString(),
            event['event_time']?.toString(),
            restaurant['name']?.toString(),
          ].where((item) => item?.trim().isNotEmpty == true).join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.qr_code_2),
        onTap: () => _showTicketDetails(ticket),
      ),
    );
  }

  Future<void> _showTicketDetails(Map<String, dynamic> ticket) async {
    final event = ticket['marketing_events'] is Map
        ? Map<String, dynamic>.from(ticket['marketing_events'] as Map)
        : const <String, dynamic>{};
    final restaurant = event['restaurants'] is Map
        ? Map<String, dynamic>.from(event['restaurants'] as Map)
        : const <String, dynamic>{};
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event['title']?.toString() ?? 'Bilhete digital'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: QrImageView(
                  data: ticket['qr_code']?.toString() ?? '',
                  version: QrVersions.auto,
                  size: 190,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                ticket['qr_code']?.toString() ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              _ticketDetailRow('Codigo', ticket['ticket_code']?.toString()),
              _ticketDetailRow('Tipo', ticket['ticket_type_name']?.toString()),
              _ticketDetailRow('Comprador', _fullName),
              _ticketDetailRow('Evento', event['title']?.toString()),
              _ticketDetailRow('Organizador', restaurant['name']?.toString()),
              _ticketDetailRow('Data', event['event_date']?.toString()),
              _ticketDetailRow('Hora', event['event_time']?.toString()),
              _ticketDetailRow('Local', event['location']?.toString()),
              _ticketDetailRow(
                'Estado',
                _ticketStatusLabel(ticket['status']?.toString() ?? 'sold'),
              ),
              _ticketDetailRow(
                'Beneficios',
                'Entrada valida mediante QR Code ou codigo de seguranca.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _ticketDetailRow(String label, String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: AppColors.darkGray),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }

  String _ticketStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'sold':
      case 'available':
      case 'valid':
        return 'Valido';
      case 'used':
        return 'Utilizado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  Widget _buildHistoryCard() {
    if (_loading) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
      );
    }

    if (_deposits.isEmpty && _withdrawals.isEmpty && _orderPayments.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: const [
              Icon(Icons.history, size: 32, color: AppColors.neutralGray),
              SizedBox(height: 8),
              Text('Ainda nao ha movimentos por aqui'),
            ],
          ),
        ),
      );
    }

    final visibleDeposits = _deposits.where((deposit) {
      if (_depositStatusFilter == 'all') return true;
      return (deposit['status']?.toString() ?? '').toLowerCase() ==
          _depositStatusFilter;
    }).toList();
    final visibleWithdrawals = _withdrawals.where((request) {
      if (_withdrawalStatusFilter == 'all') return true;
      return (request['status']?.toString() ?? '').toLowerCase() ==
          _withdrawalStatusFilter;
    }).toList();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_orderPayments.isNotEmpty) ...[
              const Text(
                'Pagamentos dos pedidos',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ..._orderPayments.map(
                (payment) => _buildOrderPaymentItem(payment),
              ),
              const SizedBox(height: 20),
            ],
            if (_isClientRole) ...[
              const Text(
                'Historico de depositos',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildStatusDropdown(
                value: _depositStatusFilter,
                label: 'Filtrar depositos',
                options: const {
                  'all': 'Todos',
                  'completed': 'Confirmados',
                  'failed': 'Falhos',
                  'pending': 'Pendentes',
                },
                onChanged: (value) =>
                    setState(() => _depositStatusFilter = value),
              ),
              const SizedBox(height: 12),
              if (visibleDeposits.isEmpty)
                const Text(
                  'Ainda nao ha depositos neste filtro.',
                  style: TextStyle(color: AppColors.neutralGray),
                )
              else
                ...visibleDeposits.map((d) => _buildDepositItem(d)),
            ],
            if (_canWithdraw && _withdrawals.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Historico de levantamentos',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildStatusDropdown(
                value: _withdrawalStatusFilter,
                label: 'Filtrar levantamentos',
                options: const {
                  'all': 'Todos',
                  'completed': 'Confirmados',
                  'failed': 'Falhos',
                  'pending': 'Pendentes',
                },
                onChanged: (value) =>
                    setState(() => _withdrawalStatusFilter = value),
              ),
              const SizedBox(height: 12),
              if (visibleWithdrawals.isEmpty)
                const Text(
                  'Ainda nao ha levantamentos neste filtro.',
                  style: TextStyle(color: AppColors.neutralGray),
                )
              else
                ...visibleWithdrawals.map((w) => _buildWithdrawalItem(w)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDropdown({
    required String value,
    required String label,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        isDense: true,
      ),
      items: options.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value),
            ),
          )
          .toList(),
      onChanged: (selected) {
        if (selected == null) return;
        onChanged(selected);
      },
    );
  }

  Widget _buildLedgerCard() {
    if (_loading) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
      );
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ledger financeiro',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Aqui voce acompanha cada entrada, taxa, reserva em escrow e liquidacao da carteira.',
              style: TextStyle(color: AppColors.neutralGray, fontSize: 12),
            ),
            const SizedBox(height: 14),
            if (_ledgerEntries.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.receipt_long, color: AppColors.neutralGray),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Ainda nao ha lancamentos financeiros.'),
                    ),
                  ],
                ),
              )
            else
              ..._ledgerEntries.map(_buildLedgerItem),
          ],
        ),
      ),
    );
  }

  Widget _buildWithdrawalCard() {
    final registeredPhone = _normalizeMozPhone(_registeredWalletPhone);
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Levantar saldo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              registeredPhone.isEmpty
                  ? 'Número registado não disponível'
                  : registeredPhone,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _buildDetectedOperator(registeredPhone),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickWithdrawAmounts
                  .where(
                    (value) =>
                        value <= _maxWithdrawForRole() &&
                        value <= _availableBalance,
                  )
                  .map(
                    (value) => OutlinedButton(
                      onPressed: () {
                        _withdrawAmountController.text = value.toStringAsFixed(
                          0,
                        );
                      },
                      child: Text('${value.toStringAsFixed(0)} MZN'),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _withdrawAmountController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Valor a levantar (MZN)',
                prefixIcon: Icon(Icons.outbox),
              ),
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final amount =
                    double.tryParse(
                      _withdrawAmountController.text.replaceAll(',', '.'),
                    ) ??
                    0;
                final fee = _feeForAmount(amount);
                return _buildWithdrawalBreakdown(
                  grossAmount: amount,
                  fee: fee,
                  netAmount: _netForAmount(amount),
                );
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TapScale(
                child: ElevatedButton.icon(
                  onPressed: _withdrawing ? null : _submitWithdrawal,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: AppColors.cleanWhite,
                  ),
                  icon: _withdrawing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.call_made),
                  label: Text(
                    _withdrawing ? 'Solicitando...' : 'Confirmar levantamento',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWithdrawalBreakdown({
    required double grossAmount,
    required double fee,
    required double netAmount,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo do levantamento',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _buildSummaryRow(
            'Valor a levantar',
            '${grossAmount.toStringAsFixed(2)} $_currency',
          ),
          _buildSummaryRow(
            'Taxa de processamento (3%)',
            '- ${fee.toStringAsFixed(2)} $_currency',
          ),
          const Divider(height: 18),
          _buildSummaryRow(
            'Valor a receber',
            '${netAmount.toStringAsFixed(2)} $_currency',
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderPaymentItem(Map<String, dynamic> order) {
    final status = (order['status'] as String?) ?? 'pending';
    final amount = (order['total_amount'] as num?)?.toDouble() ?? 0;
    final created = DateTime.tryParse(order['created_at']?.toString() ?? '');
    final deliveryFee = (order['delivery_fee'] as num?)?.toDouble() ?? 0;
    final statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: statusColor.withValues(alpha: 0.12),
            child: Icon(Icons.receipt_long, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pedido #${order['id'].toString().substring(0, 8)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Total ${amount.toStringAsFixed(2)} $_currency • Entrega ${deliveryFee.toStringAsFixed(0)} MZN',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.neutralGray,
                  ),
                ),
                if (created != null)
                  Text(
                    _formatDate(created),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.neutralGray,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(color: statusColor, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepositItem(Map<String, dynamic> deposit) {
    final status = (deposit['status'] as String?) ?? 'pending';
    final amount = (deposit['amount'] as num?)?.toDouble() ?? 0;
    final gatewayFee =
        (deposit['gateway_fee'] as num?)?.toDouble() ?? _depositFee(amount);
    final netAmount =
        (deposit['net_amount'] as num?)?.toDouble() ?? _depositNet(amount);
    final created = DateTime.tryParse(deposit['created_at']?.toString() ?? '');
    final method = (deposit['payment_method'] as String?) ?? '-';
    final transactionId = deposit['transaction_id']?.toString();
    final providerStatus = deposit['provider_status']?.toString();
    final providerPayload = deposit['provider_payload'];
    final providerError = providerPayload is Map<String, dynamic>
        ? providerPayload['error']?.toString() ??
              providerPayload['message']?.toString() ??
              providerPayload['detail']?.toString()
        : providerPayload is Map
        ? providerPayload['error']?.toString() ??
              providerPayload['message']?.toString() ??
              providerPayload['detail']?.toString()
        : null;
    final statusColor = _statusColor(status);
    final depositId = deposit['id']?.toString();
    final isChecking = _checkingDepositId == depositId;
    final checkoutUrl = _checkoutUrlFromDeposit(deposit);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.payments, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_currency ${amount.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Taxa ${gatewayFee.toStringAsFixed(2)} $_currency • Liquido ${netAmount.toStringAsFixed(2)} $_currency',
                      style: const TextStyle(
                        color: AppColors.neutralGray,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${method.toUpperCase()} • ${created != null ? _formatDate(created) : '-'}',
                      style: const TextStyle(
                        color: AppColors.neutralGray,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _depositStatusLabel(status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (transactionId != null && transactionId.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Ref. gateway: $transactionId',
                        style: const TextStyle(
                          color: AppColors.neutralGray,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (providerStatus != null &&
                        providerStatus.isNotEmpty &&
                        status != 'pending') ...[
                      const SizedBox(height: 4),
                      Text(
                        'Provider: $providerStatus',
                        style: const TextStyle(
                          color: AppColors.neutralGray,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (providerError != null &&
                        providerError.isNotEmpty &&
                        status == 'failed') ...[
                      const SizedBox(height: 6),
                      Text(
                        providerError,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(color: statusColor, fontSize: 11),
                ),
              ),
            ],
          ),
          if (status == 'pending' && depositId != null) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (checkoutUrl != null)
                  OutlinedButton.icon(
                    onPressed: () => _resumeDepositCheckout(checkoutUrl),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Retomar checkout'),
                  ),
                OutlinedButton.icon(
                  onPressed: isChecking
                      ? null
                      : () => _checkDepositStatusById(depositId),
                  icon: isChecking
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(
                    isChecking ? 'Verificando...' : 'Verificar status',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWithdrawalItem(Map<String, dynamic> request) {
    final status = (request['status'] as String?) ?? 'pending';
    final amount = (request['amount'] as num?)?.toDouble() ?? 0;
    final created = DateTime.tryParse(request['created_at'] ?? '');
    final method = (request['method'] as String?) ?? '-';
    final statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: statusColor.withValues(alpha: 0.12),
            child: Icon(Icons.call_made, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Levantamento • ${method.toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  created != null
                      ? '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')} ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}'
                      : '-',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.neutralGray,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '- ${amount.toStringAsFixed(2)} $_currency',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerItem(Map<String, dynamic> entry) {
    final entryType = (entry['entry_type'] as String?) ?? 'entry';
    final direction = (entry['direction'] as String?) ?? 'credit';
    final status = (entry['status'] as String?) ?? 'confirmed';
    final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
    final balanceBefore = (entry['balance_before'] as num?)?.toDouble();
    final balanceAfter = (entry['balance_after'] as num?)?.toDouble();
    final created = DateTime.tryParse(entry['created_at']?.toString() ?? '');
    final color = direction == 'debit' ? Colors.red : AppColors.successGreen;
    final icon = _ledgerIcon(entryType, direction);
    final statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _ledgerTitle(entryType),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _ledgerDescription(entryType, created),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.neutralGray,
                  ),
                ),
                if (balanceBefore != null || balanceAfter != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Saldo: ${balanceBefore?.toStringAsFixed(2) ?? '-'} $_currency -> ${balanceAfter?.toStringAsFixed(2) ?? '-'} $_currency',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.neutralGray,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${direction == 'debit' ? '-' : '+'} ${amount.toStringAsFixed(2)} $_currency',
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  String _ledgerTitle(String entryType) {
    switch (entryType) {
      case 'deposit_net':
        return 'Deposito liquido';
      case 'deposit_gateway_fee':
        return 'Taxa do gateway';
      case 'order_payment_escrow':
        return 'Reserva do pedido em escrow';
      case 'restaurant_confirmation_settlement':
        return 'Liquidacao do restaurante';
      case 'courier_settlement':
        return 'Liquidacao do estafeta';
      case 'platform_fee_settlement':
        return 'Comissao da plataforma';
      case 'cashback_reward':
        return 'Cashback da plataforma';
      case 'referral_share_reward':
        return 'Bonus de convite';
      case 'escrow_release':
        return 'Liberacao do escrow';
      case 'order_timeout_refund':
        return 'Reembolso automatico';
      default:
        return entryType.replaceAll('_', ' ');
    }
  }

  String _ledgerDescription(String entryType, DateTime? created) {
    final when = created != null ? _formatDate(created) : 'agora';
    switch (entryType) {
      case 'deposit_net':
        return 'Saldo liquido creditado apos a taxa de processamento • $when';
      case 'deposit_gateway_fee':
        return 'Taxa cobrada pelo parceiro de pagamento • $when';
      case 'order_payment_escrow':
        return 'Valor reservado com seguranca ate a conclusao do pedido • $when';
      case 'restaurant_confirmation_settlement':
        return 'Repasse feito quando o restaurante confirmou o pedido • $when';
      case 'courier_settlement':
        return 'Repasse do delivery apos a confirmacao do cliente • $when';
      case 'platform_fee_settlement':
        return 'Comissao operacional da plataforma • $when';
      case 'cashback_reward':
        return 'Cashback de fidelidade creditado pela plataforma • $when';
      case 'referral_share_reward':
        return 'Bonus por convite convertido no restaurante • $when';
      case 'escrow_release':
        return 'Fechamento financeiro do pedido • $when';
      case 'order_timeout_refund':
        return 'Valor devolvido automaticamente por timeout operacional • $when';
      default:
        return 'Lancamento financeiro • $when';
    }
  }

  IconData _ledgerIcon(String entryType, String direction) {
    switch (entryType) {
      case 'deposit_net':
        return Icons.south_west;
      case 'deposit_gateway_fee':
        return Icons.receipt_long;
      case 'order_payment_escrow':
        return Icons.lock_clock;
      case 'restaurant_confirmation_settlement':
        return Icons.storefront;
      case 'courier_settlement':
        return Icons.delivery_dining;
      case 'platform_fee_settlement':
        return Icons.admin_panel_settings;
      case 'cashback_reward':
        return Icons.savings;
      case 'referral_share_reward':
        return Icons.card_giftcard;
      case 'escrow_release':
        return Icons.lock_open;
      case 'order_timeout_refund':
        return Icons.undo;
      default:
        return direction == 'debit' ? Icons.remove_circle : Icons.add_circle;
    }
  }

  double _depositFee(double amount) {
    if (amount <= 0) return 0;
    return double.parse((amount * _depositFeePercent).toStringAsFixed(2));
  }

  double _depositNet(double amount) {
    if (amount <= 0) return 0;
    return double.parse((amount - _depositFee(amount)).toStringAsFixed(2));
  }

  Widget _buildDepositBreakdown({
    required double grossAmount,
    required double gatewayFee,
    required double netAmount,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo do deposito',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _buildSummaryRow(
            'Valor a depositar',
            '${grossAmount.toStringAsFixed(2)} $_currency',
          ),
          _buildSummaryRow(
            'Taxa de processamento (3%)',
            '- ${gatewayFee.toStringAsFixed(2)} $_currency',
          ),
          const Divider(height: 18),
          _buildSummaryRow(
            'Valor a receber',
            '${netAmount.toStringAsFixed(2)} $_currency',
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: highlight ? AppColors.primaryRed : AppColors.neutralGray,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: highlight ? AppColors.primaryRed : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'cancelled':
        return Colors.orange;
      case 'reversed':
        return Colors.deepOrange;
      default:
        return Colors.blueGrey;
    }
  }

  String _depositStatusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Saldo atualizado automaticamente';
      case 'failed':
        return 'Pagamento falhou ou foi cancelado';
      case 'cancelled':
        return 'Deposito cancelado';
      default:
        return 'Aguardando a confirmacao do pagamento';
    }
  }
}

class _PaymentChip extends StatelessWidget {
  final String label;
  final String assetPath;
  final bool selected;
  final VoidCallback onSelected;

  const _PaymentChip({
    required this.label,
    required this.assetPath,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryRed.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primaryRed : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                assetPath,
                height: 24,
                width: 24,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? AppColors.primaryRed : AppColors.neutralGray,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
