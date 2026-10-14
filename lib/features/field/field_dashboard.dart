import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/router/app_router.dart';
import '../../config/theme/app_colors.dart';
import '../../services/field_verification_service.dart';
import '../../services/push_notification_service.dart';
import '../admin/admin_document_viewer_page.dart';

class FieldDashboard extends StatefulWidget {
  const FieldDashboard({super.key});

  @override
  State<FieldDashboard> createState() => _FieldDashboardState();
}

class _FieldDashboardState extends State<FieldDashboard> {
  final _service = FieldVerificationService(Supabase.instance.client);
  final _searchController = TextEditingController();
  final _fieldScrollController = ScrollController();
  RealtimeChannel? _supportTicketsChannel;
  RealtimeChannel? _supportMessagesChannel;

  bool _loading = true;
  bool _processing = false;
  int _tabIndex = 0;
  String _statusFilter = 'pending';
  String _roleFilter = 'all';
  String _cityFilter = 'all';
  String _query = '';
  Map<String, dynamic>? _staffProfile;
  List<Map<String, dynamic>> _cases = const [];
  List<Map<String, dynamic>> _auditTrail = const [];
  List<Map<String, dynamic>> _staffOperationalStatus = const [];
  List<Map<String, dynamic>> _supportTickets = const [];
  List<Map<String, dynamic>> _supportOrders = const [];
  List<Map<String, dynamic>> _supportRestaurants = const [];
  List<Map<String, dynamic>> _supportCouriers = const [];
  List<Map<String, dynamic>> _supportClients = const [];
  List<Map<String, dynamic>> _supportActionsToday = const [];
  String _supportDashboardFilter = 'all';
  late Future<Map<String, String>> _operationalDiagnosticsFuture;

  static const _cities = ['all', 'Maputo', 'Matola', 'Beira', 'Nampula'];
  static const _rejectReasons = [
    'Documento ilegivel',
    'NUIT invalido',
    'Licenca expirada',
    'Fotos insuficientes',
    'Informacao incorreta',
    'Outro',
  ];
  static const _checklistLabels = {
    'nuit_valid': 'NUIT valido',
    'license_valid': 'Licenca valida',
    'photos_received': 'Fotos recebidas',
    'phone_confirmed': 'Telefone confirmado',
    'address_confirmed': 'Endereco confirmado',
  };
  static const _kycLabelOverrides = {
    'foto_loja': 'Foto da loja',
    'foto_nuit': 'Foto do NUIT',
    'foto_interior': 'Foto do interior',
    'bi_frente': 'BI frente',
    'bi_tras': 'BI verso',
    'selfie': 'Selfie',
    'foto': 'Foto do estafeta',
    'foto_veiculo': 'Foto do veiculo',
    'foto_matricula': 'Foto da matricula',
    'carta_conducao': 'Carta de conducao',
    'documento_veiculo': 'Documento do veiculo',
    'selfie_veiculo': 'Selfie com veiculo',
  };

  @override
  void initState() {
    super.initState();
    _operationalDiagnosticsFuture = _loadOperationalDiagnostics();
    _load();
  }

  @override
  void dispose() {
    _supportTicketsChannel?.unsubscribe();
    _supportMessagesChannel?.unsubscribe();
    _searchController.dispose();
    _fieldScrollController.dispose();
    super.dispose();
  }

  bool get _isAdmin => _staffProfile?['role']?.toString() == 'admin';
  bool get _canVerify => _isAdmin || _staffProfile?['role'] == 'field_agent';
  bool get _isSupportAgent => _staffProfile?['role'] == 'support_agent';
  bool get _isAmbassador => _staffProfile?['role'] == 'ambassador';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final staff = await _service.fetchCurrentStaffProfile();
      if (staff?['role'] == 'support_agent') {
        await _loadSupportWorkspace(staff: staff);
        _startSupportRealtime();
        return;
      }

