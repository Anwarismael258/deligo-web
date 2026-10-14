import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../config/theme/app_colors.dart';
import '../../services/cart_service.dart';
import '../../services/payment_service.dart';
import '../../services/order_service.dart';
import 'package:deligo_app/services/restaurant_service.dart';
import '../../services/weather_service.dart';
import '../../services/sound_controller.dart';
import '../../shared/widgets/deligo_pressable.dart';
import '../../shared/widgets/deligo_wow_button.dart';
import '../../shared/utils/ecosystem_test_persona.dart';
import '../../shared/location/location_picker_page.dart';

class _CheckoutStep extends StatelessWidget {
  const _CheckoutStep({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: AppColors.primaryRed,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final OrderService _orderService = OrderService();
  final PaymentService _paymentService = PaymentService();
  final supabase = Supabase.instance.client;
  final _addressController = TextEditingController();
  bool _isLoading = false;
  bool _isDelivery = true;
  bool _deliveryChoiceMade = false;
  static const int _deliveryFeeMinimum = 100;
  static const int _deliveryFeeMaximum = 200;
  double? _deliveryLat;
  double? _deliveryLng;
  double _walletBalance = 0;
  String _walletCurrency = 'MZN';
  String _paymentPhone = '';
  String? _walletId;
  bool _isTestWallet = false;
  Map<String, dynamic>? _activeCombo;
  String? _comboRestaurantId;
  DateTime? _scheduledFor;
  String? _groupCode;
  String? _couponCode;
  Map<String, dynamic>? _couponQuote;
  bool _checkingCoupon = false;

  Future<void> _clearStoredPlanning() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final profile = await supabase
          .from('profiles')
          .select('settings')
          .eq('id', user.id)
          .maybeSingle();
      final settings = Map<String, dynamic>.from(
        (profile?['settings'] as Map?) ?? {},
      );
      settings.remove('scheduled_for');
      settings.remove('group_order_code');
      await supabase
          .from('profiles')
          .update({
            'settings': settings,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final cart = context.read<CartService>();
      cart.setDeliveryFee(_deliveryFeeMinimum);
      await _loadDefaultAddress();
      await _loadWalletAndPaymentProfile();
      await _recalculateDeliveryFee();
      await _loadActiveCombo();
    });
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaultAddress() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final addressRow = await supabase
          .from('user_addresses')
          .select('address, latitude, longitude, is_default')
          .eq('user_id', user.id)
          .order('is_default', ascending: false)
          .limit(1)
          .maybeSingle();

      final address = (addressRow?['address'] as String?)?.trim();
      if (address != null && address.isNotEmpty && mounted) {
        setState(() {
          _addressController.text = address;
          _deliveryLat = (addressRow?['latitude'] as num?)?.toDouble();
          _deliveryLng = (addressRow?['longitude'] as num?)?.toDouble();
        });
        return;
      }

      final profile = await supabase
          .from('profiles')
          .select('address')
          .eq('id', user.id)
          .maybeSingle();
      final fallback = (profile?['address'] as String?)?.trim();
      if (fallback != null && fallback.isNotEmpty && mounted) {
        setState(() => _addressController.text = fallback);
      }
    } catch (_) {}
  }

