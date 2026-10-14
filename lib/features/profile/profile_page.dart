import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/profile_service.dart';
import '../../services/order_service.dart';
import '../../services/account_deletion_service.dart';
import '../../config/theme/app_colors.dart';
import '../../config/router/app_router.dart';
import '../../services/app_language_controller.dart';
import '../../shared/location/location_picker_page.dart';
import '../../shared/models/order.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.initialSection});

  final String? initialSection;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _addressesSectionKey = GlobalKey();
  final OrderService _orderService = OrderService();

  // Dados do perfil
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _uploadingAvatar = false;
  Map<String, dynamic> _settings = {};
  Map<String, bool> _notificationPrefs = {
    'promotions': true,
    'order_status': true,
    'restaurant_offers': true,
    'sms': false,
    'push': true,
    'email': true,
  };
  String _language = 'pt';
  String _currency = 'MZN';
  String _voiceMode = 'important_only';
  bool _darkTheme = false;
  // Controladores para edicao
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();
  String? _selectedGender;
  String? _profileImageUrl;

  // Enderecos salvos
  List<Map<String, dynamic>> _savedAddresses = [];
  List<Order> _clientOrders = const [];
  bool _loadingOrders = false;

  bool get _isClientRole {
    final role = (_profile?['role'] as String?)?.trim().toLowerCase() ?? '';
    return role == 'client' || role == 'customer';
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      if (mounted) {
        final settings =
            (response['settings'] as Map?)?.cast<String, dynamic>() ?? {};
        final notifications =
            (settings['notifications'] as Map?)?.cast<String, dynamic>() ?? {};
        setState(() {
          _profile = response;
          _nameController.text = response['full_name'] ?? '';
          _phoneController.text = response['phone'] ?? '';
          _dobController.text = response['date_of_birth'] ?? '';
          _addressController.text = response['address'] ?? '';
          _selectedGender = response['gender'];
          _profileImageUrl = response['avatar_url'];
          _settings = settings;
          _language = settings['language'] ?? _language;
          _currency = settings['currency'] ?? _currency;
          _voiceMode = settings['voice_mode'] ?? _voiceMode;
          _darkTheme = settings['dark_theme'] == true;
          _notificationPrefs = {
            'promotions':
                notifications['promotions'] ??
                _notificationPrefs['promotions']!,
            'order_status':
                notifications['order_status'] ??
                _notificationPrefs['order_status']!,
            'restaurant_offers':
                notifications['restaurant_offers'] ??
                _notificationPrefs['restaurant_offers']!,
            'sms': notifications['sms'] ?? _notificationPrefs['sms']!,
            'push': notifications['push'] ?? _notificationPrefs['push']!,
            'email': notifications['email'] ?? _notificationPrefs['email']!,
          };
          _isLoading = false;
        });

        // Carregar enderecos
        _loadAddresses();
        _loadOrders();
        _scrollToInitialSection();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadAddresses() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase
          .from('user_addresses')
          .select()
          .eq('user_id', user.id)
          .order('is_default', ascending: false);

      if (mounted) {
        setState(() {
          _savedAddresses = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar enderecos: $e');
    }
  }

  Future<void> _updateProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      await supabase
          .from('profiles')
          .update({
            'full_name': _nameController.text.trim(),
            'address': _addressController.text.trim(),
            'date_of_birth': _dobController.text.trim(),
            'gender': _selectedGender,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);
      try {
        await supabase.auth.updateUser(
          UserAttributes(
            data: {
              'full_name': _nameController.text.trim(),
              'address': _addressController.text.trim(),
            },
          ),
        );
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil atualizado com sucesso!'),
            backgroundColor: AppColors.successGreen,
          ),
        );
        _loadProfile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Nao foi possivel atualizar o seu perfil agora. Tente novamente.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sair'),
        content: const Text('Tem certeza que deseja sair?'),
      ),
    );

    if (confirm == true) {
      AuthRefreshNotifier.markIntentionalSignOut();
      await supabase.auth.signOut();
      if (!mounted) return;
      context.go('/login');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    if (!_isClientRole) return;
    try {
      if (mounted) {
        setState(() => _loadingOrders = true);
      }
      final orders = await _orderService.getClientOrders();
      if (!mounted) return;
      setState(() {
        _clientOrders = orders;
        _loadingOrders = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingOrders = false);
    }
  }

  void _scrollToInitialSection() {
    if ((widget.initialSection ?? '').trim().toLowerCase() != 'addresses') {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = _addressesSectionKey.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        backgroundColor: AppColors.primaryRed,
        foregroundColor: AppColors.cleanWhite,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Foto de Perfil
                  _buildProfileHeader(),
                  const SizedBox(height: 16),

                  // Enderecos Salvos
                  KeyedSubtree(
                    key: _addressesSectionKey,
                    child: _buildAddressesSection(),
                  ),
                  const SizedBox(height: 16),

                  // Carteira
                  _buildWalletSection(),
                  const SizedBox(height: 16),
                  _buildHelpAndAccountSection(),
                  const SizedBox(height: 16),

                  // Botao Logout
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text(
                        'Sair da conta',
                        style: TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileHeader() {
    final phone = (supabase.auth.currentUser?.phone ?? _profile?['phone'] ?? '')
        .toString()
        .trim();
    final defaultAddress = _savedAddresses.firstWhere(
      (a) => a['is_default'] == true,
      orElse: () => {},
    );
    final defaultAddressText = (defaultAddress['address'] as String?) ?? '';
    return Column(
      children: [
        Stack(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: AppColors.primaryRed.withValues(alpha: 0.1),
                  backgroundImage: _profileImageUrl != null
                      ? NetworkImage(_profileImageUrl!)
                      : null,
                  child: _profileImageUrl == null
                      ? const Icon(
                          Icons.person,
                          size: 50,
                          color: AppColors.primaryRed,
                        )
                      : null,
                ),
                if (_uploadingAvatar)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryRed,
                child: IconButton(
                  icon: const Icon(
                    Icons.camera_alt,
                    size: 18,
                    color: Colors.white,
                  ),
                  onPressed: _uploadingAvatar ? null : _changeProfilePicture,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _profile?['full_name'] ?? 'Usuario',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        if (phone.isNotEmpty)
          Text(phone, style: const TextStyle(color: AppColors.neutralGray)),
        if (defaultAddressText.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_on,
                size: 14,
                color: AppColors.primaryRed,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  defaultAddressText,
                  style: const TextStyle(color: AppColors.neutralGray),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.successGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Conta Verificada',
            style: TextStyle(
              color: AppColors.successGreen,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHelpAndAccountSection() {
    return Card(
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.help_outline, color: AppColors.primaryRed),
            title: Text(
              'Ajuda e conta',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('Central de ajuda'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/support'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Termos de uso'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/terms'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Política de privacidade'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/privacy'),
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Pagamentos e reembolsos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/wallet?section=history'),
          ),
          ListTile(
            leading: const Icon(Icons.manage_accounts_outlined),
            title: const Text('Gerir conta'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showDeleteAccountDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoSection() {
    final email = supabase.auth.currentUser?.email ?? '-';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Informacoes Pessoais',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () => _showEditProfileDialog(),
                  child: const Text('Editar'),
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow(
              Icons.person,
              'Nome completo',
              _profile?['full_name'] ?? '-',
            ),
            _buildInfoRow(Icons.phone, 'Telefone', _profile?['phone'] ?? '-'),
            _buildInfoRow(Icons.email, 'Email', email),
            _buildInfoRow(
              Icons.cake,
              'Data de Nascimento',
              _profile?['date_of_birth'] ?? '-',
            ),
            _buildInfoRow(Icons.wc, 'Genero', _profile?['gender'] ?? '-'),
            _buildInfoRow(
              Icons.language,
              'Idioma',
              _language == 'pt' ? 'Portugues' : 'English',
            ),
            _buildInfoRow(
              Icons.record_voice_over,
              'Voz',
              _voiceModeLabel(_voiceMode),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Enderecos Salvos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: () => _showAddAddressDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar'),
                ),
              ],
            ),
            const Divider(),
            if (_savedAddresses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Nenhum endereco salvo',
                    style: TextStyle(color: AppColors.neutralGray),
                  ),
                ),
              )
            else
              ...(_savedAddresses.map((address) => _buildAddressCard(address))),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressCard(Map<String, dynamic> address) {
    final neighborhood = (address['neighborhood'] as String?)?.trim();
    final city = (address['city'] as String?)?.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: address['is_default'] == true
          ? AppColors.primaryRed.withValues(alpha: 0.05)
          : null,
      child: ListTile(
        leading: Icon(
          _getAddressIcon(address['label']),
          color: AppColors.primaryRed,
        ),
        title: Row(
          children: [
            Text(address['label'] ?? 'Endereco'),
            if (address['is_default'] == true) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryRed,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Padrao',
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(address['address'] ?? ''),
            if (address['reference'] != null)
              Text(
                'Ref: ${address['reference']}',
                style: const TextStyle(fontSize: 12),
              ),
            if ((neighborhood?.isNotEmpty ?? false) ||
                (city?.isNotEmpty ?? false))
              Text(
                [
                  if (neighborhood?.isNotEmpty == true) 'Bairro: $neighborhood',
                  if (city?.isNotEmpty == true) 'Cidade: $city',
                ].join(' - '),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.neutralGray,
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 18),
                  SizedBox(width: 8),
                  Text('Editar'),
                ],
              ),
            ),
            if (address['is_default'] != true)
              const PopupMenuItem(
                value: 'default',
                child: Row(
                  children: [
                    Icon(Icons.star, size: 18),
                    SizedBox(width: 8),
                    Text('Definir padrao'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Excluir', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'edit') {
              _showEditAddressDialog(address);
            } else if (value == 'default') {
              _setDefaultAddress(address['id'], address['address'] ?? '');
            } else if (value == 'delete') {
              _deleteAddress(address['id']);
            }
          },
        ),
      ),
    );
  }

  IconData _getAddressIcon(String? label) {
    switch (label?.toLowerCase()) {
      case 'casa':
        return Icons.home;
      case 'trabalho':
        return Icons.work;
      default:
        return Icons.location_on;
    }
  }

  Widget _buildWalletSection() {
    final paymentContact = (_profile?['payment_contact'] as String?)?.trim();
    final preferredMethod =
        (_profile?['preferred_payment_method'] as String?)?.trim() ??
        'carteira';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF4EE), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primaryRed.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet,
                      color: AppColors.primaryRed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Carteira',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (paymentContact?.isNotEmpty ?? false)
                              ? 'Metodo principal: $preferredMethod - $paymentContact'
                              : _isClientRole
                              ? 'Gerencie saldo, pagamentos, depositos e levantamentos'
                              : 'Gerencie saldo, pagamentos e levantamentos',
                          style: const TextStyle(color: AppColors.neutralGray),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.account_balance_wallet,
                color: AppColors.primaryRed,
              ),
              title: const Text('Abrir carteira'),
              subtitle: Text(
                _isClientRole
                    ? 'Saldo, pagamentos de pedidos, depositos e levantamentos'
                    : 'Saldo, pagamentos de pedidos e levantamentos',
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.push('/wallet'),
            ),
            ListTile(
              leading: Icon(
                _isClientRole ? Icons.add_card : Icons.call_made,
                color: AppColors.successGreen,
              ),
              title: Text(_isClientRole ? 'Adicionar saldo' : 'Levantar saldo'),
              subtitle: Text(
                _isClientRole
                    ? 'M-Pesa ou e-Mola conforme o seu numero'
                    : 'Levante apenas o saldo disponivel da sua wallet',
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _isClientRole
                  ? context.push('/wallet?section=deposit')
                  : context.push('/wallet?section=withdraw'),
            ),
            if (_isClientRole)
              ListTile(
                leading: const Icon(
                  Icons.call_made,
                  color: AppColors.primaryRed,
                ),
                title: const Text('Levantar saldo'),
                subtitle: const Text(
                  'Levante apenas o saldo disponivel da sua wallet',
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => context.push('/wallet?section=withdraw'),
              ),
            ListTile(
              leading: const Icon(Icons.history, color: AppColors.neutralGray),
              title: const Text('Ver historico da carteira'),
              subtitle: const Text('Pagamentos dos pedidos e movimentacoes'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => context.push('/wallet?section=history'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notificacoes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notificationPrefs['push'] ?? true,
              onChanged: (value) async {
                setState(() => _notificationPrefs['push'] = value);
                await _saveSettings();
              },
              title: const Text('Push Notification'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notificationPrefs['sound'] ?? true,
              onChanged: (value) async {
                setState(() => _notificationPrefs['sound'] = value);
                await _saveSettings();
              },
              title: const Text('Sons das notificações'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notificationPrefs['voice'] ?? true,
              onChanged: (value) async {
                setState(() => _notificationPrefs['voice'] = value);
                await _saveSettings();
              },
              title: const Text('Voz das notificações'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponsSection() {
    final coupons = (_settings['coupons'] as List?)?.cast<String>() ?? [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cupons e Promocoes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            if (coupons.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nenhum cupom registrado',
                  style: TextStyle(color: AppColors.neutralGray),
                ),
              )
            else
              ...coupons.map(
                (c) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.local_offer,
                    color: AppColors.primaryRed,
                  ),
                  title: Text(c),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showCouponDialog,
                icon: const Icon(Icons.add),
                label: const Text('Inserir codigo promocional'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.receipt_long, color: AppColors.primaryRed),
                SizedBox(width: 10),
                Text(
                  'Historico de pedidos',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingOrders)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_clientOrders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Ainda nao existem pedidos no historico.',
                  style: TextStyle(color: AppColors.neutralGray),
                ),
              )
            else
              ..._clientOrders.map(
                (order) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.shopping_bag_outlined,
                    color: AppColors.primaryRed,
                  ),
                  title: Text('Pedido ${order.id.substring(0, 8)}'),
                  subtitle: Text(
                    '${order.status.displayName} - ${_formatDateTime(order.createdAt)}',
                  ),
                  trailing: Text(
                    '${order.totalAmount.toStringAsFixed(0)} MZN',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () => context.push('/order/${order.id}'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesSection() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.favorite, color: Colors.redAccent),
        title: const Text('Favoritos'),
        subtitle: const Text('Restaurantes e pratos favoritos'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => context.go('/client-dashboard?tab=favorites'),
      ),
    );
  }

  Widget _buildSupportSection() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.support_agent, color: AppColors.primaryRed),
        title: const Text('Suporte DeliGo'),
        subtitle: const Text('Chat de suporte e ajuda com pedidos'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => context.push('/support'),
      ),
    );
  }

  Widget _buildAppSettingsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.settings, color: AppColors.primaryRed),
                SizedBox(width: 10),
                Text(
                  'Configuracoes do App',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Idioma: ${_language == 'pt' ? 'Portugues' : 'English'} - Moeda: $_currency - Voz: ${_voiceModeLabel(_voiceMode)}',
              style: const TextStyle(color: AppColors.neutralGray),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _language,
              decoration: const InputDecoration(
                labelText: 'Idioma',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.language),
              ),
              items: const [
                DropdownMenuItem(value: 'pt', child: Text('Portugues')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (value) => setState(() => _language = value ?? 'pt'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _darkTheme,
              onChanged: (value) async {
                setState(() => _darkTheme = value);
                await _saveSettings();
              },
              title: const Text('Tema escuro'),
              secondary: const Icon(Icons.dark_mode_outlined),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _voiceMode,
              decoration: const InputDecoration(
                labelText: 'Voz do app',
                helperText:
                    'Use voz completa, apenas eventos importantes ou desligue.',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.record_voice_over_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'full', child: Text('Voz completa')),
                DropdownMenuItem(
                  value: 'important_only',
                  child: Text('Apenas eventos importantes'),
                ),
                DropdownMenuItem(value: 'off', child: Text('Sem voz')),
              ],
              onChanged: (value) =>
                  setState(() => _voiceMode = value ?? 'important_only'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await _saveSettings();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Preferencias do app atualizadas.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar preferencias'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.push('/settings'),
                icon: const Icon(Icons.tune),
                label: const Text('Abrir configuracoes completas'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecuritySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seguranca',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.lock, color: AppColors.primaryRed),
              title: const Text('Alterar palavra-passe'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showChangePasswordDialog(),
            ),
            ListTile(
              leading: const Icon(Icons.devices, color: AppColors.primaryRed),
              title: const Text('Encerrar sessoes em outros dispositivos'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                try {
                  AuthRefreshNotifier.markIntentionalSignOut();
                  await supabase.auth.signOut(scope: SignOutScope.global);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sessoes encerradas com sucesso.'),
                      ),
                    );
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Nao foi possivel encerrar as sessoes agora.',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeProfilePicture() async {
    if (_uploadingAvatar) return;
    final pageMessenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (modalContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(modalContext, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(modalContext, 'camera'),
            ),
            if (_profileImageUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.redAccent),
                title: const Text(
                  'Remover foto',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => Navigator.pop(modalContext, 'remove'),
              ),
          ],
        ),
      ),
    );

    if (action == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final service = ProfileService();
      String? url;
      if (action == 'gallery') {
        url = await service.uploadProfilePhoto();
      } else if (action == 'camera') {
        url = await service.takeProfilePhoto();
      } else if (action == 'remove') {
        final ok = await service.removeProfilePhoto();
        if (ok) url = null;
      }

      if (!mounted) return;
      if (action != 'remove' && (url == null || url.trim().isEmpty)) {
        pageMessenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível atualizar a foto. Tente novamente.',
            ),
          ),
        );
        return;
      }
      setState(() => _profileImageUrl = url);
      pageMessenger.showSnackBar(
        SnackBar(
          content: Text(
            action == 'remove'
                ? 'Foto removida'
                : 'Foto atualizada com sucesso',
          ),
        ),
      );
      _loadProfile();
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _showEditProfileDialog() {
    final pageContext = context;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(modalContext).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Editar perfil',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome completo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              readOnly: true,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Telefone',
                border: OutlineInputBorder(),
                helperText: 'O número usado no cadastro não pode ser alterado.',
                suffixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dobController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Data de nascimento',
                border: OutlineInputBorder(),
              ),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1950),
                  lastDate: now,
                  initialDate: DateTime(now.year - 18, now.month, now.day),
                );
                if (picked != null) {
                  _dobController.text = picked
                      .toIso8601String()
                      .split('T')
                      .first;
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedGender,
              decoration: const InputDecoration(
                labelText: 'Genero',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Masculino', child: Text('Masculino')),
                DropdownMenuItem(value: 'Feminino', child: Text('Feminino')),
                DropdownMenuItem(value: 'Outro', child: Text('Outro')),
              ],
              onChanged: (value) => setState(() => _selectedGender = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _language,
              decoration: const InputDecoration(
                labelText: 'Idioma',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'pt', child: Text('Portugues')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (value) => setState(() => _language = value ?? 'pt'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _voiceMode,
              decoration: const InputDecoration(
                labelText: 'Voz do app',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'full', child: Text('Voz completa')),
                DropdownMenuItem(
                  value: 'important_only',
                  child: Text('Apenas eventos importantes'),
                ),
                DropdownMenuItem(value: 'off', child: Text('Sem voz')),
              ],
              onChanged: (value) =>
                  setState(() => _voiceMode = value ?? 'important_only'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final focusScope = FocusScope.of(pageContext);
                  Navigator.of(modalContext).pop();
                  await _updateProfile();
                  if (!mounted) return;
                  await _saveSettings();
                  if (!mounted) return;
                  focusScope.unfocus();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Salvar'),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primaryRed),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.neutralGray),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddAddressDialog() {
    final pageContext = context;
    final pageMessenger = ScaffoldMessenger.of(pageContext);
    final labelCtrl = TextEditingController(text: 'Casa');
    final addressCtrl = TextEditingController();
    final referenceCtrl = TextEditingController();
    final instructionCtrl = TextEditingController();
    final neighborhoodCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    LatLng? coords;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) => StatefulBuilder(
        builder: (modalContext, setModal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalContext).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Adicionar endereco',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: labelCtrl.text,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Casa', child: Text('Casa')),
                    DropdownMenuItem(
                      value: 'Trabalho',
                      child: Text('Trabalho'),
                    ),
                    DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                  ],
                  onChanged: (value) => labelCtrl.text = value ?? 'Casa',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Endereco',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: referenceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Referencia (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: instructionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Instrucoes de entrega',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: neighborhoodCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bairro',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cidade',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.location_on),
                        label: const Text('Selecionar no mapa'),
                        onPressed: () async {
                          final picked = await _pickLocationOnMap();
                          if (picked != null) {
                            coords = picked.position;
                            setModal(() {
                              addressCtrl.text = _bestAddressFromPickedLocation(
                                picked,
                              );
                              neighborhoodCtrl.text =
                                  picked.neighborhood?.trim() ?? '';
                              cityCtrl.text = picked.city?.trim() ?? '';
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.my_location),
                        label: const Text('Usar minha localizacao'),
                        onPressed: () async {
                          final picked = await _pickLocationOnMap(
                            useCurrentLocationOnStart: true,
                          );
                          if (picked != null) {
                            coords = picked.position;
                            setModal(() {
                              addressCtrl.text = _bestAddressFromPickedLocation(
                                picked,
                              );
                              neighborhoodCtrl.text =
                                  picked.neighborhood?.trim() ?? '';
                              cityCtrl.text = picked.city?.trim() ?? '';
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final focusScope = FocusScope.of(pageContext);
                      final navigator = Navigator.of(modalContext);
                      final user = supabase.auth.currentUser;
                      if (user == null) return;
                      if (addressCtrl.text.trim().isEmpty) {
                        if (!mounted) return;
                        pageMessenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Preencha o endereco antes de salvar.',
                            ),
                          ),
                        );
                        return;
                      }
                      final isDefault = _savedAddresses.isEmpty;
                      try {
                        await supabase.from('user_addresses').insert({
                          'user_id': user.id,
                          'label': labelCtrl.text.trim(),
                          'address': addressCtrl.text.trim(),
                          'reference': referenceCtrl.text.trim().isEmpty
                              ? null
                              : referenceCtrl.text.trim(),
                          'delivery_instructions':
                              instructionCtrl.text.trim().isEmpty
                              ? null
                              : instructionCtrl.text.trim(),
                          'neighborhood': neighborhoodCtrl.text.trim().isEmpty
                              ? null
                              : neighborhoodCtrl.text.trim(),
                          'city': cityCtrl.text.trim().isEmpty
                              ? null
                              : cityCtrl.text.trim(),
                          'latitude': coords?.latitude,
                          'longitude': coords?.longitude,
                          'is_default': isDefault,
                          'created_at': DateTime.now().toIso8601String(),
                        });
                        if (isDefault) {
                          _addressController.text = addressCtrl.text.trim();
                          await supabase
                              .from('profiles')
                              .update({
                                'address': addressCtrl.text.trim(),
                                'updated_at': DateTime.now().toIso8601String(),
                              })
                              .eq('id', user.id);
                        }
                      } catch (_) {
                        if (!mounted) return;
                        pageMessenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Nao foi possivel salvar o endereco agora.',
                            ),
                          ),
                        );
                        return;
                      }
                      if (!mounted) return;
                      navigator.pop();
                      await _loadAddresses();
                      await _loadProfile();
                      if (!mounted) return;
                      focusScope.unfocus();
                      pageMessenger.showSnackBar(
                        const SnackBar(
                          content: Text('Endereco salvo com sucesso.'),
                          backgroundColor: AppColors.successGreen,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Salvar endereco'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditAddressDialog(Map<String, dynamic> address) {
    final pageContext = context;
    final pageMessenger = ScaffoldMessenger.of(pageContext);
    final labelCtrl = TextEditingController(text: address['label'] ?? 'Casa');
    final addressCtrl = TextEditingController(text: address['address'] ?? '');
    final referenceCtrl = TextEditingController(
      text: address['reference'] ?? '',
    );
    final instructionCtrl = TextEditingController(
      text: address['delivery_instructions'] ?? address['instructions'] ?? '',
    );
    final neighborhoodCtrl = TextEditingController(
      text: address['neighborhood'] ?? '',
    );
    final cityCtrl = TextEditingController(text: address['city'] ?? '');
    LatLng? coords =
        (address['latitude'] != null && address['longitude'] != null)
        ? LatLng(
            (address['latitude'] as num).toDouble(),
            (address['longitude'] as num).toDouble(),
          )
        : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) => StatefulBuilder(
        builder: (modalContext, setModal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalContext).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Editar endereco',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: labelCtrl.text,
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Casa', child: Text('Casa')),
                    DropdownMenuItem(
                      value: 'Trabalho',
                      child: Text('Trabalho'),
                    ),
                    DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                  ],
                  onChanged: (value) => labelCtrl.text = value ?? 'Casa',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Endereco',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: referenceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Referencia',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: instructionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Instrucoes de entrega',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: neighborhoodCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bairro',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cidade',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.map),
                  label: const Text('Selecionar no mapa'),
                  onPressed: () async {
                    final picked = await _pickLocationOnMap(initial: coords);
                    if (picked != null) {
                      coords = picked.position;
                      setModal(() {
                        addressCtrl.text = _bestAddressFromPickedLocation(
                          picked,
                        );
                        neighborhoodCtrl.text =
                            picked.neighborhood?.trim() ?? '';
                        cityCtrl.text = picked.city?.trim() ?? '';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.my_location),
                  label: const Text('Usar minha localizacao'),
                  onPressed: () async {
                    final picked = await _pickLocationOnMap(
                      initial: coords,
                      useCurrentLocationOnStart: true,
                    );
                    if (picked != null) {
                      coords = picked.position;
                      setModal(() {
                        addressCtrl.text = _bestAddressFromPickedLocation(
                          picked,
                        );
                        neighborhoodCtrl.text =
                            picked.neighborhood?.trim() ?? '';
                        cityCtrl.text = picked.city?.trim() ?? '';
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final focusScope = FocusScope.of(pageContext);
                      final navigator = Navigator.of(modalContext);
                      if (addressCtrl.text.trim().isEmpty) {
                        if (!mounted) return;
                        pageMessenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Preencha o endereco antes de salvar.',
                            ),
                          ),
                        );
                        return;
                      }
                      try {
                        await supabase
                            .from('user_addresses')
                            .update({
                              'label': labelCtrl.text.trim(),
                              'address': addressCtrl.text.trim(),
                              'reference': referenceCtrl.text.trim().isEmpty
                                  ? null
                                  : referenceCtrl.text.trim(),
                              'delivery_instructions':
                                  instructionCtrl.text.trim().isEmpty
                                  ? null
                                  : instructionCtrl.text.trim(),
                              'neighborhood':
                                  neighborhoodCtrl.text.trim().isEmpty
                                  ? null
                                  : neighborhoodCtrl.text.trim(),
                              'city': cityCtrl.text.trim().isEmpty
                                  ? null
                                  : cityCtrl.text.trim(),
                              'latitude': coords?.latitude,
                              'longitude': coords?.longitude,
                              'updated_at': DateTime.now().toIso8601String(),
                            })
                            .eq('id', address['id']);
                        if (address['is_default'] == true) {
                          _addressController.text = addressCtrl.text.trim();
                          await supabase
                              .from('profiles')
                              .update({
                                'address': addressCtrl.text.trim(),
                                'updated_at': DateTime.now().toIso8601String(),
                              })
                              .eq('id', supabase.auth.currentUser!.id);
                        }
                      } catch (_) {
                        if (!mounted) return;
                        pageMessenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Nao foi possivel salvar as alteracoes agora.',
                            ),
                          ),
                        );
                        return;
                      }
                      if (!mounted) return;
                      navigator.pop();
                      await _loadAddresses();
                      await _loadProfile();
                      if (!mounted) return;
                      focusScope.unfocus();
                      pageMessenger.showSnackBar(
                        const SnackBar(
                          content: Text('Endereco atualizado com sucesso.'),
                          backgroundColor: AppColors.successGreen,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Salvar alteracoes'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setDefaultAddress(dynamic id, String address) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase
        .from('user_addresses')
        .update({'is_default': false})
        .eq('user_id', user.id);
    await supabase
        .from('user_addresses')
        .update({'is_default': true})
        .eq('id', id);
    await supabase
        .from('profiles')
        .update({'address': address})
        .eq('id', user.id);
    _addressController.text = address;
    await _loadAddresses();
    await _loadProfile();
  }

  Future<void> _deleteAddress(dynamic id) async {
    await supabase.from('user_addresses').delete().eq('id', id);
    await _loadAddresses();
  }

  Future<void> _saveSettings() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    _settings['notifications'] = _notificationPrefs;
    _settings['language'] = _language;
    _settings['currency'] = _currency;
    _settings['voice_mode'] = _voiceMode;
    _settings['dark_theme'] = _darkTheme;
    await supabase
        .from('profiles')
        .update({
          'settings': _settings,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', user.id);
    if (!mounted) return;
    await context.read<AppLanguageController>().setLanguage(
      _language,
      persistRemote: false,
    );
  }

  String _voiceModeLabel(String value) {
    switch (value) {
      case 'full':
        return 'Voz completa';
      case 'off':
        return 'Sem voz';
      case 'important_only':
      default:
        return 'Apenas eventos importantes';
    }
  }

  Future<void> _showCouponDialog() async {
    final ctrl = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cupom promocional'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Codigo do cupom'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (saved == null || saved.isEmpty) return;
    final coupons = (_settings['coupons'] as List?)?.cast<String>() ?? [];
    if (!coupons.contains(saved)) {
      coupons.add(saved);
      _settings['coupons'] = coupons;
      await _saveSettings();
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _showChangePasswordDialog() {
    final pageContext = context;
    final currentController = TextEditingController();
    final nextController = TextEditingController();
    final confirmController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(modalContext).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Alterar Palavra-passe',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: currentController,
                decoration: InputDecoration(
                  labelText: 'Palavra-passe atual',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nextController,
                decoration: InputDecoration(
                  labelText: 'Nova palavra-passe',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                decoration: InputDecoration(
                  labelText: 'Confirmar nova palavra-passe',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final current = currentController.text;
                    final next = nextController.text;
                    final confirm = confirmController.text;
                    if (current.isEmpty || next.length < 6 || next != confirm) {
                      ScaffoldMessenger.of(pageContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Confirme a senha actual e uma nova senha válida.',
                          ),
                        ),
                      );
                      return;
                    }
                    final user = supabase.auth.currentUser;
                    final email = user?.email;
                    if (user == null || email == null || email.isEmpty) {
                      ScaffoldMessenger.of(pageContext).showSnackBar(
                        const SnackBar(
                          content: Text('Sessão inválida. Entre novamente.'),
                        ),
                      );
                      return;
                    }
                    try {
                      await supabase.auth.signInWithPassword(
                        email: email,
                        password: current,
                      );
                      await supabase.auth.updateUser(
                        UserAttributes(password: next),
                      );
                      if (modalContext.mounted) Navigator.pop(modalContext);
                      if (pageContext.mounted) {
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          const SnackBar(
                            content: Text('Senha alterada com sucesso.'),
                          ),
                        );
                      }
                    } on AuthException catch (error) {
                      ScaffoldMessenger.of(
                        pageContext,
                      ).showSnackBar(SnackBar(content: Text(error.message)));
                    } finally {
                      currentController.dispose();
                      nextController.dispose();
                      confirmController.dispose();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Alterar Palavra-passe'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final deletionService = AccountDeletionService();
    late final AccountDeletionPreview preview;
    try {
      preview = await deletionService.previewDeletion();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
      return;
    }
    if (!preview.canDelete) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            preview.message ?? 'Não é possível eliminar a conta agora.',
          ),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar Conta'),
        content: Text(
          'Tem certeza que deseja eliminar a sua conta? Esta ação é irreversível.'
          '${preview.transferableAmount > 0 ? '\n\n${preview.confirmationDisclosure}' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final result = await deletionService.requestDeletion(
                  confirmationText: 'DELETE',
                );
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(result.message)));
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Não foi possível eliminar a conta agora: $error',
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<LocationAddressDetails?> _pickLocationOnMap({
    LatLng? initial,
    bool useCurrentLocationOnStart = false,
  }) async {
    final seed = initial ?? const LatLng(-25.9655, 32.5832);
    if (!mounted) return null;
    return Navigator.of(context).push<LocationAddressDetails>(
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          initialPosition: seed,
          title: 'Escolher localizacao',
          confirmLabel: 'Confirmar localizacao',
          useCurrentLocationOnStart: useCurrentLocationOnStart,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  String _bestAddressFromPickedLocation(LocationAddressDetails picked) {
    final formatted = picked.formattedAddress.trim();
    if (formatted.isNotEmpty) return formatted;

    final parts = <String>[
      if ((picked.street ?? '').trim().isNotEmpty) picked.street!.trim(),
      if ((picked.route ?? '').trim().isNotEmpty) picked.route!.trim(),
      if ((picked.neighborhood ?? '').trim().isNotEmpty)
        picked.neighborhood!.trim(),
      if ((picked.city ?? '').trim().isNotEmpty) picked.city!.trim(),
    ];

    if (parts.isNotEmpty) {
      return parts.join(', ');
    }

    return '${picked.position.latitude.toStringAsFixed(6)}, ${picked.position.longitude.toStringAsFixed(6)}';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}