      final cases = await _service.fetchVerificationCases(
        status: _statusFilter,
        role: _roleFilter,
        city: _cityFilter,
        query: _query,
      );
      final audit = await _service.fetchAuditTrail(limit: 60);
      final staffOperationalStatus = staff?['role'] == 'admin'
          ? await _service.fetchStaffOperationalStatus()
          : const <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _staffProfile = staff;
        _cases = cases;
        _auditTrail = audit;
        _staffOperationalStatus = staffOperationalStatus;
      });
    } catch (error) {
      if (!mounted) return;
      _showSnack('Nao foi possivel carregar o DeliGo Field: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, String>> _loadOperationalDiagnostics({
    bool refreshToken = false,
  }) {
    return PushNotificationService().operationalDiagnostics(
      refreshToken: refreshToken,
    );
  }

  void _refreshOperationalDiagnostics({bool refreshToken = false}) {
    setState(() {
      _operationalDiagnosticsFuture = _loadOperationalDiagnostics(
        refreshToken: refreshToken,
      );
    });
  }

  Future<void> _loadSupportWorkspace({Map<String, dynamic>? staff}) async {
    final tickets = await _service.fetchSupportTickets();
    final orders = await _service.fetchSupportOrders();
    final restaurants = await _service.fetchSupportRestaurants();
    final couriers = await _service.fetchSupportCouriers();
    final clients = await _service.fetchSupportClients();
    final actions = await _service.fetchSupportActionsToday();
    if (!mounted) return;
    setState(() {
      if (staff != null) _staffProfile = staff;
      _supportTickets = tickets;
      _supportOrders = orders;
      _supportRestaurants = restaurants;
      _supportCouriers = couriers;
      _supportClients = clients;
      _supportActionsToday = actions;
      _cases = const [];
      _auditTrail = const [];
    });
  }

  void _startSupportRealtime() {
    if (_supportTicketsChannel != null && _supportMessagesChannel != null) {
      return;
    }
    _supportTicketsChannel ??= Supabase.instance.client
        .channel('field-support-tickets')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'support_tickets',
          callback: (_) => unawaited(_loadSupportWorkspace()),
        )
        .subscribe();
    _supportMessagesChannel ??= Supabase.instance.client
        .channel('field-support-messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_messages',
          callback: (_) => unawaited(_loadSupportWorkspace()),
        )
        .subscribe();
  }

  int get _pendingRestaurants =>
      _cases.where((item) => item['role'] == 'restaurant').length;
  int get _pendingCouriers =>
      _cases.where((item) => item['role'] == 'courier').length;
  int get _waitingReview => _cases.length;
  int get _approvedToday => _auditTrail
      .where((item) => _isToday(item['created_at']) && _isApprovedAction(item))
      .length;
  int get _rejectedToday => _auditTrail
      .where((item) => _isToday(item['created_at']) && _isRejectedAction(item))
      .length;

  @override
  Widget build(BuildContext context) {
    if (!_loading && _isSupportAgent) {
      return _supportScaffold();
    }

    final titles = [
      'Mapa',
      'Tarefas',
      'KYC',
      'Restaurantes',
      'Estafetas',
      'Relatorios',
      'Perfil',
    ];
    return Scaffold(
      backgroundColor: AppColors.softBackground,
      appBar: AppBar(
        title: Text('DeliGo Field - ${titles[_tabIndex]}'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: _fieldDrawer(),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: Scrollbar(
                  controller: _fieldScrollController,
                  thumbVisibility: true,
                  child: CustomScrollView(
                    controller: _fieldScrollController,
                    slivers: [
                      SliverToBoxAdapter(child: _header()),
                      SliverToBoxAdapter(child: _statsGrid()),
                      SliverToBoxAdapter(child: _filters()),
                      SliverFillRemaining(
                        hasScrollBody: true,
                        child: IndexedStack(
                          index: _tabIndex,
                          children: [
                            _fieldMapTab(),
                            _fieldTasksTab(),
                            _kycTab(),
                            _restaurantsTab(),
                            _couriersTab(),
                            _historyTab(),
                            _profileTab(),
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

  Widget _fieldDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _fieldDrawerHeader(),
            _fieldDrawerItem(Icons.map_outlined, 'Mapa ao vivo', 0),
            _fieldDrawerItem(Icons.assignment_outlined, 'Tarefas', 1),
            _fieldDrawerItem(Icons.fact_check_outlined, 'KYC', 2),
            _fieldDrawerItem(Icons.storefront_outlined, 'Restaurantes', 3),
            _fieldDrawerItem(Icons.two_wheeler_outlined, 'Estafetas', 4),
            _fieldDrawerItem(Icons.bar_chart_outlined, 'Relatorios', 5),
            _fieldDrawerItem(Icons.person_outline, 'Perfil', 6),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.primaryRed),
              title: const Text('Sair'),
              onTap: _logout,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldDrawerHeader() {
    final name = _staffProfile?['full_name']?.toString() ?? 'Colaborador';
    final phone = _staffProfile?['phone']?.toString() ?? '';
    final role = _roleLabel(_staffProfile?['role']?.toString() ?? '');
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.verified_user_outlined)),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(phone.isEmpty ? role : '$role - $phone'),
    );
  }

  Widget _fieldDrawerItem(IconData icon, String label, int index) {
    return ListTile(
      selected: _tabIndex == index,
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.of(context).pop();
        setState(() => _tabIndex = index);
      },
    );
  }

  Widget _supportScaffold() {
    final titles = [
      'Dashboard',
      'Inbox',
      'Chat',
      'Pedidos',
      'Wallet',
      'Disputas',
      'Utilizadores',
      'Logs',
      'Perfil',
    ];
    return Scaffold(
      backgroundColor: AppColors.softBackground,
      appBar: AppBar(
        title: Text('Suporte - ${titles[_tabIndex]}'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              _supportDrawerHeader(),
              _supportDrawerItem(Icons.dashboard_outlined, 'Dashboard', 0),
              _supportDrawerItem(Icons.inbox_outlined, 'Inbox de Tickets', 1),
              _supportDrawerItem(Icons.support_agent, 'Chat', 2),
              _supportDrawerItem(
                Icons.report_problem_outlined,
                'Pedidos com problemas',
                3,
              ),
              _supportDrawerItem(Icons.account_balance_wallet_outlined, 'Wallet', 4),
              _supportDrawerItem(Icons.gavel_outlined, 'Disputas', 5),
              _supportDrawerItem(Icons.people_alt_outlined, 'Utilizadores', 6),
              _supportDrawerItem(Icons.manage_history_outlined, 'Logs', 7),
              _supportDrawerItem(Icons.person_outline, 'Perfil', 8),
              const Spacer(),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.primaryRed),
                title: const Text('Sair'),
                onTap: _logout,
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: IndexedStack(
            index: _tabIndex,
            children: [
              _supportDashboardTab(),
              _supportTicketsTab(showResolved: false),
              _supportChatTab(),
              _supportProblemOrdersTab(),
              _supportWalletTab(),
              _supportDisputesTab(),
              _supportUsersTab(),
              _supportLogsTab(),
              _supportProfileTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _supportDrawerHeader() {
    final name = _staffProfile?['full_name']?.toString() ?? 'Agente';
    final phone = _staffProfile?['phone']?.toString() ?? '';
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.support_agent)),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(phone.isEmpty ? 'Agente de Suporte' : phone),
    );
  }

  Widget _supportDrawerItem(IconData icon, String label, int index) {
    return ListTile(
      selected: _tabIndex == index,
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.of(context).pop();
        setState(() => _tabIndex = index);
      },
    );
  }

  Widget _supportDashboardTab() {
    final pendingTickets = _supportTickets
        .where((ticket) => !_isResolvedTicket(ticket))
        .length;
    final attendedTicketsToday = _supportTickets
        .where(
          (ticket) => _isToday(ticket['updated_at'] ?? ticket['created_at']),
        )
        .length;
    final resolvedToday = _supportTickets
        .where(
          (ticket) =>
              _isResolvedTicket(ticket) && _isToday(ticket['updated_at']),
        )
        .length;
    final callsToday = _supportTickets
        .where(
          (ticket) =>
              _isToday(ticket['updated_at'] ?? ticket['created_at']) &&
              _containsAny(ticket['dispute_type'], ['call', 'chamada']),
        )
        .length;
    final chatsToday = _supportTickets
        .where(
          (ticket) =>
              _isToday(ticket['updated_at'] ?? ticket['created_at']) &&
              (_containsAny(ticket['dispute_type'], ['chat']) ||
                  ticket['external_source']?.toString() == 'deligo_chat') &&
              ticket['status']?.toString() != 'open',
        )
        .length;
    final filteredTickets = _supportDashboardTickets();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _supportHero(),
        const SizedBox(height: 12),
        _supportMetricGrid([
          _Stat(
            Icons.task_alt,
            'Tickets atendidos hoje',
            attendedTicketsToday,
            filter: 'attended_today',
          ),
          _Stat(
            Icons.pending_actions,
            'Tickets pendentes',
            pendingTickets,
            filter: 'pending',
          ),
          _Stat(
            Icons.check_circle_outline,
            'Resolvidos hoje',
            resolvedToday,
            filter: 'resolved_today',
          ),
          _Stat(
            Icons.phone_in_talk_outlined,
            'Chamadas recebidas',
            callsToday,
            filter: 'calls_today',
          ),
          _Stat(
            Icons.chat_bubble_outline,
            'Chats respondidos',
            chatsToday,
            filter: 'chats_today',
          ),
        ]),
        const SizedBox(height: 12),
        _supportMetricDetails(filteredTickets),
        const SizedBox(height: 12),
        _sectionTitle('Funcoes principais'),
        _supportQuickActions(),
        const SizedBox(height: 12),
        _sectionTitle('Historico de atendimentos'),
        if (_supportActionsToday.isEmpty)
          _emptyCard('Sem atendimentos registados hoje.')
        else
          ..._supportActionsToday.map(_auditCard),
      ],
    );
  }

  List<Map<String, dynamic>> _supportDashboardTickets() {
    return _supportTickets.where((ticket) {
      final eventDate = ticket['updated_at'] ?? ticket['created_at'];
      switch (_supportDashboardFilter) {
        case 'attended_today':
          return _isToday(eventDate);
        case 'pending':
          return !_isResolvedTicket(ticket);
        case 'resolved_today':
          return _isResolvedTicket(ticket) && _isToday(ticket['updated_at']);
        case 'calls_today':
          return _isToday(eventDate) &&
              _containsAny(ticket['dispute_type'], ['call', 'chamada']);
        case 'chats_today':
          return _isToday(eventDate) &&
              (_containsAny(ticket['dispute_type'], ['chat']) ||
                  ticket['external_source']?.toString() == 'deligo_chat') &&
              ticket['status']?.toString() != 'open';
        default:
          return false;
      }
    }).toList();
  }

  Widget _supportMetricDetails(List<Map<String, dynamic>> tickets) {
    if (_supportDashboardFilter == 'all') {
      return _noticeCard(
        'Toque num indicador para ver os tickets, chamadas ou chats dessa categoria.',
      );
    }
    final title = _supportDashboardFilterLabel(_supportDashboardFilter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(title),
        if (tickets.isEmpty)
          _emptyCard('Sem detalhes para esta categoria.')
        else
          ...tickets.map(_supportTicketCard),
      ],
    );
  }

  String _supportDashboardFilterLabel(String filter) {
    switch (filter) {
      case 'attended_today':
        return 'Tickets atendidos hoje';
      case 'pending':
        return 'Tickets pendentes';
      case 'resolved_today':
        return 'Resolvidos hoje';
      case 'calls_today':
        return 'Chamadas recebidas';
      case 'chats_today':
        return 'Chats respondidos';
      default:
        return 'Detalhes';
    }
  }

  Widget _supportHero() {
    final name = _staffProfile?['full_name']?.toString() ?? 'Agente';
    final active = _staffProfile?['staff_active'] != false;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 26,
              child: Icon(Icons.headset_mic_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Theme.of(context).textTheme.titleLarge),
                  const Text('Cargo: Agente de Suporte'),
                ],
              ),
            ),
            Chip(
              label: Text(active ? 'Ativo' : 'Inativo'),
              avatar: Icon(
                active
                    ? Icons.check_circle_outline
                    : Icons.pause_circle_outline,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _supportMetricGrid(List<_Stat> stats) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 5 : 2,
            mainAxisExtent: 112,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final stat = stats[index];
            final selected = stat.filter == _supportDashboardFilter;
            return Card(
              elevation: 0,
              color: selected
                  ? AppColors.primaryRed.withValues(alpha: 0.08)
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: selected
                      ? AppColors.primaryRed
                      : AppColors.neutralGray.withValues(alpha: 0.16),
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(
                  () =>
                      _supportDashboardFilter = selected ? 'all' : stat.filter,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(stat.icon, color: AppColors.primaryRed),
                      const Spacer(),
                      Text(
                        stat.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        stat.value.toString(),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _supportQuickActions() {
    final actions = [
      _SupportAction(
        Icons.support_agent,
        'Abrir chat',
        () => setState(() => _tabIndex = 2),
      ),
      _SupportAction(
        Icons.confirmation_number_outlined,
        'Ver tickets atribuidos',
        () => setState(() => _tabIndex = 1),
      ),
      _SupportAction(
        Icons.history,
        'Historico de atendimentos',
        () => setState(() => _tabIndex = 0),
      ),
      _SupportAction(
        Icons.report_problem_outlined,
        'Registrar reclamacoes',
        () => setState(() => _tabIndex = 7),
      ),
      _SupportAction(
        Icons.bug_report_outlined,
        'Registrar problemas tecnicos',
        () => setState(() => _tabIndex = 7),
      ),
      _SupportAction(
        Icons.supervisor_account_outlined,
        'Encaminhar para gestores',
        () => setState(() => _tabIndex = 1),
      ),
      _SupportAction(
        Icons.receipt_long_outlined,
        'Consultar pedidos',
        () => setState(() => _tabIndex = 3),
      ),
      _SupportAction(
        Icons.storefront,
        'Consultar restaurantes',
        () => setState(() => _tabIndex = 6),
      ),
      _SupportAction(
        Icons.two_wheeler,
        'Consultar estafetas',
        () => setState(() => _tabIndex = 6),
      ),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: actions.map((item) {
        return OutlinedButton.icon(
          onPressed: item.onPressed,
          icon: Icon(item.icon),
          label: Text(item.label),
        );
      }).toList(),
    );
  }

  Widget _supportTicketsTab({required bool showResolved}) {
    final tickets = _supportTickets
        .where(
          (ticket) => showResolved
              ? _isResolvedTicket(ticket)
              : !_isResolvedTicket(ticket),
        )
        .where(_matchesSupportQuery)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _supportSearchField(),
        const SizedBox(height: 12),
        _sectionTitle(
          showResolved ? 'Tickets resolvidos' : 'Tickets atribuidos',
        ),
        if (showResolved)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: () =>
                  _showSupportActivityDialog('support_complaint_registered'),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Registrar reclamacao'),
            ),
          ),
        if (tickets.isEmpty)
          _emptyCard(
            showResolved ? 'Sem tickets resolvidos.' : 'Sem tickets pendentes.',
          )
        else
          ...tickets.map(_supportTicketCard),
      ],
    );
  }

  // ignore: unused_element
  Widget _supportComplaintsTab() {
    final complaints = _supportActionsToday
        .where((action) => _isComplaintAction(action['action']))
        .where(_matchesSupportQuery)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _supportSearchField(),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () =>
              _showSupportActivityDialog('support_complaint_registered'),
          icon: const Icon(Icons.add_comment_outlined),
          label: const Text('Registrar reclamacao'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () =>
              _showSupportActivityDialog('support_technical_issue_registered'),
          icon: const Icon(Icons.bug_report_outlined),
          label: const Text('Registrar problema tecnico'),
        ),
        const SizedBox(height: 12),
        _sectionTitle('Reclamacoes e problemas tecnicos'),
        if (complaints.isEmpty)
          _emptyCard('Sem reclamacoes registadas hoje.')
        else
          ...complaints.map(_auditCard),
      ],
    );
  }

  Widget _supportTicketCard(Map<String, dynamic> ticket) {
    final id = ticket['id']?.toString() ?? '';
    final code = id.length >= 8 ? id.substring(0, 8) : id;
    final status = ticket['status']?.toString() ?? 'open';
    final type = ticket['dispute_type']?.toString() ?? 'support';
    final reason = ticket['reason']?.toString() ?? 'Sem detalhe';
    final source = ticket['external_source']?.toString() ?? '';
    final customerName = _ticketCustomerName(ticket);
    final customerPhone = _ticketCustomerPhone(ticket);
    final isResolved = _isResolvedTicket(ticket);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppColors.neutralGray.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: source == 'deligo_chat'
            ? () => context.push('/support-ticket/${ticket['id']}')
            : () => _showSupportTicketDetails(ticket),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: isResolved
                        ? AppColors.primaryGreen.withValues(alpha: 0.14)
                        : AppColors.primaryRed.withValues(alpha: 0.12),
                    child: Icon(
                      source == 'deligo_chat'
                          ? Icons.chat_bubble_outline
                          : Icons.confirmation_number_outlined,
                      color: isResolved
                          ? AppColors.primaryGreen
                          : AppColors.primaryRed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          customerPhone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.neutralGray),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(_supportStatusLabel(status)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _supportInfoPill(Icons.tag, 'Chat #$code'),
                  _supportInfoPill(
                    Icons.category_outlined,
                    _supportTypeLabel(type),
                  ),
                  _supportInfoPill(
                    Icons.schedule,
                    _dateLabel(
                      ticket['updated_at']?.toString() ??
                          ticket['created_at']?.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(reason, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: source == 'deligo_chat'
                      ? () => context.push('/support-ticket/${ticket['id']}')
                      : () => _showSupportTicketDetails(ticket),
                  icon: Icon(
                    source == 'deligo_chat'
                        ? Icons.open_in_new
                        : Icons.visibility_outlined,
                  ),
                  label: Text(
                    source == 'deligo_chat' ? 'Abrir chat' : 'Ver detalhes',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _supportInfoPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.softBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.neutralGray),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  String _ticketCustomerName(Map<String, dynamic> ticket) {
    final name = ticket['customer_name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final role = ticket['opened_by_role']?.toString().trim() ?? '';
    if (role.isNotEmpty) return _roleSubjectLabel(role);
    return 'Usuario DeliGo';
  }

  String _ticketCustomerPhone(Map<String, dynamic> ticket) {
    final phone = ticket['customer_phone']?.toString().trim() ?? '';
    return phone.isEmpty ? 'Telefone nao registado' : phone;
  }

  Widget _supportChatTab() {
    final tickets = _supportTickets
        .where((ticket) => !_isResolvedTicket(ticket))
        .where(_matchesSupportQuery)
        .toList();
    return Scrollbar(
      thumbVisibility: true,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _supportSearchField(),
          const SizedBox(height: 12),
          _sectionTitle('Chats de usuarios'),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Fila de atendimento',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pesquise por nome, telefone ou ID. Ao abrir, o agente ve todos os chats pendentes com identificacao do usuario.',
                    style: TextStyle(color: AppColors.neutralGray),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => context.push('/support/support_agent'),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Abrir fila pesquisavel'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (tickets.isEmpty)
            _emptyCard('Sem chats de usuarios pendentes.')
          else
            ...tickets.map(_supportTicketCard),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _supportOrdersTab() {
    final orders = _supportOrders.where(_matchesSupportQuery).toList();
    final restaurants = _supportRestaurants
        .where(_matchesSupportQuery)
        .toList();
    final couriers = _supportCouriers.where(_matchesSupportQuery).toList();
    final clients = _supportClients.where(_matchesSupportQuery).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _supportSearchField(),
        const SizedBox(height: 12),
        _sectionTitle('Pedidos'),
        if (orders.isEmpty)
          _emptyCard('Sem pedidos encontrados.')
        else
          ...orders.take(20).map(_supportOrderCard),
        const SizedBox(height: 12),
        _sectionTitle('Restaurantes'),
        if (restaurants.isEmpty)
          _emptyCard('Sem restaurantes encontrados.')
        else
          ...restaurants.take(12).map(_supportEntityCard),
        const SizedBox(height: 12),
        _sectionTitle('Estafetas'),
        if (couriers.isEmpty)
          _emptyCard('Sem estafetas encontrados.')
        else
          ...couriers.take(12).map(_supportEntityCard),
        const SizedBox(height: 12),
        _sectionTitle('Clientes'),
        if (clients.isEmpty)
          _emptyCard('Sem clientes encontrados.')
        else
          ...clients.take(12).map(_supportEntityCard),
      ],
    );
  }

  Widget _supportProblemOrdersTab() {
    final orders = _supportOrders
        .where(_matchesSupportQuery)
        .where(_isSupportProblemOrder)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _supportSearchField(),
        const SizedBox(height: 12),
        _sectionTitle('Pedidos com problemas'),
        _supportPermissionBanner(
          icon: Icons.support_agent_outlined,
          title: 'Support Ops',
          body:
              'Pode resolver tickets, investigar pedidos, analisar pagamentos e escalar casos criticos. Dinheiro e alteracoes sensiveis ficam sempre auditados.',
        ),
        const SizedBox(height: 12),
        if (orders.isEmpty)
          _emptyCard('Sem pedidos problematicos encontrados.')
        else
          ...orders.map(_supportProblemOrderCard),
      ],
    );
  }

  Widget _supportWalletTab() {
    final payments = _supportOrders
        .where(_matchesSupportQuery)
        .where((order) => _isPaymentIssue(order))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _supportSearchField(),
        const SizedBox(height: 12),
        _sectionTitle('Pagamentos / Wallet'),
        _supportPermissionBanner(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Camada financeira',
          body:
              'O suporte pode investigar, registar pedido de reembolso e escalar para admin. Aprovacao financeira final fica protegida por auditoria.',
        ),
        const SizedBox(height: 12),
        if (payments.isEmpty)
          _emptyCard('Sem pagamentos pendentes ou falhados.')
        else
          ...payments.map(_supportPaymentCard),
      ],
    );
  }

  Widget _supportDisputesTab() {
    final disputes = _supportTickets
        .where(_matchesSupportQuery)
        .where((ticket) {
          final type = ticket['dispute_type']?.toString().toLowerCase() ?? '';
          final source = ticket['external_source']?.toString().toLowerCase() ?? '';
          return source.contains('dispute') ||
              type.contains('dispute') ||
              type.contains('refund') ||
              type.contains('reembolso') ||
              type.contains('delivery') ||
              type.contains('payment');
        })
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _supportSearchField(),
        const SizedBox(height: 12),
        _sectionTitle('Disputas / Reembolsos'),
        if (disputes.isEmpty)
          _emptyCard('Sem disputas encontradas.')
        else
          ...disputes.map(_supportTicketCard),
      ],
    );
  }

  Widget _supportUsersTab() {
    final restaurants = _supportRestaurants
        .where(_matchesSupportQuery)
        .toList();
    final couriers = _supportCouriers.where(_matchesSupportQuery).toList();
    final clients = _supportClients.where(_matchesSupportQuery).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _supportSearchField(),
        const SizedBox(height: 12),
        _sectionTitle('Restaurantes em suporte'),
        if (restaurants.isEmpty)
          _emptyCard('Sem restaurantes encontrados.')
        else
          ...restaurants.take(20).map(_supportEntityCard),
        const SizedBox(height: 12),
        _sectionTitle('Estafetas em suporte'),
        if (couriers.isEmpty)
          _emptyCard('Sem estafetas encontrados.')
        else
          ...couriers.take(20).map(_supportEntityCard),
        const SizedBox(height: 12),
        _sectionTitle('Clientes'),
        if (clients.isEmpty)
          _emptyCard('Sem clientes encontrados.')
        else
          ...clients.take(20).map(_supportEntityCard),
      ],
    );
  }

  Widget _supportLogsTab() {
    final logs = _supportActionsToday.where(_matchesSupportQuery).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _supportSearchField(),
        const SizedBox(height: 12),
        _sectionTitle('Logs do sistema'),
        FilledButton.icon(
          onPressed: () =>
              _showSupportActivityDialog('support_complaint_registered'),
          icon: const Icon(Icons.add_comment_outlined),
          label: const Text('Registrar reclamacao'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () =>
              _showSupportActivityDialog('support_technical_issue_registered'),
          icon: const Icon(Icons.bug_report_outlined),
          label: const Text('Registrar problema tecnico'),
        ),
        const SizedBox(height: 12),
        if (logs.isEmpty)
          _emptyCard('Sem logs de suporte hoje.')
        else
          ...logs.map(_auditCard),
      ],
    );
  }

  Widget _supportPermissionBanner({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Card(
      elevation: 0,
      color: AppColors.primaryRed.withValues(alpha: 0.06),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryRed),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(body),
      ),
    );
  }

  bool _isSupportProblemOrder(Map<String, dynamic> order) {
    final status = order['status']?.toString().toLowerCase() ?? '';
    return _isPaymentIssue(order) ||
        status.contains('cancel') ||
        status.contains('failed') ||
        status.contains('rejected') ||
        status.contains('dispute') ||
        status.contains('otp') ||
        status == 'pending';
  }

  bool _isPaymentIssue(Map<String, dynamic> order) {
    final payment = order['payment_status']?.toString().toLowerCase() ?? '';
    return payment == 'pending' ||
        payment == 'failed' ||
        payment == 'declined' ||
        payment == 'cancelled' ||
        payment == 'canceled';
  }

  Widget _supportProblemOrderCard(Map<String, dynamic> order) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _supportOrderTile(order),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      _showSupportOrderDetails(order, focus: 'pedido'),
                  icon: const Icon(Icons.manage_search_outlined),
                  label: const Text('Abrir detalhes'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showSupportDecisionDialog(
                    'support_restaurant_contact_requested',
                    'Contactar restaurante',
                    order,
                  ),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Contactar restaurante'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showSupportDecisionDialog(
                    'support_investigation_opened',
                    'Abrir investigacao',
                    order,
                  ),
                  icon: const Icon(Icons.policy_outlined),
                  label: const Text('Abrir investigacao'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _supportPaymentCard(Map<String, dynamic> order) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _supportOrderTile(order),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      _showSupportOrderDetails(order, focus: 'wallet'),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Ver pagamento'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showSupportDecisionDialog(
                    'support_refund_requested',
                    'Registar pedido de reembolso',
                    order,
                  ),
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('Pedir reembolso'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showSupportDecisionDialog(
                    'support_case_forwarded',
                    'Escalar para admin',
                    order,
                  ),
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: const Text('Escalar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _supportOrderTile(Map<String, dynamic> order) {
    final id = order['id']?.toString() ?? '';
    final status = order['status']?.toString() ?? '-';
    final payment = order['payment_status']?.toString() ?? '-';
    final amount = order['total_amount']?.toString() ?? '-';
    final address = order['delivery_address']?.toString() ?? '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(id.isEmpty ? 'Pedido' : 'Pedido ${id.substring(0, 8)}'),
      subtitle: Text(
        'Estado: $status - Pagamento: $payment\n'
        'Total: $amount MZN\n$address',
      ),
      isThreeLine: true,
    );
  }

  Widget _supportOrderCard(Map<String, dynamic> order) {
    return Card(
      elevation: 0,
      child: _supportOrderTile(order),
    );
  }

  Widget _supportEntityCard(Map<String, dynamic> item) {
    final name =
        item['name']?.toString() ?? item['full_name']?.toString() ?? 'Sem nome';
    final phone = item['phone']?.toString() ?? 'Sem telefone';
    final status = item['is_open'] != null
        ? (item['is_open'] == true ? 'Aberto' : 'Fechado')
        : item['is_online'] != null
        ? (item['is_online'] == true ? 'Online' : 'Offline')
        : item['is_blocked'] == true
        ? 'Bloqueado'
        : 'Ativo';
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.person_search_outlined),
        title: Text(name),
        subtitle: Text('$phone - $status'),
      ),
    );
  }

  Widget _supportProfileTab() {
    final profile = _staffProfile ?? const <String, dynamic>{};
    final active = profile['staff_active'] != false;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Perfil'),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _profileRow('Nome', profile['full_name']?.toString() ?? '-'),
                _profileRow('Telefone', profile['phone']?.toString() ?? '-'),
                _profileRow('Cargo', 'Agente de Suporte'),
                _profileRow('Estado', active ? 'Ativo' : 'Inativo'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _operationalDiagnosticsCard(),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: const Text('Sair'),
        ),
      ],
    );
  }

  Widget _supportSearchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        labelText: 'Pesquisar',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
      ),
      onChanged: (value) => setState(() => _query = value.trim()),
    );
  }

  bool _matchesSupportQuery(Map<String, dynamic> row) {
    if (_query.trim().isEmpty) return true;
    final needle = _query.trim().toLowerCase();
    return row.values
        .map((value) => value?.toString().toLowerCase() ?? '')
        .join(' ')
        .contains(needle);
  }

  bool _isResolvedTicket(Map<String, dynamic> ticket) {
    final status = ticket['status']?.toString().toLowerCase() ?? '';
    return status == 'resolved' || status == 'closed' || status == 'completed';
  }

  bool _isComplaintAction(dynamic rawAction) {
    final action = rawAction?.toString() ?? '';
    return action == 'support_complaint_registered' ||
        action == 'support_technical_issue_registered';
  }

  bool _isToday(dynamic rawDate) {
    final parsed = DateTime.tryParse(rawDate?.toString() ?? '');
    if (parsed == null) return false;
    final local = parsed.toLocal();
    final now = DateTime.now();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  bool _containsAny(dynamic raw, List<String> needles) {
    final value = raw?.toString().toLowerCase() ?? '';
    return needles.any((needle) => value.contains(needle));
  }

  String _supportTypeLabel(String type) {
    final normalized = type.replaceAll('_', ' ');
    if (normalized.contains('support chat')) return 'Chat de suporte';
    if (normalized.contains('support call')) return 'Chamada de suporte';
    if (normalized.contains('technical')) return 'Problema tecnico';
    if (normalized.contains('delivery')) return 'Reclamacao de entrega';
    if (normalized.contains('restaurant')) return 'Reclamacao de restaurante';
    return normalized.isEmpty ? 'Ticket' : normalized;
  }

  String _supportStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return 'Pendente';
      case 'in_progress':
        return 'Em atendimento';
      case 'resolved':
      case 'closed':
      case 'completed':
        return 'Resolvido';
      default:
        return status;
    }
  }

  Future<void> _showSupportActivityDialog(String action) async {
    final controller = TextEditingController();
    final isTechnical = action.contains('technical');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isTechnical ? 'Problema tecnico' : 'Reclamacao'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: isTechnical
                ? 'Descricao do problema'
                : 'Descricao da reclamacao',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    final note = controller.text.trim();
    controller.dispose();
    if (confirmed != true || note.isEmpty) return;

    await _service.addSupportActivity(
      action: action,
      reason: note,
      metadata: {'category': isTechnical ? 'technical' : 'complaint'},
    );
    _showSnack(
      isTechnical ? 'Problema tecnico registrado.' : 'Reclamacao registrada.',
    );
    await _load();
  }

  Future<void> _showSupportForwardDialog(Map<String, dynamic> ticket) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encaminhar caso'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Nota para gestor'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Encaminhar'),
          ),
        ],
      ),
    );
    final note = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;

    await _service.addSupportActivity(
      action: 'support_case_forwarded',
      reason: note.isEmpty ? 'Caso encaminhado para gestor.' : note,
      metadata: {
        'ticket_id': ticket['id']?.toString(),
        'order_id': ticket['order_id']?.toString(),
        'external_source': ticket['external_source']?.toString(),
        'external_id': ticket['external_id']?.toString(),
        'ticket_status': ticket['status']?.toString(),
      },
    );
    _showSnack('Caso encaminhado para gestores.');
    await _load();
  }

  Future<void> _showSupportDecisionDialog(
    String action,
    String title,
    Map<String, dynamic> subject,
  ) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Nota operacional',
            hintText: 'Explique a decisao para auditoria.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Registar'),
          ),
        ],
      ),
    );
    final note = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;

    await _service.addSupportActivity(
      action: action,
      reason: note.isEmpty ? title : note,
      metadata: {
        'subject_id': subject['id']?.toString(),
        'order_id': subject['order_id']?.toString() ?? subject['id']?.toString(),
        'status': subject['status']?.toString(),
        'source': 'support_ops',
      },
    );
    _showSnack('$title registado.');
    await _load();
  }

  Future<void> _showSupportOrderDetails(
    Map<String, dynamic> order, {
    required String focus,
  }) async {
    final id = order['id']?.toString() ?? '';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(id.isEmpty ? 'Pedido' : 'Pedido #${id.substring(0, 8)}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _profileRow('Foco', focus),
              _profileRow('Estado', order['status']?.toString() ?? '-'),
              _profileRow(
                'Pagamento',
                order['payment_status']?.toString() ?? '-',
              ),
              _profileRow(
                'Total',
                '${order['total_amount']?.toString() ?? '-'} MZN',
              ),
              _profileRow('Cliente', order['client_id']?.toString() ?? '-'),
              _profileRow(
                'Restaurante',
                order['restaurant_id']?.toString() ?? '-',
              ),
              _profileRow('Estafeta', order['courier_id']?.toString() ?? '-'),
              _profileRow(
                'Endereco',
                order['delivery_address']?.toString() ?? '-',
              ),
              _profileRow(
                'Criado',
                _dateLabel(order['created_at']?.toString()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _showSupportDecisionDialog(
                'support_case_forwarded',
                'Escalar para admin',
                order,
              );
            },
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Escalar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSupportTicketDetails(Map<String, dynamic> ticket) async {
    final id = ticket['id']?.toString() ?? '';
    final code = id.length >= 8 ? id.substring(0, 8) : id;
    final source = ticket['external_source']?.toString() ?? '';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ticket #$code'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _profileRow('Nome', _ticketCustomerName(ticket)),
              _profileRow('Telefone', _ticketCustomerPhone(ticket)),
              _profileRow(
                'Estado',
                _supportStatusLabel(ticket['status']?.toString() ?? 'open'),
              ),
              _profileRow(
                'Tipo',
                _supportTypeLabel(ticket['dispute_type']?.toString() ?? ''),
              ),
              _profileRow('Origem', source.isEmpty ? 'DeliGo' : source),
              _profileRow(
                'Atualizado',
                _dateLabel(
                  ticket['updated_at']?.toString() ??
                      ticket['created_at']?.toString(),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Detalhe',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(ticket['reason']?.toString() ?? 'Sem detalhe'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _showSupportForwardDialog(ticket);
            },
            icon: const Icon(Icons.send_outlined),
            label: const Text('Encaminhar'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _showSupportDecisionDialog(
                'support_investigation_opened',
                'Abrir investigacao',
                ticket,
              );
            },
            icon: const Icon(Icons.policy_outlined),
            label: const Text('Investigar'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    AuthRefreshNotifier.markIntentionalSignOut();
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  Widget _header() {
    final name = _staffProfile?['full_name']?.toString() ?? 'Colaborador';
    final role = _roleLabel(_staffProfile?['role']?.toString() ?? '');
    final active = _staffProfile?['staff_active'] != false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.verified_user,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      role,
                      style: const TextStyle(color: AppColors.neutralGray),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(active ? 'Ativo' : 'Inativo'),
                avatar: Icon(
                  active ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18,
                ),
              ),
              if (_isAmbassador)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Chip(
                    label: Text('Leitura'),
                    avatar: Icon(Icons.visibility_outlined, size: 18),
                  ),
                ),
              if (_isAdmin)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: FilledButton.icon(
                    onPressed: () => context.push('/support/support_agent'),
                    icon: const Icon(Icons.support_agent, size: 18),
                    label: const Text('Chat'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsGrid() {
    final stats = [
      _Stat(Icons.pending_actions, 'Cadastros pendentes', _waitingReview),
      _Stat(Icons.check_circle_outline, 'Aprovados hoje', _approvedToday),
      _Stat(Icons.cancel_outlined, 'Rejeitados hoje', _rejectedToday),
      _Stat(Icons.hourglass_top, 'Aguardando Revisao', _waitingReview),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: stats.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isWide ? 4 : 2,
              mainAxisExtent: 118,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (context, index) {
              final stat = stats[index];
              return Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(stat.icon, color: AppColors.primaryGreen),
                      const Spacer(),
                      Text(
                        stat.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        stat.value.toString(),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Pesquisar por nome, telefone, NUIT, matricula ou ID',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                        _load();
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            onSubmitted: (value) {
              setState(() => _query = value);
              _load();
            },
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _menuFilter(
                  value: _statusFilter,
                  icon: Icons.verified_outlined,
                  items: const {
                    'pending': 'Pendentes',
                    'approved': 'Aprovados',
                    'rejected': 'Rejeitados',
                    'all': 'Todos',
                  },
                  onChanged: (value) {
                    setState(() => _statusFilter = value);
                    _load();
                  },
                ),
                _menuFilter(
                  value: _roleFilter,
                  icon: Icons.badge_outlined,
                  items: const {
                    'all': 'Todos',
                    'restaurant': 'Restaurantes',
                    'courier': 'Estafetas',
                  },
                  onChanged: (value) {
                    setState(() => _roleFilter = value);
                    _load();
                  },
                ),
                _menuFilter(
                  value: _cityFilter,
                  icon: Icons.location_city_outlined,
                  items: {for (final city in _cities) city: _cityLabel(city)},
                  onChanged: (value) {
                    setState(() => _cityFilter = value);
                    _load();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuFilter({
    required String value,
    required IconData icon,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        initialValue: value,
        onSelected: onChanged,
        itemBuilder: (context) => items.entries
            .map(
              (entry) =>
                  PopupMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        child: Chip(
          avatar: Icon(icon, size: 18),
          label: Text(items[value] ?? value),
        ),
      ),
    );
  }

  Widget _fieldMapTab() {
    final restaurants = _cases
        .where((profile) => profile['role']?.toString() == 'restaurant')
        .toList();
    final couriers = _cases
        .where((profile) => profile['role']?.toString() == 'courier')
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _sectionTitle('Mapa ao vivo'),
        _fieldOpsBanner(
          Icons.map_outlined,
          'Operacao fisica',
          'Restaurantes, estafetas e KYC pendentes organizados por cidade para acao em campo.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(Icons.storefront, size: 18),
              label: Text('Restaurantes: ${restaurants.length}'),
            ),
            Chip(
              avatar: const Icon(Icons.two_wheeler, size: 18),
              label: Text('Estafetas: ${couriers.length}'),
            ),
            Chip(
              avatar: const Icon(Icons.location_city_outlined, size: 18),
              label: Text('Cidade: ${_cityFilter == 'all' ? 'Todas' : _cityFilter}'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionTitle('Tarefas proximas'),
        if (_cases.isEmpty)
          _emptyCard('Nenhuma tarefa de campo encontrada.')
        else
          ..._cases.take(8).map(_fieldTaskCard),
      ],
    );
  }

  Widget _fieldTasksTab() {
    final rejected = _cases
        .where((profile) => profile['kyc_status']?.toString() == 'rejected')
        .toList();
    final pending = _cases
        .where((profile) => profile['kyc_status']?.toString() != 'rejected')
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _sectionTitle('Tarefas atribuídas'),
        _fieldOpsBanner(
          Icons.assignment_outlined,
          'Prioridade de campo',
          'KYC rejeitado, restaurante novo e estafeta suspeito entram aqui para verificacao fisica.',
        ),
        const SizedBox(height: 12),
        _sectionTitle('Prioridade alta'),
        if (rejected.isEmpty)
          _emptyCard('Sem KYC rejeitado para visita.')
        else
          ...rejected.map(_fieldTaskCard),
        const SizedBox(height: 12),
        _sectionTitle('Pendentes'),
        if (pending.isEmpty)
          _emptyCard('Sem tarefas pendentes.')
        else
          ...pending.take(20).map(_fieldTaskCard),
      ],
    );
  }

  Widget _kycTab() => _dashboardTab();

  Widget _restaurantsTab() {
    final restaurants = _cases
        .where((profile) => profile['role']?.toString() == 'restaurant')
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _sectionTitle('Restaurantes'),
        if (restaurants.isEmpty)
          _emptyCard('Nenhum restaurante nesta lista.')
        else
          ...restaurants.map(_caseCard),
      ],
    );
  }

  Widget _couriersTab() {
    final couriers = _cases
        .where((profile) => profile['role']?.toString() == 'courier')
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _sectionTitle('Estafetas'),
        if (couriers.isEmpty)
          _emptyCard('Nenhum estafeta nesta lista.')
        else
          ...couriers.map(_caseCard),
      ],
    );
  }

  Widget _fieldOpsBanner(IconData icon, String title, String body) {
    return Card(
      elevation: 0,
      color: AppColors.primaryGreen.withValues(alpha: 0.06),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryGreen),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(body),
      ),
    );
  }

  Widget _fieldTaskCard(Map<String, dynamic> profile) {
    final role = profile['role']?.toString() ?? '';
    final status = profile['kyc_status']?.toString() ?? 'pending';
    final task = role == 'restaurant'
        ? 'Verificar restaurante'
        : 'Validar estafeta';
    return Card(
      elevation: 0,
      child: ListTile(
        onTap: () => _openCase(profile),
        leading: CircleAvatar(
          backgroundColor: _statusColor(status).withValues(alpha: 0.12),
          child: Icon(_roleIcon(role), color: _statusColor(status)),
        ),
        title: Text(task),
        subtitle: Text(
          '${profile['full_name'] ?? 'Sem nome'}\n'
          '${profile['phone'] ?? 'Sem telefone'} - '
          '${profile['city'] ?? 'Cidade nao informada'}',
        ),
        isThreeLine: true,
        trailing: Chip(label: Text(_statusLabel(status))),
      ),
    );
  }

  Widget _dashboardTab() {
    final history = _auditTrail.where(_isFieldKycAction).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _sectionTitle('Cadastros pendentes'),
        _miniStatsRow(),
        const SizedBox(height: 12),
        _sectionTitle('Fila de verificacao'),
        if (_cases.isEmpty)
          _emptyCard('Nenhum cadastro encontrado para estes filtros.')
        else
          ..._cases.take(5).map(_caseCard),
        if (_isAdmin) ...[
          const SizedBox(height: 12),
          _sectionTitle('Agentes e notificacoes'),
          _adminStaffOpsSummary(),
          const SizedBox(height: 8),
          if (_staffOperationalStatus.isEmpty)
            _emptyCard('Nenhum agente encontrado.')
          else
            ..._staffOperationalStatus.take(8).map(_staffOpsCard),
        ],
        const SizedBox(height: 12),
        _sectionTitle('Historico recente'),
        if (history.isEmpty)
          _emptyCard('Nenhuma acao registada ainda.')
        else
          ...history.take(6).map(_auditCard),
      ],
    );
  }

  Widget _adminStaffOpsSummary() {
    final activeStaff = _staffOperationalStatus
        .where((row) => row['staff_active'] != false)
        .length;
    final activePush = _staffOperationalStatus
        .where((row) => row['push_token_active'] == true)
        .length;
    final withoutPush = _staffOperationalStatus.length - activePush;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.groups_outlined, size: 18),
          label: Text('Agentes: ${_staffOperationalStatus.length}'),
        ),
        Chip(
          avatar: const Icon(Icons.verified_user_outlined, size: 18),
          label: Text('Ativos: $activeStaff'),
        ),
        Chip(
          avatar: const Icon(Icons.notifications_active_outlined, size: 18),
          label: Text('Push ativo: $activePush'),
        ),
        Chip(
          avatar: Icon(
            Icons.notification_important_outlined,
            size: 18,
            color: withoutPush > 0 ? AppColors.primaryRed : null,
          ),
          label: Text('Sem push: $withoutPush'),
        ),
      ],
    );
  }

  Widget _staffOpsCard(Map<String, dynamic> staff) {
    final name = staff['full_name']?.toString().trim() ?? '';
    final phone = staff['phone']?.toString().trim() ?? '';
    final role = staff['role']?.toString() ?? '';
    final active = staff['staff_active'] != false;
    final pushActive = staff['push_token_active'] == true;
    final platform = staff['push_platform']?.toString().trim() ?? '';
    final lastPush = staff['push_last_seen_at']?.toString();
    final lastProfile = staff['updated_at']?.toString();
    return Card(
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: pushActive
              ? const Color(0xFFE8F5EE)
              : AppColors.primaryRed.withValues(alpha: 0.12),
          child: Icon(
            pushActive
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            color: pushActive ? const Color(0xFF0B8F6A) : AppColors.primaryRed,
          ),
        ),
        title: Text(
          name.isEmpty ? 'Agente sem nome' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_roleLabel(role)} - ${active ? 'Ativo' : 'Inativo'}\n'
          '${phone.isEmpty ? 'Sem telefone' : phone} - '
          'Push: ${pushActive ? 'ativo' : 'sem sinal'}'
          '${platform.isEmpty ? '' : ' ($platform)'}\n'
          'Ultimo push: ${_dateLabel(lastPush)} - Perfil: ${_dateLabel(lastProfile)}',
        ),
        isThreeLine: true,
      ),
    );
  }

  // ignore: unused_element
  Widget _casesTab() {
    final restaurants = _cases
        .where((profile) => profile['role']?.toString() == 'restaurant')
        .toList();
    final couriers = _cases
        .where((profile) => profile['role']?.toString() == 'courier')
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _sectionTitle('Restaurantes'),
        if (restaurants.isEmpty)
          _emptyCard('Nenhum restaurante nesta lista.')
        else
          ...restaurants.map(_caseCard),
        const SizedBox(height: 12),
        _sectionTitle('Estafetas'),
        if (couriers.isEmpty)
          _emptyCard('Nenhum estafeta nesta lista.')
        else
          ...couriers.map(_caseCard),
      ],
    );
  }

  Widget _historyTab() {
    final history = _auditTrail.where(_isFieldKycAction).toList();
    final approved = history.where(_isApprovedAction).toList();
    final rejected = history.where(_isRejectedAction).toList();
    final corrected = history.where(_isCorrectionAction).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _sectionTitle('Cadastros aprovados'),
        if (approved.isEmpty)
          _emptyCard('Nenhum cadastro aprovado no historico recente.')
        else
          ...approved.map(_auditCard),
        const SizedBox(height: 12),
        _sectionTitle('Cadastros rejeitados'),
        if (rejected.isEmpty)
          _emptyCard('Nenhum cadastro rejeitado no historico recente.')
        else
          ...rejected.map(_auditCard),
        const SizedBox(height: 12),
        _sectionTitle('Cadastros corrigidos'),
        if (corrected.isEmpty)
          _emptyCard('Nenhuma correcao solicitada no historico recente.')
        else
          ...corrected.map(_auditCard),
      ],
    );
  }

  Widget _miniStatsRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.storefront, size: 18),
          label: Text('Restaurantes: $_pendingRestaurants'),
        ),
        Chip(
          avatar: const Icon(Icons.two_wheeler, size: 18),
          label: Text('Estafetas: $_pendingCouriers'),
        ),
      ],
    );
  }

  Widget _profileTab() {
    final profile = _staffProfile ?? const <String, dynamic>{};
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _profileRow('Nome', profile['full_name']?.toString() ?? '-'),
                _profileRow('Telefone', profile['phone']?.toString() ?? '-'),
                _profileRow(
                  'Cargo',
                  _roleLabel(profile['role']?.toString() ?? ''),
                ),
                _profileRow('Cidade', profile['city']?.toString() ?? '-'),
                _profileRow(
                  'Criado em',
                  _dateLabel(profile['created_at']?.toString()),
                ),
                _profileRow(
                  'Ultimo acesso',
                  _dateLabel(profile['updated_at']?.toString()),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _operationalDiagnosticsCard(),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.push('/reset-password'),
          icon: const Icon(Icons.lock_reset),
          label: const Text('Alterar senha'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: const Text('Terminar sessao'),
        ),
      ],
    );
  }

  Widget _caseCard(Map<String, dynamic> profile) {
    final status = profile['kyc_status']?.toString() ?? 'pending';
    final role = profile['role']?.toString() ?? '';
    final name = profile['full_name']?.toString() ?? 'Sem nome';
    final phone = profile['phone']?.toString() ?? 'Sem telefone';
    final city = profile['city']?.toString() ?? 'Cidade nao informada';
    return Card(
      elevation: 0,
      child: ListTile(
        onTap: () => _openCase(profile),
        leading: CircleAvatar(
          backgroundColor: _statusColor(status).withValues(alpha: 0.12),
          child: Icon(_roleIcon(role), color: _statusColor(status)),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('$phone\n${_roleSubjectLabel(role)} - $city'),
        isThreeLine: true,
        trailing: Chip(label: Text(_statusLabel(status))),
      ),
    );
  }

  Future<void> _openCase(Map<String, dynamic> profile) async {
    final checklist = {for (final key in _checklistLabels.keys) key: false};
    final notesFuture = _service.fetchInternalNotes(profile['id'].toString());
    final auditFuture = _service.fetchAuditTrail(
      entityId: profile['id'].toString(),
    );
    final docsFuture = _service.fetchKycDocuments(
      userId: profile['id'].toString(),
      subjectType: profile['role'].toString(),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final allChecked = checklist.values.every((value) => value);
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.92,
              minChildSize: 0.55,
              maxChildSize: 0.96,
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _caseHeader(profile),
                    _detailBlock(profile),
                    const SizedBox(height: 12),
                    _sectionTitle('Fotografias e documentos'),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: docsFuture,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final docs = snapshot.data!;
                        if (docs.isEmpty) {
                          return _emptyCard('Nenhum documento enviado.');
                        }
                        return Column(
                          children: docs.map(_documentTile).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _sectionTitle('Checklist de aprovacao'),
                    Card(
                      elevation: 0,
                      child: Column(
                        children: _checklistLabels.entries.map((entry) {
                          return CheckboxListTile(
                            value: checklist[entry.key],
                            onChanged: _canVerify
                                ? (value) => setSheetState(
                                    () => checklist[entry.key] = value ?? false,
                                  )
                                : null,
                            title: Text(entry.value),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sectionTitle('Notas internas'),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: notesFuture,
                      builder: (context, snapshot) {
                        final notes =
                            snapshot.data ?? const <Map<String, dynamic>>[];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _showAddNoteDialog(profile),
                              icon: const Icon(Icons.note_add_outlined),
                              label: const Text('Adicionar nota'),
                            ),
                            if (notes.isEmpty)
                              _emptyCard('Sem notas internas.')
                            else
                              ...notes.map(
                                (note) => ListTile(
                                  leading: const Icon(
                                    Icons.sticky_note_2_outlined,
                                  ),
                                  title: Text(note['note']?.toString() ?? ''),
                                  subtitle: Text(
                                    _dateLabel(note['created_at']?.toString()),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _sectionTitle('Historico do cadastro'),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: auditFuture,
                      builder: (context, snapshot) {
                        final items =
                            snapshot.data ?? const <Map<String, dynamic>>[];
                        if (items.isEmpty) {
                          return _emptyCard('Sem historico ainda.');
                        }
                        return Column(children: items.map(_auditCard).toList());
                      },
                    ),
                    const SizedBox(height: 16),
                    _caseActions(profile, allChecked, checklist),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _caseHeader(Map<String, dynamic> profile) {
    final role = profile['role']?.toString() ?? '';
    return Row(
      children: [
        CircleAvatar(radius: 24, child: Icon(_roleIcon(role))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile['full_name']?.toString() ?? 'Sem nome',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(_roleSubjectLabel(role)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Fechar',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }

  Widget _detailBlock(Map<String, dynamic> profile) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _profileRow('Telefone', profile['phone']?.toString() ?? '-'),
            _profileRow('Cidade', profile['city']?.toString() ?? '-'),
            _profileRow('Endereco', profile['address']?.toString() ?? '-'),
            _profileRow(
              'Status',
              _statusLabel(profile['kyc_status']?.toString() ?? 'pending'),
            ),
            _profileRow(
              'Submetido',
              _dateLabel(profile['approval_submitted_at']?.toString()),
            ),
            if (profile['kyc_rejection_reason']?.toString().trim().isNotEmpty ==
                true)
              _profileRow(
                'Motivo anterior',
                profile['kyc_rejection_reason'].toString(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _documentTile(Map<String, dynamic> document) {
    final label = _docLabel(document['label']?.toString() ?? 'Documento');
    final pathProbe =
        '${document['path'] ?? ''} ${document['url'] ?? ''} ${document['content_type'] ?? ''}'
            .toLowerCase();
    final isImage =
        pathProbe.contains('image/') ||
        pathProbe.contains('.jpg') ||
        pathProbe.contains('.jpeg') ||
        pathProbe.contains('.png') ||
        pathProbe.contains('.webp');
    return Card(
      elevation: 0,
      child: ListTile(
        leading: Icon(
          isImage ? Icons.image_outlined : Icons.description_outlined,
        ),
        title: Text(label),
        subtitle: Text(
          isImage ? 'Foto enviada no cadastro' : 'Documento enviado',
        ),
        trailing: const Icon(Icons.open_in_new),
        onTap: () => _openDocument(document, label),
      ),
    );
  }

  Widget _caseActions(
    Map<String, dynamic> profile,
    bool allChecked,
    Map<String, bool> checklist,
  ) {
    final status = profile['kyc_status']?.toString() ?? 'pending';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed:
              _processing || !_canVerify || status == 'approved' || !allChecked
              ? null
              : () => _decide(profile, 'approve', checklist: checklist),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Aprovar'),
        ),
        FilledButton.tonalIcon(
          onPressed: _processing || !_canVerify || status == 'approved'
              ? null
              : () => _showRejectDialog(profile, checklist),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Rejeitar'),
        ),
        OutlinedButton.icon(
          onPressed: _processing || !_canVerify || status == 'approved'
              ? null
              : () => _showCorrectionDialog(profile, checklist),
          icon: const Icon(Icons.edit_note),
          label: const Text('Solicitar correcao'),
        ),
      ],
    );
  }

  Future<void> _openDocument(
    Map<String, dynamic> document,
    String label,
  ) async {
    try {
      final url = await _service.resolveDocumentUrl(document);
      if (url.isEmpty) {
        _showSnack('Documento indisponivel.');
        return;
      }
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => AdminDocumentViewerPage(
            title: label,
            url: url,
            storagePath: document['path']?.toString(),
            contentType: document['content_type']?.toString(),
          ),
        ),
      );
    } catch (error) {
      _showSnack('Nao foi possivel abrir o documento: $error');
    }
  }

  Future<void> _decide(
    Map<String, dynamic> profile,
    String decision, {
    String? reason,
    required Map<String, bool> checklist,
    String? successMessage,
  }) async {
    setState(() => _processing = true);
    try {
      await _service.decideKyc(
        profile: profile,
        decision: decision,
        reason: reason,
        checklist: checklist,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack(
        successMessage ??
            (decision == 'approve'
                ? 'Cadastro aprovado.'
                : 'Cadastro rejeitado.'),
      );
      await _load();
    } catch (error) {
      _showSnack('Falha ao processar decisao: $error');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _showRejectDialog(
    Map<String, dynamic> profile,
    Map<String, bool> checklist,
  ) async {
    final controller = TextEditingController();
    String selectedReason = _rejectReasons.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Rejeitar cadastro'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  items: _rejectReasons
                      .map(
                        (reason) => DropdownMenuItem(
                          value: reason,
                          child: Text(reason),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(
                    () => selectedReason = value ?? _rejectReasons.first,
                  ),
                  decoration: const InputDecoration(labelText: 'Motivo rapido'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Comentario obrigatorio',
                    hintText: 'Explique o que precisa ser corrigido.',
                  ),
                ),
              ],
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
      ),
    );
    final comment = controller.text.trim();
    controller.dispose();
    if (confirmed == true && comment.isNotEmpty) {
      await _decide(
        profile,
        'reject',
        reason: '$selectedReason: $comment',
        checklist: checklist,
      );
    } else if (confirmed == true) {
      _showSnack('Informe um comentario para rejeitar.');
    }
  }

  Future<void> _showCorrectionDialog(
    Map<String, dynamic> profile,
    Map<String, bool> checklist,
  ) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Solicitar correcao'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'O que deve ser corrigido?',
            hintText: 'Ex.: reenviar NUIT legivel, confirmar telefone...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Solicitar'),
          ),
        ],
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;
    if (reason.isEmpty) {
      _showSnack('Informe o que precisa ser corrigido.');
      return;
    }
    await _decide(
      profile,
      'pending',
      reason: reason,
      checklist: checklist,
      successMessage: 'Correcao solicitada.',
    );
  }

  Future<void> _showAddNoteDialog(Map<String, dynamic> profile) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nota interna'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Nota',
            hintText: 'Esta nota fica apenas para a equipa DeliGo.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final note = controller.text.trim();
    controller.dispose();
    if (confirmed == true && note.isNotEmpty) {
      await _service.addInternalNote(
        entityId: profile['id'].toString(),
        entityType: profile['role'].toString(),
        note: note,
      );
      _showSnack('Nota guardada.');
    }
  }

  Widget _auditCard(Map<String, dynamic> action) {
    final metadata =
        (action['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
    final role = metadata['role']?.toString() ?? '';
    final reason = action['reason']?.toString() ?? 'Sem motivo';
    return Card(
      elevation: 0,
      child: ListTile(
        leading: const Icon(Icons.history),
        title: Text(_actionLabel(action['action']?.toString() ?? '')),
        subtitle: Text(
          '${_roleSubjectLabel(role)} - $reason\n${_dateLabel(action['created_at']?.toString())}',
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _emptyCard(String text) {
    return Card(
      elevation: 0,
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }

  Widget _noticeCard(String text) {
    return Card(
      elevation: 0,
      color: AppColors.accentYellow.withValues(alpha: 0.14),
      child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
    );
  }

  Widget _operationalDiagnosticsCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<Map<String, String>>(
          future: _operationalDiagnosticsFuture,
          builder: (context, snapshot) {
            final data = snapshot.data ?? const <String, String>{};
            final loading = snapshot.connectionState == ConnectionState.waiting;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.health_and_safety_outlined),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Diagnostico operacional',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Atualizar diagnostico',
                      onPressed: loading
                          ? null
                          : () => _refreshOperationalDiagnostics(),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (snapshot.hasError)
                  Text(
                    'Falha ao verificar: ${snapshot.error}',
                    style: const TextStyle(color: AppColors.primaryRed),
                  )
                else if (loading && data.isEmpty)
                  const LinearProgressIndicator()
                else ...[
                  _diagnosticRow(
                    'Sessao',
                    data['sessao'] ?? '-',
                    ok: data['sessao'] == 'Com login',
                  ),
                  _diagnosticRow(
                    'Permissao Android',
                    data['permissao_android'] ?? '-',
                    ok:
                        data['permissao_android'] == 'authorized' ||
                        data['permissao_android'] == 'provisional',
                  ),
                  _diagnosticRow(
                    'Token FCM',
                    data['token_fcm'] ?? '-',
                    ok: (data['token_fcm'] ?? '').startsWith('...'),
                  ),
                  _diagnosticRow(
                    'Token no banco',
                    data['token_no_banco'] ?? '-',
                    ok: data['token_no_banco'] == 'Ativo',
                  ),
                  _diagnosticRow(
                    'Realtime push',
                    data['realtime_push'] ?? '-',
                    ok: data['realtime_push'] == 'Conectado',
                  ),
                  _diagnosticRow(
                    'Servico push',
                    data['servico_push'] ?? '-',
                    ok: data['servico_push'] == 'Inicializado',
                  ),
                  _profileRow('Plataforma', data['plataforma'] ?? '-'),
                  _profileRow('Ultimo token', _dateLabel(data['ultimo_token'])),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: loading
                              ? null
                              : () => _refreshOperationalDiagnostics(
                                  refreshToken: true,
                                ),
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('Revalidar push'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _diagnosticRow(String label, String value, {required bool ok}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.neutralGray),
            ),
          ),
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            color: ok ? const Color(0xFF0B8F6A) : AppColors.primaryRed,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.neutralGray),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _roleLabel(String role) =>
      FieldVerificationService.roleLabels[role] ?? _roleSubjectLabel(role);

  String _roleSubjectLabel(String role) {
    switch (role) {
      case 'restaurant':
        return 'Restaurante';
      case 'courier':
        return 'Estafeta';
      case 'field_agent':
        return 'Agente';
      case 'support_agent':
        return 'Suporte ao Cliente';
      case 'ambassador':
        return 'Embaixador';
      case 'admin':
        return 'Admin';
      default:
        return role.isEmpty ? 'Utilizador' : role;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'restaurant':
        return Icons.storefront;
      case 'courier':
        return Icons.two_wheeler;
      default:
        return Icons.person;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Aprovado';
      case 'rejected':
        return 'Rejeitado';
      case 'pending':
        return 'Pendente';
      default:
        return status;
    }
  }

  bool _isApprovedAction(Map<String, dynamic> item) {
    return _containsAny(item['action'], ['approved', 'aprovou']);
  }

  bool _isRejectedAction(Map<String, dynamic> item) {
    return _containsAny(item['action'], ['rejected', 'rejeitou']);
  }

  bool _isCorrectionAction(Map<String, dynamic> item) {
    final action = item['action']?.toString().toLowerCase() ?? '';
    final reason = item['reason']?.toString().trim() ?? '';
    return action == 'pending' ||
        action == 'kyc_pending' ||
        action == 'field_requested_correction' ||
        (_containsAny(action, ['pending']) && reason.isNotEmpty);
  }

  bool _isFieldKycAction(Map<String, dynamic> item) {
    return _isApprovedAction(item) ||
        _isRejectedAction(item) ||
        _isCorrectionAction(item);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.primaryGreen;
      case 'rejected':
        return AppColors.primaryRed;
      default:
        return Colors.orange;
    }
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'field_approved_kyc':
      case 'kyc_approved':
      case 'approved':
        return 'Aprovou cadastro';
      case 'field_rejected_kyc':
      case 'kyc_rejected':
      case 'rejected':
        return 'Rejeitou cadastro';
      case 'kyc_pending':
      case 'pending':
      case 'field_requested_correction':
        return 'Solicitou correcao';
      case 'support_complaint_registered':
        return 'Registrou reclamacao';
      case 'support_technical_issue_registered':
        return 'Registrou problema tecnico';
      case 'support_case_forwarded':
        return 'Encaminhou caso';
      default:
        return action.isEmpty ? 'Acao registada' : action;
    }
  }

  String _cityLabel(String city) => city == 'all' ? 'Todas cidades' : city;

  String _docLabel(String label) => _kycLabelOverrides[label] ?? label;

  String _dateLabel(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Stat {
  const _Stat(this.icon, this.label, this.value, {this.filter = 'all'});

  final IconData icon;
  final String label;
  final int value;
  final String filter;
}

class _SupportAction {
  const _SupportAction(this.icon, this.label, this.onPressed);

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}