  Future<void> _pickCheckoutLocation({
    required bool useCurrentLocation,
    bool saveAsAddress = false,
  }) async {
    if (!mounted) return;
    LatLng initial = const LatLng(-25.9655, 32.5832);
    if (!useCurrentLocation && _deliveryLat != null && _deliveryLng != null) {
      initial = LatLng(_deliveryLat!, _deliveryLng!);
    }
    final picked = await Navigator.of(context).push<LocationAddressDetails>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          initialPosition: initial,
          title: useCurrentLocation
              ? 'Usar minha localização atual'
              : 'Escolher local de entrega',
          confirmLabel: 'Confirmar este local',
          useCurrentLocationOnStart: useCurrentLocation,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted || picked == null) return;
    final address = picked.formattedAddress.trim().isNotEmpty
        ? picked.formattedAddress.trim()
        : 'Localização confirmada';
    setState(() {
      _addressController.text = address;
      _deliveryLat = picked.position.latitude;
      _deliveryLng = picked.position.longitude;
    });
    if (saveAsAddress) {
      final user = supabase.auth.currentUser;
      if (user != null) {
        try {
          await supabase.from('user_addresses').insert({
            'user_id': user.id,
            'label': 'Novo endereço',
            'address': address,
            'reference': picked.suggestedReference,
            'neighborhood': picked.neighborhood,
            'city': picked.city,
            'latitude': picked.position.latitude,
            'longitude': picked.position.longitude,
            'is_default': false,
          });
        } catch (_) {}
      }
    }
    await _recalculateDeliveryFee();
  }

  Future<void> _showSavedDeliveryAddresses() async {
    final user = supabase.auth.currentUser;
    if (user == null || !mounted) return;
    try {
      final rows = await supabase
          .from('user_addresses')
          .select(
            'id, label, address, reference, neighborhood, city, latitude, longitude',
          )
          .eq('user_id', user.id)
          .order('is_default', ascending: false);
      if (!mounted) return;
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              const ListTile(
                title: Text(
                  'Endereços salvos',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('Escolha onde deseja receber este pedido.'),
              ),
              ...List<Map<String, dynamic>>.from(rows).map(
                (row) => ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text((row['label'] ?? 'Endereço').toString()),
                  subtitle: Text((row['address'] ?? '').toString()),
                  onTap: () => Navigator.pop(sheetContext, row),
                ),
              ),
            ],
          ),
        ),
      );
      if (!mounted || selected == null) return;
      final lat = (selected['latitude'] as num?)?.toDouble();
      final lng = (selected['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Este endereço ainda não tem pin confirmado no mapa.',
            ),
          ),
        );
        return;
      }
      setState(() {
        _addressController.text = (selected['address'] ?? '').toString();
        _deliveryLat = lat;
        _deliveryLng = lng;
      });
      await _recalculateDeliveryFee();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível carregar os endereços salvos.'),
          ),
        );
      }
    }
  }

  Future<void> _loadWalletAndPaymentProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final profile = await supabase
          .from('profiles')
          .select('preferred_payment_method, payment_contact')
          .eq('id', user.id)
          .maybeSingle();
      final walletRows = await supabase
          .from('wallets')
          .select('id, balance, available_balance, currency, updated_at')
          .eq('user_id', user.id)
          .order('updated_at', ascending: false)
          .limit(1);
      final wallet = (walletRows as List).isNotEmpty
          ? Map<String, dynamic>.from((walletRows).first as Map)
          : null;

      if (!mounted) return;
      setState(() {
        _paymentPhone = (profile?['payment_contact'] as String?)?.trim() ?? '';
        _walletId = wallet?['id']?.toString();
        _isTestWallet = EcosystemTestPersona.matches(user);
        _walletBalance =
            (wallet?['available_balance'] as num?)?.toDouble() ??
            (wallet?['balance'] as num?)?.toDouble() ??
            0;
        _walletCurrency = (wallet?['currency'] as String?) ?? 'MZN';
      });
    } catch (_) {}
  }

  Future<void> _recalculateDeliveryFee() async {
    if (!_isDelivery) return;
    final cart = context.read<CartService>();
    final restId = cart.restaurantId;
    if (restId == null || _deliveryLat == null || _deliveryLng == null) {
      cart.setDeliveryFee(_deliveryFeeMinimum);
      return;
    }
    try {
      final response = await supabase
          .from('restaurants')
          .select('latitude, longitude, neighborhood, city')
          .eq('id', restId)
          .maybeSingle();
      final restLat = (response?['latitude'] as num?)?.toDouble();
      final restLng = (response?['longitude'] as num?)?.toDouble();
      if (restLat == null || restLng == null) {
        cart.setDeliveryFee(_deliveryFeeMinimum);
        return;
      }
      final distance = _calculateDistanceKm(
        _deliveryLat!,
        _deliveryLng!,
        restLat,
        restLng,
      );
      final weather = await WeatherService.instance.fetchWeather(
        latitude: _deliveryLat,
        longitude: _deliveryLng,
        city: response?['city'] as String?,
      );
      final fee = RestaurantService.calculateDeliveryFee(
        distance,
        neighborhood: response?['neighborhood'] as String?,
        city: response?['city'] as String?,
        temperatureC: weather?.temperatureC,
      );
      final clamped = fee.clamp(_deliveryFeeMinimum, _deliveryFeeMaximum);
      cart.setDeliveryFee(clamped);
    } catch (_) {
      cart.setDeliveryFee(_deliveryFeeMinimum);
    }
  }

  Future<void> _loadActiveCombo() async {
    final cart = context.read<CartService>();
    final restaurantId = cart.restaurantId;
    if (restaurantId == null || restaurantId.isEmpty) {
      if (mounted) {
        setState(() {
          _activeCombo = null;
          _comboRestaurantId = null;
        });
      }
      return;
    }
    try {
      final combo = await RestaurantService().getActiveDailyCombo(restaurantId);
      if (!mounted) return;
      setState(() {
        _activeCombo = combo;
        _comboRestaurantId = restaurantId;
      });
    } catch (_) {}
  }

  double _comboDiscountFor(CartService cart) {
    final combo = _activeCombo;
    if (combo == null || _comboRestaurantId != cart.restaurantId) return 0;
    final percent = (combo['discount_percentage'] as num?)?.toDouble() ?? 0;
    if (percent <= 0) return 0;
    return ((cart.subtotal) * (percent / 100)).clamp(0, cart.subtotal);
  }

  double _serviceFeeFor(CartService cart) {
    return 0;
  }

  double _finalTotalFor(CartService cart) {
    return (cart.subtotal - _comboDiscountFor(cart)) +
        cart.deliveryFee +
        _serviceFeeFor(cart) -
        _couponDiscountFor(cart);
  }

  double _couponDiscountFor(CartService cart) {
    if (_activeCombo != null || _couponQuote?['eligible'] != true) return 0;
    return ((_couponQuote?['discount_amount'] as num?)?.toDouble() ?? 0).clamp(
      0,
      cart.subtotal + cart.deliveryFee,
    );
  }

  Future<void> _applyCoupon(CartService cart) async {
    if (_activeCombo != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Um combo já está aplicado. Remova-o antes de usar cupão.',
          ),
        ),
      );
      return;
    }
    final controller = TextEditingController(text: _couponCode ?? '');
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aplicar cupão'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Código do cupão'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Validar'),
          ),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty || cart.restaurantId == null) {
      return;
    }
    setState(() => _checkingCoupon = true);
    try {
      final quote = await supabase.rpc(
        'validate_deligo_coupon_v1',
        params: {
          'p_code': code.trim().toUpperCase(),
          'p_restaurant_id': cart.restaurantId,
          'p_subtotal': cart.subtotal,
          'p_delivery_fee': cart.deliveryFee,
          'p_neighborhood': null,
        },
      );
      final result = Map<String, dynamic>.from(quote as Map);
      if (result['eligible'] == true) {
        if (mounted) {
          setState(() {
            _couponCode = code.trim().toUpperCase();
            _couponQuote = result;
          });
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cupão indisponível para este pedido.'),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível validar o cupão.')),
        );
      }
    }
    if (mounted) setState(() => _checkingCoupon = false);
  }

  Future<void> _placeOrder() async {
    final cart = context.read<CartService>();

    if (supabase.auth.currentUser == null) {
      if (!mounted) return;
      await _showGuestCheckoutDialog();
      return;
    }

    if (cart.isEmpty) {
      await SoundController.instance.error();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O carrinho está vazio. Adicione algo para continuar.'),
        ),
      );
      return;
    }

    if (_isDelivery && _addressController.text.trim().isEmpty) {
      await SoundController.instance.error();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Falta o endereço de entrega para seguir com o pedido.',
          ),
        ),
      );
      return;
    }

    if (_isDelivery && (_deliveryLat == null || _deliveryLng == null)) {
      await SoundController.instance.error();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Localização precisa necessária. Confirme o pin no mapa antes de continuar.',
          ),
        ),
      );
      return;
    }

    final finalTotal = _finalTotalFor(cart);
    if (_walletBalance < finalTotal) {
      await SoundController.instance.error();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Saldo insuficiente. Recarregue a carteira antes de concluir o pedido.',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final items = cart.items
          .map(
            (item) => {
              'menu_item_id': item.menuItem.id,
              'quantity': item.quantity,
              'unit_price': item.menuItem.price,
              'subtotal': item.subtotal,
            },
          )
          .toList();

      DateTime? scheduledFor;
      String? groupCode;
      try {
        final profile = await supabase
            .from('profiles')
            .select('settings')
            .eq('id', supabase.auth.currentUser!.id)
            .maybeSingle();
        final settings =
            (profile?['settings'] as Map?)?.cast<String, dynamic>() ?? {};
        final scheduledRaw = settings['scheduled_for'] as String?;
        scheduledFor = scheduledRaw != null
            ? DateTime.tryParse(scheduledRaw)
            : null;
        groupCode = settings['group_order_code'] as String?;
        if (mounted) {
          setState(() {
            _scheduledFor = scheduledFor;
            _groupCode = groupCode;
          });
        }
      } catch (_) {}
      final comboDiscount = _comboDiscountFor(cart);
      final comboPayload = _activeCombo != null && comboDiscount > 0
          ? <String, dynamic>{
              'id': _activeCombo!['id'],
              'title': _activeCombo!['title'],
              'discount_percentage': _activeCombo!['discount_percentage'],
              'discount_amount': comboDiscount,
            }
          : null;
      final order = await _orderService.createOrder(
        restaurantId: cart.restaurantId!,
        deliveryAddress: _isDelivery
            ? _addressController.text.trim()
            : 'SEM DELIVERY',
        totalAmount: finalTotal,
        deliveryFee: cart.deliveryFee.toDouble(),
        paymentMethod: 'wallet',
        items: items,
        processWalletPayment: true,
        deliveryType: _isDelivery ? 'delivery' : 'pickup',
        scheduledFor: scheduledFor,
        groupCode: groupCode,
        combo: comboPayload,
        couponCode: _couponCode,
        deliveryLatitude: _isDelivery ? _deliveryLat : null,
        deliveryLongitude: _isDelivery ? _deliveryLng : null,
      );

      if (order != null && mounted) {
        final createdOrderId = order.id;
        final createdOrderTotal = order.totalAmount;
        await cart.clearCart();
        await _clearStoredPlanning();
        if (mounted) {
          setState(() {
            _activeCombo = null;
            _comboRestaurantId = null;
            _scheduledFor = null;
            _groupCode = null;
          });
        }
        await SoundController.instance.success();
        final paymentReady =
            order.hasConfirmedPayment || order.fundsHeldInEscrow;
        if (paymentReady) {
          await _showTransientSuccessSplash(isPickup: !_isDelivery);
          if (!mounted) return;
          context.go('/client-dashboard');
        } else {
          await _startPaymentForOrder(
            createdOrderId,
            createdOrderTotal,
            comboTitle: comboPayload?['title']?.toString(),
            comboDiscountAmount: (comboPayload?['discount_amount'] as num?)
                ?.toDouble(),
            scheduledFor: scheduledFor,
            groupCode: groupCode,
          );
        }
      } else if (mounted) {
        await SoundController.instance.error();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Nao conseguimos enviar o pedido agora. Verifique o carrinho e tente novamente.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await SoundController.instance.error();
        if (!mounted) return;
        final raw = e.toString().replaceFirst('Exception: ', '').trim();
        final message = raw.isNotEmpty
            ? raw
            : 'Algo nao correu bem ao processar o pedido. Tente de novo.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showGuestCheckoutDialog() async {
    final destination = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quase lá!'),
        content: const Text(
          'Para concluir a sua encomenda, entre na sua conta ou crie uma conta gratuita. O seu carrinho ficará guardado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('register'),
            child: const Text('Criar conta'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('login'),
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
    if (!mounted || destination == null) return;
    context.push(destination == 'register' ? '/register' : '/login');
  }

  Future<void> _startPaymentForOrder(
    String orderId,
    double amount, {
    String? comboTitle,
    double? comboDiscountAmount,
    DateTime? scheduledFor,
    String? groupCode,
  }) async {
    try {
      final payment = await _paymentService.createPayment(
        amount: amount,
        walletType: 'wallet',
        orderId: orderId,
      );

      if (!mounted) return;

      if (payment == null) {
        _showOrderConfirmation(
          orderId,
          paymentStarted: false,
          paymentFailureReason: _paymentService.lastErrorMessage,
          comboTitle: comboTitle,
          comboDiscountAmount: comboDiscountAmount,
          scheduledFor: scheduledFor,
          groupCode: groupCode,
        );
        return;
      }

      await _orderService.waitForOrderVisibility(orderId);
      if (!mounted) return;
      await _showTransientSuccessSplash(isPickup: !_isDelivery);
      if (!mounted) return;
      context.go('/client-dashboard');
    } catch (_) {
      if (!mounted) return;
      _showOrderConfirmation(
        orderId,
        paymentStarted: false,
        paymentFailureReason: _paymentService.lastErrorMessage,
        comboTitle: comboTitle,
        comboDiscountAmount: comboDiscountAmount,
        scheduledFor: scheduledFor,
        groupCode: groupCode,
      );
    }
  }

  Future<void> _handlePlaceOrder() async {
    if (_isLoading) return;
    if (!_deliveryChoiceMade) {
      await SoundController.instance.error();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Escolha primeiro entre delivery ou sem delivery para continuar.',
          ),
        ),
      );
      return;
    }
    await _placeOrder();
  }

  Future<void> _showTransientSuccessSplash({required bool isPickup}) {
    final navigator = Navigator.of(context);
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'success-splash',
      barrierColor: Colors.black.withValues(alpha: 0.78),
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        Future.delayed(const Duration(milliseconds: 1150), () {
          if (navigator.canPop()) {
            navigator.pop();
          }
        });
        return _SuccessSplashLayer(isPickup: isPickup);
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  void _showOrderConfirmation(
    String orderId, {
    required bool paymentStarted,
    String? paymentFailureReason,
    String? comboTitle,
    double? comboDiscountAmount,
    DateTime? scheduledFor,
    String? groupCode,
  }) {
    final normalizedFailure = paymentFailureReason?.trim();
    final failureDetails =
        normalizedFailure != null && normalizedFailure.isNotEmpty
        ? normalizedFailure
        : 'Abra os detalhes do pedido para concluir o pagamento interno novamente.';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.check_circle,
          color: AppColors.successGreen,
          size: 64,
        ),
        title: Text(
          paymentStarted ? 'Pedido pago e enviado' : 'Pedido criado',
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Seu pedido foi criado com sucesso.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              paymentStarted
                  ? 'O valor ja saiu da sua carteira interna, ficou protegido em escrow e o restaurante ja pode confirmar o pedido.'
                  : 'Nao foi possivel concluir o pagamento interno agora. Abra o pedido para tentar novamente.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.neutralGray,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    paymentStarted
                        ? 'Pagamento confirmado'
                        : 'Pagamento pendente',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    paymentStarted
                        ? 'Cliente debitado, restaurante em espera de confirmacao, e o estafeta so recebe apos o cliente clicar recebido.'
                        : failureDetails,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            if ((comboTitle ?? '').isNotEmpty ||
                scheduledFor != null ||
                (groupCode ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((comboTitle ?? '').isNotEmpty)
                      Text(
                        '$comboTitle aplicado${comboDiscountAmount != null && comboDiscountAmount > 0 ? ' • -${comboDiscountAmount.toStringAsFixed(0)} MZN' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    if (scheduledFor != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Entrega agendada: ${_formatDateTime(scheduledFor)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    if ((groupCode ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Pedido em grupo: $groupCode',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          DeligoWowButton(
            onTap: () {
              Navigator.pop(dialogContext);
              if (!mounted) return;
              context.push('/order/$orderId');
            },
            child: const Text(
              'Ver pedido',
              style: TextStyle(
                color: AppColors.cleanWhite,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateDistanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371;
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        _sin(dLat / 2) * _sin(dLat / 2) +
        _cos(_toRadians(lat1)) *
            _cos(_toRadians(lat2)) *
            _sin(dLng / 2) *
            _sin(dLng / 2);
    final c = 2 * _atan2(_sqrt(a), _sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degree) => degree * 3.141592653589793 / 180;
  double _sin(double x) => _taylorSin(x);
  double _cos(double x) => _taylorCos(x);
  double _sqrt(double x) => _newtonSqrt(x);
  double _atan2(double y, double x) => _approximateAtan2(y, x);

  double _taylorSin(double x) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carrinho'),
        centerTitle: true,
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
        surfaceTintColor: AppColors.primaryRed,
      ),
      body: Consumer<CartService>(
        builder: (context, cart, child) {
          if (_comboRestaurantId != cart.restaurantId && !_isLoading) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadActiveCombo();
            });
          }

          if (cart.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Carrinho vazio',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Adicione itens de um restaurante para continuar',
                    style: TextStyle(color: AppColors.neutralGray),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.go('/client-dashboard'),
                    child: const Text('Ver Restaurantes'),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _buildRestaurantIdentity(cart),
              const SizedBox(height: 10),
              _buildDeliveryModePanel(cart),
              const SizedBox(height: 10),
              if (_isDelivery) ...[
                _buildAddressPanel(),
                const SizedBox(height: 10),
              ],
              _buildOrderItemsSummary(cart),
              const SizedBox(height: 10),
              _buildPaymentSummaryCard(cart),
              const SizedBox(height: 10),
              _buildPricingSummary(cart),
              const SizedBox(height: 12),
              _buildPrimaryCheckoutButton(cart),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAddressPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Onde quer receber?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _addressController,
            decoration: InputDecoration(
              labelText: _isDelivery ? 'Endereco de entrega' : 'Sem delivery',
              hintText: _isDelivery ? 'Rua, numero, bairro...' : 'Sem delivery',
              prefixIcon: Icon(_isDelivery ? Icons.location_on : Icons.store),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            maxLines: _isDelivery ? 2 : 1,
            enabled: _isDelivery,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    _pickCheckoutLocation(useCurrentLocation: true),
                icon: const Icon(Icons.my_location),
                label: const Text('Minha localização atual'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _pickCheckoutLocation(useCurrentLocation: false),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Escolher no mapa'),
              ),
              OutlinedButton.icon(
                onPressed: _showSavedDeliveryAddresses,
                icon: const Icon(Icons.bookmark_border),
                label: const Text('Endereços salvos'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickCheckoutLocation(
                  useCurrentLocation: false,
                  saveAsAddress: true,
                ),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Novo endereço'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItemsSummary(CartService cart) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo do pedido',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 12),
          ...List.generate(cart.items.length, (index) {
            final item = cart.items[index];
            return _buildCartItemCard(cart, item, index);
          }),
        ],
      ),
    );
  }

  Widget _buildPricingSummary(CartService cart) {
    final serviceFee = _serviceFeeFor(cart);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preco transparente',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal'),
              Text('${cart.subtotal.toStringAsFixed(0)} MZN'),
            ],
          ),
          if (_comboDiscountFor(cart) > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Desconto (${(_activeCombo?['discount_percentage'] as num?)?.toStringAsFixed(0) ?? '0'}%)',
                ),
                Text(
                  '-${_comboDiscountFor(cart).toStringAsFixed(0)} MZN',
                  style: const TextStyle(
                    color: AppColors.successGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _checkingCoupon ? null : () => _applyCoupon(cart),
            icon: const Icon(Icons.local_offer_outlined),
            label: Text(
              _couponCode == null
                  ? 'Adicionar cupão'
                  : 'Cupão $_couponCode aplicado',
            ),
          ),
          if (_couponDiscountFor(cart) > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Cupão'),
                Text(
                  '-${_couponDiscountFor(cart).toStringAsFixed(0)} MZN',
                  style: const TextStyle(
                    color: AppColors.successGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          if (_isDelivery) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Entrega'),
                Text('${cart.deliveryFee.toStringAsFixed(0)} MZN'),
              ],
            ),
            if (serviceFee > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Taxa de servico'),
                  Text('${serviceFee.toStringAsFixed(0)} MZN'),
                ],
              ),
            ],
          ],
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total final',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Text(
                '${_finalTotalFor(cart).toStringAsFixed(0)} MZN',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.primaryRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Confirmacao rapida',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            _isDelivery
                ? 'Ao confirmar, o total e debitado da carteira e fica protegido em escrow ate a entrega.'
                : 'Ao confirmar, o total e debitado da carteira no modo sem delivery.',
            style: const TextStyle(color: AppColors.neutralGray, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryCheckoutButton(CartService cart, {bool compact = false}) {
    return SizedBox(
      width: double.infinity,
      height: compact ? 46 : 52,
      child: DeligoWowButton(
        onTap: _isLoading ? null : _handlePlaceOrder,
        enabled: !_isLoading,
        height: compact ? 46 : 52,
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Confirmar pedido – ${_finalTotalFor(cart).toStringAsFixed(0)} MZN',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.cleanWhite,
                    ),
                  ),
                  if (!compact)
                    const Text(
                      'Checkout rapido, tudo numa unica etapa',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.cleanWhite,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildCheckoutHero(CartService cart) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3ED), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primaryRed.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Expanded(
                child: _CheckoutStep(number: '1', label: 'Entrega'),
              ),
              SizedBox(width: 6),
              Expanded(
                child: _CheckoutStep(number: '2', label: 'Pagamento'),
              ),
              SizedBox(width: 6),
              Expanded(
                child: _CheckoutStep(number: '3', label: 'Confirmar'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: AppColors.primaryRed,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Checkout rapido',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${cart.itemCount} itens • Total atual ${_finalTotalFor(cart).toStringAsFixed(0)} MZN',
                      style: const TextStyle(color: AppColors.neutralGray),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSummaryChip(
                icon: Icons.account_balance_wallet,
                label:
                    'Saldo: $_walletCurrency ${_walletBalance.toStringAsFixed(2)}',
                color: AppColors.successGreen,
              ),
              _buildSummaryChip(
                icon: Icons.delivery_dining,
                label: _isDelivery ? 'DELIVERY' : 'SEM DELIVERY',
                color: AppColors.primaryRed,
              ),
              _buildSummaryChip(
                icon: Icons.payments,
                label: 'Carteira interna',
                color: Colors.indigo,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantIdentity(CartService cart) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderGray),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primaryRed.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.storefront, color: AppColors.primaryRed),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cart.restaurantName?.trim().isNotEmpty == true
                      ? cart.restaurantName!
                      : 'Deligo Restaurante',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isDelivery ? 'Pedido para entrega' : 'Pedido para recolha',
                  style: const TextStyle(color: AppColors.neutralGray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(CartService cart, dynamic item, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.primaryGreen.withValues(alpha: 0.08),
          ),
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.cleanWhite,
              AppColors.primaryGreen.withValues(alpha: 0.03),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.grey[200],
                ),
                child: item.menuItem.imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(
                          imageUrl: item.menuItem.imageUrl!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(Icons.fastfood),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.menuItem.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (item.menuItem.category != null &&
                        item.menuItem.category!.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentYellow.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          item.menuItem.category!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.deepBlack,
                          ),
                        ),
                      ),
                    if (item.observations != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          item.observations!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.neutralGray,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      '${item.menuItem.price.toStringAsFixed(0)} MZN x ${item.quantity}',
                      style: const TextStyle(
                        color: AppColors.neutralGray,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _QtyButton(
                        icon: Icons.remove,
                        onTap: () async {
                          await SoundController.instance.click();
                          if (item.quantity > 1) {
                            await cart.updateQuantity(index, item.quantity - 1);
                          } else {
                            await cart.removeItem(index);
                          }
                          if (mounted) setState(() {});
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '${item.quantity}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      _QtyButton(
                        icon: Icons.add,
                        onTap: () async {
                          await SoundController.instance.click();
                          await cart.updateQuantity(index, item.quantity + 1);
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${item.subtotal.toStringAsFixed(0)} MZN',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryRed,
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

  Widget _buildDeliveryModePanel(CartService cart) {
    return Row(
      children: [
        Expanded(
          child: _ModeCard(
            title: 'DELIVERY',
            subtitle: cart.deliveryFee > 0
                ? 'Taxa ${cart.deliveryFee.toStringAsFixed(0)} MZN'
                : 'Taxa a calcular',
            icon: Icons.delivery_dining,
            selected: _isDelivery,
            onTap: () async {
              setState(() {
                _deliveryChoiceMade = true;
                _isDelivery = true;
              });
              cart.setDeliveryFee(_deliveryFeeMinimum);
              await _loadDefaultAddress();
              await _recalculateDeliveryFee();
              await SoundController.instance.click();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ModeCard(
            title: 'RECOLHA',
            subtitle: 'Levantar no restaurante',
            icon: Icons.storefront,
            selected: !_isDelivery,
            onTap: () async {
              setState(() {
                _deliveryChoiceMade = true;
                _isDelivery = false;
                _addressController.text = 'SEM DELIVERY';
              });
              cart.setDeliveryFee(0);
              await SoundController.instance.click();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentSummaryCard(CartService cart) {
    final combo = _activeCombo;
    final comboDiscount = _comboDiscountFor(cart);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Carteira e pagamento',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Saldo disponivel: $_walletCurrency ${_walletBalance.toStringAsFixed(2)}',
            style: const TextStyle(color: AppColors.neutralGray),
          ),
          if (_paymentPhone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Numero da carteira: $_paymentPhone',
              style: const TextStyle(color: AppColors.neutralGray),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Pagamento do pedido: carteira interna',
            style: const TextStyle(color: AppColors.neutralGray),
          ),
          if (_activeCombo != null && comboDiscount > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${combo?['title'] ?? 'Combo do Dia'} - ${(combo?['discount_percentage'] as num?)?.toStringAsFixed(0) ?? '0'}% OFF',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.successGreen,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    combo?['description']?.toString() ??
                        'Desconto aplicado automaticamente neste pedido.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.neutralGray,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Desconto atual: -${comboDiscount.toStringAsFixed(0)} MZN',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.successGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_scheduledFor != null || _groupCode != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_scheduledFor != null)
                    Text(
                      'Entrega agendada: ${_formatDateTime(_scheduledFor!)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  if (_groupCode != null && _groupCode!.isNotEmpty)
                    Text(
                      'Pedido em grupo: $_groupCode',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _isDelivery
                  ? 'Ao confirmar a compra, o pedido sera pago com a carteira interna e o valor ficara protegido em escrow ate a entrega.'
                  : 'Ao confirmar a compra, o pedido sera pago com a carteira interna e seguira sem taxa de entrega.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.neutralGray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final d = value.day.toString().padLeft(2, '0');
    final m = value.month.toString().padLeft(2, '0');
    final y = value.year.toString();
    final h = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    return '$d/$m/$y as $h:$min';
  }

  Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final Future<void> Function() onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DeligoPressable(
      onTap: () async => onTap(),
      borderRadius: BorderRadius.circular(999),
      pressedScale: 0.92,
      splashColor: AppColors.accentYellow.withValues(alpha: 0.18),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.primaryGreen.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: AppColors.primaryGreen),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DeligoPressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      splashColor: selected
          ? AppColors.accentYellow.withValues(alpha: 0.20)
          : AppColors.rippleBase,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryGreen.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primaryGreen : AppColors.borderGray,
            width: selected ? 1.8 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.glowInteractive,
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: selected ? AppColors.primaryGreen : AppColors.neutralGray,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.primaryGreen : AppColors.darkGray,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.neutralGray,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessSplashLayer extends StatelessWidget {
  const _SuccessSplashLayer({required this.isPickup});

  final bool isPickup;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _SplashWave(
            alignment: Alignment(-0.82, -0.62),
            color: AppColors.primaryGreen,
            maxSize: 360,
            durationMs: 900,
          ),
          const _SplashWave(
            alignment: Alignment(0.88, -0.20),
            color: AppColors.primaryRed,
            maxSize: 320,
            durationMs: 1040,
          ),
          const _SplashWave(
            alignment: Alignment(-0.14, 0.74),
            color: AppColors.accentYellow,
            maxSize: 420,
            durationMs: 1120,
          ),
          const _SplashWave(
            alignment: Alignment(0.76, 0.82),
            color: AppColors.primaryGreen,
            maxSize: 280,
            durationMs: 980,
          ),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.86, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(scale: value, child: child);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primaryGreen,
                          AppColors.primaryRed,
                          AppColors.accentYellow,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryGreen.withValues(alpha: 0.28),
                          blurRadius: 26,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: AppColors.cleanWhite,
                      size: 58,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Pedido enviado ao restaurante',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.cleanWhite,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isPickup
                        ? 'Aguardando confirmação. Avisaremos quando estiver pronto para recolha.'
                        : 'Aguardando confirmação. Avisaremos assim que o restaurante responder. Entrega no seu endereço.',
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.cleanWhite.withValues(alpha: 0.88),
                      fontSize: 14,
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
}

class _SplashWave extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final double maxSize;
  final int durationMs;

  const _SplashWave({
    required this.alignment,
    required this.color,
    required this.maxSize,
    required this.durationMs,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.12, end: 1),
        duration: Duration(milliseconds: durationMs),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: (1 - value).clamp(0, 1) * 0.38,
            child: Container(
              width: maxSize * value,
              height: maxSize * value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.34),
              ),
            ),
          );
        },
      ),
    );
  }
}
